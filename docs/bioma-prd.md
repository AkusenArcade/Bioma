# Bioma — Product Requirements

A Wayland desktop shell built as independent, living surfaces rather than a bar.

Target compositor: Niri. Toolkit: Quickshell (Qt/QML).
Language: English throughout — code, config keys, UI strings, comments.
The project name **Bioma** is the only Italian word retained.

Status: design closed, implementation not started.
Companion document: `bioma-spec.md` (design rationale, in Italian — working
material, not a source of strings).

---

## 1. Vision

The machine is an organism. Bioma shows its vital signs.

Where other shells display a bar that is always present and always saying
everything, Bioma is a set of surfaces that appear when they have something to
say, animate in proportion to what they measure, and go quiet when nothing is
happening. The composition of the desktop changes with the state of the machine.

## 2. Scope

**In scope.** The shell surfaces, their behaviour, their configuration, and the
generation of a colour palette that other applications can consume.

**Out of scope for v1.**
- Theming third-party components: cursor themes, GTK icon themes, system UI
  fonts. Bioma themes itself. (Working code for this exists in Prisma and can be
  ported later if wanted.)
- Lock screen / greeter — use an external one. A bug here locks the user out of
  their session.
- Localisation. English only; the i18n layer from Prisma is deliberately dropped.

**Palette propagation is in scope.** Bioma owns the palette and renders it to
other applications through matugen templates plus reload hooks. Bioma never
parses or rewrites another program's config file for theming purposes.

> Known limit: GTK3 applications accept a generated `gtk.css` fully; GTK4 and
> libadwaita applications accept far less. This is a platform limit, not a bug
> to be fixed in Bioma. Document it, don't fight it.

---

## 3. Principles

These are decision rules, not slogans. When a design question arises, it should
be resolvable by reference to one of these.

1. **At rest, the interface does not speak.** No numbers, no text in contracted
   cells. Exceptions: the clock, the active window title, media track metadata,
   and notification content. Icons are not text — they are symbols recognised by
   shape.
2. **Movement means something.** Every animated indicator encodes a live value in
   the *rate* or *extent* of its motion. Motion at a fixed rate with no data
   behind it is decoration and is not permitted. An indicator with nothing to
   report is still, or absent.
3. **Colour says state, form says domain.** Three indicators of the same shape
   are indistinguishable without labels. Domain is carried by form and rhythm;
   load is carried by colour.
4. **A cell exists when it has something to say.** Conditional presence is the
   default, not the exception.
5. **Expanded forms grow from their origin.** Nothing appears from nowhere.
6. **Volume is reserved for what is alive.** Surfaces are flat. Gradients belong
   to indicators and active controls only.
7. **Vocabulary, not presets.** The system offers composable rules; the user
   composes. The shipped default demonstrates a sensible composition.

---

## 4. Structural model

Three levels: **membrane → tissue → cell**. Each level knows only the one below.

### 4.1 Membrane

One edge of one monitor (e.g. `monitor 1 / top`). Tissues anchored to that edge
share its length.

| Property | Behaviour |
|---|---|
| `reserve_space` | Whether the membrane cedes a strip to the window layout. **Only horizontal edges (top/bottom) may reserve.** Geometric rule, no exceptions. |
| `auto_hide` | The membrane slides out of view and reveals on pointer-at-edge. Implies `reserve_space: false`. |
| `scale` | `compact` \| `normal` \| `comfortable` |

These two settings govern **every tissue and cell on that membrane**, including
the dock. Hiding a membrane hides everything on it.

- Tissue widths on a membrane are percentages that **must not exceed 100 in
  total**. Exactly 100 is not required; unused space stays empty. Above 100 the
  system warns.
- **Collision between tissues on the same membrane is impossible by
  construction.**
- Percentages are **ceilings, not reservations**.
- When `reserve_space` is on, the strip is reserved **even while a conditional
  cell inside is invisible** ("slot" model), so windows never reflow.
- An auto-hidden membrane must **remain present as a surface** with a few-pixel
  reveal zone — it cannot be destroyed and recreated, or nothing would catch the
  pointer at the edge. Reveal: pointer at edge. Hide: timed, after the pointer
  leaves the membrane area; the delay comes from the global timing set.

### 4.2 Tissue

A positioned container. Owns anchor, margins, orientation, monitor, max width,
and the ordered list of its cells.

- **Anchored** tissues belong to a membrane and declare a percentage.
- **Floating** tissues sit free on screen and use anchor + margins instead; no
  membrane to share. Floating tissues may overlap; this is not prevented.
- `orientation`: horizontal or vertical. The same unit serves a top strip and a
  side column.
- Background surface with configurable opacity, **not blurred**.
- Inner padding configurable **2–12 px**. The tissue background is a *surface*,
  not a border: at a wide margin the band reads as a tray.

### 4.3 Cell

A unit of content with one domain. No position of its own, no max width of its
own: it takes what the tissue grants.

