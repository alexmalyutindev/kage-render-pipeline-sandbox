using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Serialization;

namespace Rendering.KageRP
{
    [Serializable]
    public class BloomPass : AbstractRenderGraphPass
    {
        [Range(1, 5)] public int BlurTaps = 3;
        [Range(0.0f, 2.0f)] public float Threshold = 1.0f;
        [Range(0.0f, 1.0f)] public float Scatter = 1.0f;
        [Min(0.0f)] public float ClampMax = 100.0f;
        [Range(0.5f, 2.0f)] public float Spread = 1.0f;

        private KageRenderPipelineDefaultResources _defaultResources;
        private readonly List<TextureHandle> _mips;

        public BloomPass()
        {
            _mips = new List<TextureHandle>(BlurTaps);
        }

        private class PassData
        {
            public TextureHandle Input;
            public List<TextureHandle> Mips;
            public Material Material;
            public int MipsCount;
            public Vector4 Params;
            public Vector4 Params2;
        }
        
        public override void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline)
        {
            _defaultResources = asset.DefaultResources;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (_defaultResources.BloomMaterial == null) return;

            var cameraData = frameData.Get<CameraData>();

            using var builder = renderGraph.AddUnsafePass<PassData>("Bloom", out var passData);
            builder.AllowPassCulling(false);

            passData.Material = _defaultResources.BloomMaterial;
            var thresholdKnee = Threshold * 0.5f; // Hardcoded soft knee
            passData.Params = new Vector4(Scatter, ClampMax, Threshold, thresholdKnee);
            passData.Params2 = new Vector4(Spread, 0.0f);

            passData.Input = cameraData.CameraActiveColor;
            builder.UseTexture(passData.Input);

            var frameDesc = cameraData.CameraActiveColor.GetDescriptor(renderGraph);
            var decs = new TextureDesc(frameDesc.width, frameDesc.height)
            {
                name = "_BlurBuffer",
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGB111110Float, false),
            };

            _mips.Clear();
            passData.Mips = _mips;
            passData.MipsCount = BlurTaps;
            for (int mip = 0; mip < BlurTaps; mip++)
            {
                decs.width /= 2;
                decs.height /= 2;
                passData.Mips.Add(builder.CreateTransientTexture(decs));
            }

            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                cmd.SetGlobalVector("_Params", data.Params);
                cmd.SetGlobalVector("_Params2", data.Params2);

                cmd.Blit(data.Input, data.Mips[0], data.Material, 0);
                for (int i = 0; i < data.MipsCount - 1; i++) cmd.Blit(data.Mips[i], data.Mips[i + 1], data.Material, 1);
                for (int i = data.MipsCount - 1; i > 0; i--) cmd.Blit(data.Mips[i], data.Mips[i - 1], data.Material, 2);
                cmd.Blit(data.Mips[0], data.Input, data.Material, 3);
            });
        }
    }
}
