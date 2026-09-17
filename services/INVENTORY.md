# Service inventory

The first pass over Prisma, as required before any code is written: what exists,
what each service actually does, what is self-contained, and what Bioma still
has to build from nothing.

- **Source read**: `~/.config/quickshell/prisma`, sources last modified
  2026-05-08, read 2026-09-17.
- **Not under version control.** Copy-and-adapt, not merge. No diff to review.
- **Installed on this machine**: niri 26.04, matugen 4.2.0, Quickshell **not
  installed** — nothing below has been run, only read.

Read this together with the correction list in §6: several statements in the PRD
about Prisma do not match its source, and two of them change how much work a
phase is.

---

## 1. Dependency shape — the good news

The PRD expected to find services entangled with `Bar.qml`. They are not.

`services/*.qml` import **only** Qt and Quickshell modules — never `../theme`,
never a widget. The dependency graph is one-directional: every presentation
directory imports `../services` and `../theme`, and nothing points back. There
are exactly three service-to-service edges:

- `MatugenService` → `NiriIPC` (reloads niri after patching the focus ring)
- `WallpaperService` → `MatugenService` (pushes the wallpaper path)
- `PrismaIPC` → `ShellActions` (signal bus)

So "disentangling the service from its widget" is work Bioma does **not** have
to do. The porting cost is API drift and missing capability, not extraction.

The exception is the dock, which is not a service: `bar/Dock.qml` is a child of
`Bar.qml` and reads `BarConfigService` directly.

---

## 2. Services — verdicts

| Service | Lines | Mechanism | Self-contained | Verdict for Bioma |
|---|---|---|---|---|
| `NiriIPC` | 164 | wrapper over `Quickshell.Niri` + `niri msg` dispatch | yes | **Done — rewritten, not ported.** That module does not exist in Quickshell 0.3.1. See §9. |
| `WallpaperService` | 145 | JSON persistence + span geometry from `Niri.outputs` | yes | **Done.** Ported, but not as-is: `Niri.outputs` does not exist here, the crossfade was broken, and persistence shelled out. See §10. |
| `MatugenService` | 221 | runs `matugen image --json hex`, parses, patches niri focus ring | yes (calls NiriIPC) | **Done — neither parser nor delivery survived.** Bioma renders a template and never parses matugen's output. See §11. |
| `SystemMonitorService` | 155 | `/proc/stat`, `/proc/meminfo`, `ps` — a new process per sample | yes | **Rewrite.** Covers maybe 30% of what vitals needs. See §3.4. |
| `AudioService` | 53 | native `Quickshell.Services.Pipewire` | yes | **Done.** Devices, per-application volume and a signal monitor added; see §13. |
| `NetworkService` | 93 | Wi-Fi native via `Quickshell.Networking`; ethernet by polling `nmcli` every 10 s | yes | **Port, then extend.** No bluetooth anywhere in it. |
| `NotificationService` | 52 | `NotificationServer` + an in-memory list | yes | **Port the server, write the grammar.** No urgency, no queue, no history. |
| `BrightnessService` | 92 | `brightnessctl`, polled every 10 s | yes | **Done**, but it could not be ported: this machine has no backlight at all. See §14. |
| `ScreenshotService` | 122 | `slurp` → `grim`, plus a `tesseract` pipeline | yes | **Port the capture calls only.** No clipboard, no save location, no recording. |
| `MediaService` | 35 | native `Quickshell.Services.Mpris`, active-player picking | yes | **Done.** Cover art, position, seeking and explicit player selection added; see §12. |
| `BarConfigService` | 161 | single-layer JSON at `~/.config/prisma/bar.json` | yes | **Do not port** — `core/Config.qml` replaces it. Read it for the persistence idiom only. |
| `PrismaIPC` | 55 | a named FIFO in `$XDG_RUNTIME_DIR` read by a shell loop | yes | **Replace with `IpcHandler`**, which 0.3.1 provides. See §3.10. |
| `ShellActions` | 14 | signal bus, five `open*` signals | yes | **Do not port.** In Bioma these are cells whose visibility is `invoked`; the second model the PRD refuses is exactly this file. |
| `I18n` | 322 | it/en string table | yes | **Do not port.** English-only project. |
| `theme/Theme.qml` | 102 | hardcoded teal palette, spacing, radii, durations | yes | **Do not port.** Superseded by `core/Theme.qml`, `core/Timing.qml`, `core/Scale.qml`. Worth one read as the precedent for a named timing set. |

### Non-service pieces worth naming

| Piece | Lines | Verdict |
|---|---|---|
| `bar/WallpaperWindow.qml` | 80 | **Port with WallpaperService.** Background-layer `PanelWindow`, no daemon. One suspect line — see §3.2. |
| `dashboard/MonitorManager.qml` | 452 | **Port the interaction, rewrite the writer.** See §5.1 — the current writer loses monitor settings. |
| `settings/pages/KeybindsPage.qml` | 609 | **Port the include-following, rewrite the parser.** See §5.2 — the current one destroys multi-line binds. |
| `settings/pages/NetworkPage.qml` | 459 | Reference for Wi-Fi connect + password entry. |
| `settings/pages/BluetoothPage.qml` | 372 | **The only bluetooth code in Prisma.** There is no BluetoothService; it lives inline in the page. |
| `osd/*.qml` | 551 | Working. Whether Bioma adopts an OSD is still open (PRD §11). |
| `bar/Dock.qml`, `DockItem.qml` | 324 | **Low value** — see §6, correction 4. |
| `launcher/*` | 411 | **Low value**, as the PRD says. |

