using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class GBufferPass : AbstractRenderGraphPass
    {
        private class GBufferPassData
        {
            // NOTE: Total 32 * 3 + 16 = 128 - 16
            public TextureHandle GBuffer0; // 32 bit <- [ ForwardLit + Emission ] (RGB32) <- Final HDR target
            public TextureHandle GBuffer1; // 32 bit <- [ NormalVS.xy | Metallic | Smoothness ] (R8G8B8A8)
            public TextureHandle GBuffer2; // 32 bit <- [ Albedo.rgb  | AO ] Color can be HDR
            public TextureHandle Depth; // 16 bit

            public RendererListHandle List;

            public Matrix4x4 View;
            public Matrix4x4 Proj;
        }

        // Forward + SlimGBuffer
        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            var cullingResultData = frameData.Get<CullingResultData>();
            var lightingData = frameData.Get<LightingData>();
            var gBufferData = frameData.Create<GBufferData>();

            using var builder = renderGraph.AddRasterRenderPass<GBufferPassData>("GBuffer", out var passData);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            var targetDesc = cameraData.TargetDescriptor;

            var rgbHDRDesc = new TextureDesc(targetDesc.width, targetDesc.height)
            {
                name = "GBuffer0",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGB111110Float, false),
                msaaSamples = MSAASamples.None,
            };
            passData.GBuffer0 = renderGraph.CreateTexture(rgbHDRDesc);

            var rgba32Desc = new TextureDesc(targetDesc.width, targetDesc.height)
            {
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.ARGB32, false),
            };

            rgba32Desc.name = "GBuffer1";
            passData.GBuffer1 = renderGraph.CreateTexture(rgba32Desc);

            rgba32Desc.name = "GBuffer2";
            passData.GBuffer2 = renderGraph.CreateTexture(rgba32Desc);

            var depthDesc = new TextureDesc(targetDesc.width, targetDesc.height)
            {
                name = "GBuffer_Depth",
                format = GraphicsFormat.D24_UNorm_S8_UInt,
                depthBufferBits = DepthBits.Depth24,
                msaaSamples = MSAASamples.None,
                clearBuffer = true,
            };
            passData.Depth = renderGraph.CreateTexture(depthDesc);

            gBufferData.GBuffer0 = passData.GBuffer0;
            gBufferData.GBuffer1 = passData.GBuffer1;
            gBufferData.GBuffer2 = passData.GBuffer2;
            gBufferData.Depth = passData.Depth;

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
                filteringSettings = FilteringSettings.defaultValue,
            };
            passData.List = renderGraph.CreateRendererList(rendererListDesc);
            builder.UseRendererList(passData.List);

            builder.AllowPassCulling(false);

            if (lightingData.MainLightShadowMap.IsValid())
            {
                builder.UseTexture(lightingData.MainLightShadowMap);
            }

            builder.SetRenderAttachment(passData.GBuffer0, 0);
            builder.SetRenderAttachment(passData.GBuffer1, 1);
            builder.SetRenderAttachment(passData.GBuffer2, 2);
            builder.SetRenderAttachmentDepth(passData.Depth);

            builder.AllowGlobalStateModification(true);
            builder.SetGlobalTextureAfterPass(passData.Depth, Shader.PropertyToID("_GBuffer_Depth"));
            builder.SetGlobalTextureAfterPass(passData.GBuffer1, Shader.PropertyToID("_GBuffer1"));
            builder.SetGlobalTextureAfterPass(passData.GBuffer2, Shader.PropertyToID("_GBuffer2"));

            builder.SetRenderFunc<GBufferPassData>(static (data, context) =>
            {
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                context.cmd.DrawRendererList(data.List);
            });
        }
    }
}
