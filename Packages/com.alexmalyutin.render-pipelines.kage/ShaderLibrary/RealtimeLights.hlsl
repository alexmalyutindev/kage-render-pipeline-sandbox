#ifndef KAGERP_REALTIMELIGHTS
#define KAGERP_REALTIMELIGHTS

#include "Input.hlsl"
#include "Shadows.hlsl"

struct Light
{
    half3 color;
    half3 direction;
    half shadowAttenuation;
    half distanceAttenuation;
};

uint GetPerObjectLightIndexOffset()
{
    #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
    return uint(unity_LightData.x);
    #else
    return 0;
    #endif
}

int GetAdditionalLightsCount()
{
    return int(min(_AdditionalLightsCount.x, unity_LightData.y));
}

int GetPerObjectLightIndex(uint index)
{
    #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
    uint offset = uint(unity_LightData.x);
    return _AdditionalLightsIndices[offset + index];
    #else
    return unity_LightIndices[index / 4][index % 4];
    #endif
}

Light GetAdditionalPerObjectLight(int perObjectLightIndex, float3 positionWS)
{
    float4 lightPositionWS = _AdditionalLightsBuffer[perObjectLightIndex].position;
    half3 color = _AdditionalLightsBuffer[perObjectLightIndex].color.rgb;
    half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[perObjectLightIndex].attenuation;
    // TODO: Add SpotLight support! 
    half4 spotDirection = _AdditionalLightsBuffer[perObjectLightIndex].spotDirection;

    float3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
    float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);
    half3 lightDirection = half3(lightVector * rsqrt(distanceSqr));

    float lightAttenuation = rcp(distanceSqr);
    half factor = half(distanceSqr * distanceAndSpotAttenuation.x);
    half smoothFactor = saturate(half(1.0h) - factor * factor);
    smoothFactor = smoothFactor * smoothFactor;
    half distanceAttenuation = lightAttenuation * smoothFactor;

    Light light;
    light.color = color;
    light.direction = lightDirection;
    light.shadowAttenuation = 1.0h;
    light.distanceAttenuation = distanceAttenuation;

    return light;
}

///////////////////////////////////////////////

Light GetMainLight(float4 shadowCoords)
{
    Light light;
    light.color = _MainLightColor.rgb;
    light.direction = _MainLightPosition.xyz;
    light.shadowAttenuation = GetMainLightShadow(shadowCoords);
    light.distanceAttenuation = 1.0h;
    return light;
}

Light GetAdditionalLight(uint i, float3 positionWS)
{
    int perObjectLightIndex = GetPerObjectLightIndex(i);
    return GetAdditionalPerObjectLight(perObjectLightIndex, positionWS);
}

#endif