---

## 3. What each service actually does

### 3.1 NiriIPC

Two halves with very different value.

The **data half** is pass-through: `Niri.focusedWindow`, `Niri.workspaces`,
`Niri.windows`, `Niri.outputs`, `Niri.overviewActive`, keyboard layout — all
straight from the native `Quickshell.Niri` module, which is push-based. Prisma
adds `activeWorkspaceForOutput()`, a global `activeWorkspace` with a
focused → active → first fallback chain, and two filter helpers. Perhaps 40
lines of genuine logic.

The **dispatch half** is the part worth having. It resolves `NIRI_SOCKET` at
startup by globbing `/run/user/$(id -u)/niri.$WAYLAND_DISPLAY.*.sock`, because
the inherited `NIRI_SOCKET` points at the wrong session when the shell is
spawned from a different TTY. That is a real bug already solved, and it is not
obvious. Actions: `focus-window`, `focus-workspace`, `focus-workspace-up/down`,
`move-column-to-workspace`, `focus-monitor`, `toggle-overview`, `close-window`,
`do-screen-transition`, `quit`, `reload-config`.

For Bioma: three cells depend on this (window title, workspaces, utility's
window mode). **No action centres a window on screen** — PRD §9.1 needs one, and
the exact name must be checked against niri 26.04.

### 3.2 WallpaperService + WallpaperWindow

Three modes — single, span, per-monitor — persisted as JSON at
`~/.config/prisma/wallpaper.json`, with a 300 ms debounce before writing.
`spanGeometry()` computes the bounding box over `Niri.outputs` and returns
per-screen offsets; `WallpaperWindow` is a `WlrLayer.Background` `PanelWindow`
that scales the image to the total box and translates negatively with `clip`.
No external daemon. This is the cleanest thing in Prisma.

Two things to check on arrival:

- `WallpaperWindow` declares `Behavior on source` with a `SequentialAnimation`
  over a **string** property. A `Behavior` cannot interpolate a string, so the
  intended crossfade very likely does not happen — the image swaps hard while
  the opacity animation runs against the already-swapped image. A real crossfade
  needs two `Image` layers. Verify before assuming the transition works.
- Geometry comes from `Niri.outputs` rather than `Quickshell.screens`, which
  makes the wallpaper compositor-specific for no reason.

### 3.3 MatugenService

Runs `matugen image <path> --json hex --old-json-output --source-color-index 0
--quiet` and parses the JSON from `~/.cache/prisma/colors.json`. It handles
**three** matugen formats: 4.x (`colors.primary.dark` as string or object),
2.x (`scheme-tonal-spot.dark.*`) and 1.x (`colors.<key>.default.hex`). Installed
here is matugen 4.2.0, so the 4.x path is the live one.

Its role mapping is deliberate and worth stealing: it takes `surface_variant`
for the background rather than `background`, because Material You always drives
`background` to near-black, and `surface_bright` for panels. Bioma's PRD §6.1
maps `background ← surface`; expect the same near-black problem and treat
Prisma's choice as the tested one.

Two divergences from Bioma's design, both deliberate on Bioma's side:

- **No templates.** Prisma reads matugen's `--json` output directly. Bioma's
  design is that matugen writes into Bioma's config directory *through a
  template* and the shell watches that file. The template does not exist in
  Prisma and must be authored.
- **It `sed`s a niri config file.** `_syncFocusRing()` rewrites `active-color`
  in `~/.config/niri/prisma-window.kdl`, then calls `reload-config`. Bioma's
  scope rule is explicit: *never parse or rewrite another program's config file
  for theming purposes* — that path is a matugen template plus a reload hook.
  Take the `#AARRGGBB` conversion helper, drop the `sed`.

### 3.4 SystemMonitorService — the largest gap

What it has: CPU percent from `/proc/stat` deltas, RAM used/total/percent from
`/proc/meminfo`, a top-80 process list from `ps -eo pid,comm,pcpu,pmem`, and
`kill -TERM`. Polls on two timers, 2 s and 3 s.

What Bioma's vitals cell needs and this does **not** provide:

| Needed by PRD §9.2 | Present |
|---|---|
| CPU **clock** — drives the cardiac beat rate | no |
| Moving average over the clock (mandatory — per-core boost is violently noisy) | no |
| GPU utilisation | no |
| GPU clock (encoded separately from utilisation — they diverge) | no |
| Battery presence, charge, charging state, time remaining | **no — nothing anywhere in Prisma** |

So vitals gets its RAM fill and its process list from here and nothing else.
Colour comes from percentages that exist; every motion in the cell — beat rate,
satellite rotation, battery direction — is driven by a quantity that has to be
sourced from scratch.

Note also that the PRD calls GPU sampling "the only expensive one". In fact
**every** sample here spawns a process: `sh -c head -1 /proc/stat` and
`sh -c grep /proc/meminfo` every 2 s, `ps` every 3 s. That is three process
spawns per 2–3 s for data available by reading two files. Bioma's rule — a
persistent process, never one per sample — applies to the rewrite of all of it,
not only to GPU.

### 3.5 AudioService

