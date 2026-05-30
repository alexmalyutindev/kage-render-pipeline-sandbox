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

        // Feathered cel step — the spine of every hard-edge effect
        half CelStep(half v, half threshold, half feather)
        {
            return smoothstep(threshold - feather, threshold + feather, v);
        }

        half3 SampleNormals(TEXTURE2D_PARAM(tex, samp), float2 uv, float scale)
        {
            return UnpackNormalScale(SAMPLE_TEXTURE2D(tex, samp, uv), scale);
        }

        half3 ResolveNormal(half3 normalWS, half4 tangentWS, float2 uv, bool useNormalMap)
        {
            if (useNormalMap)
            {
                half3 normalTS = SampleNormals(_NormalMap, sampler_NormalMap, uv, _NormalScale);
                half3x3 tbn = CreateTangentToWorld(normalWS, tangentWS.xyz, tangentWS.w);
                return TransformTangentToWorld(normalTS, tbn, true);
            }
            return SafeNormalize(normalWS);
        }

        half3 OverlayBlend(half3 upper, half3 lower)
        {
            half3 lowerResult = 2.0h * lower * upper;
            half3 greaterResult = 2.0h * upper * (1.0h - lower) + (2.0h * lower - 1.0h);
            return lerp(lowerResult, greaterResult, round(lower));
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

            #pragma multi_compile_fragment _ MAIN_LIGHT_SHADOW_ON
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
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                half4 diffSamplerColor = _BaseMap.Sample(sampler_BaseMap, input.uv) * _BaseColor;
                // TODO: keyword
                clip(diffSamplerColor.a - 0.5h);

                Light mainLight = GetMainLight(input.positionWS, TransformWorldToShadowMap(input.positionWS));

                half3 normalTS = SampleNormals(_NormalMap, sampler_NormalMap, input.uv, _NormalScale);
                half3x3 tbn = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);
                half3 normalWS = TransformTangentToWorld(normalTS, tbn, false);

                half NdotL = dot(normalWS, mainLight.direction);
                half NdotV = dot(normalWS, input.viewDirectionWS);

                // Falloff. Convert the angle between the normal and the camera direction into a lookup for the gradient
                half falloffU = clamp(1.0h - abs(NdotV), 0.02h, 0.98h);
                half4 falloffSamplerColor = FALLOFF_POWER * _FalloffSampler.Sample(sampler_LinearClamp, float2(falloffU, 0.25f));

                half3 shadowColor = diffSamplerColor.rgb * diffSamplerColor.rgb;

                half3 combinedColor = lerp(diffSamplerColor.rgb, shadowColor, falloffSamplerColor.r);
                combinedColor *= (1.0 + falloffSamplerColor.rgb * falloffSamplerColor.a);

                // Specular
                // Use the eye vector as the light vector
                #if defined(_SPECULAR_MAP)
                half4 reflectionMaskColor = _SpecularReflectionSampler.Sample(sampler_SpecularReflectionSampler, input.uv.xy);
                #else
                half4 reflectionMaskColor = half4(1.0h, 1.0h, 1.0h, 0.0h);
                #endif

                half specularDot = dot(normalWS, input.viewDirectionWS.xyz); // NOTE: Should be NdotH?
                half4 lighting = lit(NdotV, specularDot, _SpecularPower);
                half3 specularColor = saturate(lighting.z) * reflectionMaskColor.rgb * diffSamplerColor.rgb;
                combinedColor += specularColor;

                // Reflection
                half3 reflectVector = reflect(-input.viewDirectionWS.xyz, normalWS).xzy;
                half2 sphereMapCoords = 0.5 * (half2(1.0, 1.0) + reflectVector.xy);
                half4 encodedReflection = unity_SpecCube0.SampleLevel(samplerunity_SpecCube0, reflectVector, 0);
                half3 reflectColor = DecodeHDREnvironment(encodedReflection, unity_SpecCube0_HDR);
                reflectColor = OverlayBlend(reflectColor, combinedColor);

                combinedColor = lerp(combinedColor, reflectColor, reflectionMaskColor.a);
                combinedColor *= _BaseColor.rgb * mainLight.color;
                float opacity = diffSamplerColor.a * _BaseColor.a;

                // Cast shadows
                shadowColor = _ShadowColor.rgb * combinedColor;
                half attenuation = saturate(2.0 * mainLight.shadowAttenuation * smoothstep(-0.2, 0.2, NdotL) - 1.0);
                combinedColor = lerp(shadowColor, combinedColor, attenuation);

                // Rimlight
                half rimlightDot = saturate(0.5 * (NdotL + 1.0));
                falloffU = saturate(rimlightDot * falloffU);
                falloffU = _RimLightSampler.Sample(sampler_LinearClamp, float2(falloffU, 0.25f)).r;
                half3 lightColor = diffSamplerColor.rgb; // * 2.0;
                combinedColor += falloffU * lightColor;

                return half4(combinedColor, 1.0h);
            }
            ENDHLSL
        }

        UsePass "KageRP/Opaque/SHADOWCASTER"
    }

    FallBack "Hidden/InternalErrorShader"
}