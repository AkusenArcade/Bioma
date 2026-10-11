#version 440

// The band as a fluid, in one of two forms, both mirrored from the centre as
// the bars are: the left channel on the left, the right on the right, the low
// frequencies meeting at the middle.
//
// - plasma: a drop for every band on the middle line, as large as the band is
//   loud, all of them one body. Its outline is the spectrum.
// - vesicles: a drop for every band that divides as the band gets louder —
//   one dot at silence, stretched, pinched, then two drops mirrored across
//   the middle line, as far from it as the band is loud. The extent is the
//   data, as the bars' height is.
// - eardrum: a membrane stretched along the middle line, held at both ends
//   as the eardrum is by its ring, with the umbo — where the hammer holds
//   it — at the centre. Each band shakes the stretch of it where its bar
//   would stand, as far as it is loud. The low bands at the centre move the
//   membrane as a whole, slowly and in long waves, as a real eardrum does at
//   low frequencies; towards the ends the highs break it into short, quick
//   ripples. The waves run outwards from the umbo, mirrored, and a faint
//   envelope shows how far it swings. Silent, it is a taut, still line.
//
// The union is a smooth minimum of distances, not a sum of fields: a sum
// swells wherever drops crowd together and a loud passage would rise out of
// the band, while a smooth minimum never reaches past its largest shape by
// more than a quarter of its blend. Neighbours that are loud together melt
// into one body; a pure tone stands alone.
//
// Compiled to fluid.frag.qsb by scripts/shaders; the .qsb is what QML loads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 extent;     // the item, in logical pixels
    float count;     // drops in the row, both wings together
    float pitch;     // from one drop's centre to the next
    float first;     // the first drop's centre, from the left
    float form;      // 0 plasma, 1 vesicles, 2 eardrum
    float time;      // seconds the eardrum has been shaking
    float thread;    // the silent dot's radius
    float drop;      // a drop's radius at full scale
    float blend;     // how far apart two vesicles still melt together
    vec4 upper;      // the gradient over the band's height, top to bottom
    vec4 lower;
    vec4 core;       // what the thick of a drop turns towards
    vec4 v0; vec4 v1; vec4 v2;  vec4 v3;  vec4 v4;  vec4 v5;
    vec4 v6; vec4 v7; vec4 v8;  vec4 v9;  vec4 v10; vec4 v11;  // the bands, 0 to 1, four to a vector
};

float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// The eardrum's colour at p: the membrane, its envelope and the umbo.
vec4 eardrum(vec2 p, float mid, int n, vec4 bands[12]) {
    float width_ = extent.x;
    float centre = width_ * 0.5;
    float reach = mid - thread - 1.0;
    float sigma = pitch;
    float half_ = max(float(n / 2) - 1.0, 1.0);

    float shake = 0.0;
    float swing = 0.0;
    float weight = 0.0;
    float atUmbo = 0.0;
    float umboWeight = 0.0;
    for (int i = 0; i < 48; i++) {
        if (i >= n)
            break;
        float v = clamp(bands[i / 4][i % 4], 0.0, 1.0);
        float x = first + float(i) * pitch;
        // 0 at the centre, the lowest band of its channel; 1 at the end.
        float rank = (i < n / 2 ? float(n / 2 - 1 - i) : float(i - n / 2)) / half_;
        float wave = 6.2831853 / mix(width_ * 0.5, pitch * 3.0, rank);
        float rate = 6.2831853 * mix(0.9, 6.0, rank);
        float g = exp(-pow((p.x - x) / sigma, 2.0));
        shake += v * g * sin(wave * abs(p.x - centre) - rate * time);
        swing += v * g;
        weight += g;
        float u = exp(-pow((centre - x) / sigma, 2.0));
        atUmbo += v * u * sin(-rate * time);
        umboWeight += u;
    }

    // Held at both ends by the ring.
    float hold = smoothstep(0.0, pitch * 2.0, p.x) * smoothstep(0.0, pitch * 2.0, width_ - p.x);
    float y = mid + reach * hold * shake / max(weight, 1e-3);
    float spread = reach * hold * swing / max(weight, 1e-3);
    float umboY = mid + reach * atUmbo / max(umboWeight, 1e-3);

    vec3 light = mix(upper.rgb, lower.rgb, clamp(p.y / extent.y, 0.0, 1.0));

    // The membrane: a line of even thickness whatever its slope.
    float slope = dFdx(y);
    float off = abs(p.y - y) / sqrt(1.0 + slope * slope);
    float line = 1.0 - smoothstep(thread - 0.5, thread + 0.5, off);

    // How far it swings, faint, as a vibrating string blurs.
    float env = (1.0 - smoothstep(spread - 0.5, spread + 0.5, abs(p.y - mid))) * 0.16;

    // The umbo.
    float node = 1.0 - smoothstep(thread * 1.9 - 0.5, thread * 1.9 + 0.5,
                                  length(p - vec2(centre, umboY)));

    float a = max(max(line * 0.95, env), node);
    vec3 colour = mix(light, core.rgb, 0.35 * max(line, node));
    return vec4(colour * a, a) * qt_Opacity;
}

