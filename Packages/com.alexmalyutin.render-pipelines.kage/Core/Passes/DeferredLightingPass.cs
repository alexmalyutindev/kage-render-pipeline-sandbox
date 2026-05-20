using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public class DeferredLightingPass : AbstractRenderGraphPass
    {
        private KageRenderPipelineDefaultResources _defaultResources;
        private readonly VisibleLight[] _pointLights = new VisibleLight[128];

        private struct DeferredLightData
        {
            public int PointLightsCount;
            public VisibleLight[] PointLights;
        }

        public override void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline)
        {
            _defaultResources = asset.DefaultResources;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<CameraData>();
            var gBufferData = frameData.Get<GBufferData>();
            var cullingResultData = frameData.Get<CullingResultData>();

            var deferredLightData = PrepareDeferredLightData(cullingResultData);
            // StencilPrepass(renderGraph, gBufferData, deferredLightData);
            DrawLights(renderGraph, gBufferData, cameraData, deferredLightData);
        }

        private class PassData
        {
            public Matrix4x4 View;
            public Matrix4x4 Proj;

            public int PointLightsCount;
            public VisibleLight[] PointLights;

            public Mesh PointLightMesh;
            public Material PointLightMaterial;

            public TextureHandle Depth;
        }

        private void StencilPrepass(RenderGraph renderGraph, GBufferData gBufferData, DeferredLightData deferredLightData)
        {
            using var builder = renderGraph.AddRasterRenderPass<PassData>("Deferred Lighting Stencil", out var passData);
            builder.AllowPassCulling(false);

            passData.PointLightMesh = _defaultResources.PointLightMesh;
            passData.PointLightMaterial = _defaultResources.PointLightMaterial;
            passData.PointLightsCount = deferredLightData.PointLightsCount;
            passData.PointLights = deferredLightData.PointLights;

            builder.UseTexture(gBufferData.Depth, AccessFlags.Read);
            builder.SetRenderAttachment(gBufferData.GBuffer0, 0);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                // TODO: Camera relative rendering!
                for (int lightIndex = 0; lightIndex < data.PointLightsCount; lightIndex++)
                {
                    var matrix = CreatePointLightData(data.PointLights[lightIndex]);
                    context.cmd.DrawMesh(data.PointLightMesh, matrix, data.PointLightMaterial, 0, 1);
                }
            });
        }

        private void DrawLights(
            RenderGraph renderGraph, 
            GBufferData gBufferData, 
            CameraData cameraData,
            DeferredLightData deferredLightData
        )
        {
            using var builder = renderGraph.AddRasterRenderPass<PassData>("Deferred Lighting", out var passData);
            builder.AllowPassCulling(false);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            passData.PointLightMesh = _defaultResources.PointLightMesh;
            passData.PointLightMaterial = _defaultResources.PointLightMaterial;
            passData.PointLightsCount = deferredLightData.PointLightsCount;
            passData.PointLights = deferredLightData.PointLights;

            builder.SetInputAttachment(gBufferData.GBuffer1, 0, AccessFlags.Read);
            builder.SetInputAttachment(gBufferData.GBuffer2, 1, AccessFlags.Read);

            builder.SetRenderAttachment(gBufferData.GBuffer0, 0, AccessFlags.Write);
            builder.SetRenderAttachmentDepth(gBufferData.Depth);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                // TODO: Camera relative rendering!
                context.cmd.SetViewProjectionMatrices(data.View, data.Proj);

                for (int lightIndex = 0; lightIndex < data.PointLightsCount; lightIndex++)
                {
                    var matrix = CreatePointLightData(data.PointLights[lightIndex]);
                    context.cmd.DrawMesh(data.PointLightMesh, matrix, data.PointLightMaterial, 0, 0);
                }
            });
        }

        private DeferredLightData PrepareDeferredLightData(CullingResultData cullingResultData)
        {
            var pointLightsCount = 0;
            var visibleLights = cullingResultData.CullingResult.visibleLights;
            for (var i = 0; i < visibleLights.Length && i < _pointLights.Length; i++)
            {
                var visibleLight = visibleLights[i];
                if (visibleLight.lightType == LightType.Point)
                {
                    _pointLights[pointLightsCount] = visibleLight;
                    pointLightsCount++;
                }
            }

            var deferredLightData = new DeferredLightData()
            {
                PointLightsCount = pointLightsCount,
                PointLights = _pointLights,
            };
            return deferredLightData;
        }
        
        internal static void GetPunctualLightDistanceAttenuation(float lightRange, ref Vector4 lightAttenuation)
        {
            // Light attenuation in universal matches the unity vanilla one (HINT_NICE_QUALITY).
            // attenuation = 1.0 / distanceToLightSqr
            // The smoothing factor makes sure that the light intensity is zero at the light range limit.
            // (We used to offer two different smoothing factors.)

            // The current smoothing factor matches the one used in the Unity lightmapper.
            // smoothFactor = (1.0 - saturate((distanceSqr * 1.0 / lightRangeSqr)^2))^2
            float lightRangeSqr = lightRange * lightRange;
            float fadeStartDistanceSqr = 0.8f * 0.8f * lightRangeSqr;
            float fadeRangeSqr = (fadeStartDistanceSqr - lightRangeSqr);
            float lightRangeSqrOverFadeRangeSqr = -lightRangeSqr / fadeRangeSqr;
            float oneOverLightRangeSqr = 1.0f / Mathf.Max(0.0001f, lightRangeSqr);

            // On all devices: Use the smoothing factor that matches the GI.
            lightAttenuation.x = oneOverLightRangeSqr;
            lightAttenuation.y = lightRangeSqrOverFadeRangeSqr;
        }

        private static Matrix4x4 CreatePointLightData(VisibleLight pointLight)
        {
            var position = pointLight.light.transform.position;
            // position = viewMatrix.MultiplyPoint(position);
            var matrix = new Matrix4x4();
            matrix.SetRow(0, position);
            matrix.SetRow(1, pointLight.finalColor);
            matrix.SetRow(2, new Vector4(pointLight.range, 0.0f));

            var lightAttenuation = Vector4.one;
            GetPunctualLightDistanceAttenuation(pointLight.range, ref lightAttenuation);
            matrix.SetRow(3, lightAttenuation);
            return matrix;
        }
    }
}
