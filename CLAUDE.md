# Bioma

A Wayland desktop shell for **Niri**, built with **Quickshell** (Qt/QML).

**Bioma is not a bar.** It is a set of independent surfaces that appear when they
have something to say and go quiet when nothing is happening. If a change makes
sense only because "that is where the bar puts it", the change is wrong.

The full specification is `docs/bioma-prd.md`. It is the source of truth —
read the relevant section before implementing, and do not re-decide questions
it has already closed.

## Language

English everywhere: code, config keys, UI strings, comments, commit messages.
`Bioma` is the only Italian word retained. There is no i18n layer and none is
planned for v1.

## Structural model

Three levels, each knowing only the one below:

- **membrane** — one edge of one monitor. Owns `reserve_space`, `auto_hide`,
  `scale`. Only horizontal edges may reserve space.
- **tissue** — a positioned container on a membrane (percentage width) or
  floating (anchor + margins). Owns orientation, padding, opacity, ordered cells.
- **cell** — a unit of content with one domain. No position of its own; takes
  what the tissue grants. Always has its own background, opacity and blur.

`cell` here is a biological term, never a grid cell.

## Design

The visual specification lives in `docs/design/`. It is normative for anything
drawn. Read `docs/design/STYLE_GUIDE.md` and `docs/design/IMPLEMENTATION.md`
before writing any UI code, and the matching section of `docs/design/CELLS.md`
before building a cell, with the matching images from `docs/design/mockups/`
open beside it.

- Measurements in the documents win over the images; the renders show the
  result, they are not there to be pixel-measured.
- `docs/design/tokens.css` is the token set. It is translated into `core/`
  singletons — `Theme`, `Timing`, `Metrics`, `Typography` — and nothing reads the
  CSS at runtime. When a token changes, it changes in the singleton.
- `docs/design/icons/` is the drawn source; `assets/icons/` is the runtime copy
  the shell loads. Keep them identical.
- `docs/design/pages/` holds the three design pages as live HTML — the animated
  indicators actually move there. Open them when a behaviour is easier to see
  than to read.
- Where the spec leaves something open, follow the principle it falls under
  rather than inventing a rule.

## Rules that are easy to break by accident

- **At rest the interface does not speak.** No figures in contracted cells.
  Exceptions: clock, window title, track metadata, notification content.
- **Movement means something.** Every animation encodes a live value in its rate
  or extent. Motion at a fixed rate with no data behind it is decoration and is
  not allowed. An indicator with nothing to report is still, or absent.
- **Colour says state, form says domain.**
- **A cell exists when it has something to say.** Conditional presence is the
  default.
- **Expanded forms grow from their origin.** Nothing appears from nowhere.
- **Adding a new cell must cost one config block**, never a structural change.
- **Grow by animating width and height, never `transform: scale`.** Scale
  deforms the lit border, distorts radii and blurs text.
- **All durations come from the timing set** (`core/Timing.qml`). Never a
  literal duration in a cell.
- **Colour is an animated singleton** (`core/Theme.qml`), never a value copied
  into a cell — that is what lets the theme cell retint the desktop live.
- **All dimensions are logical units**, never physical pixels. Round only
  critical dimensions (hairlines, 1.3 px threads) to the physical pixel.
- **The geometry singleton is `core/Metrics.qml`, not `Scale`.** `QtQuick`
  already exports a `Scale` type — the transform — and it shadows a singleton of
  that name wherever `QtQuick` is imported, which is everywhere.
- **Blur applies to cells only, never to the tissue background**, and via
  `ext-background-effect`, never compositor layer rules.
- **One service singleton per domain.** Never a poller per cell.

## Quickshell 0.3.1 — what this build actually gives us

Verified against the installed build, not assumed.

**Singletons and compositor-backed models initialise on their first property
binding, not on first access.** Read `ToplevelManager.toplevels` from inside a
function and it answers empty; bind it to a property and it fills. This is the
single most expensive thing to learn the hard way here — every service is
verified through `probe.qml`, which binds before it reads.

**There is no `Quickshell.Niri` module.** Prisma was built against one; it does
not exist in 0.3.1. `services/Niri.qml` reads niri's own IPC socket instead —
one connection, one `"EventStream"` request, newline-delimited JSON for the life
of the session. Nothing polls.

Available and already relied on, so do not write these by hand:

| Need | Use |
|---|---|
| Blur on a declared shape | `Quickshell.Wayland` → `BackgroundEffect.blurRegion` (niri 26.04 implements `ext_background_effect_v1`) |
| Battery | `Quickshell.Services.UPower` — `UPower.displayDevice`, `isLaptopBattery` |
| Bluetooth | `Quickshell.Bluetooth` — adapter, devices, states |
| Wi-Fi **and ethernet** | `Quickshell.Networking` — `WifiDevice`, `WiredDevice` |
| Windows / workspaces, compositor-agnostic | `ToplevelManager`, `WindowManager` — the fallback if Bioma ever leaves niri |
| Keybind → invoked cell | `Quickshell.Io` → `IpcHandler` |
| Writing config back | `FileView.setText` / `writeAdapter` — no shell process |
| Colours from an image | `ColorQuantizer` |

Two shapes come back from these APIs: most collections are an `ObjectModel`
(read `.values`), but `WindowManager.windowsets` is a plain JS array. Check
before iterating.

## Layout

```
shell.qml          Quickshell entry point
core/              Config, Theme, Timing, Metrics — global singletons
structure/         Membrane, Tissue, Cell — the layout engine
components/        Shared primitives (capsules, threads, indicators)
services/          One singleton per system domain (ported from Prisma)
cells/<name>/      One directory per cell: contracted, expanded, logic
config/            default.json (base layer) + palettes/
assets/            icons, fonts
docs/              PRD and design material
```

## Configuration

JSON, two layers: `config/default.json` (base, hand-written, in the repo) then
the user's override file written by the settings UI, loaded last, wins.
Both layers are designed in from the start — retrofitting the override layer
means redoing all loading.

## Porting from Prisma

Prisma is the predecessor Quickshell shell, at `~/.config/quickshell/prisma`.
It is **not under version control**, so this is copy-and-adapt, not merge, and
its sources predate the current Quickshell release — expect API drift.

- **Work into this structure, never out of the old one.** Ask for a specific
  capability and bring it here; do not open Prisma and take what looks reusable,
  because the bar-centric architecture comes with it.
- **Inventory before writing** (`services/INVENTORY.md`).
- **Port service by service and verify each without UI** before a cell depends
  on it.
- **Do not port**: `bar/Bar.qml`, `bar/SysStats.qml`, `services/I18n.qml`.

## Build order

Phase 0 foundations → 1 services → 2 window title / workspaces / vitals →
3 sinestesia, theme, utility → 4 volume, connectivity, session, dock,
notifications last → 5 settings → 6 launcher. See PRD §10.

Notifications are the point of no return: `org.freedesktop.Notifications` has
one owner per session, so Bioma's notification cell cannot be tested while
another shell is running.
