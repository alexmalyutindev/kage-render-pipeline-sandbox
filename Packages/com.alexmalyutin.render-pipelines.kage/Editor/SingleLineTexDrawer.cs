using System;
using JetBrains.Annotations;
using UnityEditor;
using UnityEngine;

namespace Rendering.KageRP.Editor
{
    [UsedImplicitly]
    internal class SingleLineTexDrawer : MaterialPropertyDrawer
    {
        private readonly string _keyword;
        private readonly bool _isKeywordEmpty;

        public SingleLineTexDrawer() { }

        public SingleLineTexDrawer(string keyword)
        {
            _keyword = keyword;
            _isKeywordEmpty = string.IsNullOrEmpty(_keyword);
        }

        public override void Apply(MaterialProperty prop)
        {
            
        }

        public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
        {
            if (!_isKeywordEmpty)
            {
                EditorGUI.BeginChangeCheck();
            }

            editor.TexturePropertySingleLine(label, prop);

            if (!_isKeywordEmpty && EditorGUI.EndChangeCheck())
            {
                foreach (Material mat in prop.targets)
                {
                    if (prop.textureValue != null)
                        mat.EnableKeyword(_keyword);
                    else
                        mat.DisableKeyword(_keyword);
                }
            }
        }

        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        {
            return -2;
        }
    }
}
