// The photoperiod organism's sky (what organisms/photoperiod/
// PhotoperiodOrganism.qml paints on a Canvas, in WGSL for a Genoma shader
// node, which has no canvas): the horizon, the moon's path, the sun's path
// with the light still to come filled under it, the moon with its phase,
// and the sun. The paths come sampled into columns across the picture,
// their heights in logical units; a column the path does not reach is
// below -1000.
//
// The numbers:
//   0        horizon     its height, from the top
//   1, 2     the sun now, x and y;  3  whether it is up
//   4, 5     the moon now, x and y; 6  its strength (1 up, 0.45 down)
//   7        the moon's phase (0 new, 0.5 full)
//   8…11     sunlight;  12…15  moonlight;  16…19  ground
//   20       margin;  21  hairline;  22  factor;  23  1 north of the
//            equator, -1 south
//   24…79    the sun's path, 56 columns
//   80…126   the moon's path, 47 columns
//   127      1 when the day runs left to right, 0 right to left

const NS: i32 = 56;
const NM: i32 = 47;

fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}

fn column_x(k: i32, n: i32) -> f32 {
    let m = value(20);
    return m + f32(k) * (shader.size.x - 2.0 * m) / f32(n - 1);
}

fn segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// The distance from p to a sampled path, looking only at the columns near.
fn path(p: vec2<f32>, base: i32, n: i32) -> f32 {
    let m = value(20);
    let step = (shader.size.x - 2.0 * m) / f32(n - 1);
    let k = i32(floor((p.x - m) / step));
    var best = 1e4;
    for (var j = k - 1; j <= k + 1; j++) {
        if (j >= 0 && j + 1 < n) {
            let ya = value(base + j);
            let yb = value(base + j + 1);
            if (ya > -1000.0 && yb > -1000.0) {
                best = min(best, segment(p, vec2<f32>(column_x(j, n), ya), vec2<f32>(column_x(j + 1, n), yb)));
            }
        }
    }
    return best;
}

// The path's height at x, or below -1000 where it is not.
fn height(x: f32, base: i32, n: i32) -> f32 {
    let m = value(20);
    let step = (shader.size.x - 2.0 * m) / f32(n - 1);
    let at = (x - m) / step;
    let k = i32(floor(at));
    if (k < 0 || k + 1 >= n) { return -2000.0; }
    let ya = value(base + k);
    let yb = value(base + k + 1);
    if (ya <= -1000.0 || yb <= -1000.0) { return -2000.0; }
    return mix(ya, yb, at - f32(k));
}

fn line(d: f32, width: f32, aa: f32) -> f32 {
    return 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, d);
}

fn over(dst: vec4<f32>, colour: vec3<f32>, alpha: f32) -> vec4<f32> {
    return vec4<f32>(colour * alpha + dst.rgb * (1.0 - alpha), alpha + dst.a * (1.0 - alpha));
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let aa = 0.5 / shader.scale;
    let f = value(22);
    let horizon = value(0);
    let sunlight = colour_at(8).rgb;
    let moonlight = colour_at(12).rgb;
    let ground = colour_at(16).rgb;
    var out_ = vec4<f32>(0.0);

    // The horizon.
    out_ = over(out_, ground, line(abs(p.y - horizon), value(21), aa));

    // The moon's path, faint, where it is up.
    out_ = over(out_, moonlight, 0.22 * line(path(p, 80, NM), 1.0 * f, aa));

    // The light still to come, under the sun's path ahead of now.
    let forward = value(127) > 0.5;
    let ahead = select(p.x <= value(1), p.x >= value(1), forward);
    let sky = height(p.x, 24, NS);
    if (ahead && sky > -1000.0 && sky < horizon && p.y >= sky && p.y <= horizon) {
        out_ = over(out_, sunlight, 0.10);
    }

    // The sun's path: under the ground faint, the part gone dimmer, the
    // part to come in full.
    let d = path(p, 24, NS);
    if (p.y > horizon) {
        out_ = over(out_, sunlight, 0.18 * line(d, 1.0 * f, aa));
    } else {
        out_ = over(out_, sunlight, select(0.38, 1.0, ahead) * line(d, 1.5 * f, aa));
    }

    // The moon, its lit part by its phase.
    let mc = vec2<f32>(value(4), value(5));
    let dim = value(6);
    let r = 7.0 * f;
    let dm = p - mc;
    let dist = length(dm);
    out_ = over(out_, moonlight, 0.10 * dim * (1.0 - smoothstep(r - aa, r + aa, dist)));
    out_ = over(out_, moonlight, 0.35 * dim * line(abs(dist - r), max(1.0, f), aa));
    let phase = value(7);
    let side = select(-1.0, 1.0, phase < 0.5) * value(23);
    let squeeze = cos(2.0 * 3.14159265 * phase);
    let w0 = sqrt(max(r * r - dm.y * dm.y, 0.0));
    let u = side * dm.x;
    if (abs(dm.y) < r && u <= w0 && u >= w0 * squeeze) {
        out_ = over(out_, moonlight, 0.9 * dim);
    }

    // The sun: a disc when it is up, a ring when it is not.
    let ds = length(p - vec2<f32>(value(1), value(2)));
    let sr = 6.0 * f;
    if (value(3) > 0.5) {
        out_ = over(out_, sunlight, 1.0 - smoothstep(sr - aa, sr + aa, ds));
    } else {
        out_ = over(out_, sunlight, 0.5 * line(abs(ds - sr), 1.2 * f, aa));
    }
    return out_;
}
