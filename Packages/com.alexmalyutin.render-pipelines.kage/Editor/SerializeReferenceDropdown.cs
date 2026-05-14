using System;
using UnityEditor;
using UnityEngine;

namespace Rendering.KageRP.Editor
{
    public static class SerializeReferenceDropdown
    {
        public static void Show(Rect rect, Action<Type> onSelected)
        {
            GenericMenu menu = new GenericMenu();
            foreach (var type in TypeCacheUtility.GetTypes<AbstractRenderGraphPass>())
            {
                menu.AddItem(new GUIContent(type.Name), false, () => onSelected(type));
            }
            menu.DropDown(rect);
        }
    }
}
