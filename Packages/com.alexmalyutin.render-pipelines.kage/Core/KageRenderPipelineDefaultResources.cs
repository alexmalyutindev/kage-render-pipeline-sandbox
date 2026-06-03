using System;
using UnityEngine;
using UnityEngine.Serialization;

namespace Rendering.KageRP
{
    [CreateAssetMenu]
    public class KageRenderPipelineDefaultResources : ScriptableObject
    {
        public Shader BlitShader;
        public Shader BlitColorAndDepth;

        public DefaultMaterials DefaultMaterials;

        [Header("Textures")]
        public Texture BRDF_LUT;
        public Texture BayerMatrix;

        [FormerlySerializedAs("PointLightMesh")] [Header("Deferred Lighting")]
        public Mesh PointLightVolume;
        public Mesh SpotLightVolume;
        public Material DeferredLightMaterial;

        [Space]
        public Material SSAOMaterial;
        public Material BloomMaterial;
    }

    [Serializable]
    public class DefaultMaterials
    {
        public Material Opaque;
        public Material Terrain;
    }
}
