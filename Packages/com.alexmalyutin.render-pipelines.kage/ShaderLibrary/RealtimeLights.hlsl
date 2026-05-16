#ifndef KAGERP_REALTIMELIGHTS
#define KAGERP_REALTIMELIGHTS

#include "Input.hlsl"
#include "Shadows.hlsl"

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
