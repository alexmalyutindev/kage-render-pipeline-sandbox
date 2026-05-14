using UnityEngine;
using UnityEngine.Rendering;

namespace Rendering.KageRP
{
    public class LightingData : ContextItem
    {
        private static readonly Matrix4x4 BiasMat = new(
            new Vector4(0.5f, 0f, 0f, 0f),
            new Vector4(0f, 0.5f, 0f, 0f),
            new Vector4(0f, 0f, -0.5f, 0f),
            new Vector4(0.5f, 0.5f, 0.5f, 1f)
        );

        public int MainLightIndex;
        public Matrix4x4 MainLightShadowView;
        public Matrix4x4 MainLightShadowProj;
        public ShadowSplitData MainLightShadowSplitData;

        public Matrix4x4 GetWorldToShadowMatrix()
        {
            return BiasMat * MainLightShadowProj * MainLightShadowView;
        }
        
        public override void Reset() { }
    }
}