- Cells always have their own background, with configurable opacity **and blur**.
- Cells declare their visibility rule and their domain options.

### 4.4 Layout rules

- **Growth moves away from the anchor.** Corner tissue → stacking inward, so
  existing cells never shift when a new one appears. Centre tissue → symmetric
  redistribution. One rule, two anchors.
- **Fixed order, variable position.** The declared order never changes. In a
  mixed tissue, a cell appearing reflows the whole tissue, including
  always-visible cells. Deliberate: the tissue always behaves the same way.
- Dynamic vs static placement is **derived, not configured**: a cell that never
  disappears never moves, because its neighbours never disappear.
- **Elastic cells** take the remaining space. With more than one elastic cell in
  a tissue: equal share, each capped by its own limit, remainder redistributed.
  (A per-cell weight may be added later; keep the width field an object, not a
  bare number, so this stays possible.)
- **Minimum width per cell.** Below it the cell prefers not to appear rather than
  appear illegible. Text cells fall back to ellipsis. A generous minimum also
  prevents small content changes from producing motion.
- **Reflow transition is a design moment**, not an incidental animation. If it is
  abrupt the desktop reads as nervous rather than alive.

### 4.5 Scale and units

**All dimensions are logical units**, never physical pixels — the equivalent of
Android `dp` / iOS `pt`.

Wayland provides this natively: the compositor reports each surface's output
scale factor (1, 2, or fractional such as 1.25 / 1.5) and Qt exposes it. Write as
though the factor were 1. Moving a cell between monitors rescales it
automatically.

- **Scale is a discrete step set, not a free value**: `compact` / `normal` /
  `comfortable`, tuned against real content. Contracted content is designed for
  defined proportions; a free height would only let the user break it.
- Scale is a **membrane** property, so a smaller second monitor can use
  `compact`.
- **Density and scale are separate.** Density brings everything to the correct
  physical size; scale is an aesthetic preference layered on top. It multiplies,
  it does not replace.
- **Fractional scaling caveat**: logical units do not land on whole pixels, so
  hairlines (1 px borders, thin icon strokes, connector threads) blur. Round
  **only critical dimensions** to the physical pixel; leave layouts fluid.

---

## 5. Visibility and temporal grammar

Three visibility types. This is the central field of the configuration.

| Type | Appears | Disappears | Keyboard focus |
|---|---|---|---|
| **always** | never hidden | never | no |
| **conditional** | condition becomes true | condition lapses | never |
| **invoked** | shortcut | same shortcut, Escape, or click outside | yes |

Types combine: the same cell may be conditional *and* invocable.

**Consequence**: launcher, session menu and settings are not a separate category
— they are cells whose visibility is `invoked`. The system needs no second model
for them.

### 5.1 Conditional parameters

No per-cell logic. Three parameters on the condition:

- **Dual threshold (hysteresis)** — distinct enter and exit values, so the state
  does not flicker around a boundary. Applies to **every** boundary, not only the
  critical one.
- **Confirm delay** — how long the condition must hold before appearing.
- **Dwell time** — how long the cell remains after the condition lapses.

Confirm and dwell are **asymmetric**: appear promptly, leave slowly.

### 5.2 System rules

- **Interaction suspends disappearance.** If the user is interacting with a cell
  when its condition lapses, it does not vanish under their hands. On pointer
  exit the timer **resumes where it stopped**; it does not restart, or a stray
  hover would keep the cell alive indefinitely.
- **Anti-flicker**: highly intermittent cells (volume OSD) either get a longer
  dwell or live in a tissue of their own, so they do not make neighbours dance.
- **Invoked cells acquire keyboard focus** and release it on close. An expanded
  conditional cell may also need focus for a text field (Wi-Fi password) — the
  expansion must be able to request focus and give it back.
- **Animations are reversible from their current state**, never queued. Invoking
  a cell mid-open must reverse smoothly, not restart or strand the sequence.

---

## 6. Visual language

### 6.1 Colour — six roles

| Role | Source | Use |
|---|---|---|
| `background` | theme source | tissue and cell fills |
| `text` | theme source | content, labels |
| `primary` | theme source | icons, controls, selections, stateless indicators |
| `secondary` | theme source | supporting accents |
| `calm` | **fixed** | low load, at rest |
| `active` | **fixed** | under load, work in progress |
| `alert` | **fixed** | past threshold |

Six is the count the user enters by hand. **All other roles are derived in
code** — elevated surface, muted text, borders, shadows — by shifting the
background's luminance and modulating text opacity. Derived roles cost the user
nothing and stay coherent by construction; the relationship between background
and elevated surface is exactly what gets set wrong by hand.

Light or dark is **inferred from the background's luminance**, not configured.

**The three state roles never come from matugen.** They are a semantic code; a
blue wallpaper would turn them into three blues and the code would stop
speaking. Declare them by hand in **two variants, light and dark** — the same
hex values lose contrast on a light background, amber especially. Six values,
written once.

