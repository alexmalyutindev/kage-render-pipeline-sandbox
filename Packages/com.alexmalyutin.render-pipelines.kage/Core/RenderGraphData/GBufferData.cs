using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    public class GBufferData : ContextItem
    {
        public TextureHandle GBuffer0; // 32 bit <- [ ForwardLit + Emission ] (RGB32) <- Final HDR target
        public TextureHandle GBuffer1; // 32 bit <- [ NormalVS.xy | Metallic | Smoothness ] (R8G8B8A8)
        public TextureHandle GBuffer2; // 32 bit <- [ Albedo.rgb  | AO ] Color can be HDR
        public TextureHandle Depth; // 16 bit

        public override void Reset()
        {
            GBuffer0 = TextureHandle.nullHandle;
            GBuffer1 = TextureHandle.nullHandle;
            GBuffer2 = TextureHandle.nullHandle;
            Depth = TextureHandle.nullHandle;
        }
    }
}
