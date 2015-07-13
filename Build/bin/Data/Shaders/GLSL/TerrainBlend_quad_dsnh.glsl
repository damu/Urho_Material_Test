#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"
#include "Lighting.glsl"
#include "Fog.glsl"

varying vec4 vTexCoord;
varying vec2 viTexCoord;

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
uniform vec4 cMatSpecColor1;
uniform vec4 cMatSpecColor2;
uniform vec4 cMatSpecColor3;

#ifndef GL_ES
uniform vec2 cDetailTiling;
#else
uniform lowp vec2 cDetailTiling;
#endif

#extension GL_ARB_texture_query_lod : enable

vec4 texture2D_bilinear(sampler2D sampler,vec2 coord)
{
//return texture2D(sampler,coord);

    // based on http://stackoverflow.com/questions/24388346/how-to-access-automatic-mipmap-level-in-glsl-fragment-shader-texture
    int lod=0;
//#ifdef GL_ARB_texture_query_lod
//    lod = int(textureQueryLOD(sampler,coord).x);
//#endif

    coord=abs(mod(coord,1));
    vec2 ts=textureSize(sampler,lod);
    coord.x=coord.x*ts.x;
    coord.y=coord.y*ts.y;
//    coord.x=clamp(coord.x,5,ts.x-5);
//    coord.y=clamp(coord.y,5,ts.y-5);

    ivec2 pixel_pos=ivec2(coord);
    //pixel_pos.x=int(min(pixel_pos.x,ts.x-1));
    //pixel_pos.y=int(min(pixel_pos.y,ts.y-1));
    float a=coord.x-pixel_pos.x;
    float b=coord.y-pixel_pos.y;

    ivec2 offset=ivec2(-1,-1);
    if(pixel_pos.x<=0)
        offset.x=0;
    if(pixel_pos.y<=0)
        offset.y=0;
    vec4 p1q1 = texelFetch(sampler,pixel_pos           ,lod);
    vec4 p0q1 = texelFetch(sampler,pixel_pos+ivec2(offset.x,0),lod);
    vec4 p1q0 = texelFetch(sampler,pixel_pos+ivec2(0,offset.y),lod);
    vec4 p0q0 = texelFetch(sampler,pixel_pos+offset,lod);

//    float a = fract( coord.x * fWidth );      // Get Interpolation factor for X direction.
                                              // Fraction near to valid data.

    vec4 pInterp_q0 = mix( p0q0, p1q0, a );   // Interpolates top row in X direction.
//    vec4 pInterp_q1 = mix( p0q1, p1q1, a );   // Interpolates bottom row in X direction.

//    float b = fract( coord.y * fHeight );   // Get Interpolation factor for Y direction.
//    return mix( pInterp_q0, pInterp_q1, b );  // Interpolate in Y direction.
   return p1q1;
   //return p0q0;
}

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vNormal = GetWorldNormal(modelMatrix);
    vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    viTexCoord = iTexCoord;

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
    vec2 tex_coord_diff  =vec2(mod(vTexCoord.x*vDetailTexCoord.x/4,0.25),vTexCoord.y*vDetailTexCoord.y);
//    tex_coord_diff.x=clamp(tex_coord_diff.x,0.01,0.24);
    vec2 tex_coord_norm  =vec2(tex_coord_diff.x+0.25,tex_coord_diff.y);
    vec2 tex_coord_spec  =vec2(tex_coord_diff.x+0.50,tex_coord_diff.y);
    vec2 tex_coord_height=vec2(tex_coord_diff.x+0.75,tex_coord_diff.y);

    vec3 weights = texture2D(sWeightMap0, vTexCoord.xy).rgb;

    // blend with height map
    weights.r*=texture2D(sDetailMap1, tex_coord_height).r;
    weights.g*=texture2D(sDetailMap2, tex_coord_height).r;

    float sumWeights = weights.r + weights.g + weights.b;
    weights /= sumWeights;
    vec4 diffColor = cMatDiffColor * (
        weights.r * texture2D_bilinear(sDetailMap1, tex_coord_diff) +
        weights.g * texture2D_bilinear(sDetailMap2, tex_coord_diff) + 
        weights.b * texture2D(sDetailMap3, vDetailTexCoord)
    );

    // Get material specular albedo
    vec4 specColor=vec4(
        weights.r * cMatSpecColor1.rgb * texture2D_bilinear(sDetailMap1, tex_coord_spec).rgb +
        weights.g * cMatSpecColor2.rgb * texture2D_bilinear(sDetailMap2, tex_coord_spec).rgb + 
        weights.b * cMatSpecColor3.rgb * texture2D(sDetailMap3, vDetailTexCoord).rgb,
        cMatSpecColor1.a*weights.r+cMatSpecColor2.a*weights.g+cMatSpecColor3.a*weights.b);

//vec4 specColor=vec4(1,1,1,1);

    // Get normal
    vec3 normal=normalize(mat3(vTangent.xyz, vec3(vTexCoord.zw, vTangent.w), vNormal)*DecodeNormal(
        weights.r * texture2D_bilinear(sDetailMap1, tex_coord_norm) +
        weights.g * texture2D_bilinear(sDetailMap2, tex_coord_norm) + 
        weights.b * texture2D(sDetailMap3, vDetailTexCoord)
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
