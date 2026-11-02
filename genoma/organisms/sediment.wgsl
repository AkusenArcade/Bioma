// The sediment organism's strata (what organisms/sediment/
// SedimentOrganism.qml paints on a Canvas, in WGSL for a Genoma shader
// node): one layer per recent file, the newest on top, each as thick as it
// is recent; the beds between them wave each in its own way, the top one
// level, the surface lit.
//
// The numbers:
//   0…3      grain (the primary)
//   4        how many layers;  5  factor;  6  the column's height
//   8 + 3k   layer k: top, thickness, its wave's seed

fn wave(x: f32, seed: f32) -> f32 {
    let u = x / shader.size.x * 6.2831853;
    return 0.6 * sin(u + seed) + 0.4 * sin(2.3 * u + seed * 1.7);
}

fn over(dst: vec4<f32>, colour: vec3<f32>, alpha: f32) -> vec4<f32> {
    return vec4<f32>(colour * alpha + dst.rgb * (1.0 - alpha), alpha + dst.a * (1.0 - alpha));
}

// Where layer k's top runs at x.
fn top(k: i32, x: f32, f: f32) -> f32 {
    let b = 8 + 3 * k;
    let y = value(b);
    if (k == 0) { return y; }
    let amplitude = min(3.0 * f, value(b + 1) * 0.12);
    return y + amplitude * wave(x, value(b + 2));
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let aa = 0.5 / shader.scale;
    let grain = vec3<f32>(value(0), value(1), value(2));
    let f = value(5);
    let n = i32(value(4));
    let column = value(6);
    var out_ = vec4<f32>(0.0);
    for (var k = 0; k < 32; k++) {
        if (k >= n) { break; }
        let h = value(8 + 3 * k + 1);
        if (h < 0.3) { continue; }
        let t = top(k, p.x, f);
        var bottom = min(column, value(8 + 3 * k) + h);
        if (k + 1 < n) { bottom = min(column, top(k + 1, p.x, f)); }
        let inside = smoothstep(t - aa, t + aa, p.y) * (1.0 - smoothstep(bottom - aa, bottom + aa, p.y));
        var alpha = 0.19;
        if (k == 0) { alpha = 0.30; } else if (k % 2 == 0) { alpha = 0.13; }
        out_ = over(out_, grain, alpha * inside);
        // The bed under it.
        if (k + 1 < n) {
            let d = abs(p.y - bottom);
            out_ = over(out_, grain, 0.45 * (1.0 - smoothstep(0.5 * f - aa, 0.5 * f + aa, d)));
        }
    }
    // The surface, lit.
    if (n > 0 && value(9) >= 0.3) {
        let d = abs(p.y - value(8));
        out_ = over(out_, grain, 1.0 - smoothstep(0.75 * f - aa, 0.75 * f + aa, d));
    }
    return out_;
}
