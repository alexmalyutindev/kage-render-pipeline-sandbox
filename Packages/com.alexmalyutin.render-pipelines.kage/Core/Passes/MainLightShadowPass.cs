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
        private static readonly int MainLightShadowMapID = Shader.PropertyToID("_MainLightShadowMap");

        public ShadowMapResolution Resolution = ShadowMapResolution._512;
        public DepthBits DepthBits = DepthBits.Depth8;
        [Min(0.01f)] public float ShadowDistance = 10.0f;
        [Range(0.0f, 1.0f)] public float ShadowFade = 1.0f;

        private class PassData
        {
            public TextureHandle MainLightShadowMap;
            public RendererListHandle List;

            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public Matrix4x4 WorldToShadow;
            public Vector4 ShadowBias;
            public Vector4 ShadowParams;
        }

        public override void BeforeCameraCulling(ref ScriptableCullingParameters cullingParameters)
        {
            cullingParameters.shadowDistance = ShadowDistance;
        }

        public override void AfterCameraCulling(
            ScriptableRenderContext context, 
            CullingResultData cullingResultData,
            ContextContainer frameData
        )
        {
            var lightingData = frameData.Get<LightingData>();
            if (lightingData.MainLightIndex < 0) return;

            var cullingResults = cullingResultData.CullingResult;

            var light = cullingResultData.CullingResult.visibleLights[lightingData.MainLightIndex];
            cullingResults.ComputeDirectionalShadowMatricesAndCullingPrimitives(
                lightingData.MainLightIndex,
                0, 1, Vector3.one,
                (int)Resolution,
                light.light.shadowNearPlane,
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

            for (int lightIndex = 0; lightIndex < perLightInfos.Length; lightIndex++)
            {
                perLightInfos[lightIndex] = new LightShadowCasterCullingInfo()
                {
                    projectionType = BatchCullingProjectionType.Orthographic,
                    splitRange = lightIndex == lightingData.MainLightIndex
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

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var lightingData = frameData.Get<LightingData>();
            if (lightingData.MainLightIndex < 0) return;

            var cullingResultData = frameData.Get<CullingResultData>();

            // BUG: Convert to Raster pass:
            // When I am using MainLightShadowMap for rendering as depth target in RasterPass, I can't 
            // set it as global texture for reading, because RenderGraph will check it read/write flag.
            // In URP they have workaround, by binding ShadowMap by it RenderTextureIdentifier, and make
            // it as UseTexture(MainLightShadowMap, AccessFlags.Read) in LightingPass.
            // For now it's ok to use UnsafePass, whatever it RG will merge it with other passes,
            // will do refactoring later.
            using var builder = renderGraph.AddRasterRenderPass<PassData>(nameof(MainLightShadowPass), out var passData);

            var light = cullingResultData.CullingResult.visibleLights[lightingData.MainLightIndex].light;
            passData.ShadowBias = new Vector4(
                light.shadowBias,
                light.shadowNormalBias,
                (int)light.type
            );

            var softShadowsProp = light.shadows == LightShadows.Soft ? 1 : 0;
            var fadeDistance = ShadowDistance * ShadowDistance;
            var distanceFadeNear = fadeDistance * Mathf.Min(0.999f, 1.0f - ShadowFade);
            var shadowFadeScale = 1.0f / (fadeDistance - distanceFadeNear);
            var shadowFadeBias = -distanceFadeNear / (fadeDistance - distanceFadeNear);
            passData.ShadowParams = new Vector4(light.shadowStrength, softShadowsProp, shadowFadeScale, shadowFadeBias);
            
            passData.View = lightingData.MainLightShadowView;
            passData.Proj = lightingData.MainLightShadowProj;
            passData.WorldToShadow = lightingData.GetWorldToShadowMatrix();

            var desc = new TextureDesc((int)Resolution, (int)Resolution)
            {
                name = "MainLightShadowMap",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.Shadowmap, false),
                depthBufferBits = DepthBits,
                filterMode = FilterMode.Bilinear,
                isShadowMap = true,
                clearBuffer = true,
            };
            passData.MainLightShadowMap = renderGraph.CreateTexture(desc);
            lightingData.MainLightShadowMap = passData.MainLightShadowMap;

            var rendererListDesc = new ShadowDrawingSettings(
                cullingResultData.CullingResult,
                lightingData.MainLightIndex
            )
            {
                objectsFilter = ShadowObjectsFilter.AllObjects,
            };
            
            passData.List = renderGraph.CreateShadowRendererList(ref rendererListDesc);
            builder.UseRendererList(passData.List);

            builder.SetRenderAttachmentDepth(passData.MainLightShadowMap);

            builder.AllowGlobalStateModification(true);
            builder.SetGlobalTextureAfterPass(passData.MainLightShadowMap, MainLightShadowMapID);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = context.cmd;

                cmd.SetViewProjectionMatrices(data.View, data.Proj);
                cmd.SetGlobalVector("_ShadowBias", data.ShadowBias);
                cmd.SetGlobalMatrix("_WorldToMainLightShadow", data.WorldToShadow);
                cmd.SetGlobalVector("_MainLightShadowParams", data.ShadowParams);
                cmd.DrawRendererList(data.List);
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
