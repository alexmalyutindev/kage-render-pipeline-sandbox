#ifndef KAGERP_LOCAL_SHADOW
#define KAGERP_LOCAL_SHADOW

#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"

float _EnableLocalShadow;
float4 _LocalShadow_TexelSize;
TEXTURE2D_ARRAY_SHADOW(_LocalShadow);
SAMPLER_CMP(sampler_LocalShadow);
float4x4 _WorldToLocalShadow[4];

half SampleLocalShadowMapPCF(float3 shadowCoord, uint index)
{
    return SAMPLE_TEXTURE2D_ARRAY_SHADOW(_LocalShadow, sampler_LocalShadow, shadowCoord, index);
}

half SampleLocalShadowMapPCF(float3 shadowCoords, float2 offset, uint index)
{
    return SampleLocalShadowMapPCF(float3(shadowCoords.xy + offset, shadowCoords.z), index);
}

half SampleLocalShadowMap3x3(float3 shadowCoords, uint index)
{
    float2 texel = _LocalShadow_TexelSize.yx * 1.334f;

    half attenuation = 0.0h;
    UNITY_UNROLL for (uint i = 0; i < 9; i++)
    {
        float2 offset = PoissonDisk9[i] * texel;
        attenuation += SampleLocalShadowMapPCF(shadowCoords.xyz, offset, index);
    }
    return attenuation * (1.0h / 9.0h);
}

half SampleLocalShadowMap2x2(float3 shadowCoords, uint index)
{
    float4 offsets = float4(_LocalShadow_TexelSize.xy, -_LocalShadow_TexelSize.xy) * 0.5f;

    half attenuation = 0.0h;
    attenuation += SampleLocalShadowMapPCF(shadowCoords, offsets.xy, index);
    attenuation += SampleLocalShadowMapPCF(shadowCoords, offsets.xw, index);
    attenuation += SampleLocalShadowMapPCF(shadowCoords, offsets.zy, index);
    attenuation += SampleLocalShadowMapPCF(shadowCoords, offsets.zw, index);

    return attenuation * 0.25h;
}

half GetLocalShadow(float3 positionWS)
{
    if (_EnableLocalShadow > 0.5)
    {
        // TODO: Add support for several local shadows!
        uint index = 0;
        float4 shadowCoords = mul(_WorldToLocalShadow[index], float4(positionWS, 1.0f));
        shadowCoords.z = saturate(shadowCoords.z);
        float2 dist = (shadowCoords.xy - 0.5f) * 2.0f;
        if (dot(dist, dist) > 1.0f) return 1.0h;

        return SampleLocalShadowMap3x3(shadowCoords.xyz, index);
    }

    return 1.0h;
}

#endif
