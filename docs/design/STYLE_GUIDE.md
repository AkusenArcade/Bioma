# Bioma — style guide

Rules for every component. If a choice is not written here, decide it here before drawing it.

---

## 1. Principles

Six rules that come before every detail. When two options look equivalent, the one that
respects the higher principle wins.

**1. At rest it is silent.** Contracted cells show no numbers and no text. The only exceptions
are the clock and the active window title. The exact value arrives on hover, in a tooltip, and
leaves on mouse-out. What a cell shows at rest is its own decision — there is no single rule —
and a cell may disappear entirely when its domain does not exist: no device connected, no
notification, no battery.

**2. Motion is data.** Every animated indicator encodes a live value in the **rhythm** or the
**amplitude** of its movement. Animation at a fixed rate with no data behind it is decoration
and is not allowed: an indicator with nothing to say stands still, or is not there.
*State transitions are a separate case* — see §6.

**3. Colour is state, form is domain.** The beating ring is the CPU, the liquid is memory, the
orbiting satellite is the GPU. Colour never says what is being talked about; it says only how
hard it is working.

**4. Volume only where it is alive.** Tissues and cells are the support and stay flat. Gradient
goes on indicators, value digits, header icons and selected controls. No glow, anywhere.

**5. It is born from its point.** Every expanded shape grows from the node of the thread that
connects it to its origin, by animating width and height. No panels appearing from nowhere, no
scaling of content.

**6. Two voices.** Orbitron for machine measurements, Spectral for human language. A piece of
text always belongs to one of the two; if it is unclear which, it is probably badly written.

---

## 2. Typography

**Orbitron** — machine measurements. Squared eye, softened corners, weights to Black.
**Spectral** — human language: the clock, the window title, names of applications, cities and
months, notifications, descriptions, track titles.

Declare them as **roles**, technical and expressive, never by name: a machine without Orbitron
or Spectral should degrade, not break.

### Scale

| Size / weight | Use |
|---|---|
| 20 / 500 | primary value — `80%`, `23:12`, `16/32 GB` |
| 15 / 500, uppercase, +0.06em | titles and labels — `CPU`, `FORMAT`, `WEEK STARTS` |
| 13 / 400 | secondary values and names — `5.1 GHz`, `12%`, `1.6 GB` |
| 11 / 400 | metadata and placeholders — `Europe/Rome`, `UTC+2` |
| 700 | only for titles that touch Spectral text |

**Tabular figures always.** Without them the width dances on every update and the tissue
reflows for nothing.

**The 700 rule is for titles only.** A city name above a Spectral clock, `Workspace 1`, the
window title in the membrane. Values and metadata stay at their scale weights, or a list gets
heavy.

---

## 3. Colour — seven roles

Four interface roles and three state roles. The flat value is the mid-colour of the gradient:
it is what matugen generates and what thin line icons use.

### Interface

| Role | Value | Use |
|---|---|---|
| `background` | `#12160f` | fill of tissues and cells |
| `elevated` | `#1b2117` | raised surface |
| `cell` | `#232a1e` | cell fill before glass |
| `text` | `#eaf1e6` | content, labels |
| `text-muted` | `rgba(234,241,230,.56)` | secondary text |
| `border` | `rgba(255,255,255,.09)` | documentation borders, not shell surfaces |
| `line` | `#4f6340` | outlines and threads |
| `node` | `#6b8457` | thread ends, running marks |
| `rim` | `#8ba86e` | light on the top edge |
| `primary` | `#b9de6b` | icons, controls, selections, stateless indicators |
| `secondary` | `#3fbfa0` | supporting accents |

### State — fixed, hand-written, never generated

| Role | Value | Meaning |
|---|---|---|
| `calm` | `#6ee7a6` | low load, at rest |
| `active` | `#f2c14e` | under load, work in progress |
| `alert` | `#ff6b5d` | past threshold |

### Thresholds

| Range | State |
|---|---|
| < 30% | calm |
| 30 – 80% | active |
| ≥ 80% | critical |

Three states, two boundaries, **no dead zone**. Flicker around a boundary is not cured with
hysteresis but **upstream, on the reading**: values arrive already smoothed by a moving
average, the way the CPU beat does, and a measurement that does not jump does not make the
colour jump either.

Indicators that do not measure a load — timezone dials, the minute pie — use the primary and
never change colour.

