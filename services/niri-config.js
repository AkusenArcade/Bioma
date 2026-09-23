.pragma library

// Reading and rewriting niri's configuration as text: its `binds` block and
// its `output` sections, the two things Bioma's settings write.
//
// The configuration belongs to niri and to whoever wrote it, so it is never
// parsed into a model and printed back: that would lose every comment, every
// blank line and every choice of spelling in a file Bioma does not own. It is
// scanned for positions instead — where each bind's key is, where each bind
// starts and ends, where a block closes — and an edit replaces exactly that
// span of text and nothing around it.
//
// This file is plain JavaScript with no QML in it, so the scanner can be run
// and tested outside the shell.
//
// What niri itself enforces, checked against 26.04:
//   - one `binds` node per file; a second one is a parse error,
//   - the same key twice in one block is an error, compared without case and
//     without modifier order (`Shift+Mod+x` is `Mod+Shift+X`),
//   - across files it is not: includes are positional, and a bind written
//     later overrides the same key written earlier,
//   - `output` sections are not merged at all: two sections naming one
//     output are both kept, so a position is written into every one of them.

// ---- Tokens ----------------------------------------------------------------
//
// Enough of KDL (v1 and v2) to find nodes and their extents: identifiers,
// quoted, raw and multi-line strings, braces, semicolons, `=`, line and
// nested block comments, and the slashdash that comments out what follows.

