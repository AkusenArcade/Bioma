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

## Who acts on the desktop

Until the switch (M6 step 7) the two run side by side, and some services
act on the desktop rather than only reading it: matugen, the templates
(GTK, niri), gsettings (icons, cursors, the proxy), the wallpaper's state.
Run twice, they would write in turn. So (Akusen, 2026-10-29): **Genoma
chooses, Quickshell acts.** Bioma on Genoma reads everything, and a choice
made in one of its cells (a wallpaper, a palette) writes only the shared
configuration and state (`override.json`, `wallpaper.json`); Bioma on
Quickshell, which follows those files already, is the one that runs the
effects. At the switch the effects move to Genoma.

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
| vitals | §9.2 | 2 | 30c6cc7 | checked 2026-10-29, awaiting Akusen and the cost |
| clock | *beyond the PRD* | 2, with the membrane | 7e62c5c | checked 2026-10-29, awaiting Akusen and the cost |
| media | §9.4 (sinestesia) | 3 | 60ca560 | checked 2026-10-29, awaiting Akusen and the cost |
| theme | §9.7 | 3 | 60ca560 | checked 2026-10-29, awaiting Akusen and the cost |
| utility | §9.6 | 3 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| audio | §9.5 | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| connectivity | §9.11 | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| system | §9.8 (session menu) | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| dock | §9.9 | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| tray | *beyond the PRD* | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| actions | *beyond the PRD* | 4 | | |
| clipboard | *beyond the PRD* | 4 | | |
| download | *beyond the PRD* | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
| drives | *beyond the PRD* | 4 | | |
| emoji | *beyond the PRD* | 4 | | |
| keyboard | *beyond the PRD* | 4 | | |
| performance | *beyond the PRD* | 4 | | |
| polkit | *beyond the PRD* | 4 | | |
| privacy | *beyond the PRD* | 4 | 11bb81e | checked 2026-10-29, awaiting Akusen and the cost |
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

The vitals' expansion, checked 2026-10-29 on HDMI-A-1 (an empty workspace,
`cells/vitals_expansion.luau`, `components/choice.luau`): the list's panel
buds out of the cell and the pods out of the panel's edge, a stagger
apart, their content once each is at size (seen at `timing.speed` 15);
CPU, RAM and GPU with their figures and the sort's dot; typing filters the
list ("nir": niri alone), Down marks a row, Enter asks "Close niri?" with
Cancel marked, Escape answers Cancel and the next closes the cell; a press
on the CPU pod sorts by CPU. Closed, it starts again empty, as Quickshell's
does, whose expansion is unloaded. The threads stay once the buds have
parted (Akusen, 2026-10-29): from the cell to its panel (every cell with
one, the workspaces' too) and from each pod to the panel's edge, a node on
each rim. A thread belongs to the shape it comes out of: it is drawn out of
that shape, already where it stays, and the shape that buds meets it (seen
at `timing.speed` 15); what flows along it starts once it is whole. Closing, every shape that
holds something waits for its content to be gone (STYLE_GUIDE §6; Akusen,
2026-10-29, as a rule): the content leaves in half its entering time, then
the shape and its thread retract, and what the content shows (the process
list) stays until then rather than emptying under it. The shapes go in
the order opposite to the one they came in (Akusen, 2026-10-29): the last
pod's thread, then that pod, then the one before it, and the panel that
came first goes last, with the cell's thread. Along the thread of the domain the list is sorted by, particles
flow out of the pod into the list, as many a second as that domain's load
(eight at full load; the battery's from the watts going in, as Vital.qml's
drops), in the primary as the sort's dot is, and none at zero (Akusen's idea, 2026-10-29,
beyond Quickshell's). Not yet: the shell-wide keyboard travel
(the pods and the choices are reached by the pointer only), the matrix's
outer pods budding out of the inner ones, the scroll bar, the window title
naming the cell while its field has the keys.

clock, contracted, checked 2026-10-29 (`genoma/cells/clock.luau`,
`components/dial.luau`) beside Bioma on Quickshell's on DP-1, the same
block: the cell the same to the pixel but for the text's antialiasing (Qt's
against cosmic-text's, as in M2) and the second hand's place between the
two captures.

The clock's expansion, checked 2026-10-29 on HDMI-A-1 (an empty workspace,
`cells/clock_expansion.luau`, `components/switch.luau`): the month buds out
of the clock with today in the disc and a point under the days something is
on; other places (with their offsets, as `date` gives them) and the timer
with the alarm bud out of its sides, and the day's appointments out of its
foot, each on its thread. A press on a day shows its appointments (Akusen's
calendars, read through `scripts/calendar`); the calendars read are chips
cut at the panel's edge; "+ Calendar" lists the accounts in Online Accounts
with what is added and what is not. Not yet: the shell-wide keyboard travel,
the lists' scroll bars; adding a place or an address was not tried, nor
forgetting a calendar, since they write Akusen's configuration and keyring
(the test configuration is a copy, but the keyring is his).

