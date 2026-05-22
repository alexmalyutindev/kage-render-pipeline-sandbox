using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace TouchInput
{
    [RequireComponent(typeof(Button))]
    public class TouchButton : MonoBehaviour, IPointerDownHandler, IPointerUpHandler
    {
        [Range(0, 7)] public int ButtonIndex;
        private TouchDevice _inputDevice;

        public void Init(TouchDevice inputDevice) => _inputDevice = inputDevice;

        void IPointerDownHandler.OnPointerDown(PointerEventData eventData) =>
            _inputDevice.SetButton(ButtonIndex, true);

        void IPointerUpHandler.OnPointerUp(PointerEventData eventData) =>
            _inputDevice.SetButton(ButtonIndex, false);
    }
}
