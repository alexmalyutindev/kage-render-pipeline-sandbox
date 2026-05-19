using System;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class FinalBlitPass : AbstractRenderGraphPass
    {
        private class PassData
        {
            public TextureHandle Source;
            public TextureHandle Destination;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();

            using var builder = renderGraph.AddUnsafePass("Blit to Backbuffer", out PassData passData);

            builder.AllowPassCulling(false);

            passData.Source = cameraData.CameraActiveColor;
            builder.UseTexture(passData.Source);

            passData.Destination = cameraData.CameraBackBuffer;
            builder.UseTexture(passData.Destination, AccessFlags.Write);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                cmd.Blit(data.Source, data.Destination);
            });
        }
    }
}