Default sink and source volume (0–1.5, PipeWire allows over 100%), mute, mic
mute, and a `PwObjectTracker` keeping the two default nodes bound.

Absent, and the whole of PRD §9.5's expanded state: **output device selection,
input device selection, and per-application volume.** Following PipeWire nodes
as they appear and disappear is not started here. The PRD's estimate that
per-app volume is "more work than the rest of that cell combined" stands, with
the correction that there is no foundation to build it on — only the default-node
convenience layer.

### 3.6 NetworkService

Wi-Fi comes from the **native** `Quickshell.Networking` module: device lookup by
`DeviceType.Wifi`, connected network, SSID, signal strength, and a 0–4 bar
bucket. Ethernet is polled every 10 s with `nmcli -t -f TYPE,STATE,DEVICE,CONNECTION
device`, accumulating into scratch properties and applying them atomically in
`onExited` — this is the shape the ethernet race fix took, and it is worth
preserving verbatim.

For Bioma's connectivity cell (§9.11), which draws one icon per *active*
connection: Wi-Fi and ethernet are covered, **bluetooth is not** — there is no
bluetooth service at all, only `settings/pages/BluetoothPage.qml`. Extracting a
`BluetoothService` out of that page is new work, and it is on the critical path
for the cell's central idea.

A 10 s ethernet poll is also too slow for a cell whose whole point is that its
width tells you what is live. Consider an event source.

### 3.7 NotificationService

`NotificationServer { keepOnReload: true }`, an array of tracked notifications,
`dismiss`, `dismissById`, `clearAll`, `count`. That is the whole file.

`NotificationPopup.qml` shows `notifications.slice(-3)` and dismisses each on a
timer of `expireTimeout` or 4000 ms.

Measured against PRD §9.10, what is missing is the entire temporal grammar:

- **Urgency is never read.** Critical notifications are dismissed after 4 s,
  which is precisely the freedesktop convention Bioma commits to honouring.
- **No queue.** `slice(-3)` silently drops the rest of a burst rather than
  collapsing to a count and deferring to history.
- **No hover-suspend**, and Bioma makes that mandatory here rather than
  optional, because the actions live in the hover state.
- **No action buttons** are rendered at all.
- **No history** beyond the in-memory array, which does not survive a reload.

Port the server. Everything above it is Bioma's to write.

### 3.8 BrightnessService

`brightnessctl get` / `max` / `set N%`, re-read after every write, refreshed
every 10 s. Single display only, no DDC for external monitors. Small and
correct for what it claims.

### 3.9 ScreenshotService

`captureRegion()` runs `slurp`, then `grim -g`. `captureScreen()` runs `grim`,
optionally `-o <output>`. `captureOCR()` is a single `sh -c` pipeline of
`grim -g "$(slurp)"` into `tesseract … stdout`. Signals for taken, cancelled,
OCR result.

Against PRD §9.6, what is missing is most of the cell:

- **No clipboard.** `wl-copy` appears nowhere in Prisma. Results go to
  `/tmp/prisma-shot.png` and stay there.
- **No screenshots folder**, no configurable destination.
- **No video recording at all** — neither `wl-screenrec` nor `wf-recorder`
  appears anywhere. The recording cell, the elapsed timer, the save-or-discard
  confirmation and the even-dimension rounding for H.264 are entirely new.
- **Selection is `slurp`.** Bioma draws its own selection over the full-screen
  input surface, so the `slurp` half is replaced, not ported. What survives is
  the `grim -g "<region>"` invocation and the tesseract pipeline.

Note the OCR path re-runs `slurp` inside its own shell rather than reusing the
region already selected — harmless in Prisma, wrong once Bioma owns selection.

### 3.10 PrismaIPC and ShellActions

`PrismaIPC` creates a FIFO at `$XDG_RUNTIME_DIR/prisma.ipc`, holds it open with
`exec 3<>`, reads lines in a shell `while` loop, and restarts itself 2 s after
exit. Niri binds `spawn sh -c "echo launcher > $FIFO"`. Each command emits a
`ShellActions` signal.

It works, and it is a shell loop kept alive to route five strings. Bioma's
invoked cells need the same capability; Quickshell's own IPC handler is the
place to start, with this file as the fallback if it proves insufficient.
`ShellActions` itself is the "second model for launcher, session menu and
settings" the PRD explicitly refuses — do not bring it.

---

## 4. Does not exist in Prisma at all

Listed because each is a cell or part of a cell in Bioma, and none of it is a
port:

- **Battery** — no UPower, no `BAT0`, nothing. Vitals' fourth indicator, its
  presence condition, its charge direction inversion.
- **GPU** — no sampling of any kind.
- **CPU and GPU clock** — only percentages exist.

  Where these four come from is settled, at least on this machine — see §4.1.
  None of them needs a new dependency.
- **Per-application volume**, output/input device selection.
- **Bluetooth service** — only a settings page.
- **Clipboard integration** — no `wl-copy`.
- **Video recording** — no recorder of any kind.
- **Cover art and playback position** — `MediaService` exposes title, artist,
  album, player name and transport only.
- **Audio signal capture / FFT** — Sinestesia is a separate Rust + GTK4
  application, to be split into a headless emitter and a renderer.
- **A full-screen transparent input surface** — the piece the PRD calls the most
  uncertain in the project. Nothing in Prisma prototypes it.

### 4.1 Where the missing vitals data lives

