import QtQuick
import Quickshell
import Quickshell.Io

// One screen's share of the wallpaper: which part of the picture it shows, and
// how the picture is fitted.
//
// Pure: it is told the image, the mode and the screen, and reads nothing else.
// The shell's own wallpaper draws it, and so does the lock screen — which runs
// as a process of its own and must not start the wallpaper service's library
// scan to find out what it is looking at.
//
//   fill, per_monitor  cover the screen, cropping the overflow
//   fit                contain within the screen, letterboxing
//   span               one picture covering the bounding box of every
//                      screen, each showing its own portion
//
// The item fills its parent, and the parent should clip in span mode.
Item {
    id: root

    property string source: ""
    property string mode: "fill"
    property var screen: null

    // Decode at a fraction of the size shown. A picture that is going to be
    // blurred needs a quarter of its pixels, and the smooth upscale is the
    // first half of the blur.
    property real density: 1

    readonly property alias status: image.status

    anchors.fill: parent

    // Where this screen sits inside the bounding box of all of them, in
    // logical units, like everything else in Bioma: a 3440 × 1440 monitor above
    // a 1920 × 1080 one is a 3440 × 2520 box whatever either one's scale.
    readonly property var span: {
        if (root.mode !== "span" || !root.screen)
            return null;
        const screens = Quickshell.screens;
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const s of screens) {
            minX = Math.min(minX, s.x);
            minY = Math.min(minY, s.y);
            maxX = Math.max(maxX, s.x + s.width);
            maxY = Math.max(maxY, s.y + s.height);
        }
        const target = screens.find(s => s.name === root.screen.name);
        if (!target)
            return null;
        return {
            "totalWidth": maxX - minX,
            "totalHeight": maxY - minY,
            "offsetX": target.x - minX,
            "offsetY": target.y - minY,
            "screenWidth": target.width,
            "screenHeight": target.height
        };
    }

    // ---- Span: only this screen's part is decoded ---------------------------
    //
    // A spanned picture used to be decoded whole on every screen — the
    // bounding box of all of them, ~45 MB at 3440 × 2520 once cropped to
    // cover it — to show a quarter of it on the small one. Qt can decode a
    // region instead: with the fill mode cropping, `sourceSize` scales the
    // picture to cover the box, and `sourceClipRect` is read in the pixels of
    // that scaled picture (measured against PIL, 2026-09-28). What is on
    // screen does not change; what is held in memory does.
    //
    // Placing the region needs the picture's exact size, and Qt does not say
    // what it is without decoding it. `identify -ping` reads the header and
    // nothing else; ImageMagick is already required for the thumbnails. A
    // proportion estimated from a small decode was tried first and put every
    // slice two pixels off centre. Without an answer the whole box is decoded,
    // as before.

    // The picture's size in pixels, 0 until known; `measured` is false while
    // it is being asked and true once there is an answer, whatever it was.
    property int naturalWidth: 0
    property int naturalHeight: 0
    property bool measured: false

    function measure() {
        // Forgotten before it is stopped, so that its stopping is not taken
        // for an answer.
        header.asked = "";
        header.running = false;
        root.naturalWidth = 0;
        root.naturalHeight = 0;
        root.measured = false;
        if (!root.spanning || root.source.length === 0) {
            root.measured = true;
            return;
        }
        header.asked = root.source;
        header.command = ["magick", "identify", "-ping", "-format", "%w %h", root.source + "[0]"];
        header.running = true;
    }

    // `span` is rebuilt whenever a screen moves; only whether there is one
    // changes what has to be measured.
    readonly property bool spanning: root.span !== null

    onSourceChanged: root.measure()
    onSpanningChanged: root.measure()
    Component.onCompleted: root.measure()

    Process {
        id: header
        // Which file the answer is about: one that arrives after the picture
        // changed again is about the old one, and is dropped.
        property string asked: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (header.asked !== root.source)
                    return;
                const parts = this.text.trim().split(/\s+/);
                const w = parseInt(parts[0], 10);
                const h = parseInt(parts[1], 10);
                if (w > 0 && h > 0) {
                    root.naturalWidth = w;
                    root.naturalHeight = h;
                }
            }
        }
        // Answered, or not able to start at all — no ImageMagick — which ends
        // with the process stopped and no exit. Either way the asking is over;
        // later in the frame, so an answer that did come is read first.
        onRunningChanged: if (!header.running) Qt.callLater(() => {
            if (header.asked.length > 0 && header.asked === root.source)
                root.measured = true;
        })
    }

    readonly property real decodeScale: (root.screen?.devicePixelRatio ?? 1) * root.density

    // The box and this screen's region of the picture that covers it, in
    // decoded pixels. The item may be larger than the screen — the backdrop
    // runs past its edges to blur them — so everything is measured in the
    // item's own units per logical unit of screen. The covering size is
    // rounded the way Qt rounds it, or the slice lands a pixel off.
    readonly property var region: {
        if (!root.span || root.naturalWidth <= 0 || root.naturalHeight <= 0)
            return null;
        const d = root.decodeScale;
        const kx = root.width / root.span.screenWidth;
        const ky = root.height / root.span.screenHeight;
        const boxW = Math.round(root.span.totalWidth * kx * d);
        const boxH = Math.round(root.span.totalHeight * ky * d);
        const scale = Math.max(boxW / root.naturalWidth, boxH / root.naturalHeight);
        const coverW = Math.round(root.naturalWidth * scale);
        const coverH = Math.round(root.naturalHeight * scale);
        return {
            "boxW": boxW,
            "boxH": boxH,
            "x": Math.round((coverW - boxW) / 2 + root.span.offsetX * kx * d),
            "y": Math.round((coverH - boxH) / 2 + root.span.offsetY * ky * d),
            "width": Math.round(root.width * d),
            "height": Math.round(root.height * d)
        };
    }

    // Spanning without a region — ImageMagick absent, or the header
    // unreadable — falls back to the whole box, shifted so this screen shows
    // its own portion.
    readonly property bool wholeBox: root.span !== null && root.region === null

    Image {
        id: image

        width: root.wholeBox ? root.width * (root.span.totalWidth / root.span.screenWidth) : root.width
        height: root.wholeBox ? root.height * (root.span.totalHeight / root.span.screenHeight) : root.height
        x: root.wholeBox ? -root.width * (root.span.offsetX / root.span.screenWidth) : 0
        y: root.wholeBox ? -root.height * (root.span.offsetY / root.span.screenHeight) : 0

        // In span mode nothing is loaded while the size is being asked: a
        // whole box decoded first and a region after would be the cost this
        // avoids.
        source: root.source.length === 0 || (root.span && !root.measured) ? "" : "file://" + root.source
        // The box is covered, never stretched: an L of a 3440 × 1440 screen
        // over a 1920 × 1080 one is a 3440 × 2520 box, and a 21:9 photograph
        // forced into that is a photograph squashed by half. Cropped from the
        // centre, the image keeps its proportions and the slices still line up
        // across the seam — each screen cuts its slice out of the same
        // covering picture.
        fillMode: root.mode === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true

        // Decode at the size actually needed. A 6000 px photograph on a
        // 1920 px monitor otherwise costs its full decoded size in memory,
        // once per screen.
        sourceSize.width: root.region ? root.region.boxW : Math.round(width * root.decodeScale)
        sourceSize.height: root.region ? root.region.boxH : Math.round(height * root.decodeScale)
        sourceClipRect: root.region
                        ? Qt.rect(root.region.x, root.region.y, root.region.width, root.region.height)
                        : undefined

        onStatusChanged: {
            if (status === Image.Error && root.source.length > 0)
                console.warn("Wallpaper: cannot load", root.source, "on", root.screen?.name ?? "");
        }
    }
}
