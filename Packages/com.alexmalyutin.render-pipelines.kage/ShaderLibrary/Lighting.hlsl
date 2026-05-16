#ifndef KAGERP_LIGHTING
#define KAGERP_LIGHTING

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SphericalHarmonics.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
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

///////////////////////////////

float3 LightingPBR_MainLight(BRDFData data)
{
    float3 N = data.normalWS;
    float3 V = data.viewDirectionWS;
    float NdotV = max(dot(N, V), 0.00001f);
    float3 baseReflection = lerp(0.04f, data.albedo, data.metallic);

    // Environmet
    float2 envBRDF = SAMPLE_TEXTURE2D_LOD(_BRDF_LUT, sampler_PointClamp, float2(NdotV, data.roughness), 0).rg;

    // TODO: Lights loop
    float3 directLighting = 0.0f;
    {
        Light mainLight = GetMainLight(data.shadowCoord);

        float3 L = mainLight.direction;
        float3 H = normalize(L + V);

        float NdotL = max(dot(N, L), 0.0001f);
        float HdotV = max(dot(H, V), 0.0);
        float NdotH = max(dot(N, H), 0.0);

        float3 lightRadiance = mainLight.color * PI;

        float D = GgxDistribution(NdotH, data.roughness); // Larger the more micro-facets aligned to H
        float G = GeomSmith(NdotV, NdotL, data.roughness); // Smaller the more micro-facets shadow
        float3 F = SchlickFresnel(HdotV, baseReflection); // Fresnel proportion of specular reflectance

        float3 specular = (D * G * F) / (4.0 * NdotV * NdotL);

        // Difuse and spec light can't be above 1.0
        // kD = 1.0 - kS  diffuse component is equal 1.0 - spec component
        float3 kD = 1.0f - F;
        // Mult kD by the inverse of metalness, only non-metals should have diffuse light
        kD *= 1.0 - data.metallic;

        directLighting += (kD * data.albedo * INV_PI + specular) * lightRadiance * NdotL;
    }

    // IBL
    float3 reflectedViewDirection = reflect(-V, N);
    float3 reflection = GlossyEnvironmentReflection(reflectedViewDirection, data.roughness, data.occlusion);

    float3 F = SchlickFresnel(NdotV, baseReflection);
    float3 specularIBL = reflection * (F * envBRDF.x + envBRDF.y);
    float3 diffuseIBL = data.albedo * SampleGI(N) * (1.0 - data.metallic);
    float3 ambient = (diffuseIBL + specularIBL) * data.occlusion;

    return ambient + directLighting + data.emission;
}

float3 LightingPBR_MainLight2(BRDFData data)
{
    float3 N = data.normalWS;
    float3 V = data.viewDirectionWS;
    float NdotV = max(dot(N, V), 0.00001f);
    float3 F0 = lerp(0.04f, data.albedo, data.metallic);

    // Environmet
    float2 envBRDF = SAMPLE_TEXTURE2D_LOD(_BRDF_LUT, sampler_PointClamp, float2(NdotV, data.roughness), 0).rg;

    float3 reflectV = reflect(-V, N);
    half mip = PerceptualRoughnessToMipmapLevel(data.roughness);
    float3 envReflection = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectV, mip).rgb;

    // TODO: Lights loop
    float3 directLighting = 0.0f;
    {
        Light mainLight = GetMainLight(data.shadowCoord);

        float3 L = mainLight.direction;
        float3 H = normalize(L + V);

        float NdotL = max(dot(N, L), 0.0001f);
        float HdotV = max(dot(H, V), 0.0);
        float NdotH = max(dot(N, H), 0.0);

        float3 lightRadiance = mainLight.color * PI;

        float D = GgxDistribution(NdotH, data.roughness); // Larger the more micro-facets aligned to H
        float G = GeomSmith(NdotV, NdotL, data.roughness); // Smaller the more micro-facets shadow
        float3 F = SchlickFresnel(HdotV, F0); // Fresnel proportion of specular reflectance

        float3 specular = (D * G * F) / (4.0 * NdotV * NdotL);

        // Difuse and spec light can't be above 1.0
        // kD = 1.0 - kS  diffuse component is equal 1.0 - spec component
        float3 kD = 1.0f - F;
        // Mult kD by the inverse of metalness, only non-metals should have diffuse light
        kD *= 1.0 - data.metallic;

        directLighting += (kD * data.albedo * INV_PI + specular) * lightRadiance * NdotL;
    }

    // IBL
    float3 F = SchlickFresnel(NdotV, F0);
    float3 specularIBL = data.occlusion * envReflection * (F * envBRDF.x + envBRDF.y);
    float3 diffuseIBL = data.albedo * SampleGI(N) * (1.0 - data.metallic);
    float3 ambient = (diffuseIBL + specularIBL) * data.occlusion;

    return ambient + directLighting + data.emission;
}

//////////////////////////////////////////////

