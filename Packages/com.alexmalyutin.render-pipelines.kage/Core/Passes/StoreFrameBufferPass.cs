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

        public override void AfterCameraCulling(
            ScriptableRenderContext context,
            CullingResultData cullingResultData,
            ContextContainer frameData
        )
        {
            // TODO: Make another configure handle!
            var persistentFrameData = frameData.Get<PersistentFrameData>();
            var prevFrameBufferData = persistentFrameData.Context.GetOrCreate<PrevFrameBufferData>();

            var cameraData = frameData.Get<CameraData>();
            var cameraColorDesc = cameraData.CameraBackBufferDescriptor;
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
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            var persistentFrameData = frameData.Get<PersistentFrameData>();
            var prevFrameBufferData = persistentFrameData.Context.GetOrCreate<PrevFrameBufferData>();

            using var builder = renderGraph.AddUnsafePass<PassData>("Store FrameBuffers", out var passData);

            // TODO: Check if I need to double import it! I will import this textures before in pipeline!!!
            passData.SrcColor = cameraData.CameraActiveColor;
            passData.DstColor = prevFrameBufferData.GetFrameColor(renderGraph); 
            builder.UseTexture(passData.SrcColor, AccessFlags.Read);
            builder.UseTexture(passData.DstColor, AccessFlags.Write);

            // TODO: Check if I need to double import it! I will import this textures before in pipeline!!!
            // TODO: Use Linear Depth from GBuffer2.z!!!
            passData.SrcDepth = cameraData.CameraActiveDepth;
            passData.DstDepth = prevFrameBufferData.GetFrameDepth(renderGraph); 
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
        private TextureHandle _frameColorHandle;
        private TextureHandle _frameDepthHandle;

        public TextureHandle GetFrameColor(RenderGraph renderGraph) => 
            ImportTexture(renderGraph, FrameColor, ref _frameColorHandle);

        public TextureHandle GetFrameDepth(RenderGraph renderGraph) => 
            ImportTexture(renderGraph, FrameDepth, ref _frameDepthHandle);

        public override void Reset()
        {
            if (FrameColor != null) RTHandles.Release(FrameColor);
            if (FrameDepth != null) RTHandles.Release(FrameDepth);

            FrameColor = null;
            FrameDepth = null;
            _frameColorHandle = TextureHandle.nullHandle;
            _frameDepthHandle = TextureHandle.nullHandle;
        }

        private static TextureHandle ImportTexture(
            RenderGraph renderGraph, 
            RTHandle texture,
            ref TextureHandle handle
        )
        {
            if (handle.IsValid()) return handle;
            if (texture == null || texture.rt == null) return TextureHandle.nullHandle;

            var rt = texture.rt;
            handle = renderGraph.ImportTexture(
                texture,
                new RenderTargetInfo()
                {
                    width = rt.width,
                    height = rt.height,
                    format = rt.graphicsFormat,
                    msaaSamples = rt.antiAliasing,
                    volumeDepth = rt.volumeDepth,
                    bindMS = rt.bindTextureMS,
                },
                new ImportResourceParams()
                {
                    clearOnFirstUse = false,
                    discardOnLastUse = false,
                    textureUVOrigin = TextureUVOrigin.BottomLeft,
                }
            );

            return handle;
        }
    }
}
