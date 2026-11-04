#version 440

// The cytoplasm organism: six applications, four lobes each. Lobes of one
// application sum into one field and melt together; two applications never
// do — where they meet, the stronger field is drawn, so they press against
// each other and stay two.
//
// Compiled to cytoplasm.frag.qsb by scripts/shaders; the .qsb is what QML loads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 extent;    // the item, in logical pixels
    float radius;   // the panel's corner
    vec4 core;      // what the thick of the wax turns towards
    vec4 c0; vec4 c1; vec4 c2; vec4 c3; vec4 c4; vec4 c5;   // each application's colour
    // x, y, radius (pixels), unused — four per application, in order.
    vec4 l0;  vec4 l1;  vec4 l2;  vec4 l3;
    vec4 l4;  vec4 l5;  vec4 l6;  vec4 l7;
    vec4 l8;  vec4 l9;  vec4 l10; vec4 l11;
    vec4 l12; vec4 l13; vec4 l14; vec4 l15;
    vec4 l16; vec4 l17; vec4 l18; vec4 l19;
    vec4 l20; vec4 l21; vec4 l22; vec4 l23;
};

// The same compact bump as the lava lamp: reach twice the radius, the surface
// of a lone lobe exactly at its radius.
const float REACH = 2.0;
const float AT_RADIUS = 0.421875;

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

float box(vec2 p, vec2 half_, float r) {
    vec2 q = abs(p) - half_ + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// One application's field and slope at p.
void cell(vec2 p, vec4 a, vec4 b, vec4 c, vec4 d, out float f, out vec2 s) {
    f = field(p, a) + field(p, b) + field(p, c) + field(p, d);
    s = slope(p, a) + slope(p, b) + slope(p, c) + slope(p, d);
}

void main() {
    vec2 p = qt_TexCoord0 * extent;

    float f[6];
    vec2 s[6];
    cell(p, l0, l1, l2, l3, f[0], s[0]);
    cell(p, l4, l5, l6, l7, f[1], s[1]);
    cell(p, l8, l9, l10, l11, f[2], s[2]);
    cell(p, l12, l13, l14, l15, f[3], s[3]);
    cell(p, l16, l17, l18, l19, f[4], s[4]);
    cell(p, l20, l21, l22, l23, f[5], s[5]);
    vec4 colours[6] = vec4[6](c0, c1, c2, c3, c4, c5);

    // The application whose field is strongest here owns the point.
    int owner = 0;
    for (int i = 1; i < 6; i++)
        if (f[i] > f[owner])
            owner = i;
    float fo = f[owner];
    vec2 so = s[owner];
    vec3 wax = colours[owner].rgb;

    // The nearest rival: the application with the next strongest field.
    int rival = owner == 0 ? 1 : 0;
    for (int i = 0; i < 6; i++)
        if (i != owner && f[i] > f[rival])
            rival = i;
    float fr = f[rival];
    vec2 sr = s[rival];

    float w = max(fwidth(fo), 1e-4);
    float inside = smoothstep(1.0 - w, 1.0 + w, fo);

    float unit = extent.x / 360.0;
    float steep = length(so);
    vec2 normal = so / max(steep, 1e-6);

    // Depth inside the merged surface, bounded where the slope vanishes —
    // as in the lava lamp.
    float depth = min(max(fo - 1.0, 0.0) / max(steep, 1e-4), (fo - 1.0) * 40.0 * unit);

    // Where two applications press together the boundary is where their
    // fields are equal. Its distance in pixels is the difference over the
    // difference's slope — continuous across the boundary, so it can be
    // smoothed, where switching owner is a hard step. Each cell is given its
    // own edge there: the rim runs along the seam as it does along the
    // outside, and a pixel of glass shows between the two.
    float contact = smoothstep(0.8, 1.0, fr);
    float seam = (fo - fr) / max(length(so - sr), 1e-4);
    seam = mix(1e4, seam, contact);
    depth = min(depth, seam);
    inside *= smoothstep(0.3 * unit, 1.3 * unit, seam);

    float thick = smoothstep(0.0, 22.0 * unit, depth);
    vec3 colour = mix(wax, core.rgb, 0.22 * thick);
    float body = mix(0.5, 0.85, thick);

    float band = 1.0 - smoothstep(0.0, 3.0 * unit, depth);
    float lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core.rgb, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    float a = inside * body;

    float edge = box(p - extent * 0.5, extent * 0.5, radius);
    a *= 1.0 - smoothstep(-0.5, 0.5, edge);

    fragColor = vec4(colour * a, a) * qt_Opacity;
}
