Shader "KageRP/Lit"
{
    Properties
    {
        _MainTex ("Albedo", 2D) = "white" {}
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
            "RenderType"="Opaque"
        }
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float _Metallic;
            float _Roughness;
            float _NormalScale;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "GBuffer"
            }

            Name "GBuffer"

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #define OPTIMIZATION
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"


            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
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
                float4 postionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS);

                output.uv = mad(input.uv, _MainTex_ST.xy, _MainTex_ST.zw);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.tangentWS.xyz = TransformObjectToWorldNormal(input.tangentOS.xyz);
                output.tangentWS.w = input.tangentOS.w * GetOddNegativeScale();

                output.positionWS = positionWS;
                output.postionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            GBuffer Fragment(Varyings input)
            {
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                clip(albedoAlpha.a - 0.5h);

                half metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, input.uv).x;
                half roughness = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, input.uv).x;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv), _NormalScale);
                half occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).x;

                half3x3 tbn = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);
                half3 normalWS = TransformTangentToWorld(normalTS, tbn, true);

                BRDFData data;
                data.albedo = albedoAlpha.rgb;
                data.normalWS = normalWS;
                data.metallic = metallic * _Metallic;
                data.roughness = roughness * _Roughness;
                data.occlusion = occlusion;
                data.viewDirectionWS = normalize(input.positionWS - _WorldSpaceCameraPos);
                data.bakedGI = SampleGI(normalWS);
                data.shadowCoord = TransformWorldToShadowMap(input.positionWS);
                data.emission = 0.0h;

                half3 color = MobilePBR(data);
                return OutputGBuffer(color, data);
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
            
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            struct Attributes
            {
                half3 positionOS : POSITION;
                half3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                float4 postionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;

                output.uv = mad(input.uv, _MainTex_ST.xy, _MainTex_ST.zw);

                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 positionWS = TransformObjectToWorld(input.positionOS);
                positionWS -= _MainLightPosition.xyz * 0.02f;
                positionWS -= output.normalWS * 0.02f;
                output.postionCS = TransformWorldToHClip(positionWS);
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