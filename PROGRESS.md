# Progress

Where the work stands. `services/INVENTORY.md` holds the detail and the
reasoning; this is the short version and the list of what is *not* done.

Last worked: 2026-09-18.

## Phase 0 — Foundations

Scaffolded, partly real, not finished.

| Piece | State |
|---|---|
| `core/Config.qml` | Working. Two layers, deep merge, hot reload. |
| `core/Theme.qml` | Working. Four roles from a source, three fixed, the rest derived. Animated. |
| `core/Timing.qml`, `core/Scale.qml`, `core/Typography.qml` | Working, unused so far. |
| `structure/Visibility.qml` | Written. Dual threshold, confirm, dwell that resumes. **Never exercised.** |
| `structure/Membrane.qml`, `Tissue.qml`, `Cell.qml` | Skeletons. Every real behaviour is a TODO naming its PRD section. |
| `shell.qml` | Instantiates wallpaper surfaces per screen. Membrane instantiation is a stub. |

**Nothing of the layout engine has ever been drawn.** Percentage sharing, reflow,
growth away from the anchor, the slot model for reserved space, auto-hide, blur
regions — all still to write.

The full-screen transparent input surface (PRD §8) has not been prototyped, and
the PRD calls it the single most uncertain piece in the project.

## Phase 1 — Service porting

Six of ten done, each verified headlessly through `probe.qml` before moving on.

| Service | State |
|---|---|
| `services/Niri.qml` | Done. IPC socket event stream, 14 event types, actions. |
| `services/Wallpaper.qml` + `structure/WallpaperSurface.qml` | Done. Four modes, crossfade, persisted state. |
| `services/Matugen.qml` + `config/matugen/` | Done. Template-rendered palette, watched by Theme. |
| `services/Media.qml` | Done. MPRIS metadata, art, position, transport, player selection. |
| `services/Audio.qml` | Done. Devices, per-application volume, peak monitor. |
| `services/Brightness.qml` | Done. Backlight and DDC backends. |
| Network | **Next.** Replace the 10 s `nmcli` poll with native `WiredDevice`; extract a bluetooth service — `Quickshell.Bluetooth` exists, so Prisma's 372 inline page lines are not the starting point. |
| System monitor | Rewrite, not port. One persistent sampler; add CPU clock, GPU, battery (§4.1, §9.2). |
| Screenshot | Port the `grim` and `tesseract` calls only. |
| Notifications | **Last.** See below. |

### Verified, and not

Everything above was checked against live state. Two gaps are known:

- **The backlight path of `Brightness.qml`** has only ever run against a
  fabricated `/sys/class/backlight` tree. This machine has no backlight. The DDC
  path is verified against both real monitors.
- **`structure/Visibility.qml`** has no test at all. It is the heart of the
  temporal grammar and the first cell will be its first exercise.

### Before notifications can be touched

`org.freedesktop.Notifications` has one owner per session, and on this machine
that owner is **Noctalia**, which is the running shell. It also holds
`org.kde.StatusNotifierWatcher`. It has to be switched off first, and that is
the point of no return the PRD describes.

## How to check the state of things

```sh
qs -p "$PWD/probe.qml"      # every service, headless, no surfaces
```

Allow six seconds: DDC detection alone costs three and a half.

`scripts/mpris-dummy.py` publishes a silent MPRIS player for testing the media
service; run two with different `--name` values to exercise player selection.

## Decisions taken since the PRD was written

Recorded in full in `services/INVENTORY.md` §9–§14. The ones that change the
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
