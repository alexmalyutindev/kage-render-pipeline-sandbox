using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    public class SSAOData : ContextItem
    {
        public TextureHandle OcclusionTexture;

        public override void Reset()
        {
            OcclusionTexture = TextureHandle.nullHandle;
        }
    }
}
