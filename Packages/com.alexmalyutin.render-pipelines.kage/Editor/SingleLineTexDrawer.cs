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

        public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
        {
            editor.TexturePropertySingleLine(label, prop);

            if (!_isKeywordEmpty)
            {
                ApplyKeyword(prop, _keyword);
            }
        }

        private static void ApplyKeyword(MaterialProperty prop, string keyword)
        {
            foreach (var target in prop.targets)
            {
                if (target is not Material material) continue;

                if (prop.textureValue != null)
                {
                    material.EnableKeyword(keyword);
                }
                else
                {
                    material.DisableKeyword(keyword);
                }
            }
        }

        public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        {
            return -2;
        }
    }
}
