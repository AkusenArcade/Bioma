# Configuration

The PRD asks for a default file "commented in English, explaining the biological
terms". JSON has no comment syntax, and a JSON-with-comments dialect would have
to be parsed by hand — which is exactly the dependency JSON was chosen to avoid.
So the commentary lives here instead, and `config/default.json` carries a single
`$comment` key pointing at this file. If that trade later proves wrong, the
alternative is a `default.jsonc` source stripped into `default.json` by a build
step; it is not worth a build step yet.

## Layers

1. **`config/default.json`** — the base layer. Hand-written, version-controlled,
   ships with the shell.
2. **`$XDG_CONFIG_HOME/bioma/override.json`** — written by the settings UI.
   Loaded last, wins.

Objects merge key by key. Arrays and scalars are replaced wholesale: an override
that declares a tissue list means *that* list, not an append.

A cell that changes a setting — the theme cell is the first — writes it into the
override layer through `Config.set`, one key at a time. The base layer is never
rewritten, and neither is anything in the override the shell did not touch: the
file is rewritten from the override document, not from the merged values, so a
membrane list or a hand-written `$comment` survives a setting being changed.

## What niri has to be told

One file, `config/niri/bioma.kdl`, included from the user's own niri
configuration:

```kdl
include "/path/to/Bioma/config/niri/bioma.kdl"
```

Blur itself needs no rule. niri turns it on by itself for any surface that
declares a blur region through `ext-background-effect`, which is exactly how
Bioma asks for it — the shape of each cell and nothing else, never the whole
membrane.

What the file says is `xray false`, and it has to. niri defaults xray to true
whenever a background effect is visible, because it is the cheaper of the two:
xray blurs the compositor's *backdrop* rather than what is actually behind the
surface. Bioma draws its own wallpaper on a layer surface of its own, so that
backdrop is a flat colour — and the cells come out as slabs you can see nothing
through, which is exactly how this was found.

## Structural terms

- **membrane** — one edge of one monitor. Tissues anchored to it share its
  length.
- **tissue** — a positioned container on a membrane, or floating.
- **cell** — a unit of content with one domain. Biological, never a grid cell.

## Keys

### `appearance`

| Key | Meaning |
|---|---|
| `radius` | One value as a percentage of the drawn shapes: 100 is the design as it stands, 0 a rectangle. It reaches every surface — cells, tissues, panels, wells, capsules, rows, controls — not only the cells on the membrane, because a shell with square cells and round capsules inside them is two shells. What it does not reach is what is round because of what it is: an avatar, a dial, a radio mark, a thread's node. A cell's radius is its tissue's minus the padding, so concentric corners are automatic at every value. |
| `xray` | On: blur a static copy of the wallpaper — cheap, but it blurs the wallpaper even when windows are underneath. Off: blur the actual underlying content — correct, more expensive, still experimental. |
| `edge` | Margin between the screen edge and a tissue, in logical units. |
| `gap` | Distance between the shapes of one open cell — a capsule and the panel beside it, the pods and the list. |

The third margin of the family, the one between a tissue and the cells inside
it, is `tissue.padding` below, where it has always been. All three are read in
one place — `core/Metrics.qml` — and everything drawn takes its spacing from
there; they are what the settings cell's **Appearance** page moves. Scale is
not among them: it belongs to a membrane, and each membrane block declares its
own.

### `cell`, `tissue`

`cell.opacity`, `cell.blur` — cells always have their own background, and blur
applies to cells only. `tissue.opacity`, `tissue.padding` (2–12) — the tissue
background is a surface, not a border: at a wide padding the band reads as a
tray, and it is never blurred.

`tissue.opacity` ships at **0.5**, the value in `docs/design/tokens.css`. The
band is one continuous fill with the cell shapes punched out of it — never an
outline around each cell and never a rule drawn between two of them: it follows
the tissue's own radius, and the only places it shows are the margin around the
cells and the gap between them.

### `fonts`

Declared as roles, not names, so a machine without the intended faces degrades
rather than breaks. `expressive` carries human language (clock, window title,
track metadata, notification body); `technical` carries machine measurement
(percentages, frequencies, memory, labels, controls).

### `theme`

`source` is `matugen` or `manual`; `palette` names a file in
`config/palettes/`. A palette declares only the four interface roles —
`background`, `text`, `primary`, `secondary`. Light or dark is inferred from the
background's luminance, never configured.

`theme.state` holds the three state roles in a `light` and a `dark` variant.
**These never come from matugen**: they are a semantic code, and a blue
wallpaper would turn them into three blues. The same hex values lose contrast on
a light background — amber especially — which is why there are two variants.
Six values, written once.