Checked on the development machine (AMD Radeon RX 9070 / Navi 48 discrete plus a
Raphael iGPU, no battery). Every quantity vitals needs is a plain file:

| Quantity | Source |
|---|---|
| GPU utilisation | `/sys/class/drm/card<N>/device/gpu_busy_percent` — an integer percent |
| GPU clock | `/sys/class/drm/card<N>/device/pp_dpm_sclk` — the line marked `*` is current |
| VRAM | `mem_info_vram_used` / `mem_info_vram_total` in the same directory |
| CPU clock | `/proc/cpuinfo`, `cpu MHz` per core — average these, then smooth |
| Battery | `/sys/class/power_supply/` — **empty here**, so this machine is the three-indicator case |

Two consequences.

**GPU sampling is not expensive on AMD.** The PRD treats it as the one costly
service needing a persistent process to avoid spawning per sample. On this
hardware it is a sysfs read, no more expensive than `/proc/stat`. The persistent
sampler is still the right shape — one process reading every source on a single
cadence — but the reason is uniformity, not GPU cost. On NVIDIA, where the
figure comes from `nvidia-smi`, the original concern stands; write the sampler so
the GPU source is swappable.

**Pick the right card.** `card0` here is the Raphael iGPU (512 MB of VRAM) and
`card1` the discrete RX 9070 (17 GB). Selecting by index is wrong; select by
VRAM size or by device id, and let the configuration override it.

`pp_dpm_sclk` also reports power states, not only frequencies — the discrete card
reads `S: 0Mhz *` while asleep. Parse a non-numeric state as "idle", not as a
failure, and do not let it reach the beat mapping as a zero.

---

## 5. Code that must not be ported as it stands

### 5.1 MonitorManager rewrites output blocks destructively

`_patchKdl()` strips **every** `output "NAME" { … }` block from
`~/.config/niri/config.kdl` using a brace-matching scan, then appends fresh
blocks containing **only** `position x= y=`.

Any other key inside an output block — `mode`, `scale`, `transform`,
`variable-refresh-rate`, `focus-at-startup`, `off` — is silently deleted the
first time the user drags a monitor. The write is also non-atomic
(`printf '%s' > file`) and unbacked: an interrupted write truncates the niri
config.

The PRD describes this as "non-destructive `niri.kdl` patching". It preserves
non-output *sections*; it does not preserve output *contents*.

Port the canvas, the drag, the 12 px magnetic snap and the virtual↔canvas
coordinate transforms — that is the part that took the work. Write the KDL with
a real edit: change the `position` line inside each existing block, leave the
rest of the block alone, write to a temporary file and rename.

### 5.2 KeybindsPage destroys multi-line binds on save

The parser matches one bind per line with
`/^([\w+\-]+)\s*((?:[\w\-]+=(?:"[^"]*"|\S+)\s*)*)\{([^}]+)\}/` — shortcut,
attributes, and a body that must close on the same line. A bind written across
several lines does not match and is dropped from `_binds`.

`_saveBinds()` then rebuilds the whole `binds { … }` block from `_binds` alone
and substitutes it into the file. So every bind the parser could not read, and
every comment inside the block, disappears on the first save.

What is genuinely valuable and should be ported: the **include-following**. It
reads `config.kdl`, finds `include` directives, scans each included file in
sequence and locates whichever one holds the top-level `binds` block. That is
the part nobody enjoys writing twice.

### 5.3 Everything that spawns `sh -c "echo $HOME"`

Five services resolve the home directory by starting a shell at startup and
waiting for its output before they can build any path, which is why they all
carry a `_homeDir` property and a "do nothing until it arrives" guard. Bioma
reads the environment directly. Dropping this removes a startup ordering hazard
and about a dozen lines per service.

---

## 6. Corrections to the PRD's picture of Prisma

The PRD's service table was written from memory of the project, and six of its
statements do not survive reading the source. None invalidate a design decision;
two change the size of a phase.

1. **"Niri IPC — complete."** Complete, but mostly because
   `Quickshell.Niri` is complete. The port is small. The socket-detection trick
   is the part worth carrying.
2. **"matugen — already adapted to matugen 2.x `scheme-tonal-spot`."** It handles
   1.x, 2.x *and* 4.x, and 4.x is the live path against the installed matugen
   4.2.0. Better than advertised. It also does not use templates at all, and it
   patches a niri config with `sed` — which Bioma's own scope rule forbids.
3. **"Network — Wi-Fi + ethernet via `nmcli`."** Only ethernet is `nmcli`. Wi-Fi
   is the native `Quickshell.Networking` module. And there is no bluetooth
   service to port, only a settings page — that is new work on the connectivity
   cell's critical path.
4. **"Dock carries the expensive part: window tracking, desktop-file icon
   resolution, matching processes to applications."** Window tracking is
   `Niri.windows.values.some(w => w.appId === id)`. Icon resolution is
   `Quickshell.iconPath()` plus `DesktopEntries.heuristicLookup()`, both native,
   about ten lines including the fallback that suppresses a 404 when the name
   does not resolve. Matching processes to applications does not exist. The rest
   of the dock is presentation Bioma does not want — circular icons, a hash
   colour per app-id, a dot indicator. **Treat the dock as low reuse value**,
   alongside the launcher. The ten lines of icon resolution are still exactly
   what PRD §9.1 asks for, and the "plain name means unresolved" guard is worth
   copying verbatim.
