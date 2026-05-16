using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace Rendering.KageRP
{
    [Serializable]
    public abstract class AbstractRenderGraphPass
    {
        [HideInInspector] public bool IsActive = true;

        public Exception LastExecutionException { get; set; }

        public virtual void Setup(in KageRenderPipelineAsset asset, in KageRenderPipeline pipeline) { }

        public virtual void BeforeCameraCulling(ref ScriptableCullingParameters cullingParameters) { }

        public virtual void AfterCameraCulling(
            ScriptableRenderContext context,
            CullingResultData cullingResultData,
            ContextContainer frameData
        ) { }

        public abstract void Record(RenderGraph renderGraph, ContextContainer frameData);

        public virtual void CleanUp() { }
    }
}
