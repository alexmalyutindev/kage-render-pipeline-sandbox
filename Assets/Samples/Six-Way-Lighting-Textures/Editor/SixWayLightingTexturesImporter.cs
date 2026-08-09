using System.IO;
using UnityEditor;
using UnityEngine;

public class SixWayLightingTexturesImporter : EditorWindow
{
    private Texture2D _textureA;
    private Texture2D _textureB;

    [MenuItem("Tools/Six-Way Lighting Importer")]
    public static void ShowWindow()
    {
        SixWayLightingTexturesImporter window = GetWindow<SixWayLightingTexturesImporter>("Six-Way Lighting Importer");
        window.minSize = new Vector2(350, 200);
        window.Show();
    }

    private void OnGUI()
    {
        GUILayout.Space(10);
        EditorGUILayout.LabelField("Six-Way Lighting Textures Importer", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Assign your primary lighting maps below to process them.", MessageType.Info);
        GUILayout.Space(10);

        _textureA = (Texture2D)EditorGUILayout.ObjectField("Lighting Texture A", _textureA, typeof(Texture2D), false);
        _textureB = (Texture2D)EditorGUILayout.ObjectField("Lighting Texture B", _textureB, typeof(Texture2D), false);

        GUILayout.Space(15);

        GUI.enabled = ReadyToProcess();
        if (GUILayout.Button("Process Textures", GUILayout.Height(30)))
        {
            ProcessTextures();
        }

        GUI.enabled = true;
    }

    private bool ReadyToProcess()
    {
        return _textureA != null && _textureB != null;
    }

    private void ProcessTextures()
    {
        string pathA = AssetDatabase.GetAssetPath(_textureA);
        string pathB = AssetDatabase.GetAssetPath(_textureB);

        EnsureTextureIsReadable(pathA);
        EnsureTextureIsReadable(pathB);

        Color[] mapA = _textureA.GetPixels();
        Color[] mapB = _textureB.GetPixels();
        Color[] result = new Color[mapA.Length];

        for (int i = 0; i < mapA.Length; i++)
        {
            // Channel mapping based on your 6-Way diagrams:
            // mapA: R=Right, G=Top, B=Back, A=Transparency
            // mapB: R=Left,  G=Bottom, B=Front, A=Extra
            float alpha = mapA[i].a * mapB[i].a;
            float rightLeft = 0.5f + 0.5f * (mapA[i].r - mapB[i].r);
            float topBottom = 0.5f + 0.5f * (mapA[i].g - mapB[i].g);
            float backFront = 0.5f + 0.5f * (mapA[i].b - mapB[i].b);

            result[i] = new Color(rightLeft, topBottom, backFront, alpha);
        }

        var packed = new Texture2D(_textureA.width, _textureA.height, TextureFormat.RGBA32, false);
        packed.SetPixels(result);
        packed.Apply();

        byte[] bytes = packed.EncodeToPNG();
        string outputPath = Path.Combine(Path.GetDirectoryName(pathA), "packed.exr");
        File.WriteAllBytes(outputPath, bytes);

        DestroyImmediate(packed);
        AssetDatabase.Refresh();
    }

    private void EnsureTextureIsReadable(string assetPath)
    {
        var importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        if (importer != null && !importer.isReadable)
        {
            importer.isReadable = true;
            importer.SaveAndReimport();
        }
    }
}