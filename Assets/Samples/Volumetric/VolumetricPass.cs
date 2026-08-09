using System;
using Rendering.KageRP;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;

namespace Samples.Volumetric
{
    [Serializable]
    public class VolumetricPass : AbstractRenderGraphPass
    {
        public Material VolumeProcessing;

        private readonly FilteringSettings _filteringSettings;
        private ShaderTagId _shaderPassName;

        public VolumetricPass()
        {
            // BUG: Ctor won't called on settings change! Creation will happens once! 
            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.opaque;
        }

        public override void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline)
        {
            base.Setup(in asset, in pipeline);
            _shaderPassName = new ShaderTagId("Volume");
        }

        private class PassData
        {
            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public RendererListHandle List;
            public Vector4 RenderSizeTexel;
            public TextureHandle Transmittance;
        }
        
        private class UpscaleData
        {
            public Material Material;

            public TextureHandle Transmittance;
            public TextureHandle Depth;
            public TextureHandle LowDepth;
            public TextureHandle Target;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            var cullingResultData = frameData.Get<CullingResultData>();
            var lightingData = frameData.Get<LightingData>();
            var gBufferData = frameData.Get<GBufferData>();
            
            var persistentFrameData = frameData.Get<PersistentFrameData>();
            var frameBufferData = persistentFrameData.Context.Get<PrevFrameBufferData>();


            var downscaleFactor = 4.0f;
            var renderDesc = gBufferData.GBuffer0.GetDescriptor(renderGraph);
            var width = Mathf.CeilToInt(renderDesc.width / downscaleFactor);
            var height = Mathf.CeilToInt(renderDesc.height / downscaleFactor);

            var desc = new TextureDesc(width, height)
            {
                name = "_TransmittanceBuffer",
                format = GraphicsFormatUtility.GetGraphicsFormat(TextureFormat.RGBAHalf, false),
                clearBuffer = true,
                clearColor = Color.clear
            };
            var transmittance = renderGraph.CreateTexture(desc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>(nameof(VolumetricPass), out var passData))
            {
                builder.AllowPassCulling(false);

                passData.RenderSizeTexel = new Vector4(desc.width, desc.height, 1.0f / desc.width, 1.0f / desc.height);
                passData.View = cameraData.Camera.worldToCameraMatrix;
                passData.Proj = cameraData.Camera.projectionMatrix;

                var drawingSettings = new DrawingSettings(_shaderPassName, new SortingSettings(cameraData.Camera))
                {
                    mainLightIndex = lightingData.MainLightIndex,
                };

                var rendererListDesc = new RendererListParams()
                {
                    cullingResults = cullingResultData.CullingResult,
                    drawSettings = drawingSettings,
                    filteringSettings = _filteringSettings,
                };
                passData.List = renderGraph.CreateRendererList(rendererListDesc);
                builder.UseRendererList(passData.List);

                builder.UseTexture(frameBufferData.GetFrameDepth(renderGraph));

                passData.Transmittance = transmittance;

                builder.AllowGlobalStateModification(true);
                builder.SetRenderAttachment(passData.Transmittance, 0, AccessFlags.WriteAll);
                builder.SetRenderFunc<PassData>(static (data, context) =>
                {
                    context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                    context.cmd.ClearRenderTarget(RTClearFlags.Color, Color.black, 0.0f, 0);
                    context.cmd.SetGlobalVector("_RenderSizeTexel", data.RenderSizeTexel);
                    context.cmd.DrawRendererList(data.List);
                });
            }

            using (var builder = renderGraph.AddUnsafePass<UpscaleData>("Volume.Upscale", out var passData))
            {
                passData.Material = VolumeProcessing;

                passData.Transmittance = transmittance;
                builder.UseTexture(passData.Transmittance);

                var lowDepthDesc = new TextureDesc(width, height)
                {
                    name = "_LowDepth",
                    format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RFloat, false),
                };
                passData.LowDepth = builder.CreateTransientTexture(lowDepthDesc);
                builder.UseTexture(passData.LowDepth);

                passData.Depth = frameBufferData.GetFrameDepth(renderGraph);
                builder.UseTexture(passData.Depth);

                passData.Target = gBufferData.GBuffer0;
                builder.UseTexture(passData.Target, AccessFlags.Write);

                builder.SetRenderFunc<UpscaleData>(static (data, context) =>
                {
                    var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                    cmd.Blit(data.Depth, data.LowDepth);

                    cmd.SetGlobalTexture("_Depth", data.Depth);
                    cmd.SetGlobalTexture("_LowDepth", data.LowDepth);
                    cmd.Blit(data.Transmittance, data.Target, data.Material, 0);
                });
            }
        }
    }
}