#ifndef KAGERP_CORE
#define KAGERP_CORE

// Default unity input declaration
#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/UnityInput.hlsl"
#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Input.hlsl"

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/BRDFData.hlsl"
#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Packing.hlsl"

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

GBuffer OutputGBuffer(half3 color, MaterialData material, InputData inputData)
{
    half3 normalVS = TransformWorldToViewNormal(inputData.normalWS);
    // TODO: Optimize depth!
    half depth = abs(TransformWorldToView(inputData.positionWS).z);
    half packedMetallicRoughness = PackHalf84(material.roughness, material.metallic);

    GBuffer output;
    output.GBuffer0 = half4(color, 1.0h);
    output.GBuffer1 = half4(material.albedo, material.occlusion);
    output.GBuffer2 = half4(normalVS.xy, depth, packedMetallicRoughness);
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
    UnpackHalf84(gBuffer2.a, data.roughness, data.metallic);

    return data;
}

#endif