**State colours are reserved for what the machine measures by itself.** A scale the user moves
— volume, brightness, colour temperature — is a control, so it uses the primary for its whole
travel, including at maximum. Red on a slider would mean "past threshold", and turning the
volume up is not an alarm.

---

## 4. Gradients

The gradient simulates light, it does not decorate. One source, from above, identical across
the shell.

- Fixed direction **165°**, from above and slightly from the left.
- Two tones of the **same hue**, luminance delta **~22%**: lighter at the top, more saturated
  and darker at the bottom.
- The rim is the only light allowed on surfaces: 1 px running from `#8ba86e` at the top to
  `#4f6340` at mid-height. It concerns the line only, never the fill.

| Token | Stops |
|---|---|
| `grad-primary` | `#ddf5a4 → #8cbb43` |
| `grad-secondary` | `#7fe3c9 → #23937b` |
| `grad-calm` | `#b0f7d0 → #36bf7e` |
| `grad-active` | `#ffe08f → #dd8f26` |
| `grad-alert` | `#ffa88c → #da3947` |

**Yes:** rings, beat, liquid, satellite; value digits; header icons; selected controls.
**No:** pill, panel, well and tissue fills; threads and nodes; thin line icons; reflections,
halos, coloured shadows, point lights.

---

## 5. Form and surfaces

Defaults. These are user settings: the design must hold at their extremes.

| Parameter | Default | Note |
|---|---|---|
| screen edge margin | 12 px | a thin frame, not a load-bearing surface |
| tissue → cell margin | 2 px | the tissue stays a line, not a panel |
| radius | 100% | full pill for anything one cell tall |
| **pill ceiling** | **110 px** | up to this height radius 100%, above it radius 20 |
| large panels | 20 px | fixed radius, not proportional |
| inner radii | outer − margin | concentric: a well 10 px inside a 20 px panel gets radius 10 |
| panel width | set by content | a panel is as wide as its job; symmetry is not a reason to narrow one |
| gap between shapes | 24 px | header–panel, capsule–capsule, capsule–panel |
| list rows | 30 px | icon 20 px, name in Spectral, value on the right |
| glass | blur 20 px | flat fill `rgba(35,42,30,.72)` |
| shadow | `0 14 28 / 45%` | only on invoked or expanded cells |
| threads | 1.3 px | `#4f6340`, nodes `#6b8457` at 2.5 px |

**The pill ceiling.** Up to 110 px the cap is narrow enough to stay a border, and the pill
applies to cells, pods and control capsules. Above 110 px the cap reaches sixty or eighty
pixels, stops being a border and becomes a shape that dictates the content, eating the corners
of images and lists. There, use the panel radius.

---

## 6. Motion

Shapes grow by animating **width and height** from the thread node. No scaling, so the 1 px rim
does not thin out, the radius does not deform and text never passes through a scale.

### Opening — 250 ms

- Sequence: mini indicators fade (0–50 ms) → header → thread → panel → capsules.
- Every shape still grows in **~100 ms**: the 250 ms is achieved by tightening the cascade,
  never by shortening the individual growths.
- Capsules start **16 ms** apart.
- Content enters **only once the shape is at size**: opacity plus 4 px upward. Text is never
  scaled.
- Overshoot `cubic-bezier(.2,.9,.3,1.15)` on small capsules only. On large panels it reads as a
  bounce: use a curve without overshoot.

### Closing — 150 ms

- Reverse order: content disappears first, then the shape retracts into its node.
- Curve `cubic-bezier(.5,0,.9,.5)`, no overshoot.
- The asymmetry is intentional: it opens calmly, it closes quickly.
- Animations are **reversible from wherever they are**, never queued: invoking a cell
  mid-opening sends it back, it does not restart.
- All durations live in **one named timing set** — open, close, debounce, reflow, theme
  transition, auto-hide, notification dwell.

### The side is inherited from the parent tissue

A cell anchored left grows to the right; anchored right it holds its right edge and widens
leftwards; in the floating centre tissue it widens from both sides. The node of the first
thread is always on the side the cell was born from.

### State transitions are a separate case

An icon that moves when a state changes — the two workspace bars shifting one step on workspace
change, 180 ms — is not an animated indicator: there is no live value in the rhythm, there is an
event. It is still the rest of the time, and that is exactly why it is noticed. It earns its
place when the command comes from the keyboard and the eye is not on the membrane.

