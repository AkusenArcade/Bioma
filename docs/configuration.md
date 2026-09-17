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
