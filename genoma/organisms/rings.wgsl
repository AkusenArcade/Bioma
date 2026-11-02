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

fn shade(p: vec2<f32>) -> vec4<f32> {
    let aa = 0.5 / shader.scale;
    let grain = colour_at(0).rgb;
    let bare = colour_at(4).rgb;
    let n = i32(value(8));
    let f = value(9);
    let c = shader.size * 0.5;
    let q = p - c;
    let angle = atan2(q.y, q.x);
    let wobble = 1.0 + trunk(angle);
    let dist = length(q);
    // The radius this point is at, as a ring would measure it.
    let e = dist / wobble;
    var out_ = vec4<f32>(0.0);
    if (n <= 0) { return out_; }
    if (e > outer(n - 1) + 2.0 * f) { return out_; }

    // The band it is in: the first whose outer radius reaches it.
    var lo = 0;
    var hi = n - 1;
    for (var step = 0; step < 12; step++) {
        if (lo >= hi) { break; }
        let mid = (lo + hi) / 2;
        if (ring(mid, angle) < e) { lo = mid + 1; } else { hi = mid; }
    }
    let k = lo;
    let inside = 1.0 - smoothstep(ring(n - 1, angle) - aa, ring(n - 1, angle) + aa, e);
    let fill = value(16 + 4 * k + 1);
    if (fill >= 0.0) {
        out_ = over(out_, grain, fill * inside);
    } else {
        out_ = over(out_, bare, -fill * inside);
    }
    // The lines round the bands either side of it.
    for (var j = max(k - 1, 0); j <= min(k + 1, n - 1); j++) {
        let line = value(16 + 4 * j + 2);
        if (line != 0.0) {
            let w = floor(value(16 + 4 * j + 3)) / 100.0;
            let d = abs(e - ring(j, angle)) * wobble;
            let a = 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, d);
            if (line > 0.0) { out_ = over(out_, grain, line * a); } else { out_ = over(out_, bare, -line * a); }
        }
    }
    // The pith.
    let pith = value(10);
    out_ = over(out_, grain, 0.7 * (1.0 - smoothstep(pith - aa, pith + aa, dist)));
    return out_;
}
