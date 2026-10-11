<h1 align="center">
  <img src="docs/media/logo.png" width="240" alt="Bioma — A Living Shell">
</h1>

A Wayland desktop shell built as independent, living surfaces rather than a bar.

The machine is an organism. Bioma shows its vital signs: surfaces appear when
they have something to say, animate in proportion to what they measure, and go
quiet when nothing is happening.

- **Compositor**: Niri
- **Toolkit**: Quickshell (Qt/QML)
- **Status**: **1.0 beta**. Every cell of the first version is built and in
  daily use, with the settings cell, the launcher, the organisms on the
  desktop, a lock screen and a greeter of its own. See `PROGRESS.md` for
  what is left and what has not been verified on real hardware

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

A membrane either reserves its strip of the screen or hides until the pointer
reaches its edge. One that hides comes back over the windows, so each of its
tissues carries a halo: its own shape, grown a little and blurred outward in
the palette's background. The cells are read against it, and the window is
left clean where there is no cell.

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

Once open, a cell is driven from the keyboard as well as the pointer. The
arrows move, Tab walks in reading order, Enter and Space act, and Escape
closes. Nothing is marked until a key asks for it; the first key marks what is
nearest to where the cell was born, with the launcher's fill rather than an
outline. A touchscreen works too: a long press does what the right button
does.

### The cells

