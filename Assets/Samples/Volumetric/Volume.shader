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

            float4 _RenderSizeTexel;
            Texture2D<float> _Depth;

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 Fragment(Varyings input, half facing : VFACE) : SV_Target
            {
                float2 screenUV = input.positionCS.xy * _RenderSizeTexel.zw;
                half sceneDepth = LinearEyeDepth(_Depth.Sample(sampler_LinearClamp, screenUV), _ZBufferParams);
                half depth = LinearEyeDepth(input.positionCS.z, _ZBufferParams);

                half effectiveDepth = min(sceneDepth, depth);
                half thickness = facing > 0 ? -effectiveDepth : effectiveDepth;
                return half4(thickness, 0, 0, sceneDepth);
            }
            ENDHLSL
        }
    }
}