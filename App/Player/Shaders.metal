#include <metal_stdlib>
using namespace metal;

// Our own shaders. Compiled into the app (no downloaded shader code).

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut screen_vertex(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 t[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VOut o;
    o.position = float4(p[vid], 0, 1);
    o.uv = t[vid];
    return o;
}

struct Params {
    float2 texSize;     // source pixels
    float2 outSize;     // drawable pixels
    int mode;           // 0 sharp, 1 integer/nearest, 2 scanlines, 3 LCD
};

// Integer prescale then bilinear: crisp pixels without shimmer at non-integer sizes.
static float2 sharpUV(float2 uv, float2 texSize, float2 outSize) {
    float2 texel = uv * texSize;
    float2 scale = max(floor(outSize / texSize), float2(1.0));
    float2 base = floor(texel);
    float2 f = fract(texel) - 0.5;
    float2 range = 0.5 - 0.5 / scale;
    float2 g = (f - clamp(f, -range, range)) * scale + 0.5;
    return (base + g) / texSize;
}

fragment float4 screen_fragment(VOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant Params &p [[buffer(0)]]) {
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;
    if (p.mode == 1) {
        return tex.sample(nearest, uv);
    }
    float4 c = tex.sample(linear, sharpUV(uv, p.texSize, p.outSize));
    if (p.mode == 2) {
        // Soft scanlines with a little bloom on bright rows.
        float y = fract(uv.y * p.texSize.y);
        float lum = dot(c.rgb, float3(0.299, 0.587, 0.114));
        float line = mix(0.62, 1.0, smoothstep(0.0, 0.5, 0.5 - abs(y - 0.5)) * (1.0 - lum * 0.35) + lum * 0.35);
        c.rgb *= line * 1.08;
    } else if (p.mode == 3) {
        // LCD: a faint grid between pixels and a cool tint.
        float2 cell = fract(uv * p.texSize);
        float2 edge = smoothstep(0.0, 0.12, cell) * smoothstep(0.0, 0.12, 1.0 - cell);
        c.rgb *= mix(0.78, 1.0, edge.x * edge.y);
    }
    return float4(c.rgb, 1.0);
}
