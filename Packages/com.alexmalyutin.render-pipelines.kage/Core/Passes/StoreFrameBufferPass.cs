using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class StoreFrameBufferPass : AbstractRenderGraphPass
    {
        private class PassData
        {
            public TextureHandle SrcColor;
            public TextureHandle DstColor;

            public TextureHandle SrcDepth;
            public TextureHandle DstDepth;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            // TODO: Set GBuffer0 as main frame buffer and set it into CameraData!
            var gBufferData = frameData.Get<GBufferData>();
            var persistentFrameData = frameData.Get<PersistentFrameData>();
            var prevFrameBufferData = persistentFrameData.Context.GetOrCreate<PrevFrameBufferData>();

            var cameraColorDesc = cameraData.CameraColorDescriptor;
            var colorDesc = new RenderTextureDescriptor(
                cameraColorDesc.width,
                cameraColorDesc.height,
                RenderTextureFormat.RGB111110Float
            );
            KageUtils.ReAllocIfNeeded(ref prevFrameBufferData.FrameColor, colorDesc, "_PrevFrameColor");
            
            var depthDesc = new RenderTextureDescriptor(
                cameraColorDesc.width,
                cameraColorDesc.height,
                RenderTextureFormat.RHalf
            );
            KageUtils.ReAllocIfNeeded(ref prevFrameBufferData.FrameDepth, depthDesc, "_PrevFrameDepth");

            using var builder = renderGraph.AddUnsafePass<PassData>("Store FrameBuffers", out var passData);

            // TODO: Check if I need to double import it! I will import this textures before in pipeline!!!
            passData.SrcColor = gBufferData.GBuffer0;
            passData.DstColor = ImportPrevFrameBuffer(renderGraph, prevFrameBufferData.FrameColor);
            builder.UseTexture(passData.SrcColor, AccessFlags.Read);
            builder.UseTexture(passData.DstColor, AccessFlags.Write);

            // TODO: Check if I need to double import it! I will import this textures before in pipeline!!!
            passData.SrcDepth = gBufferData.Depth;
            passData.DstDepth = ImportPrevFrameBuffer(renderGraph, prevFrameBufferData.FrameDepth);
            builder.UseTexture(passData.SrcDepth, AccessFlags.Read);
            builder.UseTexture(passData.DstDepth, AccessFlags.Write);

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                cmd.Blit(data.SrcColor, data.DstColor);
                cmd.Blit(data.SrcDepth, data.DstDepth);
            });
        }

        private static TextureHandle ImportPrevFrameBuffer(RenderGraph renderGraph, RTHandle rtHandle)
        {
            var descriptor = rtHandle.rt.descriptor;
            return renderGraph.ImportTexture(
                rtHandle,
                new RenderTargetInfo()
                {
                    width = descriptor.width,
                    height = descriptor.height,
                    msaaSamples = descriptor.msaaSamples,
                    bindMS = descriptor.bindMS,
                    format = descriptor.graphicsFormat,
                    volumeDepth = descriptor.volumeDepth,
                },
                new ImportResourceParams()
                {
                    clearColor = Color.clear,
                    clearOnFirstUse = false,
                    discardOnLastUse = false,
                    textureUVOrigin = TextureUVOrigin.BottomLeft,
                }
            );
        }
    }

    public abstract class PersistentContextItem : ContextItem { }

    public class PrevFrameBufferData : PersistentContextItem
    {
        public RTHandle FrameColor;
        public RTHandle FrameDepth;

        public override void Reset()
        {
            if (FrameColor != null) RTHandles.Release(FrameColor);
            if (FrameDepth != null) RTHandles.Release(FrameDepth);

            FrameColor = null;
            FrameDepth = null;
        }
    }
}
