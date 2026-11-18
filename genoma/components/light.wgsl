// The light at the pointer (components/light.luau): a soft glow round the
// pointer on the shape it is over, cut to that shape and only there. It
// fades out just inside the outline, so the rim stays the shape's own.
// Still pointer, still light; off the shape, no light. A button held opens
// it a little wider.
//
// The numbers:
//   0     the shape's corner radius, logical units
//   1…4   the light's colour, straight alpha
//   5     how far it reaches, logical units

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
    let a = value(4) * light * inside;
    return vec4<f32>(vec3<f32>(value(1), value(2), value(3)) * a, a);
}