void main() {
    vec2 p = qt_TexCoord0 * extent;
    float mid = extent.y * 0.5;

    vec4 bands[12] = vec4[](v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11);
    int n = int(count + 0.5);

    if (form > 1.5) {
        fragColor = eardrum(p, mid, n, bands);
        return;
    }

    float d = 1e5;

    if (form < 0.5) {
        // Plasma. The blend between two neighbours is the radius of the
        // smaller: a quiet drop beside a loud one barely touches it, two loud
        // ones are one body, and the dots of silence stay apart.
        float previous = 0.0;
        for (int i = 0; i < 48; i++) {
            if (i >= n)
                break;
            float v = clamp(bands[i / 4][i % 4], 0.0, 1.0);
            float r = mix(thread, drop, v);
            float own = length(p - vec2(first + float(i) * pitch, mid)) - r;
            d = smin(d, own, min(previous, r));
            previous = r;
        }
    } else {
        // Vesicles. A drop grows from the dot's size as it divides, and its
        // two halves stop short of the band's edge.
        float reach = mid - drop - 1.0;
        for (int i = 0; i < 48; i++) {
            if (i >= n)
                break;
            float x = first + float(i) * pitch;
            float near = abs(p.x - x);
            if (near > drop + blend)
                continue;
            float v = clamp(bands[i / 4][i % 4], 0.0, 1.0);
            float r = mix(thread, drop, sqrt(v));
            float off = v * reach;
            float up = length(vec2(near, p.y - (mid - off))) - r;
            float down = length(vec2(near, p.y - (mid + off))) - r;
            d = smin(d, smin(up, down, blend), blend);
        }
    }

    float inside = 1.0 - smoothstep(-0.5, 0.5, d);
    if (inside <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float depth = max(-d, 0.0);
    vec2 slope = vec2(dFdx(d), dFdy(d));
    vec2 normal = slope / max(length(slope), 1e-4);

    // Light passes through a drop: the edge and the necks let the glass behind
    // show, the thick of it is denser and lighter, as the lava lamp's wax is.
    float thick = smoothstep(0.0, 0.75 * drop, depth);
    vec3 colour = mix(upper.rgb, lower.rgb, clamp(p.y / extent.y, 0.0, 1.0));
    colour = mix(colour, core.rgb, 0.16 * thick);
    float body = mix(0.66, 0.96, thick);

    // The rim: a band just inside the edge, brightest where the surface faces
    // up, as the lit border runs along every cell's top.
    float rim = clamp(0.3 * drop, 1.0, 3.5);
    float band = 1.0 - smoothstep(0.0, rim, depth);
    float lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core.rgb, 0.45 * lit);
    body = min(1.0, body + 0.3 * lit);

    float a = inside * body;
    fragColor = vec4(colour * a, a) * qt_Opacity;
}
