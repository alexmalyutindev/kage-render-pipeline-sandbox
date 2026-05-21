#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"


half PackHalf44(half a, half b)
{
    uint a4 = (uint)(saturate(a) * 15.0f);
    uint b4 = (uint)(saturate(b) * 15.0f);
    uint packed = b4 << 4 | a4;
    return packed;
}

void UnpackHalf44(half packed, out half a, out half b)
{
    uint packed8 = packed;
    uint a4 = packed8 & 0x0F;
    uint b4 = packed8 >> 4 & 0x0F;

    a = half(a4) / 15.0h;
    b = half(b4) / 15.0h;
}

half PackHalf442(half a, half b, half c)
{
    uint a4 = round(saturate(a) * 15.0h);
    uint b4 = round(saturate(b) * 15.0h);
    uint c2 = round(saturate(c) * 3.0h);
    uint packed = a4 | b4 << 4 | c2 << 8;
    return (half)packed;
}

void UnpackHalf442(half packed, out half a, out half b, out half c)
{
    uint p = packed;

    uint a4 = p & 0x0F;
    uint b4 = p >> 4 & 0x0F;
    uint c2 = p >> 8 & 0x03;

    a = (half)a4 / 15.0h;
    b = (half)b4 / 15.0h;
    c = (half)c2 / 3.0h;
}

half PackHalf66(half a, half b)
{
    uint a6 = round(saturate(a) * 63.0h);
    uint b6 = round(saturate(b) * 63.0h);
    uint packed = a6 | b6 << 6;
    return (half)packed;
}

void UnpackHalf66(half packed, out half a, out half b)
{
    uint p = packed;
    uint a6 = p & 0x3F;
    uint b6 = p >> 6 & 0x3F;
    a = (half)a6 / 63.0h;
    b = (half)b6 / 63.0h;
}

half PackHalf84(half a, half b)
{
    uint a8 = round(saturate(a) * 255.0h);
    uint b4 = round(saturate(b) * 15.0h);
    uint packed = a8 | b4 << 8;
    return (half)packed;
}

void UnpackHalf84(half packed, out half a, out half b)
{
    uint p = packed;
    uint a8 = p & 0xFF;
    uint b4 = p >> 8 & 0x0F;
    a = (half)a8 / 255.0h;
    b = (half)b4 / 15.0h;
}
