# Bioma — setup

*2026-10-13, at Akusen's request: a first-run walk-through, and three layouts Bioma ships.
Built the same day: `services/Setup.qml`, `cells/settings/Setup*.qml`, `components/Setup*.qml`,
`scripts/greeter-setup`, `scripts/setup-scan`, `config/presets/`.*

What a new user meets the first time the shell starts: a few steps that put the desktop together,
connect it to niri, offer the login screen, and say what is missing — instead of a message in
pacman's log that nobody reads. Read it with `STYLE_GUIDE.md` and `IMPLEMENTATION.md`, and with
`CELLS.md` §12, whose shape it borrows whole.

---

## What it is

**Setup is the settings cell in another form.** It is not a window and not a surface of its own: it is
the settings cell expanded with **steps** where the categories usually stand: the same capsules, the
same thread, the same panel. It grows from the settings cell and goes back into it.

- It **opens by itself** the first time the shell starts with no override file
  (`~/.config/bioma/override.json`). Someone updating from a beta has one, so they never see it.
  That first start applies **Complete** and writes `setup.pending`, then opens the setup once the
  shell has settled (`Timing.settle`), in the settings cell of the primary monitor.
- Afterwards it is opened on purpose: by **SETUP** at the right end of the PRESET row on the
  Structure page — in the same panel, from WELCOME, with what the last run chose forgotten — or by
  IPC, `setup open` (the focused output) or `setup openOn <output>`. Running it again never touches
  the saved presets: LAYOUT puts a shipped one on screen, and asks first when the layout there is
  kept under no name. `setup state` reports the steps and what each one chose; `setup go
  <step>` and `setup close` exist for keys and for tests.
- **Escape**, or a press outside, means *later*: setup closes, and while `setup.pending` holds it
  opens again at the next start.
- **DONE** on the last step, or **SKIP SETUP** at any point, writes `setup.done` and clears
  `setup.pending`. Skipping leaves everything as it is: the layout on screen, the palette, greetd
  untouched. Nothing asks for confirmation, because nothing is lost.
- A layout applied under it that rebuilds the band the settings cell sat in destroys the cell; the
  setup reopens by itself in the cell that replaces it, or in the middle of the screen if there is
  none (`Setup.lost`).

**Why the settings cell** — three rules already decide it. Expanded forms grow from their origin,
and a panel that appeared centred on the screen would come from nowhere. The mark appears only in
the settings cell (`CELLS.md` §12), and a first run without it would be the one place the shell did not
say whose it is. And capsules feeding a panel through a thread is already how Bioma shows a choice
between pages. A wizard with its own window, progress dots and a NEXT arrow would be the one part
of the shell not speaking its language.

## Shape

As `CELLS.md` §12 Settings, with three differences:

- **The column holds steps, not categories.** It uses the same capsule (240 × 64, 76 pitch), glyph,
  name in Orbitron and line in Spectral. Before a step is visited, its line says what the step
  is about. Once it is done, the line says **what was chosen**: `Minimal`, `Bioma's login screen`,
  `Kept SDDM`, `Two to install`. The column turns into a summary as it fills, so there is no check
  mark to invent.
- **Colour on a capsule's glyph says state**, as everywhere else. Muted means not visited yet,
  the primary gradient means chosen, `active` means the step found something that wants attention
  (a conflict, a missing package), and `alert` means an action in it failed. A step that is simply
  done goes back to muted with its new line.
- **The panel ends in a footer**: **SKIP SETUP** on the left in Orbitron 11 muted, **BACK**
  (outline) and **NEXT** (filled primary) on the right, and **DONE** in NEXT's place on the last
  step. Skip sits inside the panel rather than under the column, where it would be text on bare
  wallpaper. The capsules can also be pressed in any order: NEXT is a convenience, not a gate.
- A step that stops existing while it is shown — the last conflict stopped — hands over to the
  one that came after it.

**Steps exist when they have something to say.** CONFLICTS and SYSTEM appear only when they found
something. On a machine where everything is in place they have no capsule, and the walk-through is
six steps long, the welcome included.

## Steps

In this order (Akusen, 2026-10-13: the desktop first, so it is there to look at while the rest is
answered).

### 0 · WELCOME — glyph `mark`

