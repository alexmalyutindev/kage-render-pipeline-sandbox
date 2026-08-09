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

        private class CombinedPassData
        {
            // Shader Data
            public Material Material;
            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public Vector4 RenderSizeTexel;
            
            // Renderer List
            public RendererListHandle List;
            
            // Textures
            public TextureHandle Transmittance;
            public TextureHandle Depth;
            public TextureHandle MinMaxDepth;
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

            // Transmittance Texture
            var desc = new TextureDesc(width, height)
            {
                name = "_TransmittanceBuffer",
                format = GraphicsFormatUtility.GetGraphicsFormat(TextureFormat.RGBAHalf, false),
                clearBuffer = true,
                clearColor = Color.clear
            };
            var transmittance = renderGraph.CreateTexture(desc);
            
            using var builder = renderGraph.AddUnsafePass<CombinedPassData>("Volume.CombinedPass", out var passData);
            builder.AllowPassCulling(false);
            builder.AllowGlobalStateModification(true);

            // Assign Matrices and Globals
            passData.Material = VolumeProcessing;
            passData.RenderSizeTexel = new Vector4(desc.width, desc.height, 1.0f / desc.width, 1.0f / desc.height);
            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            // Setup Renderer List
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

            // Assign Textures to Builder with proper Access Flags
            passData.Transmittance = transmittance;
            builder.UseTexture(passData.Transmittance, AccessFlags.ReadWrite); // Written via RenderTarget, Read via Blit

            var minMaxDepthDesc = new TextureDesc(width, height)
            {
                name = "_MinMaxDepth",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGHalf, false),
            };
            passData.MinMaxDepth = builder.CreateTransientTexture(minMaxDepthDesc);
            builder.UseTexture(passData.MinMaxDepth, AccessFlags.ReadWrite);

            passData.Depth = frameBufferData.GetFrameDepth(renderGraph);
            builder.UseTexture(passData.Depth, AccessFlags.Read);

            passData.Target = gBufferData.GBuffer0;
            builder.UseTexture(passData.Target, AccessFlags.Write);

            // Execution
            builder.SetRenderFunc<CombinedPassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                
                cmd.Blit(data.Depth, data.MinMaxDepth, data.Material, 0);

                cmd.SetRenderTarget(data.Transmittance);
                cmd.ClearRenderTarget(false, true, Color.black);
                cmd.SetViewProjectionMatrices(data.View, data.Proj);
                
                cmd.SetGlobalTexture("_MinMaxDepth", data.MinMaxDepth);
                cmd.SetGlobalVector("_RenderSizeTexel", data.RenderSizeTexel);
                cmd.DrawRendererList(data.List);

                cmd.SetGlobalTexture("_Depth", data.Depth);
                cmd.SetGlobalTexture("_LowDepth", data.MinMaxDepth);
                cmd.Blit(data.Transmittance, data.Target, data.Material, 1);
            });
        }
    }
}