half3 EvaluateBlinnPhongBRDF(BRDFData data)
{
    // Normalize input vectors
    half3 N = data.normalWS;
    half3 V = data.viewDirectionWS;
    half NdotV = max(dot(N, V), 0.00001f);

    // Environmet
    half2 envBRDF = SAMPLE_TEXTURE2D_LOD(_BRDF_LUT, sampler_PointClamp, float2(NdotV, data.roughness), 0).rg;

    half3 reflectV = reflect(-V, N);
    half mip = PerceptualRoughnessToMipmapLevel(data.roughness);
    half3 envReflection = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectV, mip).rgb;

    half3 diffuseColor = lerp(data.albedo, 0.0, data.metallic);
    half3 F0 = lerp(0.04f, data.albedo, data.metallic);
    half specularPower = 512.0 * (1.0 - data.roughness);
    half scpecularNormalization = (1.04 - data.roughness) * (specularPower + 8.0) / 8.0;

    half3 directLighting = 0.0h;
    // TODO: Light loop
    {
        Light mainLight = GetMainLight(data.shadowCoord);
        half3 L = mainLight.direction;
        half3 H = normalize(V + L);

        // Dot products
        half NdotL = saturate(dot(N, L));
        half NdotH = saturate(dot(N, H));

        half specularTerm = scpecularNormalization * pow(NdotH, specularPower);
        half3 specColor = F0;

        // === Light contribution ===
        half3 diffuse = diffuseColor * mainLight.color * NdotL;
        half3 specular = specColor * mainLight.color * specularTerm;

        // === Combine with occlusion and emissive ===
        directLighting += (diffuse + specular) * data.occlusion + data.emission;
    }

    // IBL
    half3 F = SchlickFresnel(NdotV, F0);
    half3 specularIBL = data.occlusion * envReflection * (F * envBRDF.x + envBRDF.y);
    // TODO: Move bakedGI into brdfData.
    half3 diffuseIBL = data.albedo * data.bakedGI * (1.0 - data.metallic);
    half3 ambient = (diffuseIBL + specularIBL) * data.occlusion;

    return directLighting + ambient;
}

/////////////////////////////////////

half3 SingleLightPBR(BRDFData brdfData, Light light)
{
    half3 F0 = lerp(0.04h, brdfData.albedo, brdfData.metallic);

    half3 N = brdfData.normalWS;
    half3 V = brdfData.viewDirectionWS;

    half3 diffuseColor = lerp(brdfData.albedo, 0.0h, brdfData.metallic);
    float specularPower = exp2(10.0h * (1.0h - brdfData.roughness) + 1.0h); // 512.0h * (1.0h - roughness);
    float specularNormalization = (specularPower + 2.0h) / 8.0h;
    // (1.04h - roughness) * (specularPower + 8.0) / 8.0;

    half3 L = light.direction;
    half3 H = normalize(V + L);
    half NdotL = max(0.0h, dot(N, L));
    float NdotH = max(0.0h, dot(N, H));

    float specularTerm = specularNormalization * pow(NdotH, specularPower);
    half3 specular = F0 * light.color * specularTerm;

    half3 diffuse = diffuseColor * light.color * NdotL;
    half3 directLighting = max(0.0h, diffuse + specular) * brdfData.occlusion;

    return directLighting * light.attenuation;
}

half3 MobilePBR(BRDFData brdfData)
{
    half3 F0 = lerp(0.04h, brdfData.albedo, brdfData.metallic);

    half3 N = brdfData.normalWS;
    half3 V = brdfData.viewDirectionWS;
    half NdotV = max(0.0h, dot(N, V));

    // Environment
    float2 envBRDF = GetEnvBRDF(NdotV, brdfData.roughness);
    half3 reflectV = reflect(-V, N);
    half4 encodedReflection = SampleEncodedEnvironmentReflection(reflectV, brdfData.roughness);

    half3 diffuseColor = lerp(brdfData.albedo, 0.0h, brdfData.metallic);
    float specularPower = exp2(10.0h * (1.0h - brdfData.roughness) + 1.0h); // 512.0h * (1.0h - roughness);
    float specularNormalization = (specularPower + 2.0h) / 8.0h;
    // (1.04h - roughness) * (specularPower + 8.0) / 8.0;

    // Direct
    Light mainLight = GetMainLight(brdfData.shadowCoord);

    half3 L = mainLight.direction;
    half3 H = normalize(V + L);
    half NdotL = max(0.0h, dot(N, L));
    float NdotH = max(0.0h, dot(N, H));

    float specularTerm = specularNormalization * pow(NdotH, specularPower);
    half3 specular = F0 * mainLight.color * specularTerm;

    half3 diffuse = diffuseColor * mainLight.color * NdotL;
    half3 directLighting = max(0.0h, diffuse + specular) * brdfData.occlusion;

    // IBL
    half3 F = SchlickFresnel(NdotV, F0);
    half3 envReflection = DecodeHDREnvironment(encodedReflection, unity_SpecCube0_HDR);
    half3 specularIBL = envReflection * (F * envBRDF.x + envBRDF.y);
    half3 diffuseIBL = (1.0h - brdfData.metallic) * brdfData.albedo * brdfData.bakedGI;
    half3 ambient = (diffuseIBL + specularIBL) * brdfData.occlusion;

    return directLighting * mainLight.attenuation + ambient + brdfData.emission;
}

#endif
