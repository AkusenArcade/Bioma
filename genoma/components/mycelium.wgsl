// Mycelium on the wallpaper (components/mycelium.luau): streaks of light,
// a bright head and a tail fading behind it, running out along a branching
// hypha, one of the picture's own outlines and the branches grown off it.
// At every fork the streak goes both ways, so one light becomes many as it
// spreads, as a mould does (Akusen, 2026-11-18: the streaks' look, the
// mycelium's branching).
//
// Every point carries how far from the root it is, along the branches:
// the head is one such distance, and what lies just behind it, on every
// branch at once, is lit. It runs out to the furthest tip, drains off it,
// waits, and runs again. How fast is the clock's rate (`clock_rate`): the
// idle time, which the layer reads.
//
// The numbers:
//   0     how many runs follow
//   1     the furthest distance from the root, logical units
//   2     the tail's length
//   3     the stroke's half-width on the trunk
//   4…7   the colour, straight alpha
//   8     how fast the head runs at rate 1, units a second of the clock
//   9     where along its round it starts, units
//   10    the whole round: out, drained, and the wait
//   12…   the runs: a branch cut into runs of a few points, each led by
//         eight numbers (how many points, the distance from the root at
//         its first and its last, the branch's weight, 1 the trunk and
//         less further out, and its box: left, top, right, bottom), then
//         its points, three numbers each: x, y (logical units from the
//         node's corner) and the distance from the root. A pixel far from
//         a run's box, or a run the streak is not on, skips it whole: the
//         cost is the runs, not the points.

fn point(i: i32) -> vec3<f32> {
    return vec3<f32>(value(i), value(i + 1), value(i + 2));
}

fn shade(p: vec2<f32>) -> vec4<f32> {
    let runs = i32(value(0));
    let furthest = value(1);
    let tail = max(value(2), 1.0);
    let width = max(value(3), 0.3);
    if (runs < 1 || furthest <= 0.0) {
        return vec4<f32>(0.0);
    }
    let head = (shader.time * value(8) + value(9)) % max(value(10), 1.0);
    if (head > furthest + tail) {
        return vec4<f32>(0.0);
    }
    let start = head - tail;
    var light = 0.0;
    var at = 12;
    for (var r = 0; r < runs; r = r + 1) {
        let count = i32(value(at));
        let near = value(at + 1);
        let far = value(at + 2);
        let weight = value(at + 3);
        let box = vec4<f32>(value(at + 4), value(at + 5), value(at + 6), value(at + 7));
        let first = at + 8;
        at = first + count * 3;
        if (far < start || near > head) {
            continue;
        }
        let thin = width * sqrt(weight);
        // Past two and a half halos the light is under a thousandth.
        let reach = thin * 12.5;
        if (p.x < box.x - reach || p.y < box.y - reach || p.x > box.z + reach || p.y > box.w + reach) {
            continue;
        }
        for (var i = 0; i < count - 1; i = i + 1) {
            let a = point(first + i * 3);
            let b = point(first + i * 3 + 3);
            if (b.z < start || a.z > head) {
                continue;
            }
            let seg = b.xy - a.xy;
            let len = max(b.z - a.z, 1e-4);
            // The nearest point of the lit part of this segment.
            var t = clamp(dot(p - a.xy, seg) / max(dot(seg, seg), 1e-6), 0.0, 1.0);
            t = clamp(t, (max(start, a.z) - a.z) / len, (min(head, b.z) - a.z) / len);
            let along = a.z + t * len;
            let d = length(p - (a.xy + seg * t));
            // 0 at the tail's end, 1 at the head.
            let w = clamp((along - start) / tail, 0.0, 1.0);
            let core = exp(-pow(d / thin, 2.0));
            let halo = exp(-pow(d / (thin * 5.0), 2.0)) * 0.35;
            light = max(light, weight * pow(w, 1.5) * (core + halo));
        }
    }
    let alpha = clamp(value(7) * light, 0.0, 1.0);
    return vec4<f32>(vec3<f32>(value(4), value(5), value(6)) * alpha, alpha);
}
