using UnityEngine;

namespace Rendering.KageRP
{
    [CreateAssetMenu]
    public class KageRenderPipelineDefaultResources : ScriptableObject
    {
        public Shader BlitShader;
        public Shader BlitColorAndDepth;

        public Mesh PointLightMesh;
        public Material PointLightMaterial;

        public Material SSAOMaterial;
    }
}
