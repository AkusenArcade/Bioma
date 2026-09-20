# Progress

Where the work stands. `services/INVENTORY.md` holds the detail and the
reasoning; this is the short version and the list of what is *not* done.

Last worked: 2026-09-20.

## Where to pick up

Phase 1 is nine services of ten, every one verified. Phase 0's layout engine now
draws: membranes, tissues and cells are real, and two cells stand on them.

Three ways in, and they are independent:

1. **Notifications**, which closes phase 1 and burns the bridge — the only work
   that cannot be done without switching the running shell off. See the
   pre-flight below.
2. **The rest of the engine**: expansion (grown, never yet opened), auto-hide,
   vertical and floating tissues, and the full-screen input surface of PRD §8,
   which the PRD calls the most uncertain piece in the project and which nothing
   has prototyped.
3. **Cells**, in build order: workspaces and vitals next.

## How to try it without touching the running shell

Noctalia owns the DP-1 membrane; HDMI-A-1 is free. `~/.config/bioma/override.json`
declares one membrane there and nothing else, so

```sh
qs -p "$PWD/shell.qml"
```

draws Bioma on the second monitor while the session's own shell keeps running.
The override file is outside the repository, and replaces `membranes` wholesale
because arrays are replaced, not merged.

## Phase 0 — Foundations

Drawn, and verified on screen against the design handoff.

| Piece | State |
|---|---|
| `core/Config.qml` | Working. Two layers, deep merge, hot reload. |
| `core/Theme.qml` | Working. Four roles from a source, three fixed, the rest derived in HSL — surfaces, the outline family, the two gradient stops. With the shipped palette the derivations reproduce `docs/design/tokens.css` to within a step or two. |
| `core/Metrics.qml` | The token geometry. **Renamed from `Scale`**: `QtQuick` exports a `Scale` type and shadows a singleton of that name everywhere. |
| `core/Timing.qml`, `core/Typography.qml` | Aligned to the handoff: one named set, curves included; two voices, Orbitron and Spectral. |
| `core/Regions.qml` | Region trees built at runtime, for the input mask and the blur region. |
| `structure/Membrane.qml` | Real. Slot placement from percentages, anchors derived from the list, exclusive zone, input mask, blur region, auto-hide written. |
| `structure/Tissue.qml` | Real. Ceiling-not-reservation widths, elastic share, reflow, the punched band. |
| `structure/Cell.qml` | Real, contracted. Glass, rim, config-driven width and visibility, growth mechanics written. |
| `structure/Visibility.qml` | **Exercised at last** — the window title appears and disappears with focus. |
| `components/` | `Rim`, `Ring`, `Dial`, `Icon`, `LightGradient`. |
| `cells/clock`, `cells/window_title` | The first two cells, and the engine's proof. |

Verified on HDMI-A-1: cells float with no band, the rim reads, the app icon
resolves and the fallback glyph is tinted, the title elides and cross-fades, the
minute dial fills, and **blur through `ext-background-effect` is confirmed** —
the wallpaper is sharp outside the pills and smoothed inside them.

Not yet exercised: expansion (no cell opens yet), auto-hide, vertical tissues,
floating tissues, several elastic cells in one tissue, keyboard focus.

### Decisions taken while building it

- **`Scale` → `Metrics`.** Name collision with `QtQuick.Scale`, which wins in
  every file that imports QtQuick.
- **Dynamic `Region` children do not work.** An object created with
  `Qt.createQmlObject` or `Component.createObject` and given a Region as parent
  never joins its `regions` list. The tree is built from a QML string that
  contains the children, and the leaves are bound afterwards — `core/Regions.qml`.
- **Icons are recoloured as text, not tinted as bitmaps.** The files paint in
  `currentColor`, which Qt renders black; `components/Icon.qml` substitutes the
  colour in the SVG source. It must emit `rgb()`: Qt writes a colour as
  `#AARRGGBB`, SVG reads that as `#RRGGBBAA`, and the glyph silently vanishes.
- **A cell's content declares an unelided width.** Binding a `Text`'s width to
  its own `contentWidth` collapses it to nothing once it elides, so a cell that
  elides reports `implicitWidth` through `Cell.contentWidth` and elides against
  what it is granted.
- **The tissue band ships invisible** (`tissue.opacity: 0`). Every mockup shows
  cells floating, with nothing outlining them and no divider between them. The
  band is still drawn when the value is raised, as one continuous fill with the
  cell shapes punched out — never as an outline.
- **A tissue's place on its membrane is derived from its order**: first is the
  start corner, last the end corner, anything else centred, `growth: symmetric`
  forces the centre and an explicit `anchor` overrides all of it. The
  configuration declared growth but never where the tissue sits.

## Phase 1 — Service porting

Nine of ten done, each verified headlessly through `probe.qml` before moving
on. Nine items, ten services: network and bluetooth are separate domains and
therefore separate singletons.

