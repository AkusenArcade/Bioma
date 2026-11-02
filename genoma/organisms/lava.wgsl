// The lava organism's wax (organisms/lava/lava.frag, in WGSL for a Genoma
// shader node): ten blobs summed into one field, drawn where the field
// passes one. Read lava.frag for the reasoning; a change to one is carried
// to the other.
//
// The numbers:
//   0        radius  the panel's corner
//   1        heat    0 cold … 1 hot: the heater's light at the bottom
//   4…7      wax     the state colour
//   8…11     core    what the thick of a blob turns towards
//   12…51    b0…b9   x, y, radius (logical), unused

const REACH: f32 = 2.0;
const AT_RADIUS: f32 = 0.421875;

fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}

fn field(p: vec2<f32>, b: vec4<f32>) -> f32 {
    let r2 = b.z * b.z * REACH * REACH;
    let d = p - b.xy;
    let k = max(1.0 - dot(d, d) / max(r2, 1e-4), 0.0);
    return k * k * k / AT_RADIUS;
}

fn slope(p: vec2<f32>, b: vec4<f32>) -> vec2<f32> {
    let r2 = b.z * b.z * REACH * REACH;
    let d = p - b.xy;
    let k = max(1.0 - dot(d, d) / max(r2, 1e-4), 0.0);
    return d * (6.0 * k * k / max(r2, 1e-4) / AT_RADIUS);
}

fn box_(p: vec2<f32>, half_: vec2<f32>, r: f32) -> f32 {
    let q = abs(p) - half_ + vec2<f32>(r);
    return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let extent = shader.size;
    var f = 0.0;
    var out_ = vec2<f32>(0.0);
    for (var i = 0; i < 10; i++) {
        let b = colour_at(12 + i * 4);
        f += field(p, b);
        out_ += slope(p, b);
    }
    // Before any branch on the pixel: derivatives need the whole quad.
    let w = max(fwidth(f), 1e-4);
    let inside = smoothstep(1.0 - w, 1.0 + w, f);

    let steep = length(out_);
    let normal = out_ / max(steep, 1e-6);
    let unit = extent.x / 200.0;
    let depth = min(max(f - 1.0, 0.0) / max(steep, 1e-4), (f - 1.0) * 40.0 * unit);

    let wax = colour_at(4).rgb;
    let core = colour_at(8).rgb;
    let thick = smoothstep(0.0, 26.0 * unit, depth);
    var colour = mix(wax, core, 0.22 * thick);
    var body = mix(0.55, 0.88, thick);

    let band = 1.0 - smoothstep(0.0, 3.5 * unit, depth);
    let lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    let wax_alpha = inside * body;

    // The heater: the light at the bottom of the lamp, as strong as it is hot.
    let from_bottom = (extent.y - p.y) / extent.y;
    let glow = value(1) * 0.38 * exp(-from_bottom * 5.0);

    var a = wax_alpha + (1.0 - wax_alpha) * glow;
    let rgb = (colour * wax_alpha + wax * glow * (1.0 - wax_alpha)) / max(a, 1e-4);

    let edge = box_(p - extent * 0.5, extent * 0.5, value(0));
    a *= 1.0 - smoothstep(-0.5, 0.5, edge);
    return vec4<f32>(rgb * a, a);
}