5. **"System monitor — GPU sampling must be added and is the only expensive
   one."** Every existing sample already spawns a process. The rewrite is
   broader than adding GPU.
6. **"Prisma's `PROGRESS.md` documents feature status."** It is dated
   2026-05-05/07 and is partly stale against the 05-08 sources — it records the
   wallpaper being applied through `swww → wpaperd → swaybg`, while the current
   `WallpaperService` renders natively in QML with no daemon. Read it for the
   bug list, not for the architecture.

---

## 7. Bugs already fixed — do not re-introduce

From `PROGRESS.md`, confirmed against the source where possible:

- **Dock reveal zone must be inside the surface bounds.** The `PanelWindow`
  height includes the hover zone and `exclusiveZone` excludes it. Bioma hits the
  same class of bug with auto-hiding membranes, which must remain present as a
  surface with a few-pixel reveal zone.
- **Ethernet detection race** — a single process accumulating into scratch
  properties and applying them atomically on exit, never property-by-property as
  lines arrive.
- **File picker layer ordering** — the settings surface drops to the Bottom
  layer before an external picker opens, via signals, with `Qt.callLater`
  deferring the dialog until the layer switch has committed.
- **`NIRI_SOCKET` from the wrong session** — resolve the socket by globbing on
  `$WAYLAND_DISPLAY` rather than trusting the inherited variable.
- **Icon resolution needs an explicit `size`** on `IconImage`, or icons fall
  back to letters.
- **`FileView` double-fire** — KeybindsPage reads config through `cat` processes
  specifically to avoid it. Worth knowing before `core/Config.qml` is trusted:
  Bioma uses `FileView` with `watchChanges` for both config layers and both
  palette sources.

---

## 9. What Quickshell 0.3.1 changes — read this before porting anything

Everything above was written from Prisma's source alone. With Quickshell
installed and probed, several verdicts move, all but one in our favour.

### 9.1 `Quickshell.Niri` does not exist

There is no Niri module in 0.3.1 — `Hyprland` and `I3` are there, Niri is not.
Prisma was built against one, so **the data half of `NiriIPC` cannot be ported
at all**: it will not compile. Every consumer of it in Prisma is affected too —
the dock, the OSDs, `WallpaperService.spanGeometry()` and `MonitorManager` all
read `Niri.outputs` or `Niri.windows`.

`services/Niri.qml` is written instead against niri's own IPC socket: one
connection, one `"EventStream"` request, then newline-delimited JSON events for
the life of the session. Push-based, nothing polls. The fourteen event variants
niri 26.04 emits are all handled.

This is **better** than what Prisma had, not worse. The socket carries window
geometry, pids, workspace indices and output names — none of which the
compositor-agnostic protocols provide, and the pid in particular is what makes
matching a process to a window possible, which Prisma could not do.

### 9.2 Much of what the inventory called "new work" is native

| Called missing in §4 | Actually available |
|---|---|
| Battery — "nothing anywhere in Prisma" | `Quickshell.Services.UPower`: `UPower.displayDevice`, `isLaptopBattery`, device states, plus `PowerProfiles` |
| Bluetooth service — "new work on the critical path" | `Quickshell.Bluetooth`: adapter, devices, pairing states |
| Ethernet, replacing the 10 s `nmcli` poll | `Quickshell.Networking` exposes `WiredDevice` alongside `WifiDevice` — the poll goes away entirely |

Probed on this machine: `Networking.devices` returns `eno1` (wired) and `wlan0`
(wifi) natively; `UPower.displayDevice.isLaptopBattery` is false, agreeing with
the empty `/sys/class/power_supply/` and confirming the three-indicator case.

Also present and worth knowing before writing anything by hand:
`ToplevelManager` and `WindowManager` (compositor-agnostic windows and
workspaces — the fallback if Bioma ever leaves niri), `IpcHandler` (replaces
PrismaIPC's FIFO), `FileView.setText` and `writeAdapter` (config writes with no
shell process, unlike every save in Prisma), `ColorQuantizer` (colours from an
image), `Socket` and `SocketServer`.

### 9.3 Blur is confirmed, on both sides

`Quickshell.Wayland._BackgroundEffect` exports `BackgroundEffect` with an
animatable `blurRegion`, and niri 26.04 advertises `ext_background_effect_v1`.
The PRD's §6.6 plan — declare the cell shapes as blur regions, never a
compositor layer rule — is supported exactly as designed. niri also advertises
`ext_foreign_toplevel_list_v1` and `ext_workspace_v1`, which is what makes the
agnostic fallback real rather than theoretical.

### 9.4 The trap that costs a day

**Quickshell singletons and compositor-backed models initialise on their first
property binding, not on first access.** Probed imperatively from inside a
function, `ToplevelManager.toplevels`, `UPower.devices`, `Networking.devices`
and `Bluetooth.devices` all returned empty on a live session with four windows
open. Bound to a property first, they filled immediately.

Nothing in the API hints at this, and the failure looks exactly like "the
service is broken" or "this compositor does not support it". `probe.qml` binds
before it reads, and every service added to it must do the same.

Two collection shapes also coexist: most are an `ObjectModel` and want
`.values`, but `WindowManager.windowsets` is a plain JS array.

### 9.5 Answers to two PRD verification items

