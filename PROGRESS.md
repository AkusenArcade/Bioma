# Progress

Where the work stands. `services/INVENTORY.md` holds the detail and the
reasoning; this is the short version and the list of what is *not* done.

Last worked: 2026-09-21.

## Where to pick up

Phase 1 is nine services of ten, every one verified. Phase 0's engine draws and
has been exercised by seven cells; phase 2 is finished — window title,
workspaces and vitals, the last of them opening into pods and a process list —
and phase 3 has started: the theme cell retints the shell live, and the utility
cell captures — with Bioma's own selection rectangle, not `slurp`.

Three ways in, and they are independent:

1. **The rest of phase 3**: sinestesia, and it is the one with real unknowns —
   the band's behaviour is defined against the author's own Sinestesia code, and
   capture and FFT have to be split from rendering into a headless process
   before a cell draws anything.
2. **Notifications**, which closes phase 1 and burns the bridge — the only work
   that cannot be done without switching the running shell off. See the
   pre-flight below.
3. **The rest of the engine**: auto-hide, vertical and floating tissues,
   keyboard focus for invoked cells, and the last user of the full-screen input
   surface — cells positioned at the pointer, which need the pointer position it
   is the only way to learn.

### Waiting for a pair of hands

Nothing here can press a mouse button — there is no `ydotool` or `wtype` on
this machine — so the following are written, look right in a screenshot, and
have never been confirmed by a real click or a real drag:

- **a press outside an open cell dismisses it**, through `structure/InputSurface.qml`;
- **the scrollbar** in both lists, which appears while the list is moving;
- **pressing the vitals search field**, which used to dismiss the cell and
  should not any more: the masks are rebound when an expansion finishes
  growing, not only when it appears;
- **every control in the theme cell**: the carousel's wheel and its two
  neighbours, the source switch, the dropdown and its rows. Each was driven from
  a throwaway timer instead — the list opens, the switch slides, and the palette
  written through `Config.set` retints the whole shell in a screenshot taken
  three seconds later — but no press has ever reached any of them;
- **the drag that draws a selection rectangle.** The surface comes up, dims the
  desktop, takes the keyboard and goes away again on cancel, all of it verified;
  the rectangle itself, its readout and the region it produces have only ever
  been reasoned about. Everything downstream of the region *is* verified, from
  when `slurp` still drew it.

The way to verify anything visual here is a temporary `Timer` that sets
`open = true` a couple of seconds after start, then `grim` for a frame or a
burst of them. Take the patch out before committing.

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
| `components/` | `Rim`, `Ring`, `DashedRing`, `Disc`, `Dial`, `Icon`, `LightGradient`, `Thread`, `Panel`, `Well`, `WorkspaceBars`, `Vital`. |
| `structure/InputSurface.qml` + `core/Focus.qml` | The full-screen surface of PRD §8, and the register of what is open. Built; the press path still needs a human to click. |
| `cells/clock`, `cells/window_title`, `cells/workspaces`, `cells/vitals`, `cells/theme`, `cells/utility`, `cells/recording` | Seven cells. Vitals opens into pods, threads and the process list; theme into the wallpaper carousel and the two palette capsules; utility into the capture panel, and generates the recording cell. |
| `structure/SelectionSurface.qml` | Bioma's own selection rectangle, over the whole desktop, in place of `slurp`. Up only while a region is being asked for, and it holds the keyboard for that long so Escape means cancel. |
| `components/Segmented.qml` | The segmented control, shared: the theme cell's source switch and the utility cell's three kinds are the same object. |
| `core/Config.qml` write-back | `Config.set` writes one key into the override layer. Brought forward from phase 5 because the theme cell has to keep a choice. |

Verified on HDMI-A-1: cells float with no band, the rim reads, the app icon
resolves and the fallback glyph is tinted, the title elides and cross-fades, the
minute dial fills, and **blur through `ext-background-effect` is confirmed** —
the wallpaper is sharp outside the pills and smoothed inside them.

Expansion works, and the workspaces list is the first one drawn: the thread
draws out of the cell, the panel grows from its far node, and the content
arrives once the shape is at size. Closing reverses it, quicker.

A membrane on the **bottom** edge is exercised too: DP-1 carries one in the test
override, with every cell built so far on it. Expansions grow upward from the
window line, and the two compositions are ordered from the cell outwards —
which is where the bug was: both were built against a cell above them, so on a
bottom membrane the theme cell's carousel ended up at the far end and the
capsules against the cell, and the shapes grew away from the thread that ties
them there instead of out of it.

Not yet exercised: auto-hide, vertical tissues, floating tissues, several
elastic cells in one tissue, and keyboard focus. Clicking outside to close is
written and mapped — `niri msg layers` shows `bioma-input` appear on every
monitor the moment a cell opens — but no test here can press a mouse button,
so the dismissal itself is verified by hand.

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
- **The tissue is one continuous fill behind its cells**, at the token's 0.5.
  `docs/design/IMPLEMENTATION.md` asks for the band to be drawn only around the
  cells, punching their shapes out of it, so that cell blur is not seen through
  two layers. That was built first and it is wrong at this scale: with a 2 px
  margin a punched band *is* a one-pixel outline around every cell plus a rule
  standing in the gap between two of them — the outline and the divider the
  design forbids. The design page draws the tissue as a plain background behind
  its cells, and so does this. The cost, stated rather than hidden: a cell
  composites over the band, so its declared opacity reads a little heavier than
  the number says.
