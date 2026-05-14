using System;
using UnityEditor;
using UnityEditorInternal;
using UnityEngine;

namespace Rendering.KageRP.Editor
{
    [CustomEditor(typeof(KageRenderPipelineAsset))]
    public class KageRenderPipelineAssetEditor : UnityEditor.Editor
    {
        private const float Padding = 2;
        private const float HalfPadding = Padding * 0.5f;
        private static readonly float ElementHeight = EditorGUIUtility.singleLineHeight + 4;
        private static readonly float InnerElementHeight = EditorGUIUtility.singleLineHeight;

        private ReorderableList _passesList;

        private void OnEnable()
        {
            var passesProperty = serializedObject.FindProperty("Passes");

            _passesList = new ReorderableList(
                serializedObject,
                passesProperty,
                draggable: true,
                displayHeader: true,
                displayAddButton: true,
                displayRemoveButton: true
            )
            {
                drawHeaderCallback = DrawHeader,
                drawElementCallback = DrawElement,
                elementHeightCallback = GetElementHeight,
                onAddDropdownCallback = OnAddDropdown
            };
        }

        public override void OnInspectorGUI()
        {
            serializedObject.Update();
            DrawPropertiesExcluding(serializedObject, "Passes");
            GUILayout.Space(10);
            _passesList.DoLayoutList();
            serializedObject.ApplyModifiedProperties();
        }

        private void DrawHeader(Rect rect)
        {
            EditorGUI.LabelField(rect, "Render Graph Passes");
        }

        private float GetElementHeight(int index)
        {
            SerializedProperty element = _passesList.serializedProperty.GetArrayElementAtIndex(index);
            if (element == null) return ElementHeight;
            return EditorGUI.GetPropertyHeight(element, true) + Padding * 2;
        }

        private void DrawElement(Rect rect, int index, bool isActive, bool isFocused)
        {
            SerializedProperty element = _passesList.serializedProperty.GetArrayElementAtIndex(index);

            if (element.managedReferenceValue is not AbstractRenderGraphPass pass)
            {
                EditorGUI.LabelField(rect, "<Missing Pass>");
                return;
            }

            if (Event.current.type == EventType.Repaint)
            {
                var boxRect = rect;
                boxRect.y += HalfPadding;
                boxRect.height -= Padding;
                EditorStyles.helpBox.Draw(boxRect, false, false, false, false);
            }

            Type type = pass.GetType();

            var propRect = rect;
            propRect.x += 18;
            propRect.width -= 22;
            propRect.y += Padding;
            propRect.height -= Padding;
            EditorGUI.PropertyField(propRect, element, new GUIContent(type.Name), true);

            if (pass.LastExecutionException != null)
            {
                var iconSize = InnerElementHeight + 2;
                Rect iconRect = new Rect(
                    rect.xMax - iconSize - 3, 
                    rect.y + Padding,
                    iconSize,
                    iconSize
                );
                GUIContent warningIcon = EditorGUIUtility.IconContent("console.erroricon");
                warningIcon.tooltip = pass.LastExecutionException.Message;
                GUI.Label(iconRect, warningIcon);
            }
        }

        private void OnAddDropdown(Rect buttonRect, ReorderableList list)
        {
            SerializeReferenceDropdown.Show(buttonRect, type =>
            {
                int index = list.serializedProperty.arraySize;
                list.serializedProperty.InsertArrayElementAtIndex(index);

                SerializedProperty element = list.serializedProperty.GetArrayElementAtIndex(index);
                element.managedReferenceValue = Activator.CreateInstance(type);
                serializedObject.ApplyModifiedProperties();
            });
        }
    }
}
