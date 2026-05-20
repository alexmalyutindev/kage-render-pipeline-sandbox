using Rendering.KageRP;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace DefaultNamespace
{
    public class SnapdragonGameSupperResolutionPass : AbstractRenderGraphPass
    {
        public enum OperationMode { RGBA = 1, RGBY = 3, LERP = 4 }

        public Material SGSR1Material;
        [Range(1.0f, 2.0f)] public float EdgeSharpen = 2.0f;
        public OperationMode Mode = OperationMode.RGBA;

        private class PassData
        {
            public Material Material;

            public Vector4 Params;
            public Vector4 ViewportInfo;
            public TextureHandle InputTexture;
            public TextureHandle OutputTexture;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (SGSR1Material == null) return;

            var cameraData = frameData.Get<CameraData>();
            using var builder = renderGraph.AddUnsafePass<PassData>("Upscale SGSRv1", out var passData);

            passData.Material = SGSR1Material;

            passData.Params = new Vector4((int) Mode, EdgeSharpen);

            var desc = cameraData.CameraBackBufferDescriptor;
            passData.ViewportInfo = new Vector4(1.0f / desc.width, 1.0f / desc.height, desc.width, desc.height);
            passData.InputTexture = cameraData.CameraActiveColor;
            builder.UseTexture(passData.InputTexture, AccessFlags.Read);
            passData.OutputTexture = cameraData.CameraBackBuffer;
            builder.UseTexture(passData.OutputTexture, AccessFlags.Write);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                cmd.SetGlobalVector("_SGSR_Params", data.Params);
                cmd.SetGlobalVector("_SGSR_ViewportInfo", data.ViewportInfo);
                cmd.Blit(data.InputTexture, data.OutputTexture, data.Material, 0);
            });
        }
    }
}
