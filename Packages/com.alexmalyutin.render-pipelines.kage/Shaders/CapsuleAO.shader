Shader "KageRP/CapsuleAO"
{
    Properties
    {
        _Intensity ("_Intensity", Range(0.0, 1.0)) = 0.5
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue" = "Transparent"
        }
        LOD 100

        Pass
        {
            Tags
            {
                "LightMode" = "KageForward"
            }

            Name "ForwardLit"

            Cull Front
            ZWrite Off
            ZTest Greater
            Blend One One
            Blend DstColor Zero

            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMatrial)
                float _Intensity;
            CBUFFER_END

            Texture2D<half> _GBuffer_Depth;
            Texture2D<half4> _GBuffer1;

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
                float3 positionWS = TransformObjectToWorld(input.positionOS);
                output.positionVS = TransformWorldToView(positionWS);
                output.postionCS = TransformWorldToHClip(positionWS);
                return output;
            }

            half sdVerticalCapsule(half3 p, half h, half r)
            {
                p.y -= clamp(p.y, 0.0, h);
                return length(p) - r;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                int3 screenCoord = int3(floor(input.postionCS.xy), 0);
                half sceneDepth = _GBuffer_Depth.Load(screenCoord).x;

                sceneDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
                float3 positionVS = input.positionVS / abs(input.positionVS.z) * sceneDepth;
                float3 positionOS = TransformWorldToObject(TransformViewToWorld(positionVS));
                positionOS.y += 0.5f;
                half occlusion = saturate(2.0h * sdVerticalCapsule(positionOS, 1.0h, 0.0h));
                return lerp(occlusion * occlusion, 1.0h, _Intensity * _Intensity);
            }
            ENDHLSL
        }
    }
}