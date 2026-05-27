using UnityEngine;
using UnityEngine.Serialization;

namespace Rendering.KageRP
{
    [CreateAssetMenu]
    public class KageRenderPipelineDefaultResources : ScriptableObject
    {
        public Shader BlitShader;
        public Shader BlitColorAndDepth;

        [Header("Textures")]
        public Texture BRDF_LUT;
        public Texture BayerMatrix;

        [FormerlySerializedAs("PointLightMesh")] [Header("Deferred Lighting")]
        public Mesh PointLightVolume;
        public Mesh SpotLightVolume;
        public Material PointLightMaterial;

        [Space]
        public Material SSAOMaterial;
    }
}