- **A cell's private visual pieces live in `components/`.** Quickshell
  generates no QML module for a cell's own directory — `import qs.cells.clock`
  is not installed and a relative `import "."` does not resolve either — so a
  sibling type is invisible to the cell beside it. `Dial` and `WorkspaceBars`
  are there for that reason as much as for reuse.
- **An expansion can be a composition, not only a panel.** `Cell.panel` is the
  single-surface case; `Cell.expansion` hands a cell the anchor and lets it lay
  out its own shapes and threads, which is what the vitals pods needed. The
  cell asks whatever it loaded for the shapes it occupies, so the membrane's
  mask and blur region follow a composition as readily as a rectangle.
- **A Loader sets its item's properties after that item is built.** Anything a
  loaded expansion has to do on arrival belongs in `onCellChanged`, not in
  `Component.onCompleted` — the first pod cascade never ran because of it.
- **A liquid's level is measured against its vessel.** The memory indicator
  fills the inside of the ring, not the square the ring is drawn in: half full
  lands on the centre line either way, which is what the design draws, but a
  fifth of the memory has to read as a fifth rather than as a sliver below the
  glass.
- **A mask's source has to render itself.** Qt Quick clips rectangles only, so
  the liquid is held inside the ring by an `OpacityMask` — and in Qt 6 an item
  that is merely `visible: false` draws nothing for a mask to sample. Both the
  source and the mask carry `layer.enabled`.
- **The edge margin is measured to the cell, not to the band.** The outermost
  cell on a membrane sits at the margin from the screen edge and its tissue's
  padding hangs outside it, so the cell lines up with the left and right edges
  of the windows — which niri insets by the same `gaps`. Measured: cell and
  window both at x 12.
- **An expansion hangs from the line the compositor draws windows on.** Not
  from the cell, and not from the edge of the reserved strip: niri insets its
  windows by `gaps` and by any `struts`, so a panel hung at the strip's edge
  floats a gap above the windows and the alignment the eye actually checks is
  the one that is wrong. `services/Niri.qml` reads those two figures out of
  niri's own `config.kdl` and watches it — `niri msg` has no configuration
  query, only outputs, workspaces, windows and layers — and the tissue makes
  each thread however long it must be to reach that line. Measured with
  `gaps 12`: the panel's upper rim and the window's top edge both at y 68.
  Akusen's rule, 2026-09-20.
- **The input surface's region is the screen minus what the shell claims.**
  Layer-shell surfaces of one layer stack in creation order, which is not
  something to build a behaviour on: the catcher subtracts every cell and panel
  from its own input region instead, so the two never overlap and the right
  surface receives a press whatever the compositor stacked where.
- **One cell is open at a time.** `core/Focus.qml` holds it: opening a second
  closes the first, because two panels on screen are two conversations.
- **A cell keeps its content when it opens**, unless it says otherwise.
  PRD §6.7 says the contracted content is entirely replaced by the expanded
  one; that is true of vitals, whose cell becomes the header of its own
  expansion, and wrong for the workspaces cell, which the mockup shows keeping
  its mark and its name while the list hangs below. `Cell.replacesContent`
  carries the difference.
- **The window title has no minimum width.** CELLS.md §01 gives it 186 px as a
  stabiliser; on the machine it read as a wide empty pill next to a short
  title, so it now takes exactly the width of its text. Akusen's call,
  2026-09-20.
- **A cell's panel content is loaded by URL, not imported.** There is no QML
  module for a cell's directory, so `cells/<name>/` holds the contracted cell
  and its expansion as separate files, and the cell loads the second with
  `Qt.resolvedUrl` — which keeps the layout CLAUDE.md describes.
- **A cell knows its monitor.** The membrane passes its screen name down
  through the tissue, so the workspaces cell answers for its own output, as
  CELLS.md §03 decided against PRD §9.3.
- **A tissue's place on its membrane is derived from its order**: first is the
  start corner, last the end corner, anything else centred, `growth: symmetric`
  forces the centre and an explicit `anchor` overrides all of it. The
  configuration declared growth but never where the tissue sits.

- **A setting the user changes is written one key at a time.** `Config.set`
  rewrites the override document with that key changed, never the merged values:
  a membrane list, a font, a hand-written `$comment` all survive a theme being
  chosen. It also keeps the document in memory, because two settings changed in
  the same breath — source and palette, when the switch moves — would otherwise
  both read the file as it was before either had landed, and the first would be
  lost. Brought forward from phase 5; the settings page will want exactly this.
