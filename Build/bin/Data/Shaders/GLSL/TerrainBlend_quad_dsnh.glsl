#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"
#include "Lighting.glsl"
#include "Fog.glsl"

varying vec4 vTexCoord;

#ifndef GL_ES
varying vec2 vDetailTexCoord;
#else
varying lowp vec2 vDetailTexCoord;
#endif

varying vec3 vNormal;
varying vec4 vTangent;
varying vec4 vWorldPos;

#ifdef PERPIXEL
    #ifdef SHADOW
        varying vec4 vShadowPos[NUMCASCADES];
    #endif
    #ifdef SPOTLIGHT
        varying vec4 vSpotPos;
    #endif
    #ifdef POINTLIGHT
        varying vec3 vCubeMaskVec;
    #endif
#else
    varying vec3 vVertexLight;
    varying vec4 vScreenPos;
    #ifdef ENVCUBEMAP
        varying vec3 vReflectionVec;
    #endif
    #if defined(LIGHTMAP) || defined(AO)
        varying vec2 vTexCoord2;
    #endif
#endif

uniform sampler2D sWeightMap0;
uniform sampler2D sDetailMap1;
uniform sampler2D sDetailMap2;
uniform sampler2D sDetailMap3;
uniform vec4 cMatDiffColor1;
uniform vec4 cMatDiffColor2;
uniform vec4 cMatDiffColor3;
uniform vec4 cMatSpecColor1;
uniform vec4 cMatSpecColor2;
uniform vec4 cMatSpecColor3;

#ifndef GL_ES
uniform vec2 cDetailTiling;
#else
uniform lowp vec2 cDetailTiling;
#endif

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));

    vec3 tangent = GetWorldTangent(modelMatrix);
    vec3 bitangent = cross(tangent, vNormal) * iTangent.w;
    vTexCoord = vec4(GetTexCoord(iTexCoord), bitangent.xy);
    vTangent = vec4(tangent, bitangent.z);
    vDetailTexCoord = cDetailTiling * vTexCoord.xy;

    #ifdef PERPIXEL
        // Per-pixel forward lighting
        vec4 projWorldPos = vec4(worldPos, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            for (int i = 0; i < NUMCASCADES; i++)
                vShadowPos[i] = GetShadowPos(i, projWorldPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = projWorldPos * cLightMatrices[0];
        #endif

        #ifdef POINTLIGHT
            vCubeMaskVec = (worldPos - cLightPos.xyz) * mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz);
        #endif
    #else
        // Ambient & per-vertex lighting
        #if defined(LIGHTMAP) || defined(AO)
            // If using lightmap, disregard zone ambient light
            // If using AO, calculate ambient in the PS
            vVertexLight = vec3(0.0, 0.0, 0.0);
            vTexCoord2 = iTexCoord2;
        #else
            vVertexLight = GetAmbient(GetZonePos(worldPos));
        #endif

        #ifdef NUMVERTEXLIGHTS
            for (int i = 0; i < NUMVERTEXLIGHTS; ++i)
                vVertexLight += GetVertexLight(i, worldPos, vNormal) * cVertexLights[i * 3].rgb;
        #endif

        vScreenPos = GetScreenPos(gl_Position);

        #ifdef ENVCUBEMAP
            vReflectionVec = worldPos - cCameraPos;
        #endif
    #endif
}