media, contracted, checked 2026-10-29 on HDMI-A-1 (`genoma/cells/media.luau`,
`components/band.luau`, `components/fluid.luau` and `fluid.wgsl`, the first
Genoma shader node): the cell rises on the signal and the band follows the
sound in all four effects, eardrum the default. Tested on a PipeWire null
sink (`pactl load-module module-null-sink sink_name=genoma_test`, the engine
started with `PIPEWIRE_NODE=genoma_test`, a synthetic loop played into it
with `pw-play --target`), so nothing was heard. Playing, the engine takes
about 2.5 % of a core at 120 Hz once the hidden bars and the colours stopped
being recomputed sixty times a second (9.9 % before). The name beside the
band, from `scripts/mpris-dummy.py`, crosses over as on Quickshell.

The media's expansion, checked 2026-10-29 on HDMI-A-1 (an empty workspace,
`cells/media_expansion.luau`): the band with room buds out of the cell, and
the track buds out of the band on its own thread, its content last; closing,
the content goes, then the track, then the band. Pause, the seek (a press on
the line goes to that place), the selector between two dummy players and the
track leaving while the cell is open (the band stays) all tried. Covers: a
local file, and a remote one served from 127.0.0.1, downloaded once to
`~/.cache/bioma/art` (Spotify sends https); without one, the well and its
glyph. Not yet: the keyboard travel through the controls. Seen while
checking, and Quickshell's behaviour as well (Cell.qml): closing, the
contracted content returns while the header waits for the composition to
go, so the two cross for the length of the retraction.

theme, checked 2026-10-29 on HDMI-A-1 (an empty workspace, `cells/theme.luau`,
`cells/theme_expansion.luau`, `components/segmented.luau`,
`components/scroller.luau`; services `wallpaper`, `looks`, `templates`, the
palettes in `core/theme.luau`): the seven chips at rest, replacing each other
a stagger apart when the palette moves. Opened, the wallpapers as a grid (the
thumbnails Quickshell made, favourites first, the star on its disc) or a
carousel whose step grows the arriving picture and shrinks the leaving one;
the source buds out of them on the spine, the palette out of the source,
DESKTOP below it with icons, cursor, the folder and the templates. The
palette's dropdown opens its list raised over DESKTOP, scrolled by the wheel
with its mark. Tried on the test configuration: grid and carousel, a step of
the carousel (wallpaper.json written in Quickshell's own form), matugen and
Bioma as the source (the shell and the chips retinting), the list. Not tried,
because they act on Akusen's real desktop through Quickshell: choosing icons,
a base, a cursor or a template (the channel itself was checked with a call
that changes nothing). Found on the way: a closed list whose rows changed
crashed the engine in taffy (now patched, Genoma's vendor/taffy), and the
palette's targets were not reactive (the chips, and the cell's pulse on a
change of palette, never heard of one).

utility, checked 2026-10-29 on HDMI-A-1 (`cells/utility.luau`,
`cells/utility_expansion.luau`, `structure/selection.luau`,
`components/veil.wgsl`; services `capture`, `dictation`): the icon at rest;
opened, the kinds over the three places, the pair last used chosen and
WINDOW drawn unavailable under Video. A region chosen on the selection
surface: the veil with the selection cut out at the rim's radius, the lit
border, the readout (400 × 220), and grim's file 400 × 220; a right press
cancels, twice in a row. A recording of the screen from the panel: the beat,
the count, the stop, then the question, and Discard leaving nothing in the
temporary directory. Headless (`BIOMA_GENOMA_CHECK=capture`): a still of an
output, its text (tesseract), three seconds recorded and closed by SIGINT
into a file ffprobe reads, the encode resolution kept even (101×51 at 1.5 is
152×76); dictation's probe, the microphone's level while listening, and a
cancel that leaves no recorder behind (`BIOMA_CHECK_LISTEN=1`). Not tried,
because they need Akusen: Escape (never sent synthetically), the crosshair
cursor (grim does not show it), the colour picker, a window's capture
(niri's goes through the clipboard), a whole take of dictation (it pastes
into the focused window), a saved recording's notification. Not yet: the
clipboard cell kept quiet through dictation's paste (with the clipboard
service), the keyboard's travel through the sources. Found on the way, in
the structure: an invoked cell that closed itself (the utility, closing for
its capture) stayed asked for, so the next call to it closed a cell already
shut; it now stops being asked for when it closes, as Cell.qml does.

