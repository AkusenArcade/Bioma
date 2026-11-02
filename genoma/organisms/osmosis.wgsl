// The osmosis organism's water (organisms/osmosis/osmosis.frag, in WGSL for
// a Genoma shader node): a membrane above, a pool below, and drops between
// them, all one field, so a drop grows out of the water it leaves and melts
// into the water it reaches. Read osmosis.frag for the reasoning; a change
// to one is carried to the other.
//
// The numbers:
//   0        radius     the panel's corner
//   1        membrane   its centre line, from the top
//   2        thickness
//   3        pool       the pool's surface, from the top
//   4…7      water
//   8…11     core       what the thick of the water turns towards
//   12…91    d0…d19     x, y, radius (logical), unused

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

fn sheet(out_: f32, reach: f32) -> f32 {
    if (out_ <= 0.0) { return 1.0 - 3.0 * out_ / reach; }
    let k = max(1.0 - out_ / reach, 0.0);
    return k * k * k;
}

fn sheet_slope(out_: f32, reach: f32) -> f32 {
    if (out_ <= 0.0) { return 3.0 / reach; }
    let k = max(1.0 - out_ / reach, 0.0);
    return 3.0 * k * k / reach;
}

fn box_(p: vec2<f32>, half_: vec2<f32>, r: f32) -> f32 {
    let q = abs(p) - half_ + vec2<f32>(r);
    return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let extent = shader.size;
    let unit = extent.x / 240.0;
    let reach = 16.0 * unit;

    var f = 0.0;
    var out_ = vec2<f32>(0.0);
    for (var i = 0; i < 20; i++) {
        let b = colour_at(12 + i * 4);
        f += field(p, b);
        out_ += slope(p, b);
    }

    // The pool: outward is up.
    let above_pool = value(3) - p.y;
    f += sheet(above_pool, reach);
    out_ += vec2<f32>(0.0, -sheet_slope(above_pool, reach));

    // The membrane: outward is away from its centre line, either way.
    let from_line = p.y - value(1);
    let outside_membrane = abs(from_line) - value(2) * 0.5;
    f += sheet(outside_membrane, reach);
    out_ += vec2<f32>(0.0, sign(from_line) * sheet_slope(outside_membrane, reach));

    // Before any branch on the pixel: derivatives need the whole quad.
    let w = max(fwidth(f), 1e-4);
    let inside = smoothstep(1.0 - w, 1.0 + w, f);

    let steep = length(out_);
    let normal = out_ / max(steep, 1e-6);
    let depth = min(max(f - 1.0, 0.0) / max(steep, 1e-4), (f - 1.0) * 40.0 * unit);

    let water = colour_at(4).rgb;
    let core = colour_at(8).rgb;
    let thick = smoothstep(0.0, 24.0 * unit, depth);
    var colour = mix(water, core, 0.18 * thick);
    var body = mix(0.45, 0.78, thick);

    let band = 1.0 - smoothstep(0.0, 3.0 * unit, depth);
    let lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    var a = inside * body;
    let edge = box_(p - extent * 0.5, extent * 0.5, value(0));
    a *= 1.0 - smoothstep(-0.5, 0.5, edge);
    return vec4<f32>(colour * a, a);
}
