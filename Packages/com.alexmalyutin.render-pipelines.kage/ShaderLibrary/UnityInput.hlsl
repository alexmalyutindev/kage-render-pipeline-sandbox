#ifndef KAGERP_UNITYINPUT
#define KAGERP_UNITYINPUT

// Time values from Unity
float4 _Time; // (t/20, t, t*2, t*3)
float4 _SinTime; // sin(t/8), sin(t/4), sin(t/2), sin(t)
float4 _CosTime; // cos(t/8), cos(t/4), cos(t/2), cos(t)
float4 unity_DeltaTime; // dt, 1/dt, smoothdt, 1/smoothdt
float4 _TimeParameters; // t, sin(t), cos(t)
float4 _LastTimeParameters; // t, sin(t), cos(t)

#if !defined(USING_STEREO_MATRICES)
float3 _WorldSpaceCameraPos;
#endif

// x = 1 or -1 (-1 if projection is flipped)
// y = near plane
// z = far plane
// w = 1/far plane
float4 _ProjectionParams;

// x = width
// y = height
// z = 1 + 1.0/width
// w = 1 + 1.0/height
float4 _ScreenParams;

// Values used to linearize the Z buffer (http://www.humus.name/temp/Linearize%20depth.txt)
// x = 1-far/near
// y = far/near
// z = x/far
// w = y/far
// or in case of a reversed depth buffer (UNITY_REVERSED_Z is 1)
// x = -1+far/near
// y = 1
// z = x/far
// w = 1/far
float4 _ZBufferParams;

// Projection matrices of the camera. Note that this might be different from projection matrix
// that is set right now, e.g. while rendering shadows the matrices below are still the projection
// of original camera.
float4x4 unity_CameraProjection;
float4x4 unity_CameraInvProjection;
float4x4 unity_WorldToCamera;
float4x4 unity_CameraToWorld;

// Block Layout should be respected due to SRP Batcher
// Block Layout should be respected due to SRP Batcher
CBUFFER_START(UnityPerDraw)
    // Space block Feature
    float4x4 unity_ObjectToWorld;
    float4x4 unity_WorldToObject;
    float4 unity_LODFade; // x is the fade value ranging within [0,1]. y is x quantized into 16 levels
    real4 unity_WorldTransformParams; // w is usually 1.0, or -1.0 for odd-negative scale transforms

    // Render Layer block feature
    // Only the first channel (x) contains valid data and the float must be reinterpreted using asuint() to extract the original 32 bits values.
    float4 unity_RenderingLayer;

    // Light Indices block feature
    // These are set internally by the engine upon request by RendererConfiguration.
    half4 unity_LightData;
    half4 unity_LightIndices[2];

    float4 unity_ProbesOcclusion;

    // Reflection Probe 0 block feature
    // HDR environment map decode instructions
    real4 unity_SpecCube0_HDR;
    real4 unity_SpecCube1_HDR;

    float4 unity_SpecCube0_BoxMax; // w contains the blend distance
    float4 unity_SpecCube0_BoxMin; // w contains the lerp value
    float4 unity_SpecCube0_ProbePosition; // w is set to 1 for box projection
    float4 unity_SpecCube1_BoxMax; // w contains the blend distance
    float4 unity_SpecCube1_BoxMin; // w contains the sign of (SpecCube0.importance - SpecCube1.importance)
    float4 unity_SpecCube1_ProbePosition; // w is set to 1 for box projection

    // Lightmap block feature
    float4 unity_LightmapST;
    float4 unity_DynamicLightmapST;

    // SH block feature
    real4 unity_SHAr;
    real4 unity_SHAg;
    real4 unity_SHAb;
    real4 unity_SHBr;
    real4 unity_SHBg;
    real4 unity_SHBb;
    real4 unity_SHC;

    // Renderer bounding box.
    float4 unity_RendererBounds_Min;
    float4 unity_RendererBounds_Max;

    // Velocity
    float4x4 unity_MatrixPreviousM;
    float4x4 unity_MatrixPreviousMI;
    //X : Use last frame positions (right now skinned meshes are the only objects that use this
    //Y : Force No Motion
    //Z : Z bias value
    //W : Camera only
    float4 unity_MotionVectorsParams;

    // Sprite.
    float4 unity_SpriteColor;
    //X : FlipX
    //Y : FlipY
    //Z : Reserved for future use.
    //W : Reserved for future use.
    float4 unity_SpriteProps;
CBUFFER_END

// ----------------------------------------------------------------------------

float4x4 unity_MatrixV;
float4x4 unity_MatrixInvV;
float4x4 unity_MatrixInvP;
float4x4 unity_MatrixVP;
float4x4 unity_MatrixInvVP;

// ----------------------------------------------------------------------------

// Unity specific
TEXTURECUBE(unity_SpecCube0);
SAMPLER(samplerunity_SpecCube0);
TEXTURECUBE(unity_SpecCube1);
SAMPLER(samplerunity_SpecCube1);

#endif