- **The palette has a destination as well as a journey.** Every visible role is
  animated, which is what makes a theme change cross the whole shell at once —
  and it is also what makes a chip bound to one arrive late: a delay restarted on
  every frame of the transition never elapses. `Theme.targetRoles` is the seven
  roles computed from the palette as loaded, and the theme cell's chips follow
  that instead, sixteen milliseconds apart.
- **The wallpaper's thumbnails belong to the wallpaper service.** Not to the
  cell that shows them: the settings page will want the same small copies, and
  the cache is the wallpaper's own business. `magick` makes them one at a time
  into `~/.cache/bioma/thumbnails`, and without ImageMagick the carousel reads
  the photographs themselves — slower on the first look, and the same cell.
- **A converter creates its output before it finishes writing it.** The
  directory model announces the file at that moment, Qt reads a fragment, and
  reports "Unsupported image format" for good. The file being written is left
  out of the cache set until the process writing it has exited.
- **A binding must not start work.** `Wallpaper.thumbnail()` looks a path up and
  nothing else; asking for one to be *made* is `prepare()`, called from a change
  handler. The first version did both in one call and Qt stopped evaluating the
  binding — a binding that changes what it reads is a loop, and the tile went
  blank rather than wrong, which is the harder kind of failure to see.
- **The theme cell does not carry the wallpaper's "how".** Fill, fit, span and
  per-monitor are requirements, but CELLS.md §07 draws a carousel and two
  capsules and no mode control, and there is no room inside 268 × 96 for one
  that would not be a fourth thing to read. The mode stays in the wallpaper
  service, where it already lives, and lands in the settings cell.

- **A capture waits for the shell to be gone.** Everything Bioma draws is on the
  screen being photographed, and closing the cell is an animation: `grim` run in
  the same instant catches the panel mid-close, and the recorder catches it in
  its first frames. The wait is in the service, once, where every path goes
  through it — `Timing.close` plus a frame — rather than in each caller.
- **A pair that cannot be done is shown as unavailable.** The recorder takes an
  output or a region and never a window, and text is recognised from a region,
  which a window does not have here — niri reports no window position, so the
  compositor captures it by id. Two independent choices are still two, and the
  ones that cannot meet are dimmed rather than offered and then refused.
- **The selection rectangle is one surface per monitor**, so a rectangle drawn
  across two outputs is not possible: the pointer leaves the surface it started
  on. `slurp` has the same limit for the same reason, and the region grim wants
  is one output's anyway.
- **The recording cell is conditional on the file, not on the recorder.** It
  stands while `wl-screenrec` runs and stays for the question afterwards,
  because the file it is asking about is the one it just made. When the answer
  arrives the condition lapses and the cell leaves on its own.

- **A composition is ordered from the cell outwards, not top to bottom.** A
  single panel already handled both edges — `structure/Cell.qml` computes its
  anchor and its node from `opensDown` — but a composition places its own
  shapes, and both of them had the cell's direction written into them as a
  constant. The rule, now stated once per composition: the shape the cell's
  thread lands on is the one nearest the cell, and everything the expansion
  opens afterwards opens away from it. The theme cell's dropdown list is the
  case that shows why — hung downwards on a bottom membrane it would lie over
  the carousel.

- **Interaction suspends disappearance, and something has to un-suspend it.**
  `structure/Visibility.qml` paused a running dwell on hover and resumed it on
  exit, which is right — but when the condition lapses *while* the pointer is on
  the cell no timer was ever started, so there was nothing to resume and the
  cell stayed for ever. Found on the recording cell: stop and save with the
  pointer still on it, and the counter stood frozen on the membrane. The pointer
  leaving now re-evaluates the condition. This matters most for notifications,
  where the actions live in the hover state.

- **A ceiling the band respects and the cells ignore is not a ceiling.** The
  tissue clamped its own length to the declared percentage and then laid its
  cells out in a row regardless, so on a narrow monitor the last of them stood
  outside the band — and far enough over, outside the screen. Found on a 1920 px
  monitor whose right tissue was 20%: the recording cell appearing pushed its
  neighbours off the edge. The tissue now hands out room in anchor order and
  leaves out what it cannot fit, saying so once; the cell comes back by itself
  when its neighbours need less. The two monitors behaved differently only
  because 30% of 3440 is room enough for anything.

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
| `services/Capture.qml` | Done. Stills, window capture through niri, text recognition, video with save or discard. The selection rectangle is now Bioma's own — the service raises a flag and `structure/SelectionSurface.qml` answers with a region. |
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
- **The drag inside Bioma's own selection rectangle.** The surface is written
  and comes up; nothing here can draw a rectangle with it.
- **`structure/Visibility.qml`** has no test at all. It is the heart of the
  temporal grammar and the first cell will be its first exercise.

### What the notification cell already owes

Asked for while using the capture cell, and recorded here so it is not
rediscovered later: **a capture that succeeded has to say so.** A screenshot is
instantaneous and leaves nothing on screen — the file is written, the clipboard
is set, and the shell says nothing at all. That is the notification cell's job
(§10) rather than a second state of the utility cell, and it is the first real
consumer of it: image, text and video each end with something worth announcing,
and the video's announcement is the one that carries a path.

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
