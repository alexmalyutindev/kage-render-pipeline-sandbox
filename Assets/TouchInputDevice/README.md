# Touch Input Device — Unity Input System

A custom `InputDevice` for Unity's **Input System** that exposes virtual buttons, sticks, and drag zones driven entirely by `UnityEngine.UI` Canvas events. Controls are added at runtime by attaching components to GameObjects.

---

## Requirements

| Package | Version |
|---|---|
| `com.unity.inputsystem` | ≥ 1.7.0 |
| `com.unity.ugui` | ≥ 1.0.0 |
| Unity | ≥ 2021.3 |

Make sure **Active Input Handling** is set to **Input System Package (New)** or **Both** in *Project Settings → Player*.

---

## File Layout

```
TouchInputDevice/
├── Runtime/
│   ├── TouchDevice.cs           # Custom InputDevice + state struct
│   ├── TouchControlManager.cs   # Singleton — owns device lifetime & index pools
│   ├── TouchControlSpawner.cs   # Runtime factory (no prefabs needed)
│   ├── TouchButton.cs           # UI Button → device button[N]
│   ├── TouchStick.cs            # UI Joystick → device stick[N]
│   └── TouchDragZone.cs         # UI Drag area → device drag[N]
├── Example/
│   └── TouchInputExample.cs     # Wiring demo
└── package.json
```

---

## Quick Start

### A — Scripted (no prefabs)

```csharp
void Start()
{
    var spawner = TouchControlSpawner.Instance;

    // Left stick
    TouchStick move = spawner.CreateStick("Move", new Vector2(180, 150));

    // Right-side drag zone for camera
    TouchDragZone look = spawner.CreateDragZone("Look",
        anchorMin: new Vector2(0.5f, 0f),
        anchorMax: Vector2.one,
        sensitivity: 0.5f);

    // Jump button bottom-right
    TouchButton jump = spawner.CreateButton("Jump",
        anchoredPos: new Vector2(-130, 120),
        size: new Vector2(110, 110));
}

void Update()
{
    var dev = TouchDevice.current;
    Vector2 movement = dev.Sticks[move.DeviceIndex].ReadValue();
    bool    jumped   = dev.Buttons[jump.DeviceIndex].isPressed;
}
```

### B — Scene prefabs / manual setup

1. Create a **Canvas** (Screen Space – Overlay).
2. Add a **GraphicRaycaster** to it.
3. Create child UI Images and attach:
   - `TouchButton` — for any press control
   - `TouchStick` — on the base image; drag the knob child into **Knob Transform**
   - `TouchDragZone` — on a full-region transparent image
4. Hit Play; `TouchControlManager` auto-creates the device.

### C — Input Actions Asset

1. Open **Window → Input Actions**.
2. Add a new binding and set the **Path** to:
   - Button: `<TouchControlDevice>/button0`
   - Stick: `<TouchControlDevice>/stick0`
   - Drag: `<TouchControlDevice>/drag0`
3. Use `InputActionReference` fields in your MonoBehaviour.

---

## Limits

| Control type | Max count |
|---|---|
| Buttons | 8 |
| Sticks | 4 |
| Drag zones | 4 |

Extend by widening the bitfield / adding more Vector2 fields in `TouchDeviceState`.

---

## Architecture

```
UI Event (IPointerDownHandler …)
        │
        ▼
  TouchButton / TouchStick / TouchDragZone
        │  calls SetButton / SetStick / SetDrag
        ▼
   TouchDevice   (holds pending state)
        │  QueueStateEvent every Input System update
        ▼
  InputSystem state buffer
        │
        ▼
  InputAction / device.Buttons[N].ReadValue()
```

Drag deltas are **reset to zero** after each `InputSystem.Update` tick so they behave like a per-frame delta rather than an accumulating position.
