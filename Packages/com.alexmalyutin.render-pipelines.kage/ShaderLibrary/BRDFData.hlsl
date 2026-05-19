#ifndef KAGERP_BRDFDATA
#define KAGERP_BRDFDATA

struct BRDFData
{
    half3 albedo;           // base color (non-metal diffuse / metal F0 tint)
    half3 F0;               // precomputed: lerp(0.04, albedo, metallic)
    half3 diffuseColor;     // precomputed: albedo * (1 - metallic)
    half  metallic;
    half  roughness;
    half  occlusion;
    half3 emission;
};

#endif