What this is, before anything is asked (Akusen, 2026-10-13). The greeter's welcome, set inside
the panel: *Welcome to* in Spectral, then the logotype — mark, name, line — then one paragraph
saying what the steps are for and that every answer can be changed later. Each line comes in from
4 px above, a `welcome_stagger` after the one before, over `welcome_open`; once there, nothing
moves. The footer has no BACK here, and NEXT reads **START**.

**Why not a splash screen** — a surface of its own over the desktop would appear from nowhere,
and the mark belongs to the settings cell alone. Inside the setup it is both where it grows from
and the one place the mark may be.

### 1 · LAYOUT — glyph `structure`

The three shipped layouts (below) as three rows, one per preset. Each row holds a **schematic** of the
monitor with the preset's tissues lit on their edges, then the name in Orbitron and one line in
Spectral saying who it is for.

- **Choosing one applies it, live.** The desktop recomposes behind the panel. The panel stays put,
  because every shipped preset keeps the settings cell in the same place (see *Shipped presets*).
- On a first start the one on screen is **Complete**, so the first row starts chosen. Run again
  over a layout kept under no name, a row asks first — *DISCARD THE LAYOUT ON SCREEN?* — and the
  second press answers, as on the Structure page.
- On more than one monitor, one line under the rows: *These are for the primary screen. The others
  start empty; compose them in Settings → Structure.*

### 2 · LOOK — glyph `theme`

- **Palette**: BIOMA (the shipped palettes, as chips) or FROM WALLPAPER (matugen), and DARK or
  LIGHT. The theme is an animated singleton, so the desktop retints while the choice is made.
