Shader "Hidden/KageRP/Bloom"
{
    Properties
    {
        _MainTex("_MainTex", 2D) = "white"
    }
    SubShader
    {
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

        float4 _MainTex_TexelSize;
        Texture2D<half3> _MainTex;
        float4 _Depth_TexelSize;
        Texture2D<float> _Depth;

        half4 _Params;
        half4 _Params2;

        #define Scatter (_Params.x)
        #define ClampMax (_Params.y)
        #define Threshold (_Params.z)
        #define ThresholdKnee (_Params.w)
        #define Spread (_Params2.x)

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

            #if UNITY_UV_STARTS_AT_TOP
            output.uv.y = 1.0f - output.uv.y;
            #endif

            output.positionCS = float4(mad(input.uv, 2.0f, -1.0f), 0.0f, 1.0f);
            return output;
        }

        half Luminance(half3 c) { return dot(c, half3(0.2126729h, 0.7151522h, 0.0721750h)); }
        half3 Sample(float2 uv) { return _MainTex.Sample(sampler_LinearClamp, uv, 0); }
        half3 Sample(float2 uv, float2 offset) { return Sample(uv + offset); }

        half3 SampleDualDown(float2 uv, float2 halfPixel)
        {
            float4 offset = float4(halfPixel.xy, -halfPixel.xy);
            float3 color = Sample(uv) * 0.5h;
            color += Sample(uv, offset.xy) * 0.125h;
            color += Sample(uv, offset.zy) * 0.125h;
            color += Sample(uv, offset.xw) * 0.125h;
            color += Sample(uv, offset.zw) * 0.125h;
            return color;
        }

        half3 SampleDualUp(float2 uv, float2 halfPixel)
        {
            half3 color = Sample(uv + float2(-halfPixel.x * 2.0f, 0.0f)).rgb;
            color += Sample(uv, float2(-halfPixel.x, halfPixel.y)).rgb * 2.0h;
            color += Sample(uv, float2(0.0f, halfPixel.y * 2.0f)).rgb;
            color += Sample(uv, float2(halfPixel.x, halfPixel.y)).rgb * 2.0h;
            color += Sample(uv, float2(halfPixel.x * 2.0f, 0.0f)).rgb;
            color += Sample(uv, float2(halfPixel.x, -halfPixel.y)).rgb * 2.0h;
            color += Sample(uv, float2(0.0f, -halfPixel.y * 2.0f)).rgb;
            color += Sample(uv, float2(-halfPixel.x, -halfPixel.y)).rgb * 2.0h;
            return color * 0.0833334h;
        }
        ENDHLSL

        Pass
        {
            Name "DualFilteringBlur Pre-filtering"

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            half3 Fragment(Varyings input) : SV_Target
            {
                half3 color = SampleDualDown(input.uv, _MainTex_TexelSize.xy * Spread);

                // Compress instead of clamp — remaps high values to a finite range
                // preserving hue and relative brightness
                half brightness = Max3(color.r, color.g, color.b); // Luminance(color);
                half compressed = brightness / (1.0h + brightness / ClampMax);
                color *= compressed / max(brightness, 1e-4h);

                // Thresholding
                half softness = clamp(brightness - Threshold + ThresholdKnee, 0.0, 2.0 * ThresholdKnee);
                softness = (softness * softness) / (4.0 * ThresholdKnee + 1e-4);
                half multiplier = max(brightness - Threshold, softness) / max(brightness, 1e-4);
                color *= multiplier;

                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DualFiltering Blur Downsampling"

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            half3 Fragment(Varyings input) : SV_Target
            {
                return SampleDualDown(input.uv, _MainTex_TexelSize.xy * Spread);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DualFiltering Blur Upsampling"

            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            half4 Fragment(Varyings input) : SV_Target
            {
                return half4(SampleDualUp(input.uv, _MainTex_TexelSize.xy * Spread), Scatter);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DualFiltering Blur Upsampling Final"

            Blend One One

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            half3 Fragment(Varyings input) : SV_Target
            {
                half3 color = SampleDualUp(input.uv, _MainTex_TexelSize.xy * Spread);
                return color * Scatter;
            }
            ENDHLSL
        }
    }
}