- **`center-window` exists in niri 26.04** and centres the *focused* window.
  The window title cell shows the focused window, so no prior focus call is
  needed there; anything else centring a window must focus it first.
- **Window titles churn harder than expected.** Measured on a terminal running a
  spinner: ten title events in eight seconds, one window. PRD §9.1 asks for
  debouncing; treat it as required, not advisory.

---

## 10. Notes from the wallpaper port

The one service the PRD marked "port as-is" needed four changes, three of them
forced.

- **Geometry moved to `Quickshell.screens`.** Not a preference: `Niri.outputs`
  does not exist in this Quickshell (§9.1). The arithmetic is unchanged and was
  verified against the real layout — a 3440×1440 output at 0,0 above a
  1920×1080 at 760,1440 gives a 3440×2520 box, with the second screen drawing
  the image at 1.79× its own width and offset into its own portion.
- **The crossfade was broken, as suspected.** `Behavior on source` over a string
  cannot interpolate: the image swapped hard while the opacity animation ran
  against the already-swapped picture. Replaced with two image layers, where the
  incoming one is decoded before anything fades.
- **Persistence uses `FileView.setText` with `atomicWrites`**, not a `printf >`
  shell process. Worth carrying to `MonitorManager` and `KeybindsPage`, whose
  non-atomic writes are half of what makes §5.1 and §5.2 dangerous.
- **`$HOME` is read from the environment**, not awaited from `sh -c "echo $HOME"`,
  which removes the startup ordering guard the Prisma services all carry.

Two things the port surfaced that Prisma never had to face:

- **Returning to an image the idle layer still holds** — stepping back and forth
  through a folder, which the theme cell invites — revealed nothing, because the
  early-return for "already loaded" skipped the reveal as well as the reload.
  Found by testing the sequence rather than the single transition.
- **`sourceSize` matters here.** A 6000 px photograph decoded at full size costs
  that much memory once per screen, per layer. Decoding at the size actually
  drawn is not an optimisation at two layers times two monitors.

The wallpaper mode is persisted as state in `~/.config/bioma/wallpaper.json`
rather than in the configuration layers, deliberately: the theme cell rewrites it
every time the user tries an image, and that churn belongs neither in a file a
human hand-edits nor in the settings override that has to merge cleanly against
it. Only the wallpaper *folder* is configuration.

---

## 11. Notes from the matugen port

Almost nothing was ported. Prisma's service is 221 lines, of which about 120 are
a parser carrying three matugen JSON formats — and a template makes all of it
unnecessary. `services/Matugen.qml` runs the binary and reads nothing back:
matugen renders `config/matugen/palette.json` into
`~/.config/bioma/generated/palette.json`, `core/Theme.qml` watches that file,
and the two never meet.

The gain is not only the line count. Format drift now lands in a text file
rather than in the shell — the exact failure that left Prisma carrying 1.x, 2.x
and 4.x code paths at once. And it is the same mechanism that will propagate the
palette to GTK and niri: one block in `config/matugen/config.toml` each, no
shell change, which is what the requirement that a new consumer cost one config
block actually means here.

**Bioma ships its own matugen config** and passes it with `--config`. The user's
`~/.config/matugen/` is neither read nor written, and the scope rule — never
rewrite another program's config file for theming — holds without an exception
for matugen itself. Prisma's `_syncFocusRing()`, which `sed`s `active-color` in a
niri config file, is not ported; when the focus ring is wanted it becomes another
template plus a reload hook.

### 11.1 More drift than the PRD expected

The PRD describes matugen 2.x. Installed here is **4.2.0**, and Prisma's exact
invocation now fails: with several candidate source colours and no terminal
attached, matugen 4.x refuses rather than defaulting. `--source-color-index 0`
restores the old behaviour and keeps the choice reproducible; the newer
`--prefer` is the alternative.

Template syntax, verified rather than assumed: `{{colors.<role>.<default|dark|
light>.hex}}` and `{{image}}`, where `default` follows `--mode`. Output paths
expand `~` and matugen creates missing directories itself. Relative
`input_path` resolves against the working directory, which is why the service
runs the process with `config/matugen` as its own.

### 11.2 The background role: the PRD is right, Prisma was solving a real problem

Prisma deliberately mapped the background to `surface_variant` rather than
`surface`, because "Material You always makes background near-black". Measured
on the current wallpaper at scheme-tonal-spot, dark:

| role | dark | light |
|---|---|---|
| `surface` | `#0e1415` | `#f4fbfa` |
| `background` | `#0e1415` | `#f4fbfa` |
| `surface_variant` | `#3f4949` | `#dae4e4` |
| `surface_bright` | `#343a3a` | `#f4fbfa` |

`surface` and `background` are identical, and both are very dark — tinted, not
literally black, but dark enough that Prisma's complaint was not imaginary.
Bioma keeps the PRD's one-to-one mapping anyway, for two reasons that did not
apply to Prisma: the cell and tissue fills are semi-transparent over a
wallpaper, so a deep background is the point rather than a problem, and the
lighter surfaces Prisma had to borrow from matugen are derived in
`core/Theme.qml` by luminance shift instead — `#0e1415` yields `#1c2223` and
`#2b3031`, a ladder that stays coherent by construction where two unrelated
Material You roles would not.

### 11.3 Verified

