// The rate thread (components/rate_thread.luau, from RateThread.qml): the
// hairline in the line colour, and over it round dashes in the primary
// running along at the rate's speed.
//
// The numbers:
//   0      speed, logical units a second (0 still)
//   1      the stroke's thickness, logical units (2 × factor)
//   2      the hairline's thickness
//   4…7    the hairline's colour
//   8…11   the dashes' colour, straight alpha

fn shade(p: vec2<f32>) -> vec4<f32> {
    let speed = value(0);
    let thick = value(1);
    let hair = value(2);
    let line = vec4<f32>(value(4), value(5), value(6), value(7));
    let dash = vec4<f32>(value(8), value(9), value(10), value(11));
    let mid = shader.size.y * 0.5;
    let aa = 0.5 / shader.scale;
    // The hairline across the middle.
    let h = 1.0 - smoothstep(hair * 0.5 - aa, hair * 0.5 + aa, abs(p.y - mid));
    var out = vec4<f32>(line.rgb * line.a * h, line.a * h);
    // Dashes two strokes long with round caps, four strokes between: Qt's
    // pattern [2, 4], in stroke widths, moving towards the right.
    let len = thick * 2.0;
    let period = thick * 6.0;
    let x = p.x - shader.time * speed;
    let local = x - floor(x / period) * period;
    let d = length(vec2<f32>(max(abs(local - len * 0.5) - len * 0.5, 0.0), p.y - mid)) - thick * 0.5;
    let a = dash.a * (1.0 - smoothstep(-aa, aa, d));
    out = vec4<f32>(dash.rgb * a + out.rgb * (1.0 - a), a + out.a * (1.0 - a));
    return out;
}
