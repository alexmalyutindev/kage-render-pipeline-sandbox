using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Rendering.KageRP
{
    [CreateAssetMenu(menuName = "Rendering/KageRP Asset", fileName = "KageRP_Asset")]
    public class KageRenderPipelineAsset : RenderPipelineAsset<KageRenderPipeline>
    {
        public KageRenderPipelineDefaultResources DefaultResources;
        public bool UseSRPBatcher = true;

        [SerializeReference] 
        public List<AbstractRenderGraphPass> Passes = new()
        {
            new MainLightShadowPass(),
            new ForwardGBufferPass(),
            new DeferredLightingPass(),
            new SkyboxPass(),
            new FinalBlitPass(),
        };

        public override Material defaultMaterial => DefaultResources.DefaultMaterials.Opaque;
        public override Shader defaultShader => DefaultResources.DefaultMaterials.Opaque.shader;

        protected override RenderPipeline CreatePipeline()
        {
            GraphicsSettings.useScriptableRenderPipelineBatching = UseSRPBatcher;
            return new KageRenderPipeline(this);
        }
    }
}
