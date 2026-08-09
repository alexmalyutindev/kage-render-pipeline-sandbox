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
        Texture2D<half4> _MainTex;
        float4 _MinMaxDepth_TexelSize;
        Texture2D<half2> _MinMaxDepth;

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
            Name "MinMaxDepthQuarterRes"

            Cull Off
            ZWrite Off
            ZTest Always

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            Texture2D<float> _Depth;
            float4 _Depth_TexelSize;

            half2 Fragment(Varyings input) : SV_Target
            {
                // 4 Gather operations cover a 4x4 pixel footprint efficiently.
                // input.uv is at the center of the 4x4 block. We offset by 1 source texel per quadrant.
                float2 offset = _Depth_TexelSize.xy;

                float4 d0 = _Depth.GatherRed(sampler_PointClamp, input.uv + float2(-offset.x, -offset.y));
                float4 d1 = _Depth.GatherRed(sampler_PointClamp, input.uv + float2(offset.x, -offset.y));
                float4 d2 = _Depth.GatherRed(sampler_PointClamp, input.uv + float2(-offset.x, offset.y));
                float4 d3 = _Depth.GatherRed(sampler_PointClamp, input.uv + float2(offset.x, offset.y));

                d0 = LinearEyeDepth(d0, _ZBufferParams);
                d1 = LinearEyeDepth(d1, _ZBufferParams);
                d2 = LinearEyeDepth(d2, _ZBufferParams);
                d3 = LinearEyeDepth(d3, _ZBufferParams);

                // Vectorized min/max reduction
                float4 minD = min(min(d0, d1), min(d2, d3));
                float4 maxD = max(max(d0, d1), max(d2, d3));

                // Final component reduction
                float minDepth = min(min(minD.x, minD.y), min(minD.z, minD.w));
                float maxDepth = max(max(maxD.x, maxD.y), max(maxD.z, maxD.w));

                return half2(minDepth, maxDepth);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Upscale"

            Cull Off
            Blend One One

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            Texture2D<float> _Depth;
            
            // Henyey-Greenstein Phase Function
            half ComputePhaseHG(half cosTheta, half g)
            {
                half g2 = g * g;
                half denom = 1.0h + g2 - 2.0h * g * cosTheta;
                return (1.0h - g2) / (12.56637h * denom * sqrt(denom)); // 4 * PI ≈ 12.56637
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                float sceneDepth = LinearEyeDepth(_Depth.Sample(sampler_LinearClamp, input.uv), _ZBufferParams);

                half4 minDepths = _MinMaxDepth.GatherRed(sampler_PointClamp, input.uv);
                half4 maxDepths = _MinMaxDepth.GatherGreen(sampler_PointClamp, input.uv);

                half4 minThicknesses = _MainTex.GatherRed(sampler_PointClamp, input.uv);
                half4 maxThicknesses = _MainTex.GatherGreen(sampler_PointClamp, input.uv);
                half4 minShadowAttens = _MainTex.GatherBlue(sampler_PointClamp, input.uv);
                half4 maxShadowAttens = _MainTex.GatherAlpha(sampler_PointClamp, input.uv);

                minThicknesses = max(0.0h, minThicknesses);
                maxThicknesses = max(0.0h, maxThicknesses);

                minShadowAttens = saturate(minShadowAttens);
                maxShadowAttens = saturate(maxShadowAttens);

                half4 depthDelta = max(maxDepths - minDepths, 0.0001h);
                half4 zWeights = saturate((sceneDepth - minDepths) / depthDelta);

                half4 thicknesses = lerp(minThicknesses, maxThicknesses, zWeights);
                half4 shadowAttens = lerp(minShadowAttens, maxShadowAttens, zWeights);

                half2 pixelUV = input.uv * _MainTex_TexelSize.zw - 0.5f;
                half2 f = frac(pixelUV);

                half4 bilinearWeights = half4(f.xy, 1.0f - f.xy);
                bilinearWeights = bilinearWeights.zxxz * bilinearWeights.yyww;

                half4 depthDist = max(0.0h, max(minDepths - sceneDepth, sceneDepth - maxDepths));
                half4 depthWeights = exp2(-50.0f * depthDist) + 0.0001f;

                half4 weights = depthWeights * bilinearWeights;
                weights /= dot(weights, 1.0f);

                half thickness = dot(thicknesses, weights);
                half shadowAtten = dot(shadowAttens, weights);
                half transmittance = 1.0f - exp2(-50.0h * thickness);
                
                float3 positionWS = ComputeWorldSpacePosition(input.uv, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP);
                float3 viewDirection = normalize(positionWS - _WorldSpaceCameraPos.xyz);
                float3 lightDirection = _MainLightPosition.xyz; 
                half cosTheta = dot(viewDirection, lightDirection);
                half g = 0.6h; 
                half phase = ComputePhaseHG(cosTheta, g);

                return transmittance * shadowAtten * phase;
            }
            ENDHLSL
        }
    }
}