void PS()
{
    vec2 tex_coord_diff=vec2(mod(vDetailTexCoord.x/4.0,0.25),vDetailTexCoord.y);
    tex_coord_diff.x=0.0625+tex_coord_diff.x*0.5;   // this is required for some reason to avoid weird lines. I guess some mipmap stuff.
    vec2 tex_coord_norm  =vec2(tex_coord_diff.x+0.25,tex_coord_diff.y);
    vec2 tex_coord_spec  =vec2(tex_coord_diff.x+0.50,tex_coord_diff.y);
    vec2 tex_coord_height=vec2(tex_coord_diff.x+0.75,tex_coord_diff.y);

    vec3 weights = texture2D(sWeightMap0, vTexCoord.xy).rgb;

    // blend with height map
    weights.r*=texture2D(sDetailMap1, tex_coord_height).r;
    weights.g*=texture2D(sDetailMap2, tex_coord_height).r;
    weights.b*=texture2D(sDetailMap3, tex_coord_height).r;

    float sumWeights = weights.r + weights.g + weights.b;
    weights /= sumWeights;
    vec4 diffColor = vec4(
        cMatDiffColor1 * weights.r * texture2D(sDetailMap1, tex_coord_diff) +
        cMatDiffColor2 * weights.g * texture2D(sDetailMap2, tex_coord_diff) +
        cMatDiffColor3 * weights.b * texture2D(sDetailMap3, tex_coord_diff)
    );
//    vec4 diffColor=vec4(1,1,1,1);

    // Get material specular albedo
    vec4 specColor=vec4(
        weights.r * cMatSpecColor1.rgb * texture2D(sDetailMap1, tex_coord_spec).rgb +
        weights.g * cMatSpecColor2.rgb * texture2D(sDetailMap2, tex_coord_spec).rgb +
        weights.b * cMatSpecColor3.rgb * texture2D(sDetailMap3, tex_coord_spec).rgb,
        cMatSpecColor1.a*weights.r+cMatSpecColor2.a*weights.g+cMatSpecColor3.a*weights.b);
    //vec4 specColor=vec4(1,1,1,1);

    // Get normal
    vec3 normal=normalize(mat3(vTangent.xyz, vec3(vTexCoord.zw, vTangent.w), vNormal)*DecodeNormal(
        weights.r * texture2D(sDetailMap1, tex_coord_norm) +
        weights.g * texture2D(sDetailMap2, tex_coord_norm) +
        weights.b * texture2D(sDetailMap3, tex_coord_norm)
    ).rgb);
//vec3 normal=vNormal;

    // Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(vWorldPos.w, vWorldPos.y);
    #else
        float fogFactor = GetFogFactor(vWorldPos.w);
    #endif

    #if defined(PERPIXEL)
        // Per-pixel forward lighting
        vec3 lightColor;
        vec3 lightDir;
        vec3 finalColor;

        float diff = GetDiffuse(normal, vWorldPos.xyz, lightDir);

        #ifdef SHADOW
            diff *= GetShadow(vShadowPos, vWorldPos.w);
        #endif

        #if defined(SPOTLIGHT)
            lightColor = vSpotPos.w > 0.0 ? texture2DProj(sLightSpotMap, vSpotPos).rgb * cLightColor.rgb : vec3(0.0, 0.0, 0.0);
        #elif defined(CUBEMASK)
            lightColor = textureCube(sLightCubeMap, vCubeMaskVec).rgb * cLightColor.rgb;
        #else
            lightColor = cLightColor.rgb;
        #endif

        #ifdef SPECULAR
            float spec = GetSpecular(normal, cCameraPosPS - vWorldPos.xyz, lightDir, specColor.a);
            finalColor = diff * lightColor * (diffColor.rgb + spec * specColor.rgb * cLightColor.a);
        #else
            finalColor = diff * lightColor * diffColor.rgb;
        #endif

        #ifdef AMBIENT
            finalColor += cAmbientColor * diffColor.rgb;
            finalColor += cMatEmissiveColor;
            gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);
        #else
            gl_FragColor = vec4(GetLitFog(finalColor, fogFactor), diffColor.a);
        #endif
    #elif defined(PREPASS)
        // Fill light pre-pass G-Buffer
        float specPower = specColor .a / 255.0;

        gl_FragData[0] = vec4(normal * 0.5 + 0.5, specPower);
        gl_FragData[1] = vec4(EncodeDepth(vWorldPos.w), 0.0);
    #elif defined(DEFERRED)
        // Fill deferred G-buffer
        float specIntensity = specColor.g;
        float specPower = specColor.a / 255.0;

        gl_FragData[0] = vec4(GetFog(vVertexLight * diffColor.rgb, fogFactor), 1.0);
        gl_FragData[1] = fogFactor * vec4(diffColor.rgb, specIntensity);
        gl_FragData[2] = vec4(normal * 0.5 + 0.5, specPower);
        gl_FragData[3] = vec4(EncodeDepth(vWorldPos.w), 0.0);
    #else
        // Ambient & per-vertex lighting
        vec3 finalColor = vVertexLight * diffColor.rgb;

        #ifdef MATERIAL
            // Add light pre-pass accumulation result
            // Lights are accumulated at half intensity. Bring back to full intensity now
            vec4 lightInput = 2.0 * texture2DProj(sLightBuffer, vScreenPos);
            vec3 lightSpecColor = lightInput.a * lightInput.rgb / max(GetIntensity(lightInput.rgb), 0.001);

            finalColor += lightInput.rgb * diffColor.rgb + lightSpecColor * specColor;
        #endif

        gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);
    #endif
}
