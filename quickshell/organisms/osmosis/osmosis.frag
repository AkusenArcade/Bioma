#version 440

// The osmosis organism's water: a membrane across the top, a pool at the
// bottom, and up to twenty drops between them, all summed into one field and
// drawn where it passes one. A drop near the membrane or the pool shares a
// surface with it, which is what the eye reads as budding off and merging in.
//
// The wax shader's field and light (lava.frag), with two reservoirs added.
// Compiled to osmosis.frag.qsb by scripts/shaders; the .qsb is what QML loads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 extent;      // the item, in logical pixels
    float radius;     // the panel's corner
    float membrane;   // the membrane's centre line, pixels from the top
    float thickness;  // the membrane, pixels
    float pool;       // the pool's surface, pixels from the top
    vec4 water;
    vec4 core;        // what the thick of the water turns towards
    vec4 d0; vec4 d1; vec4 d2; vec4 d3; vec4 d4;
    vec4 d5; vec4 d6; vec4 d7; vec4 d8; vec4 d9;
    vec4 d10; vec4 d11; vec4 d12; vec4 d13; vec4 d14;
    vec4 d15; vec4 d16; vec4 d17; vec4 d18; vec4 d19;   // x, y, radius (pixels), unused
};

// A drop: the lava lamp's compact bump, one at its own radius.
const float REACH = 2.0;
const float AT_RADIUS = 0.421875;   // (1 - 1/REACH²)³

float field(vec2 p, vec4 b) {
    float R2 = b.z * b.z * REACH * REACH;
    vec2 d = p - b.xy;
    float k = max(1.0 - dot(d, d) / max(R2, 1e-4), 0.0);
    return k * k * k / AT_RADIUS;
}

vec2 slope(vec2 p, vec4 b) {
    float R2 = b.z * b.z * REACH * REACH;
    vec2 d = p - b.xy;
    float k = max(1.0 - dot(d, d) / max(R2, 1e-4), 0.0);
    return d * (6.0 * k * k / max(R2, 1e-4) / AT_RADIUS);
}

// A reservoir's field at `out_` pixels outside its surface: one at the
// surface, falling as a cube to nothing at `reach`, rising in a straight line
// inside, with the same slope on both sides, so a drop meets it smoothly.
float sheet(float out_, float reach) {
    if (out_ <= 0.0)
        return 1.0 - 3.0 * out_ / reach;
    float k = max(1.0 - out_ / reach, 0.0);
    return k * k * k;
}

// How fast that field falls going outward: its slope's length.
float sheetSlope(float out_, float reach) {
    if (out_ <= 0.0)
        return 3.0 / reach;
    float k = max(1.0 - out_ / reach, 0.0);
    return 3.0 * k * k / reach;
}

float box(vec2 p, vec2 half_, float r) {
    vec2 q = abs(p) - half_ + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * extent;
    float unit = extent.x / 240.0;
    float reach = 16.0 * unit;

    float f = field(p, d0) + field(p, d1) + field(p, d2) + field(p, d3) + field(p, d4)
            + field(p, d5) + field(p, d6) + field(p, d7) + field(p, d8) + field(p, d9)
            + field(p, d10) + field(p, d11) + field(p, d12) + field(p, d13) + field(p, d14)
            + field(p, d15) + field(p, d16) + field(p, d17) + field(p, d18) + field(p, d19);
    vec2 out_ = slope(p, d0) + slope(p, d1) + slope(p, d2) + slope(p, d3) + slope(p, d4)
              + slope(p, d5) + slope(p, d6) + slope(p, d7) + slope(p, d8) + slope(p, d9)
              + slope(p, d10) + slope(p, d11) + slope(p, d12) + slope(p, d13) + slope(p, d14)
              + slope(p, d15) + slope(p, d16) + slope(p, d17) + slope(p, d18) + slope(p, d19);

    // The pool: outward is up.
    float abovePool = pool - p.y;
    f += sheet(abovePool, reach);
    out_ += vec2(0.0, -sheetSlope(abovePool, reach));

    // The membrane: outward is away from its centre line, either way.
    float fromLine = p.y - membrane;
    float outsideMembrane = abs(fromLine) - thickness * 0.5;
    f += sheet(outsideMembrane, reach);
    out_ += vec2(0.0, sign(fromLine) * sheetSlope(outsideMembrane, reach));

    float w = max(fwidth(f), 1e-4);
    float inside = smoothstep(1.0 - w, 1.0 + w, f);

    // Depth inside the water, in pixels, as the lava lamp measures its wax.
    float steep = length(out_);
    vec2 normal = out_ / max(steep, 1e-6);
    float depth = min(max(f - 1.0, 0.0) / max(steep, 1e-4), (f - 1.0) * 40.0 * unit);

    // Water is thinner than wax: more of the glass shows through it.
    float thick = smoothstep(0.0, 24.0 * unit, depth);
    vec3 colour = mix(water.rgb, core.rgb, 0.18 * thick);
    float body = mix(0.45, 0.78, thick);

    // Lit along the top of every edge, as every cell's border is.
    float band = 1.0 - smoothstep(0.0, 3.0 * unit, depth);
    float lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core.rgb, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    float a = inside * body;

    float edge = box(p - extent * 0.5, extent * 0.5, radius);
    a *= 1.0 - smoothstep(-0.5, 0.5, edge);

    fragColor = vec4(colour * a, a) * qt_Opacity;
}