This also resolves the fact that `active` has no Material You counterpart: it is
not supposed to have one.

**Theme sources** (feeding the four interface roles only):

1. **matugen** — wallpaper-reactive. matugen writes a file into the config
   directory via template; the shell watches it (`FileView`) and hot-reloads.
   The four roles map one-to-one to `surface`, `on-surface`, `primary`,
   `secondary`. No direct dependency on matugen.
2. **Manual palettes** — a small set shipped by default, each **a data file, not
   code**, so palettes can be added without touching the shell. A manual palette
   defines only the four interface roles.

**Palette changes are animated, never instantaneous.** Colour must be an animated
singleton, never a value copied into cells — this is what allows the theme cell
to retint the whole desktop live on hover.

### 6.2 State thresholds

| State | Range |
|---|---|
| calm | 0–30% |
| active | 31–70% |
| critical | 71–100% |

Nominal values; hysteresis applies to both boundaries per §5.1.

### 6.3 Typography

Two registers.

| Register | Font | Use |
|---|---|---|
| Human language | **Spectral** | clock, window title, track metadata, notification body, place and month names |
| Machine measurement | **Barlow** | percentages, frequencies, memory, labels, controls |

Rule for future cells: **if the string came from a human, Spectral; if the system
measured it, Barlow.**

- Declare fonts as **roles** (`technical` / `expressive`), not by name, so a
  machine without Barlow and Spectral degrades rather than breaks.
- Continuously changing figures use **tabular numerals**, or width dances on
  every update and the dynamic tissue reflows for nothing.
- Because contracted cells are nearly textless, **Spectral is more visible than
  Barlow at rest**. The serif ends up defining the shell's identity.

### 6.4 Icons

A dedicated set, drawn for the project.

**Style** — soft but not playful. The binding constraint is that icons must sit
beside **Spectral**; Barlow is forgiving, a literary serif is not.

- uniform stroke weight, thin-to-medium
- rounded terminals with a **small radius**: softness lives in the stroke's cut,
  not in the silhouette
- geometrically precise forms, never bulbous
- **vertical proportions, not squat** — Spectral has a slender x-height to
  ascender ratio; wide low icons read as belonging to another system
- optical weight **slightly lighter than adjacent text**, so icons read as signal
  rather than as a word

**Method** — fix the shared parameters first (stroke, terminals, grid, how far
curves depart from the geometric); draw them **beside the text they will live
in**, not on an isolated grid; declarative SVG using colour roles so icons follow
palette and theme transitions; draw the ~10 always-present symbols first and
start from an existing set for the rest.

Scope note: a complete set (network, bluetooth, battery, volume, media, power,
tray categories) is easily a hundred symbols, and application tray icons will
remain in third-party styles regardless.

### 6.5 Form

- **Radius**: one configurable value as a **percentage**, 0 = rectangle,
  100 = pill. The cell's radius is the tissue's minus the padding, so concentric
  corners are automatic at every value. Clamp: radius may not exceed half the
  smaller dimension, and the cell's radius may not go below zero.
- **Contracted regular, expanded organic.** Contracted cells are always regular
  forms — this is what makes the cells read as a family. Expanded cells have a
  composite silhouette.
- The expanded silhouette is **constructive, not hand-drawn**: it derives from
  the shapes of its own content. This keeps it a rule, so it applies to cells
  added in future without violating the requirement that a new cell costs one
  config block.

**Decided: threads, not metaball.** Each content area is a **separate floating
shape**; shapes are joined by **1.3 px threads** with **nodes** at their ends and a
barely-suggested curve. Metaball soft-union silhouettes are rejected.

Consequences, all favourable:
- Blur shapes stay simple — one region per shape, not one arbitrary silhouette.
- Layout bounding boxes stay rectangular and predictable.
- The visual family holds: shapes remain regular, only their arrangement is
  organic.
- Biologically it still reads: organelles joined by cytoskeleton.

Implementation note: threads at 1.3 px are exactly the "critical dimension" case
of §4.5 — round to the physical pixel under fractional scaling or they blur or
vanish. Thread drawing animates via stroke dash offset; QML `ShapePath` exposes
an animatable `dashOffset`.

The full-screen reference mockups predate this decision and show the metaball
direction — treat them as stale on silhouette, current on composition, palette
and at-rest density.

### 6.6 Blur

Niri supports blur from 26.04 via the `ext-background-effect` protocol, already
supported by Quickshell.

- **Do not use compositor layer rules** — they blur the entire layer including
  transparent regions, i.e. the gaps between cells.
- **Use `ext-background-effect`** — blur follows exactly the shape the client
  declares. Blur shape becomes a property of the cell, like radius.
- **Blur applies to cells only, never to the tissue background.** Declare only
  the cell shapes as blur regions.
