pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Sums and conversions, answered in the launcher's field.
//
// `qalc` does the arithmetic, the units and the currencies — 26 ms a call, so
// one process per question is cheaper than one kept alive all day for the
// few the launcher will ever ask. It runs in the C locale: the shell speaks
// English, and a decimal comma in a result would be a different number once
// pasted somewhere that reads a point.
//
// The hard part is not the answer but whether there is a question. qalc will
// make something of anything — "firefox" comes back as a quantity of bytes —
// and the first row is the one Enter takes, so a calculation that is not
// one steals the launch. A query is a question only when it says so:
// figures joined by an operator, a conversion (`to`, `in`), a function
// called, or a leading `=` that asks outright. A word in it must be one of
// those, or a constant; a name with a figure in it — `gnome-2048`, `7zip` —
// is an application.
Singleton {
    id: root

    property string query: ""

    // What came back, and for which query. Empty when there is nothing to
    // say, which is most of the time.
    property string answer: ""
    property string answered: ""

    readonly property string expression: root.question(root.query)
    readonly property bool asked: root.expression.length > 0
    readonly property string result: root.asked && root.answered === root.query ? root.answer : ""

    // Between asking and the answer: the launcher says nothing answers only
    // once it knows.
    readonly property bool pending: root.asked && root.answered !== root.query

    // Words a calculation may hold without a call or a conversion to vouch
    // for it.
    readonly property var constants: ["pi", "e", "tau", "phi", "π", "τ", "φ", "and", "or", "not", "mod", "rem", "xor"]

    function question(text) {
        const trimmed = text.trim();
        if (trimmed.startsWith("="))
            return trimmed.slice(1).trim();

        if (!/\d/.test(trimmed))
            return "";
        // A trailing operator is a sum still being typed: qalc would answer
        // "5 +" with 5, and the row would flicker a wrong figure on every
        // keystroke.
        if (/[+\-*\/^×÷,.]\s*$/.test(trimmed))
            return "";

        // A conversion starts from a quantity: "h264 to mp4" is a question
        // about files, not units.
        const converts = /^[-+(]?\s*[\d.]/.test(trimmed) && /\s(to|in)\s+\S/i.test(trimmed);
        const operates = /[\d)πτφ]\s*[+\-*\/^×÷%<>=!]|[+\-*\/^×÷]\s*[\d(]/.test(trimmed);
        const calls = /[A-Za-z]\w*\s*\(/.test(trimmed);
        if (!converts && !operates && !calls)
            return "";

        if (!converts) {
            const words = trimmed.replace(/[A-Za-z_]\w*\s*\(/g, "(").match(/[A-Za-z_]+/g) || [];
            for (const word of words)
                if (root.constants.indexOf(word.toLowerCase()) < 0)
                    return "";
        }
        return trimmed;
    }

    // Asked of the query itself rather than of `asked`: this handler can run
    // before that binding has heard the query change, and it read the
    // previous one's answer — every sum was a keystroke late.
    onQueryChanged: {
        if (root.question(root.query).length === 0) {
            settle.stop();
            root.answer = "";
            root.answered = root.query;
            return;
        }
        settle.restart();
    }

    Timer {
        id: settle
        interval: Timing.search
        onTriggered: root.ask()
    }

    function ask() {
        root.refreshRates();
        const asking = root.query;
        const process = sum.createObject(root, {
            "asked": asking,
            "command": ["qalc", "-t", "--", root.question(asking)]
        });
        process.running = true;
    }

    Component {
        id: sum

        Process {
            id: call

            property string asked: ""

            environment: ({ "LC_ALL": "C" })

            stdout: StdioCollector {
                onStreamFinished: root.land(call.asked, text)
            }

            onExited: call.destroy()
        }
    }

    function land(asked, text) {
        if (asked !== root.query)
            return;
        root.answer = root.valid(root.question(asked), text.trim()) ? text.trim() : "";
        root.answered = asked;
    }

    // What qalc gives back when it understood nothing: the question itself,
    // or a function it could not evaluate left standing in the answer.
    function valid(expression, out) {
        if (out.length === 0 || out.indexOf("\n") >= 0)
            return false;
        const flat = s => s.replace(/\s+/g, "").replace(/−/g, "-").toLowerCase();
        if (flat(out) === flat(expression))
            return false;
        return !/[A-Za-z_]\(/.test(out);
    }

    // The result alone, as it would be typed: a currency's symbol and a
    // unit stay, because "34.2" without "$" is not what was asked for.
    function copy() {
        if (root.result.length > 0)
            Quickshell.execDetached(["wl-copy", "--type", "text/plain", "--", root.result]);
    }

    // ---- Exchange rates ------------------------------------------------------
    //
    // qalc reads its rates from a file it only refreshes when told to, so a
    // conversion done today would quietly use last month's euro. Once a day,
    // on the first question, it is told to, in the background: the answer in
    // front of the user is never held up for it.

    property string refreshed: ""

    function refreshRates() {
        const today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        if (root.refreshed === today)
            return;
        root.refreshed = today;
        Quickshell.execDetached(["sh", "-c",
            'rates="${XDG_DATA_HOME:-$HOME/.local/share}/qalculate/rates.json"; '
            + '[ -n "$(find "$rates" -mmin -1440 2>/dev/null)" ] || exec qalc -e -t 0 >/dev/null 2>&1']);
    }
}