function tokenize(text) {
    const tokens = [];
    const n = text.length;
    let i = 0;

    const isSpace = c => c === " " || c === "\t" || c === "\r" || c === "﻿";
    const ends = c => isSpace(c) || c === "\n" || c === "{" || c === "}"
                      || c === ";" || c === "=" || c === "\"" || c === "(" || c === ")";

    while (i < n) {
        const c = text[i];

        if (isSpace(c)) { i++; continue; }

        if (c === "\\") {
            // A line continuation: the newline after it does not end the node.
            let j = i + 1;
            while (j < n && isSpace(text[j])) j++;
            if (text.startsWith("//", j)) while (j < n && text[j] !== "\n") j++;
            if (text[j] === "\n") { i = j + 1; continue; }
            i++;
            continue;
        }

        if (c === "\n") { tokens.push({ "type": "newline", "start": i, "end": i + 1 }); i++; continue; }

        if (text.startsWith("//", i)) {
            while (i < n && text[i] !== "\n") i++;
            continue;
        }

        if (text.startsWith("/*", i)) {
            let depth = 1;
            i += 2;
            while (i < n && depth > 0) {
                if (text.startsWith("/*", i)) { depth++; i += 2; }
                else if (text.startsWith("*/", i)) { depth--; i += 2; }
                else i++;
            }
            continue;
        }

        if (text.startsWith("/-", i)) { tokens.push({ "type": "slashdash", "start": i, "end": i + 2 }); i += 2; continue; }

        if (c === "{" || c === "}" || c === ";" || c === "=") {
            const type = c === "{" ? "open" : c === "}" ? "close" : c === ";" ? "semi" : "equals";
            tokens.push({ "type": type, "start": i, "end": i + 1 });
            i++;
            continue;
        }

        if (c === "(") {
            // A type annotation, `(u8)10`. Carried as nothing.
            while (i < n && text[i] !== ")") i++;
            i++;
            continue;
        }

        // Raw strings: r#"…"# in v1, #"…"# in v2, any number of hashes.
        const raw = /^(?:r(#*)|(#+))"/.exec(text.slice(i, i + 64));
        if (raw) {
            const close = "\"" + (raw[1] !== undefined ? raw[1] : raw[2]);
            const from = i + raw[0].length;
            const to = text.indexOf(close, from);
            const end = to < 0 ? n : to + close.length;
            tokens.push({ "type": "string", "start": i, "end": end,
                          "value": text.slice(from, to < 0 ? n : to) });
            i = end;
            continue;
        }

        if (text.startsWith("\"\"\"", i)) {
            const to = text.indexOf("\"\"\"", i + 3);
            const end = to < 0 ? n : to + 3;
            tokens.push({ "type": "string", "start": i, "end": end,
                          "value": text.slice(i + 3, to < 0 ? n : to) });
            i = end;
            continue;
        }

        if (c === "\"") {
            let j = i + 1;
            let value = "";
            while (j < n && text[j] !== "\"") {
                if (text[j] === "\\" && j + 1 < n) {
                    const e = text[j + 1];
                    value += e === "n" ? "\n" : e === "t" ? "\t" : e;
                    j += 2;
                } else {
                    value += text[j];
                    j++;
                }
            }
            tokens.push({ "type": "string", "start": i, "end": j + 1, "value": value });
            i = j + 1;
            continue;
        }

        let j = i;
        while (j < n && !ends(text[j]) && !text.startsWith("//", j) && !text.startsWith("/*", j)) j++;
        if (j === i) j++;
        tokens.push({ "type": "ident", "start": i, "end": j, "value": text.slice(i, j) });
        i = j;
    }

    return tokens;
}

// ---- Nodes -----------------------------------------------------------------
//
// A node is a name, then arguments and `key=value` properties, then an
// optional block of children, and it ends at a newline, a semicolon or the
// brace that closes its parent. Each one keeps the text offsets it spans.

function parseNodes(tokens, at, nested) {
    const nodes = [];
    let i = at;

    while (i < tokens.length) {
        const t = tokens[i];
        if (t.type === "newline" || t.type === "semi") { i++; continue; }
        if (t.type === "close") {
            if (nested) return { "nodes": nodes, "next": i };
            i++;
            continue;
        }

        let dropped = false;
        let start = t.start;
        if (t.type === "slashdash") {
            dropped = true;
            i++;
            while (i < tokens.length && tokens[i].type === "newline") i++;
            if (i >= tokens.length) break;
        }

        const head = tokens[i];
        const node = {
            "name": head.value !== undefined ? head.value : "",
            "nameStart": head.start,
            "nameEnd": head.end,
            "start": start,
            "end": head.end,
            "args": [],
            "props": {},
            "children": null,
            "dropped": dropped
        };
        i++;

        let skipNext = false;
        while (i < tokens.length) {
            const u = tokens[i];
            if (u.type === "newline" || u.type === "semi" || u.type === "close")
                break;

            if (u.type === "slashdash") { skipNext = true; i++; continue; }

            if (u.type === "open") {
                const inner = parseNodes(tokens, i + 1, true);
                const closeTok = tokens[inner.next];
                const block = {
                    "open": u.start,
                    "close": closeTok ? closeTok.start : u.end,
                    "nodes": inner.nodes
                };
                i = inner.next + 1;
                node.end = closeTok ? closeTok.end : u.end;
                if (!skipNext)
                    node.children = block;
                skipNext = false;
                continue;
            }

            if ((u.type === "ident" || u.type === "string") && tokens[i + 1] && tokens[i + 1].type === "equals") {
                const v = tokens[i + 2];
                if (!skipNext && v)
                    node.props[u.value] = v.value;
                node.end = v ? v.end : tokens[i + 1].end;
                i += v ? 3 : 2;
                skipNext = false;
                continue;
            }

            if (!skipNext)
                node.args.push({ "value": u.value, "quoted": u.type === "string" });
            node.end = u.end;
            skipNext = false;
            i++;
        }

        // A semicolon that ends the node belongs to it: removing the node
        // takes its terminator with it.
        if (i < tokens.length && tokens[i].type === "semi") {
            node.end = tokens[i].end;
            i++;
        }

        nodes.push(node);
    }

    return { "nodes": nodes, "next": i };
}

// ---- What a file says ---------------------------------------------------------

// Scan one file: its includes, its binds and its outputs, in the order they
// appear, and the one `binds` block. `items` interleaves them, because the
// order between an include and a bind is what decides which of two binds on
// one key wins.
function scan(text) {
    const top = parseNodes(tokenize(text), 0, false).nodes;
    const items = [];
    let block = null;

    for (const node of top) {
        if (node.dropped)
            continue;

        if (node.name === "include" && node.args.length > 0) {
            items.push({ "kind": "include", "path": node.args[node.args.length - 1].value,
                         "optional": node.props.optional === "true" || node.props.optional === "#true" });
            continue;
        }

        if (node.name === "output" && node.args.length > 0 && node.children) {
            items.push(outputOf(node));
            continue;
        }

        if (node.name !== "binds" || !node.children)
            continue;

        block = { "start": node.start, "end": node.end,
                  "open": node.children.open, "close": node.children.close };

        for (const bind of node.children.nodes) {
            if (bind.dropped)
                continue;
            const action = bind.children
                ? bind.children.nodes.find(child => !child.dropped) || null
                : null;
            items.push({
                "kind": "bind",
                "key": bind.name,
                "keyStart": bind.nameStart,
                "keyEnd": bind.nameEnd,
                "start": bind.start,
                "end": bind.end,
                "props": bind.props,
                "action": action ? {
                    "name": action.name,
                    "args": action.args.map(a => a.value),
                    "props": action.props
                } : null
            });
        }
    }

    return { "items": items, "block": block };
}

// Where an include points, from the directory of the file that names it.
function resolve(path, directory, home) {
    if (path.startsWith("~/"))
        return home + path.slice(1);
    if (path.startsWith("/"))
        return path;
    return directory.replace(/\/$/, "") + "/" + path.replace(/^\.\//, "");
}

function directoryOf(path) {
    const cut = path.lastIndexOf("/");
    return cut <= 0 ? "/" : path.slice(0, cut);
}

// ---- Keys -------------------------------------------------------------------

const modifierNames = {
    "mod": "Mod",
    "super": "Super", "win": "Super",
    "ctrl": "Ctrl", "control": "Ctrl",
    "shift": "Shift",
    "alt": "Alt",
    "iso_level3_shift": "ISO_Level3_Shift", "mod5": "ISO_Level3_Shift",
    "iso_level5_shift": "ISO_Level5_Shift", "mod3": "ISO_Level5_Shift"
};

// The order a combination is written in, whatever order it was pressed in.
const modifierOrder = ["Mod", "Super", "Ctrl", "Alt", "Shift", "ISO_Level3_Shift", "ISO_Level5_Shift"];

function split(key) {
    const parts = String(key).split("+");
    // `Mod++` is not a thing niri accepts, but a trailing empty part must not
    // become a key.
    const last = parts.pop();
    const mods = [];
    for (const part of parts) {
        const known = modifierNames[part.toLowerCase()];
        if (known && !mods.includes(known))
            mods.push(known);
    }
    mods.sort((a, b) => modifierOrder.indexOf(a) - modifierOrder.indexOf(b));
    return { "mods": mods, "key": last };
}

// Two spellings of one combination compare equal. `Mod` is compared as
// `Super`: that is what it means when niri runs on a TTY, and a bind on
// `Mod+X` and another on `Super+X` answer the same press.
function normalize(key) {
    const parts = split(key);
    const mods = parts.mods.map(m => m === "Mod" ? "Super" : m);
    const unique = mods.filter((m, i) => mods.indexOf(m) === i).sort();
    return unique.concat([parts.key.toLowerCase()]).join("+");
}

function compose(mods, key) {
    const sorted = mods.slice().sort((a, b) => modifierOrder.indexOf(a) - modifierOrder.indexOf(b));
    return sorted.concat([key]).join("+");
}

// What a key is called on a keycap. Names that are already short and legible
// stay as they are; the ones that are keysym jargon are translated.
const keyLabels = {
    "space": "Space", "return": "Enter", "kp_enter": "Enter", "escape": "Esc",
    "tab": "Tab", "backspace": "⌫", "delete": "Del", "insert": "Ins",
    "home": "Home", "end": "End", "page_up": "PgUp", "page_down": "PgDn",
    "prior": "PgUp", "next": "PgDn",
    "up": "↑", "down": "↓", "left": "←", "right": "→",
    "comma": ",", "period": ".", "slash": "/", "backslash": "\\",
    "semicolon": ";", "apostrophe": "'", "grave": "`", "minus": "−",
    "equal": "=", "plus": "+", "bracketleft": "[", "bracketright": "]",
    "print": "Print", "pause": "Pause", "menu": "Menu",
    "wheelscrollup": "Wheel ↑", "wheelscrolldown": "Wheel ↓",
    "wheelscrollleft": "Wheel ←", "wheelscrollright": "Wheel →",
    "touchpadscrollup": "Swipe ↑", "touchpadscrolldown": "Swipe ↓",
    "touchpadscrollleft": "Swipe ←", "touchpadscrollright": "Swipe →",
    "mouseleft": "Left click", "mouseright": "Right click", "mousemiddle": "Middle click",
    "mouseback": "Back button", "mouseforward": "Forward button",
    "xf86audioraisevolume": "Vol +", "xf86audiolowervolume": "Vol −",
    "xf86audiomute": "Mute", "xf86audiomicmute": "Mic mute",
    "xf86audioplay": "Play", "xf86audiopause": "Pause", "xf86audiostop": "Stop",
    "xf86audionext": "Next", "xf86audioprev": "Previous",
    "xf86monbrightnessup": "Bright +", "xf86monbrightnessdown": "Bright −"
};

const modifierLabels = {
    "Mod": "Super", "Super": "Super", "Ctrl": "Ctrl", "Alt": "Alt", "Shift": "Shift",
    "ISO_Level3_Shift": "AltGr", "ISO_Level5_Shift": "Level 5"
};

function keycaps(key) {
    const parts = split(key);
    const out = parts.mods.map(m => modifierLabels[m] || m);
    const lower = parts.key.toLowerCase();
    let label = keyLabels[lower];
    if (label === undefined)
        label = parts.key.length === 1 ? parts.key.toUpperCase()
              : parts.key.replace(/^XF86/, "");
    out.push(label);
    return out;
}

// ---- What a bind does, in words ---------------------------------------------

function humanize(name) {
    const words = String(name).replace(/-/g, " ");
    return words.charAt(0).toUpperCase() + words.slice(1);
}

// The name a row goes by. niri's own `hotkey-overlay-title` wins when there is
// one — somebody chose it — and otherwise the action says what it does.
function describe(bind) {
    const title = bind.props["hotkey-overlay-title"];
    if (title && title !== "null" && title !== "#null")
        return title;

    const action = bind.action;
    if (!action)
        return bind.key;

    if (action.name === "spawn" || action.name === "spawn-sh") {
        const words = action.args.slice();
        if (words.length === 0)
            return "Run a command";
        words[0] = words[0].split("/").pop();
        return "Run " + words.join(" ");
    }

    return [humanize(action.name)].concat(action.args).join(" ");
}

// ---- Writing ------------------------------------------------------------------

function quote(value) {
    return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
}

// One bind as a line. Only what Bioma itself adds is ever written this way —
// an edited bind keeps its own text and has only its key replaced.
function line(key, action, title) {
    const words = [key];
    if (title)
        words.push("hotkey-overlay-title=" + quote(title));
    const call = [action.name].concat(action.args.map(quote)).join(" ");
    return words.join(" ") + " { " + call + "; }";
}

function withKey(text, bind, key) {
    return text.slice(0, bind.keyStart) + key + text.slice(bind.keyEnd);
}

// A bind is removed with the whole of its lines when it has them to itself,
// so the block does not keep a hole where it was. A comment on the line
// directly above belongs to it and goes with it.
function without(text, bind) {
    let from = bind.start;
    let to = bind.end;

    let lineStart = from;
    while (lineStart > 0 && (text[lineStart - 1] === " " || text[lineStart - 1] === "\t")) lineStart--;
    const ownsStart = lineStart === 0 || text[lineStart - 1] === "\n";

    let lineEnd = to;
    while (lineEnd < text.length && (text[lineEnd] === " " || text[lineEnd] === "\t")) lineEnd++;
    const ownsEnd = lineEnd >= text.length || text[lineEnd] === "\n";

    if (!ownsStart || !ownsEnd)
        return text.slice(0, from) + text.slice(to);

    from = lineStart;
    to = Math.min(text.length, lineEnd + 1);

    // Comment lines immediately above, with no blank line between.
    for (;;) {
        if (from === 0)
            break;
        const prevEnd = from - 1;
        let prevStart = prevEnd;
        while (prevStart > 0 && text[prevStart - 1] !== "\n") prevStart--;
        const previous = text.slice(prevStart, prevEnd).trim();
        if (!previous.startsWith("//"))
            break;
        from = prevStart;
    }

    // A bind set apart by blank lines on both sides leaves one of them, not
    // two.
    const blankBefore = from >= 2 && text[from - 1] === "\n" && text[from - 2] === "\n";
    const blankAfter = text[to] === "\n";
    if (blankBefore && blankAfter)
        to++;

    return text.slice(0, from) + text.slice(to);
}

// A new bind goes at the end of the block, indented like the bind before it.
// A file with no block gets one at its end.
function withAdded(text, block, entry, lastBind) {
    if (!block) {
        const tail = text.length === 0 || text.endsWith("\n") ? "" : "\n";
        return text + tail + "\nbinds {\n    " + entry + "\n}\n";
    }

    return withChild(text, block, entry, lastBind);
}

// The block alone, as niri would read it: what gets validated before a file
// is written, so a mistake is found in a scratch copy rather than in the
// running compositor's configuration.
function blockOf(text) {
    const found = scan(text).block;
    return found ? text.slice(found.start, found.end) + "\n" : "";
}

// ---- Outputs --------------------------------------------------------------------

function outputOf(node) {
    const children = node.children.nodes.filter(child => !child.dropped);
    const named = name => children.find(child => child.name === name) || null;
    const position = named("position");
    return {
        "kind": "output",
        "name": node.args[0].value,
        "start": node.start,
        "end": node.end,
        "open": node.children.open,
        "close": node.children.close,
        "children": children,
        "off": named("off") !== null,
        "primary": named("focus-at-startup") !== null,
        "position": position ? {
            "start": position.start,
            "end": position.end,
            "x": Number(position.props.x),
            "y": Number(position.props.y)
        } : null
    };
}

// Whether a section names this output. niri accepts the connector or the
// monitor's make, model and serial, and compares without case.
function names(output, connector, description) {
    const wanted = String(output.name).toLowerCase();
    return wanted === String(connector).toLowerCase()
        || (description.length > 0 && wanted === String(description).toLowerCase());
}

// A child line goes at the end of a section, indented like the children
// already in it.
function withChild(text, block, entry, lastChild) {
    let indent = "    ";
    if (lastChild) {
        let s = lastChild.start;
        while (s > 0 && text[s - 1] !== "\n") s--;
        const lead = /^[ \t]*/.exec(text.slice(s, lastChild.start))[0];
        if (lead.length > 0)
            indent = lead;
    }

    let back = block.close;
    while (back > 0 && (text[back - 1] === " " || text[back - 1] === "\t")) back--;

    if (back > 0 && text[back - 1] === "\n")
        return text.slice(0, back) + indent + entry + "\n" + text.slice(back);

    return text.slice(0, block.close) + "\n" + indent + entry + "\n" + text.slice(block.close);
}

function positionLine(x, y) {
    return "position x=" + Math.round(x) + " y=" + Math.round(y);
}

// The position replaced where it is written, or added when it is not.
function withPosition(text, output, x, y) {
    const entry = positionLine(x, y);
    if (output.position)
        return text.slice(0, output.position.start) + entry + text.slice(output.position.end);
    return withChild(text, output, entry, output.children[output.children.length - 1] || null);
}

// A flag — a child with no value, like `focus-at-startup` — set or cleared.
function withFlag(text, output, flag, on) {
    const present = output.children.find(child => child.name === flag) || null;
    if (on && !present)
        return withChild(text, output, flag, output.children[output.children.length - 1] || null);
    if (!on && present)
        return without(text, present);
    return text;
}

// A section for an output the configuration does not mention yet.
function withOutput(text, name, x, y) {
    const tail = text.length === 0 || text.endsWith("\n") ? "" : "\n";
    return text + tail + "\noutput " + quote(name) + " {\n    " + positionLine(x, y) + "\n}\n";
}

// Every output section of a file on its own — what is validated before the
// file is written, for the same reason the binds block is.
function outputsText(text) {
    const out = [];
    for (const item of scan(text).items)
        if (item.kind === "output")
            out.push(text.slice(item.start, item.end));
    return out.join("\n") + "\n";
}
