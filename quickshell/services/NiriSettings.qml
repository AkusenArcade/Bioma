pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import "niri-config.js" as NiriKdl

// A few of niri's own settings, kept where niri keeps them: the gaps, the
// focus ring's width, whether the focus follows the pointer, the named
// workspaces, what starts with the session, and three things a window rule
// can say about one application — its opacity, the width it opens at and the
// workspace it opens on.
//
// Written **into the user's own files**, in place, the way the Monitors and
// Keybinds pages write (services/NiriConfig.qml): the setting is changed where
// it is written and nothing around it moves, and something new goes beside
// the last thing like it. Not into a file of Bioma's included last, because
// niri cannot be told from an include to undo what an earlier file says:
// `focus-follows-mouse` is a flag, and niri 26.04 refuses `false` after it.
//
// Switching off keeps the line. A startup entry or the focus flag switched off
// is commented out, as a person does by hand — so lines already commented out
// in somebody's configuration appear here as entries that are off, and come
// back exactly as they were written.
//
// Bioma's own files — `bioma-*.kdl`, and the repository's `config/niri` — are
// read for what is in force, never written here: they are rendered, and the
// next render would undo the edit.
//
// The focus ring is the exception that proves it: Bioma already draws it,
// from niri's template (bioma-theme.kdl, services/Templates.qml), and that
// file is included last — so the width is Bioma's setting, `niri.focus_ring`,
// and goes into the template. With the template switched off, it is written in
// place like the rest.
//
// Akusen asked for this page 2026-10-23 ("Nuove idee"). See
// cells/settings/SettingsNiri.qml.
Singleton {
    id: root

    readonly property bool ready: NiriConfig.ready
    readonly property bool busy: NiriConfig.busy || NiriConfig.queue.length > 0
    readonly property string error: NiriConfig.error

    readonly property string main: NiriConfig.main

    // What niri does when the configuration does not say: 26.04's defaults.
    readonly property int defaultGaps: 16

    function own(file) {
        const base = String(file).split("/").pop();
        return base.startsWith("bioma") || String(file).startsWith(Quickshell.shellDir + "/");
    }

    // Everything niri reads, and the part of it that is the user's.
    readonly property var all: NiriConfig.items
    readonly property var items: root.all.filter(item => !root.own(item.file))

    function sections(list, name) {
        return list.filter(item => item.kind === "section" && item.name === name);
    }

    // Every child of that name in those sections, in the order niri reads
    // them, each with its file: the last is the one in force.
    function named(list, name) {
        const out = [];
        for (const section of list)
            for (const child of section.children)
                if (!child.dropped && child.name === name)
                    out.push({ "file": section.file, "section": section, "node": child });
        return out;
    }

    // ---- What is in force ------------------------------------------------------

    readonly property var gapNodes: root.named(root.sections(root.all, "layout"), "gaps")

    readonly property real gaps: {
        if (root.pending.gaps !== undefined)
            return root.pending.gaps;
        const last = root.gapNodes[root.gapNodes.length - 1];
        return last && last.node.args.length > 0 ? Number(last.node.args[0].value) : root.defaultGaps;
    }

    readonly property bool themed: Templates.isOn("niri")

    // The width of every `focus-ring { width }`, in the user's files and in
    // all of them.
    function ringWidths(list) {
        const out = [];
        for (const ring of root.named(root.sections(list, "layout"), "focus-ring")) {
            if (!ring.node.children)
                continue;
            for (const child of ring.node.children.nodes)
                if (!child.dropped && child.name === "width")
                    out.push({ "file": ring.file, "ring": ring, "node": child });
        }
        return out;
    }

    readonly property real focusRing: {
        if (root.pending.focusRing !== undefined)
            return root.pending.focusRing;
        if (root.themed)
            return Config.get("niri.focus_ring", 2);
        const widths = root.ringWidths(root.all);
        const last = widths[widths.length - 1];
        return last && last.node.args.length > 0 ? Number(last.node.args[0].value) : 4;
    }

    readonly property bool followsMouse: root.named(root.sections(root.all, "input"), "focus-follows-mouse").length > 0

    readonly property var workspaces: root.items.filter(item => item.kind === "workspace")

    // Bioma's own line starts the shell, and switching it off from inside the
    // shell is not a setting.
    function isShell(item) {
        return !item.sh && item.args.length >= 2 && /\/scripts\/shell$/.test(item.args[0])
            && item.args[1] === "start";
    }

    readonly property var startup: root.items.filter(item => item.kind === "spawn" && !root.isShell(item))

    // A rule is an application's when one of its matches names one.
    readonly property var rules: root.items.filter(item => item.kind === "rule"
                                                   && item.matches.some(match => match["app-id"] !== undefined))
    readonly property int otherRules: root.items.filter(item => item.kind === "rule").length - root.rules.length

    // ---- Writing ----------------------------------------------------------------------
    //
    // One change at a time: each is computed against the text as it is read
    // now, and a second one computed before the first had landed would write
    // over it. A press made while niri is still checking the last one is
    // dropped, and a slider waits for it.

    // The item as the files say it now. A row hands back what it was given,
    // and that is a copy — a Repeater's modelData is not the object in the
    // list — so it is found again by where it is and what it says. One that
    // is no longer there was read from a text that has changed since, and its
    // offsets point somewhere else now.
    function current(item) {
        const said = root.signature(item);
        const found = item ? NiriConfig.items.find(other => other.file === item.file && other.kind === item.kind
            && other.start === item.start && other.end === item.end && root.signature(other) === said) : null;
        if (!found)
            NiriConfig.error = "The file changed under this setting. Try again.";
        return found || null;
    }

    function signature(item) {
        if (!item)
            return "";
        if (item.kind === "rule")
            return JSON.stringify([item.matches, item.opacity, item.width, item.workspace, item.others]);
        if (item.kind === "workspace")
            return JSON.stringify([item.name, item.output]);
        if (item.kind === "spawn")
            return JSON.stringify([item.args, item.sh, item.on]);
        return "";
    }

    function commit(file, change) {
        const text = NiriConfig.textOf(file);
        if (text === null) {
            NiriConfig.error = "niri's configuration could not be read.";
            return;
        }
        const next = change(text);
        if (next !== text)
            NiriConfig.write(file, next, NiriKdl.standalone(next));
    }

    function edits(file, list) {
        if (list.length > 0)
            root.commit(file, text => NiriKdl.spliced(text, list));
    }

    // Edits gathered across files, `{ file: [edit] }`, written one file after
    // the other.
    function editsAcross(byFile) {
        for (const file in byFile)
            root.edits(file, byFile[file]);
    }

    // A new top-level entry beside the last one like it — `like`, or else the
    // last of its kind — or at the end of niri's own file when there is none.
    function place(kind, entry, apart, like) {
        const found = like && like.length > 0 ? like : root.items.filter(item => item.kind === kind);
        const last = found[found.length - 1];
        if (last)
            root.commit(last.file, text => NiriKdl.spliced(text, [NiriKdl.after(text, last, entry, apart)]));
        else
            root.commit(root.main, text => NiriKdl.spliced(text, [NiriKdl.appending(text, entry)]));
    }

    // A child of a section, beside the section's last child; or a section of
    // its own at the end of niri's file.
    function addToSection(name, entry) {
        const found = root.sections(root.items, name);
        const section = found[found.length - 1];
        if (section) {
            const kids = section.children.filter(child => !child.dropped);
            root.commit(section.file, text => NiriKdl.withChild(text, section, entry, kids[kids.length - 1] || null));
        } else {
            root.commit(root.main, text => NiriKdl.spliced(text, [NiriKdl.appending(text, `${name} {\n    ${entry}\n}`)]));
        }
    }

    // ---- Sliders, written when the hand rests -----------------------------------------

    // What a slider has asked for and not yet been written, shown meanwhile.
    property var pending: ({})

    function later(key, value) {
        const next = Object.assign({}, root.pending);
        next[key] = value;
        root.pending = next;
        rest.restart();
    }

    Timer {
        id: rest
        interval: 400
        onTriggered: {
            if (root.busy) {
                rest.restart();
                return;
            }
            const asked = root.pending;
            if (asked.gaps !== undefined)
                root.writeGaps(asked.gaps);
            if (asked.focusRing !== undefined)
                root.writeFocusRing(asked.focusRing);
            // Kept until niri has read it back, so the slider does not jump
            // to the old value in between.
            settle.restart();
        }
    }

    Timer {
        id: settle
        interval: 100
        onTriggered: {
            if (root.busy) {
                settle.restart();
                return;
            }
            root.pending = ({});
        }
    }

    function setGaps(value) {
        root.later("gaps", Math.round(value));
    }

    function writeGaps(value) {
        const entry = "gaps " + value;
        const mine = root.named(root.sections(root.items, "layout"), "gaps");
        if (mine.length === 0) {
            root.addToSection("layout", entry);
            return;
        }
        // Every one of them, so the number on the page is the number in every
        // file: one left behind comes back the day the later file is gone.
        const byFile = {};
        for (const found of mine) {
            const text = NiriConfig.textOf(found.file) || "";
            (byFile[found.file] = byFile[found.file] || []).push(NiriKdl.replacing(text, found.node, entry));
        }
        root.editsAcross(byFile);
    }

    function setFocusRing(value) {
        root.later("focusRing", Math.round(value));
    }

    function writeFocusRing(value) {
        if (root.themed) {
            Config.set("niri.focus_ring", value);
            return;
        }
        const entry = "width " + value;
        const mine = root.ringWidths(root.items);
        if (mine.length === 0) {
            root.addToSection("layout", `focus-ring { ${entry}; }`);
            return;
        }
        const byFile = {};
        for (const found of mine) {
            const text = NiriConfig.textOf(found.file) || "";
            (byFile[found.file] = byFile[found.file] || []).push(NiriKdl.replacing(text, found.node, entry));
        }
        root.editsAcross(byFile);
    }

    // ---- The focus and the pointer -----------------------------------------------------

    function setFollowsMouse(on) {
        if (root.busy || on === root.followsMouse)
            return;

        if (!on) {
            const byFile = {};
            for (const found of root.named(root.sections(root.items, "input"), "focus-follows-mouse")) {
                const text = NiriConfig.textOf(found.file) || "";
                (byFile[found.file] = byFile[found.file] || []).push(NiriKdl.switchingOff(text, found.node));
            }
            root.editsAcross(byFile);
            return;
        }

        // The line that was switched off, if there is one, comes back as it
        // was — with its `max-scroll-amount`, if it had one.
        let commented = null;
        for (const section of root.sections(root.items, "input")) {
            for (const note of section.commented)
                if (note.node.name === "focus-follows-mouse")
                    commented = { "file": section.file, "note": note };
            for (const child of section.children)
                if (child.dropped && child.name === "focus-follows-mouse")
                    commented = { "file": section.file,
                                  "note": { "start": child.start, "bodyStart": child.nameStart } };
        }
        if (commented)
            root.edits(commented.file, [NiriKdl.switchingOn(commented.note)]);
        else
            root.addToSection("input", "focus-follows-mouse");
    }

    // ---- Workspaces ----------------------------------------------------------------------

    function workspaceProblem(name, except) {
        const wanted = String(name).trim();
        if (wanted.length === 0)
            return "A workspace needs a name.";
        // niri compares names without case. The one being renamed is told by
        // its place in its file, not by identity: a Repeater's modelData is a
        // copy, never the object in `workspaces`, so every name collided with
        // itself.
        const self = ws => except && ws.file === except.file && ws.start === except.start;
        if (root.workspaces.some(ws => !self(ws) && ws.name.toLowerCase() === wanted.toLowerCase()))
            return "Another workspace already has this name.";
        return "";
    }

    function freeWorkspace() {
        let n = root.workspaces.length + 1;
        while (root.workspaceProblem(`Workspace ${n}`, null).length > 0)
            n++;
        return `Workspace ${n}`;
    }

    function addWorkspace() {
        if (root.busy)
            return;
        const last = root.workspaces[root.workspaces.length - 1];
        root.place("workspace", "workspace " + NiriKdl.quote(root.freeWorkspace()), last ? last.open >= 0 : false);
    }

    // The new name everywhere the old one is used: the rules that open
    // windows on it and the binds that go to it.
    function renameWorkspace(ws, name) {
        const wanted = String(name).trim();
        if (root.busy || wanted === ws.name)
            return;
        ws = root.current(ws);
        if (!ws || root.workspaceProblem(wanted, ws).length > 0)
            return;

        const byFile = {};
        const add = (file, edit) => (byFile[file] = byFile[file] || []).push(edit);
        const quoted = NiriKdl.quote(wanted);

        add(ws.file, { "start": ws.nameStart, "end": ws.nameEnd, "text": quoted });

        for (const item of root.items) {
            const text = NiriConfig.textOf(item.file) || "";
            if (item.kind === "rule" && item.workspace !== null) {
                for (const child of item.children)
                    if (child.name === "open-on-workspace" && child.args.length > 0 && child.args[0].value === ws.name)
                        add(item.file, { "start": child.args[0].start, "end": child.args[0].end, "text": quoted });
            } else if (item.kind === "bind" && item.action && item.action.name.indexOf("workspace") >= 0
                       && item.action.args.includes(ws.name)) {
                for (const found of NiriKdl.naming(text, item.start, item.end, ws.name))
                    add(item.file, Object.assign(found, { "text": quoted }));
            }
        }
        root.editsAcross(byFile);
    }

    function setWorkspaceOutput(ws, output) {
        if (root.busy || output === ws.output)
            return;
        ws = root.current(ws);
        if (!ws)
            return;
        const text = NiriConfig.textOf(ws.file) || "";
        const entry = "open-on-output " + NiriKdl.quote(output);

        if (ws.outputNode) {
            root.edits(ws.file, [output.length > 0 ? NiriKdl.replacing(text, ws.outputNode, entry)
                                                   : NiriKdl.removing(text, ws.outputNode)]);
        } else if (output.length > 0 && ws.open >= 0) {
            root.commit(ws.file, t => NiriKdl.withChild(t, ws, entry, ws.children[ws.children.length - 1] || null));
        } else if (output.length > 0) {
            root.edits(ws.file, [NiriKdl.replacing(text, ws,
                `workspace ${NiriKdl.quote(ws.name)} {\n    ${entry}\n}`)]);
        }
    }

    // A workspace changes places with its neighbour — only one in the same
    // file: across files, the order is the order of the includes.
    function neighbour(ws, delta) {
        const at = root.workspaces.findIndex(other => other.file === ws.file && other.start === ws.start);
        const other = root.workspaces[at + delta];
        return other && other.file === ws.file ? other : null;
    }

    function moveWorkspace(ws, delta) {
        if (root.busy)
            return;
        ws = root.current(ws);
        const other = ws ? root.neighbour(ws, delta) : null;
        if (!other)
            return;
        const text = NiriConfig.textOf(ws.file) || "";
        root.edits(ws.file, [
            { "start": ws.start, "end": ws.end, "text": text.slice(other.start, other.end) },
            { "start": other.start, "end": other.end, "text": text.slice(ws.start, ws.end) }
        ]);
    }

    function removeWorkspace(ws) {
        if (root.busy)
            return;
        ws = root.current(ws);
        if (!ws)
            return;
        root.edits(ws.file, [NiriKdl.removing(NiriConfig.textOf(ws.file) || "", ws)]);
    }

    // ---- At startup -------------------------------------------------------------------------

    // `command` is the words of a command, or one line for the shell.
    function addStartup(command, sh) {
        if (root.busy || (sh ? String(command).trim().length === 0 : command.length === 0))
            return;
        const entry = NiriKdl.spawnLine(sh ? String(command).trim() : command, sh);
        root.place("spawn", entry, false, root.startup);
    }

    function setStartupOn(item, on) {
        if (root.busy || on === item.on)
            return;
        item = root.current(item);
        if (!item)
            return;
        const text = NiriConfig.textOf(item.file) || "";
        root.edits(item.file, [on ? NiriKdl.switchingOn(item) : NiriKdl.switchingOff(text, item)]);
    }

    function removeStartup(item) {
        if (root.busy)
            return;
        item = root.current(item);
        if (!item)
            return;
        root.edits(item.file, [NiriKdl.removing(NiriConfig.textOf(item.file) || "", item)]);
    }

    // ---- Window rules --------------------------------------------------------------------------

    // What the page offers to change is all a rule says: it can go.
    function removable(rule) {
        return rule.others === 0 && rule.excludes === 0
            && rule.matches.every(match => Object.keys(match).length === 1 && match["app-id"] !== undefined);
    }

    function setRule(rule, name, entry) {
        if (root.busy)
            return;
        rule = root.current(rule);
        if (!rule)
            return;
        const text = NiriConfig.textOf(rule.file) || "";
        const present = rule.children.filter(child => child.name === name).pop() || null;
        if (entry === null) {
            if (present)
                root.edits(rule.file, [NiriKdl.removing(text, present)]);
        } else if (present) {
            root.edits(rule.file, [NiriKdl.replacing(text, present, entry)]);
        } else {
            root.commit(rule.file, t => NiriKdl.withChild(t, rule, entry, rule.children[rule.children.length - 1] || null));
        }
    }

    function setRuleOpacity(rule, value) {
        root.setRule(rule, "opacity", value === null ? null : "opacity " + NiriKdl.figure(value));
    }

    function setRuleWidth(rule, fraction) {
        root.setRule(rule, "default-column-width",
                     fraction === null ? null : `default-column-width { proportion ${NiriKdl.figure(fraction)}; }`);
    }

    function setRuleWorkspace(rule, name) {
        root.setRule(rule, "open-on-workspace", name === null ? null : "open-on-workspace " + NiriKdl.quote(name));
    }

    function removeRule(rule) {
        if (root.busy || !root.removable(rule))
            return;
        rule = root.current(rule);
        if (!rule)
            return;
        root.edits(rule.file, [NiriKdl.removing(NiriConfig.textOf(rule.file) || "", rule)]);
    }

    // An application's windows, by the id they report: matched whole, so
    // `zen` is not also `zen-beta`.
    function addRule(appId) {
        if (root.busy || String(appId).length === 0)
            return;
        const pattern = "^" + String(appId).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$";
        // Beside the other rules for an application: the last rule of all can
        // be a file's catch-all, included after them.
        root.place("rule", NiriKdl.ruleBlock(pattern), true, root.rules);
    }
}
