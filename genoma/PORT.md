# Bioma on Genoma

This directory is Bioma written on **Genoma**, the Rust and Luau toolkit
meant to replace Quickshell under it
(`~/Documents/Development/Genoma`, its PRD and `docs/m6-plan.md`). The shell
is still Bioma; Genoma is only what it runs on.

It lives beside the Quickshell version, which stays feature complete and
keeps being refined. The two share what is Bioma's rather than Quickshell's:
`docs/` (normative, as ever), `config/`, the person's `override.json`,
`assets/` and `scripts/`. The AUR package leaves this directory out until it
is ready.

## Running it

```
scripts/genoma
```

It needs Genoma's runtime: `$GENOMA_BIN`, or `genoma` on the `PATH`. Until
Genoma is packaged, point `GENOMA_BIN` at its build
(`…/Genoma/target/release/genoma`).

## Who draws what

The port goes surface by surface, the two shells side by side. A block in
the configuration marked

```json
"runtime": "genoma"
```

is drawn by Bioma on Genoma, and Bioma on Quickshell leaves it out. Today
that key is read on membranes and floating tissues; the surfaces that are
not configuration blocks (the wallpaper, the organisms, the OSD) get their
own when they are ported. Notifications move last: the session's
notification name has one owner.

## Parity

A surface is ported when its checklist is ticked from a side-by-side
capture, Akusen has looked at the two, and its cost is measured against the
same surface on Quickshell. Each ported cell records the commit of the QML
it was taken from, so `git log <commit>.. -- cells/<name>` shows what
changed on Quickshell since and has to be carried over.

## The feature list

Taken from the code at 5e5ff60 (beta.59), 2026-10-28, and checked against
the PRD's cell catalogue (§9). Every catalogue entry exists in the code
(the session menu as `system`, sinestesia as `media`, setup inside
`settings`); the code has a good deal the catalogue does not, marked
*beyond the PRD*, and all of it is ported. The check is at the level of the
catalogue: whether each cell does all its section describes is checked when
that cell is ported, against its QML, and a gap found then is Bioma's work,
not the port's.

The order is the PRD's build order (§10).

### Foundations

- [x] Config: `config/default.json`, then `override.json`, watched, written
      back atomically. (`genoma/core/config.luau`, from `core/Config.qml` at
      5e5ff60.)
- [x] Theme (roles, sources, palettes, matugen) as animated signals.
      (`core/theme.luau`, `core/colour.luau`; the list of palettes on offer
      comes with the theme cell.)
