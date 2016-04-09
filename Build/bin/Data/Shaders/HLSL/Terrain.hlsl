#include "Uniforms.hlsl"
#include "Samplers.hlsl"
#include "Transform.hlsl"
#include "ScreenPos.hlsl"
#include "Lighting.hlsl"
#include "Fog.hlsl"

uniform float4 cMatDiffColor1;
uniform float4 cMatDiffColor2;
uniform float4 cMatDiffColor3;
uniform float4 cMatSpecColor1;
uniform float4 cMatSpecColor2;
uniform float4 cMatSpecColor3;

#ifndef D3D11

// D3D9 uniforms and samplers
#ifdef COMPILEVS
uniform float2 cDetailTiling;
#else
sampler2D sWeightMap0 : register(s0);
sampler2D sDetailMap1 : register(s1);
sampler2D sDetailMap2 : register(s2);
sampler2D sDetailMap3 : register(s3);
#endif

#else

// D3D11 constant buffers and samplers
cbuffer CustomVS : register(b6)
{
    float2 cDetailTiling;
}
#ifndef COMPILEVS
Texture2D tWeightMap0 : register(t0);
Texture2DArray tDetailMap1 : register(t1);
SamplerState sWeightMap0 : register(s0);
SamplerState sDetailMap1 : register(s1);
#endif

#endif

