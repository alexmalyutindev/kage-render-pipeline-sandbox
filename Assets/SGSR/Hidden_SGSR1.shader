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
        float4 _SGSR_ViewportInfo;
        Texture2D<half4> _MainTex;

        #define OperationMode (_SGSR_Params.x)
        #define EdgeSharpness (_SGSR_Params.y)
        #define InputTexture (_MainTex)

        half4 SGSRRH(float2 p) { return InputTexture.GatherRed(sampler_LinearClamp, p); }
        half4 SGSRGH(float2 p) { return InputTexture.GatherGreen(sampler_LinearClamp, p); }
        half4 SGSRBH(float2 p) { return InputTexture.GatherBlue(sampler_LinearClamp, p); }
        half4 SGSRAH(float2 p) { return InputTexture.GatherAlpha(sampler_LinearClamp, p); }
        half4 SGSRRGBH(float2 p) { return InputTexture.SampleLevel(sampler_LinearClamp, p, 0); }

        half4 SGSRH(float2 p, uint channel)
        {
            if (channel == 0) return SGSRRH(p);
            if (channel == 1) return SGSRGH(p);
            if (channel == 2) return SGSRBH(p);
            return SGSRAH(p);
        }

        #define SGSR_MOBILE
        #include "./sgsr1_mobile.hlsl"

        half4 SnapdragonGameSuperResolution(float2 uv)
        {
            half4 OutColor = half4(0, 0, 0, 1);
            SgsrYuvH(OutColor, uv, _SGSR_ViewportInfo);
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