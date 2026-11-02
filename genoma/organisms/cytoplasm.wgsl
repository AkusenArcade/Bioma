// The cytoplasm organism's field (organisms/cytoplasm/cytoplasm.frag, in
// WGSL for a Genoma shader node): six applications, four lobes each. Lobes
// of one application sum into one field and melt together; two applications
// never do: where they meet, the stronger field is drawn, so they press
// against each other and stay two. The nucleus organism draws its battery
// with it too. Read cytoplasm.frag for the reasoning; a change to one is
// carried to the other.
//
// The numbers:
//   0        radius   the panel's corner
//   4…7      core     what the thick of the wax turns towards
//   8…31     c0…c5    each application's colour
//   32…127   l0…l23   x, y, radius (logical), unused: four per application

const REACH: f32 = 2.0;
const AT_RADIUS: f32 = 0.421875;

fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}
fn lobe(i: i32) -> vec4<f32> { return colour_at(32 + i * 4); }

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
    var f: array<f32, 6>;
    var s: array<vec2<f32>, 6>;
    for (var c = 0; c < 6; c++) {
        var fc = 0.0;
        var sc = vec2<f32>(0.0);
        for (var j = 0; j < 4; j++) {
            let b = lobe(c * 4 + j);
            fc += field(p, b);
            sc += slope(p, b);
        }
        f[c] = fc;
        s[c] = sc;
    }

    // The application whose field is strongest here owns the point.
    var owner = 0;
    for (var i = 1; i < 6; i++) {
        if (f[i] > f[owner]) { owner = i; }
    }
    // The nearest rival: the next strongest field.
    var rival = select(0, 1, owner == 0);
    for (var i = 0; i < 6; i++) {
        if (i != owner && f[i] > f[rival]) { rival = i; }
    }
    let fo = f[owner];
    let so = s[owner];
    let fr = f[rival];
    let sr = s[rival];
    let wax = colour_at(8 + owner * 4).rgb;
    let core = colour_at(4).rgb;

    // Before any branch on the pixel: derivatives need the whole quad. Per
    // physical pixel here, so the edge is half a physical pixel each side.
    let w = max(fwidth(fo), 1e-4);
    var inside = smoothstep(1.0 - w, 1.0 + w, fo);

    let unit = extent.x / 360.0;
    let steep = length(so);
    let normal = so / max(steep, 1e-6);

    // Depth inside the merged surface, bounded where the slope vanishes.
    var depth = min(max(fo - 1.0, 0.0) / max(steep, 1e-4), (fo - 1.0) * 40.0 * unit);

    // Where two applications press together the seam is where their fields
    // are equal: each cell is given its own edge there.
    let contact = smoothstep(0.8, 1.0, fr);
    let seam = mix(1e4, (fo - fr) / max(length(so - sr), 1e-4), contact);
    depth = min(depth, seam);
    inside *= smoothstep(0.3 * unit, 1.3 * unit, seam);

    let thick = smoothstep(0.0, 22.0 * unit, depth);
    var colour = mix(wax, core, 0.22 * thick);
    var body = mix(0.5, 0.85, thick);

    let band = 1.0 - smoothstep(0.0, 3.0 * unit, depth);
    let lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    var a = inside * body;
    let edge = box_(p - extent * 0.5, extent * 0.5, value(0));
    a *= 1.0 - smoothstep(-0.5, 0.5, edge);
    return vec4<f32>(colour * a, a);
}
