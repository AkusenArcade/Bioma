# Bioma

A Wayland desktop shell for **niri, Hyprland and Umbriel**, running on
**Genoma** (Rust + Luau, `~/Documents/Development/Genoma`) since 1.0.0-beta.61.
The Quickshell (Qt/QML)
version it was first written in is no longer in the tree: the tag
`quickshell-final` is the last commit that carries it.

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
- **All durations come from the timing set** (`genoma/core/timing.luau`). Never a
  literal duration in a cell.
- **Colour is an animated singleton** (`genoma/core/theme.luau`), never a value copied
  into a cell — that is what lets the theme cell retint the desktop live.
- **All dimensions are logical units**, never physical pixels. Round only
  critical dimensions (hairlines, 1.3 px threads) to the physical pixel.
- **Blur applies to cells only, never to the tissue background**, and via
  `ext-background-effect`, never compositor layer rules. Umbriel has no
  `ext-background-effect`: its layer rule (`services/looks.luau`) is the one
  exception.
- **The three compositors are peers.** Whatever touches the compositor is done
  for niri, Hyprland and Umbriel, or says which of them cannot have it.
  None is the reference.
- **One service singleton per domain.** Never a poller per cell.

## Layout

```
genoma/            the shell, the lock and the greeter: core/, structure/,
                   components/, services/, cells/, organisms/ (genoma/PORT.md)
config/            default.json (base layer) + palettes/
assets/            icons, fonts
scripts/           start, lock, greeter, ipc, each compositor's include
docs/              PRD and design material
```

## Bioma on Genoma

`genoma/` is Bioma written on Genoma, the Rust + Luau toolkit that replaced
Quickshell (`~/Documents/Development/Genoma`, its `docs/m6-plan.md`). The
package ships `genoma/` and depends on the `genoma` package at a precise
version. The lock falls back to hyprlock (or swaylock), the greeter to
agreety. When a behaviour has to be compared with the Quickshell original,
read it at the tag `quickshell-final`.

## Configuration

JSON, two layers: `config/default.json` (base, hand-written, in the repo) then
the user's override file written by the settings UI, loaded last, wins.
Both layers are designed in from the start — retrofitting the override layer
means redoing all loading.

## Porting from Prisma

Prisma is the predecessor Quickshell shell, at `~/.config/quickshell/prisma`.
It is **not under version control**, so this is copy-and-adapt, not merge, and
it is QML: what it does is brought over, never its code.

- **Work into this structure, never out of the old one.** Ask for a specific
  capability and bring it here; do not open Prisma and take what looks reusable,
  because the bar-centric architecture comes with it.
- **Inventory before writing** (the Quickshell one is `quickshell/services/INVENTORY.md` at the tag `quickshell-final`).
- **Port service by service and verify each without UI** before a cell depends
  on it.
- **Do not port**: `bar/Bar.qml`, `bar/SysStats.qml`, `services/I18n.qml`.

## Build order

Phase 0 foundations → 1 services → 2 window title / workspaces / vitals →
3 media (was sinestesia), theme, utility → 4 volume, connectivity, session, dock,
notifications last → 5 settings → 6 launcher. See PRD §10.

Notifications are the point of no return: `org.freedesktop.Notifications` has
one owner per session, so Bioma's notification cell cannot be tested while
another shell is running.
