using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;
using UnityEngine.InputSystem.Layouts;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.InputSystem.Utilities;

namespace TouchInput
{
    /// <summary>
    /// Low-level state struct written into the Input System's state buffers.
    /// Layout must match the controls registered in TouchDevice.
    /// Supports up to 8 buttons, 4 sticks, and 4 drag zones.
    /// </summary>
    public struct TouchDeviceState : IInputStateTypeInfo
    {
        public static readonly FourCC Format = new FourCC('T', 'C', 'H', 'D');
        public FourCC format => Format;

        // 8 buttons packed as bits in a short (bit 0 = button0, bit 1 = button1, …)
        [InputControl(name = "button0", layout = "Button", bit = 0)]
        [InputControl(name = "button1", layout = "Button", bit = 1)]
        [InputControl(name = "button2", layout = "Button", bit = 2)]
        [InputControl(name = "button3", layout = "Button", bit = 3)]
        [InputControl(name = "button4", layout = "Button", bit = 4)]
        [InputControl(name = "button5", layout = "Button", bit = 5)]
        [InputControl(name = "button6", layout = "Button", bit = 6)]
        [InputControl(name = "button7", layout = "Button", bit = 7)]
        public short buttons;

        // 4 sticks – each is a Vector2 (x, y floats)
        [InputControl(name = "stick0", layout = "Stick", format = "VEC2")]
        public Vector2 stick0;
        [InputControl(name = "stick1", layout = "Stick", format = "VEC2")]
        public Vector2 stick1;
        [InputControl(name = "stick2", layout = "Stick", format = "VEC2")]
        public Vector2 stick2;
        [InputControl(name = "stick3", layout = "Stick", format = "VEC2")]
        public Vector2 stick3;
        
        // 4 drag zones – delta Vector2 per zone
        [InputControl(name = "drag0", layout = "Vector2", format = "VEC2")]
        public Vector2 drag0;
        [InputControl(name = "drag1", layout = "Vector2", format = "VEC2")]
        public Vector2 drag1;
        [InputControl(name = "drag2", layout = "Vector2", format = "VEC2")]
        public Vector2 drag2;
        [InputControl(name = "drag3", layout = "Vector2", format = "VEC2")]
        public Vector2 drag3;
    }

    /// <summary>
    /// Custom InputDevice that exposes virtual buttons, sticks, and drag zones.
    /// Register via TouchControlManager; individual UI components write state updates.
    /// </summary>
#if UNITY_EDITOR
    [UnityEditor.InitializeOnLoad]
#endif
    [InputControlLayout(stateType = typeof(TouchDeviceState), displayName = "Touch Control Device")]
    public class TouchDevice : InputDevice, IInputUpdateCallbackReceiver
    {
        public ButtonControl[] Buttons { get; private set; }
        public StickControl[] Sticks { get; private set; }
        public Vector2Control[] DragZones { get; private set; }

        public static TouchDevice current { get; private set; }

        private TouchDeviceState _pendingState;
        private bool _stateDirty;
        private short _dragZoneActiveMask;
        private short _prevDragZoneActiveMask;
        private readonly object _lock = new object();

        static TouchDevice()
        {
            InputSystem.RegisterLayout<TouchDevice>();
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void Initialize()
        {
            InputSystem.RegisterLayout<TouchDevice>();
        }

        protected override void FinishSetup()
        {
            base.FinishSetup();

            Buttons = new ButtonControl[8];
            for (int i = 0; i < 8; i++)
                Buttons[i] = GetChildControl<ButtonControl>($"button{i}");

            Sticks = new StickControl[4];
            for (int i = 0; i < 4; i++)
                Sticks[i] = GetChildControl<StickControl>($"stick{i}");

            DragZones = new Vector2Control[4];
            for (int i = 0; i < 4; i++)
                DragZones[i] = GetChildControl<Vector2Control>($"drag{i}");
        }

        public override void MakeCurrent()
        {
            base.MakeCurrent();
            current = this;
        }

        protected override void OnRemoved()
        {
            base.OnRemoved();
            if (current == this) current = null;
        }

        public void SetButton(int index, bool pressed)
        {
            if (index < 0 || index >= 8) return;
            lock (_lock)
            {
                if (pressed) _pendingState.buttons |= (short)(1 << index);
                else _pendingState.buttons &= (short)~(1 << index);
                _stateDirty = true;
            }
        }

        public void SetStick(int index, Vector2 value)
        {
            if (index < 0 || index >= 4) return;
            lock (_lock)
            {
                switch (index)
                {
                    case 0: _pendingState.stick0 = value; break;
                    case 1: _pendingState.stick1 = value; break;
                    case 2: _pendingState.stick2 = value; break;
                    case 3: _pendingState.stick3 = value; break;
                }

                _stateDirty = true;
            }
        }

        public void SetDrag(int index, Vector2 delta)
        {
            if (index < 0 || index >= 4) return;
            lock (_lock)
            {
                switch (index)
                {
                    case 0: _pendingState.drag0 = delta; break;
                    case 1: _pendingState.drag1 = delta; break;
                    case 2: _pendingState.drag2 = delta; break;
                    case 3: _pendingState.drag3 = delta; break;
                }

                _dragZoneActiveMask |= (short)(1 << index);
                _stateDirty = true;
            }
        }

        public void OnUpdate()
        {
            lock (_lock)
            {
                _stateDirty |= IsDragZonesNeedReset();
                if (!_stateDirty) return;
                InputSystem.QueueStateEvent(this, _pendingState);
                _stateDirty = false;
            }
        }

        private bool IsDragZonesNeedReset()
        {
            // Any zone active last frame but not this frame needs a zero flush
            short needsReset = (short)(_prevDragZoneActiveMask & ~_dragZoneActiveMask);
            if (needsReset != 0)
            {
                for (int index = 0; index < 4; index++)
                {
                    if ((needsReset & (1 << index)) == 0) continue;
                    switch (index)
                    {
                        case 0: _pendingState.drag0 = Vector2.zero; break;
                        case 1: _pendingState.drag1 = Vector2.zero; break;
                        case 2: _pendingState.drag2 = Vector2.zero; break;
                        case 3: _pendingState.drag3 = Vector2.zero; break;
                    }
                }
            }

            _prevDragZoneActiveMask = _dragZoneActiveMask;
            _dragZoneActiveMask = 0;
            return needsReset != 0;
        }
    }
}
