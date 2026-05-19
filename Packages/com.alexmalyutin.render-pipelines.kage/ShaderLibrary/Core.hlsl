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

GBuffer OutputGBuffer(half3 color, MaterialData material, InputData inputData)
{
    half3 normalVS = TransformWorldToViewNormal(inputData.normalWS);

    GBuffer output;
    output.GBuffer0 = half4(color, 1.0h);
    output.GBuffer1 = half4(material.albedo, material.occlusion);
    output.GBuffer2 = half4(
        normalVS.xy * 0.5h + 0.5h,
        material.metallic,
        material.roughness
    );
    return output;
}

#endif
