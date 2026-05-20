#ifndef KAGERP_CORE
#define KAGERP_CORE

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

#include "UnityInput.hlsl"
#include "Input.hlsl"
#include "BRDFData.hlsl"

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

struct MaterialData
{
    half3 albedo;
    half3 normalTS;
    half3 emission;
    half metallic;
    half roughness;
    half occlusion;
    half alpha;
};

struct InputData
{
    float3 positionWS;
    float4 shadowCoord;
    half3 normalWS;
    half3 viewDirectionWS; // Vector from surface to camera 
    half3 bakedGI;
};

struct GBuffer
{
    half4 GBuffer0 : SV_Target0;
    half4 GBuffer1 : SV_Target1;
    half4 GBuffer2 : SV_Target2;
};

struct GBufferData
{
    half3 albedo;
    half occlusion;
    half3 normalVS;
    half depth;
    half metallic;
    half roughness;
};

half PackHalf2ToHalf(half a, half b)
{
    uint a4 = (uint)(saturate(a) * 15.0f);
    uint b4 = (uint)(saturate(b) * 15.0f);
    uint packed = b4 << 4 | a4;
    return packed;
}

void UnpackHalfToHalf2(half packed, out half a, out half b)
{
    uint packed8 = packed;
    uint a4 = packed8 & 0x0F;
    uint b4 = packed8 >> 4 & 0x0F;

    a = half(a4) / 15.0h;
    b = half(b4) / 15.0h;
}

GBuffer OutputGBuffer(half3 color, MaterialData material, InputData inputData)
{
    half3 normalVS = TransformWorldToViewNormal(inputData.normalWS);
    half packedMetallicRoughness = PackHalf2ToHalf(material.metallic, material.roughness);

    GBuffer output;
    output.GBuffer0 = half4(color, 1.0h);
    output.GBuffer1 = half4(material.albedo, material.occlusion);
    output.GBuffer2 = half4(
        normalVS.xy,
        abs(TransformWorldToView(inputData.positionWS).z),
        packedMetallicRoughness
    );
    return output;
}

GBufferData ReadGBuffer(half4 gBuffer1, half4 gBuffer2)
{
    GBufferData data;
    data.albedo = gBuffer1.rgb;
    data.occlusion = gBuffer1.a;

    data.normalVS.xy = gBuffer2.xy;
    data.normalVS.z = sqrt(max(0.00001f, 1.0f - dot(data.normalVS.xy, data.normalVS.xy)));
    data.depth = gBuffer2.z;
    UnpackHalfToHalf2(gBuffer2.a, data.metallic, data.roughness);

    return data;
}

#endif
