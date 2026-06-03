using System;
using System.Collections.Generic;
using Rendering.KageRP;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

[Serializable]
public class LocalShadowPass : AbstractRenderGraphPass
{
    private const int MaxShadowCount = 4;

    private static readonly List<LocalShadow> LocalShadows = new();
    private static readonly List<Material> TempMaterials = new();

    public ShadowMapResolution Resolution = ShadowMapResolution._256;

    private static Matrix4x4[] _worldToShadow = new Matrix4x4[MaxShadowCount];

    public static void Register(LocalShadow localShadow)
    {
        LocalShadows.Add(localShadow);
    }

    public static void Unregister(LocalShadow localShadow)
    {
        LocalShadows.Remove(localShadow);
    }

    public override void AfterCameraCulling(
        ScriptableRenderContext context,
        CullingResultData cullingResultData,
        ContextContainer frameData
    )
    {
        // TODO: Make LocalShadows culling.
    }

    public class PassData
    {
        public TextureHandle LocalShadowMap;
        public VisibleLight MainLight;
        public Matrix4x4[] WorldToShadowMap;
        public List<LocalShadow> LocalShadowCaster;
    }

    public override void Record(RenderGraph renderGraph, ContextContainer frameData)
    {
        var lightingData = frameData.Get<LightingData>();
        if (lightingData.MainLightIndex < 0)
        {
            Shader.SetGlobalFloat("_EnableLocalShadow", 0.0f);
            return;
        }

        var cullingResultData = frameData.Get<CullingResultData>();
        var mainLight = cullingResultData.CullingResult.visibleLights[lightingData.MainLightIndex];

        using var builder = renderGraph.AddUnsafePass<PassData>("LocalShadows", out var passData);
        builder.AllowPassCulling(false);

        passData.MainLight = mainLight;
        passData.LocalShadowCaster = LocalShadows;
        passData.WorldToShadowMap = _worldToShadow;

        var desc = new TextureDesc((int)Resolution, (int)Resolution)
        {
            name = "_LocalShadowAtlas",
            format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.Shadowmap, false),
            depthBufferBits = DepthBits.Depth16,
            filterMode = FilterMode.Bilinear,
            isShadowMap = true,
            clearBuffer = false,

            wrapMode = TextureWrapMode.Clamp,
            dimension = TextureDimension.Tex2DArray,
            slices = MaxShadowCount,
        };
        passData.LocalShadowMap = renderGraph.CreateTexture(desc);
        builder.UseTexture(passData.LocalShadowMap);

        builder.SetGlobalTextureAfterPass(passData.LocalShadowMap, Shader.PropertyToID("_LocalShadow"));
        builder.SetRenderFunc<PassData>(static (data, context) =>
        {
            var cmd = context.cmd;

            if (data.LocalShadowCaster.Count == 0)
            {
                cmd.SetGlobalFloat("_EnableLocalShadow", 0.0f);
                return;
            }

            var mainLightDirection = -data.MainLight.localToWorldMatrix.GetColumn(2);
            var shadowBias = new Vector4(data.MainLight.light.shadowBias, 0.0f);
            cmd.SetGlobalVector("_MainLightPosition", mainLightDirection);
            cmd.SetGlobalVector("_ShadowBias", shadowBias);

            for (var casterIndex = 0;
                casterIndex < data.LocalShadowCaster.Count && casterIndex < MaxShadowCount;
                casterIndex++)
            {
                var localShadow = data.LocalShadowCaster[casterIndex];
                var bounds = localShadow.Renderers[0].bounds;
                for (int i = 1; i < localShadow.Renderers.Count; i++)
                {
                    if (localShadow.Renderers[i] != null) bounds.Encapsulate(localShadow.Renderers[i].bounds);
                }

                var id = new RenderTargetIdentifier(data.LocalShadowMap, 0, CubemapFace.Unknown, casterIndex);
                cmd.SetRenderTarget(
                    id, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare,
                    id, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store
                );
                cmd.ClearRenderTarget(
                    true,
                    false,
                    Color.clear,
                    SystemInfo.usesReversedZBuffer ? 1.0f : 0.0f,
                    0
                );

                localShadow.GetViewProjectionForLightShadow(data.MainLight.light, out var view, out var proj);
                cmd.SetViewProjectionMatrices(view, proj);

                foreach (var renderer in localShadow.Renderers)
                {
                    renderer.GetSharedMaterials(TempMaterials);
                    for (var submeshIndex = 0; submeshIndex < TempMaterials.Count; submeshIndex++)
                    {
                        var shadowPass = 1;
                        var material = TempMaterials[submeshIndex];
                        if (material.passCount > shadowPass)
                        {
                            cmd.DrawRenderer(renderer, material, submeshIndex, shadowPass);
                        }
                    }

                    renderer.shadowCastingMode = ShadowCastingMode.Off;
                }

                data.WorldToShadowMap[casterIndex] = CalculateWorldToShadowMatrix(view, proj);
            }

            cmd.SetGlobalFloat("_EnableLocalShadow", 1.0f);
            cmd.SetGlobalMatrixArray("_WorldToLocalShadow", data.WorldToShadowMap);
        });
    }

    private static readonly Matrix4x4 BiasMat = new(
        new Vector4(0.5f, 0f, 0f, 0f),
        new Vector4(0f, 0.5f, 0f, 0f),
        new Vector4(0f, 0f, -0.5f, 0f),
        new Vector4(0.5f, 0.5f, 0.5f, 1f)
    );

    public static Matrix4x4 CalculateWorldToShadowMatrix(Matrix4x4 view, Matrix4x4 proj)
    {
        return BiasMat * proj * view;
    }
}
