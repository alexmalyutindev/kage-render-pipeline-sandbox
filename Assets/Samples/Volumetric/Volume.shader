Shader "KageRP/Volume"
{
    Properties
    {
        _Density("Density", Float) = 1.0
    }
    SubShader
    {
        Pass
        {
            Tags
            {
                "LightMode" = "Volume"
            }

            Cull Off
            ZWrite Off
            ZTest Off
            Blend One One, One One

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Shadows.hlsl"

            float _Density;
            float4 _RenderSizeTexel;
            Texture2D<float2> _MinMaxDepth;

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 positionVS : TEXCOORD1;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);

                output.positionWS = positionWS;
                output.positionVS = TransformWorldToView(positionWS);
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half2 ComputeShadowAttenuation(float2 coord, float3 viewDirectionWS, half2 minMaxDepth, half selfDepth, half facing)
            {
                const float maxDistance = 10.0f;
                const int stepsCount = 8;
                const float stepsCountRcp = 1.0f / stepsCount;

                half2 maxRayDist = min(maxDistance, minMaxDepth);
                half noise = InterleavedGradientNoise(coord, 0);

                // March a single ray based entirely on the MAX depth bound
                float3 rayOriginWS = _WorldSpaceCameraPos.xyz;
                float3 rayEndWS = rayOriginWS + viewDirectionWS * maxRayDist.y;

                float3 rayOriginSM = TransformWorldToShadowMap(rayOriginWS).xyz;
                float3 rayEndSM = TransformWorldToShadowMap(rayEndWS).xyz;

                float3 rayDirSM = (rayEndSM - rayOriginSM) * stepsCountRcp;
                
                // Calculate the single physical world-space distance of each step
                half distanceStep = maxRayDist.y * stepsCountRcp;

                float3 currentPosSM = rayOriginSM + rayDirSM * noise;
                half currentDistance = noise * distanceStep;

                half2 shadowAtten = 0.0h;

                UNITY_UNROLL
                for (int stepIndex = 0; stepIndex < stepsCount; stepIndex++)
                {
                    if (currentDistance >= selfDepth)
                        break;

                    half shadowSample = SampleMainLightShadowMapPCF(currentPosSM);
                    if (currentDistance < maxRayDist.x) shadowAtten.x += shadowSample;
                    shadowAtten.y += shadowSample;

                    currentPosSM += rayDirSM;
                    currentDistance += distanceStep;
                }

                // NOTE: Tricky lerp to white!
                // if (currentDistance >= maxDistance && facing < 0) shadowAtten += 1.0h;

                // Multiply by the uniform physical step size to complete the Riemann sum integral
                shadowAtten *= distanceStep * 0.25h;

                return facing > 0 ? -shadowAtten : shadowAtten;
            }

            half4 Fragment(Varyings input, half facing : VFACE) : SV_Target
            {
                float2 screenUV = input.positionCS.xy * _RenderSizeTexel.zw;
                half2 minMaxDepth = _MinMaxDepth.Sample(sampler_LinearClamp, screenUV);
                half selfdepth = LinearEyeDepth(input.positionCS.z, _ZBufferParams);

                half2 effectiveDepth = min(minMaxDepth, selfdepth.xx);
                half2 thickness = facing > 0 ? -effectiveDepth : effectiveDepth;

                // float3 viewDirectionVS = -input.positionVS / input.positionVS.z;
                // float3 viewDirectionWS = TransformViewToWorldDir(viewDirectionVS);
                
                float3 viewDirectionWS = normalize(input.positionWS - _WorldSpaceCameraPos.xyz);
                half2 shadowAttenuation = ComputeShadowAttenuation(
                    input.positionCS.xy, 
                    viewDirectionWS,
                    minMaxDepth,
                    selfdepth,
                    facing
                );

                return half4(thickness, shadowAttenuation);
            }
            ENDHLSL
        }
    }
}