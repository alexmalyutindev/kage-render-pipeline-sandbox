#ifndef KAGERP_GLOBALILLUMINATION
#define KAGERP_GLOBALILLUMINATION

#include "UnityInput.hlsl"
#include "BRDFData.hlsl"

Texture2D<half2> _BRDF_LUT;

// Samples SH L0, L1 and L2 terms
half3 SampleSH(half3 normalWS)
{
    // LPPV is not supported in Ligthweight Pipeline
    real4 SHCoefficients[7];
    SHCoefficients[0] = unity_SHAr;
    SHCoefficients[1] = unity_SHAg;
    SHCoefficients[2] = unity_SHAb;
    SHCoefficients[3] = unity_SHBr;
    SHCoefficients[4] = unity_SHBg;
    SHCoefficients[5] = unity_SHBb;
    SHCoefficients[6] = unity_SHC;

    return max(half3(0, 0, 0), SampleSH9(SHCoefficients, normalWS));
}

half3 SampleGI(half3 normalWS)
{
    return SampleSH(normalWS);
}

float2 GetEnvBRDF(half NdotV, half roughness)
{
    return SAMPLE_TEXTURE2D_LOD(_BRDF_LUT, sampler_PointClamp, half2(NdotV, roughness), 0).rg;
}

half3 GlossyEnvironmentReflection(half3 reflectVector, half perceptualRoughness, half occlusion)
{
    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
    return SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip).rgb * occlusion;
}

half4 SampleEncodedEnvironmentReflection(half3 reflectVector, half roughness)
{
    half mip = PerceptualRoughnessToMipmapLevel(roughness);
    return SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
}

//////////////////////////////////////////////

// F0 - reflection
half3 SchlickFresnel(half HdotV, half3 F0)
{
    #if !defined(OPTIMIZATION)
    return F0 + (1.0 - F0) * pow(1.0 - HdotV, 5.0);
    #else
    return F0 + (1.0h - F0) * pow(2.0h, (-5.55473h * HdotV - 6.98316h) * HdotV);
    #endif
}

half3 MobileGI(BRDFData brdfData)
{
    half roughness = brdfData.roughness; // saturate(1.0h - brdfData.smoothness);
    half3 F0 = lerp(0.04h, brdfData.albedo, brdfData.metallic);

    half3 N = brdfData.normalWS;
    half3 V = brdfData.viewDirectionWS;
    half NdotV = max(0.0h, dot(N, V));

    // Environment
    float2 envBRDF = GetEnvBRDF(NdotV, roughness);
    half3 reflectV = reflect(-V, N);
    half4 encodedReflection = SampleEncodedEnvironmentReflection(reflectV, roughness);

    // IBL
    half3 F = SchlickFresnel(NdotV, F0);
    half3 envReflection = DecodeHDREnvironment(encodedReflection, unity_SpecCube0_HDR);
    half3 specularIBL = envReflection * (F * envBRDF.x + envBRDF.y);
    half3 diffuseIBL = (1.0h - brdfData.metallic) * brdfData.albedo * brdfData.bakedGI;
    half3 ambient = (diffuseIBL + specularIBL) * brdfData.occlusion;

    return ambient;
}

#endif
