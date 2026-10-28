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

- [ ] Config: `config/default.json`, then `override.json`, watched, written
      back atomically.
- [ ] Theme (roles, sources, palettes, matugen) as animated signals.
- [ ] Timing, Metrics, Typography from `docs/design/tokens.css`.
- [ ] Structure: membrane, tissue, cell, the registry, visibility types,
      expansion by budding (Akusen, 2026-10-28), the input surface.

### Cells

| Cell | PRD | Phase | Ported from | State |
|---|---|---|---|---|
| window_title | §9.1 | 2 | | |
| workspaces | §9.3 | 2 | | |
| vitals | §9.2 | 2 | | |
| clock | *beyond the PRD* | 2, with the membrane | | |
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
