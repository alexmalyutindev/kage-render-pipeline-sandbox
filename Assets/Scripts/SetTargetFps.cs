using UnityEngine;

namespace DefaultNamespace
{
    public class SetTargetFps : MonoBehaviour
    {
        [SerializeField] private int _targetFps = 120;
        private void Start()
        {
            Application.targetFrameRate = _targetFps;
        }
    }
}
