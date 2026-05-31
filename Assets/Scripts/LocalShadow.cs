using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

[ExecuteAlways]
public class LocalShadow : MonoBehaviour
{
    public Light Light;
    public List<Renderer> Renderers;

    private RenderTexture _shadowMap;
    private MaterialPropertyBlock _props;
    private readonly List<Material> _materialsTemp = new();

    private void OnEnable()
    {
        _props = new MaterialPropertyBlock();

        _shadowMap = new RenderTexture(1024, 1024, GraphicsFormat.None, GraphicsFormat.D24_UNorm)
        {
            name = $"_LocalShadow_{name}",
            filterMode = FilterMode.Bilinear,
        };

        GetComponentsInChildren(false, Renderers);
    }

    private void OnDisable()
    {
        if (_shadowMap != null)
        {
            _shadowMap.Release();
            CoreUtils.Destroy(_shadowMap);
        }
    }

    public void LateUpdate()
    {
        if (Light == null || Renderers.Count == 0) return;

        Bounds bounds = Renderers[0].bounds;
        for (int i = 1; i < Renderers.Count; i++)
        {
            if (Renderers[i] != null) bounds.Encapsulate(Renderers[i].bounds);
        }

        GetViewProjectionMatrices(Light, bounds, out var view, out var proj);

        var cmd = CommandBufferPool.Get("LocalShadow");
        cmd.SetRenderTarget(_shadowMap);
        cmd.ClearRenderTarget(true, false, Color.clear);
        cmd.SetViewProjectionMatrices(view, proj);

        foreach (var rend in Renderers)
        {
            rend.GetSharedMaterials(_materialsTemp);
            for (var submeshIndex = 0; submeshIndex < _materialsTemp.Count; submeshIndex++)
            {
                var shadowPass = 1;
                var material = _materialsTemp[submeshIndex];
                if (material.passCount > shadowPass)
                {
                    cmd.DrawRenderer(rend, material, submeshIndex, shadowPass);
                }
            }
        }

        Graphics.ExecuteCommandBuffer(cmd);
        cmd.Clear();

        CommandBufferPool.Release(cmd);

        _props.SetFloat("_EnableLocalShadow", 1.0f);
        _props.SetTexture("_LocalShadow", _shadowMap);
        _props.SetMatrix("_WorldToLocalShadow", CalculateWorldToShadowMatrix(view, proj));
        _props.SetVector("_MainLightPosition", -Light.transform.forward);
        _props.SetVector("_ShadowBias", new Vector4(0.02f, 0.0f));
        foreach (var rend in Renderers)
        {
            rend.SetPropertyBlock(_props);
        }
    }

    private static void GetViewProjectionMatrices(
        Light light,
        Bounds bounds,
        out Matrix4x4 view,
        out Matrix4x4 projMatrix
    )
    {
        Vector3 lightDirection = light.transform.forward;
        Vector3 shadowCameraPosition = bounds.center - lightDirection * (bounds.extents.magnitude + 1.0f);

        view = Matrix4x4.LookAt(shadowCameraPosition, shadowCameraPosition + lightDirection, Vector3.up);
        view = view.inverse;
        view.SetRow(2, -view.GetRow(2));

        var lightSpaceBounds = TransformBounds(bounds, view);

        float minX = lightSpaceBounds.min.x;
        float maxX = lightSpaceBounds.max.x;
        float minY = lightSpaceBounds.min.y;
        float maxY = lightSpaceBounds.max.y;

        float width = maxX - minX;
        float height = maxY - minY;

        if (width > height)
        {
            float diff = width - height;
            minY -= diff * 0.5f;
            maxY += diff * 0.5f;
        }
        else
        {
            float diff = height - width;
            minX -= diff * 0.5f;
            maxX += diff * 0.5f;
        }

        float nearClip = -lightSpaceBounds.max.z - 1.0f;
        float farClip = -lightSpaceBounds.min.z + 1.0f;

        projMatrix = Matrix4x4.Ortho(minX, maxX, minY, maxY, nearClip, farClip);
    }

    private static readonly Vector3[] TempCorners = new Vector3[8];

    private static Bounds TransformBounds(in Bounds bounds, in Matrix4x4 transform)
    {
        Vector3 ext = bounds.extents;
        TempCorners[0] = bounds.center + new Vector3(-ext.x, -ext.y, -ext.z);
        TempCorners[1] = bounds.center + new Vector3(-ext.x, -ext.y, ext.z);
        TempCorners[2] = bounds.center + new Vector3(-ext.x, ext.y, -ext.z);
        TempCorners[3] = bounds.center + new Vector3(-ext.x, ext.y, ext.z);
        TempCorners[4] = bounds.center + new Vector3(ext.x, -ext.y, -ext.z);
        TempCorners[5] = bounds.center + new Vector3(ext.x, -ext.y, ext.z);
        TempCorners[6] = bounds.center + new Vector3(ext.x, ext.y, -ext.z);
        TempCorners[7] = bounds.center + new Vector3(ext.x, ext.y, ext.z);

        Bounds transformedBounds = new Bounds(transform.MultiplyPoint3x4(bounds.center), Vector3.zero);
        foreach (var corner in TempCorners) transformedBounds.Encapsulate(transform.MultiplyPoint3x4(corner));

        return transformedBounds;
    }

    private static Matrix4x4 CalculateWorldToShadowMatrix(Matrix4x4 view, Matrix4x4 proj)
    {
        Matrix4x4 viewProj = proj * view;

        Matrix4x4 scaleBias = Matrix4x4.identity;
        scaleBias.m00 = 0.5f; scaleBias.m03 = 0.5f;
        scaleBias.m11 = 0.5f; scaleBias.m13 = 0.5f;
        scaleBias.m22 = 0.5f; scaleBias.m23 = 0.5f;

        if (SystemInfo.usesReversedZBuffer)
        {
            scaleBias.m22 = -0.5f;
            scaleBias.m23 = 0.5f;
        }

        return scaleBias * viewProj;
    }
}