Palette file deleted, then regenerated end to end during a probe run: wallpaper
change → matugen → template → file watch → `Theme`. The transition is animated,
not applied: ten intermediate frames between the built-in palette and the
generated one, which is what makes the theme cell able to retint the desktop
live.

A failing generation leaves the current palette standing rather than clearing
it. Error reporting needed fixing to be worth anything: matugen prints a
numbered cause chain followed by two lines about backtraces, so the last line of
stderr is "Run with RUST_BACKTRACE=full" and the first is "Failed to get source
color". The deepest numbered line is the one that says what actually happened.

---

## 12. Notes from the media port

Prisma's service is 35 lines: it picks an active player and exposes title,
artist, album and three transport calls. What it lacks is everything the
expanded Sinestesia cell asks for — cover art, position, length, seeking, and a
way to choose among several players. All of it is already on `MprisPlayer`
(`trackArtUrl`, `position`, `length`, `canSeek`, `seek`), so this was less a port
than a matter of exposing what was there.

### 12.1 `uniqueId` is not unique

With two players running at once, **both report `uniqueId` 1**. Selecting by it
does not fail loudly: it finds the first match and silently controls the wrong
player — exactly the bug that would be blamed on the dropdown rather than on the
service. `dbusName` is unique by construction, and is what the selection holds.

Found by running two fixtures at once. One player would never have shown it, and
neither would reading the API.

### 12.2 Position is the only poll

MPRIS does not push position. A player answers when asked and emits `Seeked`
only when the position jumps, so a progress indicator has to ask. The timer runs
only while something is actually playing and the player supports position at
all, so a paused or absent player costs nothing.

One second is right for text. A smooth bar interpolates between ticks rather
than asking more often — each ask is a D-Bus round trip, per tick, per player.

### 12.3 What this service is not

It is **not** what raises the Sinestesia cell. The PRD is explicit that the
visualiser and the metadata are two independent inputs and that the cell's
condition is the audio signal: a game, or a browser tab with no MPRIS player,
still has sound and the cell must still appear. Choosing a different player here
changes the text beside the visualiser and nothing else.

### 12.4 Test fixture

`scripts/mpris-dummy.py` publishes a silent MPRIS player with a live position and
working transport methods — no audio device touched, no package installed. Two
copies with different `--name` values exercise selection. mpv would have needed
`mpv-mpris`, and playing real audio to test a service is a poor trade.

Verified through it: discovery of two players, the preference order (chosen →
playing → first), explicit selection by D-Bus name, `next`, `playPause` and
`seek` all reaching the player, position advancing, and progress agreeing with
the seek — 64 s of 320 s reported as 20%.

### 12.5 The shell to switch off is not Prisma

§7's blocking constraint is live right now, and against a different shell than
the inventory assumed: **Noctalia is the running shell on this machine**, and it
owns `org.freedesktop.Notifications` and `org.kde.StatusNotifierWatcher`. That is
what must be disabled before Bioma's notification cell can be tested. Media,
being read-only, coexists with it perfectly well.

---

## 13. Notes from the audio port

The PRD calls per-application volume "more work than the rest of that cell
combined", and against a raw PipeWire API it would be. Against
`Quickshell.Services.Pipewire` it is a filter over `Pipewire.nodes` and a
`PwObjectTracker`. Appearing and disappearing streams are handled by the model,
not by us. **Revise that estimate down**: what remains expensive in the volume
cell is its interface, not its data.

### 13.1 `isSink` and `isStream` are not enough, and fail plausibly

Filtering inputs as "not a sink and not a stream" produced eleven microphones,
including `Dummy-Driver`, `Freewheel-Driver`, `Midi-Bridge`, `BLE MIDI 1` and
both webcams twice. PipeWire's graph holds its own driver nodes, MIDI bridges
and every video device, and all of them answer false to both.

The node type is a flag set — Audio 1, Video 2, Stream 4, Source 8, Sink 16 —
so an audio source is 9 and a video source is 10. Masking separates them where
a boolean cannot:

| List | Test |
|---|---|
| outputs | `type & AudioSink === AudioSink` (17), not a stream |
| inputs | `type & AudioSource === AudioSource` (9), not a stream |
| playing applications | `type & AudioOutStream === AudioOutStream` (21) |
| recording applications | `type & AudioInStream === AudioInStream` (13) |

Correctly filtered, this machine has five outputs and five inputs, the webcam
microphones among them legitimately.

Two smaller findings. The `.monitor` source that every sink publishes **does not
appear as a node at all** — `pactl` lists them, Quickshell does not — so the code
written to filter them out was dead, and the visualiser will need another way to
reach one. And something on this machine holds a recording stream permanently:
an indicator built naively on "is anyone recording" would claim the microphone is
live at all times.

### 13.2 PwObjectTracker is not bookkeeping

A node that nothing tracks stays unpopulated: its `audio` is null and its volume
reads zero. In a list of applications that is indistinguishable from a muted
application, so the failure is silent and looks like a bug in the cell. Every
node the service exposes is tracked.

### 13.3 The signal source for Sinestesia already exists

`PwNodePeakMonitor` reports a live peak, per channel, for any node. Verified
against a 440 Hz tone: 0.445 across two channels, while the real default sink
correctly read 0 because nothing was playing through it.

This matters for the cell's **condition**, which the PRD defines as the audio
signal rather than MPRIS playback — a game or a browser tab with no metadata
must still raise it. That condition needs one number, and here it is: no
capture, no FFT, no external process. The split of Sinestesia into a headless
emitter and a renderer is still required for the **bands** the visualiser draws,
but not for deciding whether the cell exists.

