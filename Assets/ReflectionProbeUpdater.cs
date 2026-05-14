// On any GameObject in scene

using UnityEngine;

public class ReflectionProbeUpdater : MonoBehaviour
{
    private ReflectionProbe _probe;

    void Start()
    {
        _probe = GetComponent<ReflectionProbe>();
        _probe.mode = UnityEngine.Rendering.ReflectionProbeMode.Realtime;
        _probe.refreshMode = UnityEngine.Rendering.ReflectionProbeRefreshMode.EveryFrame;
        _probe.timeSlicingMode = UnityEngine.Rendering.ReflectionProbeTimeSlicingMode.NoTimeSlicing;
    }

    void Update()
    {
        _probe.RenderProbe();
    }
}
