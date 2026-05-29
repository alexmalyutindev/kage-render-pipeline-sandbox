Shader "Hidden/KageRP/DeferredLighting"
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
        float4 _LightColor;
        float4 _LightPositionWS;
        float4 _LightDirectionWS;
        // Precomputed data: (1.0f / rangeSq, 0.25f, cosRangeRcp, -cosOuter * cosRangeRcp)
        float4 _LightAttenuation;
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "DeferredStencil"
            }

            Name "Deferred Stencil"

            // Rendering deferred lights using Stencil culling algorithm
            // ref. https://kayru.org/articles/deferred-stencil/
            Stencil
            {
                Ref [_DeferredLight_StencilMask]
                ReadMask [_DeferredLight_StencilMask]
                WriteMask [_DeferredLight_StencilMask]

                Comp Always
                Pass Keep
                Fail Keep

                // Mark pixels where front faces fail depth
                ZFail Replace
            }

            ColorMask 0

            Cull Back
            Blend Off
            ZWrite Off
            ZTest LEqual

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
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS);
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                return 0.0h;
            }
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "DeferredLighting"
            }

            Name "Deferred Lighting"

            // Rendering deferred lights using Stencil culling algorithm
            // ref. https://kayru.org/articles/deferred-stencil/
            Stencil
            {
                Ref 0 // 0000_0000
                ReadMask [_DeferredLight_StencilMask]
                WriteMask [_DeferredLight_StencilMask]
                Comp Equal
                Pass Replace
                Fail Replace
            }

            Blend One One
            ColorMask RGB

            Cull Front
            ZWrite Off
            ZTest GEqual

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
                float3 lightPositionWS : TEXCOORD1;
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.lightPositionWS = _LightPositionWS.xyz;
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
                float3 scenePositionWS = TransformViewToWorld(scenePositionVS);

                Light light;
                {
                    float3 lightVector = input.lightPositionWS - scenePositionWS;
                    float distanceSqr = dot(lightVector, lightVector);
                    half3 lightDirectionWS = half3(lightVector * rsqrt(distanceSqr));
                    half3 spotDirection = normalize(_LightDirectionWS.xyz);

                    light.color = _LightColor.rgb;
                    light.direction = lightDirectionWS;
                    light.shadowAttenuation = 1.0h;
                    light.distanceAttenuation = DistanceAttenuation(distanceSqr, _LightAttenuation.xy);
                    light.distanceAttenuation *= AngleAttenuation(spotDirection, lightDirectionWS, _LightAttenuation.zw);
                }

                InputData inputData;
                {
                    inputData.positionWS = scenePositionWS;
                    inputData.normalWS = TransformViewToWorldNormal(gBuffer.normalVS);
                    inputData.viewDirectionWS = GetWorldSpaceViewDirection(scenePositionWS);
                    inputData.shadowCoord = 0.0f;
                    inputData.bakedGI = 0.0h;
                    inputData.normalizedScreenUV = 0.0h;
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

                BRDFData brdf = InitBRDFData(data);
                half3 color = SingleLightPBR(brdf, inputData, light);
                return half4(color, 0.0h);
            }
            ENDHLSL
        }
    }
}