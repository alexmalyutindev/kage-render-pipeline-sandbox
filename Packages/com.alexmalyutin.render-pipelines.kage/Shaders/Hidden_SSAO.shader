Shader "Hidden/KageRP/SSAO"
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
        float4 _Depth_TexelSize;
        Texture2D<float> _Depth;

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

        float3 ReconstructPositionVS(float2 uv, float eyeDepth)
        {
            float2 ndc = mad(uv, 2.0f, -1.0f);
            return float3(
                ndc.x / unity_CameraProjection[0][0],
                ndc.y / unity_CameraProjection[1][1],
                -1.0f
            ) * eyeDepth;
        }

        float3 GetPostionVS(float2 uv)
        {
            float depth = LinearEyeDepth(_Depth.Sample(sampler_LinearClamp, uv), _ZBufferParams);
            return ReconstructPositionVS(uv, depth);
        }
        ENDHLSL

        Pass
        {
            Name "Blur"

            Cull Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment
            float2 _Direction;
            half Fragment(Varyings input) : SV_Target
            {
                const int kernelSize = 3;
                const half kernelSizeRcp = 1.0h / half(kernelSize);
                const half halfKernel = (half(kernelSize) - 1.0h) * 0.5h;

                half result = 0.0h;
                for (int i = 0; i < kernelSize; i++)
                {
                    // TODO: Use depth guided blur!
                    float2 offset = (i - halfKernel) * _Direction * _MainTex_TexelSize.xy * 1.5f;
                    result += _MainTex.Sample(sampler_LinearClamp, input.uv + offset);
                }

                return result * kernelSizeRcp;
            }
            ENDHLSL
        }

        Pass
        {
            Name "GTAO"

            Cull Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            #define GTAO_RADIUS 0.75h
            #define GTAO_THICKNESS 0.1h

            half IntegrateArc_UniformWeight(half2 horizions)
            {
                half2 arc = 1.0h - cos(horizions);
                return arc.x + arc.y;
            }

            half Fragment(Varyings input) : SV_Target
            {
                const float renderScale = 0.25f;
                float centerDepth = LinearEyeDepth(_Depth.Sample(sampler_LinearClamp, input.uv), _ZBufferParams);

                float uvRadius = clamp(
                    renderScale * GTAO_RADIUS * unity_CameraProjection[0][0] / max(centerDepth, 1e-4) * 0.5f,
                    _Depth_TexelSize.x * 2.0f, 0.2f
                );

                float noise = InterleavedGradientNoise(floor(input.positionCS.xy), 0);
                float noise2 = InterleavedGradientNoise(floor(input.positionCS.xy), 1);

                half occlusion = 0.0h;
                float3 positionVS = ReconstructPositionVS(input.uv, centerDepth);
                float3 viewDirectionVS = -normalize(positionVS);

                const int sliceCount = 4;
                const int stepsCount = 4;
                const float sliceCountRcp = 1.0f / sliceCount;
                const float stepsCountRcp = 1.0f / stepsCount;

                UNITY_UNROLL for (int sliceIndex = 0; sliceIndex < sliceCount; sliceIndex++)
                {
                    float angle = (sliceIndex + noise) * sliceCountRcp * PI;
                    float2 sliceDir;
                    sincos(angle, sliceDir.y, sliceDir.x);
                    sliceDir *= uvRadius * stepsCountRcp * float2(1.0, _Depth_TexelSize.z * _Depth_TexelSize.y);

                    half2 horizon = half2(-1.0f, -1.0f);
                    UNITY_UNROLL for (int stepIndex = 0; stepIndex < stepsCount; stepIndex++)
                    {
                        float2 uvOffset = (stepIndex + 1.0f) * sliceDir;
                        float3 h1 = GetPostionVS(input.uv + uvOffset) - positionVS;
                        float3 h2 = GetPostionVS(input.uv - uvOffset) - positionVS;

                        float2 h1h2 = float2(dot(h1, h1), dot(h2, h2));
                        float2 h1h2Length = rsqrt(h1h2);

                        float2 falloff = saturate(h1h2 * (2.0f / max(GTAO_RADIUS * GTAO_RADIUS, 0.001f)));
                        float2 currentHorizon = float2(dot(h1, viewDirectionVS), dot(h2, viewDirectionVS)) * h1h2Length;
                        horizon.xy = (currentHorizon.xy > horizon.xy) ? 
                            lerp(currentHorizon, horizon, falloff) : 
                            lerp(currentHorizon.xy, horizon.xy, GTAO_THICKNESS);
                    }

                    half n = 0.0; // TODO: ???
                    horizon = acos(clamp(horizon, -1, 1));
                    horizon.x = n + max(-horizon.x - n, -HALF_PI);
                    horizon.y = n + min(horizon.y - n, HALF_PI);

                    occlusion += saturate(IntegrateArc_UniformWeight(horizon));
                }

                return pow(saturate(occlusion * sliceCountRcp), 4.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "HBAO"
            Cull Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            half GetRaySin(float3 positionVS, float3 rayVS, float3 viewDiretionVS, float radius)
            {
                float3 delta = rayVS - positionVS;
                float dist2 = dot(delta, delta);
                float lenRcp = rsqrt(dist2);
                float atten = saturate(1.0h - sqrt(dist2) / radius);
                return (half)(delta.z * lenRcp * atten);

                // NOTE: Adaptive bias.
                float sinE = delta.z * lenRcp;
                float sinBias = dot(normalize(delta), -viewDiretionVS);
                return (half)(saturate(sinE - sinBias) * atten);
            }

            half Fragment(Varyings input) : SV_Target
            {
                half centerDepth = LinearEyeDepth(_Depth.Sample(sampler_LinearClamp, input.uv), _ZBufferParams);
                centerDepth -= 0.02h;

                float _Radius = 0.25f * 0.5f;
                half _AngleBias = 0.05h;
                half sinBias = sin(_AngleBias);

                float uvRadius = clamp(
                    _Radius * unity_CameraProjection[0][0] / max(centerDepth, 1e-4) * 0.5,
                    _Depth_TexelSize.x * 2.0, 0.2
                );

                float noise = InterleavedGradientNoise(floor(input.positionCS.xy), 0);

                half visibility = 0.0h;
                float3 positionVS = ReconstructPositionVS(input.uv, centerDepth);
                float3 viewDirectionVS = -normalize(positionVS);

                const float sliceCount = 4.0f;
                const float stepsCount = 4.0f;
                const float sliceCountRcp = 1.0f / sliceCount;
                const float stepsCountRcp = 1.0f / stepsCount;

                for (float alpha = 0.0f; alpha < PI; alpha += PI * sliceCountRcp)
                {
                    half2 sin2 = sinBias.xx;
                    float2 ray2d;
                    sincos(alpha + PI * sliceCountRcp * noise, ray2d.y, ray2d.x);
                    ray2d *= uvRadius * stepsCountRcp * float2(1.0, _Depth_TexelSize.z * _Depth_TexelSize.y);

                    #if defined(HBAO)
                    for (float stepIndex = 0.0f; stepIndex < stepsCount; stepIndex++)
                    {
                        float2 offset = (stepIndex + 1.0f) * ray2d;

                        float depthL = _Depth.Sample(sampler_LinearClamp, input.uv + offset);
                        float depthR = _Depth.Sample(sampler_LinearClamp, input.uv - offset);

                        depthL = LinearEyeDepth(depthL, _ZBufferParams);
                        depthR = LinearEyeDepth(depthR, _ZBufferParams);

                        float3 rayVS_l = ReconstructPositionVS(input.uv + offset, depthL);
                        float3 rayVS_r = ReconstructPositionVS(input.uv - offset, depthR);
                        sin2.x = max(sin2.x, GetRaySin(positionVS, rayVS_l, viewDirectionVS, _Radius));
                        sin2.y = max(sin2.y, GetRaySin(positionVS, rayVS_r, viewDirectionVS, _Radius));
                    }

                    visibility += saturate(sin2.x - sinBias) + saturate(sin2.y - sinBias);
                    #else

                    // TODO: This is part from my other GI project, need to complete it
                    float2 prevHorizon = 0.0h;
                    for (float stepIndex = 0.0f; stepIndex < stepsCount; stepIndex++)
                    {
                        float2 offset = (stepIndex + 1.0f) * ray2d;
                        float depth_l = _Depth.Sample(sampler_LinearClamp, input.uv - offset);
                        float depth_r = _Depth.Sample(sampler_LinearClamp, input.uv + offset);

                        depth_l = LinearEyeDepth(depth_l, _ZBufferParams);
                        depth_r = LinearEyeDepth(depth_r, _ZBufferParams);

                        float3 rayVS_l = ReconstructPositionVS(input.uv - offset, depth_l);
                        float3 rayVS_r = ReconstructPositionVS(input.uv + offset, depth_r);

                        half VdotR;
                        half horizon;

                        VdotR = dot(normalize(rayVS_l - positionVS), viewDirectionVS);
                        horizon = FastACos(-VdotR) * INV_PI;
                        visibility += clamp(horizon - prevHorizon.x, 0.0h, 1.0f / (2.0h + stepIndex));
                        prevHorizon.x = max(prevHorizon.x, horizon);

                        VdotR = dot(normalize(rayVS_r - positionVS), viewDirectionVS);
                        horizon = FastACos(-VdotR) * INV_PI;
                        visibility += clamp(horizon - prevHorizon.y, 0.0h, 1.0f / (2.0h + stepIndex));
                        prevHorizon.y = max(prevHorizon.y, horizon);
                    }
                    #endif
                }

                visibility *= 0.5f * sliceCountRcp;
                return 1.0h - saturate(visibility);
            }
            ENDHLSL
        }
    }
}
