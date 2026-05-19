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
        #define _LightRadius (UNITY_MATRIX_M._m20)
        #define _LightColor (UNITY_MATRIX_M[1].rgb)
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

            Blend One One
            ZTest Off
            Cull Front
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"

            FRAMEBUFFER_INPUT_HALF(0); 
            FRAMEBUFFER_INPUT_HALF(1); 
            Texture2D<float> _GBuffer_Depth;

            struct Attributes
            {
                half3 positionOS : POSITION;
            };

            struct Varyings
            {
                float3 positionVS : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = input.positionOS * _LightRadius + _LightPositionWS;
                output.positionVS = TransformWorldToView(positionWS);
                output.positionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                half4 gBuffer1 = LOAD_FRAMEBUFFER_INPUT(0, input.positionCS);
                half4 gBuffer2 = LOAD_FRAMEBUFFER_INPUT(1, input.positionCS);
                half sceneDepth = _GBuffer_Depth.Load(int3(input.positionCS.xy, 0));
                if (COMPARE_DEVICE_DEPTH_CLOSER(input.positionCS.z, sceneDepth))
                {
                    return 0.0h;
                }

                sceneDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
                float3 scenePositionVS = input.positionVS.xyz / abs(input.positionVS.z) * sceneDepth;

                half3 normalVS;
                normalVS.xy = gBuffer2.xy * 2.0h - 1.0h;
                normalVS.z = sqrt(max(0.00001f, 1.0f - dot(normalVS.xy, normalVS.xy)));

                Light light;
                {
                    float lightRadius = _LightRadius;
                    float radiusSq = lightRadius * lightRadius;

                    float3 lightPositionWS = _LightPositionWS;
                    float3 lightPositionVS = TransformWorldToView(lightPositionWS);
                    float3 lightDirectionVS = lightPositionVS - scenePositionVS;

                    float distSq = dot(lightDirectionVS, lightDirectionVS);
                    float attenuation = 1.0h / dot(lightDirectionVS, lightDirectionVS);
                    float window = saturate(1.0f - (distSq / radiusSq) * (distSq / radiusSq));
                    window *= window;
                    attenuation *= window;

                    light.color = _LightColor;
                    light.direction = lightDirectionVS * rsqrt(distSq);
                    light.shadowAttenuation = 1.0h;
                    light.distanceAttenuation = attenuation;
                }
                
                InputData input_data;
                {
                    // NOTE: All computation made in ViewSpace!
                    input_data.positionWS = input.positionVS;
                    input_data.normalWS = normalVS;
                    input_data.viewDirectionWS = -SafeNormalize(scenePositionVS);
                    input_data.shadowCoord = 0.0f;
                    input_data.bakedGI = 0.0h;
                }

                MaterialData data;
                {
                    data.albedo = gBuffer1.rgb;
                    data.occlusion = gBuffer1.a;
                    data.metallic = gBuffer2.z;
                    data.roughness = gBuffer2.w;
                    data.emission = 0.0h;
                    data.normalTS = half3(0.0h, 0.0h, 1.0h);
                    data.alpha = 0.0h;
                }

                BRDFData brdf = InitBRDFData(data);
                return half4(SingleLightPBR_Opt(brdf, input_data, light) * data.occlusion, 1.0h);
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