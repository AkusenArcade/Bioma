import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// One glyph from `assets/icons`, in a colour or in the light gradient.
//
// The sources are written once, at 24 with a 20 live area, and they paint
// themselves in `currentColor` — which Qt renders as black, since there is no
// cascade to inherit from. So the file is read as text and the colour is
// substituted at load: a theme change repaints the icons with everything else,
// and a gradient icon gets a real gradient rather than a tinted bitmap.
//
// Icons say *what* something is, never how hard it is working: the gradient is
// for a header, an active control or the only content of a cell, muted text for
// anything inactive or a fallback, and never a state colour.
Item {
    id: root

    required property string name

    property color colour: Theme.textMuted
    property bool gradient: false
    property color gradientBase: Theme.primary

    implicitWidth: 24
    implicitHeight: 24

    FileView {
        id: file
        path: `${Quickshell.shellDir}/assets/icons/${root.name}.svg`
        blockLoading: true
        printErrors: true
    }

    // Qt writes a colour as #AARRGGBB, which SVG does not understand — the
    // alpha lands where the red belongs and the glyph silently disappears. The
    // channels go in as `rgb()` and the alpha is applied to the item instead.
    function rgb(colour) {
        return `rgb(${Math.round(colour.r * 255)},${Math.round(colour.g * 255)},${Math.round(colour.b * 255)})`;
    }

    // The gradient is declared in the file's own coordinate space: the same
    // 165°, from above and slightly from the left, as every other surface.
    readonly property string gradientDefs: {
        const radians = Theme.gradientAngle * Math.PI / 180;
        const dx = Math.sin(radians) / 2;
        const dy = -Math.cos(radians) / 2;
        return `<defs><linearGradient id="biomaGradient" x1="${0.5 - dx}" y1="${0.5 - dy}" x2="${0.5 + dx}" y2="${0.5 + dy}">`
             + `<stop offset="0" stop-color="${root.rgb(Theme.gradientTop(root.gradientBase))}"/>`
             + `<stop offset="1" stop-color="${root.rgb(Theme.gradientBottom(root.gradientBase))}"/>`
             + `</linearGradient></defs>`;
    }

    readonly property string painted: {
        const source = file.text();
        if (!source)
            return "";
        const paint = root.gradient ? "url(#biomaGradient)" : root.rgb(root.colour);
        const body = source.replace(/currentColor/g, paint);
        return root.gradient
               ? body.replace(/(<svg[^>]*>)/, `$1${root.gradientDefs}`)
               : body;
    }

    Image {
        anchors.fill: parent
        // The colour's alpha, which could not travel inside the file.
        opacity: root.gradient ? 1 : root.colour.a
        source: root.painted ? `data:image/svg+xml;utf8,${encodeURIComponent(root.painted)}` : ""
        // Rendered at device resolution: a glyph rasterised at logical size and
        // scaled up is exactly the smearing the stroke weights are chosen to
        // avoid.
        sourceSize.width: Math.round(root.width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.height * Screen.devicePixelRatio)
        smooth: true
    }
}