- [x] Timing, Metrics, Typography from `docs/design/tokens.css`.
      (`core/timing.luau`, `core/metrics.luau`, `core/typography.luau`;
      performance mode's instant transitions come with its service.)

Checked 2026-10-28 (`BIOMA_GENOMA_CHECK=1 scripts/genoma`):
- With the shipped palette the derived colours are Qt's to the byte
  (elevated `#1d2418`, cell `#252d1f`, line `#4f643f`, node `#6a8755`, rim
  `#88a772`, the gradient's `#dbf4a7` and `#94bc41`), computed by Qt with
  Theme.qml's functions. The token set wrote them rounder; at Akusen's word
  it now has Qt's values (c969d89).
- A palette changed in the override crossed in 32 steps of 8 ms, the four
  roles together, from the default to `paper`.
- `config.set_many` changed `appearance.gap` and added one key, and left
  the other 1,282 lines of the override as they were.
- At rest, 20 s: no thread woke.
- [x] Structure: membrane, tissue, cell, the registry, visibility types,
      expansion by budding (Akusen, 2026-10-28), the input surface,
      floating tissues, the host, and invocation by name.
      (`genoma/structure/`, from `structure/*.qml` and `core/Focus.qml` at
      5e5ff60.) A floating block takes `"runtime": "genoma"` as a membrane
      does; a keybind reaches a cell with
      `scripts/genoma ipc cell toggle <domain> [output]` (`close`, `list`),
      on the output the keyboard is on unless it names one.
      Still to come, each with what it needs:
      - no shadow, on panels or floating tissues, until Genoma has a soft
        shadow; a panel's content fades but does not grow from its centre;
        a summoned cell fades in rather than growing into place;
      - `"anchor": "pointer"` and cells that come to the pointer, which need
        the pointer's position; a floating tissue holding its place while
        the pointer is on what it opened;
      - keyboard travel inside an open cell (arrows, Tab, Enter), with the
        first cell that has something to travel through;
      - the input surface and the hosts stay mapped for the whole session,
        transparent: Genoma cannot yet unmap a surface with nothing in it.

Checked 2026-10-28, a probe membrane on HDMI-A-1 (`cells/probe.luau`,
three tissues at 25/30/25 %, the geometry logged from Luau):
- The end tissue ends 10 from the edge (the margin, measured to the cell),
  the centre one is centred on the output, and an elastic cell asking for
  more than its `max_percent: 10` is granted 192 of 1920 and ends in an
  ellipsis.
- Pressing the centre probe three times lengthened it 74 → 120 → 166 →
  212, the tissue growing about its centre with every step animated.
- The centre tissue's ceiling changed in the override, live: at 20 % the
  elastic cell gave way (192 → 159), at 12 % it no longer fitted and was
  not placed, at 30 % it came back.
- A conditional probe whose condition lasts 5 s on and 5 s off left 2 s
  after the condition ended (the default dwell) and came back with it,
  the start tissue reflowing each time.

Checked 2026-10-29, probes with a panel on the same membrane:
- Pressed, the start probe's panel budded from the middle of its bottom
  edge, the neck narrowing and parting, without crossing the cell beside
  it (seen at `timing.speed` 15); a press on the desktop took it back.
- With the start probe open, a press on the centre probe closed the one
  and opened the other.
- While a cell was open its membrane on HDMI-A-1 and the input surface on
  DP-1 held the keyboard (`niri msg layers`: exclusive); Escape closed the
  cell and both let the keyboard go.
- A conditional cell appearing fades in at its place; it used to slide
  there from the tissue's start.

Checked 2026-10-29, a floating block (bottom-right, vertical) and the
host, driven only by `scripts/genoma ipc`:
- The floating tissue sat above the bottom strip at the right margin; a
  cell in it with `"visibility": { "type": "invoked" }` appeared on
  `cell toggle probe HDMI-A-1`, holding the keyboard, and left on the
  second call, letting it go.
- A domain placed nowhere was summoned into the middle of HDMI-A-1 by its
  host and left on the second call; once gone it was no longer in the
  register.
- Escape, from an empty workspace, sent off both the summoned cell and
  the invoked one.
- An unknown target or domain is answered, not ignored (`no target`,
  `no invocable cell`); a save in `structure/` reloads the interface.

### Cells

| Cell | PRD | Phase | Ported from | State |
|---|---|---|---|---|
| window_title | §9.1 | 2 | 670c660 | checked 2026-10-29, awaiting Akusen and the cost |
| workspaces | §9.3 | 2 | 7ea52ac | checked 2026-10-29, awaiting Akusen and the cost |
| vitals | §9.2 | 2 | 30c6cc7 | contracted checked 2026-10-29; expansion to come |
| clock | *beyond the PRD* | 2, with the membrane | 7e62c5c | contracted checked 2026-10-29; expansion to come |
| media | §9.4 (sinestesia) | 3 | | |
| theme | §9.7 | 3 | | |
| utility | §9.6 | 3 | | |
| audio | §9.5 | 4 | | |
| connectivity | §9.11 | 4 | | |
| system | §9.8 (session menu) | 4 | | |
| dock | §9.9 | 4 | | |
| tray | *beyond the PRD* | 4 | | |
| actions | *beyond the PRD* | 4 | | |
| clipboard | *beyond the PRD* | 4 | | |
| download | *beyond the PRD* | 4 | | |
| drives | *beyond the PRD* | 4 | | |
| emoji | *beyond the PRD* | 4 | | |
| keyboard | *beyond the PRD* | 4 | | |
| performance | *beyond the PRD* | 4 | | |
| polkit | *beyond the PRD* | 4 | | |
| privacy | *beyond the PRD* | 4 | | |
| timer | *beyond the PRD* | 4 | | |
| notifications | §9.10 | 4, last | | |
| settings (with setup, §9.14) | §9.12 | 5 | | |
| launcher | §9.13 | 6 | | |

window_title, checked 2026-10-29 (`genoma/cells/window_title.luau`,
`components/sweep.luau`) beside Bioma on Quickshell's on DP-1, the same
block and palette: the same height to the pixel (tissue, rim, cell), the
same width from the disc to the end, the disc, icon, loader and text at the
same places (a difference of antialiasing, the loader's phase, and the
glass over a different wallpaper). It leaves with the focus and comes back
with it; a new title waits out the debounce, fades out and the next fades
in; a spinner in the title becomes the loader, late in and at once out.
Not yet: the glyph of a cell holding the keyboard (no ported cell takes
it). A press centres the window: not pressed in the check, it would have
moved Akusen's.

workspaces, checked 2026-10-29 (`genoma/cells/workspaces.luau`,
`components/workspace_bars.luau`) beside Bioma on Quickshell's on the same
monitor (its bottom membrane on HDMI-A-1): the cell the same to the pixel
but for the glass; open, the same WORKSPACES header and a panel of the
same 236 × 152 with its well 10 inside, budding downward where Quickshell's
hangs from a thread upward. The first arrow marks the active row, Enter
jumps, Escape closes; the wheel goes to the previous and next workspace,
the mark stepping in that direction (seen at `timing.speed` 15). The cell
framework gained with it: the header while open, the width held while
open, `pulse()` for a condition that is an event, the wheel. The text
tracking had been passed in logical units where Genoma takes em: the
headers are now as wide as Quickshell's. Not yet: the shell-wide keyboard
travel (the list answers its keys itself), the panel's shadow.

vitals, contracted, checked 2026-10-29 (`genoma/cells/vitals.luau`,
`components/vital.luau`): the processor's dot beating at its clock, the
memory's liquid at its level (17 %, as `free` says) with its wave, the
card's satellite in orbit, in the calm colour; the geometry is M2's,
measured then against Quickshell's (`docs/m2-parity.md` in Genoma). Here
the cell is conditional and nothing was critical, so Quickshell's was not
on screen to set beside it. A cell made for the check (deleted after) drew
the states this machine does not reach: a critical processor in the alert
colour with its wave every 0.9 s, the memory full as a pulsing disc, a
battery half charged filling from the left (Genoma's `level_left`). An
indicator not drawn raises no alarm: the desktop's hidden battery read as
empty and kept an alarm running, found in the check. Not yet: the
expansion (the pods, the process list and its sort, its filter, which
waits for Genoma's text field), the battery's drops and bolt (on the
laptop), performance mode's resting poses.

clock, contracted, checked 2026-10-29 (`genoma/cells/clock.luau`,
`components/dial.luau`) beside Bioma on Quickshell's on DP-1, the same
block: the cell the same to the pixel but for the text's antialiasing (Qt's
against cosmic-text's, as in M2) and the second hand's place between the
two captures. Not yet: the expansion (the month, other places, the timer
and the alarm, the day's appointments), whose fields wait for Genoma's
text field.

### Surfaces that are not cells

| Surface | PRD | State |
|---|---|---|
| Wallpaper, and its blurred backdrop for niri's overview | §9.7 | |
| Floating tissues, and the host float for invoked cells | §4 | |
| OSD (volume, brightness, keyboard layout) | §11, an open question then, adopted since | |
| Selection surface (Bioma's own region picker) | §9.6 | |
| Organisms, and their arrange mode | *beyond the PRD* | |
| Lock screen (`lock.qml`, its guard, hyprlock as the fallback) | *beyond the PRD* | |
| Greeter (`greeter.qml`, agreety as the fallback) | *beyond the PRD* | |

### Organisms

adipose, agenda, calendar, clock, cytoplasm, lava, media, note, nucleus,
osmosis, photoperiod, rings, sediment, vacuole, vitals, weather.

### Shaders, to WGSL

`components/fluid.frag` (the media band), `organisms/lava/lava.frag`,
`organisms/cytoplasm/cytoplasm.frag`, `organisms/osmosis/osmosis.frag`.

### Services

Genoma's built-in domains replace Quickshell's modules (Niri's IPC,
SystemMonitor's vitals, Audio, Bluetooth, Network, Media's MPRIS,
Notifications, Polkit, Power, Tray); Bioma's own logic on top of them, and
every other service, is ported to Luau on `g.process`, `g.file`, `g.socket`,
`g.dbus` and `g.timer`, each verified headless first:

Actions, Activity, AppLoad, Audio, Bluetooth, Brightness, Calculator,
Calendar, Capture, Clipboard, Dictation, Downloads, Drives, Emoji, Files,
GreeterSync, Keybinds, Keyboard, Locker, Looks, Machine, Matugen, Media,
Monitors, Network, Niri, NiriConfig, NiriSettings, Notifications, Osd,
Palettes, Polkit, Power, Printers, Privacy, Proxy, Recent, Session, Setup,
Sinestesia, Sounds, Storage, SystemMonitor, Templates, Time, Tray, Vpn,
Wallpaper, Weather, Workload.

Ported, in `genoma/services/`, each checked with
`BIOMA_GENOMA_CHECK=<name> scripts/genoma` (`services/check.luau`) on a
configuration with nothing of Genoma's in it:

- [x] Niri (`niri.luau`, from 5e5ff60): its own event stream on `g.socket`,
      actions through `niri msg`. Checked 2026-10-29: workspaces per
      output with the active and focused ones, the focused window and its
      size (942×1000, as `niri msg focused-window`), the keyboard layout,
      `gaps` 12. `gaps` and `struts` are read from every file of the
      configuration, a later `layout` winning: Niri.qml reads the main file
      alone and would miss them in an included `layout.kdl`. The membranes
      and floating tissues now hang from the window line.
- [x] NiriConfig, reading (`niri_config.luau`, `niri_kdl.luau` from
      `niri-config.js`): every included file followed; includes and
      `output` sections scanned. Binds, rules, workspaces, startup lines
      and writing through `niri validate` come with the services that use
      them.
- [x] Monitors, reading (`monitors.luau`): niri's outputs and the sections
      naming them; the primary from `focus-at-startup`, decided at the load
      against the outputs the compositor describes (`g.outputs()`), so a
      block on `primary` lands on DP-1 here. Switching, moving, variable
      refresh and the games rule come with settings.
- [x] SystemMonitor (`system_monitor.luau`): load, clock (32 cores, range
      417–5763 MHz), memory and swap, the discrete card (card1, not the
      integrated card0), its clock from `pp_dpm_sclk`, VRAM, the k10temp
      package temperature, traffic on physical links, the battery through
      Genoma's power domain (now with UPower's `EnergyRate`), and `ps` only
      while a list is asked for. One binding run per sample (`g.batch`).
      Performance mode's longer interval comes with its service.
- [x] Time (`time.luau`): other places (offsets asked of `date`, the same
      as `TZ=… date` gives), the timer on the wall clock (counted down and
      paused in the check), the alarm at each minute's turn. Ringing (a
      critical notification and a sound) was not set off in the check.
- [x] Calendar (`calendar.luau`), through `scripts/calendar` with the
      sources in its environment (`g.process` now takes `env`): read once
      at the start, again when the sources change and every `minutes`;
      today's bounds at local midnight (Luau's `os.time` reads a table as
      UTC, so local times go through the offset). The events of the
      sources were counted, never printed.
- [~] Proxy, reading (`proxy.luau`): the profile in force and the
      environment it gives a program. The triggers wait for the VPN and
      network services, so `auto` chooses none yet; writing the desktop's
      proxy (`gsettings`) stays Quickshell's while both run.
- [x] Apps (`core/apps.luau`): an application from a window's class or a
      cut executable (`steamwebhelp` → steam, `zen-bin` → zen, `nvim`
      nothing, as Apps.qml rules), its icon through the theme, and `run`
      through `scripts/launch`. Genoma reads the desktop entries
      (`g.desktop_entries()`, `g.icon_path()`); they are read at the load.
