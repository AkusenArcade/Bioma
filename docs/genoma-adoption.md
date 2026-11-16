# Bioma ← Genoma: adoption inventory

Written 2026-11-16. Bioma (`bioma-shell` 1.0.0-beta.71) requires Genoma
0.1.9; Genoma `main` now holds 0.1.10 to 0.1.15 and everything under
"Unreleased" in its CHANGELOG. This lists, for each capability Genoma
gained, where it touches Bioma and what to do with it: **migrate** (a
Bioma service or an external tool replaced by Genoma's), **use** (a
visual capability put to work, Bioma as Genoma's showcase), or
**ignore** (with the reason). Every visual use is held to Bioma's rules:
movement encodes a live value, colour says state, a cell exists when it
has something to say, expanded forms grow from their origin.

Each step lands as its own small release, raising the `genoma` floor in
the AUR package. Nothing reaches Akusen's desktop until his live Genoma
binary is rebuilt, which is his call.

## A. Services Genoma now does natively (migrate)

| Genoma | Bioma today | Change | Gain | Note |
|---|---|---|---|---|
| `@genoma/capture` (wlr-screencopy) | `services/capture.luau`: `grim` for the freeze, regions, whole screens and unfrozen OCR | all through `capture:screenshot`; the colour picker stays niri's (it draws the crosshair); window shots stay on niri's action; OCR keeps `tesseract`, crops keep `magick` | one dependency fewer (`grim`), no process per shot | verified pixel for pixel against grim |
| `@genoma/capture` | `lock.luau`: `grim` per output for the lock's first frame | **ignore**: the lock takes `grim` as a process on purpose — a protocol error inside the lock's own connection would end the lock, a failed `grim` only costs the photograph | — | decided when the lock was built |
| `@genoma/kit/record` | `services/capture.luau`: `wl-screenrec` with codec, bitrate and an even encode resolution | **ignore**: `kit/record` has none of those three, and the even resolution is what makes a hand-drawn region encodable | — | extend `kit/record` first if it is ever wanted |
| `@genoma/brightness` | `services/brightness.luau`: `brightnessctl`, `ddcutil` processes | `brightness.displays`, `:set` | no processes; DDC writes coalesced | backlight path needs the laptop test |
| `@genoma/drives` | `services/drives.luau` + `scripts/drives` | `drives.list`, `:mount/:unmount/:eject` | one script fewer; rate and free space built in | tested on a real stick |
| `compositor.keyboard`, `switch_layout` | `services/keyboard.luau`: niri events for the current layout | current layout and switching from Genoma; the catalogue (`scripts/xkb`) and the niri include stay | less parsing | Hyprland path untested |
| `vitals.cpu_temp`, `gpu_temp`, `sensors` | `services/system_monitor.luau`: hwmon read by hand, `temperature_sensor` override | **ignore** for now: requiring `@genoma/vitals` starts a second sampler (every hwmon chip re-read every 2 s) beside Bioma's own; worth it only when all of `system_monitor` moves onto Genoma, which lacks network traffic, VRAM and processes | — | revisit with those in Genoma |
| `@genoma/notifications` `image` | `services/notifications.luau` says pixel-only images cannot be drawn | draw `image` in the notification (falls back to icon, then bell) | images from Telegram, Discord… appear | |
| `@genoma/notifications` inline replies, activation token | none | a reply field in an expanded notification that `can_reply`; pass a token on action so the app takes the focus | new, small | design choice: where the field grows from |
| `@genoma/accounts` | `lock.luau`, `greeter.luau`, `cells/system*.luau`: name and `~/.face` read by hand | `accounts.me` / `accounts.users` (greeter list) | the greeter can list users properly | `set_icon` untested (would touch his avatar) |
| `g.colour` | `core/colour.luau` (Qt colour arithmetic in Luau) | call `g.colour` from `core/colour` | native speed for every derived colour | same algorithms, port from Bioma |

## B. Visual capabilities (use — the showcase)

| Genoma | Proposed use in Bioma | The live value behind it |
|---|---|---|
| `g.svg` with `parts` | Icons that carry a reading by part: Wi-Fi arcs lit by signal strength, battery fill by charge, volume waves by level, the bell by unread count, the drive by space used. Static icons stay `g.icon` (cheaper) | strength, charge, level, count, space |
| Path `d` morph | A shape morphing between two states: play ↔ pause as one outline (`components/play_pause`). Dials and gauges (`components/gauge`, `dial`, `vital`) keep their SDF arcs: dropped | the state change |
| `morph = "name"` (shared transitions) | A cell's contracted form and its expansion as one shape that grows from its origin — the rule "expanded forms grow from their origin" taken literally. Start with one cell (clock → calendar), then the others | opening and closing (the person's act) |
| Particles: sprites, sub-emitters, forces | Traffic as particles whose rate is the transfer rate (connectivity expansion, downloads); a notification burst whose count is the number arrived | bytes a second; count |
| `compute` simulations | An organism whose simulation speed is the machine's load (reaction-diffusion, boids), beside lava and the others | CPU or GPU load |
| Post-processing passes | Only where a value drives the pass: e.g. a privacy pass on the lock while a capture or recording is running. No decorative passes | capture/recording state |
| `isolate` | Controls held dimmed as one picture, so their parts do not show through each other: the slider (muted), the timer's face (paused), the timer's bar in the clock (stopped). Not the expansions' fade: measured, 120 ms hides the difference | — (correctness) |
| `cache = true` | Rich static subtrees beside moving ones (settings pages, organisms' static parts) drawn once | — (cost) |

## C. Smaller fits and things to ignore

| Genoma | Decision | Why |
|---|---|---|
| Touchpad gestures (`on_pinch`, `on_swipe`, `on_long_press`, `on_hold`) | **use, small**: swipe on the workspaces cell, long press for touch on the laptop | his laptop has a touchpad and touchscreen use is coming with new users |
| Layout: `flow`, `snap`, insets | **check** the settings grids and the dock; adopt where Bioma lays out by hand | less layout code |
| `@genoma/theme` (`theme.new`) | **later**: Bioma's `core/theme` is the model it was built from; moving is a refactor of every cell's colour access, worth one release of its own | risk is high, gain is code size |
| `@genoma/portal` settings | **ignore**: Bioma sets the desktop's colour scheme, it does not follow it | Bioma is the source |
| `@genoma/portal` file chooser | **ignore** for now: Bioma's pickers are its own design | design is normative |
| `kit` components (tree, calendar, colour and file pickers) | **ignore**: Bioma's components follow `docs/design` | design is normative |
| Shared modules, `genoma module` | **ignore**: Bioma is one shell | |
| `portal:screenshot` | **ignore**: niri has wlr-screencopy | |

## Status of A (2026-11-16)

Done, each its own commit, verified headless and on the live shell:
capture (c119406), brightness over DDC (backlight on the laptop
pending), drives, keyboard, notification pictures and the activation
token, accounts (session's name, uid, picture), `g.colour` (alpha
remembered over the native call, mix, luminance: equal to the byte,
a miss four times cheaper). Kept as they are, with reasons above: the
lock's grim, the recorder, the sensors. Inline replies done at Akusen's word: a Reply among the actions grows
a field across the panel, and the cell takes the keys while it is open
(the panel stays, its clock stops); verified with a real reply.

## Status of B (2026-11-16)

**B1, icons by part** — `components/glyph.luau` draws a file of
`assets/icons` as nodes (`g.svg` with `gradient_top`/`gradient_bottom`,
Genoma after 0.1.16), identical to `g.icon` at rest; parts the file hides
at opacity 0 are revealed with `glyph.shown`. In use: the Wi-Fi arcs fade
lit or dim one by one with the strength (connectivity cell and its
header); a stick's body filled as far as the drive is used (drives cell,
contracted and rows); the resting bell rings for what is unread, a ring
each side drawn up from its shoulders as far as the count (1 short, 5 or
more whole); the brightness OSD's rays drawn as far as the level. Two
rings each side were tried and merge at 18 px.

