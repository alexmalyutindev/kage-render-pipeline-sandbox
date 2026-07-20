Shader "Hidden/KageRP/SGSR1"
{
    Properties
    {
        _MainTex("_MainTex", 2D) = "white"
    }
    SubShader
    {

        HLSLINCLUDE
        #pragma editor_sync_compilation

        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

        float4 _SGSR_Params;
        float4 _MainTex_TexelSize;
        Texture2D<half4> _MainTex;

        #define OperationMode (_SGSR_Params.x)
        #define EdgeSharpness (_SGSR_Params.y)

        half4 SGSRRGBH(float2 p) { return _MainTex.SampleLevel(sampler_LinearClamp, p, 0); }

        half4 SGSRH(float2 p, uint channel)
        {
            if (channel == 0) return _MainTex.GatherRed(sampler_PointClamp, p);
            if (channel == 1) return _MainTex.GatherGreen(sampler_PointClamp, p);
            if (channel == 2) return _MainTex.GatherBlue(sampler_PointClamp, p);
            return _MainTex.GatherAlpha(sampler_PointClamp, p);
        }

        #define SGSR_MOBILE
        #include "./sgsr1_mobile.hlsl"

        half4 SnapdragonGameSuperResolution(float2 uv)
        {
            half4 OutColor = half4(0, 0, 0, 1);
            SgsrYuvH(OutColor, uv, _MainTex_TexelSize);
            return OutColor;
        }
        ENDHLSL

        Pass
        {
            Name "SGSR1"

            Cull Off
            ZTest Off
            Blend Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings FullScreenVertex(Attributes input)
            {
                Varyings output;
                output.uv = input.uv;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                return SnapdragonGameSuperResolution(input.uv);
            }
            ENDHLSL
        }
    }
}