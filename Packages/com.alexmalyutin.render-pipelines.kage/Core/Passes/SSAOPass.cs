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

            public TextureHandle SceneDepth;

            public Material Material;
            public TextureHandle Occlusion;
            public TextureHandle MinMaxDepth;
            public TextureHandle VarianceDepth;

            public TextureHandle Temp;
            public Vector4 Params;
            public Texture BayerMatrix;
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
                passData.BayerMatrix = _defaultResources.BayerMatrix;

                passData.SceneDepth = prevFrameDepth;

                builder.UseTexture(passData.SceneDepth, AccessFlags.Read);

                var frameDesc = cameraData.CameraBackBufferDescriptor;
                var ssaoDesc = new TextureDesc(frameDesc.width / 4, frameDesc.height / 4)
                {
                    name = "_SSAO",
                    format = GraphicsFormat.R8_UNorm,
                };
                passData.Occlusion = renderGraph.CreateTexture(ssaoDesc);
                builder.UseTexture(passData.Occlusion, AccessFlags.ReadWrite);

                ssaoDesc.name = "_SSAO_Temp";
                passData.Temp = renderGraph.CreateTexture(ssaoDesc);
                builder.UseTexture(passData.Temp, AccessFlags.ReadWrite);

                ssaoDesc.name = "_MinMaxDepth";
                ssaoDesc.format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGHalf, false);
                passData.MinMaxDepth = renderGraph.CreateTexture(ssaoDesc);
                builder.UseTexture(passData.MinMaxDepth, AccessFlags.ReadWrite);

                ssaoDesc.name = "_VarianceDepth";
                ssaoDesc.format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGHalf, false);
                passData.VarianceDepth = renderGraph.CreateTexture(ssaoDesc);
                builder.UseTexture(passData.VarianceDepth, AccessFlags.ReadWrite);

                builder.SetGlobalTextureAfterPass(passData.Occlusion, Shader.PropertyToID("_OcclusionTexture"));
            }

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                if (!data.SSAOActive || 
                    !data.SceneDepth.IsValid() || 
                    !data.SceneDepth.IsValid() || 
                    !data.Occlusion.IsValid()
                )
                {
                    cmd.DisableShaderKeyword("SSAO_ON");
                    return;
                }

                // TODO: Use Linear Depth from GBuffer2.z!!!
                cmd.Blit(data.SceneDepth, data.MinMaxDepth, data.Material, 1);
                cmd.Blit(data.SceneDepth, data.VarianceDepth, data.Material, 2);

                // AO
                cmd.SetGlobalVector("_GTAO_Params", data.Params);
                cmd.SetGlobalTexture("_MinMaxDepth", data.MinMaxDepth);
                cmd.SetGlobalTexture("_VarianceDepth", data.VarianceDepth);
                cmd.SetGlobalTexture("_BayerMatrix", data.BayerMatrix);
                cmd.Blit(data.SceneDepth, data.Occlusion, data.Material, 3);

                // Blur
                cmd.SetGlobalVector("_Direction", new Vector4(1, 0));
                cmd.Blit(data.Occlusion, data.Temp, data.Material, 0);
                cmd.SetGlobalVector("_Direction", new Vector4(0, 1));
                cmd.Blit(data.Temp, data.Occlusion, data.Material, 0);

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

            if (cameraData.Camera.cameraType is not (CameraType.Game or CameraType.SceneView))
            {
                return false;
            }

            var persistentFrameData = frameData.Get<PersistentFrameData>();
            if (!persistentFrameData.Context.Contains<PrevFrameBufferData>()) return false;
            var prevFrameBufferData = persistentFrameData.Context.Get<PrevFrameBufferData>();
            prevFrameDepth = prevFrameBufferData.GetFrameDepth(renderGraph);
            if (!prevFrameDepth.IsValid()) return false;

            return true;
        }
    }
}
