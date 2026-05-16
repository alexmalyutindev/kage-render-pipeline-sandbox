using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Rendering.KageRP
{
    [CreateAssetMenu(menuName = "Rendering/KageRP Asset", fileName = "KageRP_Asset")]
    public class KageRenderPipelineAsset : RenderPipelineAsset<KageRenderPipeline>
    {
        public KageRenderPipelineDefaultResources DefaultResources;

        [SerializeReference] 
        public List<AbstractRenderGraphPass> Passes = new()
        {
            new MainLightShadowPass(),
            new GBufferPass(),
            new DeferredLitPass(),
            new SkyboxPass(),
            new FinalBlitPass(),
        };
        

        protected override RenderPipeline CreatePipeline()
        {
            GraphicsSettings.useScriptableRenderPipelineBatching = true;
            return new KageRenderPipeline(this);
        }
    }
}
