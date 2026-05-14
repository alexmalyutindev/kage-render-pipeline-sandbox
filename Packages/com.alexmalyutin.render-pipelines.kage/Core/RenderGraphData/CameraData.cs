using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    public class CameraData : ContextItem
    {
        public Camera Camera;
        public RenderTextureDescriptor TargetDescriptor;
        public TextureHandle CameraBackBuffer;

        public override void Reset()
        {
            Camera = null;
        }
    }
}
