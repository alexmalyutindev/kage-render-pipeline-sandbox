using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [System.Serializable]
    public class DeinterleavedDepthPass : AbstractRenderGraphPass
    {
        private static readonly int _DeinterleaveParams = Shader.PropertyToID("_DeinterleaveParams");
        private static readonly int _FullResDepth = Shader.PropertyToID("_FullResDepth");
        private static readonly int _DeinterleavedDepthArray = Shader.PropertyToID("_DeinterleavedDepthArray");

        [SerializeField] private ComputeShader _deinterleavedDepth;
        private KageRenderPipelineDefaultResources _defaultResources;

        // Render Graph requires all data used in the lambda execution to be in PassData
        private class PassData
        {
            public ComputeShader Shader;
            public int KernelId;

            public Vector4 DeinterleaveParams;
            public int FullWidth;
            public int FullHeight;

            // Handles to let Render Graph track data dependencies
            public TextureHandle FullResDepthTex;
            public TextureHandle DeinterleavedArrayTex;
        }
        
        private class PassData2
        {
            public TextureHandle GBuffer2;
            public TextureHandle InterleavedDepth;
            public TextureHandle Target;

            public Material Material;
        }

        public override void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline)
        {
            _defaultResources = asset.DefaultResources;
        }

        public override void Record(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (_deinterleavedDepth == null) return;

            var cameraData = frameData.Get<CameraData>();
            var gBufferData = frameData.Get<GBufferData>();

            int fullWidth = cameraData.CameraBackBufferDescriptor.width;
            int fullHeight = cameraData.CameraBackBufferDescriptor.height;
            int lowWidth = fullWidth / 4;
            int lowHeight = fullHeight / 4;

            var persistentFrameData = frameData.Get<PersistentFrameData>();
            if (!persistentFrameData.Context.Contains<PrevFrameBufferData>()) return;
            var prevFrameBufferData = persistentFrameData.Context.Get<PrevFrameBufferData>();
            var prevFrameDepth = prevFrameBufferData.GetFrameDepth(renderGraph);
            if (!prevFrameDepth.IsValid()) return;

            var arrayDesc = new TextureDesc(lowWidth, lowHeight)
            {
                colorFormat = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RHalf, false),
                dimension = TextureDimension.Tex2DArray,
                slices = 16,
                enableRandomWrite = true,
                name = "_DeinterleavedDepthArray"
            };

            var deinterleavedArrayTex = renderGraph.CreateTexture(arrayDesc);

            using (var builder = renderGraph.AddComputePass<PassData>("DeinterleavedDepthPass", out var passData))
            {
                builder.AllowPassCulling(false);
                // builder.EnableAsyncCompute(true);

                passData.FullWidth = fullWidth;
                passData.FullHeight = fullHeight;
                passData.FullResDepthTex = gBufferData.Depth;
                builder.UseTexture(passData.FullResDepthTex);

                passData.DeinterleavedArrayTex = deinterleavedArrayTex;
                builder.UseTexture(passData.DeinterleavedArrayTex, AccessFlags.Write);

                passData.Shader = _deinterleavedDepth;
                passData.KernelId = _deinterleavedDepth.FindKernel("CSMain");
                passData.DeinterleaveParams = new Vector4(fullWidth, fullHeight, lowWidth, lowHeight);

                builder.SetGlobalTextureAfterPass(passData.DeinterleavedArrayTex,
                    Shader.PropertyToID("_DeinterleavedDepthArray"));
                builder.SetRenderFunc<PassData>(static (data, context) =>
                {
                    var cmd = context.cmd;

                    cmd.SetComputeVectorParam(data.Shader, _DeinterleaveParams, data.DeinterleaveParams);

                    cmd.SetComputeTextureParam(data.Shader, data.KernelId, _FullResDepth, data.FullResDepthTex);
                    cmd.SetComputeTextureParam(data.Shader, data.KernelId, _DeinterleavedDepthArray, data.DeinterleavedArrayTex);

                    int threadGroupsX = Mathf.CeilToInt(data.FullWidth / 8.0f);
                    int threadGroupsY = Mathf.CeilToInt(data.FullHeight / 8.0f);

                    cmd.DispatchCompute(data.Shader, data.KernelId, threadGroupsX, threadGroupsY, 1);
                });
            }

            using (var builder = renderGraph.AddUnsafePass<PassData2>("HBAO+", out var passData))
            {
                passData.Material = _defaultResources.SSAOMaterial;
                passData.GBuffer2 = gBufferData.GBuffer2;
                builder.UseTexture(passData.GBuffer2);

                passData.InterleavedDepth = deinterleavedArrayTex;
                builder.UseTexture(passData.InterleavedDepth);
                passData.Target = cameraData.CameraActiveColor;
                builder.UseTexture(passData.Target, AccessFlags.Write);

                builder.SetRenderFunc<PassData2>(static (data, context) =>
                {
                    var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                    cmd.SetGlobalTexture("_GBuffer2", data.GBuffer2);
                    cmd.Blit(data.GBuffer2, data.Target, data.Material, 5);
                });
            }
        }
    }
}
