#ifndef KAGERP_SHADOWS
#define KAGERP_SHADOWS

// x: depth bias,
// y: normal bias,
// z: light type (Spot = 0, Directional = 1, Point = 2, Area/Rectangle = 3, Disc = 4, Pyramid = 5, Box = 6, Tube = 7)
// w: unused
float4 _ShadowBias;
float4x4 _WorldToMainLightShadow;

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

///////////////////////////
/// SHADOW MAP SAMPLING ///
///////////////////////////

float4 _MainLightShadowMap_TexelSize;
TEXTURE2D_SHADOW(_MainLightShadowMap);
SAMPLER_CMP(sampler_MainLightShadowMap);

half SampleMainLightShadowMap(float3 shadowCoords)
{
    return SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowMap, sampler_MainLightShadowMap, shadowCoords);
}

half SampleMainLightShadowMap(float3 shadowCoords, float2 offset)
{
    return SampleMainLightShadowMap(float3(shadowCoords.xy + offset, shadowCoords.z));
}

half SampleMainLightShadowMap2x2(float4 shadowCoords)
{
    float4 offsets = float4(_MainLightShadowMap_TexelSize.xy, -_MainLightShadowMap_TexelSize.xy) * 0.66f;
    half attenuation = 0.0h;

    attenuation += SampleMainLightShadowMap(shadowCoords.xyz);
    attenuation += SampleMainLightShadowMap(shadowCoords.xyz, offsets.xy);
    attenuation += SampleMainLightShadowMap(shadowCoords.xyz, offsets.xw);
    attenuation += SampleMainLightShadowMap(shadowCoords.xyz, offsets.zy);
    attenuation += SampleMainLightShadowMap(shadowCoords.xyz, offsets.zw);

    return attenuation * 0.2h;
}

half GetMainLightShadow(float4 shadowCoords)
{
    #if defined(MAIN_LIGHT_SHADOW_ON)
    shadowCoords.z = saturate(shadowCoords.z);
    half shadow = SampleMainLightShadowMap2x2(shadowCoords);
    return shadow;
    #else
    return 1.0h;
    #endif
}

#endif
