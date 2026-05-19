using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    public class KageRenderPipeline : RenderPipeline
    {
        private readonly KageRenderPipelineAsset _asset;
        private readonly RenderGraph _renderGraph = new("Kage RenderGraph");
        private readonly ContextContainer _frameData = new();
        private readonly Dictionary<Camera, ContextContainer> _persistentFrameData = new();

        private readonly List<AbstractRenderGraphPass> _passes = new();

        public KageRenderPipeline(KageRenderPipelineAsset asset)
        {
            _asset = asset;
            foreach (var pass in asset.Passes) _passes.Add(pass);
        }

        protected override void Render(ScriptableRenderContext context, List<Camera> cameras)
        {
            // TODO: Setup blit shaders!
            // Blitter.Initialize(BlitShader, BlitColorAndDepth);

            foreach (var camera in cameras)
            {
                var cmd = CommandBufferPool.Get();

                var sampler = ProfilingSampler.Get(camera.cameraType);

                var rgParams = new RenderGraphParameters()
                {
                    commandBuffer = cmd,
                    executionId = camera.GetEntityId(),
                    currentFrameIndex = Time.frameCount,
                    scriptableRenderContext = context,
                    renderTextureUVOriginStrategy = RenderTextureUVOriginStrategy.BottomLeft,
                    rendererListCulling = true,
                };

                // NOTE: Init frame data
                {
                    _frameData.Dispose();
                    if (!_persistentFrameData.TryGetValue(camera, out var persistentFrameContext))
                    {
                        persistentFrameContext = new ContextContainer();
                        _persistentFrameData.Add(camera, persistentFrameContext);
                    }

                    var persistentFrameData = _frameData.Create<PersistentFrameData>();
                    persistentFrameData.Context = persistentFrameContext;
                }

                foreach (var pass in _passes)
                {
                    pass.Setup(_asset, this);
                }

                if (camera.cameraType is CameraType.Game)
                {
                    // TODO: Make interface to insert custom setup logic
                    // DynamicGI.UpdateEnvironment();
                }

                try
                {
                    _renderGraph.BeginRecording(rgParams);
                    using var _ = new RenderGraphProfilingScope(_renderGraph, sampler);

                    InitCameraData(camera, _renderGraph, _frameData);

                    // NOTE: Culling
                    {
                        context.SetupCameraProperties(camera);
                        camera.TryGetCullingParameters(out var cullingParameters);
                        foreach (var pass in _passes) pass.BeforeCameraCulling(ref cullingParameters);
                        var cullingResultData = Culling(context, _frameData, ref cullingParameters);
                        // TODO: Don't like that lighting data initialization here.
                        InitLightingData(_frameData, cullingResultData);

                        foreach (var pass in _passes) pass.AfterCameraCulling(context, cullingResultData, _frameData);
                    }

                    // TODO: Use backbuffer as GBuffer0?
                    // TODO: Init main lighting data
                    // TODO: Move this into PASS
                    SetupLighting(_renderGraph, _frameData);

                    foreach (var pass in _passes)
                    {
                        // TODO: Use try catch only in Editor or debug!
                        try
                        {
                            pass.LastExecutionException = null;
                            pass.Record(_renderGraph, _frameData);
                        }
                        catch (Exception ex)
                        {
                            pass.LastExecutionException = ex;
                            Debug.LogException(ex);
                        }
                    }
                }
                catch (Exception e)
                {
                    Debug.LogException(e);
                }
                finally
                {
                    _renderGraph.EndRecordingAndExecute();
                }

                // TODO: Do not execute commands, when exception occured!
                context.ExecuteCommandBuffer(rgParams.commandBuffer);
                rgParams.commandBuffer.Clear();

                DrawGizmos(context, camera);

                context.Submit();

                CommandBufferPool.Release(rgParams.commandBuffer);
            }

            _renderGraph.EndFrame();
        }

        protected override void Dispose(bool disposing)
        {
            base.Dispose(disposing);
            foreach (var context in _persistentFrameData) context.Value.Dispose();
            ShaderData.instance.Dispose();
        }

        private CullingResultData Culling(ScriptableRenderContext context, ContextContainer frameData,
            ref ScriptableCullingParameters cullingParameters)
        {
            var cullingResultData = frameData.Create<CullingResultData>();
            cullingResultData.CullingResult = context.Cull(ref cullingParameters);
            return cullingResultData;
        }

        private static void InitLightingData(ContextContainer frameData, CullingResultData cullingResultData)
        {
            var lightingData = frameData.GetOrCreate<LightingData>();
            lightingData.MainLightIndex = -1;
            for (var lightIndex = 0; lightIndex < cullingResultData.CullingResult.visibleLights.Length; lightIndex++)
            {
                var visibleLight = cullingResultData.CullingResult.visibleLights[lightIndex];
                if (visibleLight.lightType == LightType.Directional)
                {
                    lightingData.MainLightIndex = lightIndex;
                    break;
                }
            }
        }

        private static void InitCameraData(Camera camera, RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Create<CameraData>();

            cameraData.Camera = camera;
            cameraData.CameraColorDescriptor = new RenderTextureDescriptor(camera.pixelWidth, camera.pixelHeight);
            cameraData.CameraBackBuffer = renderGraph.ImportBackbuffer(
                new RenderTargetIdentifier(BuiltinRenderTextureType.CameraTarget)
            );
        }

        private class SetupLightingPassData
        {
            public Vector4 MainLightDirection;
            public Color MainLightColor;
        }

        private void SetupLighting(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cullingResultData = frameData.Get<CullingResultData>();

            using var builder = _renderGraph.AddUnsafePass<SetupLightingPassData>("Setup Lighting", out var passData);

            passData.MainLightColor = Color.black;
            foreach (var visibleLight in cullingResultData.CullingResult.visibleLights)
            {
                if (visibleLight.lightType == LightType.Directional)
                {
                    passData.MainLightColor = visibleLight.finalColor;
                    passData.MainLightDirection = -visibleLight.localToWorldMatrix.GetColumn(2);
                    break;
                }
            }

            builder.AllowPassCulling(false);
            builder.AllowGlobalStateModification(true);
            builder.SetRenderFunc<SetupLightingPassData>(static (data, context) =>
            {
                context.cmd.SetGlobalVector("_MainLightPosition", data.MainLightDirection);
                context.cmd.SetGlobalColor("_MainLightColor", data.MainLightColor);
            });
        }


        private static void DrawGizmos(ScriptableRenderContext context, Camera camera)
        {
#if UNITY_EDITOR
            if (camera.cameraType is CameraType.SceneView)
            {
                ScriptableRenderContext.EmitWorldGeometryForSceneView(camera);
            }

            if (camera.cameraType is CameraType.Game or CameraType.SceneView &&
                UnityEditor.Handles.ShouldRenderGizmos())
            {
                context.DrawGizmos(camera, GizmoSubset.PreImageEffects);
                context.DrawGizmos(camera, GizmoSubset.PostImageEffects);
                context.DrawWireOverlay(camera);
                // context.DrawUIOverlay(camera);
            }
#endif
        }
    }
}
