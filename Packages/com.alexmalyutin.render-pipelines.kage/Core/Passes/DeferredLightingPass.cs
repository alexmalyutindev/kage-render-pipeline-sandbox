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
        private readonly VisibleLight[] _additionalLights = new VisibleLight[256];

        private struct DeferredLightData
        {
            public int LightsCount;
            public VisibleLight[] Lights;
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
            DrawLights(renderGraph, gBufferData, cameraData, deferredLightData);
        }

        private class PassData
        {
            public Matrix4x4 View;
            public Matrix4x4 Proj;

            public int PointLightsCount;
            public VisibleLight[] PointLights;

            public int SpotLightsCount;
            public VisibleLight[] SpotLights;

            public Mesh PointLightVolume;
            public Mesh SpotLightVolume;

            public Material DeferredLightMaterial;

            public TextureHandle Depth;
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
            builder.AllowGlobalStateModification(true);

            passData.View = cameraData.Camera.worldToCameraMatrix;
            passData.Proj = cameraData.Camera.projectionMatrix;

            passData.PointLightVolume = _defaultResources.PointLightVolume;
            passData.SpotLightVolume = _defaultResources.SpotLightVolume;
            passData.DeferredLightMaterial = _defaultResources.PointLightMaterial;

            passData.PointLightsCount = deferredLightData.LightsCount;
            passData.PointLights = deferredLightData.Lights;


            builder.SetInputAttachment(gBufferData.GBuffer1, 0, AccessFlags.Read);
            builder.SetInputAttachment(gBufferData.GBuffer2, 1, AccessFlags.Read);

            builder.SetRenderAttachment(gBufferData.GBuffer0, 0, AccessFlags.Write);
            builder.SetRenderAttachmentDepth(gBufferData.Depth);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = context.cmd;

                // TODO: Camera relative rendering!
                cmd.SetViewProjectionMatrices(data.View, data.Proj);

                // TODO: Draw light by group of 8, using different stencil bit.
                cmd.SetGlobalInteger("_DeferredLight_StencilMask", 1);

                for (int lightIndex = 0; lightIndex < data.PointLightsCount; lightIndex++)
                {
                    ref var visibleLight = ref data.PointLights[lightIndex];
                    var localToWorld = visibleLight.localToWorldMatrix;
                    var position = localToWorld.GetColumn(3);
                    var direction = localToWorld.GetColumn(2);

                    float range = visibleLight.range;
                    var matrix = Matrix4x4.TRS(
                        position,
                        Quaternion.identity,
                        new Vector3(range, range, range)
                    );

                    float rangeSq = Mathf.Max(range * range, 0.0001f);
                    var attenuation = new Vector4(1.0f / rangeSq, 0.25f, 0.0f, 1.0f);

                    if (visibleLight.lightType == LightType.Spot)
                    {
                        float outerAngle = visibleLight.light.spotAngle;
                        float innerAngle = visibleLight.light.innerSpotAngle;
                        float cosOuter = Mathf.Cos(outerAngle * 0.5f * Mathf.Deg2Rad);
                        float cosInner = Mathf.Cos(innerAngle * 0.5f * Mathf.Deg2Rad);
                        float cosRangeRcp = 1.0f / Mathf.Max(cosInner - cosOuter, 0.0001f);
                        // TODO: Check shader code to bring into conformity spot light math!
                        attenuation.z = cosRangeRcp;
                        attenuation.w = -cosOuter * cosRangeRcp;
                    }

                    cmd.SetGlobalVector("_LightColor", visibleLight.finalColor);
                    cmd.SetGlobalVector("_LightPositionWS", new Vector4(position.x, position.y, position.z, 1.0f));
                    cmd.SetGlobalVector("_LightDirectionWS", new Vector4(-direction.x, -direction.y, -direction.z, 0.0f));
                    cmd.SetGlobalVector("_LightAttenuation", attenuation);

                    // Stencil
                    cmd.DrawMesh(data.PointLightVolume, matrix, data.DeferredLightMaterial, 0, 0);
                    // Lighting
                    cmd.DrawMesh(data.PointLightVolume, matrix, data.DeferredLightMaterial, 0, 1);
                }
            });
        }

        private DeferredLightData PrepareDeferredLightData(CullingResultData cullingResultData)
        {
            var lightsCount = 0;

            var visibleLights = cullingResultData.CullingResult.visibleLights;
            for (var i = 0; i < visibleLights.Length && i < _additionalLights.Length; i++)
            {
                var visibleLight = visibleLights[i];
                if (visibleLight.lightType == LightType.Point || visibleLight.lightType == LightType.Spot)
                {
                    _additionalLights[lightsCount] = visibleLight;
                    lightsCount++;
                }
            }

            var deferredLightData = new DeferredLightData()
            {
                LightsCount = lightsCount,
                Lights = _additionalLights,
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
    }
}
