using UnityEngine;
using UnityEngine.Rendering;

namespace Rendering.KageRP
{
    public static class KageUtils
    {
        /// <summary>
        /// Return true if handle does not match descriptor
        /// </summary>
        /// <param name="handle">RTHandle to check (can be null)</param>
        /// <param name="descriptor">Descriptor for the RTHandle to match</param>
        /// <param name="scaled">Check if the RTHandle has auto scaling enabled if not, check the widths and heights</param>
        /// <returns></returns>
        public static bool RTHandleNeedsReAlloc(RTHandle handle, in RenderTextureDescriptor descriptor)
        {
            if (handle == null || handle.rt == null)
                return true;
            return
                handle.rt.width != descriptor.width ||
                handle.rt.height != descriptor.height;
        }

        public static bool ReAllocIfNeeded(ref RTHandle frameColor, RenderTextureDescriptor descriptor, string name)
        {
            if (KageUtils.RTHandleNeedsReAlloc(frameColor, descriptor))
            {
                if (frameColor != null) RTHandles.Release(frameColor);
                frameColor = RTHandles.Alloc(descriptor, name: name);
                return true;
            }

            return false;
        }
    }
}