| Service | State |
|---|---|
| `services/Niri.qml` | Done. IPC socket event stream, 14 event types, actions. |
| `services/Wallpaper.qml` + `structure/WallpaperSurface.qml` | Done. Four modes, crossfade, persisted state. |
| `services/Matugen.qml` + `config/matugen/` | Done. Template-rendered palette, watched by Theme. |
| `services/Media.qml` | Done. MPRIS metadata, art, position, transport, player selection. |
| `services/Audio.qml` | Done. Devices, per-application volume, peak monitor. |
| `services/Brightness.qml` | Done. Backlight and DDC backends. |
| `services/Network.qml` | Done. Wired and Wi-Fi, native, no `nmcli` and no poll. |
| `services/Bluetooth.qml` | Done. Adapter, devices, pairing, native. Nothing taken from Prisma's page. |
| `services/SystemMonitor.qml` | Done. Load, memory, CPU clock, GPU, battery, processes. No process on the sampling path at all. |
| `services/Capture.qml` | Done. Stills, window capture through niri, text recognition, video with save or discard. |
| Notifications | **Next, and last.** See below. |

### Verified, and not

Everything above was checked against live state. Six gaps are known, and all
but the last two are missing hardware rather than missing work:

- **The backlight path of `Brightness.qml`** has only ever run against a
  fabricated `/sys/class/backlight` tree. This machine has no backlight. The DDC
  path is verified against both real monitors.
- **Joining a Wi-Fi network** — the radio, the scanner, the list and the
  security detection are all verified, but every network in range belongs to
  someone else, so `join`, `joinWithPassword` and the failure path have never
  run.
- **Every device-level bluetooth path**, including the battery scale, which is
  a documented guess. There is no paired device on this machine.
- **Everything battery**, in `SystemMonitor.qml`. There is no battery here, and
  UPower's percentage scale is deliberately left raw rather than converted on a
  guess (§16.6).
- **Bioma's own selection rectangle**, which `Capture.selectRegion()` stands in
  for with `slurp`. It needs the full-screen input surface of PRD §8, which is
  phase 0 work that has never been prototyped.
- **`structure/Visibility.qml`** has no test at all. It is the heart of the
  temporal grammar and the first cell will be its first exercise.

### Before notifications can be touched

`org.freedesktop.Notifications` has one owner per session, and on this machine
that owner is **Noctalia**, which is the running shell. It also holds
`org.kde.StatusNotifierWatcher`. It has to be switched off first, and that is
the point of no return the PRD describes.

Checked on 2026-09-18, so the cutover does not have to be worked out from
scratch:

| Fact | Value |
|---|---|
| Owner of both bus names | one process, `noctalia`, pid 1776 at the time of checking |
| How it starts | `spawn-at-startup "noctalia" "-d"` in `~/.config/niri/config.kdl`, with `include "noctalia-binds.kdl"` on the next line |
| Parent | `systemd --user` — niri spawns it detached, so killing niri's child does not help and there is no user unit to stop |

The cutover is therefore: comment out those two lines in the niri config, kill
the process, and start Bioma in its place. The keybind file goes with it, which
means every shortcut the machine currently has for a shell stops working at the
same moment — worth doing when there is time to finish, not at the end of a
session.

Confirm the names are free before writing the cell:

```sh
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus GetConnectionUnixProcessID s org.freedesktop.Notifications
```

## How to check the state of things

```sh
qs -p "$PWD/probe.qml"      # every service, headless, no surfaces
```

Allow six seconds: DDC detection alone costs three and a half.

The probe reports the Wi-Fi radio as it finds it and never turns it on. The
scan path was verified with a throwaway probe that toggled the radio through
`Network.setWifiEnabled` and put it back; it is not kept in the repository,
because a file that flips the machine's radio as a side effect of being run is a
trap. Rebuild it from §15.6 if the Wi-Fi path needs checking again.

`scripts/mpris-dummy.py` publishes a silent MPRIS player for testing the media
service; run two with different `--name` values to exercise player selection.

## Decisions taken since the PRD was written

Recorded in full in `services/INVENTORY.md` §9–§17. The ones that change the
plan rather than an implementation detail:

- There is no `Quickshell.Niri` module. The compositor service reads niri's own
  IPC socket, and is richer for it (§9.1).
- Battery, bluetooth and wired networking are native in Quickshell 0.3.1, so
  three items the inventory called new work are mostly not (§9.2).
- Per-application volume is far less work than the PRD estimated; the expense in
  that cell is its interface (§13).
- Sinestesia's visibility condition needs no capture and no FFT —
  `PwNodePeakMonitor` gives the signal directly. The split of Sinestesia is still
  required for the bands the visualiser draws (§13.3).
- The palette goes through a matugen template, so format drift lands in a text
  file rather than in the shell (§11).
- §9.4's trap has a second half: a bound property is still at its default for an
  instant after binding, so a function that *gates an action* on one silently
  does nothing. Properties display state; they do not decide whether to call the
  backend (§15.1).
- Prisma's Wi-Fi signal bars were wrong — `signalStrength` is 0–1, not 0–100 —
  which is worth knowing as a measure of how much of Prisma to trust on sight
  (§15.2).
- The vitals sampler needs no persistent process either: `FileView` reads
  `/proc` and `/sys` directly, so the shell spawns nothing to sample the
  machine. `reload()` is asynchronous, though, and reading the text back
  immediately returns the previous sample — a third instance of the same trap
  (§16.1).
- Capture is bigger than §8 assumed. Prisma has no clipboard, no destination
  folder and no recorder, so only two command lines were ported; and a window
  cannot be captured with `grim` at all, because niri reports no window
  position — the compositor does it by id instead (§17.1).
