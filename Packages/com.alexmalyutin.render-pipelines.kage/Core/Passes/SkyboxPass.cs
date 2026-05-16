using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class SkyboxPass : AbstractRenderGraphPass
    {
        private class SkyBoxPassData
        {
            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public RendererListHandle List;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (!frameData.Contains<GBufferData>()) return;

            var cameraData = frameData.Get<CameraData>();
            if (cameraData.Camera.cameraType == CameraType.Preview)
            {
                return;
            }

            var gBufferData = frameData.Get<GBufferData>();

            using var builder = renderGraph.AddRasterRenderPass("Skybox", out SkyBoxPassData passData);
            builder.AllowPassCulling(false);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            passData.List = renderGraph.CreateSkyboxRendererList(cameraData.Camera);
            builder.UseRendererList(passData.List);

            builder.SetRenderAttachment(gBufferData.GBuffer0, 0);
            builder.SetRenderAttachmentDepth(gBufferData.Depth);
            builder.SetRenderFunc<SkyBoxPassData>(static (data, context) =>
            {
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                context.cmd.DrawRendererList(data.List);
            });
        }
    }
}