- Consequence: the padding band reads **sharper** than the cells. At high tissue
  opacity this is invisible; at low opacity it is a pronounced effect.
- The tissue background must be drawn **only in the band**, punching out the cell
  areas. Otherwise cell blur is seen through two layers and cell opacity stops
  meaning what it declares.
- **xray is a configuration option**, not a fixed choice. On: a static blurred
  copy of the wallpaper — efficient, but blurs the wallpaper even when windows
  are underneath. Off: blurs actual underlying content — visually correct, more
  expensive, still experimental. Note: with xray, contrasted wallpapers can show
  wallpaper-coloured pixels along antialiased rounded edges.

### 6.7 Expansion and animation

Two distinct expansions:

- **Lateral** — an elastic cell grows within its own vertical space (window
  title). This is not a separate animation: it is the tissue reflow already
  defined.
- **Panel** — growth from the cell's anchor point. No pre-collapse: the
  contracted content is **entirely replaced** by the expanded content. Stagger
  the outgoing and incoming content slightly; simultaneous crossfade reads as
  overlap.

In both cases **expansion goes over windows, never into reserved space.** The
window layout never reflows for an expansion.

**Technique — decided.** Grow by animating **width and height**, never
`transform: scale`. Scale is cheaper but deforms everything inside: the 1 px
lit border changes thickness throughout the growth, corner radii distort, and
text is stretched and blurred. Since the lit border is the signature of Bioma's
surfaces, scale is disqualified.

- The shape grows by size; **content enters only once the shape has reached its
  size**, via opacity plus a 4 px upward translation. **Text is never scaled.**
- Do not mix techniques within one animation — the difference is visible when
  the two sit side by side, which is exactly where they sit.
- Overshoot (`cubic-bezier(0.2, 0.9, 0.3, 1.15)`) is appropriate on small
  capsules and **not** on large panels, where it reads as a bounce and conflicts
  with the intended serious register.
- Cost note: animating size relayouts each frame. Irrelevant at this scale. If a
  future cell proves heavy, the remedy is local to that cell.

**Timing.** Opening ~250 ms, closing ~150 ms. The asymmetry is intentional. Reach
250 ms by tightening the cascade, **not** by shortening individual growth: each
shape still grows over roughly 100 ms, phases overlap more, and capsule stagger
is ~16 ms rather than 25.

Reference sequence (vitals): mini indicators fade out (0–50 ms) → header grows →
connector draws → panel grows → capsules stagger in.

**All durations live in one named timing set** — open, close, stagger, reflow
transition, theme transition, auto-hide delay, notification dwell. Never
scattered constants. This is also what makes a user-facing "animation speed"
setting possible later.

---

## 7. Configuration

**Format: JSON.** QML reads and writes it natively, no parser, no dependency. It
is less pleasant to hand-edit than TOML, but that is precisely the drawback the
settings UI removes — and a TOML rewritten by code would lose the user's comments
and formatting on every save.

**Layered, because both a human and the UI write it:**

1. **base file** — hand-written, version-controllable in dotfiles
2. **override file** — written by the settings UI, loaded last, wins

Design this in from the start; adding it later means redoing all loading.

**Schema requirements**

- Per membrane: monitor, edge, `reserve_space`, `auto_hide`, `scale`, tissues.
- Per tissue: membrane + percentage (or anchor + margins if floating), margins,
  orientation, padding, opacity, ordered cell list.
- Per cell: type, enabled, visibility rule (thresholds, confirm, dwell if
  conditional; shortcut if invoked), min width, domain options.
- Global: radius percentage, cell opacity and blur, xray mode, font roles, theme
  source, manual palette, timing set.
- Keys and identifiers in English; structural terms `membrane`, `tissue`, `cell`.
- **Adding a new cell must cost one config block**, never a structural change.
- The default file is **commented in English**, explaining the biological terms —
  `cell` in a layout context can be misread as a grid cell.
- The default must be functional and demonstrate the vocabulary, not be
  exhaustive.

---

## 8. Services

A **singleton per domain**: one source, many consumers. Never a poller per cell.

Prisma (the predecessor Quickshell shell) has a near-complete service layer.
Snapshot supplied separately; source last modified 8 May 2026, **not under
version control**, so expect Quickshell API drift and treat this as
copy-and-adapt, not merge. Port services **individually into the new structure**
and verify each without UI before building cells on them.

