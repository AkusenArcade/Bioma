// The selection's veil (structure/selection.luau): the whole output dimmed,
// the selection cut out of it with the rim's own radius, so the hole and
// the border round it are one shape seen twice. Four rectangles round the
// selection cut it square and left a lit splinter at every corner
// (structure/SelectionSurface.qml).
//
// The numbers:
//   0…3   the selection: x, y, width, height, logical units; 0 wide is none
//   4     its corner radius
//   5…8   the veil's colour, straight alpha

fn shade(p: vec2<f32>) -> vec4<f32> {
    let colour = vec4<f32>(value(5), value(6), value(7), value(8));
    let half = vec2<f32>(value(2), value(3)) * 0.5;
    let centre = vec2<f32>(value(0), value(1)) + half;
    let r = min(value(4), min(half.x, half.y));
    let q = abs(p - centre) - half + vec2<f32>(r, r);
    let d = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
    // Half a physical pixel each side of the edge.
    let aa = 0.5 / shader.scale;
    var outside = smoothstep(-aa, aa, d);
    if (half.x <= 0.0 || half.y <= 0.0) {
        outside = 1.0;
    }
    let a = colour.a * outside;
    return vec4<f32>(colour.rgb * a, a);
}