**B2, morph** — the cell→panel budding stays (Akusen, 2026-10-28): a
pill that keeps its content cannot morph into its panel. Morph is used
where a thing becomes another inside an expansion: the clock's + PLACE
opens into its search field and + CALENDAR into the address field, one
shape each. The content takes turns with it: it fades out before the
chip opens and fades in after the field has closed back, never under a
moving shape. A `morph` timing joins the timing set.

**B3, particles** — `components/traffic`: the connection carrying the
traffic (the wire, else the Wi-Fi network joined) has two lanes along
its row, in and out, particles as many as the bytes on a logarithmic
scale. Notifications arriving a moment apart burst from the badge, one
particle each. `components/rate_particles` takes rate_thread's place in
the download cell (drives keep rate_thread). Osmosis stays a shader: it
is one metaball field, drops budding from the membrane and melting into
the pool, which independent particles cannot do.

**B4, simulations** — `organisms/plankton.luau` (ORGANISMS.md §17): a
swarm, Genoma's boids on the GPU. Its speed is the processor's load on a
square-root scale, so an idle machine still drifts; how close it keeps is
the memory used; how many there are is the kernel's tasks, in steps of
twenty-five. Clipped to the panel's round corners (Genoma's `clip` cut a
rectangle and the creatures crossed them; it now follows the radius), and lit by `genoma:glow`, a bloom
pass over the swarm.

## Order proposed

1. **A, the services** (capture, lock, record, brightness, drives,
   keyboard, sensors, notification images, accounts, g.colour) — each a
   small step, verified as before (headless first, then on screen).
   Brightness and accounts' backlight/greeter parts need the laptop.
2. **B, one showcase at a time**, each chosen by Akusen from the list:
   start with `g.svg` icons by part (Wi-Fi, battery, volume) and the
   clock → calendar morph, the two most visible.
3. **C**, as each comes up.

Before step 1: Genoma 0.1.16 released (everything on `main`), and
Akusen's live binary rebuilt on it.
