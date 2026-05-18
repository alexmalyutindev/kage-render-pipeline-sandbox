using UnityEngine;
using UnityEngine.Rendering;

namespace Rendering.KageRP.ShaderLibrary
{
    /// <summary>
    /// Contains structs used for shader input.
    /// </summary>
    public static partial class ShaderTypes
    {
        /// <summary>
        /// Container struct for various data used for lights in URP.
        /// </summary>
        [GenerateHLSL(PackingRules.Exact, false)]
        public struct LightData
        {
            /// <summary>
            /// The position of the light.
            /// </summary>
            public Vector4 position;

            /// <summary>
            /// The color of the light.
            /// </summary>
            public Vector4 color;

            /// <summary>
            /// The attenuation of the light.
            /// </summary>
            public Vector4 attenuation;

            /// <summary>
            /// The direction of the light (Spot light).
            /// </summary>
            public Vector4 spotDirection;
        }
    }
}