| Service | Prisma source | Notes |
|---|---|---|
| Niri IPC | `services/NiriIPC.qml` | Complete: workspaces, windows, outputs, focus actions, `reload-config`. Feeds window title, workspaces, screenshot-window mode. Push-based event stream — not polling. |
| Wallpaper | `services/WallpaperService.qml` + `bar/WallpaperWindow.qml` | **Port as-is.** Native QML rendering on a Background-layer `PanelWindow`, no external daemon. Three modes: single, **span**, per-monitor. Span scales the image to the total bounding box and translates negatively with clip, so each monitor shows its portion. Persisted. |
| matugen | `services/MatugenService.qml` | Already adapted to matugen 2.x `scheme-tonal-spot` format. |
| System monitor | `services/SystemMonitorService.qml` | CPU/RAM/process. **GPU sampling must be added** and is the only expensive one: use a persistent process, never a new process per sample. |
| Audio | `services/AudioService.qml` | Per-application volume requires following PipeWire nodes as they come and go — more work than the rest of that cell combined. |
| Network | `services/NetworkService.qml` | Wi-Fi + ethernet via `nmcli`. |
| Notifications | `services/NotificationService.qml` | See §9 blocking note. |
| Brightness | `services/BrightnessService.qml` | |
| Screenshot | `services/ScreenshotService.qml` | `grim`, `slurp`, **and `tesseract` OCR** already wired. |
| Media | `services/MediaService.qml` | MPRIS. |
| Monitor layout | `dashboard/MonitorManager.qml` | Drag-and-drop with magnetic snap; writes `niri.kdl` preserving non-output sections. Substantial, working. |
| Keybinds | `settings/pages/KeybindsPage.qml` | Parses the `binds` block, writes, calls `niri msg action reload-config`. |
| OSD | `osd/VolumeOSD.qml`, `BrightnessOSD.qml`, `WorkspaceOSD.qml` | Working. Resolves the open question of whether OSDs are affordable. |

### 8.1 Porting method

Prisma's source lives in the author's development directory and will be pointed
at directly; the snapshot in `prisma-pack/` documents its state as of
2026-09-17 (sources last modified 8 May 2026).

**Work into the new structure, never out of the old one.** The instruction is not
"open Prisma and take what is reusable" — that pulls across more than needed, and
the bar-centric architecture comes with it. Define the destination first, then
ask for a specific capability: *"I need desktop-file icon resolution and
open-window tracking; look at how Prisma does it and bring it here."*

**Inventory before writing.** The first pass over Prisma produces a written
inventory and no code: which services exist, what each actually does, which are
self-contained and which are entangled with `Bar.qml`. This is needed regardless,
and it is where it becomes clear whether a piece is clean or knotted.

**Rules**

- Port **service by service**, verifying each without UI before any cell depends
  on it. A service that silently returns stale data is far harder to diagnose
  once there is a face on top of it.
- **Keep services and presentation separate.** Services talk to the system and do
  not care whether a bar or a cell sits above them; presentation is being
  redesigned deliberately and is not ported. If a Prisma service is entangled
  with its widget, disentangling it is the work — and it is worth doing.
- **Expect API drift.** Prisma's sources are four months old and Quickshell moves
  quickly; a deprecation warning is already recorded in its `PROGRESS.md`.
- **No version control history.** Prisma is not under git, so this is
  copy-and-adapt, not merge. There is no incremental path and no diff to review.
- **Do not import wholesale.** Open a fresh repository organised around cells, and
  bring files in one at a time. The same amount of code ends up reused, but from
  the right structure.
- A `CLAUDE.md` in the new repository stating what the project is — *independent
  cells, not a bar* — prevents falling back into the old model session by
  session.

**Reference documents inside the snapshot**: `CLAUDE.md` (architecture) and
`PROGRESS.md` (feature status, including fixed bugs worth not re-introducing —
dock reveal zone inside surface bounds, file-picker layer ordering, ethernet
detection race).

