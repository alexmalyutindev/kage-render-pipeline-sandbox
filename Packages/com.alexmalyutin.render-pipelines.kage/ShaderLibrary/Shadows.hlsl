#ifndef KAGERP_SHADOWS
#define KAGERP_SHADOWS

// x: depth bias,
// y: normal bias,
// z: light type (Spot = 0, Directional = 1, Point = 2, Area/Rectangle = 3, Disc = 4, Pyramid = 5, Box = 6, Tube = 7)
// w: unused
float4 _ShadowBias;

float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection)
{
    float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
    float scale = invNdotL * _ShadowBias.y;

    // normal bias is negative since we want to apply an inset normal offset
    positionWS = lightDirection * _ShadowBias.xxx + positionWS;
    positionWS = normalWS * scale.xxx + positionWS;
    return positionWS;
}

#endif
