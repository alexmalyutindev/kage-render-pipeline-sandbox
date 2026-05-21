Shader "Hidden/KageRP/PointLight"
{
    Properties {}
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"

        // TODO: Move to include
        #define _LightPositionWS (UNITY_MATRIX_M[0].xyz)
        #define _LightColor (UNITY_MATRIX_M[1].rgb)
        #define _LightRadius (UNITY_MATRIX_M._m20)
        #define _LightDistanceAttenuation (UNITY_MATRIX_M._m30_m31)
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "DeferredLighting"
            }

            Name "PointLight"

            // TODO: Add stencil prepass
            // Stencil
            // {
            //     Ref 2 // 0000_0010
            //     ReadMask 2
            //     Comp Equal
            // }

            Cull Front
            Blend One One
            ZTest Greater
            ZWrite Off
            ColorMask RGB

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"

            FRAMEBUFFER_INPUT_HALF(0);
            FRAMEBUFFER_INPUT_HALF(1);

            struct Attributes
            {
                half3 positionOS : POSITION;
            };

            struct Varyings
            {
                float3 positionVS : TEXCOORD0;
                float3 lightPositionVS : TEXCOORD1;
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = _LightPositionWS + input.positionOS * _LightRadius;
                output.lightPositionVS = TransformWorldToView(_LightPositionWS);
                output.positionVS = TransformWorldToView(positionWS);
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                half4 gBuffer1 = LOAD_FRAMEBUFFER_INPUT(0, input.positionCS);
                half4 gBuffer2 = LOAD_FRAMEBUFFER_INPUT(1, input.positionCS);

                GBufferData gBuffer = ReadGBuffer(gBuffer1, gBuffer2);
                float3 scenePositionVS = input.positionVS.xyz / abs(input.positionVS.z);
                scenePositionVS *= gBuffer.depth;

                Light light;
                {
                    float3 lightPositionVS = input.lightPositionVS;
                    float3 lightDirectionVS = lightPositionVS - scenePositionVS;

                    float distanceSqr = dot(lightDirectionVS, lightDirectionVS);
                    float lightAtten = rcp(distanceSqr);
                    // NOTE: GetPunctualLightDistanceAttenuation: distanceAttenuationFloat.x
                    half factor = half(distanceSqr * _LightDistanceAttenuation.x);
                    half smoothFactor = saturate(half(1.0h) - factor * factor);
                    smoothFactor = smoothFactor * smoothFactor;

                    light.color = _LightColor;
                    light.direction = lightDirectionVS * rsqrt(distanceSqr);
                    light.shadowAttenuation = 1.0h;
                    light.distanceAttenuation = lightAtten * smoothFactor;
                }

                InputData inputData;
                {
                    // NOTE: All computation made in ViewSpace!
                    inputData.positionWS = scenePositionVS;
                    inputData.normalWS = gBuffer.normalVS;
                    inputData.viewDirectionWS = -SafeNormalize(scenePositionVS);
                    inputData.shadowCoord = 0.0f;
                    inputData.bakedGI = 0.0h;
                }

                MaterialData data;
                {
                    data.albedo = gBuffer.albedo;
                    data.occlusion = gBuffer.occlusion;
                    data.metallic = gBuffer.metallic;
                    data.roughness = gBuffer.roughness;
                    data.emission = 0.0h;
                    data.normalTS = half3(0.0h, 0.0h, 1.0h);
                    data.alpha = 0.0h;
                }

                // return half4(gBuffer.depth.xxx, 1.0h);

                BRDFData brdf = InitBRDFData(data);
                half3 color = SingleLightPBR_Opt(brdf, inputData, light);
                return half4(color, 0.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "DeferredLighting Stencil"
            }

            Name "PointLight Stencil"

            Stencil
            {
                Ref 2 // 0000_0010
                ReadMask 2
                WriteMask 2
                Comp Always
                Pass Replace
            }

            Blend Off
            ColorMask 0
            ZTest Greater
            Cull Front
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"

            Texture2D<float> _GBuffer_Depth;

            struct Attributes
            {
                half3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = input.positionOS * _LightRadius + _LightPositionWS;
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                half sceneDepth = _GBuffer_Depth.Load(int3(input.positionCS.xy, 0));
                clip(sceneDepth - input.positionCS.z);
                return 0.0h;
            }
            ENDHLSL
        }
    }
}