using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace TouchInput
{
    [RequireComponent(typeof(Image))]
    public class TouchDragZone : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
    {
        [Range(0, 7)] public int DragIndex;

        [Header("Settings")] [Tooltip("Scale applied to raw pixel delta before sending to device.")] [SerializeField]
        private float _sensitivity = 1f;

        [Tooltip("Invert horizontal axis.")] [SerializeField]
        private bool _invertX = false;

        [Tooltip("Invert vertical axis.")] [SerializeField]
        private bool _invertY = false;

        private TouchDevice _device;
        private int _activeTouchId = -1;
        private Vector2 _lastPosition;

        public void Init(TouchDevice device) => _device = device;

        void IPointerDownHandler.OnPointerDown(PointerEventData eventData)
        {
            if (_activeTouchId >= 0) return;
            _activeTouchId = eventData.pointerId;
            _lastPosition = eventData.position;
        }

        void IDragHandler.OnDrag(PointerEventData eventData)
        {
            if (eventData.pointerId != _activeTouchId) return;

            Vector2 delta = eventData.position - _lastPosition;
            _lastPosition = eventData.position;

            if (_invertX) delta.x = -delta.x;
            if (_invertY) delta.y = -delta.y;

            delta *= _sensitivity;
            _device.SetDrag(DragIndex, delta);
        }

        void IPointerUpHandler.OnPointerUp(PointerEventData eventData)
        {
            if (eventData.pointerId != _activeTouchId) return;
            _activeTouchId = -1;
            _device.SetDrag(DragIndex, Vector2.zero);
        }
    }
}
