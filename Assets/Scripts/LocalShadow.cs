using System;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class LocalShadow : MonoBehaviour
{
    private static readonly Vector3[] TempCorners = new Vector3[8];
    public List<Renderer> Renderers;
    public MaterialPropertyBlock Props;

    private Matrix4x4 _view;
    private Matrix4x4 _proj;

    private void OnEnable()
    {
        Props = new MaterialPropertyBlock();
        GetComponentsInChildren(false, Renderers);
        LocalShadowPass.Register(this);
    }

    private void OnDisable()
    {
        LocalShadowPass.Unregister(this);
        foreach (var rend in Renderers) rend.SetPropertyBlock(null);
    }

    private void OnDrawGizmosSelected()
    {
        Gizmos.matrix = _view.inverse;
        Gizmos.DrawWireCube(_proj.GetPosition(), _proj.lossyScale * 2.0f);
    }

    public void GetViewProjectionForLightShadow(Light light, out Matrix4x4 view, out Matrix4x4 proj)
    {
        var bounds = Renderers[0].bounds;
        for (int i = 1; i < Renderers.Count; i++) bounds.Encapsulate(Renderers[i].bounds);
        GetViewProjectionMatrices(light, bounds, out _view, out _proj);
        view = _view;
        proj = _proj;
    }

    private static void GetViewProjectionMatrices(
        Light light,
        Bounds bounds,
        out Matrix4x4 view,
        out Matrix4x4 projMatrix
    )
    {
        Vector3 lightDirection = light.transform.forward;
        Vector3 shadowCameraPosition = bounds.center;

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

        float nearClip = lightSpaceBounds.min.z;
        float farClip = lightSpaceBounds.max.z;

        projMatrix = Matrix4x4.Ortho(minX, maxX, minY, maxY, nearClip, farClip);
    }

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
}
