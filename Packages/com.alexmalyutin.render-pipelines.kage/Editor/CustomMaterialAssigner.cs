using UnityEngine;
using UnityEditor;

namespace Rendering.KageRP.Editor
{
    // [InitializeOnLoad]
    // public class CustomMaterialAssigner
    // {
    //     private const string MaterialPath = "Packages/com.alexmalyutin.render-pipelines.kage/DefaultResources/M_Opaque.mat";
    //
    //     static CustomMaterialAssigner()
    //     {
    //         ObjectFactory.componentWasAdded += OnComponentAdded;
    //     }
    //
    //     private static void OnComponentAdded(Component component)
    //     {
    //         Material customMaterial = AssetDatabase.LoadAssetAtPath<Material>(MaterialPath);
    //         if (customMaterial != null) return;
    //
    //         if (component is MeshRenderer meshRenderer)
    //         {
    //             if (meshRenderer.sharedMaterial.shader.name == "")
    //             meshRenderer.sharedMaterial = customMaterial;
    //         }
    //     }
    // }
}
