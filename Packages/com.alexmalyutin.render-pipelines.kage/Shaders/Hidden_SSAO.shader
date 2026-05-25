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
            // float depth = _MinMaxDepth.Sample(sampler_LinearClamp, uv);
            float2 moments = SAMPLE_TEXTURE2D_LOD(_VarianceDepth, sampler_LinearClamp, uv, 0).xy;
            float depth = moments.x + sqrt(max(0.0, moments.y - moments.x * moments.x));
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
                const half halfKernel = (half(kernelSize) - 1.0h) * 0.5h;

                half centerDepth = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv).y;

                half result = 0.0h;
                half totalWeight = 0.0h;
                for (int i = 0; i < kernelSize; i++)
                {
                    // TODO: Use depth guided blur!
                    float2 offset = (i - halfKernel) * _Direction * _MainTex_TexelSize.xy * 1.33f;
                    half sample = _MainTex.Sample(sampler_LinearClamp, input.uv + offset);
                    half depth = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv + offset).y;
                    half weight = exp2(-20.0h * abs(centerDepth - depth));
                    result += sample * weight;
                    totalWeight += weight;
                }

                return result / totalWeight;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Gen MinMaxDepth"

            Cull Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment
            half2 Fragment(Varyings input) : SV_Target
            {
                float2 minMaxDepth = float2(HALF_MAX, -HALF_MAX);
                for (int y = 0; y < 2; y++)
                {
                    for (int x = 0; x < 2; x++)
                    {
                        float4 depths = _MainTex.Gather(
                            sampler_LinearClamp,
                            input.uv + _MainTex_TexelSize.xy * 2.0f * float2(x, y)
                        );
                        depths = LinearEyeDepth(depths, _ZBufferParams);

                        float minDepth = min(min(depths.x, depths.y), min(depths.z, depths.w));
                        float maxDepth = max(max(depths.x, depths.y), max(depths.z, depths.w));
                        minMaxDepth.x = min(minMaxDepth.x, minDepth);
                        minMaxDepth.y = max(minMaxDepth.y, maxDepth);
                    }
                }
                return minMaxDepth;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Gen VarianceDepth"

            Cull Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment
            float2 Fragment(Varyings input) : SV_Target
            {
                float mean = 0.0h;
                float meanSq = 0.0h;

                const float2 offsets[4] = {
                    float2(-1.0f, -1.0f),
                    float2(1.0f, -1.0f),
                    float2(-1.0f, 1.0f),
                    float2(1.0f, 1.0f)
                };

                UNITY_UNROLL for (int i = 0; i < 4; i++)
                {
                    float4 depths = _MainTex.Gather(sampler_PointClamp, input.uv + _MainTex_TexelSize.xy * offsets[i]);
                    depths = LinearEyeDepth(depths, _ZBufferParams);
                    mean += dot(depths, 0.0625h); // E[x]
                    meanSq += dot(depths * depths, 0.0625h); // E[x²]
                }
                return float2(mean, meanSq);
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

            float4 _GTAO_Params;

            #define GTAO_RADIUS (_GTAO_Params.x)
            #define GTAO_THICKNESS (_GTAO_Params.y)

            half IntegrateArc_UniformWeight(half2 horizions)
            {
                half2 arc = 1.0h - cos(horizions);
                return arc.x + arc.y;
            }

            half Fragment(Varyings input) : SV_Target
            {
                const float renderScale = 0.25f;
                float centerDepth = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv).x;

                float uvRadius = clamp(
                    renderScale * GTAO_RADIUS * unity_CameraProjection[0][0] / max(centerDepth, 1e-4) * 0.5f,
                    _MinMaxDepth_TexelSize.x * 2.0f, 0.2f
                );

                float angleNoise = InterleavedGradientNoise(floor(input.positionCS.xy), 0);
                float2 coords = frac(floor(input.positionCS.xy) * 0.5f) * 0.5f;
                float stepNoise = coords.x + coords.y;

                half occlusion = 0.0h;
                float3 positionVS = ReconstructPositionVS(input.uv, centerDepth);
                float3 viewDirectionVS = -normalize(positionVS);

                const int sliceCount = 3;
                const int stepsCount = 3;
                const float sliceCountRcp = 1.0f / sliceCount;
                const float stepsCountRcp = 1.0f / stepsCount;

                UNITY_UNROLL for (int sliceIndex = 0; sliceIndex < sliceCount; sliceIndex++)
                {
                    float angle = (sliceIndex + angleNoise) * sliceCountRcp * PI;
                    float2 sliceDir;
                    sincos(angle, sliceDir.y, sliceDir.x);
                    sliceDir *= uvRadius * stepsCountRcp * float2(1.0, _MinMaxDepth_TexelSize.z * _MinMaxDepth_TexelSize.y);

                    half2 horizon = half2(-1.0f, -1.0f);
                    UNITY_UNROLL for (int stepIndex = 0; stepIndex < stepsCount; stepIndex++)
                    {
                        float2 uvOffset = (stepIndex + 1.0f + stepNoise) * sliceDir;
                        float3 h1 = GetPostionVS(input.uv + uvOffset) - positionVS;
                        float3 h2 = GetPostionVS(input.uv - uvOffset) - positionVS;

                        float2 h1h2 = float2(dot(h1, h1), dot(h2, h2));
                        float2 h1h2Length = rsqrt(h1h2);

                        float2 falloff = saturate(h1h2 * (2.0f / max(GTAO_RADIUS * GTAO_RADIUS, 0.001f)));
                        float2 currentHorizon = float2(dot(h1, viewDirectionVS), dot(h2, viewDirectionVS)) * h1h2Length;
                        horizon.xy = (currentHorizon.xy > horizon.xy)
                             ? lerp(currentHorizon, horizon, falloff)
                             : lerp(currentHorizon.xy, horizon.xy, GTAO_THICKNESS);
                    }

                    half n = 0.0; // TODO: ???
                    horizon = acos(clamp(horizon, -1, 1));
                    horizon.x = n + max(-horizon.x - n, -HALF_PI);
                    horizon.y = n + min(horizon.y - n, HALF_PI);

                    occlusion += saturate(IntegrateArc_UniformWeight(horizon));
                }

                return Pow4(saturate(occlusion * sliceCountRcp));
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
                half centerDepth = LinearEyeDepth(_MinMaxDepth.Sample(sampler_LinearClamp, input.uv), _ZBufferParams);
                centerDepth -= 0.02h;

                float _Radius = 0.25f * 0.5f;
                half _AngleBias = 0.05h;
                half sinBias = sin(_AngleBias);

                float uvRadius = clamp(
                    _Radius * unity_CameraProjection[0][0] / max(centerDepth, 1e-4) * 0.5,
                    _MinMaxDepth_TexelSize.x * 2.0, 0.2
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
                    ray2d *= uvRadius * stepsCountRcp * float2(1.0, _MinMaxDepth_TexelSize.z * _MinMaxDepth_TexelSize.y);

                    #if defined(HBAO)
                    for (float stepIndex = 0.0f; stepIndex < stepsCount; stepIndex++)
                    {
                        float2 offset = (stepIndex + 1.0f) * ray2d;

                        float depthL = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv + offset);
                        float depthR = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv - offset);

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
                        float depth_l = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv - offset);
                        float depth_r = _MinMaxDepth.Sample(sampler_LinearClamp, input.uv + offset);

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