using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace TouchInput
{
    public class TouchControlManager : MonoBehaviour
    {
        private TouchDevice _inputDevice;
        private readonly List<TouchButton> _touchButtons = new();
        private readonly List<TouchDragZone> _touchDragZones = new();

        private void Start()
        {
            _inputDevice = InputSystem.AddDevice<TouchDevice>();

            GetComponentsInChildren(_touchButtons);
            GetComponentsInChildren(_touchDragZones);

            if (Application.platform is RuntimePlatform.Android or RuntimePlatform.IPhonePlayer)
            {
                foreach (var touchButton in _touchButtons) touchButton.Init(_inputDevice);
                foreach (var touchDragZone in _touchDragZones) touchDragZone.Init(_inputDevice);
            }
            else
            {
                foreach (var touchButton in _touchButtons) touchButton.gameObject.SetActive(false);
                foreach (var touchDragZone in _touchDragZones) touchDragZone.gameObject.SetActive(false);
            }
        }
    }
}
