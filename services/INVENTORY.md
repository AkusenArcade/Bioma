# Service inventory

The first pass over Prisma produces this document and no code: which services
exist, what each actually does, which are self-contained and which are entangled
with `Bar.qml`.

Prisma lives at `~/.config/quickshell/prisma`. It is **not under version
control**, so this is copy-and-adapt, not merge, and there is no diff to review.
Its sources predate the current Quickshell release — expect API drift.

**Work into this structure, never out of the old one.** Ask for a specific
capability and bring it here. Port service by service and verify each *without
UI* before a cell depends on it: a service that silently returns stale data is
far harder to diagnose once there is a face on top of it.

| Service | Prisma source | Status | Notes |
|---|---|---|---|
| Niri IPC | `services/NiriIPC.qml` | not started | Complete in Prisma: workspaces, windows, outputs, focus actions, `reload-config`. Push-based event stream, not polling. Three cells depend on it. |
| Wallpaper | `services/WallpaperService.qml`, `bar/WallpaperWindow.qml` | not started | Port as-is. Native QML rendering on a Background-layer `PanelWindow`, no external daemon. Modes: single, span, per-monitor. |
| matugen | `services/MatugenService.qml` | not started | Already adapted to matugen 2.x `scheme-tonal-spot`. |
| System monitor | `services/SystemMonitorService.qml` | not started | CPU/RAM/process present. **GPU sampling must be added** — the only expensive one; use a persistent process, never one per sample. |
| Audio | `services/AudioService.qml` | not started | Per-application volume means following PipeWire nodes as they appear and disappear — more work than the rest of that cell combined. |
| Network | `services/NetworkService.qml` | not started | Wi-Fi + ethernet via `nmcli`. Watch the ethernet detection race Prisma already fixed. |
| Notifications | `services/NotificationService.qml` | not started | **Blocking**: one owner per session. Cannot be tested alongside another running shell. Build last (PRD §10, phase 4). |
| Brightness | `services/BrightnessService.qml` | not started | |
| Screenshot | `services/ScreenshotService.qml` | not started | `grim`, `slurp` and `tesseract` OCR already wired. Selection UI is Bioma's own, not `slurp`. |
| Media | `services/MediaService.qml` | not started | MPRIS. Independent of the audio signal feeding the visualiser — two inputs, not one. |
| Monitor layout | `dashboard/MonitorManager.qml` | not started | Drag-and-drop with magnetic snap; writes `niri.kdl` preserving non-output sections. Substantial and working. |
| Keybinds | `settings/pages/KeybindsPage.qml` | not started | Parses the `binds` block, writes, calls `niri msg action reload-config`. |
| OSD | `osd/VolumeOSD.qml`, `BrightnessOSD.qml`, `WorkspaceOSD.qml` | deferred | Whether Bioma adopts a system-wide OSD is an open question (PRD §11). |

## Do not port

- `bar/Bar.qml` — the bar-model monolith.
- `bar/SysStats.qml` — numeric CPU/RAM readout, the opposite of Bioma's indicators.
- `services/I18n.qml` — English-only project.

## Low reuse value

- `launcher/*` — substring match over name/genericName/id, alphabetical sort.
  Functional, but fuzzy matching, frequency ranking and icon resolution are
  absent, and those are the launcher.

## Bugs Prisma already fixed — do not re-introduce

- Dock reveal zone must be **inside** the surface bounds.
- File-picker layer ordering.
- Ethernet detection race.
