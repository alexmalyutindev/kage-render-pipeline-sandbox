using System.Collections.Generic;
using UnityEditor;
using UnityEditor.AssetImporters;
using UnityEngine;

namespace Rendering.KageRP.Editor
{
    public class ModelImporter : AssetPostprocessor
    {
        private void OnPreprocessMaterialDescription(
            MaterialDescription description,
            Material material,
            AnimationClip[] animations
        )
        {
            var names = new List<string>();
            description.GetTexturePropertyNames(names);
            Debug.Log("Texture:\n- " + string.Join("\n- ", names));

            description.GetVector4PropertyNames(names);
            Debug.Log("Vector4:\n- " + string.Join("\n- ", names));

            material.shader = Shader.Find("KageRP/Opaque");

            // Vector4:
            // - Bump
            // - ReflectionColor
            // - AmbientColor
            // - TransparentColor
            // - DisplacementColor
            // - Emissive
            // - Diffuse
            // - VectorDisplacementColor
            // - SpecularColor
            // - Specular
            // - DiffuseColor
            // - Ambient
            // - EmissiveColor
            // - NormalMap

            if (description.TryGetProperty("DiffuseColor", out Vector4 color))
            {
                material.SetColor("_BaseColor", color);
            }

            if (description.TryGetProperty("NormalMap", out TexturePropertyDescription desc))
            {
                material.SetTexture("_NormalMap", desc.texture);
            }
        }
    }
}
