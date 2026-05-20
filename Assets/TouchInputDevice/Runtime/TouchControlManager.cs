using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace TouchInput
{
    public class TouchControlManager : MonoBehaviour
    {
        public InputDevice InputDevice;
        private readonly List<TouchButton> _touchButtons = new();
        private readonly List<TouchDragZone> _touchDragZones = new();

        private void Start()
        {
            GetComponentsInChildren(_touchButtons);
            GetComponentsInChildren(_touchDragZones);

            foreach (var touchButton in _touchButtons)
            {
                touchButton.OnClick += static button =>
                {
                    // InputControlPath.TryFindControl(InputDevice, button.Action.bindings[].path);
                    Debug.Log($"[InputSystem] Clicked: {button}");
                };
            }
            
            foreach (var touchDragZone in _touchDragZones)
            {
                touchDragZone.OnDrag += static (dragZone, delta) =>
                {
                    Debug.Log($"[InputSystem] Drag: {dragZone} - {delta}");
                };
            }
        }
    }
}