void VS(float4 iPos : POSITION,
    float3 iNormal : NORMAL,
    float2 iTexCoord : TEXCOORD0,
    #ifdef SKINNED
        float4 iBlendWeights : BLENDWEIGHT,
        int4 iBlendIndices : BLENDINDICES,
    #endif
    #ifdef INSTANCED
        float4x3 iModelInstance : TEXCOORD2,
    #endif
    #if defined(BILLBOARD) || defined(DIRBILLBOARD)
        float2 iSize : TEXCOORD1,
    #endif
    float4 iTangent : TANGENT,
    out float4 oTexCoord : TEXCOORD0,
    out float3 oNormal : TEXCOORD1,
    out float4 oWorldPos : TEXCOORD2,
//    out float2 oDetailTexCoord : TEXCOORD3,
    out float4 oTangent : TEXCOORD13,
    #ifdef PERPIXEL
        #ifdef SHADOW
            out float4 oShadowPos[NUMCASCADES] : TEXCOORD4,
        #endif
        #ifdef SPOTLIGHT
            out float4 oSpotPos : TEXCOORD5,
        #endif
        #ifdef POINTLIGHT
            out float3 oCubeMaskVec : TEXCOORD5,
        #endif
    #else
        out float3 oVertexLight : TEXCOORD4,
        out float4 oScreenPos : TEXCOORD5,
    #endif
    #if defined(D3D11) && defined(CLIPPLANE)
        out float oClip : SV_CLIPDISTANCE0,
    #endif
    out float4 oPos : OUTPOSITION)
{
    float4x3 modelMatrix = iModelMatrix;
    float3 worldPos = GetWorldPos(modelMatrix);
    oPos = GetClipPos(worldPos);
    oNormal = GetWorldNormal(modelMatrix);
    oWorldPos = float4(worldPos, GetDepth(oPos));
    float3 tangent = GetWorldTangent(modelMatrix);
    float3 bitangent = cross(tangent, oNormal) * iTangent.w;
    oTexCoord = float4(GetTexCoord(iTexCoord), 1,1);
    oTangent = float4(tangent, bitangent.z);
//    oDetailTexCoord = cDetailTiling * oTexCoord.xy;

    #if defined(D3D11) && defined(CLIPPLANE)
        oClip = dot(oPos, cClipPlane);
    #endif

    #ifdef PERPIXEL
        // Per-pixel forward lighting
        float4 projWorldPos = float4(worldPos.xyz, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            GetShadowPos(projWorldPos, oShadowPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            oSpotPos = mul(projWorldPos, cLightMatrices[0]);
        #endif

        #ifdef POINTLIGHT
            oCubeMaskVec = mul(worldPos - cLightPos.xyz, (float3x3)cLightMatrices[0]);
        #endif
    #else
        // Ambient & per-vertex lighting
        oVertexLight = GetAmbient(GetZonePos(worldPos));

        #ifdef NUMVERTEXLIGHTS
            for (int i = 0; i < NUMVERTEXLIGHTS; ++i)
                oVertexLight += GetVertexLight(i, worldPos, oNormal) * cVertexLights[i * 3].rgb;
        #endif
        
        oScreenPos = GetScreenPos(oPos);
    #endif
}

void PS(float4 iTexCoord : TEXCOORD0,
    float3 iNormal : TEXCOORD1,
    float4 iWorldPos : TEXCOORD2,
    float4 iTangent : TEXCOORD3,
//    float2 iDetailTexCoord : TEXCOORD3,
    #ifdef PERPIXEL
        #ifdef SHADOW
            float4 iShadowPos[NUMCASCADES] : TEXCOORD4,
        #endif
        #ifdef SPOTLIGHT
            float4 iSpotPos : TEXCOORD5,
        #endif
        #ifdef POINTLIGHT
            float3 iCubeMaskVec : TEXCOORD5,
        #endif
    #else
        float3 iVertexLight : TEXCOORD4,
        float4 iScreenPos : TEXCOORD5,
    #endif
    #if defined(D3D11) && defined(CLIPPLANE)
        float iClip : SV_CLIPDISTANCE0,
    #endif
    #ifdef PREPASS
        out float4 oDepth : OUTCOLOR1,
    #endif
    #ifdef DEFERRED
        out float4 oAlbedo : OUTCOLOR1,
        out float4 oNormal : OUTCOLOR2,
        out float4 oDepth : OUTCOLOR3,
    #endif
    out float4 oColor : OUTCOLOR0)
{
    float3 weights = Sample2D(WeightMap0, iTexCoord.xy).rgb;
    float2 iDetailTexCoord = cDetailTiling * iTexCoord.xy;

    // height mapping
    weights.r*=Sample2D(DetailMap1, float3(iDetailTexCoord,9)).r;
    weights.g*=Sample2D(DetailMap1, float3(iDetailTexCoord,10)).r;
    weights.b*=Sample2D(DetailMap1, float3(iDetailTexCoord,11)).r;

    // squaring makes the height mapping effect stronger
    weights*=weights;
    weights*=weights;
    weights*=weights;

    float sumWeights = weights.r + weights.g + weights.b;
    weights /= sumWeights;

    // diffuse mapping
    float4 diffColor = cMatDiffColor * (
        cMatDiffColor1 * weights.r * Sample2D(DetailMap1, float3(iDetailTexCoord,0)) +
        cMatDiffColor2 * weights.g * Sample2D(DetailMap1, float3(iDetailTexCoord,1)) +
        cMatDiffColor3 * weights.b * Sample2D(DetailMap1, float3(iDetailTexCoord,2))
    );
//    float4 diffColor=cMatDiffColor;

    // normal mapping
    float3 normal=normalize(mul(float3x3(iTangent.xyz, float3(iTexCoord.zw, iTangent.w), iNormal),DecodeNormal(
        weights.r * Sample2D(DetailMap1, float3(iDetailTexCoord,3)) +
        weights.g * Sample2D(DetailMap1, float3(iDetailTexCoord,4)) +
        weights.b * Sample2D(DetailMap1, float3(iDetailTexCoord,5)))
    ).rgb);
    //float3 normal = normalize(iNormal);

    // specular mapping
    float4 specColor=float4(
        weights.r * cMatSpecColor1.rgb * Sample2D(DetailMap1, float3(iDetailTexCoord,6)).rgb +
        weights.g * cMatSpecColor2.rgb * Sample2D(DetailMap1, float3(iDetailTexCoord,7)).rgb +
        weights.b * cMatSpecColor3.rgb * Sample2D(DetailMap1, float3(iDetailTexCoord,8)).rgb,
        cMatSpecColor1.a*weights.r+cMatSpecColor2.a*weights.g+cMatSpecColor3.a*weights.b);
//    float3 specColor = cMatSpecColor.rgb;

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(iWorldPos.w, iWorldPos.y);
    #else
        float fogFactor = GetFogFactor(iWorldPos.w);
    #endif

    #if defined(PERPIXEL)
        // Per-pixel forward lighting
        float3 lightDir;
        float3 lightColor;
        float3 finalColor;
        
        float diff = GetDiffuse(normal, iWorldPos.xyz, lightDir);

        #ifdef SHADOW
            diff *= GetShadow(iShadowPos, iWorldPos.w);
        #endif
    
        #if defined(SPOTLIGHT)
            lightColor = iSpotPos.w > 0.0 ? Sample2DProj(LightSpotMap, iSpotPos).rgb * cLightColor.rgb : 0.0;
        #elif defined(CUBEMASK)
            lightColor = SampleCube(LightCubeMap, iCubeMaskVec).rgb * cLightColor.rgb;
        #else
            lightColor = cLightColor.rgb;
        #endif
    
        float spec = GetSpecular(normal, cCameraPosPS - iWorldPos.xyz, lightDir, specColor.a);
        finalColor = diff * lightColor * (diffColor.rgb + spec * specColor.rgb * cLightColor.a);

        #ifdef AMBIENT
            finalColor += cAmbientColor * diffColor.rgb;
            finalColor += cMatEmissiveColor;
            oColor = float4(GetFog(finalColor, fogFactor), diffColor.a);
        #else
            oColor = float4(GetLitFog(finalColor, fogFactor), diffColor.a);
        #endif
    #elif defined(PREPASS)
        // Fill light pre-pass G-Buffer
        float specPower = specColor.a / 255.0;

        oColor = float4(normal * 0.5 + 0.5, specPower);
        oDepth = iWorldPos.w;
    #elif defined(DEFERRED)
        // Fill deferred G-buffer
        float specIntensity = specColor.g;
        float specPower = specColor.a / 255.0;

        float3 finalColor = iVertexLight * diffColor.rgb;

        oColor = float4(GetFog(finalColor, fogFactor), 1.0);
        oAlbedo = fogFactor * float4(diffColor.rgb, specIntensity);
        oNormal = float4(normal * 0.5 + 0.5, specPower);
        oDepth = iWorldPos.w;
    #else
        // Ambient & per-vertex lighting
        float3 finalColor = iVertexLight * diffColor.rgb;

        #ifdef MATERIAL
            // Add light pre-pass accumulation result
            // Lights are accumulated at half intensity. Bring back to full intensity now
            float4 lightInput = 2.0 * Sample2DProj(LightBuffer, iScreenPos);
            float3 lightSpecColor = lightInput.a * (lightInput.rgb / GetIntensity(lightInput.rgb));

            finalColor += lightInput.rgb * diffColor.rgb + lightSpecColor * specColor.rgb;
        #endif

        oColor = float4(GetFog(finalColor, fogFactor), diffColor.a);
    #endif
}
