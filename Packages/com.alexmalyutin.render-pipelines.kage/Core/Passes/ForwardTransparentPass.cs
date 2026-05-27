using System;
using System.Text;
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
        public const int MaxAdditionalLights = 32;
        public static readonly int AdditionalLightsBufferId = Shader.PropertyToID("_AdditionalLightsBuffer");
        public static readonly int AdditionalLightsIndicesId = Shader.PropertyToID("_AdditionalLightsIndices");
        public static readonly int AdditionalLightsCountId = Shader.PropertyToID("_AdditionalLightsCount");

        private readonly FilteringSettings _filteringSettings;

        public ForwardTransparentPass()
        {
            // BUG: Ctor won't called on settings change! Creation will happens once! 
            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.transparent;
        }

        public override void BeforeCameraCulling(ref ScriptableCullingParameters cullingParameters)
        {
            cullingParameters.maximumVisibleLights = 32;
        }

        public override void AfterCameraCulling(
            ScriptableRenderContext context,
            CullingResultData cullingResultData,
            ContextContainer frameData
        )
        {
            // TODO: Complete additional lights setup.
            SetupAdditionalLightsData(cullingResultData.CullingResult);
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
            var rendererListDesc = new RendererListParams()
            {
                cullingResults = cullingResultData.CullingResult,
                drawSettings = drawingSettings,
                filteringSettings = _filteringSettings,
            };
            passData.List = renderGraph.CreateRendererList(rendererListDesc);
            builder.UseRendererList(passData.List);

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
            var visibleLights = cullingResults.visibleLights;
            var additionalLightCount = SetupPerObjectLightIndices(cullingResults, visibleLights);

            if (additionalLightCount > 0)
            {
                var additionalLightsData = new NativeArray<ShaderTypes.LightData>(additionalLightCount, Allocator.Temp);

                for (int i = 0, lightIter = 0; i < visibleLights.Length && lightIter < additionalLightCount; i++)
                {
                    ref var light = ref visibleLights.UnsafeElementAtMutable(i);
                    if (light.lightType is not (LightType.Point or LightType.Spot)) continue;

                    var lightLocalToWorld = light.localToWorldMatrix;
                    var position = lightLocalToWorld.GetColumn(3);
                    var direction = lightLocalToWorld.GetColumn(2);

                    var range = light.range;
                    var rangeSq = Mathf.Max(range * range, 0.0001f);
                    
                    // Cone attenuation: URP packs cos(innerAngle/2) and the
                    // 1/(cos(inner)-cos(outer)) falloff scale into zw.
                    var spotAttenZW = new Vector2(0.0f, 1.0f);
                    if (light.lightType == LightType.Spot)
                    {
                        var unityLight = light.light;
                        float outerAngle = unityLight.spotAngle;
                        float innerAngle = unityLight.innerSpotAngle;

                        float cosOuter = Mathf.Cos(outerAngle * 0.5f * Mathf.Deg2Rad);
                        float cosInner = Mathf.Cos(innerAngle * 0.5f * Mathf.Deg2Rad);

                        float cosRangeRcp = 1.0f / Mathf.Max(cosInner - cosOuter, 0.0001f);

                        // zw matches URP's SLightData layout:
                        // z = -cosOuter * cosRangeRcp  (additive bias term)
                        // w =  cosRangeRcp             (scale term)
                        // In shader: saturate(dot(L, spotDir) * w + z)
                        spotAttenZW = new Vector2(-cosOuter * cosRangeRcp, cosRangeRcp);
                    }

                    additionalLightsData[lightIter] = new ShaderTypes.LightData
                    {
                        color = light.finalColor,
                        position = position,
                        spotDirection = new Vector4(-direction.x, -direction.y, -direction.z, 0.0f),
                        attenuation = new Vector4(1.0f / rangeSq, 0.25f, spotAttenZW.x, spotAttenZW.y),
                    };
                    lightIter++;
                }

                var lightIndicesBuffer = ShaderData.instance.GetLightIndicesBuffer(cullingResults.lightAndReflectionProbeIndexCount);
                var lightDataBuffer = ShaderData.instance.GetLightDataBuffer(additionalLightCount);
                lightDataBuffer.SetData(additionalLightsData);

                Shader.SetGlobalBuffer(AdditionalLightsBufferId, lightDataBuffer);
                Shader.SetGlobalBuffer(AdditionalLightsIndicesId, lightIndicesBuffer);
                Shader.SetGlobalVector(AdditionalLightsCountId, new Vector4(additionalLightCount, 0.0f, 0.0f, 0.0f));

                additionalLightsData.Dispose();
            }
            else
            {
                Shader.SetGlobalVector(AdditionalLightsCountId, Vector4.zero);
            }
        }

        private static int SetupPerObjectLightIndices(CullingResults cullingResults, NativeSlice<VisibleLight> visibleLights)
        {
            var lightIndexMap = cullingResults.GetLightIndexMap(Allocator.Temp);

            int globalDirectionalLightsCount = 0;
            int additionalLightsCount = 0;

            for (int i = 0; i < visibleLights.Length; i++)
            {
                if (additionalLightsCount >= MaxAdditionalLights)
                    break;

                var lightType = visibleLights[i].lightType;

                if (lightType == LightType.Directional)
                {
                    lightIndexMap[i] = -1;
                    globalDirectionalLightsCount++;
                }
                else if (lightType == LightType.Point || lightType == LightType.Spot)
                {
                    lightIndexMap[i] -= globalDirectionalLightsCount;
                    additionalLightsCount++;
                }
                else
                {
                    lightIndexMap[i] = -1;
                }
            }

            for (int i = globalDirectionalLightsCount + additionalLightsCount; i < lightIndexMap.Length; i++)
            {
                lightIndexMap[i] = -1;
            }

            cullingResults.SetLightIndexMap(lightIndexMap);

            if (additionalLightsCount > 0)
            {
                int lightAndReflectionProbeIndices = cullingResults.lightAndReflectionProbeIndexCount;
        
                cullingResults.FillLightAndReflectionProbeIndices(
                    ShaderData.instance.GetLightIndicesBuffer(lightAndReflectionProbeIndices));
            }

            lightIndexMap.Dispose();
            return additionalLightsCount;
        }
    }
}
