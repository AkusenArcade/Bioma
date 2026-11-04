import QtQuick
import qs.core

// The hand's speed, kept when the fingers lift.
//
// On Wayland a touchpad scroll reaches Qt as a run of pixel deltas and an end,
// and nothing after it: libinput leaves kinetic scrolling to the client, and
// Flickable follows the fingers and stops dead on the frame they leave the
// pad. This follows them the same way and, at the end, flicks the list on at
// the speed the fingers had over the last `Timing.fling` — so the glide is the
// hand's own movement carried on, at the list's own deceleration, and a hand
// that stopped before it lifted leaves the list where it is.
//
// A WheelHandler on the list takes the wheel before the list does and cannot
// give it back, so the mouse wheel comes through here too, and gets what the
// list would have given it: one flick per notch, at a quarter of the top
// speed or twice the notch, whichever is more. Qt reports both through the
// same device; the phase tells them apart — a notch has none, a stroke runs
// from updates to an end.
//
// Scroller makes one for its list, so every list that can be longer than its
// room has it. A list without the mark declares one itself.
WheelHandler {
    id: root

    property Flickable flick: null

    // While the fingers are on the pad. The list is not `moving` then — it is
    // this handler that moves it — so the mark reads this as well.
    property bool following: false

    property var samples: []

    function top() {
        return root.flick.originY - root.flick.topMargin;
    }

    function bottom() {
        return Math.max(root.top(), root.flick.originY + root.flick.contentHeight
                                    + root.flick.bottomMargin - root.flick.height);
    }

    parent: root.flick
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    // A list that fits leaves the wheel to whatever is under it.
    enabled: root.flick !== null && root.flick.interactive
             && root.flick.contentHeight + root.flick.topMargin + root.flick.bottomMargin
                > root.flick.height

    onWheel: event => {
        const list = root.flick;

        if (event.phase === Qt.NoScrollPhase) {
            const notch = event.angleDelta.y;
            if (notch !== 0)
                list.flick(0, Math.sign(notch) * Math.max(Math.abs(notch) * 2,
                                                          list.maximumFlickVelocity / 4));
            return;
        }

        const now = Date.now();

        if (event.phase === Qt.ScrollEnd) {
            // The speed over the window, measured from the last sample before
            // it: each delta is the movement since the one before.
            const from = now - Timing.fling;
            const kept = root.samples;
            const first = kept.findIndex(s => s.t >= from);
            root.samples = [];
            root.following = false;
            if (first < 0)
                return;
            const start = Math.max(0, first - 1);
            let moved = 0;
            for (let i = start + 1; i < kept.length; i++)
                moved += kept[i].dy;
            const span = now - kept[start].t;
            if (span > 0 && moved !== 0)
                list.flick(0, moved / span * 1000);
            return;
        }

        if (!root.following) {
            list.cancelFlick();
            root.following = true;
        }
        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
        list.contentY = Math.max(root.top(), Math.min(root.bottom(), list.contentY - dy));
        root.samples = root.samples.filter(s => now - s.t <= Timing.fling * 2)
                                   .concat([{ "t": now, "dy": dy }]);
    }
}
