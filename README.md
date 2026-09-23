<h1 align="center">
  <img src="docs/media/logo.png" width="240" alt="Bioma — A Living Shell">
</h1>

A Wayland desktop shell built as independent, living surfaces rather than a bar.

The machine is an organism. Bioma shows its vital signs: surfaces appear when
they have something to say, animate in proportion to what they measure, and go
quiet when nothing is happening.

- **Compositor**: Niri
- **Toolkit**: Quickshell (Qt/QML)
- **Status**: every cell of the first version is built and in daily use, with
  the settings cell and the launcher; see `PROGRESS.md` for what is left

![The desktop at rest](docs/media/at-rest.webp)

## How it works

### At rest, the interface does not speak

There is no bar. Each edge of a monitor is a **membrane**. A membrane carries
**tissues**, positioned containers, and a tissue carries **cells**, one domain
each: the clock, the workspaces, audio, the machine's vitals. At rest a cell is
its glyph and nothing more. No percentages, no counters, no figures. The clock,
the window title, the track playing and a notification are the only things
that are ever written out.

![The three tissues of the top membrane at rest](docs/media/at-rest-detail.png)

A cell exists when it has something to say. A cell can be set to be always
there, or to appear only when something happens: the workspaces when you
change one, audio when the volume moves, vitals when a reading turns critical.

<p align="center">
  <img src="docs/media/notification.webp" width="300" alt="A notification at the left edge">
</p>

### Movement means something

Every animation encodes a live value in its rate or its extent. A ring fills
as far as the load it measures; a bar breathes as fast as the audio it hears.
Motion at a fixed rate with no data behind it is decoration, and Bioma has
none: an indicator with nothing to report is still, or absent. Colour says
state (calm, active, alert), and form says domain.

### Expanded forms grow from their origin

Opening a cell grows it out of the place it sits, shape by shape, joined by
threads. Nothing appears from nowhere, and nothing scales: shapes grow by
width and height, so the lit border and the radii stay true while they move.

<p align="center">
  <img src="docs/media/clock.webp" width="600" alt="The clock, opened: other places, the month, a timer and an alarm">
</p>

<p align="center">
  <img src="docs/media/vitals.webp" width="480" alt="Vitals, opened: CPU, memory and GPU beside the tasks using them">
  <img src="docs/media/audio.webp" width="310" alt="Audio, opened: outputs, inputs, the applications playing, and the volume">
</p>

<p align="center">
  <img src="docs/media/connectivity.webp" width="360" alt="Connectivity: Wi-Fi, Bluetooth devices, VPN profiles and proxies">
  <img src="docs/media/system.webp" width="480" alt="System: the account, the machine, and the ways to leave">
</p>

<p align="center">
  <img src="docs/media/utility.webp" width="300" alt="Utility: screenshot and recording of a screen, a window or a region">
  <img src="docs/media/workspaces.webp" width="190" alt="Workspaces, opened">
  <img src="docs/media/launcher.webp" width="380" alt="The launcher">
</p>

Every cell also answers a key. A cell placed on a membrane opens there, and a
cell placed nowhere opens floating: in the middle of the screen, at a corner,
or at the pointer.

### One palette, the whole desktop

A palette has four roles (background, text, primary, secondary), and every
surface derives from them. It is either one of Bioma's own palettes or computed
from the wallpaper by matugen. The theme cell switches it live. Colour is an
animated value rather than a constant copied into each cell, so the whole shell
changes colour at once.

<p align="center">
  <img src="docs/media/theme.webp" width="560" alt="The theme cell: the wallpaper carousel, the palette source, and the palette">
</p>

The same palette goes past the shell into the rest of the desktop. It sets
niri's focus ring and borders, and rounds niri's windows to the shell's radius.
It also themes GTK, Qt, and the terminals and tools that have a template:
Alacritty, btop, cava, Kitty, Foot, Ghostty and more, chosen under APPS in the
theme cell.

![niri, Alacritty and btop in the Bioma palette](docs/media/applications.webp)

### Settings, in the shell

The layout is edited from the shell itself, with no config file to write by
hand. The settings cell has five pages: Appearance, Structure (which cell goes
where, on each monitor), Cells (always or conditional), Monitors and Keybinds.
Adding a cell costs one block of configuration, and the Structure page writes
that block for you.

<p align="center">
  <img src="docs/media/settings-structure.webp" width="440" alt="Settings, Structure: bands and floating tissues per monitor">
  <img src="docs/media/settings-appearance.webp" width="330" alt="Settings, Appearance: opacity, radius, spacing, blur, scale and timing">