Everything else — elevated surface, muted text, borders, shadows — is derived in
code, and stays coherent by construction.

`theme.matugen.scheme` is a user choice, not a constant: content and tonal spot
from the same wallpaper give two different desktops. The theme cell offers it,
and writes `source`, `palette` and `matugen.scheme` back into the override layer
as they are chosen.

### `timing`

The single named timing set. No duration is written anywhere else. `speed`
multiplies all of them, which is what makes a user-facing "animation speed"
setting possible.

Opening (250 ms) is slower than closing (150 ms) on purpose. Reach the opening
figure by tightening the cascade, not by shortening `grow`.

### `membranes[]`

| Key | Meaning |
|---|---|
| `monitor` | `primary`, or an output name |
| `edge` | `top` \| `bottom` \| `left` \| `right` |
| `reserve_space` | Cede a strip to the window layout. **Only horizontal edges may reserve** — geometric rule, no exceptions. The strip stays reserved even while a conditional cell inside is invisible, so windows never reflow. |
| `auto_hide` | Slide out of view, reveal on pointer-at-edge. Implies `reserve_space: false`. Governs every tissue on the membrane, the dock included. |
| `scale` | `compact` \| `normal` \| `comfortable` |
| `tissues` | Ordered list. Percentages are ceilings, not reservations, and must not exceed 100 in total; above that the system warns. Unused space stays empty. |

### tissues

`percentage` (anchored) or `anchor` + `margins` (floating), `orientation`,
`growth` (`inward` for a corner, `symmetric` for the centre), `padding`,
`opacity`, and the ordered `cells`.

`anchor` — `start`, `centre` or `end` — overrides the position a tissue would
take from its place in the list. The settings cell always writes it, because
six slots drawn on screen are positional: an empty middle one must not move the
two beside it.

Collision between tissues on one membrane is impossible by construction.
Floating tissues may overlap; that is not prevented.

A percentage is a **ceiling, not a reservation**, and the tissue holds to it: it
hands out room in anchor order — the cells against the screen edge first, since
that is the end a tissue grows inward from — and a cell it cannot fit is not
drawn at all until there is room for it again. The shell says so once, naming
the membrane and the cell. A cell drawn outside its band, or off the screen, is
the one outcome a ceiling exists to prevent.

**The ceiling has a floor.** A band has to be granted at least what its cells
need at their narrowest: every `min_width` in it, one gap between each pair and
the tissue's own margin on both sides. Below that the membrane is drawn with
cells missing from it, which looks like a defect rather than a setting, so the
shell warns at startup and names the percentage to raise it to:

```
Bioma: the top membrane on HDMI-A-1 is granted less than it was asked to hold
     — tissue 2 holds 4 cells and needs 12% rather than 5%
```

Conditional cells count: a band that only fits while the notification is away
is a band that breaks when one arrives. The arithmetic is `Metrics.roomFor`,
and `Registry.roomFor` answers it for a list of cell blocks — which is how the
settings cell can refuse to add a cell to a band that cannot hold it, before
the cell exists.

### cells

| Key | Meaning |
|---|---|
| `type` | Which cell |
| `enabled` | |
| `visibility.type` | `always` \| `conditional` \| `invoked`. They combine — a cell may be conditional *and* invocable. |
| `visibility.enter` / `exit` | Dual threshold. Distinct values on **every** boundary, so the state cannot flicker around one. |
| `visibility.confirm` | How long the condition must hold before appearing. |
| `visibility.dwell` | How long the cell remains after the condition lapses. |
| `visibility.shortcut` | For `invoked`. |
| `min_width` | Below it the cell prefers not to appear rather than appear illegible. A generous minimum also stops small content changes producing motion. Omitted, the cell's own floor from `cells/Registry.qml` applies; this raises it, and the band's percentage has to cover the sum. |
| `width` | An **object**, not a bare number — `{ "elastic": true, "max_percent": 25 }` — so a per-cell weight stays possible later. |
| `options` | Per-cell domain settings. |

Confirm and dwell are asymmetric on purpose: appear promptly, leave slowly.

Launcher, session menu and settings are not a separate category — they are cells
whose visibility is `invoked`. The system needs no second model for them.

### Service sections

One block per service singleton, holding what the *domain* needs rather than
what a cell displays. A cell's own settings live in its `options`.

