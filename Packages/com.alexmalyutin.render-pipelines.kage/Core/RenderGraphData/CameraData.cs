using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    public class CameraData : ContextItem
    {
        public Camera Camera;
        public TextureHandle CameraActiveColor;
        public TextureHandle CameraActiveDepth;

        public RenderTextureDescriptor CameraBackBufferDescriptor;
        public TextureHandle CameraBackBuffer;

        public override void Reset()
        {
            Camera = null;
        }
    }
}