### Indicator rhythms

| Indicator | Form | Rhythm |
|---|---|---|
| CPU | ring + beating dot | beat = frequency, 45–140 bpm on a moving average · colour = load |
| RAM | ring filled with liquid | level = memory used · continuous wave, 2.4 s cycle |
| GPU | ring + orbiting satellite | rotation = frequency · colour = utilisation — two different quantities |
| Battery | level rising or falling **horizontally** | exists only if the machine has a battery; distinguishes it from RAM |
| Minutes | dial filling | 60 s, then restarts empty |
| Critical | wave emitted by the ring | 0.9 s cycle, expands and fades |

---

## 7. Components

### Membrane, tissue, cell

The membrane is one edge of one output. It owns **auto-hide**; the cells on it do not have
their own rule. A tissue is a group with one anchor and a percentage of the edge. A cell is the
unit: 40 px tall contracted, full pill radius, flat glass fill, 1 px rim with the light at the
top.

### Capsules and panels

A **capsule** is a pill-shaped surface in an expanded cell: pods of 236 × 108, the visualiser
capsule at 372 × 88, category capsules at 160 × 44. A **panel** is a rectangular surface, radius
20, for lists and anything with rectangular content. Inside a panel, **wells** hold rows: radius
10 (concentric), flat darker fill `rgba(24,30,20,.8)`.

### Vertical capsules

The interface's pills are normally horizontal, but the mark is a vertical pill and it is a rare
sign in interfaces. It is worth bringing inside, on the condition that it is a content decision
and not a flourish.

**Yes:** one indicator above a value read top to bottom; a column of short switches; tissues on
a side membrane, where a vertical capsule is the natural form; columns of symbols only —
numbers, icons, levels — where no text appears.

**No:** with long text or proper names, which a narrow column sends into ellipsis; beside
horizontal capsules of the same family, where two orientations read as a misalignment; for a
label-and-control pair, which is wide by nature; as an aesthetic variant of a capsule that
already works horizontally.

As soon as names are needed next to the symbols, the right form goes back to a rectangular
panel — that is what happened with the workspaces.

Minimum width 84 px. When the column is made of repeated round elements, the **first and last
are concentric with the caps**: the cap radius is the element radius plus its margin. Horizontal
threads attach at that centre.

### Threads

Threads **touch the edge** of both shapes. A thread stopping two pixels short makes the shapes
look placed against each other rather than connected: compute them from geometry, never place
them by eye. The attachment is always at the **centre** of the shape being connected: vertical
centre for horizontal threads, cap centre for vertical ones.

### Controls and selection

- A **segmented** control's selection change is animated: the pill **slides** to the chosen
  option with the opening timings; it does not vanish on one side and appear on the other.
- The **switch** moves its knob instead of swapping two images, and the **slider** follows the
  finger without steps. These are the only movements in the shell that answer a gesture; without
  them the interface looks broken rather than restrained.
- The selected pill carries the primary gradient; the track and the well stay flat. A selected
  control is not a surface and does not take the rim.
- **Errors live where they happened.** A field that rejects what it received turns its outline
  to the alert colour and carries a line with the reason underneath, in Spectral: no dialog, no
  notification. And it **does not clear itself** — making someone retype is a punishment, not
  information.
- A **radio dot** appears only where the choice is exclusive. On a multi-select list it would
  lie: it is the fastest way to make someone believe that connecting one device disconnects
  another.

### Icons

See `icons/README.md`. In short: grid 24, live area 20, stroke 1.5, round caps and joins,
radius 3 on rectangles, no fills except nodes, must survive 16 px. Primary gradient when the
icon is a header or an active control; muted text when inactive or a fallback; never a state
colour, because an icon measures nothing.

---

## 8. Before drawing a component

Seven questions. If one has no answer, the component is not ready to be drawn.

1. What does it show at rest? If it contains a number, is it needed, or is a changing shape enough?
2. What state does it measure? If it does not measure a load, the indicator is primary and never changes colour.
3. What point does it grow from when it opens, and which thread connects it to the contracted cell?
4. Which texts are machine and which are human? Proper names go in Spectral, always.
5. Where does it land in the opening cascade, and how far from the previous shape?
6. Does it hold the defaults at their extremes: radius 0%, 12 px margin, long text with ellipsis?
7. Are the controls real elements — button, switch, field with label — even in the mockup?
