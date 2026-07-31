Shader "KageRP/Unlit/Transparent_6Way"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode ("Cull Mode", Float) = 2

        _BaseColor("Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Albedo", 2D) = "white" {}
        
        [Header(Six Way Lighting)]
        [SingleLineTex] _SixWayMap ("6-Way Packed Map", 2D) = "gray" {}
        _SixWayIntensity ("6-Way Intensity", Range(0, 10)) = 1.0

        [Space]
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
            float _SixWayIntensity; // Injected variable
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
            TEXTURE2D(_SixWayMap); // Injected Map
            SAMPLER(sampler_SixWayMap);
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
                half3x3 tbn = CreateTangentToWorld(input.normalWS, input.tangentWS.xyz, input.tangentWS.w);

                half4 sixWayPacked = SAMPLE_TEXTURE2D(_SixWayMap, sampler_SixWayMap, input.uv);
                float3 packedDirs = sixWayPacked.rgb * 2.0 - 1.0;
                float3 mainLightDirTS = TransformWorldToTangent(_MainLightPosition.xyz, tbn);
                half sixWayLightResponse = max(0.0h, dot(packedDirs, mainLightDirTS)) * _SixWayIntensity;
                return half4(_MainLightColor.rgb * sixWayLightResponse, sixWayPacked.a);
            }
            ENDHLSL
        }
    }
}