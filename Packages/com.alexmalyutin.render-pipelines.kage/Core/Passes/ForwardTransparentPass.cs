using System;
using Rendering.KageRP.ShaderLibrary;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class ForwardTransparentPass : AbstractRenderGraphPass
    {
        public static readonly int AdditionalLightsBufferId = Shader.PropertyToID("_AdditionalLightsBuffer");
        public static readonly int AdditionalLightsIndicesId = Shader.PropertyToID("_AdditionalLightsIndices");
        
        private readonly FilteringSettings _filteringSettings;

        public ForwardTransparentPass()
        {
            // BUG: Ctor won't called on settings change! Creation will happens once! 
            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.transparent;
        }

        private class PassData
        {
            public Matrix4x4 View;
            public Matrix4x4 Proj;
            public RendererListHandle List;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            // TODO: Add additional light support!

            var cameraData = frameData.Get<CameraData>();
            var cullingResultData = frameData.Get<CullingResultData>();
            var lightingData = frameData.Get<LightingData>();
            var gBufferData = frameData.Get<GBufferData>();

            using var builder = renderGraph.AddRasterRenderPass<PassData>("Transparent", out var passData);
            builder.AllowPassCulling(false);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            var shaderPassName = new ShaderTagId("ForwardLit");
            var sortingSettings = new SortingSettings(cameraData.Camera)
            {
                criteria = SortingCriteria.CommonTransparent
            };
            var drawingSettings = new DrawingSettings(shaderPassName, sortingSettings)
            {
                mainLightIndex = lightingData.MainLightIndex,
                perObjectData = PerObjectData.LightData | PerObjectData.LightIndices
                    | PerObjectData.ReflectionProbes
                // | PerObjectData.ReflectionProbeData
                // | PerObjectData.LightProbe
            };

            var cullingResults = cullingResultData.CullingResult;
            var rendererListDesc = new RendererListParams()
            {
                cullingResults = cullingResults,
                drawSettings = drawingSettings,
                filteringSettings = _filteringSettings,
            };
            passData.List = renderGraph.CreateRendererList(rendererListDesc);
            builder.UseRendererList(passData.List);

            // TODO: Complete additional lights setup.
            SetupAdditionalLightsData(cullingResults);

            builder.SetRenderAttachment(gBufferData.GBuffer0, 0, AccessFlags.Write);
            builder.SetRenderAttachmentDepth(gBufferData.Depth, AccessFlags.Read);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
                context.cmd.DrawRendererList(data.List);
            });
        }

        private static void SetupAdditionalLightsData(CullingResults cullingResults)
        {
            using var lightIndexMap = cullingResults.GetLightIndexMap(Allocator.Temp);
            // TODO: cullResults.SetLightIndexMap(perObjectLightIndexMap);

            var additionalLightsData = new NativeArray<ShaderTypes.LightData>(cullingResults.lightIndexCount, Allocator.Temp);

            var additionalLightCount = 0;
            var visibleLights = cullingResults.visibleLights;
            for (var lightIndex = 0; lightIndex < cullingResults.lightIndexCount; lightIndex++)
            {
                var light = visibleLights.UnsafeElementAtMutable(lightIndex);
                var lightLocalToWorld = light.localToWorldMatrix;

                var position = lightLocalToWorld.GetColumn(3);
                Vector4 dir = lightLocalToWorld.GetColumn(2);
                var direction = new Vector4(-dir.x, -dir.y, -dir.z, 0.0f);

                var lightData = new ShaderTypes.LightData
                {
                    color = light.finalColor,
                    attenuation = Vector4.one,
                    position = position,
                    spotDirection = direction,
                };
                additionalLightsData[additionalLightCount] = lightData;
                additionalLightCount++;
            }

            var lightIndicesBuffer = ShaderData.instance.GetLightIndicesBuffer(additionalLightCount);
            var lightDataBuffer = ShaderData.instance.GetLightDataBuffer(additionalLightCount);
            lightDataBuffer.SetData(additionalLightsData);

            // TODO: additionalLightCount
            Shader.SetGlobalVector("_AdditionalLightsCount", new Vector4(0.0f, 0.0f));
            Shader.SetGlobalBuffer(AdditionalLightsIndicesId, lightIndicesBuffer);
            Shader.SetGlobalBuffer(AdditionalLightsBufferId, lightDataBuffer);

            additionalLightsData.Dispose();
        }
    }
}
