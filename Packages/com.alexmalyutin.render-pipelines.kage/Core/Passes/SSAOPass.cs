using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class SSAOPass : AbstractRenderGraphPass
    {
        [Serializable]
        public class Settings
        {
            [Range(0.1f, 2.0f)] public float OcclusionRadius = 1.0f;
            [Range(0.0f, 1.0f)] public float OcclusionThickness = 0.1f;
        }

        [SerializeField] private Settings _settings = new();

        private KageRenderPipelineDefaultResources _defaultResources;

        private class PassData
        {
            public bool SSAOActive;

            public TextureHandle Depth;

            public Material Material;
            public TextureHandle OcclusionTexture;
            public TextureHandle TempTexture;
            public Vector4 Params;
        }

        public override void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline)
        {
            _defaultResources = asset.DefaultResources;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            using var builder = renderGraph.AddUnsafePass<PassData>("SSAO", out var passData);
            builder.AllowPassCulling(false);
            builder.AllowGlobalStateModification(true);

            passData.SSAOActive = IsSSAOActive(
                renderGraph,
                frameData, out var cameraData,
                out var prevFrameDepth
            );

            if (passData.SSAOActive)
            {
                passData.Material = _defaultResources.SSAOMaterial;
                passData.Params = new Vector4(_settings.OcclusionRadius, _settings.OcclusionThickness);

                passData.Depth = prevFrameDepth;

                builder.UseTexture(passData.Depth, AccessFlags.Read);

                var frameDesc = cameraData.CameraBackBufferDescriptor;
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
            }

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                if (!data.SSAOActive)
                {
                    cmd.DisableShaderKeyword("SSAO_ON");
                    return;
                }

                cmd.SetGlobalTexture("_Depth", data.Depth);
                cmd.SetGlobalVector("_GTAO_Params", data.Params);
                cmd.Blit(data.Depth, data.OcclusionTexture, data.Material, 1);

                // Blur
                cmd.SetGlobalVector("_Direction", new Vector4(1, 0));
                cmd.Blit(data.OcclusionTexture, data.TempTexture, data.Material, 0);
                cmd.SetGlobalVector("_Direction", new Vector4(0, 1));
                cmd.Blit(data.TempTexture, data.OcclusionTexture, data.Material, 0);

                cmd.EnableShaderKeyword("SSAO_ON");
            });
        }

        private static bool IsSSAOActive(
            RenderGraph renderGraph,
            ContextContainer frameData,
            out CameraData cameraData,
            out TextureHandle prevFrameDepth
        )
        {
            cameraData = frameData.Get<CameraData>();
            prevFrameDepth = TextureHandle.nullHandle;

            if (cameraData.Camera.cameraType is not (CameraType.Game or CameraType.SceneView)) return false;

            var persistentFrameData = frameData.Get<PersistentFrameData>();
            if (!persistentFrameData.Context.Contains<PrevFrameBufferData>()) return false;

            var prevFrameBufferData = persistentFrameData.Context.Get<PrevFrameBufferData>();
            if (prevFrameBufferData.FrameDepth == null || prevFrameBufferData.FrameDepth.rt == null)
            {
                return false;
            }

            prevFrameDepth = renderGraph.ImportTexture(prevFrameBufferData.FrameDepth);
            if (!prevFrameDepth.IsValid()) return false;

            return true;
        }
    }
}
