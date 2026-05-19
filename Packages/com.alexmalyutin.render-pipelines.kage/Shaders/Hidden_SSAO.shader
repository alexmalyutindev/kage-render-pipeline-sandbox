Shader "Hidden/KageRP/SSAO"
{
    SubShader
    {
        Pass
        {
            Name "SSAO"

            Cull Off

            HLSLPROGRAM
            #pragma vertex FullScreenVertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

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

            float3 ReconstructViewPos(float2 uv, float eyeDepth)
            {
                float2 ndc = uv * 2.0 - 1.0;
                return float3(
                    ndc.x / unity_CameraProjection[0][0],
                    ndc.y / unity_CameraProjection[1][1],
                    -1.0
                ) * eyeDepth;
            }

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
                float3 positionVS = ReconstructViewPos(input.uv, centerDepth);
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

                        float3 rayVS_l = ReconstructViewPos(input.uv + offset, depthL);
                        float3 rayVS_r = ReconstructViewPos(input.uv - offset, depthR);
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

                        float3 rayVS_l = ReconstructViewPos(input.uv - offset, depth_l);
                        float3 rayVS_r = ReconstructViewPos(input.uv + offset, depth_r);

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