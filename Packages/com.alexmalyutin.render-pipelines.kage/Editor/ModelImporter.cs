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
            // var textureNames = new List<string>();
            // description.GetTexturePropertyNames(textureNames);
            // Debug.Log(string.Join(", ", textureNames));

            // TODO: Make proper description read!
            material.shader = Shader.Find("KageRP/Lit");
            if (description.TryGetProperty("NormalMap", out TexturePropertyDescription texturePropertyDescription))
            {
                material.SetTexture("_NormalMap", texturePropertyDescription.texture);
            }
        }
    }
}