- **Wallpaper**: FOLDER (the theme cell's picker), and five thumbnails of what is in it, the one
  on screen in the middle; a press on another puts it on the desktop.
- **Other applications**: one switch, off by default, that turns on all of the theme cell's APPS
  targets together: GTK, Qt, the cursor, the icons. One line in Spectral says what it writes, and
  that each target is switched on or off on its own later, in the theme cell (Mod+Alt+T).

### 3 · NIRI — glyph `window`

What `bioma-install --autostart` does today, with the outcome shown instead of printed.

- Three rows, each with its state: **the keys** (`bioma-binds.kdl` beside `config.kdl`), **the
  includes** (Bioma's niri files), and **start with the session** (a switch, on by default).
- **SET UP NIRI** runs `scripts/install`, plus `--autostart` when the switch is on. While it
  runs, the button holds the loader. Afterwards each row reads `calm`, or the step turns `alert`
  and quotes the first line `niri validate` refused, under the sentence *config.kdl was put back
  as it was*.
- Already set up, as on a second run: the rows are calm, the button is not there, and the line
  says so.

### 4 · LOGIN — glyph `lock`

**The greeter becomes a choice.** Today `post_install` takes greetd over on its own. With
strangers installing Bioma, the login screen is the one thing it must not change without asking
(Akusen, 2026-10-13).

- Two rows: **BIOMA'S LOGIN SCREEN** and **KEEP *what is there*** — the login manager found
  through `display-manager.service` (SDDM, GDM, …) or, with none, `TEXT LOGIN`. KEEP starts
  chosen, and NEXT without touching anything keeps it.
- Choosing Bioma runs `pkexec /usr/share/bioma/scripts/greeter-setup enable`, which holds what
  `_greeter_install` does today: the copy of the desktop in `/var/lib/bioma-greeter`, greetd's
  `default_session` with the old file kept as `config.toml.before-bioma`, and greetd enabled in
  place of the old manager. The password is asked by the polkit agent, not by Bioma.
- One line in Spectral says *From the next boot*. Nothing is restarted: restarting greetd from
  inside a session ends that session.
- **With no polkit agent running**, `pkexec` cannot ask. The row then shows the one command to
  run, with **COPY**, and the step says why.
- Choosing KEEP after Bioma was set up — on a second run — runs `greeter-setup disable`, which
  puts the old file back, as uninstalling does today.

### 5 · CONFLICTS — glyph `bell` · *only when something is found*

Someone arriving from another shell still has it starting with niri. Two things then go wrong
without saying why: two bars on one edge, and notifications that never reach Bioma, because
`org.freedesktop.Notifications` has one owner per session.

- **What is looked for**: the owner of `org.freedesktop.Notifications`, found through D-Bus
  (`GetConnectionUnixProcessID`), and known shells and daemons running now: waybar, mako, dunst,
  swaync, fnott, eww, ags, ironbar, hyprpanel, and Quickshell running a configuration other than
  Bioma's (Noctalia, DankMaterialShell, …).
- **One row each**: the name, what it collides on (`OWNS NOTIFICATIONS`, `DRAWS A BAR`), and where
  it starts from: a `spawn-at-startup` line in niri's configuration, a systemd user unit, or
  `NOT FOUND`.
- **STOP** on a row stops it now and takes it out of startup. A `spawn-at-startup` line is
  commented out, not deleted, after a copy of `config.kdl` and before `niri validate`, the way the
  NIRI step writes. A user unit is `systemctl --user disable --now`. Where it starts from cannot be
  found, STOP only stops it, and the row says *it will come back at the next login*.
- Once the notification name is free, Bioma's notifications service claims it. If Quickshell's
  server cannot claim a name after it has started, DONE restarts the shell instead, and the step
  says so before it happens (to be verified on the build, as `CLAUDE.md` asks of every
  service).

### 6 · SYSTEM — glyph `screen` · *only when something is missing*

`bioma-install --check`, drawn.

- **To install**: the missing packages in one well, named by what they are for (as `--check`
  names them), with the single command that installs them all — `sudo pacman -S …`, and
  `paru -S …` for the AUR ones — and **COPY**. Bioma never runs a package manager itself.
- **To enable**: system services that are installed but off (NetworkManager, Bluetooth, CUPS,
  Avahi), each with **ENABLE**, which runs `pkexec systemctl enable --now` on it. With no polkit
  agent, the command with COPY instead.
- **No polkit agent** is itself a row here: without one, nothing in Bioma that needs a password
  can ask for it.
- **Another polkit agent.** Bioma carries its own (CELLS.md §19), and polkit allows one per
  session: the first to register keeps it, so another agent started at login holds the session
  or races Bioma's at every start. When `scripts/polkit-agent report` finds one running or set to
  start — a `spawn-at-startup` line in niri's configuration or a file it includes, an enabled
  systemd user unit, an XDG autostart entry the session would run — PASSWORDS names it and where
  it starts, with two answers (Akusen, 2026-10-15):
  - **Use Bioma's agent** runs `polkit-agent takeover`: the niri line is commented out under a
    note (validated by niri first), the unit disabled and stopped, the autostart entry shadowed in
    `~/.config/autostart` with `Hidden=true`, and the running agent sent SIGTERM. Nothing is
    deleted. Bioma's agent then registers again in place, no restart.
  - **Keep** it switches `polkit.agent` off, which ends the race the other way.
- **Optional**, in its own well below a dashed rule: dictation, with its size said plainly
  (*about half a gigabyte, for one key*) and its command.

### 7 · KEYS — glyph `keyboard`

Bioma says nothing at rest, so a new user does not know where to start. This step shows **the
seven keys** to know, read from the user's own `bioma-binds.kdl`, so it shows what is actually
bound: launcher, settings, theme, capture, vitals, system, lock. One row each, the combination as
keycaps on the left and what it opens in Spectral. Below them: *Every key, at any time:
Mod+Shift+/*, niri's hotkey overlay, where every Bioma key has a title.

Then **DONE**.

## Shipped presets

PRD §3.7 is amended (Akusen, 2026-10-13): Bioma ships three layouts as starting points. The rule
underneath does not change. They are compositions of the same vocabulary, nothing a user could
not build in Settings → Structure, and once applied the layout is the user's to change.

| Preset | Top membrane | Bottom membrane | Floating |
|---|---|---|---|
| **Complete** | the base layout: workspaces, window title · media, privacy, timer, download · vitals, utility, theme, connectivity, tray, audio, settings, system | dock, auto-hide | notifications, launcher; organisms: clock, vitals, calendar, media, lava lamp |
| **Minimal** | workspaces, window title · media, privacy · connectivity, tray, audio, settings, system | — | notifications, launcher |
| **Empty** | settings, system | — | notifications, launcher |

- **Settings and system are always the last two cells of the top membrane's right tissue**, so the
  setup's origin does not move while LAYOUT recomposes the desktop under it, and the person who
  chose Empty still finds the two cells they need to change it.
- **Empty keeps the floating notifications and launcher.** Both are invisible at rest — one
  conditional, one invoked — so the desktop is still empty. Without the notifications cell, Bioma
  would own the notification name and show nothing, so another program's message would be
  swallowed in silence.
- **Complete carries five organisms** (Akusen, 2026-10-13): clock and vitals in a row, calendar
  and media under them, the lava lamp beside — on the primary screen's grid, from its top-left
  corner. The base layer still ships none: nobody's desktop gains furniture by updating, only by
  choosing Complete.
- All three are on `primary` only, like the base layout.

**Where they live.** One file each in `config/presets/`, in a preset's shape plus `order` and
`line`. Complete's file names `from_base: ["membranes", "floating"]` and holds only its organisms:
its membranes and floating tissues are read from `config/default.json` and never copied, so the
default and Complete cannot drift apart. Adding a shipped preset costs one file.

**Applying one writes it**, as `Presets.apply` does for a saved one: its lists are copied into the
override and become the user's. An update that changes a shipped preset does not reach a desktop
that applied it.

**In Settings → Structure** the dropdown lists the shipped presets below the user's, under a
dashed rule, in the same rows. A shipped row has no cross, because it cannot be forgotten. Its
name is reserved: SAVE AS over it reads `TAKEN`, dimmed, and a user preset cannot take a shipped
name, in any case. `CHANGED` works as for any other preset.

## Install

- **`post_install` stops setting up the greeter.** It loads uinput as before, and its message
  shrinks to: install, then start Bioma once with `bioma -d` from a terminal inside niri, and *it
  walks you through the rest*. `post_remove` keeps `_greeter_remove`, for every machine where a
  beta set greetd up.
- **`scripts/greeter-setup`** (new; `enable`, `disable`, `status`) holds the body of
  `_greeter_install` and `_greeter_remove`, run as root through `pkexec`. It finds the installing
  user from `PKEXEC_UID`. `status` needs no root, and is how the LOGIN step knows what is there.
- `bioma-install` stays, for anyone who prefers a terminal and for dotfiles. Setup calls it; it
  does not replace it. Two modes were added for the setup: `--report` prints what `--check`
  finds, what is already in niri's configuration and whether a polkit agent runs, one fact per
  line in tab-separated fields; `--niri-only` writes the keys and includes without the program
  check, which the SYSTEM step reports separately.
- **`scripts/setup-scan`** (new; `list`, `stop`) finds the CONFLICTS and stops one. A login manager
  the greeter replaced is remembered in `/var/lib/bioma-greeter/.manager-before`, so `disable`
  and uninstalling enable it again.

## Measures

As `CELLS.md` §12 unless listed here.

| Measure | Value | Note |
|---|---|---|
| step capsule | 240 × 64 px | the category capsule; the line becomes the outcome once done |
| panel | 520 – 640 px | as wide as the step asks: LAYOUT and CONFLICTS 640, SYSTEM 600, the rest 520 |
| preset row | 76 px | schematic, then name (Orbitron 12) over line (Spectral 13 muted); organisms drawn as their panels at 35 % |
| schematic | 96 × 54 px | the monitor as a 16:9 outline, radius 6, hairline in `line`; tissues as 4 px bars on their edges, primary on the chosen row and muted on the others |
| footer | 44 px | BACK and NEXT/DONE 26 px high, 12 from the panel's edges |
| skip | Orbitron 11 | muted, at the footer's start, primary on hover |
| keycap | 26 px | outline, radius 6, Orbitron 11; `+` between keys in muted |
| command well | 38 px | monospace is not used: Orbitron 11, COPY at the right end |

## Motion

| Event | Motion | Timing |
|---|---|---|
| first start | the shell comes up as always; once it has settled, the settings cell expands into setup | `open` after `settle` |
| changing step | the thread slides to the new capsule, the panel's content cross-fades; its width holds — the widest step's, as in the settings | `transition`, `contentFade` |
| a preset applied | the desktop reflows behind the panel, the panel does not move | `reflow` |
| an action running | the button holds the loader, whose spin is the work still pending — not a decoration | `loader` |
| DONE, SKIP, Escape | the panel goes back into the settings cell | `close` |

## Configuration

```json
"setup": { "pending": false,   // true from the first start until DONE or SKIP
           "done": true }      // written by DONE or SKIP; then only SETUP or IPC opens it
```

`config/presets/*.json` holds the shipped presets.

## Open

- ~~**A polkit agent of Bioma's own.**~~ Built (CELLS.md §19, 2026-10-15), on by default, with
  the hand-over from another agent in the SYSTEM step above.
