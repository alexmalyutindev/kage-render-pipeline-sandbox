using System;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class MainLightShadowPass : AbstractRenderGraphPass
    {
        public ShadowMapResolution Resolution = ShadowMapResolution._512;

        private class PassData
        {
            public TextureHandle MainLightShadowMap;
            public RendererListHandle List;

            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public Matrix4x4 WorldToShadow;
        }

        public override void AfterCameraCulling(ScriptableRenderContext context, CullingResultData cullingResultData, ContextContainer frameData)
        {
            var lightingData = frameData.Get<LightingData>();
            var cullingResults = cullingResultData.CullingResult;

            if (lightingData.MainLightIndex >= 0)
            {
                cullingResults.ComputeDirectionalShadowMatricesAndCullingPrimitives(
                    lightingData.MainLightIndex,
                    0, 1, Vector3.one, (int)Resolution, 0.0f,
                    out lightingData.MainLightShadowView,
                    out lightingData.MainLightShadowProj,
                    out lightingData.MainLightShadowSplitData
                );

                if (!cullingResults.GetShadowCasterBounds(lightingData.MainLightIndex, out _))
                {
                    lightingData.MainLightIndex = -1;
                    return;
                }

                var splitInfos = new NativeArray<ShadowSplitData>(1, Allocator.Temp);
                splitInfos[0] = lightingData.MainLightShadowSplitData;

                var perLightInfos = new NativeArray<LightShadowCasterCullingInfo>(
                    cullingResults.visibleLights.Length, Allocator.Temp
                );

                for (int i = 0; i < perLightInfos.Length; i++)
                {
                    perLightInfos[i] = new LightShadowCasterCullingInfo()
                    {
                        projectionType = BatchCullingProjectionType.Orthographic,
                        splitRange = (i == lightingData.MainLightIndex)
                            ? new RangeInt(0, 1)
                            : new RangeInt(0, 0),
                    };
                }

                var cullInfos = new ShadowCastersCullingInfos
                {
                    splitBuffer = splitInfos,
                    perLightInfos = perLightInfos
                };
                context.CullShadowCasters(cullingResults, cullInfos);

                cullInfos.splitBuffer.Dispose();
                cullInfos.perLightInfos.Dispose();
            }
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cullingResultData = frameData.Get<CullingResultData>();
            var lightingData = frameData.Get<LightingData>();

            if (lightingData.MainLightIndex < 0) return;

            using var builder = renderGraph.AddUnsafePass<PassData>(nameof(MainLightShadowPass), out var passData);
            builder.AllowPassCulling(false);

            passData.View = lightingData.MainLightShadowView;
            passData.Proj = lightingData.MainLightShadowProj;
            passData.WorldToShadow = lightingData.GetWorldToShadowMatrix();

            var desc = new TextureDesc((int)Resolution, (int)Resolution)
            {
                name = "MainLightShadowMap",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.Shadowmap, false),
                depthBufferBits = DepthBits.Depth8,
                filterMode = FilterMode.Bilinear,
                msaaSamples = MSAASamples.None,
                isShadowMap = true,
            };
            passData.MainLightShadowMap = renderGraph.CreateTexture(desc);
            builder.UseTexture(passData.MainLightShadowMap, AccessFlags.Write);

            var rendererListDesc = new ShadowDrawingSettings(cullingResultData.CullingResult, lightingData.MainLightIndex)
            {
                objectsFilter = ShadowObjectsFilter.AllObjects,
            };
            passData.List = renderGraph.CreateShadowRendererList(ref rendererListDesc);
            builder.UseRendererList(passData.List);

            builder.AllowGlobalStateModification(true);
            builder.SetGlobalTextureAfterPass(passData.MainLightShadowMap, Shader.PropertyToID("_MainLightShadowMap"));
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                context.cmd.SetRenderTarget(data.MainLightShadowMap);
                context.cmd.ClearRenderTarget(true, false, Color.black);
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                context.cmd.DrawRendererList(data.List);
                context.cmd.SetGlobalMatrix("_WorldToMainLightShadow", data.WorldToShadow);
            });
        }
    }

    public enum ShadowMapResolution
    {
        _256 = 256,
        _512 = 512,
        _1024 = 1024,
        _2048 = 2048,
    }
}
