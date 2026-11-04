#version 440

// The lava organism's wax: ten blobs summed into one field, drawn where the
// field passes one. Two blobs close enough share a surface, which is what the
// eye reads as melting together.
//
// Compiled to lava.frag.qsb by scripts/shaders; the .qsb is what QML loads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 extent;    // the item, in logical pixels
    float radius;   // the panel's corner
    float heat;     // 0 cold … 1 hot: the heater's light at the bottom
    vec4 wax;       // the state colour
    vec4 core;      // what the thick of a blob turns towards
    vec4 b0; vec4 b1; vec4 b2; vec4 b3; vec4 b4;
    vec4 b5; vec4 b6; vec4 b7; vec4 b8; vec4 b9;   // x, y, radius (pixels), unused
};

// Each blob's reach is twice its radius, and its field there falls to
// nothing: a smooth bump with no peak to infinity, so the slope is defined
// everywhere and a crowd of blobs does not swell into one mass the way an
// inverse-square field does. Divided by its value at the radius, so the
// surface of a lone blob is exactly its radius.
const float REACH = 2.0;
const float AT_RADIUS = 0.421875;   // (1 - 1/REACH²)³

float field(vec2 p, vec4 b) {
    float R2 = b.z * b.z * REACH * REACH;
    vec2 d = p - b.xy;
    float k = max(1.0 - dot(d, d) / max(R2, 1e-4), 0.0);
    return k * k * k / AT_RADIUS;
}

// Its slope, pointing away from the blob: summed, the outward direction of the
// surface at any point, which is what decides where the light catches it.
vec2 slope(vec2 p, vec4 b) {
    float R2 = b.z * b.z * REACH * REACH;
    vec2 d = p - b.xy;
    float k = max(1.0 - dot(d, d) / max(R2, 1e-4), 0.0);
    return d * (6.0 * k * k / max(R2, 1e-4) / AT_RADIUS);
}

// A rounded box, signed: negative inside.
float box(vec2 p, vec2 half_, float r) {
    vec2 q = abs(p) - half_ + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * extent;

    float f = field(p, b0) + field(p, b1) + field(p, b2) + field(p, b3) + field(p, b4)
            + field(p, b5) + field(p, b6) + field(p, b7) + field(p, b8) + field(p, b9);

    // The edge, one pixel soft whatever the slope of the field.
    float w = max(fwidth(f), 1e-4);
    float inside = smoothstep(1.0 - w, 1.0 + w, f);

    // How far inside the wax this point is, in pixels: the field's excess
    // over its threshold divided by its slope. It follows the surface of the
    // whole merged mass, where the field itself peaks at every blob's centre
    // and would show the spheres the mass is made of.
    vec2 out_ = slope(p, b0) + slope(p, b1) + slope(p, b2) + slope(p, b3) + slope(p, b4)
              + slope(p, b5) + slope(p, b6) + slope(p, b7) + slope(p, b8) + slope(p, b9);
    float steep = length(out_);
    vec2 normal = out_ / max(steep, 1e-6);

    float unit = extent.x / 200.0;
    // Where two blobs meet, the slope of the field is zero at the middle of
    // the neck and the estimate runs to infinity, lighting a speck in the
    // thinnest wax there is. The field's own excess bounds it: a neck is wax
    // barely over the threshold.
    float depth = min(max(f - 1.0, 0.0) / max(steep, 1e-4), (f - 1.0) * 40.0 * unit);

    // Wax, not paint: light passes through it. Thin wax — the edge of a blob,
    // the neck between two — lets the glass behind show; deeper in, it is
    // denser and lighter, as if lit from within.
    float thick = smoothstep(0.0, 26.0 * unit, depth);
    vec3 colour = mix(wax.rgb, core.rgb, 0.22 * thick);
    float body = mix(0.55, 0.88, thick);

    // The rim: a band just inside the edge, brightest where the surface faces
    // up towards the light, as the lit border runs along every cell's top.
    float band = 1.0 - smoothstep(0.0, 3.5 * unit, depth);
    float lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core.rgb, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    float waxAlpha = inside * body;

    // The heater: the light at the bottom of the lamp, as strong as it is hot.
    float fromBottom = (extent.y - p.y) / extent.y;
    float glow = heat * 0.38 * exp(-fromBottom * 5.0);

    float a = waxAlpha + (1.0 - waxAlpha) * glow;
    vec3 rgb = (colour * waxAlpha + wax.rgb * glow * (1.0 - waxAlpha)) / max(a, 1e-4);

    // Clipped to the panel it fills.
    float edge = box(p - extent * 0.5, extent * 0.5, radius);
    a *= 1.0 - smoothstep(-0.5, 0.5, edge);

    fragColor = vec4(rgb * a, a) * qt_Opacity;
}