audio, checked 2026-10-29 on HDMI-A-1 (`cells/audio.luau`,
`cells/audio_expansion.luau`, `cells/audio_capsule.luau`,
`components/gauge.luau`, `components/slider.luau`): the dial at rest, set
beside Quickshell's on the same monitor's bottom edge (the node at the
head is a shade smaller: Quickshell's merges with the stroke's round cap).
Opened, the capsule (dial, figure, slider) buds from the cell and the
three wells from the capsule on their own thread, with the machine's real
devices, their buses and the default marked. A silent stream played into
a null sink (`pw-play --target genoma_test`) came and went in
APPLICATIONS; its slider pressed and dragged to 75 % and its mute pressed,
read back from `pactl`. Summoned with no cell placed on the output, it is
the capsule in the middle of the screen with the wells hanging from it,
and a second call sends it off and lets the keyboard go. Not tried,
because they move Akusen's own sound: the wheel and the middle button on
the cell, the capsule's slider, choosing another device. Not yet: the
keyboard's travel through the rows. Found on the way: a cell's middle
button opened it (only the left one does now, the middle one is the
cell's: `on_middle`), and adding or removing a cell in the configuration
takes a reload, where Quickshell follows it live — settings will need it.

connectivity, in progress 2026-10-29 (`cells/connectivity.luau`,
`cells/connectivity_expansion.luau`; services `network`, `bluetooth`,
`vpn`, `proxy`, `printers`): one glyph per live connection at rest, the
Wi-Fi one carrying its signal in its arcs. Opened: ETHERNET with the
profile and the link's speed, WI-FI with its switch and the networks once
it is on (the radio switched on and back off, it is off by Akusen's
choice), BLUETOOTH with SEARCH, its loader and what it found. The password
field is `components/field.luau` with `secret`. Not tried: joining a
network, pairing a device (the desktop has none to pair and no saved
Wi-Fi profile). Then the VPN well, its form with the file chosen through
the desktop's portal (`services/picker.luau`: GTK's chooser here, as
zenity's; the portal opened and closed from a check, a choice by hand
still to see), the proxy well and its editor (a profile typed, Tab from
field to field, the port taking figures only, a trigger, saved, edited,
removed, all in the test configuration), the printers well (CUPS's queue
and its default). Found on the way: Genoma names a device's call in
flight as a string, and an empty string is true in Luau, so every device
read as pairing; and an emptied list was written to `override.json` as
`{}`, which Quickshell reads as no list (Genoma's `g.json_set` now keeps
the shape the document had, `g.array` marks a new one, and lists parsed
from JSON no longer carry a metatable table.clone refuses).

