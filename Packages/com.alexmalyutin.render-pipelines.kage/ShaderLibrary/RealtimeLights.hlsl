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

half DistanceAttenuation(float distanceSqr, half2 distanceAttenuation)
{
    float lightAttenuation = rcp(distanceSqr);
    half factor = half(distanceSqr * distanceAttenuation.x);
    half smoothFactor = saturate(half(1.0h) - factor * factor);
    smoothFactor = smoothFactor * smoothFactor;
    return lightAttenuation * smoothFactor;
}

half AngleAttenuation(half3 spotDirection, half3 lightDirection, half2 spotAttenuation)
{
    // Spot Attenuation with a linear falloff can be defined as
    // (SdotL - cosOuterAngle) / (cosInnerAngle - cosOuterAngle)
    // This can be rewritten as
    // invAngleRange = 1.0 / (cosInnerAngle - cosOuterAngle)
    // SdotL * invAngleRange + (-cosOuterAngle * invAngleRange)
    // SdotL * spotAttenuation.x + spotAttenuation.y

    // If we precompute the terms in a MAD instruction
    half SdotL = dot(spotDirection, lightDirection);
    half atten = saturate(SdotL * spotAttenuation.x + spotAttenuation.y);
    return atten * atten;
}

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
    half4 spotDirection = _AdditionalLightsBuffer[perObjectLightIndex].spotDirection;

    float3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
    float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);
    half3 lightDirection = half3(lightVector * rsqrt(distanceSqr));

    Light light;
    light.color = color;
    light.direction = lightDirection;
    light.shadowAttenuation = 1.0h;
    light.distanceAttenuation = 
        DistanceAttenuation(distanceSqr, distanceAndSpotAttenuation.xy) * 
        AngleAttenuation(spotDirection.xyz, lightDirection, distanceAndSpotAttenuation.zw);

    return light;
}

///////////////////////////////////////////////

Light GetMainLight(float3 positionWS, float4 shadowCoords)
{
    Light light;
    light.color = _MainLightColor.rgb;
    light.direction = _MainLightPosition.xyz;
    light.shadowAttenuation = GetMainLightShadow(positionWS, shadowCoords);
    light.distanceAttenuation = 1.0h;
    return light;
}

Light GetAdditionalLight(uint i, float3 positionWS)
{
    int perObjectLightIndex = GetPerObjectLightIndex(i);
    return GetAdditionalPerObjectLight(perObjectLightIndex, positionWS);
}

#endif
