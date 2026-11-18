// The light at the pointer (components/light.luau): a soft glow round the
// pointer on the shape it is over, cut to that shape and only there. It
// fades out just inside the outline, so the rim stays the shape's own.
// Still pointer, still light; off the shape, no light. A button held opens
// it a little wider.
//
// Bioluminescent, the light shows a living pattern where it falls: noise
// warped by noise (Inigo Quilez's domain warping, as Genoma's showcase
// draws it), in two tones of the background's own hue, brightest where
// the field folds (Akusen, 2026-11-18). The pattern is stirred by the hand, not by a
// clock: where the pointer is sets how far it has flowed, so it moves as
// the pointer moves and is still when it is still. It is laid in the
// screen's own space, so it runs on from one shape into the next.
//
// The numbers:
//   0     the shape's corner radius, logical units
//   1…4   the light's colour, straight alpha (bioluminescent: the first
//         tone)
//   5     how far it reaches, logical units
//   6     0 soft, 1 bioluminescent
//   7…9   the second tone

fn living(p: vec2<f32>) -> vec4<f32> {
    // Logical units from the screen's corner, for the point and the hand.
    let corner = shader.origin / max(shader.scale, 1e-3);
    let uv = (corner + p) / 160.0;
    let stir = (corner + shader.pointer.xy) * 0.002;
    let q = vec2<f32>(g_fbm(uv + stir, 4), g_fbm(uv + vec2<f32>(5.2, 1.3) - stir * 0.7, 4));
    let r = vec2<f32>(
        g_fbm(uv + 3.0 * q + vec2<f32>(1.7, 9.2) + stir * 0.6, 4),
        g_fbm(uv + 3.0 * q + vec2<f32>(8.3, 2.8) - stir * 0.4, 4),
    );
    let f = 0.5 + 0.5 * g_fbm(uv + 3.0 * r, 4);
    let first = vec3<f32>(value(1), value(2), value(3));
    let second = vec3<f32>(value(7), value(8), value(9));
    let colour = mix(first, second, clamp(length(r) * 0.9, 0.0, 1.0));
    // Lit where the field folds hardest; a faint glow between.
    let glow = clamp(0.25 + 1.6 * f * f * f + 0.35 * length(q), 0.0, 1.6);
    return vec4<f32>(colour, glow);
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    if (shader.pointer.z < 0.5) {
        return vec4<f32>(0.0);
    }
    let half = shader.size * 0.5;
    let r = value(0);
    // Over this shape, or over a neighbour: only its own shape lights.
    if (g_sd_rounded_box(shader.pointer.xy - half, half, r) > 0.0) {
        return vec4<f32>(0.0);
    }
    let edge = g_sd_rounded_box(p - half, half, r);
    let inside = smoothstep(0.0, 2.0, -edge);
    let reach = value(5) * mix(1.0, 1.4, shader.pointer.w);
    let light = exp(-pow(length(p - shader.pointer.xy) / max(reach, 1.0), 2.0));
    if (value(6) < 0.5) {
        let a = value(4) * light * inside;
        return vec4<f32>(vec3<f32>(value(1), value(2), value(3)) * a, a);
    }
    if (light * inside < 0.004) {
        return vec4<f32>(0.0);
    }
    let life = living(p);
    let a = clamp(value(4) * light * inside * life.a, 0.0, 1.0);
    return vec4<f32>(life.rgb * a, a);
}
