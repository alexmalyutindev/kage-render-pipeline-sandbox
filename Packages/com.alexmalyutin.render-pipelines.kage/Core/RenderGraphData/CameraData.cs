using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    public class CameraData : ContextItem
    {
        public Camera Camera;
        public RenderTextureDescriptor CameraBackBufferDescriptor;
        public TextureHandle CameraBackBuffer;
        public TextureHandle CameraActiveColor;

        public override void Reset()
        {
            Camera = null;
        }
    }
}
