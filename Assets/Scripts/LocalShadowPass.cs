using System.Collections.Generic;
using Rendering.KageRP;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

public class LocalShadowPass : AbstractRenderGraphPass
{
    private static readonly List<LocalShadow> LocalShadows = new();
    private static readonly List<Material> TempMaterials = new();

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
        public List<LocalShadow> LocalShadows;
    }

    public override void Record(RenderGraph renderGraph, ContextContainer frameData)
    {
        var lightingData = frameData.Get<LightingData>();
        if (lightingData.MainLightIndex < 0) return;

        var cullingResultData = frameData.Get<CullingResultData>();
        var mainLight = cullingResultData.CullingResult.visibleLights[lightingData.MainLightIndex];

        using var builder = renderGraph.AddUnsafePass<PassData>("LocalShadows", out var passData);
        builder.AllowPassCulling(false);

        passData.MainLight = mainLight;
        passData.LocalShadows = LocalShadows;

        var desc = new TextureDesc(256, 256)
        {
            name = "_LocalShadowAtlas",
            format = GraphicsFormat.D16_UNorm,
            depthBufferBits = DepthBits.Depth16,
            isShadowMap = true,
        };
        passData.LocalShadowMap = renderGraph.CreateTexture(desc);
        builder.UseTexture(passData.LocalShadowMap, AccessFlags.Write);

        builder.SetRenderFunc<PassData>(static (data, context) =>
        {
            var cmd = context.cmd;

            foreach (var localShadow in data.LocalShadows)
            {
                var bounds = localShadow.Renderers[0].bounds;
                for (int i = 1; i < localShadow.Renderers.Count; i++)
                {
                    if (localShadow.Renderers[i] != null) bounds.Encapsulate(localShadow.Renderers[i].bounds);
                }

                localShadow.GetViewProjectionForLightShadow(data.MainLight.light, out var view, out var proj);
                
                cmd.SetRenderTarget(data.LocalShadowMap);
                cmd.ClearRenderTarget(true, false, Color.clear);
                cmd.SetViewProjectionMatrices(view, proj);

                localShadow.Props.SetFloat("_EnableLocalShadow", 1.0f);
                localShadow.Props.SetTexture("_LocalShadow", data.LocalShadowMap);
                localShadow.Props.SetMatrix("_WorldToLocalShadow", CalculateWorldToShadowMatrix(view, proj));
                localShadow.Props.SetVector("_MainLightPosition", -data.MainLight.localToWorldMatrix.GetColumn(2));
                localShadow.Props.SetVector("_ShadowBias", new Vector4(0.03f, 0.0f));

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

                    renderer.SetPropertyBlock(localShadow.Props);
                }
            }
        });
    }


    public static Matrix4x4 CalculateWorldToShadowMatrix(Matrix4x4 view, Matrix4x4 proj)
    {
        Matrix4x4 viewProj = proj * view;

        Matrix4x4 scaleBias = Matrix4x4.identity;
        scaleBias.m00 = 0.5f; scaleBias.m03 = 0.5f;
        scaleBias.m11 = 0.5f; scaleBias.m13 = 0.5f;
        scaleBias.m22 = 0.5f; scaleBias.m23 = 0.5f;

        if (SystemInfo.usesReversedZBuffer)
        {
            scaleBias.m22 = -0.5f;
            scaleBias.m23 = 0.5f;
        }

        return scaleBias * viewProj;
    }
}
