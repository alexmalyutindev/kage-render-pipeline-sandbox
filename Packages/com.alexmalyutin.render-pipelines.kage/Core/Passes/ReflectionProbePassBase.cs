using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class ReflectionProbePass : AbstractRenderGraphPass
    {
        private class SkyboxProbePassData
        {
            public RendererListHandle List;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();

            if (cameraData.Camera.cameraType is not CameraType.Reflection) return;

            using var builder = renderGraph.AddRasterRenderPass("Probe Skybox", out SkyboxProbePassData passData);

            passData.List = renderGraph.CreateSkyboxRendererList(cameraData.Camera);
            builder.UseRendererList(passData.List);
            builder.SetRenderAttachment(cameraData.CameraBackBuffer, 0);
            builder.AllowPassCulling(false);
            
            builder.SetRenderFunc<SkyboxProbePassData>(static (data, context) =>
            {
                context.cmd.DrawRendererList(data.List);
            });
        }
    }
}
