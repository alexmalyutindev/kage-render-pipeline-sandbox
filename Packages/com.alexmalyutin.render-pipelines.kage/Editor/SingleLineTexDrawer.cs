using JetBrains.Annotations;
using UnityEditor;
using UnityEngine;

namespace Rendering.KageRP.Editor
{
    [UsedImplicitly]
    internal class SingleLineTexDrawer : MaterialPropertyDrawer
    {
        public SingleLineTexDrawer() { }

        public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
        {
            editor.TexturePropertySingleLine(label, prop);
        }

        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        {
            return -2;
        }
    }

}
