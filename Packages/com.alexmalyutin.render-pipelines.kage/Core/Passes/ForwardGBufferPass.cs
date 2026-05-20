using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class ForwardGBufferPass : AbstractRenderGraphPass
    {
        private readonly FilteringSettings _filteringSettings;
        public readonly MSAASamples MSAASamples = MSAASamples.None;
        [Space] public bool UseRenderScale = false;
        [Range(0.1f, 2.0f)] public float RenderSacle = 0.75f;

        public ForwardGBufferPass()
        {
            // BUG: Ctor won't called on settings change! Creation will happens once! 
            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.opaque;
        }

        private class GBufferPassData
        {
            public TextureHandle GBuffer0; // 32 bit <- [ ForwardLit + Emission ] (RGB111110Float) <- Final HDR target
            public TextureHandle GBuffer1; // 32 bit <- [ Albedo.rgb  | AO ] (R8G8B8A8)
            public TextureHandle GBuffer2; // 64 bit <- [ NormalVS.xy | LinearDepth | Metallic & Roughness ] (ARGBHalf)
            public TextureHandle Depth; // 32 bit <- [ Depth24 | Stencil8 ] (D24_UNorm_S8_UInt)

            public RendererListHandle List;

            public Vector4 ScreenSize;
            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public bool MainLightShadowOn;
        }

        // Forward + SlimGBuffer
        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            var cullingResultData = frameData.Get<CullingResultData>();
            var lightingData = frameData.Get<LightingData>();
            var gBufferData = frameData.Create<GBufferData>();

            using var builder = renderGraph.AddRasterRenderPass<GBufferPassData>("Forward+GBuffer", out var passData);
            var targetDesc = cameraData.CameraBackBufferDescriptor;

            var width = UseRenderScale ? Mathf.RoundToInt(targetDesc.width * RenderSacle) : targetDesc.width;
            var height = UseRenderScale ? Mathf.RoundToInt(targetDesc.height * RenderSacle) : targetDesc.height;

            passData.ScreenSize = new Vector4(
                width, height,
                1.0f / width, 1.0f / height
            );
            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            var gBuffer0Desc = new TextureDesc(width, height)
            {
                name = "GBuffer0",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGB111110Float, false),
                msaaSamples = MSAASamples,
                filterMode = FilterMode.Bilinear,
            };
            var gBuffer1Desc = new TextureDesc(width, height)
            {
                name = "GBuffer1",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.ARGB32, false),
                memoryless = RenderTextureMemoryless.Color,
                msaaSamples = MSAASamples,
            };
            var gBuffer2Desc = new TextureDesc(width, height)
            {
                name = "GBuffer2",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.ARGBHalf, false),
                memoryless = RenderTextureMemoryless.Color,
                msaaSamples = MSAASamples,
            };
            var depthDesc = new TextureDesc(width, height)
            {
                name = "GBuffer_Depth",
                format = GraphicsFormat.D24_UNorm_S8_UInt,
                depthBufferBits = DepthBits.Depth24,
                msaaSamples = MSAASamples,
                clearBuffer = true,
            };

            passData.GBuffer0 = renderGraph.CreateTexture(gBuffer0Desc);
            passData.GBuffer1 = renderGraph.CreateTexture(gBuffer1Desc);
            passData.GBuffer2 = renderGraph.CreateTexture(gBuffer2Desc);
            passData.Depth = renderGraph.CreateTexture(depthDesc);

            gBufferData.GBuffer0 = passData.GBuffer0;
            gBufferData.GBuffer1 = passData.GBuffer1;
            gBufferData.GBuffer2 = passData.GBuffer2;
            gBufferData.Depth = passData.Depth;

            cameraData.CameraActiveColor = passData.GBuffer0;
            cameraData.CameraActiveDepth = passData.Depth;

            var shaderPassName = new ShaderTagId("GBuffer");
            var drawingSettings = new DrawingSettings(shaderPassName, new SortingSettings(cameraData.Camera))
            {
                mainLightIndex = lightingData.MainLightIndex,
                perObjectData = PerObjectData.LightData
                    | PerObjectData.ReflectionProbes
                // | PerObjectData.ReflectionProbeData
                // | PerObjectData.LightProbe,
            };

            var rendererListDesc = new RendererListParams()
            {
                cullingResults = cullingResultData.CullingResult,
                drawSettings = drawingSettings,
                filteringSettings = _filteringSettings,
            };
            passData.List = renderGraph.CreateRendererList(rendererListDesc);
            builder.UseRendererList(passData.List);

            builder.AllowPassCulling(false);

            if (lightingData.MainLightShadowMap.IsValid())
            {
                builder.UseTexture(lightingData.MainLightShadowMap);
                passData.MainLightShadowOn = true;
            }
            else
            {
                passData.MainLightShadowOn = false;
            }

            builder.SetRenderAttachment(passData.GBuffer0, 0);
            builder.SetRenderAttachment(passData.GBuffer1, 1);
            builder.SetRenderAttachment(passData.GBuffer2, 2);
            builder.SetRenderAttachmentDepth(passData.Depth);

            builder.AllowGlobalStateModification(true);
            builder.SetRenderFunc<GBufferPassData>(static (data, context) =>
            {
                if (data.MainLightShadowOn) context.cmd.EnableShaderKeyword("MAIN_LIGHT_SHADOW_ON");
                else context.cmd.DisableShaderKeyword("MAIN_LIGHT_SHADOW_ON");

                context.cmd.SetGlobalVector("_ScreenSize", data.ScreenSize);
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                context.cmd.DrawRendererList(data.List);
            });
        }
    }
}
