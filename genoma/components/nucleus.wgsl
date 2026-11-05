// The battery vital (components/vital.luau): the nucleus organism at the
// size of a vital. The same tissue as organisms/cytoplasm.wgsl, one
// application of four lobes (the mass and three drops) that melt together,
// over the faint envelope it could fill; full on the mains, a bolt cut out
// of it, a hole that shows whatever the indicator sits on. A change to the
// tissue there is carried here.
//
// The numbers (logical units):
//   0        unit      the tissue's scale: the cytoplasm's unit at this size
//   1        bolt      0…1, how far the bolt is cut out
//   2        grid      logical units per unit of the design's 64 grid
//   3        envelope  the inside of the ring, a radius about the centre
//   4…7      core      the text colour
//   8…11     wax       the state colour
//   12…27    l0…l3     x, y, radius, unused: the mass, then three drops

const REACH: f32 = 2.0;
const AT_RADIUS: f32 = 0.421875;

fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}
fn lobe(i: i32) -> vec4<f32> { return colour_at(12 + i * 4); }

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

// The bolt the Quickshell vital cut out (components/Vital.qml), in the 64
// grid about the centre: a signed distance, negative inside.
fn bolt(q: vec2<f32>) -> f32 {
    var v = array<vec2<f32>, 6>(
        vec2<f32>(4.0, -16.0), vec2<f32>(-9.0, 3.0), vec2<f32>(-1.0, 3.0),
        vec2<f32>(-4.0, 16.0), vec2<f32>(9.0, -3.0), vec2<f32>(1.0, -3.0));
    var d = dot(q - v[0], q - v[0]);
    var s = 1.0;
    var j = 5;
    for (var i = 0; i < 6; i++) {
        let e = v[j] - v[i];
        let w = q - v[i];
        let b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        let above = q.y >= v[i].y;
        let below = v[j].y > q.y;
        let left = e.x * w.y > e.y * w.x;
        if ((above && below && left) || (!above && !below && !left)) { s = -s; }
        j = i;
    }
    return s * sqrt(d);
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let unit = value(0);
    let centre = shader.size * 0.5;
    let half_px = 0.5 / shader.scale;

    var fo = 0.0;
    var so = vec2<f32>(0.0);
    for (var j = 0; j < 4; j++) {
        let b = lobe(j);
        fo += field(p, b);
        so += slope(p, b);
    }
    let wax = colour_at(8).rgb;
    let core = colour_at(4).rgb;

    // Before any branch on the pixel: derivatives need the whole quad.
    let w = max(fwidth(fo), 1e-4);
    let inside = smoothstep(1.0 - w, 1.0 + w, fo);

    let steep = length(so);
    let normal = so / max(steep, 1e-6);
    let depth = min(max(fo - 1.0, 0.0) / max(steep, 1e-4), (fo - 1.0) * 40.0 * unit);

    let thick = smoothstep(0.0, 22.0 * unit, depth);
    var colour = mix(wax, core, 0.22 * thick);
    var body = mix(0.5, 0.85, thick);

    // The lit rim, never thinner than a pixel and a half: at the
    // organism's scale it would be a tenth of one here and not be seen.
    let band = 1.0 - smoothstep(0.0, max(3.0 * unit, 3.0 * half_px), depth);
    let lit = band * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core, 0.5 * lit);
    body = min(1.0, body + 0.3 * lit);

    let grid = value(2);
    let cut = smoothstep(-half_px, half_px, bolt((p - centre) / grid) * grid);
    let a = inside * body * mix(1.0, cut, value(1));

    // The envelope, the battery full: the organism's text at 3 %.
    let room = 1.0 - smoothstep(value(3) - half_px, value(3) + half_px, length(p - centre));
    let e = 0.03 * room;
    return vec4<f32>(colour * a + core * e * (1.0 - a), a + e * (1.0 - a));
}