### 13.4 Verified

Against the live graph: five outputs and five inputs correctly separated from
drivers, MIDI and video; default output and input identified; per-application
volume set to 25% and back to 100%, and mute toggled, each confirmed
independently through `pactl`; peak monitoring proved against a real tone.

Testing per-application volume needs a stream, and playing audible sound to test
a service is a poor trade, so the tone went into a temporary `module-null-sink`
which was unloaded afterwards. The user's default sink was never touched.

---

## 14. Notes from the brightness port

The inventory called this "the smallest and most complete relative to its job".
It is neither, on this machine: **there is no backlight device at all.**
`/sys/class/backlight/` is empty, because both monitors are external, and
`brightnessctl -l` offers only keyboard LEDs and a network-card LED. Prisma's
service would read nothing, report a confident 0.5, and control a caps-lock
light at worst.

This is the first ported service where the Prisma version is not merely dated
but inapplicable, and it is worth stating why the failure is bad rather than
merely useless: a brightness control that reports a number and changes nothing
is indistinguishable, from the user's side, from a broken monitor.

So the service has two backends and, above all, a capability check.

| Backend | Route | Notes |
|---|---|---|
| `backlight` | `/sys/class/backlight` read directly, written through `brightnessctl --class=backlight` | Laptops. Fast. |
| `ddc` | DDC/CI over I²C through `ddcutil` | External monitors. Slow — a round trip per call — and not always permitted. |

With neither present the service reports `available: false` and every control is
a no-op. Nothing above it should be visible in that case: a control that cannot
change anything is exactly what principle 4 excludes.

### 14.1 Two backlights is the normal case, and the glob picks by alphabet

A laptop commonly exposes a native backlight *and* `acpi_video0`, the generic
fallback. Reading the enumeration line by line and keeping the last leaves the
choice to alphabetical order, which is arbitrary and differs between machines.
Candidates are now collected and one is chosen deliberately, preferring anything
over `acpi_video*`, and writes name that device explicitly instead of letting
`brightnessctl` guess again.

Verified against a fabricated `/sys/class/backlight` tree, since there is no
real one here: two devices, `intel_backlight` at 812/1024 and `acpi_video0` at
50/100, parse to 0.793 and 0.500 and the native device is the one chosen.

### 14.2 DDC is written but unverified

`ddcutil` is not installed, so the DDC path has never run. The prerequisites are
in place — `i2c-dev` is loaded and `/dev/i2c-*` exist — but the user is in
`video` and not `i2c`, which DDC access may still require.

What is verified is the **absence** path: with no backlight and no `ddcutil`, the
probe exits cleanly, the backend reports `none`, and nothing fabricates a value.

DDC is never polled. A read is one I²C round trip taking a good fraction of a
second, so each display is read once at startup and the service's own writes are
the only thing that moves it afterwards — a monitor adjusted by its own buttons
will go unnoticed, which is the right trade against hammering the bus. Writes
are debounced, or dragging a slider queues fifty round trips.

### 14.3 There is no brightness cell

Worth noting while this is fresh: the cell catalogue has no brightness cell. The
PRD mentions brightness only in passing, in the deferred question of a
system-wide OSD. This service therefore has no consumer yet, and on this
hardware it would have nothing to say if it did.

---

## 8. Port order

Mapped onto PRD §10 phase 1. Each line is verified without UI before any cell
depends on it.

1. ~~**NiriIPC**~~ — **done**, as `services/Niri.qml`, rewritten against the
   IPC socket (§9.1) and verified through `probe.qml`: four windows with
   geometry and pids, six workspaces across two outputs, live title updates.
   `center-window` confirmed.
2. ~~**WallpaperService + WallpaperWindow**~~ — **done**, as
   `services/Wallpaper.qml` and `structure/WallpaperSurface.qml`. The crossfade
   suspicion in §3.2 was correct and is fixed; geometry now comes from
   `Quickshell.screens`, which is no longer an improvement but a requirement
   (§9.1). Verified on two outputs, span arithmetic included.
3. ~~**MatugenService**~~ — **done**, as `services/Matugen.qml` plus
   `config/matugen/`. The parser was not ported at all (§11); the `sed` and the
   focus-ring patch are gone.
4. ~~**MediaService**~~ — **done**, as `services/Media.qml`, with a test
   fixture in `scripts/mpris-dummy.py`. See §12.
5. ~~**AudioService**~~ — **done**, as `services/Audio.qml`. Per-application
   volume turned out to be far less work than the PRD estimated (§13).
6. ~~**BrightnessService**~~ — **done**, as `services/Brightness.qml`, with a
   DDC backend the machine cannot yet verify (§14).
7. **NetworkService** — port, replace the 10 s ethernet poll, then extract a
   BluetoothService out of `BluetoothPage`.
8. **System monitor** — rewrite around one persistent sampler; add clock, GPU
   and battery.
9. **ScreenshotService** — port the `grim` and `tesseract` calls only.
10. **NotificationService** — **last.** One owner per session: the cell cannot be
    tested while another shell runs.

Outside this list and not blocking: `MonitorManager` and `KeybindsPage` arrive
with phase 5, each needing its writer rewritten (§5.1, §5.2).
