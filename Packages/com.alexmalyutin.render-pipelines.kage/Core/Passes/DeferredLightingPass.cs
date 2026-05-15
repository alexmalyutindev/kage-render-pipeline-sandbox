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
            using var builder = renderGraph.AddRasterRenderPass<PassData>("DeferredLighting Stencil", out var passData);
            builder.AllowPassCulling(false);

            passData.PointLightMesh = _defaultResources.PointLightMesh;
            passData.PointLightMaterial = _defaultResources.PointLightMaterial;
            passData.PointLightsCount = deferredLightData.PointLightsCount;
            passData.PointLights = deferredLightData.PointLights;

            builder.SetRenderAttachmentDepth(gBufferData.Depth, AccessFlags.ReadWrite);
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

        private void DrawLights(RenderGraph renderGraph, GBufferData gBufferData, CameraData cameraData,
            DeferredLightData deferredLightData)
        {
            using var builder = renderGraph.AddRasterRenderPass<PassData>("DeferredLighting", out var passData);
            builder.AllowPassCulling(false);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            passData.PointLightMesh = _defaultResources.PointLightMesh;
            passData.PointLightMaterial = _defaultResources.PointLightMaterial;
            passData.PointLightsCount = deferredLightData.PointLightsCount;
            passData.PointLights = deferredLightData.PointLights;

            builder.UseTexture(gBufferData.GBuffer1);
            builder.UseTexture(gBufferData.GBuffer2);

            builder.SetRenderAttachment(gBufferData.GBuffer0, 0);
            builder.SetRenderAttachmentDepth(gBufferData.Depth, AccessFlags.Read);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                // TODO: Camera relative rendering!
                for (int lightIndex = 0; lightIndex < data.PointLightsCount; lightIndex++)
                {
                    context.cmd.SetViewProjectionMatrices(data.View, data.Proj);
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

        private static Matrix4x4 CreatePointLightData(VisibleLight pointLight)
        {
            var position = pointLight.light.transform.position;
            var matrix = new Matrix4x4();
            matrix.SetRow(0, position);
            matrix.SetRow(1, pointLight.finalColor);
            matrix.SetRow(2, new Vector4(pointLight.range, 0.0f));
            return matrix;
        }
    }
}
