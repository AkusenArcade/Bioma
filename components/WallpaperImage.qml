import QtQuick
import Quickshell

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

    Image {
        id: image

        // In span mode the item is the bounding box of every monitor, shifted
        // so this screen shows its own portion. In every other mode it simply
        // fills the screen.
        width: root.span ? root.width * (root.span.totalWidth / root.span.screenWidth) : root.width
        height: root.span ? root.height * (root.span.totalHeight / root.span.screenHeight) : root.height
        x: root.span ? -root.width * (root.span.offsetX / root.span.screenWidth) : 0
        y: root.span ? -root.height * (root.span.offsetY / root.span.screenHeight) : 0

        source: root.source.length > 0 ? "file://" + root.source : ""
        // The box is covered, never stretched: an L of a 3440 × 1440 screen
        // over a 1920 × 1080 one is a 3440 × 2520 box, and a 21:9 photograph
        // forced into that is a photograph squashed by half. Cropped from the
        // centre, the image keeps its proportions and the slices still line up
        // across the seam.
        fillMode: root.mode === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true

        // Decode at the size actually needed. A 6000 px photograph on a
        // 1920 px monitor otherwise costs its full decoded size in memory,
        // once per screen.
        sourceSize.width: Math.round(width * (root.screen?.devicePixelRatio ?? 1) * root.density)
        sourceSize.height: Math.round(height * (root.screen?.devicePixelRatio ?? 1) * root.density)

        onStatusChanged: {
            if (status === Image.Error && root.source.length > 0)
                console.warn("Wallpaper: cannot load", root.source, "on", root.screen?.name ?? "");
        }
    }
}
