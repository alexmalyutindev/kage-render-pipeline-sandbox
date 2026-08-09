Shader "Hidden/KageRP/VolumeProcessing"
{
    Properties
    {
        _MainTex("_MainTex", 2D) = "white"
    }
    SubShader
    {

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

        float4 _MainTex_TexelSize;
        Texture2D<float> _MainTex;
        float4 _MinMaxDepth_TexelSize;
        Texture2D<half2> _MinMaxDepth;
        Texture2D<half2> _VarianceDepth;

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

        Varyings FullScreenVertexProcedural(uint vertexID : SV_VertexID)
        {
            Varyings output;

            float2 ndc;
            ndc.x = (vertexID == 2) ? 3.0f : -1.0f;
            ndc.y = (vertexID == 1) ? -3.0f : 1.0f;

            output.positionCS = float4(ndc, UNITY_NEAR_CLIP_VALUE, 1.0f);
            output.uv = mad(ndc, 0.5f, 0.5f);

            #if UNITY_UV_STARTS_AT_TOP
            output.uv.y = 1.0f - output.uv.y;
            #endif

            return output;
        }

        float3 ReconstructPositionVS(float2 uv, float eyeDepth)
        {
            float2 ndc = mad(uv, 2.0f, -1.0f);
            return float3(
                ndc.x / unity_CameraProjection[0][0],
                ndc.y / unity_CameraProjection[1][1],
                -1.0f
            ) * eyeDepth;
        }
        ENDHLSL

        Pass
        {
            Name "Upscale"

            Cull Off
            Blend One One

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            Texture2D<float> _Depth;
            Texture2D<float> _LowDepth;

            half4 Fragment(Varyings input) : SV_Target
            {
                float sceneDepth = LinearEyeDepth(_Depth.Sample(sampler_LinearClamp, input.uv), _ZBufferParams);

                half4 depths = _LowDepth.GatherRed(sampler_PointClamp, input.uv); // _MainTex.GatherAlpha(sampler_PointClamp, input.uv);
                depths = LinearEyeDepth(depths, _ZBufferParams);

                half4 thicknesses = _MainTex.GatherRed(sampler_PointClamp, input.uv);
                thicknesses = max(0.0h, thicknesses);

                half2 pixelUV = input.uv * _MainTex_TexelSize.zw - 0.5f;
                half2 f = frac(pixelUV);
                half4 bilinearWeights = half4(f.xy, 1.0f - f.xy);
                bilinearWeights = bilinearWeights.zxxz * bilinearWeights.yyww;
                half4 depthWeights = exp2(-50.0f * abs(sceneDepth - depths)) + 0.0001f;

                half4 weights = depthWeights * bilinearWeights;
                weights /= dot(weights, 1.0f);

                half thickness = dot(thicknesses, weights);
                return 1.0f - exp2(-thickness);
            }
            ENDHLSL
        }
    }
}