</p>

## Requirements

| Requirement | Notes |
|---|---|
| Niri | 26.04 or later for `ext-background-effect` blur |
| Quickshell | recent build; the PRD assumes current API |
| matugen | optional, wallpaper-reactive palette |
| grim, slurp, tesseract | screenshot and OCR |
| wl-screenrec (VAAPI) | video capture; `wf-recorder` as fallback |
| Spectral, Orbitron | fonts; declared as roles — expressive and technical — so absence degrades rather than breaks. Both are SIL OFL: on Arch, `ttf-spectral` and AUR `ttf-orbitron`, or drop the families from Google Fonts into `~/.local/share/fonts` |

## Running

```sh
scripts/bioma
```

Quickshell also loads a configuration by directory name, and that works too:

```sh
ln -s "$PWD" ~/.config/quickshell/bioma
quickshell -c bioma
```

The script sets two things for this process. The first is `QT_QPA_PLATFORMTHEME`,
set to `xdgdesktopportal`. Bioma draws every pixel it shows, so a
platform theme has nothing to style here — except the file picker the system
cell opens, which is Qt's own `FileDialog`. Qt asks the platform theme for a
native dialog and draws its own when there is none, and `qt6ct`, a common
choice for everything else on a machine, provides none. Started any other way
the shell still works and the picker is Qt's, which looks like nothing else on
the screen. Set `BIOMA_PLATFORMTHEME` to override it.

The second is `QS_ICON_THEME`, read from the desktop's icon theme
(`org.gnome.desktop.interface icon-theme`). That platform theme does not pass
the icon theme on, and without it Qt looks only in hicolor. An application's
own icon is still found there, but a themed icon, such as a folder or a
device, is not. Quickshell reads the variable once, at start: an icon theme
chosen in the theme cell reaches the shell's own icons at its next start.

## Two shells, one session

One program per session may own `org.freedesktop.Notifications`, so Bioma and
whatever was there before cannot both run. `scripts/shell` is the switch:

```sh
scripts/shell            # what is running, and what will run at login
scripts/shell bioma      # stop the other, start Bioma, remember it
scripts/shell noctalia   # the other way
scripts/shell toggle     # whichever is not running now
scripts/shell start      # start what was remembered — the line niri spawns
```

The choice lives in `~/.config/bioma/shell`, outside the repository: it is a
fact about a machine's session, not about the project. `Mod+Alt+B` is the same
toggle on a key.

## Verifying a service without a UI

```sh
qs -p "$PWD/probe.qml"
```

Creates no surfaces. It binds each service the way a cell would, waits for the
data to arrive, prints what came back, and exits. Every service is verified
through this before a cell is built on it.

## Layout

```
shell.qml          entry point
probe.qml          headless service verification
core/              Config, Theme, Timing, Metrics — global singletons
structure/         Membrane, Tissue, Cell — the layout engine
components/        shared primitives
services/          one singleton per system domain
cells/<name>/      one directory per cell
config/            default.json + palettes/
assets/icons/      the 33 glyphs, at runtime
docs/              bioma-prd.md — the specification
docs/design/       the visual specification: style guide, cells, tokens, mockups
docs/media/        the logo, and the screenshots in this file (tools/showcase
                   takes them)
tools/             development tools
```

## Configuration

Two layers. `config/default.json` ships with the shell; a user override file
written by the settings UI is loaded last and wins. The default is functional
and demonstrates the vocabulary — it is not exhaustive.

## Trying it on one monitor

`org.freedesktop.Notifications` has one owner per session, so Bioma and another
shell cannot both show notifications — `scripts/shell` above switches between
them. To try Bioma beside another shell without switching, declare a membrane
on a monitor the other shell does not occupy in `~/.config/bioma/override.json`,
then

```sh
qs -p "$PWD/shell.qml"
```

## Documentation

- `docs/bioma-prd.md` — the product requirements, and the source of truth
- `docs/design/` — the visual specification: `STYLE_GUIDE.md`, `CELLS.md`,
  `IMPLEMENTATION.md`, `tokens.css`, the icon set and 68 mockups
- `PROGRESS.md` — where the work stands, and what is not done
- `services/INVENTORY.md` — the Prisma inventory and every decision taken since
- `CLAUDE.md` — architecture rules for anyone (or anything) writing code here

## Licence

GPL-3.0-or-later. See `LICENSE`.

The design material in `docs/design/` — the style guide, the cell
specifications, the icons and the mockups — is part of the same work and
travels under the same terms.
