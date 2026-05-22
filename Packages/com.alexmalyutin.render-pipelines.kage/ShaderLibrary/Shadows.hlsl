#ifndef KAGERP_SHADOWS
#define KAGERP_SHADOWS

// x: depth bias,
// y: normal bias,
// z: light type (Spot = 0, Directional = 1, Point = 2, Area/Rectangle = 3, Disc = 4, Pyramid = 5, Box = 6, Tube = 7)
// w: unused
float4 _ShadowBias;
float4x4 _WorldToMainLightShadow;
// (x: shadowStrength, y: >= 1.0 if soft shadows, 0.0 otherwise, z: main light fade scale, w: main light fade bias)
float4 _MainLightShadowParams;


float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection)
{
    float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
    float scale = invNdotL * _ShadowBias.y;

    // normal bias is negative since we want to apply an inset normal offset
    positionWS = lightDirection * _ShadowBias.xxx + positionWS;
    positionWS = normalWS * scale.xxx + positionWS;
    return positionWS;
}

float4 ApplyShadowClamping(float4 positionCS)
{
    #if UNITY_REVERSED_Z
    float clamped = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
    #else
    float clamped = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
    #endif

    // The current implementation of vertex clamping in Universal RP is the same as in Unity Built-In RP.
    // We follow the same convention in Universal RP where it's only enabled for Directional Lights
    // (see: Shadows.cpp::RenderShadowMaps() #L2161-L2162)
    // (see: Shadows.cpp::RenderShadowMaps() #L2086-L2102)
    // (see: Shadows.cpp::PrepareStateForShadowMap() #L1685-L1686)
    // positionCS.z = lerp(positionCS.z, clamped, IsDirectionalLight());
    positionCS.z = clamped;

    return positionCS;
}

float4 TransformWorldToShadowMap(float3 positionWS)
{
    float4 shadowCoord = mul(_WorldToMainLightShadow, float4(positionWS, 1.0f));
    return saturate(shadowCoord);
}

half GetMainLightShadowFade(float3 positionWS)
{
    float3 camToPixel = positionWS - _WorldSpaceCameraPos;
    float distanceCamToPixel2 = dot(camToPixel, camToPixel);

    float fade = saturate(distanceCamToPixel2 * float(_MainLightShadowParams.z) + float(_MainLightShadowParams.w));
    return half(fade);
}

///////////////////////////
/// SHADOW MAP SAMPLING ///
///////////////////////////

float4 _MainLightShadowMap_TexelSize;
TEXTURE2D_SHADOW(_MainLightShadowMap);
SAMPLER_CMP(sampler_MainLightShadowMap);

half SampleMainLightShadowMapPCF(float3 shadowCoords)
{
    return SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowMap, sampler_MainLightShadowMap, shadowCoords);
}

half SampleMainLightShadowMapLinear(float3 shadowCoords)
{
    half shadowZ = SAMPLE_TEXTURE2D(_MainLightShadowMap, sampler_LinearClamp, shadowCoords.xy);
    return step(shadowZ, shadowCoords.z);
}

half SampleMainLightShadowMapPCF(float3 shadowCoords, float2 offset)
{
    return SampleMainLightShadowMapPCF(float3(shadowCoords.xy + offset, shadowCoords.z));
}

half SampleMainLightShadowMap2x2(float4 shadowCoords)
{
    float4 offsets = float4(_MainLightShadowMap_TexelSize.xy, -_MainLightShadowMap_TexelSize.xy) * 0.5f;
    half attenuation = 0.0h;

    attenuation += SampleMainLightShadowMapPCF(shadowCoords.xyz);
    attenuation += SampleMainLightShadowMapPCF(shadowCoords.xyz, offsets.xy);
    attenuation += SampleMainLightShadowMapPCF(shadowCoords.xyz, offsets.xw);
    attenuation += SampleMainLightShadowMapPCF(shadowCoords.xyz, offsets.zy);
    attenuation += SampleMainLightShadowMapPCF(shadowCoords.xyz, offsets.zw);

    return attenuation * 0.2h;
}

half GetMainLightShadow(float3 positionWS, float4 shadowCoords)
{
    #if defined(MAIN_LIGHT_SHADOW_ON)
    shadowCoords.z = saturate(shadowCoords.z);
    half shadow = SampleMainLightShadowMap2x2(shadowCoords);
    half fade = GetMainLightShadowFade(positionWS);
    return lerp(shadow, 1.0h, fade);
    #else
    return 1.0h;
    #endif
}

#endif
