// The growth rings organism's wood (what organisms/rings/RingsOrganism.qml
// paints on a Canvas, in WGSL for a Genoma shader node): one ring a day
// since the system was born, the pith at the centre, today at the bark,
// each as dark as the day was spent at the machine, the trunk's own wobble
// in every ring. Read RingsOrganism.qml for the reasoning.
//
// The numbers:
//   0…3      grain (the primary);  4…7  bare (the text, for days unknown)
//   8        how many bands;  9  factor;  10  the pith's radius
//   16 + 4k  band k: its outer radius, its fill (grain's alpha, or below 0
//            the bare colour's alpha negated), the line round it (alpha,
//            0 for none; below 0 the bare colour's, negated), its width in
//            hundredths with the ring's own phase as the fraction (a part of
//            a turn): every ring wobbles a little on its own as well

fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}

fn trunk(angle: f32) -> f32 {
    return 0.035 * sin(2.0 * angle + 0.7) + 0.020 * sin(3.0 * angle + 2.1) + 0.012 * sin(5.0 * angle + 4.0);
}

fn over(dst: vec4<f32>, colour: vec3<f32>, alpha: f32) -> vec4<f32> {
    return vec4<f32>(colour * alpha + dst.rgb * (1.0 - alpha), alpha + dst.a * (1.0 - alpha));
}

// A ring's radius at an angle: its own small wobble, over the trunk's
// that `e` already takes out.
fn ring(k: i32, angle: f32) -> f32 {
    let own = fract(value(16 + 4 * k + 3)) * 6.2831853;
    return value(16 + 4 * k) * (1.0 + 0.008 * sin(7.0 * angle + own));
}

fn outer(k: i32) -> f32 { return value(16 + 4 * k); }

// The first band whose ring, at this angle, reaches `e`. The rings are in
// order only roughly: each wobbles on its own, so thin neighbours cross, and
// the caller looks a little either side of what this finds.
fn band_at(e: f32, angle: f32, n: i32) -> i32 {
    var lo = 0;
    var hi = n - 1;
    for (var step = 0; step < 12; step++) {
        if (lo >= hi) { break; }
        let mid = (lo + hi) / 2;
        if (ring(mid, angle) < e) { lo = mid + 1; } else { hi = mid; }
    }
    return lo;
}

// Each pixel is the average of the wood under it, as the Canvas's
// antialiasing gave it: once the days are thinner than a pixel, a point
// taken from one day striped the bark with the pixel grid (moiré). Every
// band is weighed by how much of the pixel's radial span it covers, and
// every line within reach is drawn by its coverage, not only the lines of
// the band the centre fell in.
fn shade(p: vec2<f32>) -> vec4<f32> {
    let aa = 0.5 / shader.scale;
    let grain = colour_at(0).rgb;
    let bare = colour_at(4).rgb;
    let n = i32(value(8));
    let f = value(9);
    let pith = value(10);
    let c = shader.size * 0.5;
    let q = p - c;
    let angle = atan2(q.y, q.x);
    let wobble = 1.0 + trunk(angle);
    let dist = length(q);
    // The radius this point is at, as a ring would measure it, and half a
    // pixel in the same measure.
    let e = dist / wobble;
    let h = aa / wobble;
    var out_ = vec4<f32>(0.0);
    if (n <= 0) { return out_; }
    if (e > outer(n - 1) * 1.01 + 2.0 * f) { return out_; }

    // How far a band or a line can be and still touch this pixel: the
    // widest line, half a pixel, and the rings' own wobble either way.
    let slack = 0.02 * e;
    let reach = (f + aa) / wobble + h + slack;
    let first = max(band_at(e - reach, angle, n) - 1, 0);

    // The wood: premultiplied, each band by its share of the pixel.
    var rgb = vec3<f32>(0.0);
    var alpha = 0.0;
    var j = first;
    for (var guard = 0; guard < 256; guard++) {
        if (j >= n) { break; }
        let inner = select(ring(j - 1, angle), pith, j == 0);
        if (inner > e + reach) { break; }
        let share = clamp(min(ring(j, angle), e + h) - max(inner, e - h), 0.0, 2.0 * h) / (2.0 * h);
        if (share > 0.0) {
            let fill = value(16 + 4 * j + 1);
            let a = abs(fill) * share;
            rgb += select(bare, grain, fill >= 0.0) * a;
            alpha += a;
        }
        j++;
    }
    out_ = vec4<f32>(rgb, alpha);

    // The late wood and the cambium: every line within reach, by coverage.
    j = first;
    for (var guard = 0; guard < 256; guard++) {
        if (j >= n) { break; }
        let r = ring(j, angle);
        if (r - slack > e + reach) { break; }
        let line = value(16 + 4 * j + 2);
        if (line != 0.0) {
            let w = floor(value(16 + 4 * j + 3)) / 100.0;
            let d = abs(e - r) * wobble;
            let a = clamp((w * 0.5 + aa - d) / (2.0 * aa), 0.0, 1.0);
            if (a > 0.0) {
                out_ = over(out_, select(bare, grain, line > 0.0), abs(line) * a);
            }
        }
        j++;
    }
    // The pith.
    out_ = over(out_, grain, 0.7 * clamp((pith + aa - dist) / (2.0 * aa), 0.0, 1.0));
    return out_;
}
