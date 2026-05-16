#ifndef KAGERP_REALTIMELIGHTS
#define KAGERP_REALTIMELIGHTS

#include "Input.hlsl"

float4 _MainLightShadowMap_TexelSize;
TEXTURE2D_SHADOW(_MainLightShadowMap);
SAMPLER_CMP(sampler_MainLightShadowMap);

float4x4 _WorldToMainLightShadow;

float4 TransformWorldToShadowMap(float3 positionWS)
{
    float4 shadowCoord = mul(_WorldToMainLightShadow, float4(positionWS, 1.0f));
    return saturate(shadowCoord);
}

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
    return SampleMainLightShadowMap2x2(shadowCoords);
    #else
    return 1.0h;
    #endif
}

struct Light
{
    half3 color;
    half3 direction;
    half attenuation;
};

Light GetMainLight(float4 shadowCoords)
{
    Light light;
    light.color = _MainLightColor.rgb;
    light.direction = _MainLightPosition.xyz;
    light.attenuation = GetMainLightShadow(shadowCoords);
    return light;
}

#endif