**Do not port**: `bar/Bar.qml` (bar-model monolith), `bar/SysStats.qml` (numeric
CPU/RAM readout — the opposite of Bioma's indicators), `services/I18n.qml`
(English-only project).

**Low reuse value**: `launcher/*` — substring match over name/genericName/id with
alphabetical sort. Functional, but fuzzy matching, frequency ranking and icon
resolution are absent, and those are the launcher.

**Blocking constraint — notifications.** `org.freedesktop.Notifications` has one
owner per session. Bioma's notification cell **cannot be tested alongside another
running shell**; the other shell's notifications must be disabled first. This
determines build order (§10). Tray is more tolerant (the spec allows multiple
hosts on one watcher) but verify. Network, bluetooth, MPRIS and vitals are
read-only and coexist freely.

**Full-screen input surface.** A transparent full-screen surface that receives
input is required by three features: click-outside-to-close, pointer-positioned
cells, and Bioma-styled screenshot region selection. Wayland gives a client no
way to query pointer position, so this surface is how it is obtained. **It is the
single most uncertain piece in the project — prototype it early.**

---

## 9. Cell catalogue

### 9.1 Window title

- **Contracted.** App icon + title. Elastic width with a declared minimum, capped
  as a percentage of screen width. Title in Spectral.
- **Expanded.** None.
- **Visibility.** Conditional: disappears entirely when no window is active.
- **Interaction.** Click → Niri action that centres the window on screen. Verify
  the exact action name against the installed Niri version; the IPC has changed
  across releases.
- **Notes.** Titles change constantly (browsers rewrite on every tab) — debounce
  and transition the text change, or it flickers and reflows the tissue. Icon
  resolution from the desktop file via the app-id Niri reports needs a decided
  fallback glyph; some windows will never resolve (missing desktop file, Wine).

### 9.2 Vitals

- **Contracted.** Animated indicators only, **no figures**. Exact value on hover
  (tooltip).

  | Domain | Form | Motion encodes | Colour encodes |
  |---|---|---|---|
  | CPU | ring + beating dot | beat rate = clock | load state |
  | RAM | circle filling with liquid | fill level = memory used | occupancy state |
  | GPU | ring + orbiting satellite | rotation speed = clock | utilisation state |
  | Battery | fill level | charge | charge state |

  - **GPU**: rotation and colour encode *different* quantities (clock and
    utilisation) which can diverge — a GPU at 30% may be at full clock. State
    this explicitly or it will be implemented as one value. This is the system's
    most expressive case: a fast green satellite means "working quickly without
    strain", which no percentage conveys.
  - **RAM at 100%**: the circle fills completely and the wave disappears. It must
    not go still — it pulses in the alert colour. It remains a **disc filled edge
    to edge**, never a dot inside a ring, or it becomes indistinguishable from a
    critical CPU exactly when the user needs to tell them apart.
  - **Battery** has a *presence* condition, not just a state condition: it exists
    only if the machine has a battery. Vitals therefore shows three indicators on
    a desktop and four on a laptop, from the same cell — the first cell whose
    composition varies with hardware. While charging the direction inverts: the
    level rises rather than falls.
  - **CPU beat mapping**: do not use a fixed ratio. 5 GHz → 50 bpm is elegant but
    makes an 800 MHz idle an 8 bpm beat, which reads as dead rather than calm.
    Map the useful clock range onto a legible cardiac range, roughly 45–140 bpm.
    A **moving average is mandatory** — real clock oscillates heavily with
    per-core boost, and without smoothing the beat is arrhythmic.

- **Expanded.** Search field, process list with kill, one capsule per domain
  (including battery, with charge state and time remaining).
  - Process list sorted by **RAM by default**; clicking an indicator re-sorts by
    that domain. The indicator doubles as a control without adding an element —
    but the active sort must be visible, or the user opens the cell not knowing
    what it is sorted by.
  - **Kill requires confirmation.** The confirmation is not a dialog from
    nowhere: it grows from the row being terminated (principle 5).
  - Full process management is an application, not a widget. Stop at top-N by
    CPU and RAM with search and kill.
- **Visibility.** User choice between **always visible** and **conditional on a
  vital reaching critical**. Also invocable.

### 9.3 Workspaces

- **Contracted.** Current workspace only — its name if it has one (Spectral,
  human language), otherwise its number (Barlow). Width changes only on
  workspace change; a minimum width stabilises the tissue.
- **Expanded.** Vertical list of open workspaces; click to jump. **First case of
  vertical orientation in the system** — good test of the tissue's orientation
  property.
- **Visibility.** Always.
- **Open**: with multiple monitors, does the list show this monitor's workspaces
  or all, grouped by monitor? On Niri the latter is more useful — jumping to a
  workspace on another screen is a normal operation.

### 9.4 Sinestesia (audio visualiser + media)

- **Contracted.** Visualiser, plus track metadata as text when available
  (Spectral). If there is no named source, the visualiser alone.
- **Expanded.** Larger visualiser, cover art and title, transport controls below.
  A dropdown to select among multiple players when more than one is present.
- **Visibility.** Conditional **on audio signal**, not on MPRIS playback — so
  audio from sources without metadata (browser video, games) still raises the
  cell. Hysteresis and a few seconds of dwell are required, or a gap between
  tracks makes the cell flicker.
- **Notes.**
  - **Two independent inputs**: the audio signal feeding the visualiser, and the
    MPRIS source providing metadata and controls. Changing player changes the
    second only — the visualiser keeps showing everything leaving the system.
    Without this stated they will be implemented as one thing.
  - Existing code: **Sinestesia** is an existing Rust + GTK4 application by the
    author. **Split it in two**: capture + FFT as a headless process emitting
    bands over stdout or a unix socket, rendering as a consumer. This is worth
    doing in every scenario and prevents two processes both capturing audio.
    Whether the existing renderer ports depends on whether it draws with a
    shader (portable to a QML `ShaderEffect`) or with Cairo / GTK4 snapshot
    (not portable).
  - Title changes per track and reflows the tissue. Max width with ellipsis, and
    scroll on hover rather than perpetually.

### 9.5 Volume and audio

- **Contracted.** Graphic indicator, reacting in real time to the wheel.
- **Expanded.** Input and output device selection, plus **per-application volume**
  (the expensive part — PipeWire nodes appear and disappear constantly).
- **Visibility.** Always, or invoked. When invoked, it opens as a floating
  tissue centred on screen — note this is the *same cell*, not a second
  implementation.
- **Open**: with visibility set to invoked, turning the wheel has no feedback. A
  system-wide OSD would fill this gap. Deferred deliberately — it is a system
  decision affecting brightness and others too, not a property of this cell.
  Prisma's OSD components exist and can be ported when decided.

### 9.6 Utility (capture)

- **Contracted.** Icon only — the first purely functional cell, with no state to
  represent.
- **Expanded.** Mode selection: **full screen / window / drawn region**, for both
  screenshot and video. Available as a membrane cell and as an invoked floating
  tissue: same implementation, two placements.
- **Screenshot.** Result goes to the **clipboard and the screenshots folder**.
- **OCR.** Separate mode. Recognises the selected region, text to clipboard.
- **Video recording.**
  - No audio. H.264 High Profile, 60 fps, MP4 container.
  - On AMD, `wl-screenrec` with VAAPI covers both region and full screen with
    hardware encoding — one backend suffices. `wf-recorder` as fallback.
    (`gpu-screen-recorder` cannot record an arbitrary sub-region and is only
    preferable on NVIDIA.)
  - **Recording has duration, unlike a screenshot** — therefore a conditional
    cell appears while recording, showing elapsed time and a stop control. This
    pattern is validated by an equivalent plugin in the field.
  - On stop: **save or discard**. Record to a temporary directory and move to the
    final location only on save, or a discarded video still lands among the
    user's files. The confirmation grows from the cell being closed — the same
    pattern as the kill confirmation.
  - **H.264 requires even dimensions.** A hand-drawn selection can produce odd
    numbers; round the region before passing it to the recorder or encoding
    fails. This surfaces only at implementation time if not stated.
  - Region coordinates are **physical pixels**; full-screen capture multiplies the
    output's logical geometry by its scale. Convert before passing on.
- **Selection UI is Bioma's own**, not `slurp` — it reuses the full-screen input
  surface (§8) and keeps Bioma's visual identity across the whole screen. Capture
  itself still uses `grim` / the recorder; what is built is the selection layer
  above it.
- **Window mode** needs window geometry from the Niri IPC — the third cell
  depending on that service.

### 9.7 Theme and wallpaper

- **Contracted.** The current palette as a live, attractive indicator —
  representative of the system's state rather than a static icon.
  - **Open**: does it animate continuously or only on theme change? Continuous
    motion with no data behind it is exactly what principle 2 forbids elsewhere.
- **Expanded.** Wallpaper preview with swatches of the palette derived from it.
  A **matugen on/off toggle**. With matugen off, selection among a small set of
  predefined palettes.
- **Visibility.** Invoked (and optionally always, as an icon).
- **Notes.**
  - Predefined palettes are **data files**, one per palette, so palettes can be
    added without touching the shell.
  - Wallpaper folder is a config value; **thumbnails must be generated and
    cached** or a folder of fifty images stutters on open.
  - Wallpaper modes — fill, fit, **span**, per-monitor — are requirements, ported
    from Prisma, not designed here. The wallpaper is "which image *and how*".
  - Palette propagation to GTK and Niri via matugen templates plus the
    `colors_changed` hook. Prisma already writes to `niri.kdl` and calls reload.

### 9.8 Session menu

- **Contracted.** Avatar only.
- **Expanded.** Large avatar with the option to change it, plus lock, suspend,
  reboot, shut down, log out.
- **Visibility.** Always, or invoked.
- **Notes.** The user avatar lives in AccountsService and must be written over
  DBus, not by copying a file — more work than it appears for a function used
  twice. Mark it optional, not first-pass. Lock delegates to an external lock
  screen for now.

### 9.9 Dock

- **Contracted.** Running applications **and** pinned applications, separated by
  a divider (as in Prisma).
- **Visibility.** Always, within whichever membrane it is placed on. **Auto-hide
  is not a dock property** — it belongs to the membrane, so the dock's behaviour
  follows the membrane it lives on, along with every other tissue there.
- **Notes.** Prisma's `bar/Dock.qml`, `DockItem.qml`, `DockSeparator.qml` carry
  the expensive part: window tracking, desktop-file icon resolution, matching
  processes to applications. The reveal zone must be **inside the surface bounds**
  — a bug Prisma already hit and fixed.

### 9.10 Notifications

- **Contracted.** Conditional, appearing on a notification event. Shows a default
  title only.
- **Hover.** The full notification, plus any action buttons the notification
  carries.
- **Click.** Opens the history.
- **Visibility.** Conditional on event; dwell varies with urgency. Critical
  notifications do not expire on their own, per the freedesktop convention, and
  use the alert colour.
- **Queueing.** Notifications arriving close together **queue**. The queue needs a
  cap: twenty notifications in ten seconds (a system update) would otherwise
  occupy the cell for minutes. Past the cap, collapse to a count and defer to the
  history. Non-expiring urgent notifications must not block the queue.
- **Notes.** Because actions live in hover, "interaction suspends disappearance"
  (§5.2) is **mandatory here, not optional** — otherwise a notification with two
  buttons vanishes while the user decides which to press.
- **Open**: do-not-disturb — wanted or not, and if so, does the toggle live in the
  history or in settings?

### 9.11 Connectivity

- **Contracted.** One icon **per active connection** — ethernet, Wi-Fi,
  Bluetooth. No active Bluetooth device, no Bluetooth glyph; same for the others.
  The cell composes itself, and its width tells the user how many connections are
  live.
  - With no connections at all, the cell **disappears entirely**.
  - Width changes when connections come and go. Less frequent than the window
    title, but a minimum width is still worth having as a stabiliser.
- **Expanded.** Toggles plus **complete Wi-Fi and Bluetooth management** —
  network selection with password entry, device pairing.
- **Notes.** Password entry is the only place in the system where a cell anchored
  to an edge needs keyboard focus while remaining a conditional cell — see §5.2.
  Prisma's `NetworkService`, `NetworkPage` and `BluetoothPage` are the porting
  base.

### 9.12 Settings

- **Contracted.** The Bioma logo (once defined).
- **Expanded.** Covers:
  - appearance — opacity, blur, radius, scale, timing
  - structure — membranes per monitor and edge, tissues with anchors and
    percentages, which cells each contains and in what order
  - per-cell settings where available, including visibility conditions
  - visual monitor management with relative positioning and snap
  - keybinds
- **Visibility.** Invoked, optionally also an always-visible icon.
- **Notes.** This is the second largest piece after the launcher. Both of the
  expensive parts exist in Prisma: `MonitorManager.qml` (drag-and-drop, magnetic
  snap, non-destructive `niri.kdl` patching) and `KeybindsPage.qml` (parses the
  `binds` block, writes, reloads). Writing into Niri's own config is accepted and
  already implemented; preserve the sections not being touched.

### 9.13 Launcher

- **Contracted.** None — invoked only.
- **Expanded.** Application search and launch.
- **Notes.** Deliberately last. It is the largest single item in the catalogue and
  the one the author most wants to own, because it carries identity. Prisma's
  launcher provides the easy 20% (desktop file enumeration, launching); **fuzzy
  matching, frequency ranking and robust icon resolution are absent and are the
  actual work.** Specify it fully here, build it once the cell system is proven.

---

## 10. Build order

**Phase 0 — Foundations.** Membranes, tissues, cells: geometry, anchors,
percentage sharing, reflow, three visibility types, layered JSON config, theme
with roles and sources, scale, named timing set, size-based animation technique.
Nothing is visible. It is the whole project.

**Phase 1 — Service porting.** Port and verify each Prisma service without UI,
updating for Quickshell API drift. The most thankless and most profitable phase:
when it ends, most cells are a face to draw.

**Phase 2 — The three cells that validate the system.** Window title (conditional
presence, elastic). Workspaces (vertical expansion). Vitals (animated indicators,
expansion, click-to-sort, kill confirmation). If these three work, Bioma works.

**Phase 3 — Identity.** Sinestesia, theme and wallpaper, utility with
Bioma-styled selection and recording. The cells no other shell has.

**Phase 4 — Replacement.** Volume and audio, connectivity, session menu, dock,
then **notifications last of this group** — that is the point of no return, where
the previous shell's notifications must be switched off.

**Phase 5 — Settings.** Whole, not split: appearance, structure, cell conditions,
monitors and keybinds, reusing `MonitorManager` and `KeybindsPage`.

**Phase 6 — Launcher.** Alone, with the system proven and full attention
available.

Phases 0–2 yield a shell already worth looking at. From there it is progressive
replacement.

---

## 11. Open questions

None blocking.

- Bioma logo (settings cell contracted state). Worth doing early: it fixes the
  shape language the icon set must obey, and drawing icons first means drawing
  them twice.
- Theme cell contracted indicator: continuous animation or only on change.
- Workspaces expanded: this monitor's workspaces or all, grouped by monitor.
- Notifications: do-not-disturb, and where its toggle lives.
- System-wide OSD: adopt or not (Prisma components exist).
- Light-variant palette validation.
- Tuning of confirm and dwell values — decided by using the system, not by
  designing it.
- Cell legibility in vertical orientation (content variant or adaptation).
- Multi-language support: deliberately deferred.

---

## 12. Sources

- `bioma-spec.md` — structural and design rationale (Italian, working material)
- `bioma-spec-v3.md` — visual decisions from the style studies, including
  concrete tokens, type scale and measured animation timings
- `prisma-pack/` — predecessor shell snapshot, with `CLAUDE.md` (architecture)
  and `PROGRESS.md` (feature status)