system, checked 2026-10-29 on HDMI-A-1 (`cells/system.luau`,
`cells/system_expansion.luau`, `components/portrait.luau`; services
`session`, `machine`, `power`): the picture at rest (AccountsService's);
opened, the identity capsule, the five actions under it with their keys,
the machine beside them (on the left, the cell standing at the end of
its strip) and the power profile above the machine. RESTART pressed and
the key 4 typed: the row became its question, and Cancel took it back.
Not pressed, for what they would do: any action itself, the power
profile, a new picture (through the portal, the cell stepping aside).
Session actions run through `setsid -f`: a lock screen that died with
the shell's next reload would unlock the session. Genoma's power domain
gained `degraded`, the reason performance is held back.

dock, checked 2026-10-29 on HDMI-A-1 (`cells/dock.luau`): set above
Quickshell's on the same monitor, the same kept icons in his order, the
rings on what runs, the hairline before what is open and not kept. The
name came under the icon the pointer was on; zen dragged two places
along the row (growing while held, the others making room) was written
in its new place and dragged back. Not pressed, for moving his windows:
a press (focus, the next window), the middle button (another one), the
right one (keep, let go). Not yet: a long press on a touch screen.

tray, checked 2026-10-29 on HDMI-A-1 (`cells/tray.luau`, service `tray`):
Genoma registered as a host with the watcher Quickshell serves, the same
four items in the same order. Two icons differ, and on purpose until
Akusen says otherwise: Steam's is the theme's own `steam_tray_mono`
(Qogir, through bioma-icons' chain) where Quickshell falls back to the
grey PNG in /usr/share/pixmaps, and Telegram's is its symbolic icon where
Quickshell draws the pixels the application sends — Qt's lookup searches
fewer of a theme's directories. The menu of Shelly opened with the right
button, its separators, a disabled entry, a submenu entered and left;
nothing in it pressed. Not yet: icons sent only as pixels (the glyph
instead), a long press on a touch screen. Found on the way: Genoma looked
icons up in application directories only (now every directory a theme
declares), and a `rotate_y` on an absent icon mirrored the text beside
it (the back chevron is now `chevron-left`, drawn in the icon set; the
Genoma bug is still to find).

download, checked 2026-10-29 on HDMI-A-1 (`cells/download.luau`,
`components/rate_thread.luau` and its `.wgsl`, service `downloads`): a
partial file grown in ~/Downloads at 6 MB a second raised the cell, its
thread running (a shader whose clock stops with the bytes); opened, the
row with the name, its own thread and the figures. Not pressed: the row
(it opens the file manager).

privacy, checked 2026-10-29 on HDMI-A-1 (`cells/privacy.luau`, service
`privacy`): nothing taken, neither shell showed it; `pw-record` taking the
microphone raised both, the same glyph in the active colour and the same
name, and opened, the row said MICROPHONE · REVELATOR IO 24 PRO. Not
tried: a camera (none is used here) and a screen cast.

### Surfaces that are not cells

| Surface | PRD | State |
|---|---|---|
| Wallpaper, and its blurred backdrop for niri's overview | §9.7 | |
| Floating tissues, and the host float for invoked cells | §4 | |
| OSD (volume, brightness, keyboard layout) | §11, an open question then, adopted since | |
| Selection surface (Bioma's own region picker) | §9.6 | checked 2026-10-29 with the utility (`structure/selection.luau`) |
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
- [x] Media (`media.luau`), on Genoma's MPRIS domain: the player chosen,
      else the one playing, else the first; the length kept for the track
      when Firefox or Zen stop sending it; the position read each second
      while playing. Checked 2026-10-29 with Akusen's Zen playing and
      `scripts/mpris-dummy.py`: Zen chosen, its title, artist and art.
- [x] Sinestesia (`sinestesia.luau`): `tools/sinestesia-bands`, run while
      something holds it: 64 bands a side at 60 frames a second, folded by
      peak. Performance mode's still band comes with its service.
- [x] Audio (`audio.luau`, from 11bb81e): the default sink and source,
      the outputs, inputs and streams by node kind, volumes and mutes and
      the default written through Genoma's audio domain; and the default
      sink's peak, ten readings a second, from `sinestesia-bands --peak`
      (Audio.qml's way on an AUX interface, here always). Checked
      2026-10-29 (`BIOMA_GENOMA_CHECK=audio`, `BIOMA_CHECK_SINK=genoma_test`
      writing a null sink's volume and mute and putting them back).
- [x] Capture (`capture.luau`, from 11bb81e): stills of a region, an
      output or a window (niri's, through the clipboard, waited for by
      checksum), text by tesseract over an upscaled crop, niri's colour
      picker and the colours kept, video by wl-screenrec into the runtime
      directory until saved, stopped by SIGINT (`p:signal`); every capture
      waits for the shell to have gone from the screen first.
- [x] Dictation (`dictation.luau`): `scripts/listen`, `whisper-cli`,
      `scripts/paste`, one take at a time, each process dying with the
      shell; the level from the recorder's own peaks.
- [x] Network (`network.luau`, from 11bb81e): the wired link, Wi-Fi, the
      networks one entry a name, joining and its failure, reachability;
      on Genoma's NetworkManager domain.
- [x] Bluetooth (`bluetooth.luau`): adapter, power with its settling,
      discovery, paired, connected and found devices, pair-trust-connect.
- [x] Vpn (`vpn.luau`): NetworkManager's VPN and WireGuard profiles by
      nmcli, followed through `nmcli monitor`; up, down, remove, import with
      credentials through `scripts/vpn`.
- [x] Proxy, the choice (`proxy.luau`): profiles, triggers (a VPN, a Wi-Fi
      network, the cable), the environment, the profiles written. The
      desktop's gsettings stays Quickshell's until the switch.
- [x] Printers (`printers.luau`): CUPS's queues, default and jobs through
      `scripts/printers`, followed by its D-Bus notifications; search, add,
      remove, default. Making the only queue the default stays Quickshell's.
- [x] Picker (`picker.luau`): a file or folder chosen through
      org.freedesktop.portal.FileChooser, for the VPN profile now and for
      everything Quickshell asks zenity for as it comes over.
- [x] Session (`session.luau`): who, the picture and its change through
      AccountsService, the five actions and their question, the restart
      due. Suspending after idle stays Quickshell's until the switch.
- [x] Machine (`machine.luau`): the facts, read once; the uptime while
      looked at.
- [x] Power, the profile (`power.luau`): Bioma's three names, held back
      by the daemon's reason. Following the mains stays Quickshell's.
- [x] Tray (`tray.luau`): the items, ranked as Tray.qml ranks them, their
      icons by name, activation, scroll and the DBusMenu menus, on
      Genoma's host beside Quickshell's watcher.
- [x] Downloads (`downloads.luau`): `scripts/downloads` while a cell holds
      it; reveal through FileManager1, else the folder.
- [x] Privacy (`privacy.luau`): captures from PipeWire's links (Genoma's
      audio domain, video nodes included), cameras by `scripts/cameras`
      believed after a moment, screens from niri's casts.
