#ifndef KAGERP_INPUT
#define KAGERP_INPUT

#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/ShaderTypes.cs.hlsl"

float4 _MainLightPosition;
half4 _MainLightColor;

// x - lights count
half4 _AdditionalLightsCount;

#define UNITY_MATRIX_M unity_ObjectToWorld
#define UNITY_MATRIX_I_M unity_WorldToObject
#define UNITY_PREV_MATRIX_M unity_ObjectToWorld
#define UNITY_PREV_MATRIX_I_M unity_WorldToObject

#define UNITY_MATRIX_V unity_MatrixV
#define UNITY_MATRIX_I_V unity_MatrixInvV

#define UNITY_MATRIX_VP unity_MatrixVP
#define UNITY_MATRIX_P unity_CameraProjection

StructuredBuffer<LightData> _AdditionalLightsBuffer;
StructuredBuffer<int> _AdditionalLightsIndices;

#endif
