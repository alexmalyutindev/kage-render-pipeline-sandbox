#include "Packages/com.alexmalyutin.render-pipelines.kage/ShaderLibrary/Core.hlsl"

#define PARALLAX_BIAS 0.99
#define PARALLAX_OFFSET_LIMITING
#define PARALLAX_RAYMARCHING_INTERPOLATE
// #define PARALLAX_RAYMARCHING_SEARCH_STEPS 3

float SampleHeight(TEXTURE2D_PARAM(heightMap, sampler_heightMap), float2 uv)
{
    return SAMPLE_TEXTURE2D_LOD(heightMap, sampler_heightMap, uv, 0).r;
}

float2 ParallaxRaymarching(TEXTURE2D_PARAM(heightMap, sampler_heightMap), float2 viewDir, float scale, float2 uv)
{
    #if !defined(PARALLAX_RAYMARCHING_STEPS)
    #define PARALLAX_RAYMARCHING_STEPS 6
    #endif

    float2 uvOffset = 0;
    float stepSize = 1.0f / PARALLAX_RAYMARCHING_STEPS;
    float2 uvDelta = viewDir * (stepSize * scale);

    float stepHeight = 1;
    float surfaceHeight = SampleHeight(heightMap, sampler_heightMap, uv);

    float2 prevUVOffset = uvOffset;
    float prevStepHeight = stepHeight;
    float prevSurfaceHeight = surfaceHeight;

    for (int i = 1; i < PARALLAX_RAYMARCHING_STEPS && stepHeight > surfaceHeight; i++)
    {
        prevUVOffset = uvOffset;
        prevStepHeight = stepHeight;
        prevSurfaceHeight = surfaceHeight;

        uvOffset -= uvDelta;
        stepHeight -= stepSize;
        surfaceHeight = SampleHeight(heightMap, sampler_heightMap, uv + uvOffset);
    }

    #if !defined(PARALLAX_RAYMARCHING_SEARCH_STEPS)
    #define PARALLAX_RAYMARCHING_SEARCH_STEPS 0
    #endif

    #if PARALLAX_RAYMARCHING_SEARCH_STEPS > 0
    for (int i0 = 0; i0 < PARALLAX_RAYMARCHING_SEARCH_STEPS; i0++) {
        uvDelta *= 0.5;
        stepSize *= 0.5;

        if (stepHeight < surfaceHeight) {
            uvOffset += uvDelta;
            stepHeight += stepSize;
        }
        else {
            uvOffset -= uvDelta;
            stepHeight -= stepSize;
        }
        surfaceHeight = SampleHeight(heightMap, sampler_heightMap, uv + uvOffset);
    }
    #elif defined(PARALLAX_RAYMARCHING_INTERPOLATE)
    float prevDifference = prevStepHeight - prevSurfaceHeight;
    float difference = max(0.01, surfaceHeight - stepHeight);
    float t = prevDifference / (prevDifference + difference);
    uvOffset = prevUVOffset - uvDelta * t;
    #endif

    // TODO: Faster Relief Mapping Using the Secant Method - Eric Risser
    #if POM_SECANT_METHOD
    {
        real pt0 = stepHeight + stepSize;
        real pt1 = stepHeight;
        real delta0 = pt0 - prevStepHeight;
        real delta1 = pt1 - surfaceHeight;

        real delta;
        real2 offset;
    
        for (int i = 0; i < 3; ++i)
        {
            // intersectionHeight is the height [0..1] for the intersection between view ray and heightfield line
            real intersectionHeight = (pt0 * delta1 - pt1 * delta0) / (delta1 - delta0);
            // Retrieve offset require to find this intersectionHeight
            offset = (1 - intersectionHeight) * texOffsetPerStep * numSteps;

            currHeight = SampleHeight(heightMap, sampler_heightMap, uv + uvOffset);

            delta = intersectionHeight - currHeight;

            if (abs(delta) <= 0.01)
                break;

            // intersectionHeight < currHeight => new lower bounds
            if (delta < 0.0)
            {
                delta1 = delta;
                pt1 = intersectionHeight;
            }
            else
            {
                delta0 = delta;
                pt0 = intersectionHeight;
            }
        }
    }
    #endif

    return uvOffset;
}

void ApplyPerPixelDisplacement(TEXTURE2D_PARAM(heightMap, sampler_heightMap), half3 normalizedViewDirTS, float scale, inout float2 uv)
{
    #if !defined(PARALLAX_BIAS)
    #define PARALLAX_BIAS 0.42
    #endif
    normalizedViewDirTS.xy /= normalizedViewDirTS.z + PARALLAX_BIAS;
    uv += ParallaxRaymarching(heightMap, sampler_heightMap, normalizedViewDirTS.xy, scale, uv);
}