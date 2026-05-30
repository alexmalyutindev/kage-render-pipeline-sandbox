#ifndef KAGERP_TOON_LIGHTING
#define KAGERP_TOON_LIGHTING

#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/RealtimeLights.hlsl"

#ifndef FALLOFF_POWER
#define FALLOFF_POWER 0.3
#endif

#ifndef SampleFalloff
#define SampleFalloff(t) (t)
#endif

#ifndef SampleRimFalloff
#define SampleRimFalloff(t) (t)
#endif

struct ToonData
{
    half3 albedo;
    half alpha;
    half4 specularMask;
    half3 shadowColor;
    half specularPower;
};

// Overlay blend: used to composite env-map reflection onto base color
half3 OverlayBlend(half3 upper, half3 lower)
{
    half3 lowerResult = 2.0h * lower * upper;
    half3 greaterResult = 2.0h * upper * (1.0h - lower) + (2.0h * lower - 1.0h);
    return lerp(lowerResult, greaterResult, round(lower));
}

half3 ToonLighting(ToonData toonData, InputData inputData)
{
    Light mainLight = GetMainLight(inputData.positionWS, inputData.shadowCoord);

    half3 N = inputData.normalWS;
    half3 V = inputData.viewDirectionWS;
    half3 L = mainLight.direction;

    half NdotL = dot(N, L);
    half NdotV = dot(N, V);
    
    // Falloff
    float falloffU = clamp(1.0h - abs(NdotV), 0.02h, 0.98h);
    half4 falloffColor = FALLOFF_POWER * SampleFalloff(falloffU);

    float3 shadowColor = toonData.albedo * toonData.albedo;

    half3 combinedColor = lerp(toonData.albedo, shadowColor, falloffColor.r);
    combinedColor *= (1.0h + falloffColor.rgb * falloffColor.a);

    // Specular
    half specularDot = dot(N, V); // NOTE: Should be NdotH?
    half4 lighting = lit(NdotV, specularDot, toonData.specularPower);
    half3 specularColor = saturate(lighting.z) * toonData.specularMask.rgb * toonData.albedo;
    combinedColor += specularColor;

    // Reflection
    half3 reflectVector = reflect(-V, N);
    half4 encodedReflection = unity_SpecCube0.SampleLevel(samplerunity_SpecCube0, reflectVector, 0);
    half3 reflectColor = DecodeHDREnvironment(encodedReflection, unity_SpecCube0_HDR);
    reflectColor = OverlayBlend(reflectColor, combinedColor);

    combinedColor = lerp(combinedColor, reflectColor, toonData.specularMask.a);
    combinedColor *= mainLight.color; // NOTE: Here was a tint color!

    // Shadow
    half3 shadowedColor = toonData.shadowColor * combinedColor;
    half attenuation = saturate(2.0h * mainLight.shadowAttenuation - 1.0h);
    combinedColor = lerp(shadowedColor, combinedColor, attenuation);

    // Rim light
    half rimLightDot = saturate(0.5 * (NdotL + 1.0));
    falloffU = saturate(rimLightDot * falloffU);
    falloffU = SampleRimFalloff(falloffU);
    combinedColor += falloffU * toonData.albedo;

    return combinedColor;
}

#endif // KAGERP_TOON_LIGHTING
