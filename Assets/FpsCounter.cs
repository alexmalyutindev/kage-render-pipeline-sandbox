using UnityEngine;
using UnityEngine.UI;

public class FpsCounter : MonoBehaviour
{
    [SerializeField] private Text _text;
    
    private int _cursor = 0;
    private int _samplesCount = 0;
    private readonly float[] _frameTimes = new float[1024];

    void Update()
    {
        _frameTimes[_cursor] = Time.unscaledDeltaTime;
        _cursor = (_cursor + 1) % _frameTimes.Length;
        if (_samplesCount < _frameTimes.Length) _samplesCount++;

        if (Time.frameCount % 120 == 0)
        {
            float totalTime = 0.0f;
            for (var i = 0; i < _samplesCount; i++)
            {
                var frameTime = _frameTimes[i];
                totalTime += frameTime;
            }
            totalTime /= _samplesCount;

            _text.text = $"{1.0f / totalTime:F1}";
        }
    }
}
