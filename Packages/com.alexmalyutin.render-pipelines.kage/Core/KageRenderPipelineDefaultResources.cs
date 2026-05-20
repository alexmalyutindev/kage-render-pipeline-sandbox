using UnityEngine;

namespace Rendering.KageRP
{
    [CreateAssetMenu]
    public class KageRenderPipelineDefaultResources : ScriptableObject
    {
        public Shader BlitShader;
        public Shader BlitColorAndDepth;

        [Header("Textures")]
        public Texture BRDF_LUT;

        [Header("Deferred Lighting")]
        public Mesh PointLightMesh;
        public Material PointLightMaterial;

        [Space]
        public Material SSAOMaterial;
    }
}
