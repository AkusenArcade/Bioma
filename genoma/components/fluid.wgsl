// The band as a fluid (components/fluid.frag, in WGSL for a Genoma shader
// node). Read fluid.frag's comment for what each form means; this is the
// same field, line for line, and a change to one is carried to the other.
//
// The numbers, as components/fluid.luau binds them:
//   0…47   the bands, 0 to 1, left wing then right, as the drops stand
//   48     count     drops in the row, both wings together
//   49     pitch     from one drop's centre to the next
//   50     first     the first drop's centre, from the left
//   51     form      0 plasma, 1 vesicles, 2 eardrum
//   52     thread    the silent dot's radius
//   53     drop      a drop's radius at full scale
//   54     blend     how far apart two vesicles still melt together
//   56…59  upper     the gradient over the band's height, top to bottom
//   60…63  lower
//   64…67  core      what the thick of a drop turns towards
//
// Differences from the GLSL that are not translation: derivatives here are
// per physical pixel, so the membrane's slope is scaled back to logical
// units; the half-pixel edges are half a physical pixel; and no branch that
// depends on the pixel comes before a derivative, which WGSL forbids.

fn band(i: i32) -> f32 { return clamp(value(i), 0.0, 1.0); }
fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    if (k <= 0.0) {
        return min(a, b);
    }
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn eardrum(p: vec2<f32>, mid: f32, n: i32) -> vec4<f32> {
    let extent = shader.size;
    let pitch = value(49);
    let first = value(50);
    let thread = value(52);
    let aa = 0.5 / shader.scale;
    let width_ = extent.x;
    let centre = width_ * 0.5;
    let reach = mid - thread - 1.0;
    let sigma = pitch;
    let half_ = max(f32(n / 2) - 1.0, 1.0);
    let time = shader.time;

    var shake = 0.0;
    var swing = 0.0;
    var weight = 0.0;
    var at_umbo = 0.0;
    var umbo_weight = 0.0;
    for (var i = 0; i < 48; i++) {
        if (i >= n) {
            break;
        }
        let v = band(i);
        let x = first + f32(i) * pitch;
        // 0 at the centre, the lowest band of its channel; 1 at the end.
        var rank: f32;
        if (i < n / 2) {
            rank = f32(n / 2 - 1 - i) / half_;
        } else {
            rank = f32(i - n / 2) / half_;
        }
        let wave = 6.2831853 / mix(width_ * 0.5, pitch * 3.0, rank);
        let rate = 6.2831853 * mix(0.9, 6.0, rank);
        let g = exp(-pow((p.x - x) / sigma, 2.0));
        shake += v * g * sin(wave * abs(p.x - centre) - rate * time);
        swing += v * g;
        weight += g;
        let u = exp(-pow((centre - x) / sigma, 2.0));
        at_umbo += v * u * sin(-rate * time);
        umbo_weight += u;
    }

    // Held at both ends by the ring.
    let hold = smoothstep(0.0, pitch * 2.0, p.x) * smoothstep(0.0, pitch * 2.0, width_ - p.x);
    let y = mid + reach * hold * shake / max(weight, 1e-3);
    let spread = reach * hold * swing / max(weight, 1e-3);
    let umbo_y = mid + reach * at_umbo / max(umbo_weight, 1e-3);

    let upper = colour_at(56);
    let lower = colour_at(60);
    let core = colour_at(64);
    let light = mix(upper.rgb, lower.rgb, clamp(p.y / extent.y, 0.0, 1.0));

    // The membrane: a line of even thickness whatever its slope.
    let slope = dpdx(y) * shader.scale;
    let off = abs(p.y - y) / sqrt(1.0 + slope * slope);
    let line = 1.0 - smoothstep(thread - aa, thread + aa, off);

    // How far it swings, faint, as a vibrating string blurs.
    let env = (1.0 - smoothstep(spread - aa, spread + aa, abs(p.y - mid))) * 0.16;

    // The umbo.
    let node = 1.0 - smoothstep(thread * 1.9 - aa, thread * 1.9 + aa, length(p - vec2<f32>(centre, umbo_y)));

    let a = max(max(line * 0.95, env), node);
    let colour = mix(light, core.rgb, 0.35 * max(line, node));
    return vec4<f32>(colour * a, a);
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let extent = shader.size;
    let mid = extent.y * 0.5;
    let n = i32(value(48) + 0.5);
    let pitch = value(49);
    let first = value(50);
    let form = value(51);
    let thread = value(52);
    let drop = value(53);
    let blend = value(54);
    let aa = 0.5 / shader.scale;

    if (form > 1.5) {
        return eardrum(p, mid, n);
    }

    var d = 1e5;
    if (form < 0.5) {
        // Plasma. The blend between two neighbours is the radius of the
        // smaller: a quiet drop beside a loud one barely touches it, two loud
        // ones are one body, and the dots of silence stay apart.
        var previous = 0.0;
        for (var i = 0; i < 48; i++) {
            if (i >= n) {
                break;
            }
            let r = mix(thread, drop, band(i));
            let own = length(p - vec2<f32>(first + f32(i) * pitch, mid)) - r;
            d = smin(d, own, min(previous, r));
            previous = r;
        }
    } else {
        // Vesicles. A drop grows from the dot's size as it divides, and its
        // two halves stop short of the band's edge.
        let reach = mid - drop - 1.0;
        for (var i = 0; i < 48; i++) {
            if (i >= n) {
                break;
            }
            let near = abs(p.x - (first + f32(i) * pitch));
            if (near <= drop + blend) {
                let v = band(i);
                let r = mix(thread, drop, sqrt(v));
                let off = v * reach;
                let up = length(vec2<f32>(near, p.y - (mid - off))) - r;
                let down = length(vec2<f32>(near, p.y - (mid + off))) - r;
                d = smin(d, smin(up, down, blend), blend);
            }
        }
    }

    // Before any branch on the pixel: derivatives need the whole quad.
    let slope = vec2<f32>(dpdx(d), dpdy(d));
    let inside = 1.0 - smoothstep(-aa, aa, d);
    if (inside <= 0.0) {
        return vec4<f32>(0.0);
    }

    let depth = max(-d, 0.0);
    let normal = slope / max(length(slope), 1e-4);

    // Light passes through a drop: the edge and the necks let the glass behind
    // show, the thick of it is denser and lighter, as the lava lamp's wax is.
    let upper = colour_at(56);
    let lower = colour_at(60);
    let core = colour_at(64);
    let thick = smoothstep(0.0, 0.75 * drop, depth);
    var colour = mix(upper.rgb, lower.rgb, clamp(p.y / extent.y, 0.0, 1.0));
    colour = mix(colour, core.rgb, 0.16 * thick);
    var body = mix(0.66, 0.96, thick);

    // The rim: a band just inside the edge, brightest where the surface faces
    // up, as the lit border runs along every cell's top.
    let rim = clamp(0.3 * drop, 1.0, 3.5);
    let edge = 1.0 - smoothstep(0.0, rim, depth);
    let lit = edge * (0.25 + 0.75 * max(0.0, -normal.y));
    colour = mix(colour, core.rgb, 0.45 * lit);
    body = min(1.0, body + 0.3 * lit);

    let a = inside * body;
    return vec4<f32>(colour * a, a);
}