| Cell | At rest | Open |
|---|---|---|
| Clock | the time, and a dial that fills with the hour while a disc runs round its rim once a minute | other places, the month, a timer and an alarm |
| Window title | the focused window's title | — |
| Workspaces | the active workspace's name, or its number | the workspaces on that screen |
| Vitals | CPU, memory and GPU as rings that beat and fill | the readings beside the tasks using them; on a laptop, the time the battery has left, or the time until it is full |
| Media | while there is sound: a band that moves with it, and the track | the cover, the progress, the controls, the player |
| Audio | a dial, the volume, moved by the wheel | outputs, inputs, the applications playing and their volumes |
| Connectivity | the network, with the Wi-Fi signal drawn in the glyph | Wi-Fi, wired, Bluetooth devices, VPN profiles, proxies, and printers: the queues, the default, network printers found and added driverless |
| System | the avatar | the account, the machine, the power profile (saver, balanced, performance), and the ways to leave |
| Notifications | a notification as it arrives; set to *always*, the bell alone in between | the history |
| Dock | the pinned and running applications, with an optional launcher at its head | — |
| Tray | the applications' own tray icons | their menus, drawn by Bioma |
| Utility | the recording, while one runs: its beat, its time, its stop | screenshots and recordings of a screen, a window or a region; text recognition; [dictation](#dictation) |
| Theme | — | wallpaper, palette, icons, cursor, application templates |
| Clipboard | — | what was copied, newest first, text and images; never what a password manager marks sensitive |
| Keyboard | the layout's code | the layouts niri has loaded, and a search of every layout there is |
| Privacy | while something is captured: the microphone, a camera or the screen, and who is taking it | one row per use, with its device |
| Timer | while a timer runs: the dial, emptying at the speed of time | the time left, the presets, start, pause, stop |
| Downloads | while a browser is downloading: a thread whose light runs as fast as the bytes arrive | each download, its bytes and rate; a press shows the file |
| Emoji | — | a search by name, the skin tones, recent picks first; the one chosen is pasted into the window that had the focus |
| Launcher | — | applications, and from the third letter files in the home found by name |
| Settings | — | see [below](#settings-in-the-shell) |

A — at rest means the cell's glyph alone, or nothing at all when the cell is
placed nowhere and comes up on its key. When
the volume, the brightness or the keyboard layout changes and no cell on that
monitor is there to say it, a small on-screen display says it instead.

<p align="center">
  <img src="docs/media/emoji.webp" width="360" alt="Emoji, opened: the search, the skin tones, recent picks and the set by group">
  <img src="docs/media/timer.webp" width="250" alt="The timer, opened: the time left, pause and stop">
</p>

<p align="center">
  <img src="docs/media/download.webp" width="480" alt="Downloads, opened beside the media and the clock: the file, its thread, the bytes so far and the rate">
  <img src="docs/media/privacy.webp" width="300" alt="Privacy: the microphone in use, and who is taking it">
</p>

### One palette, the whole desktop

A palette has four roles (background, text, primary, secondary), and every
surface derives from them. It is either one of Bioma's own palettes or computed
from the wallpaper by matugen. The theme cell switches it live. Colour is an
animated value rather than a constant copied into each cell, so the whole shell
changes colour at once.

<p align="center">
  <img src="docs/media/theme.webp" width="560" alt="The theme cell: the wallpaper carousel, the palette source, and the palette">
</p>

A new wallpaper and palette, picked in the theme cell, retint the whole shell as
it runs:

https://github.com/user-attachments/assets/c816f39e-bda5-46b9-a476-74eb5cc4e5eb

The same palette goes past the shell into the rest of the desktop. It sets
niri's focus ring and borders, and rounds niri's windows to the shell's radius.
It also themes GTK, Qt, and the terminals and tools that have a template:
Alacritty, btop, cava, Kitty, Foot, Ghostty and more, chosen under APPS in the
theme cell.

![niri, Alacritty and btop in the Bioma palette](docs/media/applications.webp)

The focused window is lifted by the same soft shadow as an invoked cell, so
its ring stands off the wallpaper on every side; the windows behind it lie
flat.

Bioma also draws its own **icon themes** and **cursors** from the palette, and
redraws them whenever the palette changes. *Bioma* and *Bioma Primary* draw
folders, places and file types as cells, with the shell's glyphs on them;
applications keep the icons of the theme beneath. *Bioma* and *Bioma Cell* are
two cursor themes, soft-edged and drawn in the palette's roles. A fresh install
comes up wearing them, once; anything chosen afterwards in the theme cell is
never taken back.

The wallpaper is chosen in a carousel or in a grid of every image at once, from
a folder picked in a file chooser. A star marks a favourite, and favourites come
first. Bioma ships three wallpapers of its own, a misty forest and a leaf tissue
in the dark palette and in Paper, so a first session never opens on a black
screen.

### Organisms

A cell speaks when something happens. An **organism** keeps the opposite
contract: it is there because it was put there to be looked at. Organisms are
read-only panels standing on the desktop itself, under the windows, in the
space the membranes leave free. They are seen on an empty workspace and
between the windows, and are gone under them the moment there is work on
screen.

Because the eye goes to them on purpose, organisms may speak at rest, with
figures: `34%`, `18°`, `3:42`. The other rules hold. Colour is state, and what
moves is a live value. The pointer passes straight through them to the desktop,
and an organism with nothing to show is absent: media with nothing playing, the
nucleus on a machine without a battery.

![Twelve organisms on an empty workspace: clock, calendar, weather, photoperiod, lava lamp, osmosis, vitals, cytoplasm, growth rings, adipose, a note and media](docs/media/organisms.webp)

| Organism | What it shows |
|---|---|
| Clock | the time, large, with the clock cell's face beside it and the date in words |
| Media | while a track is loaded: the cover as the surface, and the sound rising out of it |
| Vitals | the vitals cell's readings, never closed: CPU, memory, GPU and, on a laptop, the battery; in a row or a square |
| Calendar | this month, read-only, today the only lit day |
| Weather | now and the next hours, for the city set in the settings, from Open-Meteo |
| Note | a Markdown file, read and never written: edit it anywhere, in an Obsidian vault or a repository, and the desktop follows |
| Lava lamp | the processor's heat, drawn as wax |
| Cytoplasm | every running application as a cell pressed against the others, as large as the memory it holds, its lobes circling as fast as it works |
| Growth rings | the machine's age, one ring for every day since the system was installed |
| Osmosis | network traffic as water crossing a membrane: what arrives falls into the pool, what leaves rises out of it, as often as the bytes cross |
| Photoperiod | the sky over the weather's place: the sun's arc and the moon's, the daylight left, how much of the moon is lit |
| Vacuole | the notifications not yet read, a drop each, one body per application |
| Sediment | the files used lately, laid down in strata, the newest on top and the widest |
| Nucleus | the battery's charge as the mass at the heart of a cell; charging, drops come in and melt into it |
| Adipose | the filesystems, one cell each, the droplet of fat as large as the share in use |

Organisms are added from the settings cell's Organisms page, one monitor at a
time. A new one grows at the centre of the screen, and the shell enters
**arrange**: every organism is lifted above the windows over a grid of squares,
to be dragged to its place, or onto another monitor. The wheel makes the
squares larger or smaller. Done, or Escape, puts them back under the windows
and writes where they stand. Each kind has a size of its own in grid units (2 × 1,
2 × 2, 1 × 2 and a few more), so organisms of different kinds fall into tidy clusters.
`qs -p /path/to/Bioma/shell.qml ipc call organisms arrange` enters the mode
from a key.

### Settings, in the shell

The layout is edited from the shell itself, with no config file to write by
hand. The settings cell has seven pages: Structure (which cell goes where, on
each monitor), Cells (always or conditional), Organisms, Appearance, Monitors,
Keybinds and Session.
Adding a cell costs one block of configuration, and the Structure page writes
that block for you: the cells not yet on the monitor appear as a row of chips,
and one that would not fit says NO ROOM before it is added. A tissue can be
moved, or copied to another monitor: every free place lights up and says what
the tissue would be there. The page also keeps whole layouts as presets
(membranes, floating tissues and organisms, on every monitor), to switch
between or to start again from an empty desktop.

Appearance sets the blur's strength as well as whether there is one, for every
surface niri blurs. Session sets the idle lock and, on a laptop, the power
profile to follow the plug: one on battery, another on mains.

<p align="center">
  <img src="docs/media/settings-structure.webp" width="440" alt="Settings, Structure: the tissues on each membrane and the floating ones, per monitor">
  <img src="docs/media/settings-appearance.webp" width="330" alt="Settings, Appearance: opacity, radius, spacing, blur, scale and timing">
</p>

Every change applies as it is made. Here the radius goes from round to square,
and every cell follows:

https://github.com/user-attachments/assets/b6040d46-5f7f-4733-bbe6-13055976d951

## Requirements

Bioma is written for **niri** and **Quickshell 0.3.1**, and it is tested on Arch
Linux (CachyOS). Package names below are Arch's.

The AUR package depends on all of the first table, so installing it installs
the whole shell. Only the second table is left to you.

| Required | Package | For |
|---|---|---|
| niri 26.04 or later | `niri` | the compositor; 26.04 is the first with `ext-background-effect` blur |
| Quickshell 0.3.1 | `quickshell` | the shell runtime |
| Qt 5 Compat | `qt6-5compat` | the masks the wallpaper tiles and faces are drawn through (`Qt5Compat.GraphicalEffects`), which Quickshell does not bring |
| Python 3 | `python` | the helper scripts in `scripts/` |
| gsettings | `glib2` | the desktop's settings: palette, icons, cursor, proxy |
| wl-clipboard | `wl-clipboard` | the clipboard cell |
| Noto Color Emoji | `noto-fonts-emoji` | the emoji cell's emoji |
| ImageMagick | `imagemagick` | wallpaper thumbnails, and the cursors' pixels |
| librsvg | `librsvg` | Bioma's cursors, drawn in the palette (`scripts/cursors`); with the icons, built and put on the desktop at the first start |
| Spectral, Orbitron | AUR `ttf-spectral`, AUR `ttf-orbitron` | the two voices, expressive and technical. Both are SIL OFL |
| matugen, zenity | `matugen`, `zenity` | palettes computed from the wallpaper; the wallpaper folder picker |
| fd, xdg-utils | `fd`, `xdg-utils` | files found by name in the launcher, and opened with their default application |
| curl | `curl` | the weather organism's forecast, from Open-Meteo |
| grim, tesseract, wl-screenrec | `grim`, `tesseract`, `tesseract-data-eng`, AUR `wl-screenrec` | screenshots, text recognition, screen recording (VAAPI) |
| PipeWire | `pipewire`, `pipewire-audio` | audio, the alarm's sound, the microphone |
| NetworkManager | `networkmanager` | Wi-Fi, wired, VPN profiles, proxy triggers |
| BlueZ | `bluez`, `bluez-utils` | Bluetooth |
| CUPS, Avahi | `cups`, `avahi` | printers in the connectivity cell: the queues, the default, network printers found and added driverless. Adding and removing one needs CUPS's admin group (`sys` or `wheel` on Arch) |
| brightnessctl, ddcutil | `brightnessctl`, `ddcutil` | the backlight of a laptop; the brightness of external monitors |
| UPower | `upower` | the battery, on a laptop |
| power-profiles-daemon | `power-profiles-daemon` (or `tuned-ppd`, which provides it) | the power profile in the System cell — saver, balanced, performance — and, on a laptop, switching it with the plug |
| pciutils, libnotify | `pciutils`, `libnotify` | the graphics card in the System cell; timer and alarm notifications |
| The gtk portal | `xdg-desktop-portal`, `xdg-desktop-portal-gtk` | notifications from Flatpak applications, and the avatar's file picker |
| hyprlock | `hyprlock` | the fallback lock screen, which takes over if Bioma's own fails |
| greetd | `greetd`, `greetd-agreety` | the Bioma greeter, and the plain one while it has no copy to run — see [The greeter](#the-greeter) |

| Optional | Package | For |
|---|---|---|
| whisper.cpp, its model, python-evdev | `whisper-cpp`, `ggml-vulkan`, AUR `whisper.cpp-model-large-v3-turbo-q5_0`, `python-evdev` | dictation — see [Dictation](#dictation). The model alone is 547 MB. `python-evdev` alone is what lets the emoji cell paste; without it the emoji is left on the clipboard |
| Business Network Wizard | AUR `business-network-wizard` | a company network — NTLM proxy, VPN, 802.1X Wi-Fi, shares, printers. When it is installed the connectivity cell's proxy well offers COMPANY NETWORK, which opens it |

## Install

From the AUR, as `bioma-shell`:

```sh
paru -S bioma-shell          # or yay, or makepkg from packaging/aur
bioma-install --autostart
```

The package puts Bioma in `/usr/share/bioma` and builds the spectrum tool for
Sinestesia. `bioma-install` is `scripts/install` below; run it once per user.
Coming from a clone, it points the existing includes, the autostart line and the
keys at the package, and leaves the keys themselves as they are.

Or from a clone:

```sh
git clone https://github.com/AkusenArcade/Bioma.git
cd Bioma
scripts/install --autostart
```

A clone needs the spectrum tool built once for Sinestesia:
`cargo build --release` in `tools/sinestesia-bands` (see its README).

`scripts/install` says what is missing first, and stops if anything required is.
It names the system services that are not enabled — NetworkManager, Bluetooth,
CUPS, Avahi — with the one `sudo systemctl enable --now` line that enables
them; it does not run it, because a machine that keeps its network another way
would lose it. Then it writes the keys and tells niri where Bioma is:

- `bioma-binds.kdl`, next to niri's `config.kdl`, from
  `config/niri/bioma-binds.kdl.in` with the repository's path filled in. The
  keys are under `Mod+Alt`, so they stay clear of niri's own defaults. The copy
  is yours: the settings cell's Keybinds page edits it, and the installer
  leaves it alone from then on (`--force` writes it again).
- `include` lines at the end of `config.kdl` for that file and for
  `config/niri/bioma.kdl`, the layer rules. With `--autostart`, it also adds a
  `spawn-at-startup` for `scripts/shell start`.

`config.kdl` is copied aside first, and the result goes through `niri validate`.
If niri refuses it, the copy is put back. Running the installer again changes
nothing.

Then start it with `scripts/shell bioma`, or log in again. After an update,
`scripts/shell restart` stops Bioma and starts the new version. The first start uses
`config/default.json`. Everything after that is set from the settings cell
(`Mod+Alt+S`) and kept in `~/.config/bioma/override.json`.

### Keys

| Key | Opens |
|---|---|
| `Mod+Space` | the launcher |
| `Mod+Alt+Period` | emoji, pasted into the window that has the focus |
| `Mod+Alt+S` | settings |
| `Mod+Alt+T` | theme: wallpaper, palette, icons, cursor, application templates |
| `Mod+Alt+V` | vitals and tasks |
| `Mod+Alt+A` | audio |
| `Mod+Alt+P` | capture and recording |
| `Mod+Alt+K` | keyboard layouts |
| `Mod+Alt+Escape` | system: the account, the machine, the ways to leave |
| `Mod+Shift+Space` | the next keyboard layout |
| `Print` | a screenshot of a region, drawn with Bioma's own rectangle |
| `Mod+Print` | a screenshot of the monitor the keyboard is on |
| `Alt+Print` | a screenshot of the window that has the focus |
| `Shift+Print` | stop a recording, wherever the utility cell is |
| `Mod+Alt+D` | dictation: press to speak, press again to type it into the focused window |
| `Mod+Alt+L` | lock the session |
| `Mod+Alt+B` | switch between Bioma and the other shell |

The volume, brightness and media keys go to Bioma too. Every other cell also
answers `qs -p /path/to/Bioma/shell.qml ipc call cell toggle <name>`, so any
key can be given to any cell from the Keybinds page. Escape, or a press
anywhere else, closes what is open.

The timer answers keys of its own: `ipc call timer start 25` starts twenty-five
minutes (`start 0` the length last set), `timer toggle` pauses or resumes it,
`timer stop` ends it. The Keybinds page offers *Timer: start or pause*; the
timer cell is there while one runs.

Layouts saved on the Structure page answer keys too: `ipc call presets apply
Work` puts the one called *Work* back, membranes, floating tissues and
organisms on every monitor at once.

### Dictation

Speech to text, in the utility cell: under **Text** the middle button is
DICTATION, or `Mod+Alt+D` from anywhere. The first press listens, and the cell
shows the open microphone, its level and the seconds spoken. The second press
transcribes, locally, with whisper.cpp, and the text lands in the window that
has the focus. `qs -p shell.qml ipc call capture cancel` drops a take.

The text is **pasted**, not typed. A typed keymap is ignored by Electron
applications, Teams, Obsidian and VS Code among them, and accented letters
arrive as other keys. So the text goes to the clipboard, a real Ctrl+V is
sent from a virtual keyboard (Ctrl+Shift+V in a terminal), and the clipboard
you had is put back.

That keyboard needs `/dev/uinput`. The package installs a udev rule giving it
to the user at the seat, the same rule `steam-devices` ships for game
controllers. Be aware of what that means: **any program you run can then
synthesise keyboard and mouse input.** Without it, dictation still works: the
text is left on the clipboard, and a notification says to paste it.

Dictation is the one feature the package leaves optional, for the size of its
model. To add it:

```sh
paru -S whisper-cpp ggml-vulkan whisper.cpp-model-large-v3-turbo-q5_0 python-evdev
```

Without them, pressing DICTATION says that whisper-cli or its model is missing.

The model is `large-v3-turbo`, quantised (547 MB). It runs on the GPU through
Vulkan when there is one, and on the CPU otherwise.
`capture.dictation` in the configuration picks another model, the language,
and the terminals that paste with Ctrl+Shift+V.

### The lock screen

Bioma's lock screen is `lock.qml`, a process of its own, so a shell that
falls over does not take the lock with it. It shows the wallpaper blurred, the
time and date, who is logged in and the password field, on the screen the
keyboard is on. It locks when asked — `Mod+Alt+L`, the System cell's LOCK, or
anything that runs `loginctl lock-session` — before a suspend, and after a time
idle, set on the Session page of the settings cell.

The password is checked by PAM with Bioma's own file, `assets/pam/bioma-lock`:
`pam_unix` alone, without the failure counter `login` has, so mistyping at the
lock screen never locks the account.

`scripts/lock` starts it and stands guard. If the lock does not take within
five seconds, or dies while it holds the screens, hyprlock (or swaylock) takes
over with a plain field. The worst case is a plainer lock screen.

#### If the lock screen fails

If both fail, niri keeps the screens locked, red, with
nothing to type into. Nothing is lost; the way back is a text console:

1. Press `Ctrl+Alt+F2` and log in.
2. Start a lock screen on the running session, then return to it with
   `Ctrl+Alt+F1` and type the password:

   ```sh
   WAYLAND_DISPLAY=wayland-1 hyprlock
   ```

   niri's socket is usually `wayland-1`; `ls /run/user/$(id -u)` shows it.

   Or, to end the session instead: `niri msg --socket "$(ls /run/user/$(id -u)/niri.wayland-1.*.sock)" action quit -s`.

### The greeter

Bioma can also greet you before you log in. The greeter is the lock screen's
composition, with greetd checking the password: the same wallpaper and mode
(span included), palette, faces, appearance and clock. The field is on the
primary monitor only, the one `focus-at-startup` marks in niri's outputs.

The greeter runs as the `greeter` user and cannot read your home, so it runs
from a copy in `/var/lib/bioma-greeter`. The shell keeps that copy current by
itself: the configuration, the wallpaper, the palette, the monitors, the
keyboard layout, the cursor and your picture.

**The AUR package sets it up.** Installing it makes the copy for the user who
installed it, keeps greetd's configuration as
`/etc/greetd/config.toml.before-bioma`, points greetd at
`/usr/share/bioma/scripts/greeter-session`, and enables greetd — unless another
login manager is enabled, which it leaves alone and names, with the line that
switches. Nothing restarts: it takes effect at the next boot. Removing the
package puts the old configuration back.

While there is no copy to run, the same command shows greetd's plain greeter,
agreety, so the login screen is never empty.

From a clone it takes three steps with sudo, once:

1. A directory you write and the greeter reads:

   ```sh
   sudo install -d -m 2750 -o "$USER" -g greeter /var/lib/bioma-greeter
   scripts/greeter-sync
   ```

2. Keep the current greeter's configuration as the way back:

   ```sh
   sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.before-bioma
   ```

3. Point greetd at Bioma's greeter, in `/etc/greetd/config.toml`:

   ```toml
   [default_session]
   command = "/var/lib/bioma-greeter/live/shell/scripts/greeter-session"
   user = "greeter"
   ```

It takes effect at the next login screen. If the greeter does not come up, it
writes why to `/tmp/bioma-greeter.log`. To go back, log in on a text console
(`Ctrl+Alt+F2`) and restore the old configuration:

```sh
sudo cp /etc/greetd/config.toml.before-bioma /etc/greetd/config.toml
sudo systemctl restart greetd
```

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

## Notifications from Flatpak applications

A sandboxed application — a Flatpak such as Teams for Linux — does not call
`org.freedesktop.Notifications` itself. It asks the notification portal, and
the portal hands the notification to a backend. The `gnome` backend passes it
to GNOME Shell (`org.gtk.Notifications`). Under niri nothing owns that name,
so the notification is lost: Bioma never sees it, and nothing is logged except
a line from `xdg-desktop-portal-gnome`:

```
Error from gnome-shell: Cannot invoke method; proxy is for the well-known name org.gtk.Notifications without an owner
```

The `gtk` backend forwards to `org.freedesktop.Notifications`, which is Bioma.
niri's own portal configuration already chooses it. A
`~/.config/xdg-desktop-portal/niri-portals.conf` of your own, however, replaces
that file whole, and one written for screen casting usually leaves the line
out. Add the last two lines to its `[preferred]` section, next to whatever it
already sets:

```ini
[preferred]
default=gnome;gtk
org.freedesktop.impl.portal.Notification=gtk
org.freedesktop.impl.portal.Access=gtk
```

The portal reads its configuration once, at start:

```sh
systemctl --user restart xdg-desktop-portal
```

A screen cast or a camera shared through the portal is dropped by the restart.

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
lock.qml           the lock screen, a process of its own (with lock/)
greeter.qml        the greeter, run by greetd (with greeter/)
structure/         Membrane, Tissue, Cell — the layout engine
components/        shared primitives
services/          one singleton per system domain
cells/<name>/      one directory per cell
organisms/<name>/  one directory per organism
config/            default.json, palettes/, niri/ (the keys and layer rules)
scripts/           the installer, the shell switch, the lock, and helpers
assets/            the 66 glyphs, wallpapers, cursor and icon-theme drawings,
                   the emoji set
packaging/aur/     the AUR package
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
- `docs/configuration.md` — every key of the configuration
- `docs/design/` — the visual specification: `STYLE_GUIDE.md`, `CELLS.md`,
  `ORGANISMS.md`, `CURSORS.md`, `ICON_THEME.md`, `IMPLEMENTATION.md`,
  `tokens.css`, the icon set and 68 mockups
- `PROGRESS.md` — where the work stands, and what is not done
- `services/INVENTORY.md` — the Prisma inventory and every decision taken since
- `CLAUDE.md` — architecture rules for anyone (or anything) writing code here

## Licence

GPL-3.0-or-later. See `LICENSE`.

The design material in `docs/design/` — the style guide, the cell
specifications, the icons and the mockups — is part of the same work and
travels under the same terms.
