using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [System.Serializable]
    public class HBAOPlus : AbstractRenderGraphPass
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
        
        private class HBAOPassData
        {
            public TextureHandle GBuffer2;
            public TextureHandle InterleavedDepth;
            public TextureHandle Occlusion;

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

                passData.FullWidth = fullWidth;
                passData.FullHeight = fullHeight;
                passData.FullResDepthTex = prevFrameDepth;
                builder.UseTexture(passData.FullResDepthTex);

                passData.DeinterleavedArrayTex = deinterleavedArrayTex;
                builder.UseTexture(passData.DeinterleavedArrayTex, AccessFlags.Write);

                passData.Shader = _deinterleavedDepth;
                passData.KernelId = _deinterleavedDepth.FindKernel("CSMain");
                passData.DeinterleaveParams = new Vector4(fullWidth, fullHeight, lowWidth, lowHeight);

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

            using (var builder = renderGraph.AddRasterRenderPass<HBAOPassData>("HBAO+", out var passData))
            {
                builder.AllowPassCulling(false);
                builder.AllowGlobalStateModification(true);

                var frameDesc = cameraData.CameraBackBufferDescriptor;
                var ssaoDesc = new TextureDesc(frameDesc.width / 4, frameDesc.height / 4)
                {
                    name = "_OcclusionTexture_HBAO+",
                    format = GraphicsFormat.R8_UNorm,
                    clearBuffer = false,
                    clearColor = Color.clear,
                    memoryless = RenderTextureMemoryless.None,
                };
                passData.Occlusion = renderGraph.CreateTexture(ssaoDesc);

                var ssaoData = frameData.Create<SSAOData>();
                ssaoData.OcclusionTexture = passData.Occlusion;

                passData.Material = _defaultResources.SSAOMaterial;
                passData.InterleavedDepth = deinterleavedArrayTex;
                builder.UseTexture(passData.InterleavedDepth);

                builder.SetRenderAttachment(passData.Occlusion, 0, AccessFlags.ReadWrite);
                builder.SetGlobalTextureAfterPass(passData.Occlusion, Shader.PropertyToID("_OcclusionTexture"));
                builder.SetRenderFunc<HBAOPassData>(static (data, context) =>
                {
                    var cmd = context.cmd;
                    // TODO: Use material property block!
                    cmd.SetGlobalTexture("_DeinterleavedDepthArray", data.InterleavedDepth);
                    cmd.DrawProcedural(Matrix4x4.identity, data.Material, 5, MeshTopology.Triangles, 3);
                });
            }
        }
    }
}
