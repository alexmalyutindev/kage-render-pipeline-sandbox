using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class ForwardOpaquePass : AbstractRenderGraphPass
    {
        private readonly FilteringSettings _filteringSettings;

        public ForwardOpaquePass()
        {
            // BUG: Ctor won't called on settings change! Creation will happens once! 
            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.opaque;
        }

        private class PassData
        {
            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public RendererListHandle List;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            // TODO: Add additional light support!

            var cameraData = frameData.Get<CameraData>();
            var cullingResultData = frameData.Get<CullingResultData>();
            var lightingData = frameData.Get<LightingData>();
            var gBufferData = frameData.Get<GBufferData>();

            using var builder = renderGraph.AddRasterRenderPass<PassData>("Opaque", out var passData);
            builder.AllowPassCulling(false);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            var shaderPassName = new ShaderTagId("ForwardLit");
            var drawingSettings = new DrawingSettings(shaderPassName, new SortingSettings(cameraData.Camera))
            {
                mainLightIndex = lightingData.MainLightIndex,
                perObjectData = PerObjectData.LightData
                    | PerObjectData.ReflectionProbes
                // | PerObjectData.ReflectionProbeData
                // | PerObjectData.LightProbe
            };

            var rendererListDesc = new RendererListParams()
            {
                cullingResults = cullingResultData.CullingResult,
                drawSettings = drawingSettings,
                filteringSettings = _filteringSettings,
            };
            passData.List = renderGraph.CreateRendererList(rendererListDesc);
            builder.UseRendererList(passData.List);

            builder.SetRenderAttachment(gBufferData.GBuffer0, 0, AccessFlags.Write);
            builder.SetRenderAttachmentDepth(gBufferData.Depth, AccessFlags.Write);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                context.cmd.DrawRendererList(data.List);
            });
        }
    }
}
