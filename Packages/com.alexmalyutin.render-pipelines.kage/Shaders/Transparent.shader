Shader "KageRP/Transparent"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode ("Cull Mode", Float) = 2

        _BaseColor("Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Albedo", 2D) = "white" {}
        [SingleLineTex] _MetallicMap ("_MetallicMap", 2D) = "white" {}
        [SingleLineTex] _RoughnessMap ("_RoughnessMap", 2D) = "white" {}
        [SingleLineTex][Normal] _NormalMap ("_NormalMap", 2D) = "bump" {}
        [SingleLineTex] _OcclusionMap ("_OcclusionMap", 2D) = "white" {}

        _NormalScale ("_NormalScale", Float) = 1.0
        _Metallic ("_Metallic", Range(0, 1)) = 0.0
        _Roughness ("_Roughness", Range(0, 1)) = 1.0
        [HideInInspector][NonModifiableTextureData] _BRDF_LUT("_BRDF_LUT", 2D) = "black" {}
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue" = "Transparent"
        }
        LOD 100

        Cull [_CullMode]

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;
            float4 _BaseMap_ST;
            float _Metallic;
            float _Roughness;
            float _NormalScale;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "ForwardLit"
            }

            Name "ForwardLit"

            Cull [_CullMode]
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma multi_compile_fragment _ MAIN_LIGHT_SHADOW_ON

            #define OPTIMIZATION
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_MetallicMap);
            SAMPLER(sampler_MetallicMap);
            TEXTURE2D(_RoughnessMap);
            SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_OcclusionMap);
            SAMPLER(sampler_OcclusionMap);

            struct Attributes
            {
                half3 positionOS : POSITION;
                half3 normalOS : NORMAL;
                half4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                half4 tangentWS : TEXCOORD3;
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS);

                output.uv = mad(input.uv, _BaseMap_ST.xy, _BaseMap_ST.zw);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.tangentWS.xyz = TransformObjectToWorldNormal(input.tangentOS.xyz);
                output.tangentWS.w = input.tangentOS.w * GetOddNegativeScale();

                output.positionWS = positionWS;
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                albedoAlpha *= _BaseColor;

                half metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, input.uv).x;
                half roughness = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, input.uv).x;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv), _NormalScale);
                half occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).x;

                half3x3 tbn = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);
                half3 normalWS = TransformTangentToWorld(normalTS, tbn, true);

                InputData inputData;
                inputData.normalWS = normalWS;
                inputData.positionWS = input.positionWS;
                inputData.shadowCoord = TransformWorldToShadowMap(input.positionWS);
                inputData.bakedGI = SampleGI(normalWS);
                inputData.viewDirectionWS = SafeNormalize(_WorldSpaceCameraPos - input.positionWS);
                inputData.normalizedScreenUV = input.positionCS.xy * _ScreenSize.zw;

                MaterialData materialData;
                materialData.albedo = albedoAlpha.rgb;
                materialData.metallic = metallic * _Metallic;
                materialData.roughness = roughness * _Roughness;
                materialData.occlusion = occlusion;
                materialData.emission = 0.0h;
                materialData.alpha = albedoAlpha.a;
                materialData.normalTS = normalTS;

                BRDFData brdf = InitBRDFData(materialData);

                half3 color = MobilePBR(brdf, inputData);

                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint i = 0; i < pixelLightCount; i++)
                {
                    Light light = GetAdditionalLight(i, input.positionWS);
                    color += SingleLightPBR_TwoSide(brdf, inputData, light) * materialData.albedo;
                }
                return half4(color, albedoAlpha.a);
            }
            ENDHLSL
        }
    }
}