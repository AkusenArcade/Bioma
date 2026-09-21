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

## Structural terms

- **membrane** — one edge of one monitor. Tissues anchored to it share its
  length.
- **tissue** — a positioned container on a membrane, or floating.
- **cell** — a unit of content with one domain. Biological, never a grid cell.

## Keys

### `appearance`

| Key | Meaning |
|---|---|
| `radius` | One value as a percentage: 0 is a rectangle, 100 a pill. A cell's radius is its tissue's minus the padding, so concentric corners are automatic at every value. |
| `xray` | On: blur a static copy of the wallpaper — cheap, but it blurs the wallpaper even when windows are underneath. Off: blur the actual underlying content — correct, more expensive, still experimental. |

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

Collision between tissues on one membrane is impossible by construction.
Floating tissues may overlap; that is not prevented.

A percentage is a **ceiling, not a reservation**, and the tissue holds to it: it
hands out room in anchor order — the cells against the screen edge first, since
that is the end a tissue grows inward from — and a cell it cannot fit is not
drawn at all until there is room for it again. The shell says so once, naming
the membrane and the cell. A cell drawn outside its band, or off the screen, is
the one outcome a ceiling exists to prevent.

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
| `min_width` | Below it the cell prefers not to appear rather than appear illegible. A generous minimum also stops small content changes producing motion. |
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
| `brightness.backend` | `auto` \| `backlight` \| `ddc` \| `none`. `auto` prefers a real backlight and falls back to DDC. |
| `brightness.display` | Which DDC display to drive, by connector (`DP-1`) or I²C bus. Empty means the first found. |
| `capture.what` / `capture.from` | The last pair the utility cell used — `image` \| `video` \| `text`, and `screen` \| `window` \| `region`. Written by the cell itself, so the common case stays one press. |
| `capture.folder` / `capture.video_folder` | Where stills and recordings are kept. A recording is written to a temporary directory first and moved here only when saved, so a discarded one never appears. |
| `capture.clipboard` | Whether a capture also takes the clipboard. §9.6 wants it; a window capture always does, because the compositor is what produces the image. |
| `capture.ocr_language` | tesseract language code. |
| `capture.fps` / `capture.codec` / `capture.bitrate` | H.264 at 60 fps by default, no audio. `fps` is a ceiling: the recorder copies a frame only when the screen changes, so a still screen records at far less. |
| `wallpaper.folder` | Where the theme cell's carousel looks for images. A human writes this one, so `~` and `$HOME` are expanded. |
| `wallpaper.thumbnails` | Whether a small copy of each image is cached under `~/.cache/bioma/thumbnails` and shown instead of the image. Off, the carousel reads the photographs themselves — slower on the first look at a large folder, and the same cell. Needs ImageMagick; without it the service falls back to the images by itself. |
| `vitals.interval` | Sampling cadence, milliseconds. One cadence for load, memory, clock and GPU — they are read at the same instant so they can be compared. |
| `vitals.clock_average` | How many samples the CPU clock is averaged over. **Not optional** (PRD §9.2): the raw clock swings hundreds of megahertz between samples and an unsmoothed beat is arrhythmic. At the default cadence, 5 samples is ten seconds. |
| `vitals.gpu_card` | Which card to sample, matched against its sysfs path (`card1`). Empty picks the one with the most VRAM, which on a machine with an integrated and a discrete GPU is the discrete one. |
| `vitals.process_interval` | Cadence of the process list, which is sampled **only while the expanded cell is open**. |
| `vitals.process_count` | How many processes `ps` returns. Full process management is an application, not a cell. |
