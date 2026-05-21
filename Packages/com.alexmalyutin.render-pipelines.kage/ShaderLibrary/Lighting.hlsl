#ifndef KAGERP_LIGHTING
#define KAGERP_LIGHTING

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

#include "UnityInput.hlsl"
#include "RealtimeLights.hlsl"
#include "BRDFData.hlsl"
#include "GlobalIlummination.hlsl"

////////////////////////
// GGX LIGHTING MODEL //
////////////////////////

float GgxDistribution(float NdotH, float roughness)
{
    float a = roughness * roughness * roughness * roughness;
    float d = NdotH * NdotH * (a - 1.0) + 1.0;
    d = PI * d * d;
    return a / max(d, 0.0000001);
}

float GeomSmith(float NdotV, float NdotL, float roughness)
{
    #if !defined(OPTIMIZATION)
    float r = roughness + 1.0;
    float k = r * r / 8.0;
    float ik = 1.0 - k;
    float ggx1 = NdotV / (NdotV * ik + k);
    float ggx2 = NdotL / (NdotL * ik + k);
    return ggx1 * ggx2;
    #else
    return NdotL * NdotV / lerp(0.5, 2.0, roughness);
    #endif
}

/////////////////////////////////////

BRDFData InitBRDFData(MaterialData surfaceData)
{
    BRDFData data;
    data.albedo = surfaceData.albedo;
    data.F0 = lerp(0.04h, surfaceData.albedo, surfaceData.metallic);
    data.diffuseColor = lerp(surfaceData.albedo, 0.0h, surfaceData.metallic);
    data.metallic = surfaceData.metallic;
    data.roughness = surfaceData.roughness;
    data.occlusion = surfaceData.occlusion;
    data.emission = surfaceData.emission;

    return data;
}

half3 SingleLightPBR(BRDFData brdfData, InputData inputData, Light light)
{
    half3 N = inputData.normalWS;
    half3 V = inputData.viewDirectionWS;

    // float specularPower = 512.0h * (1.0h - brdfData.roughness); 
    float specularPower = exp2(10.0h * (1.0h - brdfData.roughness) + 1.0h);
    float specularNormalization = (specularPower + 2.0h) / 8.0h;
    // (1.04h - roughness) * (specularPower + 8.0) / 8.0;

    half3 L = light.direction;
    half3 H = normalize(V + L);
    half NdotL = max(0.0h, dot(N, L));
    float NdotH = max(0.0h, dot(N, H));

    float specularTerm = specularNormalization * pow(NdotH, specularPower);
    half3 specular = brdfData.F0 * light.color * specularTerm;

    half3 diffuse = brdfData.diffuseColor * light.color * NdotL;
    half3 directLighting = max(0.0h, diffuse + specular) * brdfData.occlusion;

    return directLighting * light.shadowAttenuation * light.distanceAttenuation;
}

// TODO: Optimize math!
half3 SingleLightPBR_TwoSide(BRDFData brdfData, InputData inputData, Light light)
{
    half3 N = inputData.normalWS;
    half3 V = inputData.viewDirectionWS;

    float specularPower = exp2(10.0h * (1.0h - brdfData.roughness) + 1.0h);
    float specularNormalization = (specularPower + 2.0h) / 8.0h;

    half3 L = light.direction;
    half3 H = normalize(float3(V) + L);
    half NdotL = abs(dot(N, L));
    half NdotH = max(0.0h, dot(float3(N), H));

    float specularTerm = specularNormalization * pow(NdotH, specularPower);
    half3 specular = brdfData.F0 * light.color * specularTerm;

    half3 diffuse = brdfData.diffuseColor * light.color * NdotL;
    half3 directLighting = max(0.0h, diffuse + specular) * brdfData.occlusion;

    return directLighting * light.shadowAttenuation * light.distanceAttenuation;
}

half3 SingleLightPBR_Opt(BRDFData brdfData, InputData inputData, Light light)
{
    half3 N = inputData.normalWS;
    half3 V = inputData.viewDirectionWS;

    half3 L = light.direction;
    half3 H = normalize(V + L);

    half NdotL = max(0.0h, dot(N, L));
    half NdotH = max(0.0h, dot(N, H));
    half VdotH = max(0.0h, dot(V, H)); // <-- needed for K/SK

    // D term
    half a2 = brdfData.roughness * brdfData.roughness;
    half denom = (NdotH * NdotH) * (a2 - 1.0h) + 1.0h;
    half D_GGX = a2 / (denom * denom + 1e-5h) * INV_PI;

    // Kelemen/Szirmay-Kalos visibility term
    // Replaces both the geometry term G and the (4 NdotL NdotV) denominator.
    // V(l,v,h) = 1 / (VdotH * VdotH)
    // The *2 NdotL below folds in the standard BRDF NdotL weight.
    half Vis = 1.0h / (VdotH * VdotH + 1e-4h); // guard against VdotH=0

    // Fresnel: Schlick
    half3 F = brdfData.F0 + (1.0h - brdfData.F0) * pow(1.0h - VdotH, 5.0h);
    half3 specular = F * D_GGX * Vis * light.color * NdotL;
    half3 diffuse = brdfData.diffuseColor * light.color * NdotL;

    // NOTE: Occlusion is applied here just for visual taste reason. Lighting looks flat without AO.
    half3 directLighting = max(0.0h, diffuse + specular) * brdfData.occlusion;

    return directLighting * light.shadowAttenuation * light.distanceAttenuation;
}

half3 MobilePBR(BRDFData brdfData, InputData inputData)
{
    half3 F0 = lerp(0.04h, brdfData.albedo, brdfData.metallic);

    half3 N = inputData.normalWS;
    half3 V = inputData.viewDirectionWS;
    half NdotV = max(0.0h, dot(N, V));

    // Environment
    float2 envBRDF = GetEnvBRDF(NdotV, brdfData.roughness);
    half3 reflectV = reflect(-V, N);
    half4 encodedReflection = SampleEncodedEnvironmentReflection(reflectV, brdfData.roughness);

    half3 diffuseColor = lerp(brdfData.albedo, 0.0h, brdfData.metallic);
    half specularPower = exp2(10.0h * (1.0h - brdfData.roughness) + 1.0h); // 512.0h * (1.0h - roughness);
    half specularNormalization = (specularPower + 2.0h) / 8.0h;
    // (1.04h - roughness) * (specularPower + 8.0) / 8.0;

    // Direct
    Light mainLight = GetMainLight(inputData.shadowCoord);

    // NOTE: float3() needed here to fix precision bug on specular highlingt.
    half3 L = mainLight.direction;
    half3 H = normalize(float3(V) + L);
    half NdotL = max(0.0h, dot(N, L));
    half NdotH = max(0.0h, dot(float3(N), H));

    half specularTerm = specularNormalization * pow(NdotH, specularPower);
    half3 specular = F0 * mainLight.color * specularTerm;

    half3 diffuse = diffuseColor * mainLight.color * NdotL;
    half3 directLighting = max(0.0h, diffuse + specular);

    // IBL
    half3 F = SchlickFresnel(NdotV, F0);
    half3 envReflection = DecodeHDREnvironment(encodedReflection, unity_SpecCube0_HDR);
    half3 specularIBL = envReflection * (F * envBRDF.x + envBRDF.y);
    half3 diffuseIBL = (1.0h - brdfData.metallic) * brdfData.albedo * inputData.bakedGI;
    half3 ambient = (diffuseIBL + specularIBL) * brdfData.occlusion;

    return directLighting * mainLight.shadowAttenuation + ambient + brdfData.emission;
}

#endif
