#ifndef KAGERP_BRDFDATA
#define KAGERP_BRDFDATA

struct BRDFData
{
    half3 albedo;
    half metallic;
    half roughness;
    half occlusion;
    half3 emission;
    // TODO: Are thies properties part of BRDF data?
    half3 normalWS;
    half3 viewDirectionWS;
    half4 shadowCoord;
    half3 bakedGI;
};

#endif
