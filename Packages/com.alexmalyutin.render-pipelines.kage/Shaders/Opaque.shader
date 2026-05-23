Shader "KageRP/Opaque"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode ("Cull Mode", Float) = 2
        [Toggle(_ALPHA_TEST)] _AlphaTest ("Alpha Test", Float) = 0

        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap ("Albedo", 2D) = "white" {}

        _NormalScale ("_NormalScale", Float) = 1.0
        [SingleLineTex][Normal] _NormalMap ("_NormalMap", 2D) = "bump" {}

        [Space]
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        _Roughness ("Roughness", Range(0, 1)) = 1.0
        [SingleLineTex] _MetallicMap ("Metallic Map", 2D) = "white" {}
        [SingleLineTex] _RoughnessMap ("Roughness Map", 2D) = "white" {}
        [SingleLineTex(_OCCLUSION_MAP)] _OcclusionMap ("Occlusion Map", 2D) = "white" {}

        [Space]
        _Parallax("Parallax", Range(0.0, 0.08)) = 0.04
        [SingleLineTex(_HEIGHT_MAP)] _HeightMap ("_HeightMap", 2D) = "black" {}
        
        _StencilBit("_StencilBit", Integer) = 0
        [HideInInspector][NonModifiableTextureData] _BRDF_LUT("_BRDF_LUT", 2D) = "black" {}
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "Queue" = "Geometry"
        }
        LOD 100

        Cull [_CullMode]

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;
            float4 _BaseMap_ST;
            float _Metallic;
            float _Roughness;
            float _NormalScale;
            float _Parallax;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "GBuffer"
            }

            Name "GBuffer"
            
            Stencil
            {
                Ref [_StencilBit] // 0000_0001
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma multi_compile_fragment _ MAIN_LIGHT_SHADOW_ON
            #pragma multi_compile_fragment _ SSAO_ON
            #pragma shader_feature_local_fragment _ALPHA_TEST
            #pragma shader_feature_local_fragment _OCCLUSION_MAP
            #pragma shader_feature_local_fragment _HEIGHT_MAP

            #define OPTIMIZATION
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/ParallaxOclussionMapping.hlsl"

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
            TEXTURE2D(_HeightMap);
            SAMPLER(sampler_HeightMap);

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
                float4 postionCS : SV_POSITION;
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
                output.postionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            GBuffer Fragment(Varyings input)
            {
                half3 viewDirectionWS = SafeNormalize(_WorldSpaceCameraPos - input.positionWS);
                half3x3 tbn = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);

                #if defined(_HEIGHT_MAP)
                half3 viewDirectionTS = TransformWorldToTangent(viewDirectionWS, tbn);
                ApplyPerPixelDisplacement(_HeightMap, sampler_HeightMap, viewDirectionTS, _Parallax, input.uv);
                #endif

                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                albedoAlpha *= _BaseColor;

                #if defined(_ALPHA_TEST)
                clip(albedoAlpha.a - 0.5h);
                #endif

                half metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, input.uv).x;
                half roughness = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, input.uv).x;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv), _NormalScale);

                #if defined(_OCCLUSION_MAP)
                half occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).x;
                #else
                half occlusion = 1.0h;
                #endif

                half3 normalWS = TransformTangentToWorld(normalTS, tbn, true);

                InputData inputData;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = viewDirectionWS;
                inputData.shadowCoord = TransformWorldToShadowMap(input.positionWS);
                inputData.bakedGI = SampleGI(normalWS);
                inputData.normalizedScreenUV = input.postionCS.xy * _ScreenSize.zw;

                MaterialData materialData;
                materialData.albedo = albedoAlpha.rgb;
                materialData.metallic = metallic * _Metallic;
                materialData.roughness = roughness * _Roughness;
                materialData.occlusion = occlusion * GetSSAO(inputData.normalizedScreenUV);
                materialData.normalTS = normalTS;
                materialData.alpha = 1.0h;
                materialData.emission = 0.0h;

                BRDFData brdf = InitBRDFData(materialData);
                half3 color = MobilePBR(brdf, inputData);
                return OutputGBuffer(color, materialData, inputData);
            }
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            Name "ShadowCaster"

            Cull Front
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                half3 positionOS : POSITION;
                half3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 postionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;

                output.uv = mad(input.uv, _BaseMap_ST.xy, _BaseMap_ST.zw);

                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 positionWS = TransformObjectToWorld(input.positionOS);
                output.postionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, -normalWS, -_MainLightPosition.xyz)
                );
                output.postionCS = ApplyShadowClamping(output.postionCS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                return 0.0h;
            }
            ENDHLSL
        }
    }
}