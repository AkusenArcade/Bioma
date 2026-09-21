# Loader — animation spec

`icons/loader.svg` is the only icon in the set that is meant to move. **The file itself is
static**: the segment sits at the left end of the track. Everything below is the
implementation's job.

This document is the whole contract. If something here conflicts with a quick reading of
`STYLE_GUIDE.md`, this file wins for the loader and only for the loader.

---

## 1. Why this icon is an exception

The style guide says motion is data: nothing moves in Bioma unless the movement itself carries
information. The loader is the single exception, and it is an exception only because its
movement *is* the information — it means **"no value yet"**. The moment a value exists, the
meaning is gone and so is the motion.

That is why the loader is never decorative, never "nice while we wait", and never runs on a
timer.

---

## 2. Geometry

The icon is a 24 × 24 viewBox with two rectangles:

| Part | Geometry | Role |
| --- | --- | --- |
| track | `rect x=3 y=8.5 w=18 h=7 rx=3.5` | 1.5 stroke, `currentColor`, no fill |
| segment | `rect x=5.2 y=10.7 w=6 h=2.6 rx=1.3` | filled `currentColor`, no stroke |

The segment is inset 2.2 units from the inner face of the track on every side. Its travel is
therefore:

```
x_start = 5.2
x_end   = 21 − 2.2 − 6 = 12.8
travel  = 7.6 units
```

**Only the segment moves.** The track never moves, never pulses, never changes opacity. Do not
scale, rotate or fade the segment; do not add a second segment; do not add a trail.

---

## 3. Timing

Both values live in the named timing set (`tokens.css`) like every other duration in the shell.
Never hard-code them at the call site.

```css
--t-loader:   1200ms;                        /* one full cycle: there and back */
--ease-sweep: cubic-bezier(.45, 0, .55, 1);  /* loader only */
```

One cycle is 1.2 s **round trip** — 600 ms left→right, 600 ms right→left. The easing is
symmetric on purpose: the segment eases out of each end and crosses the middle at speed, so the
rhythm reads as breathing rather than as a progress bar. It is not a progress bar: it must never
suggest a position within a known duration.

`--ease-sweep` is used by nothing else. It is not one of the shell's open/close curves and must
not be borrowed for other motion.

---

## 4. Implementation

### CSS

```css
@keyframes sweep {
  0%, 100% { transform: translateX(0); }
  50%      { transform: translateX(7.6px); }
}

.sweep { animation: sweep var(--t-loader) var(--ease-sweep) infinite; }
```

`.sweep` is the class on the second `<rect>`. The `7.6px` is in the SVG's own user-space units,
so it stays correct at any rendered size as long as the `viewBox` is `0 0 24 24` and the
element's `width`/`height` match it. (See the viewBox trap in `IMPLEMENTATION.md`: if the element
size and the viewBox disagree, the browser rescales and the travel no longer lands on the track's
inner edge.)

### QML

```qml
// the segment rect, animated in its own 24-unit space
SequentialAnimation on x {
    running: busy          // bind to the wait, not to a timer
    loops: Animation.Infinite
    NumberAnimation { from: 5.2;  to: 12.8; duration: Timing.loader / 2; easing.bezierCurve: Timing.sweep }
    NumberAnimation { from: 12.8; to: 5.2;  duration: Timing.loader / 2; easing.bezierCurve: Timing.sweep }
}
```

In QML an SVG that uses `currentColor` needs an explicit fill: keep the source file as it is and
set the colour at render time, so a theme change repaints the loader together with everything
else.

`Timing.loader` and `Timing.sweep` are the QML mirror of the two CSS tokens — the same two
numbers, declared once, not repeated per component.

---

## 5. Rules that are not optional

**It stops the moment the value arrives.** Not on the next cycle boundary, not after a minimum
display time. A loader still sweeping after the data landed is lying about the state of the
system. This is why `running` binds to the wait itself (the property, the promise, the process
state) and never to a timer or to a `setTimeout` fallback.

**It sits beside the control that is waiting**, never in place of the glyph on the left of a
row. Replacing the glyph makes the row jump twice — once when the loader appears, once when it
goes.

**It never appears for waits the shell can predict.** If the duration is known, the correct
element is a determinate bar, not this icon. If the wait is under ~150 ms, show nothing: a
loader that flashes is worse than a moment of stillness.

**It carries no colour of its own.** The loader inherits the colour of the row it sits in —
usually `--text-muted`. It never takes `--active`, and a wait is not a warning state.

**Only one per capsule.** Three rows waiting inside one cell get one loader on the cell, not
three sweeping segments out of phase with each other.

---

## 6. Reduced motion

Under `prefers-reduced-motion` (and the equivalent QML setting) the segment **holds still at the
left end** — `x = 5.2`, the file's own resting state. The icon is still shown and still means
"not ready"; the shape alone carries that. Do not substitute a spinner, a fade, or a text label.

---

## 7. Quick checklist

- [ ] Segment travels exactly 7.6 units, nothing else moves
- [ ] Duration and easing come from `--t-loader` / `--ease-sweep`, never inline
- [ ] `running` is bound to the wait, not to a timer
- [ ] Animation stops on the same frame the value lands
- [ ] Loader sits beside the waiting control, layout does not shift
- [ ] Inherits `--text-muted`, no state colour
- [ ] One loader per capsule
- [ ] Reduced motion → static, segment at the left end
