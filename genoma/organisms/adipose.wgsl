// The adipose organism's tissue (what organisms/adipose/AdiposeOrganism.qml
// paints on a Canvas, in WGSL for a Genoma shader node): up to four cells,
// one per disk, each a membrane with a drop of fat as full as the disk, the
// nucleus pressed flat against the membrane on the far side.
//
// The numbers:
//   0…3      ink (the membrane, the nucleus)
//   4        how many disks;  5  factor
//   8 + 16k  disk k: centre x, y, radius;  the drop's centre x, y and
//            radius;  the tint r, g, b, a;  the nucleus's centre x, y,
//            angle, depth, breadth

fn colour_at(at: i32) -> vec4<f32> {
    return vec4<f32>(value(at), value(at + 1), value(at + 2), value(at + 3));
}

fn over(dst: vec4<f32>, colour: vec3<f32>, alpha: f32) -> vec4<f32> {
    return vec4<f32>(colour * alpha + dst.rgb * (1.0 - alpha), alpha + dst.a * (1.0 - alpha));
}

fn disc(d: f32, r: f32, aa: f32) -> f32 { return 1.0 - smoothstep(r - aa, r + aa, d); }
fn ring(d: f32, r: f32, w: f32, aa: f32) -> f32 { return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(d - r)); }

fn shade(p: vec2<f32>) -> vec4<f32> {
    let aa = 0.5 / shader.scale;
    let ink = colour_at(0).rgb;
    let f = value(5);
    let n = i32(value(4));
    var out_ = vec4<f32>(0.0);
    for (var k = 0; k < 4; k++) {
        if (k >= n) { break; }
        let b = 8 + 16 * k;
        let c = vec2<f32>(value(b), value(b + 1));
        let r = value(b + 2);
        let d = length(p - c);
        // The membrane.
        out_ = over(out_, ink, 0.03 * disc(d, r, aa));
        out_ = over(out_, ink, 0.22 * ring(d, r, 1.5 * f, aa));
        // The drop of fat, as full as the disk.
        let dc = vec2<f32>(value(b + 3), value(b + 4));
        let dr = value(b + 5);
        let tint = colour_at(b + 6).rgb;
        if (dr > 0.5) {
            let dd = length(p - dc);
            out_ = over(out_, tint, 0.42 * disc(dd, dr, aa));
            out_ = over(out_, tint, 0.9 * ring(dd, dr, 1.2 * f, aa));
        }
        // The nucleus, flattened against the membrane on the far side.
        let nc = vec2<f32>(value(b + 10), value(b + 11));
        let angle = value(b + 12);
        let q = p - nc;
        let local_ = vec2<f32>(q.x * cos(angle) + q.y * sin(angle), -q.x * sin(angle) + q.y * cos(angle));
        let e = length(local_ / vec2<f32>(max(value(b + 13), 0.1), max(value(b + 14), 0.1)));
        let edge = aa / max(min(value(b + 13), value(b + 14)), 0.1);
        out_ = over(out_, ink, 0.55 * (1.0 - smoothstep(1.0 - edge, 1.0 + edge, e)));
    }
    return out_;
}
