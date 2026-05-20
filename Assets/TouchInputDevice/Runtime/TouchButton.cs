using System;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace TouchInput
{
    [RequireComponent(typeof(Button))]
    public class TouchButton : MonoBehaviour
    {
        public InputDevice InputDevice;
        public InputAction Action;
        public event Action<TouchButton> OnClick;
        private Button _button;

        private void OnEnable()
        {
            foreach (var actionBinding in Action.bindings)
            {
                InputControlPath.TryFindControl(InputDevice, actionBinding.path);
            }

            _button = GetComponent<Button>();
            _button.onClick.AddListener(ClickHandler);
        }

        private void OnDisable() => _button.onClick.RemoveListener(ClickHandler);
        private void ClickHandler() => OnClick?.Invoke(this);
    }
}
