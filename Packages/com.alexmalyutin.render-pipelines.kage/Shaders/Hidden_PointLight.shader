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
            //     Ref 1
            //     Comp Equal
            // }

            Blend One One
            ZTest Greater
            Cull Front
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"
            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Lighting.hlsl"

            Texture2D<half4> _GBuffer1;
            Texture2D<half4> _GBuffer2;
            Texture2D<half> _GBuffer_Depth;

            struct Attributes
            {
                half3 positionOS : POSITION;
            };

            struct Varyings
            {
                float3 positionVS : TEXCOORD0;
                float4 postionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = input.positionOS * _LightRadius + _LightPositionWS;
                output.positionVS = TransformWorldToView(positionWS);
                output.postionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                int3 screenCoord = int3(floor(input.postionCS.xy), 0);
                half sceneDepth = _GBuffer_Depth.Load(screenCoord).x;
                half4 gBuffer1 = _GBuffer1.Load(screenCoord);
                half4 gBuffer2 = _GBuffer2.Load(screenCoord);

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

                BRDFData data;
                {
                    data.albedo = gBuffer1.rgb;
                    data.metallic = gBuffer1.z;
                    data.roughness = gBuffer2.w;
                    data.occlusion = gBuffer2.a;
                    data.normalWS = normalVS; // NOTE: All computation made in ViewSpace!
                    data.viewDirectionWS = -SafeNormalize(scenePositionVS);

                    data.shadowCoord = 0.0h;
                    data.bakedGI = 0.0h;
                    data.emission = 0.0h;
                }

                return half4(SingleLightPBR(data, light), 1.0h);
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
                Ref 1
                Comp Always
                Pass Replace
            }

            Blend Off
            ColorMask 0
            ZTest LEqual
            Cull Back
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                half3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 postionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = input.positionOS * _LightRadius + _LightPositionWS;
                output.postionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                return 0.0h;
            }
            ENDHLSL
        }
    }
}