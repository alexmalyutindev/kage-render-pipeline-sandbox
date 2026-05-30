Shader "KageRP/Toon/Opaque"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode ("Cull Mode", Float) = 2

        _BaseColor ("Main Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow Color", Color) = (0.8, 0.8, 1, 1)
        _SpecularPower ("Specular Power", Float) = 20
        _EdgeThickness ("Outline Thickness", Float) = 1

        _BaseMap ("Diffuse", 2D) = "white" {}
        [SingleLineTex] _FalloffSampler ("Falloff Control", 2D) = "white" {}
        [SingleLineTex] _RimLightSampler ("RimLight Control", 2D) = "white" {}
        [SingleLineTex(_SPECULAR_MAP)] _SpecularReflectionSampler ("Specular (RGB) ReflectionMask (A)", 2D) = "white" {}
        [SingleLineTex(_NORMAL_MAP)][Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }
        LOD 100

        Cull [_CullMode]

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"

        // Constants
        #define FALLOFF_POWER 0.3

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;
            float4 _BaseMap_ST;
            float3 _ShadowColor;
            float _NormalScale;
            float _SpecularPower;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        TEXTURE2D(_FalloffSampler);
        TEXTURE2D(_RimLightSampler);

        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);

        TEXTURE2D(_SpecularReflectionSampler);
        SAMPLER(sampler_SpecularReflectionSampler);

        #define SampleFalloff(t) (_FalloffSampler.Sample(sampler_LinearClamp, float2(t, 0.25f)))
        #define SampleRimFalloff(t) (_RimLightSampler.Sample(sampler_LinearClamp, float2(t, 0.25f)).x)
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/ToonLighting.hlsl"

        // Feathered cel step — the spine of every hard-edge effect
        half CelStep(half v, half threshold, half feather)
        {
            return smoothstep(threshold - feather, threshold + feather, v);
        }

        half3 SampleNormal(TEXTURE2D_PARAM(tex, samp), float2 uv, float scale)
        {
            return UnpackNormalScale(SAMPLE_TEXTURE2D(tex, samp, uv), scale);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "ForwardLit"
            }

            ZWrite On
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma multi_compile _ MAIN_LIGHT_SHADOW_ON
            #pragma shader_feature_fragment _NORMAL_MAP
            #pragma shader_feature_fragment _SPECULAR_MAP

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                half4 tangentWS : TEXCOORD3;
                half3 viewDirectionWS : TEXCOORD4;
                half shadowAttenuation : TEXCOORD5;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(positionWS);
                output.positionWS = positionWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.tangentWS.xyz = TransformObjectToWorldNormal(input.tangentOS.xyz);
                output.tangentWS.w = input.tangentOS.w * GetOddNegativeScale();
                output.viewDirectionWS = GetWorldSpaceViewDirection(positionWS);

                output.shadowAttenuation = GetMainLightShadow(positionWS, TransformWorldToShadowMap(positionWS));
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                half4 diffSamplerColor = _BaseMap.Sample(sampler_BaseMap, input.uv) * _BaseColor;
                clip(diffSamplerColor.a - 0.5h); // TODO: keyword

                half3 normalTS = SampleNormal(_NormalMap, sampler_NormalMap, input.uv, _NormalScale);
                half3x3 tbn = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);
                half3 normalWS = TransformTangentToWorld(normalTS, tbn, false);

                #if defined(_SPECULAR_MAP)
                half4 specularMask = _SpecularReflectionSampler.Sample(sampler_SpecularReflectionSampler, input.uv.xy);
                #else
                half4 specularMask = half4(1.0h, 1.0h, 1.0h, 0.0h);
                #endif

                ToonData toonData;
                toonData.albedo = diffSamplerColor.rgb;
                toonData.alpha = 1.0h;
                toonData.shadowColor = _ShadowColor.rgb;
                toonData.specularMask = specularMask;
                toonData.specularPower = _SpecularPower;

                InputData inputData;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = input.viewDirectionWS;
                inputData.shadowCoord = TransformWorldToShadowMap(input.positionWS);
                inputData.normalizedScreenUV = 0.0h; // TODO
                inputData.bakedGI = 0.0h; // TODO
                half3 toonLighting = ToonLighting(toonData, inputData);

                return half4(toonLighting, 1.0h);
            }
            ENDHLSL
        }

        UsePass "KageRP/Opaque/SHADOWCASTER"
    }

    FallBack "Hidden/InternalErrorShader"
}