| Key | Meaning |
|---|---|
| `audio.monitor_signal` | Whether the peak monitor on the default sink runs. It is Sinestesia's visibility condition, and it is the only continuous audio work in the shell. |
| `audio.step` | How far one notch of the wheel moves the volume cell, as a fraction of the travel. The wheel is that cell's main interaction, and a mouse with a coarse wheel and a touchpad want different answers. |
| `sinestesia.bands` | How many bands `tools/sinestesia-bands` emits per frame. The cell folds them down to the fourteen it draws contracted and the thirty-four it draws open, so this is the resolution the folding starts from, not the number of bars. |
| `sinestesia.fps` | Frames per second out of the tool. Sixty is what Sinestesia itself runs at. |
| `sinestesia.gain` | Multiplier applied after the dB mapping, 0.1 to 10. The mapping puts −70 dB at nothing and 0 dB at full; quiet material needs more than 1. |
| `sinestesia.source` | `output` — the default sink's monitor, everything the machine plays — or `input`, the default source. |
| `brightness.backend` | `auto` \| `backlight` \| `ddc` \| `none`. `auto` prefers a real backlight and falls back to DDC. |
| `brightness.display` | Which DDC display to drive, by connector (`DP-1`) or I²C bus. Empty means the first found. |
| `capture.what` / `capture.from` | The last pair the utility cell used — `image` \| `video` \| `text`, and `screen` \| `window` \| `region`. Written by the cell itself, so the common case stays one press. |
| `capture.folder` / `capture.video_folder` | Where stills and recordings are kept. A recording is written to a temporary directory first and moved here only when saved, so a discarded one never appears. |
| `capture.clipboard` | Whether a capture also takes the clipboard. §9.6 wants it; a window capture always does, because the compositor is what produces the image. |
| `capture.ocr_language` | tesseract language code. |
| `capture.fps` / `capture.codec` / `capture.bitrate` | H.264 at 60 fps by default, no audio. `fps` is a ceiling: the recorder copies a frame only when the screen changes, so a still screen records at far less. |
| `wallpaper.folder` | Where the theme cell's carousel looks for images. A human writes this one, so `~` and `$HOME` are expanded. |
| `wallpaper.thumbnails` | Whether a small copy of each image is cached under `~/.cache/bioma/thumbnails` and shown instead of the image. Off, the carousel reads the photographs themselves — slower on the first look at a large folder, and the same cell. Needs ImageMagick; without it the service falls back to the images by itself. |
| `timing.loader` | The loader's round trip, out and back. It is the only motion in the shell that runs while nothing is being measured, because the movement is the measurement: it means "no value yet" and stops on the frame the value arrives. `docs/design/icons/LOADER.md` is its whole contract. |
| `notifications.quiet` | Do not disturb. Everything still arrives and everything is kept; what stops is the appearing. The cell writes this itself, from the history panel where it is looked for. |
| `notifications.dwell_low` / `dwell_normal` | How long a notification stays, by urgency. A critical one never leaves by itself, as the freedesktop convention requires, and a sender that asks for a particular time gets it — it knows something about its own message. |
| `notifications.queue_cap` / `burst_window` | Past this many in this long, a burst stops queueing and becomes a count: twenty in ten seconds is a system update, and without a cap the cell would be occupied for minutes. A critical one never counts towards it. |
| `notifications.history` | How many are kept for the history panel. In memory: the freedesktop server owns no store, and a shell that wrote every notification to disk would be keeping a diary nobody asked it to keep. |
| `dock.pinned` | The applications the dock keeps, by desktop entry id, in the order they are shown. Empty is a legitimate setting: with nothing kept the dock is a window list. |
| `session.lock` / `session.suspend` / `session.restart` / `session.shutdown` / `session.logout` | Each is a list — the program and its arguments. None of the five is universal: a lock screen is a choice, systemd is not the only init, and leaving the session is a different sentence on every compositor. The defaults are `loginctl lock-session`, `systemctl suspend|reboot|poweroff` and `niri msg action quit -s`. |
| `vitals.interval` | Sampling cadence, milliseconds. One cadence for load, memory, clock and GPU — they are read at the same instant so they can be compared. |
| `vitals.clock_average` | How many samples the CPU clock is averaged over. **Not optional** (PRD §9.2): the raw clock swings hundreds of megahertz between samples and an unsmoothed beat is arrhythmic. At the default cadence, 5 samples is ten seconds. |
| `vitals.gpu_card` | Which card to sample, matched against its sysfs path (`card1`). Empty picks the one with the most VRAM, which on a machine with an integrated and a discrete GPU is the discrete one. |
| `vitals.process_interval` | Cadence of the process list, which is sampled **only while the expanded cell is open**. |
| `vitals.process_count` | How many processes `ps` returns. Full process management is an application, not a cell. |
