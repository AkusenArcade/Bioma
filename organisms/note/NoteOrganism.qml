import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.core
import qs.components

// A Markdown file on the desktop, read and never written.
//
// The text lives where it is written — an Obsidian vault, a repository — and
// this shows it: edit the file anywhere and the note changes here, watched
// rather than polled. Writing inside the organism was considered and refused
// (Akusen, 2026-10-04): an organism takes no input, and a second, poorer
// editor of a file that already has a good one is not a feature.
//
// The Markdown is read here, line by line, into blocks drawn in the shell's
// own terms — a task is a ring or a lit disc, not a font's box — rather than
// handed to Qt's renderer, which would draw it in a third voice.
//
// See docs/design/ORGANISMS.md §06.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})

    readonly property real factor: root.metrics.factor

    // ---- The file -----------------------------------------------------------------

    readonly property string home: Quickshell.env("HOME")
    readonly property string path: {
        const file = (root.entry.file || "").trim();
        return file.startsWith("~") ? root.home + file.slice(1) : file;
    }

    property bool readable: false
    property string source: ""
    property double edited: 0

    readonly property bool present: root.readable

    // Absent, it is drawn only while being placed, and then blank: the
    // file's name if it has one, and what is wrong in place of the text.
    readonly property string reason: (root.entry.file || "").trim().length === 0
        ? "No file chosen. Choose one under Settings → Organisms → Note → File."
        : "This file cannot be read."

    FileView {
        id: file

        path: root.path
        watchChanges: true
        printErrors: false

        onLoaded: {
            root.readable = true;
            root.source = file.text();
            stat.running = true;
        }
        onLoadFailed: root.readable = false
        onFileChanged: reload()
    }

    // When the file last changed, for the header. FileView does not say.
    Process {
        id: stat
        command: ["stat", "-c", "%Y", root.path]
        stdout: StdioCollector {
            onStreamFinished: {
                const seconds = parseInt(text.trim(), 10);
                if (seconds > 0)
                    root.edited = seconds * 1000;
            }
        }
    }

    // Relative times drift: the header is read again once a minute.
    property double now: Date.now()
    Timer {
        interval: 60 * 1000
        repeat: true
        running: root.readable
        onTriggered: root.now = Date.now()
    }

    readonly property string when: {
        if (root.edited <= 0)
            return "";
        const minutes = Math.floor(Math.max(0, root.now - root.edited) / 60000);
        if (minutes < 1) return "EDITED JUST NOW";
        if (minutes < 60) return `EDITED ${minutes} MIN AGO`;
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return `EDITED ${hours} H AGO`;
        return `EDITED ${Math.floor(hours / 24)} D AGO`;
    }

    // ---- Reading it ----------------------------------------------------------------

    // Never more than this is parsed: a megabyte of Markdown is read only as
    // far as a panel can show, and the rest is a count.
    readonly property int readAtMost: 400

    readonly property var parsed: root.parse(root.source)
    readonly property string title: root.readable && root.parsed.title.length > 0 ? root.parsed.title
        : root.path.length > 0 ? root.path.split("/").pop().replace(/\.md$/i, "") : "Note"

    function escaped(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Inline marks, as rich text: bold, italic, code in the technical voice,
    // links and wiki links reduced to their words — there is nothing to press.
    function inline(text) {
        let out = root.escaped(text);
        out = out.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2")
                 .replace(/\[\[([^\]]+)\]\]/g, "$1")
                 .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1");
        const code = `<span style="font-family:'${Typography.technical}'; font-size:${root.metrics.fontMeta}px;">$1</span>`;
        out = out.replace(/`([^`]+)`/g, code)
                 .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
                 .replace(/__([^_]+)__/g, "<b>$1</b>")
                 .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
                 .replace(/(^|[^\w])_([^_\s][^_]*)_/g, "$1<i>$2</i>")
                 .replace(/~~([^~]+)~~/g, "<s>$1</s>");
        return out;
    }

    // [{ "kind": "heading" | "text" | "item" | "quote" | "code" | "rule",
    //    "text", "mark": "node" | "open" | "done", "depth", "lines" }]
    function parse(source) {
        const lines = source.split("\n").slice(0, root.readAtMost);
        const blocks = [];
        let title = "";
        let i = 0;

        // Obsidian's properties are not the note.
        if (lines[0] !== undefined && lines[0].trim() === "---") {
            const end = lines.indexOf("---", 1);
            if (end > 0)
                i = end + 1;
        }

        let paragraph = [];
        let firstLine = 0;
        const flush = () => {
            if (paragraph.length > 0)
                blocks.push({ "kind": "text", "text": root.inline(paragraph.join(" ")), "lines": paragraph.length });
            paragraph = [];
        };

        for (; i < lines.length; i++) {
            const line = lines[i].replace(/\s+$/, "");
            const trimmed = line.trim();

            if (trimmed.length === 0) {
                flush();
                continue;
            }

            if (trimmed.startsWith("```")) {
                flush();
                const code = [];
                for (i++; i < lines.length && !lines[i].trim().startsWith("```"); i++)
                    code.push(root.escaped(lines[i]));
                blocks.push({ "kind": "code", "text": code.join("<br>"), "lines": code.length + 2 });
                continue;
            }

            const heading = /^(#{1,6})\s+(.*)$/.exec(trimmed);
            if (heading) {
                flush();
                if (heading[1].length === 1 && title.length === 0 && blocks.length === 0) {
                    title = heading[2];
                    continue;
                }
                blocks.push({ "kind": "heading", "text": root.inline(heading[2]),
                              "depth": heading[1].length, "lines": 1 });
                continue;
            }

            if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
                flush();
                blocks.push({ "kind": "rule", "lines": 1 });
                continue;
            }

            const item = /^(\s*)[-*+]\s+(\[( |x|X)\]\s+)?(.*)$/.exec(line)
                      || /^(\s*)\d+[.)]\s+(\[( |x|X)\]\s+)?(.*)$/.exec(line);
            if (item) {
                flush();
                const depth = Math.floor(item[1].replace(/\t/g, "    ").length / 2);
                const mark = item[2] ? (item[3] === " " ? "open" : "done") : "node";
                blocks.push({ "kind": "item", "text": root.inline(item[4]), "mark": mark,
                              "depth": Math.min(depth, 4), "lines": 1 });
                continue;
            }

            if (trimmed.startsWith(">")) {
                flush();
                blocks.push({ "kind": "quote", "text": root.inline(trimmed.replace(/^>\s?/, "")), "lines": 1 });
                continue;
            }

            paragraph.push(trimmed);
        }
        flush();

        const total = source.split("\n").length;
        return { "title": title, "blocks": blocks, "unread": Math.max(0, total - lines.length) };
    }

    // ---- How tall ---------------------------------------------------------------------

    // The panel is 220, 300 or 460 tall; the content is that less the padding.
    readonly property real panelHeight: {
        const height = root.entry.height || "medium";
        return (height === "short" ? 220 : height === "tall" ? 460 : 300) * root.factor;
    }

    implicitWidth: 320 * root.factor
    implicitHeight: root.panelHeight - 40 * root.factor

    readonly property font technical: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontMeta,
        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
    })

    // ---- The header ----------------------------------------------------------------------

    Item {
        id: header

        width: parent.width
        height: 22 * root.factor

        Text {
            anchors.left: parent.left
            anchors.right: whenText.left
            anchors.rightMargin: 12 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: Math.round(15 * root.factor)
            font.weight: Font.Bold
        }

        Text {
            id: whenText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.readable ? root.when : ""
            color: Theme.textFaint
            font: root.technical
        }
    }

    // ---- The text --------------------------------------------------------------------------

    Text {
        visible: !root.readable
        y: header.height + 12 * root.factor
        width: parent.width
        text: root.reason
        wrapMode: Text.Wrap
        color: Theme.textFaint
        font.family: Typography.expressive
        font.pixelSize: Math.round(14 * root.factor)
        font.italic: true
    }

    Item {
        id: page

        visible: root.readable

        y: header.height + 12 * root.factor
        width: parent.width
        height: parent.height - y

        // Cross-faded when the file changes: the panel stays where it is,
        // the text goes and comes back changed.
        property var shown: ({ "title": "", "blocks": [], "unread": 0 })
        property bool primed: false

        Connections {
            target: root
            function onParsedChanged() {
                if (!page.primed) {
                    page.shown = root.parsed;
                    page.primed = true;
                    return;
                }
                swap.restart();
            }
        }

        SequentialAnimation {
            id: swap
            NumberAnimation { target: page; property: "opacity"; to: 0; duration: Timing.contentFade }
            ScriptAction { script: page.shown = root.parsed }
            NumberAnimation { target: page; property: "opacity"; to: 1; duration: Timing.contentFade }
        }

        Component.onCompleted: {
            page.shown = root.parsed;
            page.primed = true;
        }

        readonly property bool overflowing: blocks.height > page.height

        // How many of the file's lines are below the fold.
        readonly property int hidden: {
            let count = page.shown.unread;
            for (let i = 0; i < blockRepeater.count; i++) {
                const item = blockRepeater.itemAt(i);
                if (item && item.y + item.height > page.height)
                    count += item.lines;
            }
            return count;
        }

        // Longer than the panel, the text runs to the foot and fades out over
        // the last 36 px — nothing scrolls, there is no hand to scroll it.
        Item {
            id: textLayer
            anchors.fill: parent
            clip: true

            layer.enabled: page.overflowing
            layer.effect: OpacityMask {
                maskSource: fade
            }

            Column {
                id: blocks
                width: parent.width
                spacing: 6 * root.factor

                Text {
                    visible: page.shown.blocks.length === 0
                    text: "Nothing written yet."
                    color: Theme.textFaint
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(14 * root.factor)
                    font.italic: true
                }

                Repeater {
                    id: blockRepeater
                    model: page.shown.blocks

                    delegate: Item {
                        id: block

                        required property var modelData
                        required property int index
                        readonly property int lines: block.modelData.lines || 1
                        readonly property string kind: block.modelData.kind
                        readonly property real indent: (block.modelData.depth || 0) * 14 * root.factor
                        readonly property real lead: block.kind === "heading" && block.index > 0 ? 4 * root.factor : 0

                        width: blocks.width
                        height: block.lead + (block.kind === "rule" ? 9 * root.factor
                                : block.kind === "code" ? codeText.implicitHeight + 16 * root.factor
                                : words.implicitHeight)

                        // A rule: a line in `line`.
                        Rectangle {
                            visible: block.kind === "rule"
                            y: 4 * root.factor
                            width: parent.width
                            height: Metrics.crisp(1, Screen.devicePixelRatio)
                            color: Theme.line
                        }

                        // A code block: a well, the technical voice, no wrapping.
                        Well {
                            visible: block.kind === "code"
                            metrics: root.metrics
                            width: parent.width
                            height: parent.height
                            Text {
                                id: codeText
                                x: 10 * root.factor
                                y: 8 * root.factor
                                width: parent.width - 20 * root.factor
                                text: block.kind === "code" ? block.modelData.text : ""
                                textFormat: Text.StyledText
                                elide: Text.ElideRight
                                color: Theme.textMuted
                                font: Qt.font({ "family": Typography.technical,
                                                "pixelSize": root.metrics.fontMeta })
                            }
                        }

                        // The mark of an item: a node, an open ring, a lit disc.
                        Item {
                            visible: block.kind === "item"
                            x: block.indent
                            width: 12 * root.factor
                            height: 18 * root.factor

                            Rectangle {
                                visible: block.modelData.mark === "node"
                                anchors.centerIn: parent
                                width: 4 * root.factor
                                height: width
                                radius: width / 2
                                color: Theme.node
                            }

                            Rectangle {
                                visible: block.modelData.mark === "open"
                                anchors.centerIn: parent
                                width: 11 * root.factor
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: Metrics.rim(Screen.devicePixelRatio)
                                border.color: Theme.line
                                antialiasing: true
                            }

                            Disc {
                                visible: block.modelData.mark === "done"
                                anchors.centerIn: parent
                                width: 12 * root.factor
                                height: width
                            }
                        }

                        // A quote's bar.
                        Rectangle {
                            visible: block.kind === "quote"
                            y: block.lead
                            width: 2 * root.factor
                            height: words.implicitHeight
                            color: Theme.line
                        }

                        Text {
                            id: words

                            visible: block.kind !== "rule" && block.kind !== "code"
                            y: block.lead
                            x: block.kind === "item" ? block.indent + 22 * root.factor
                             : block.kind === "quote" ? 12 * root.factor : 0
                            width: parent.width - x
                            text: block.kind === "rule" || block.kind === "code" ? "" : block.modelData.text
                            textFormat: Text.RichText
                            wrapMode: Text.Wrap
                            lineHeight: 0.95
                            color: block.kind === "quote" || (block.kind === "heading" && block.modelData.depth > 2)
                                   || block.modelData.mark === "done" ? Theme.textMuted : Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: Math.round(14 * root.factor)
                            font.weight: block.kind === "heading" ? Font.Bold : Font.Normal
                            font.italic: block.kind === "quote"
                        }
                    }
                }
            }
        }

        // The fade's shape: whole down to the last 36 px, then nothing.
        Rectangle {
            id: fade
            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                GradientStop { position: 0; color: "white" }
                GradientStop { position: Math.max(0, 1 - 36 * root.factor / Math.max(1, page.height)); color: "white" }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        // How much is not shown, over the fade.
        Text {
            visible: page.overflowing && page.hidden > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: `${page.hidden} MORE ${page.hidden === 1 ? "LINE" : "LINES"}`
            color: Theme.textFaint
            font: root.technical
        }
    }
}
