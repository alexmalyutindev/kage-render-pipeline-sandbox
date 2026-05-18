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
    uint offset = uint(unity_LightData.x);
    return _AdditionalLightsIndices[offset + index];
}

Light GetAdditionalPerObjectLight(int perObjectLightIndex, float3 positionWS)
{
    float4 lightPositionWS = _AdditionalLightsBuffer[perObjectLightIndex].position;
    half3 color = _AdditionalLightsBuffer[perObjectLightIndex].color.rgb;
    half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[perObjectLightIndex].attenuation;
    half4 spotDirection = _AdditionalLightsBuffer[perObjectLightIndex].spotDirection;

    float3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
    float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);

    half3 lightDirection = half3(lightVector * rsqrt(distanceSqr));

    // TODO: Compute distanceAttenuation!
    half distanceAttenuation = 1.0h;

    Light light;
    light.direction = lightDirection;
    light.distanceAttenuation = distanceAttenuation;
    light.color = color;
    light.shadowAttenuation = 1.0h;

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
