using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Scripting.APIUpdating;

namespace Rendering.KageRP
{
    [Serializable]
    public class SSAOPass : AbstractRenderGraphPass
    {
        private KageRenderPipelineDefaultResources _defaultResources;

        private class PassData
        {
            public TextureHandle Color;
            public TextureHandle Depth;

            public Material Material;
            public TextureHandle OcclusionTexture;
            public TextureHandle TempTexture;
        }

        public override void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline)
        {
            _defaultResources = asset.DefaultResources;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            var persistentFrameData = frameData.Get<PersistentFrameData>();

            if (!persistentFrameData.Context.Contains<PrevFrameBufferData>()) return;
            var prevFrameBufferData = persistentFrameData.Context.Get<PrevFrameBufferData>();

            using var builder = renderGraph.AddUnsafePass<PassData>("SSAO", out var passData);
            builder.AllowPassCulling(false);

            passData.Material = _defaultResources.SSAOMaterial;

            passData.Color = renderGraph.ImportTexture(prevFrameBufferData.FrameColor);
            passData.Depth = renderGraph.ImportTexture(prevFrameBufferData.FrameDepth);

            builder.UseTexture(passData.Color, AccessFlags.Read);
            builder.UseTexture(passData.Depth, AccessFlags.Read);

            var frameDesc = cameraData.CameraColorDescriptor;
            var ssgiDesc = new TextureDesc(frameDesc.width / 4, frameDesc.height / 4)
            {
                name = "_SSAO",
                format = GraphicsFormat.R8_UNorm,
            };
            passData.OcclusionTexture = renderGraph.CreateTexture(ssgiDesc);
            builder.UseTexture(passData.OcclusionTexture, AccessFlags.ReadWrite);

            ssgiDesc.name = "_SSAO_Temp";
            passData.TempTexture = renderGraph.CreateTexture(ssgiDesc);
            builder.UseTexture(passData.TempTexture, AccessFlags.ReadWrite);

            builder.SetGlobalTextureAfterPass(passData.OcclusionTexture, Shader.PropertyToID("_OcclusionTexture"));
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                cmd.SetGlobalTexture("_Depth", data.Depth);
                cmd.Blit(data.Color, data.OcclusionTexture, data.Material, 1);

                // Blur
                cmd.SetGlobalVector("_Direction", new Vector4(1, 0));
                cmd.Blit(data.OcclusionTexture, data.TempTexture, data.Material, 0);
                cmd.SetGlobalVector("_Direction", new Vector4(0, 1));
                cmd.Blit(data.TempTexture, data.OcclusionTexture, data.Material, 0);
            });
        }
    }
}
