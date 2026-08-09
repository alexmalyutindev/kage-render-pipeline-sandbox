Shader "KageRP/Volume"
{
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
            Blend One One, One Zero

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Shadows.hlsl"

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
            
            half ComputeShadowAtten(float3 positionWS, float3 viewDirectionWS, half2 minMaxDepth, half facing)
            {
                const int stepsCount = 16;
                const float stepsCountRcp = 1.0f / stepsCount;
                half shadowAtten = 0.0f;
                
                if (facing > 0) // Front face
                {
                    float3 rayOrigin = TransformWorldToShadowMap(positionWS).xyz;
                    float3 rayEnd = TransformWorldToShadowMap(_WorldSpaceCameraPos.xyz + viewDirectionWS * minMaxDepth.y).xyz;
                    float3 rayDir = (rayEnd - rayOrigin) * stepsCountRcp;

                    for (int i = 0; i < stepsCount; i++)
                    {
                        rayOrigin += rayDir;
                        shadowAtten += SampleMainLightShadowMapPCF(rayOrigin);
                    }
                    shadowAtten *= stepsCountRcp;
                }
                else
                {
                    float3 rayOrigin = TransformWorldToShadowMap(_WorldSpaceCameraPos.xyz).xyz;
                    float3 rayEnd = TransformWorldToShadowMap(positionWS).xyz;
                    float3 rayDir = (rayEnd - rayOrigin) * stepsCountRcp;

                    for (int i = 0; i < stepsCount; i++)
                    {
                        rayOrigin += rayDir;
                        shadowAtten += SampleMainLightShadowMapPCF(rayOrigin);
                    }
                    shadowAtten *= stepsCountRcp;
                }

                return shadowAtten;
            }
            
            half ComputeShadowAtten2(float2 coord, float3 viewDirectionWS, half2 minMaxDepth, half selfDepth, half facing)
            {
                const int stepsCount = 8;
                const float stepsCountRcp = 1.0f / stepsCount;
                const float maxRayDist = min(selfDepth, minMaxDepth.x);
                
                float3 rayOriginWS = _WorldSpaceCameraPos.xyz;
                float3 rayEndWS = rayOriginWS + viewDirectionWS * maxRayDist;

                float3 rayOriginSM = TransformWorldToShadowMap(rayOriginWS).xyz;
                float3 rayEndSM = TransformWorldToShadowMap(rayEndWS).xyz;
                
                float3 rayDirSM = (rayEndSM - rayOriginSM) * stepsCountRcp;
                float3 currentPosSM = rayOriginSM + rayDirSM * InterleavedGradientNoise(coord, 0);

                half shadowAtten = 0.0h;
                
                for (int i = 0; i < stepsCount; i++)
                {
                    shadowAtten += SampleMainLightShadowMapPCF(currentPosSM);
                    currentPosSM += rayDirSM;
                }
                
                shadowAtten = shadowAtten * stepsCountRcp * maxRayDist;
                return facing > 0 ? -shadowAtten : shadowAtten;
            }

            half ComputeShadowAtten3(float3 positionWS, float3 viewDirectionWS, half faceDepth, half sceneDepth, half facing)
            {
                const int stepsCount = 16;
                const float stepsCountRcp = 1.0f / stepsCount;
                half shadowAtten = 0.0f;

                // Ensure the volume never marches past the opaque scene depth
                half effectiveDepth = min(faceDepth, sceneDepth);

                // Both faces march from the Camera to their respective effective surface depth.
                // This allows Blend One One to correctly subtract Front from Back: (Camera-to-Back) - (Camera-to-Front) = Volume Core.
                float3 rayOriginWS = positionWS;
                float3 rayEndWS = positionWS + viewDirectionWS * 10.0f;

                // Transform to shadow map space and march
                float3 rayOriginSM = TransformWorldToShadowMap(rayOriginWS);
                float3 rayEndSM = TransformWorldToShadowMap(rayEndWS);
                float3 rayDirSM = (rayEndSM - rayOriginSM) * stepsCountRcp;
                float3 currentPosSM = rayOriginSM;

                half currentDepth = faceDepth;
                half depthStep = 5.0f * stepsCountRcp;

                [unroll]
                for (int i = 0; i < stepsCount && currentDepth < sceneDepth; i++)
                {
                    currentPosSM += rayDirSM;
                    shadowAtten += SampleMainLightShadowMapPCF(currentPosSM);
                    currentDepth += depthStep;
                }

                shadowAtten = shadowAtten * stepsCountRcp;

                // Scale by the depth interval so the integral represents true physical volume accumulation
                shadowAtten *= effectiveDepth;

                return facing > 0 ? shadowAtten : -shadowAtten;
            }

            half4 Fragment(Varyings input, half facing : VFACE) : SV_Target
            {
                float2 screenUV = input.positionCS.xy * _RenderSizeTexel.zw;
                half2 minMaxDepth = _MinMaxDepth.Sample(sampler_LinearClamp, screenUV);
                half depth = LinearEyeDepth(input.positionCS.z, _ZBufferParams);

                half2 effectiveDepth = min(minMaxDepth, depth.xx);
                half2 thickness = facing > 0 ? -effectiveDepth : effectiveDepth;

                float3 viewDirectionVS = -input.positionVS / input.positionVS.z;
                float3 viewDirectionWS = TransformViewToWorldDir(viewDirectionVS);
                // half shadowAtten = ComputeShadowAtten(input.positionWS, viewDirectionWS, minMaxDepth, facing);

                half shadowAtten = 0.0f;
                // half shadowAtten = ComputeShadowAtten2(
                //     input.positionCS.xy, 
                //     viewDirectionWS,
                //     minMaxDepth,
                //     depth,
                //     facing
                // );

                // float3 positionVS = input.positionVS;
                // positionVS = positionVS / positionVS.z * ceil(positionVS.z);
                // float3 positionWS = TransformViewToWorld(positionVS);
                // half shadowAtten = ComputeShadowAtten3(
                //     input.positionWS, 
                //     viewDirectionWS, 
                //     depth, 
                //     minMaxDepth.y,
                //     facing
                // );

                return half4(thickness, shadowAtten, 0);
            }
            ENDHLSL
        }
    }
}