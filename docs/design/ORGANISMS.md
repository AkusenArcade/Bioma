# Bioma — organisms

*Approved 2026-10-04, media redrawn at Akusen's request. Built: the structure, arranging, the five organisms, the Settings category; since then the note, the lava lamp, the cytoplasm, the growth rings, osmosis, the photoperiod, the vacuole and the sediment.*

The visual specification of the organisms: read-only surfaces that live on the desktop, under
the windows, in the part of the screen the top and bottom membranes leave free. Read it with
`STYLE_GUIDE.md` and `IMPLEMENTATION.md`; the live page is `pages/organisms.html`.

---

## What an organism is

A cell speaks when something happens and goes quiet when nothing does. An organism is the
opposite contract: **it is there because it was put there to be looked at.** Nobody clicks it,
it does not open, it hangs from nothing. It is the desktop's own furniture, seen on an empty
workspace and between the windows, and gone under them the moment there is work on screen.

That changes three rules and keeps the rest.

**Changed**
- **It speaks at rest.** Figures are allowed — `34%`, `18°`, `3:42` — because a surface placed
  to be read that refused to say anything would be an ornament. *Silence at rest* is a rule for
  cells on a membrane, where the eye passes a hundred times an hour; the eye goes to an organism
  on purpose.
- **It has no thread and no origin.** Like the launcher it is born in place: it appears by
  growing from its own centre, and leaves by shrinking into it.
- **It takes no input.** The pointer passes through it to the desktop. The one exception is
  arranging (below), when it is lifted above the windows and can be dragged.

**Kept**
- Colour is state, form is domain: a vitals ring is the CPU's ring, in the CPU's state colour.
- Motion is data: what moves encodes a live value, and nothing moves at a fixed rate for its own
  sake. A clock organism does not tick seconds.
- Two voices: Orbitron for measurements, Spectral for human language.
- Conditional presence where it has a meaning: media is absent with nothing playing, a note
  when its file cannot be read. Weather is not conditional: without a reading it is blank.
- Every colour comes from `Theme`, every duration from `Timing`, every size from `Metrics`.

## Where they live

- **Layer.** Their own layer surface per monitor, namespace `bioma-organisms`, on the **Bottom**
  layer: above the wallpaper, below every window. It reserves nothing and never takes the
  keyboard; its input region is empty, so it cannot steal a click from the desktop.
- **The free area.** The screen minus what the membranes hold, measured to **the line the
  windows begin on**: past a top or bottom membrane's strip and niri's gap — whether the
  membrane reserves space, auto-hides, or is not declared at all, in which case it is the strip
  one would take at the membranes' density — and the 12 px edge margin on a side with no
  membrane. It is the same line a floating tissue anchored to an edge sits on
  (`structure/Strips.qml`). An organism is always wholly inside it; when a membrane is added or
  changes density the free area changes and the organisms are clamped back into it, never cut.
- **Size** is a **template**: so many **units** across and down, the shape gap (24) between
  each two — a unit is 200 at the normal step and follows the organism's density. One template
  per kind, so organisms of different kinds fall into tidy clusters (Akusen, 2026-10-07); the
  content is laid out in what the template leaves, never the other way round.

  | Template | Panel | Organisms |
  |---|---|---|
  | 1 × 2 | 200 × 424 | lava lamp, osmosis |
  | 2 × 1 | 424 × 200 | clock, weather, photoperiod, cytoplasm, vitals in a row, note `short` |
  | 3 × 1 | 648 × 200 | vitals in a row of four (with a battery): a figure cut short is not a figure |
  | 2 × 2 | 424 × 424 | media, calendar, growth rings, vacuole, sediment, vitals `square`, note `medium` |
  | 2 × 3 | 424 × 648 | note `tall` |

- **The grid.** Organisms stand on a grid of squares laid over the free area. Its **module** is
  one unit and one gap (224), and it is divided into 1, 2, 4 or 8 squares — always a whole
  number, so an organism's edges land on the lines and it covers whole squares, never halves.
  An organism covers its panel and half a gap around it: two on neighbouring squares stand one
  gap apart. The grid is the free area cut to the finest square, the remainder shared on both
  sides, and every division counts from the same corner, so changing it moves nothing.
- **Position** is stored as the grid point of the organism's top-left corner — `col` and `row`,
  in modules from the grid's corner (`1.5` is a module and a half). A smaller screen or a new
  membrane clamps it back inside the grid; it is never cut. A block with no point — written
  before the grid, or just added — has its centre as fractions of the free area (`x`, `y`) and
  stands on the nearest grid point until it is next dropped.
- **Overlap** is not prevented, as with floating tissues — but on the grid neighbours stand one
  gap apart, so it only happens on purpose.
- An organism with a `size` of its own is a template at its own step, and covers what it covers;
  its top-left corner still lands on the lines.

## Surface

Every organism is a **glass panel**: the cell's flat glass fill, its blur
(`ext-background-effect`, on the panel's own shape), and the rim — light at the top edge
running to `line` at mid-height. Radius 20, the panel radius: every organism is taller than the
110 px pill ceiling. Inner padding 20. Wells, where an organism has rows, radius 10.

**No shadow.** The shadow is reserved for what is invoked or expanded — what stands *above*
something. An organism stands on the wallpaper; a shadow would lift it off the desktop and make
it read as a panel waiting for a click.

Density follows the membranes' step (compact, normal, comfortable), like the floating tissues
since beta.20. One organism can override it with its own `size`.

## Motion

| Event | Motion | Timing |
|---|---|---|
| appears (added, or its condition becomes true) | grows from its centre in width and height; content fades in with 4 px rise once at size | `open`, flat curve (it is a large panel) |
| leaves | content out, then the shape shrinks into its centre | `close` |
| track or forecast changes | content cross-fades, the panel does not move | `contentFade` |
| free area changes | slides to its clamped place | `reflow` |
| live indicators | as in the style guide: CPU beat, RAM liquid, GPU satellite, band | data |

## Arranging

Organisms take no input at rest, so they are placed in a mode of their own.

- **Entered** from Settings → Cells → Organisms → *Arrange*, or by IPC: `organisms arrange`
  enters or leaves, `organisms done` leaves, `organisms state` and `organisms list` say where
  things are (`qs -p …/shell.qml ipc call organisms arrange`).
- **While arranging**, every screen's organism surface comes up from the Bottom layer to the
  **Top** layer — the organisms are lifted, not copied — takes the pointer, and dims the windows
  behind. The free area is drawn: a dashed outline in `line`, 1 px (never under 2 physical px),
  radius 20. Over it, **the grid**: hairlines in primary, 8 % on every square, 22 % on every
  module, so the units of the templates can be counted.
- **The wheel** divides the grid — up for larger squares, down for smaller — anywhere on any
  screen, over an organism too. Under Done: `GRID 1/2 · SCROLL TO CHANGE`, Orbitron 11 muted.
  The division is written with the positions on leaving (`arrange.grid`, default 2).
- Each organism wears a **dashed primary outline** 8 px outside its panel, and a plate inside its
  top-left corner (10 in, the background at 88 %) with its name and template —
  `CLOCK · 2 × 1`, Orbitron 11 primary — over its place on the grid, `COL 5 · ROW 3` muted:
  column and row in the squares as they are divided now, counted from one. Above the panel, as
  it first was, the label of an organism one unit wide ran into its neighbour's. Hover brightens
  the outline; press and drag moves it. Drag is not scaled, not tilted: the panel moves whole,
  and where the press landed inside it stays under the pointer.
- **Absent organisms are placed in their blank form.** While arranging, an organism with nothing
  to show comes up anyway — its own panel at its own size, empty, saying in Spectral italic, text
  faint, what is missing — so it can be dragged; leaving the mode, it leaves with it (Akusen,
  2026-10-05: a media organism added with nothing playing opened the mode with nothing to drag).
  Media blank: glass, the `sinestesia` glyph, the band lying still, *Nothing playing*. Note
  blank: the file's name (or *Note*) and *No file chosen…* or *This file cannot be read.*
- **Landing.** In the hand the panel follows the pointer freely; the squares it would cover are
  lit under it — its own shape, primary at 14 % with a 55 % hairline — and the plate says that
  grid point. Let go, it slides onto them (`reflow`, flat open curve).
- An organism dropped onto **another monitor** moves there; it lands on the nearest grid point of
  that monitor. It leaves the first screen from where it was let go and grows on the
  second. (Every surface keeps one organism for every block and shows only its own, so a drop
  never destroys what the hand is holding.)
- **Done** — a primary button centred at the top of every screen's free area — or Escape leaves
  the mode. The positions are written to the override layer on leaving, in one write.
- **The keyboard is on demand, never exclusive.** niri gives it to the surface that is pressed,
  so Escape is heard from the first press on; before it, Done or the same keybind leave. Held
  exclusively by one screen, every press on the other one was cancelled the moment it landed
  (found 2026-10-04 with a synthetic pointer: once an organism had been carried there, every
  press failed until the shell restarted).

## Settings

Settings has a category of its own, **ORGANISMS** (glyph `organisms`: a desktop with its
membrane and one panel standing on it), laid out in wells like the Session page:

- one well per monitor, its organisms as chips, a dashed **+** chip to add one: the kinds appear
  as a row of chips under a dashed rule — between what stands on the desktop and what could — and
  the one chosen appears at the centre of that screen's free area while
  the settings close and the mode enters *Arrange*;
- a chip's × takes it away: it shrinks into its centre on the desktop, and the list is written
  without it once it has gone;
- a press on a chip's name shows its options in the well: SIZE (the membranes' step, or its own),
  VISUALISER for media, LAYOUT for vitals, HEIGHT and FILE for a note, CITY for weather. Every
  option of an organism is found the same way, under its chip (Akusen, 2026-10-04: the city had a
  well of its own and was the one exception). The city is one place for every weather organism, so
  the same field stands under each of them; it keeps what was typed when the place is not found
  and says why under it, in the alert colour;
- **ARRANGE** — the button that closes the settings and enters the mode.

Blocks written from the shell carry an `id`, so a surface keeps each organism's delegate across
a change to the list: one taken away from the middle does not take the ones after it with it.

---

## 01 · Clock

*Always present · the time, large.*

The time in Spectral, the clock cell's face beside it, the date under them in words. The face
is the cell's own — the hour filling (or, while a timer runs, what is left of it emptying) and
the disc round the rim where the second hand is, moving continuously. Without it the organism
read as unfinished (Akusen, 2026-10-04); it is the same live value the cell shows.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 200 | template 2 × 1; padding 20 |
| time | Spectral 72 / 500 | tabular figures, primary gradient fill |
| date | Spectral 19 / 400 | `Sunday 4 October`, text muted |
| face | 62 | the cell's `Dial`, the size of the vitals organism's rings, 16 right of the figures |
| gap time → date | 4 | |
| format | the clock cell's | 24 h / 12 h, read from the clock cell's option |

**Limit cases** — 12 h: `9:41` with `PM` in Orbitron 15 beside it, baseline-aligned. A long date
(`Wednesday 30 September`) fits the template at every step, never ellipsed.

**Options** — `size`.

## 02 · Media

*Present while a track is loaded · the cover as the surface, the sound rising out of it.*

Not the sinestesia cell's track panel made bigger. In the cell the cover is an 88 px thumbnail
beside the words and the band is a strip; here **the cover is the surface** and **the band is the
largest moving thing on the desktop**. The band is the sound leaving the machine, from the same
capture as the sinestesia cell (one capture, never two); the track is the active MPRIS source.
(Akusen, 2026-10-04: more room for the art, used as the background, and for the visualiser.)

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 424 | template 2 × 2, square like the art; radius 20 |
| cover | the whole panel | edge to edge, cropped to the panel's radius on the **image**, never by clipping the panel — the rim is drawn over it. Non-square art (a video thumbnail) is cropped centred |
| scrim | over the cover | the theme's `background`, transparent down to 36 % of the height, 0.80 at 60 %, 0.92 at the bottom — the words are read on the shell's own colour whatever the picture is |
| band | 384 × 96 | 48 bars of 4 px, 8 px pitch, symmetric from the centre line, primary gradient over the band's height; it rises out of the picture where the scrim begins |
| title | Spectral 22 / 700 | one line, ellipsis; 16 under the band |
| artist | Spectral 16 / 400 | text muted, one line, ellipsis |
| album | Spectral 13 / 400 | italic, text faint; omitted when absent |
| progress | 3 px | primary, 7 px node at the head; times in Orbitron 11 tabular under it; 14 under the words |
| padding | 20 | the content sits on the bottom edge |

**Present** while the source is Playing or Paused with a track. **Absent** when stopped or no
source has a track. Paused: the band lies still as a row of dots (there is no sound) and the
progress holds — the organism stays, because a paused track is still the track.

**The band moves whenever there is sound.** It was first held still while the screen's workspace
had any window, but niri leaves the desktop showing beside and between the windows, and there a
still band beside a playing track said silence (Akusen, 2026-10-04). niri does not report where a
tiled window is on screen, so the organism cannot know it is covered; a band that may be seen
has to be true. `Sinestesia.hold(owner, on)` keeps the one capture running while anything holds
it — the sinestesia cell, which already holds it whenever there is sound, or the organism.

**Track change** — the new cover cross-fades over the old one (`contentFade`), then the words;
the panel does not move or resize.

**Limit cases** — no cover: the panel is glass, and the `sinestesia` glyph, 96 px in muted text,
holds the picture's place in the upper half; the scrim is not drawn. No metadata but sound (a
browser video with no MPRIS): absent; the band alone is the sinestesia cell's job. Stream with
no length: no progress line, no times. A very light cover: the scrim carries the words; the band
over the bright part keeps its gradient — it is light on light only where there are no words.

**Options** — `size`, `band` (on / off; off, the words move up into the band's place and the
cover shows more).

## 03 · Vitals

*Always present · the machine, read in full.*

The vitals cell's expanded pods, gathered in one panel and never closed. Same indicators, same
rhythms, same state colours — an organism does not get a second vocabulary for the CPU.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 200 | template 2 × 1; 3 × 1 (648 × 200) with four domains. The columns share the width, 16 apart; a column widens to its longest line (`6.7 / 30.5 GB`) rather than cutting a figure short |
| indicator | 62 | 1.5 px ring, as in the pods |
| label | Orbitron 15 / 500, +0.06 em | `CPU` `RAM` `GPU` `BAT` |
| value | Orbitron 20 / 500 | state gradient fill (calm / active / alert) |
| secondary | Orbitron 13 / 400 | `4.8 GHz`, `14 / 32 GB`, `1.9 GHz`, `2 h 10` |

Battery appears only on a machine that has one, as in the cell.

**Options** — `size`, `layout` (row / `square`: template 2 × 2, the 2 × 2 block centred).

## 04 · Calendar

*Always present · this month.*

The clock cell's month, alone and read-only: no arrows, no navigation — a calendar on the wall,
not a planner. Today is the only lit day.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 424 | template 2 × 2; padding 20: the width in 7 days, the six weeks share what header and weekdays leave |
| month | Spectral 19 / 700 | `October`, year in Orbitron 13 muted beside it |
| weekdays | Orbitron 11 | text faint, first letter; the week starts on Monday, as in the clock cell |
| days | Orbitron 13 / 400 | 7 columns × 37, rows of 34 |
| outside days | Orbitron 13 | text faint |
| today | 28 px disc | primary gradient, figure in `background`, weight 700 |

**Six weeks always**, as in the clock cell: every month fits, and the panel never changes
height — an organism that grew a row would move on the desktop by itself, since it is placed by
its centre. Midnight: today moves; nothing else animates.

**Options** — `size`.

## 05 · Weather

*Always present · now, and the next hours; blank without a reading under two hours old.*

The weather where Akusen is: the city from Settings, geocoded once by Open-Meteo, then the
forecast every 30 minutes through the proxy when one is on. No key, metric units.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 200 | template 2 × 1; padding 20 |
| city | Spectral 15 / 700 | the name as geocoded |
| condition glyph | 44 | primary gradient, new weather glyphs (below) |
| temperature | Orbitron 40 / 500 | primary gradient, `18°` |
| condition | Spectral 15 / 400 | `Light rain`, text muted |
| high / low | Orbitron 13 | `24° · 12°`, text muted |
| hours well | 384 × 64, radius 10 | next 5 hours: Orbitron 11 hour, 20 glyph, Orbitron 13 temperature |

The temperature is **not** a state: it measures the weather, not the machine, so it is primary
and never calm, active or alert — the same reason a timezone dial never changes colour.

**Glyphs** — eight new icons for `docs/design/icons/`, built to the icon rules (grid 24, stroke
1.5, round caps, no fills): `weather-clear`, `weather-clear-night`, `weather-partly`,
`weather-cloudy`, `weather-fog`, `weather-rain`, `weather-snow`, `weather-storm`. Open-Meteo's
WMO codes map onto them.

**Limit cases** — offline: the last reading stays until it is two hours old, then the organism
turns blank. **Blank** (Akusen, 2026-10-05: always visible, and it must say how to set the
city): the place's name or *Weather*, the glyph unlit in text faint, no figures, what is missing
in the condition's place (*No city set* · *No forecast* · *Asking…*), and in the hours well, in
Spectral italic, why — *Type a city under Settings → Organisms → Weather → City.*, or the
service's reason. No city set: blank, and Settings says why under the field too. A city that geocodes to
nothing: the field's error, as every field's — outline in alert, reason under it.

**Options** — `size`, `city` (shared by every weather organism, stored once under `weather`).

## 06 · Note

*Approved 2026-10-04. Present while its file exists · a Markdown file, read.*

A Markdown file on the desktop, read and never written. The text lives where it is written — an
Obsidian vault, a repository — and the organism shows it: edit the file anywhere and the note
changes on the desktop, watched by `FileView` rather than polled. Writing inside the organism was
considered and refused (Akusen, 2026-10-04): an organism takes no input, and a second, poorer
editor of a file that already has a good one is not a feature.

**Drawn, not handed to Qt's Markdown.** The file is read line by line into blocks the organism
draws itself, so a task is a shell control rather than a font's ☐ and the two voices hold:

| Block | Drawn as | Note |
|---|---|---|
| title | Spectral 15 / 700, one line, ellipsis | the file's first `# heading`, else its name without `.md` |
| when | Orbitron 11, text faint, right of the title | `EDITED 2 H AGO` — when the file last changed; a figure, so allowed |
| `## heading` | Spectral 14 / 700, 10 above | `###` and below the same size, text muted |
| paragraph | Spectral 14 / 400, line height 1.3 | wraps; `**bold**` 700, `*italic*` italic, `` `code` `` Orbitron 11 |
| `- item` | a 4 px node in `node`, 14 in, the text beside it | nested items 14 further in |
| `- [ ] task` | a 12 px ring in `line`, the text beside it | open |
| `- [x] task` | a 12 px disc with the primary light, the text in text muted | done — muted, not struck through: a struck line is heavier, not lighter |
| `> quote` | a 2 px bar in `line`, the text in italic | |
| code block | a well (radius 10), Orbitron 11, no wrapping, elided | |
| `[text](url)`, `[[Note]]` | the text, plain | there is nothing to press |
| `---` front matter | not drawn | Obsidian's properties are not the note |
| `---` rule | a 1 px line in `line` | |

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 424 | padding 20; `height` chooses the template: short 2 × 1 · medium 2 × 2 · tall 2 × 3 |
| header | 22 | title and when, then 12 to the text |
| block gap | 6 | 10 before a heading |

**Longer than the panel.** Nothing scrolls — there is no hand to scroll it. The text runs to the
panel's foot and fades out over the last 36 px, and in the bottom-right corner, over the fade,
`12 MORE LINES` in Orbitron 11, text faint, says how much is not shown. A taller `height`, or a
shorter note, is the answer; the organism does not shrink its type to fit.

**A change to the file** — the text cross-fades (`contentFade`); the panel does not move. A change
that only touches what is below the fold changes the count and nothing else.

**Limit cases** — the file missing or unreadable: the organism is absent, and Settings says why
under the file's field, in the alert colour. An empty file: the title and *Nothing written yet.*
in Spectral italic, text faint. A file of a megabyte: read up to what the panel can hold plus the
count; the rest is never parsed.

**Options** — `size`, `file` (a path; `~` is the home), `height` (`short` · `medium` · `tall`).

**Settings** — the note's chip opens FILE, a field with the path and a CHOOSE button that opens
the file picker (zenity, already a dependency, limited to `*.md`), and HEIGHT. A note added with
the dashed chip does not start the arranging mode: with no file it has nothing to show, so the
settings stay open on its options, and it is placed once it has one.

**Not now** — ticking a task from the desktop would be the one input that made sense, and it is
still input; the edit stays where the file is. A keybind or IPC call that opens the file in its
default application could come later, outside the organism.

---

## 07 · Lava lamp

*Built 2026-10-05 as Bioma's metaball proof of concept, at Akusen's request. Present while the
machine reports a CPU temperature · the processor's heat, drawn as wax.*

A lava lamp heated by the processor. The one place Bioma draws metaballs: PRD §6.5 rejected them
for the shapes of the interface, because a soft union has no outline anyone can predict and a
surface that is pressed needs one. An organism is never pressed, and here the union is the
point — wax melts together where it meets. The silhouette stays inside the glass panel: the
panel is still a rectangle and the blur still follows it.

**Every motion is the temperature.** Wax sits on the heater and warms towards the heater's heat;
once it is as warm as the heater will make it, it lets go, rises, cools as it climbs and sinks
back. How high it climbs is how hot the processor is: 0.2 of the lamp at the start of the scale,
the whole lamp at its end, and hotter wax is also quicker. Below the start nothing warms enough
to leave the bottom, so a cool machine is a still pool that draws no frames.

| Measure | Value | Note |
|---|---|---|
| panel | 200 × 424 | template 1 × 2; bleeds: the wax fills the glass, the rim is drawn over it |
| blobs | 7 | radii 0.07–0.12 of the width; at rest they overlap into one pool on the heater |
| field | Σ (1 − d²/R²)³, R = 2 r | compact: smooth everywhere, a crowd does not swell into one mass |
| scale | `cold` 48 °C · `hot` 90 °C | heat = (T − cold) / (hot − cold); nothing rises below heat 0.16 |
| cap | the caption | the wax never climbs over the figure |

**The wax is translucent.** Its opacity follows the depth inside the merged surface, not the
field's value — the field peaks at every blob's centre and would show the spheres the mass is made
of: about 0.55 at the edge and in the necks between blobs, 0.88 and lighter in the thick of a
mass. A band just inside the edge is lit, brightest where the surface faces up, as the lit border
runs along every cell's top. The heater's light at the foot of the glass is as strong as it is
hot.

**Colour** — the state colours by default (calm, active, alert by heat), like every reading of
load. With `colour: "theme"` the wax and the figure take `Theme.primary`, the light the icons are
lit with, and the heat is said by motion and the heater alone (Akusen, 2026-10-05).

**Figure** — `CPU` in Orbitron label, the temperature below it in the value size, lit with the
wax colour, in the top-left of the cap. `figures: false` hides them.

**Frames** — at the monitor's rate while the wax moves. Thirty a second showed as stutter at once,
and a timer at sixty is not tied to the refresh. Measured on this machine: about 5.6 % of one
core at 165 Hz while moving (0.17 % of the 32-thread total), nothing at rest. The cost is Qt
redrawing the whole organism surface each frame, not the shader.

**Sensor** — `SystemMonitor.cpuTemperature`: k10temp `Tctl` (AMD), zenpower `Tdie`, coretemp
`Package id 0` (Intel), then the thermal zones `x86_pkg_temp`, a CPU zone, `acpitz`.
`vitals.temperature_sensor` overrides the choice with any part of the input file's path.

**Limit cases** — no sensor: the organism is absent; while arranging its blank form says *No
temperature sensor*.

**Options** — `size`, `colour` (`theme`, or absent for state), `cold`, `hot`, `figures`.

**Settings** — the lava lamp's chip opens COLOUR: State · Theme.

**Shader** — `organisms/lava/lava.frag`, compiled by `scripts/shaders` to the committed
`lava.frag.qsb`, so running Bioma never needs `qt6-shadertools`; changing the shader does.

---

## 08 · Cytoplasm

*Built 2026-10-05, from "Nuove idee". Present while any application runs · what each
application costs, as cells pressed together.*

Each running application is a cell — the biological kind — and its heaviest processes are its
lobes: a browser is a body with its content processes melted into its side, Telegram a single
round cell. Lobes of one application fuse; two applications never do — where they meet, each
keeps its own edge and a pixel of glass shows between them. What melts together is what belongs
together, which is the condition on which Bioma draws metaballs at all (see §07).

**Size is memory.** A cell's area is its share of the machine's memory: the panel's area stands
for all of it, so the cytoplasm fills as the memory fills. Past 45 % of the panel the cells are
scaled down together and keep their proportions.

**Motion is processor.** Lobes circle their cell at 0.03 rad/s per percent of one core, at most
3 rad/s — cytoplasmic streaming. An idle application is still; when every application is idle
and every cell has its size, the organism draws no frames. A starting application grows from
nothing where there is most room; a closing one is taken back in, its radius falling to nothing,
and the others close over the space.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 200 | template 2 × 1; bleeds, like the lava lamp |
| cells | 6 at most, the heaviest by memory | `count` |
| lobes | 4 per cell | the three heaviest processes and the rest; a share under 8 % joins the body |
| packing | lobe against lobe | pulled to the centre, pushed apart 2 px; a circle per cell left gaps on lobed sides |
| names | inside cells at least 24 px across | name in Orbitron meta, memory below it at 80 % |

**Wax** — the lava lamp's: translucent, denser and lighter with depth, lit along the top of
every edge — the seams between cells included.

**Colour** — state by the application's processor, 100 % of one core being the top of the scale;
or `colour: "theme"`, the theme's primary.

**Names** — the one shadow on an organism: words over translucent wax of any colour need ground
of their own (Akusen, 2026-10-05), so they carry a close, soft shadow in the theme's background
colour. Not coloured, so not the halo §4 of the style guide forbids. `labels: false` hides them.

**Grouping** — `services/AppLoad.qml`, sampled every `vitals.process_interval` while an organism
holds it. A process belongs to the nearest ancestor that owns a window (Xwayland's pid excluded);
otherwise to its ancestor just below the session; a windowless group holding a process named
after an open application joins it — Steam's helpers, launched under a shell script, join the
Steam window. Bioma's own process is a cell named *Bioma*. Processor is the difference in clock
ticks between two samples, never `ps`'s lifetime average.

**Options** — `size`, `count` (1–6), `colour`, `labels`.

**Settings** — the cytoplasm's chip opens COLOUR (State · Theme) and NAMES.

**Shader** — `organisms/cytoplasm/cytoplasm.frag`, compiled like the lava lamp's.

---

## 09 · Growth rings

*Built 2026-10-06, from "Nuove idee". Present once the record is read · the days spent at this
machine, laid down like a tree's.*

One ring per day, the oldest at the heart and today outermost. A ring is as thick as the hours
that day was active, so a long day is a wide band and a weekend away a thin one; a day not here
leaves no ring, as a tree that does not grow lays down nothing. The disc is always full: the
rings share its radius in proportion, so a fortnight is a few broad bands and a year is grain.

**Today is the cambium** — lit at its edge, and growing a little each minute somebody is here.
It is the only thing that moves, and only while it grows: the canvas is redrawn once per
change, never animated, so the disc costs nothing between minutes.

**Wood, not a target.** Every ring follows one fixed distortion of the trunk, with a small
wobble of its own seeded by its date. Days alternate a shade apart so thin rings stay apart,
and a darker line marks where each day ended — the late wood.

| Measure | Value | Note |
|---|---|---|
| disc | 354 | template 2 × 2: as large as the square leaves above the caption, centred; pith 3, the outermost ring inside the wobble |
| early wood | primary at 16 % / 22 % | alternating; today 34 % |
| late wood | primary at 55 %, 1 px | |
| cambium | primary, 1.8 px | today's edge |
| caption | 14 below | `TODAY 3 H 20 M` lit · `90 DAYS · 474 H` muted |

**Active** is `services/Activity.qml`: neither idle — ext-idle-notify after
`activity.idle_minutes` (5), inhibitors respected, so a film is somebody watching — nor locked.
The minutes before idle was declared are taken back. There was no history to start from (the
journal kept three days), so the record begins when the organism is first placed, and it is only
kept while one exists: `activity.json` beside `wallpaper.json`, minutes by local date, the last
400 days.

**Options** — `size`, `days` (30 · 90 · 365), `figures`.

**Settings** — the rings' chip opens DAYS.

---

## 10 · Osmosis

*Built 2026-10-07, from "Nuove idee". Present while the machine has a network link · the traffic
on it, as water crossing a membrane.*

A membrane across the top is the link; a pool at the bottom is the machine. What arrives buds off
the underside of the membrane and falls into the pool; what leaves buds off the pool's surface and
rises into the membrane. A drop grows out of the water it comes from and is taken into the water
it reaches, where it shrinks in place — carried on into the pool, its own field showed through as
a darker bubble. The lava lamp's metaballs (§07), for the same reason: the union is the point.

**Every drop is traffic.** Drops come each way as often as bytes cross that way, on a logarithmic
scale from 0.4 a second at `quiet` to 6 a second at `ceiling`, at random intervals around that
rate (exponential waits, so never on a beat). A drop crosses in about a second whatever the
traffic: how many cross is what the traffic says, not how fast. Below `quiet` nothing buds — a
machine at rest still trades a few hundred bytes a second — and once the last drop is taken in
the water is still and draws no frames.

| Measure | Value | Note |
|---|---|---|
| panel | 200 × 424 | template 1 × 2; bleeds, like the lava lamp |
| membrane | 6 thick | under the figures, so no drop crosses them; at the top inset without them |
| pool | from 0.8 of the height | |
| drops | radius 0.045–0.07 of the width | 20 in flight at most |
| scale | `quiet` 4 KB/s · `ceiling` 100 000 KB/s | about a gigabit link at the top |
| fall | 2.2 spans/s² | gathering 0.35 s, taken in 0.18 s |

**Water** — the wax shader's field and light with two reservoirs added, thinner than wax: 0.45
at the edge, 0.78 in the thick, lit along the top of every edge. `Theme.primary`: traffic has no
calm or alert, so there is no state colour to say.

**Figures** — `IN` and `OUT` in Orbitron label, each rate beside it in the value size, lit with
the water's colour: B/s, KB/s, MB/s (one decimal under 10). `figures: false` hides them.

**Traffic** — `SystemMonitor.netIn` / `netOut`, bytes per second from `/proc/net/dev` at the
vitals cadence, summed over the machine's own links. Loopback and virtual links (VPN tunnels,
WireGuard, bridges, veth, container and VM interfaces, bonds) are left out by name: each carries
packets a physical link counts already.

**Limit cases** — no link: the organism is absent; while arranging its blank form says *No
network link*.

**Options** — `size`, `quiet`, `ceiling` (both KB/s), `figures`.

**Shader** — `organisms/osmosis/osmosis.frag`, compiled like the lava lamp's.

---

## 11 · Photoperiod

*Built 2026-10-07, from "Nuove idee". Always present · the sky over the weather's place: the
sun's arc and the moon's, the light the day has left, and how much of the moon is lit.*

The sky as one stands in it, facing the sun at noon — south in the northern hemisphere, north in
the southern: the compass runs across (east on the left up here), the altitude up, at one scale
for every season, so a December sun is a low arc and a June sun a tall one. The horizon is a
line; under it a shallow strip holds what has set, pressed — under the horizon is under it, how
far matters less.

**The sun's arc** is the whole of today's path. The part it has travelled is dim, the part ahead
is lit, and the sky under the part ahead is filled faintly: **the light left**, as an area, while
the figure above says it in hours. Under the horizon its path is a faint line, and the sun there
is a ring instead of a disc. **The moon** has its own arc, fainter, in the text's colour, and its
disc is lit as the moon is — the bright limb on the sun's side, the terminator an ellipse,
mirrored south of the equator. When it is near the sun it stands near the sun: that is a new moon.

It moves as the sky does: everything is worked out again once a minute and drawn once, never
animated. Today is the place's **solar day**, from the sun's lowest to its lowest — the clock's
midnight where the clock is right for the place, and still the night where it is not, so the arc
is never cut in daylight. The moon's arc is drawn over a lunar day, fifty minutes longer, so it
closes on itself.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 200 | template 2 × 1; padding 20 |
| place | Spectral 15 / 700 | the weather's place, as geocoded |
| figure | `LIGHT LEFT` Orbitron 11 label · `4 H 12 M` lit, Orbitron 15 / 500 | |
| sky | the height between the rows, 10 below the figure and 8 above the phase | horizon at 0.74 of it, `line`, a hairline |
| margin | 9 across, 9 above the zenith | so the discs at the edges are whole |
| sun's arc | primary, 1.5; travelled at 38 %; under the horizon 1 at 18 % | light left: primary at 10 % |
| sun | disc 6, primary; under the horizon a ring at 50 % | |
| moon's arc | text at 22 %, 1 | above the horizon only |
| moon | disc 7: the dark part text at 10 % with a hairline at 35 %, the lit part text at 90 % | under the horizon at 45 % of that |
| rising, setting | Orbitron 11 muted, under the strip where the arc crosses | `07:29`, `18:54` |
| phase | Spectral 14 muted · Orbitron 11 muted | `Waning crescent  8 %` |
| day | Orbitron 11 muted, right | `DAY 11 H 25 M` |

**The figure** — by day `LIGHT LEFT` and the hours to sunset; by night `SUNRISE IN` and the hours
to sunrise; with no crossing in the next two days, `MIDNIGHT SUN` or `POLAR NIGHT` alone. Sunrise
and sunset are the almanac's: the sun's upper limb on the horizon, refraction included (−0.833°).
**The phase** names the four principal ones for about a day either side of their instant, as a
calendar does, and the other four between them.

**The sky** — `organisms/photoperiod/sky.js`, the low-precision formulas of Meeus' *Astronomical
Algorithms*: the sun to within a minute of its rising, the moon to a fraction of a degree, its
parallax included. Finer than a pixel of the organism. Nothing is asked over the network but the
place: the coordinates are the weather's (§05), and the weather service is held only until it has
them. Times are the machine's clock — the place is where the machine is.

**Limit cases** — no city: blank, the horizon alone, and in the sky, Spectral italic, *Type a city
under Settings → Organisms → Weather → City.* A city nobody could find: the weather's reason.
While it is being looked for: *Looking for the place…*

**Options** — `size`. The city is the weather's, stored once under `weather`; Settings shows the
same CITY field under the photoperiod's chip.

---

## 12 · Vacuole

*Built 2026-10-07, from "Nuove idee". Present while a notification is unread · what was said and
not yet read, stored in a sac.*

Each application is one body in the sac and each of its unread notifications a drop of it. Drops
of one application melt together and two applications never do — the cytoplasm's tissue (§08),
its shader too, for the same reason: what melts together is what belongs together. A chat that
wrote five times is one swollen body; five applications that wrote once are five small ones.

**Unread** (Akusen, 2026-10-07): every notification arrives unread, seen going past or not, and
stays so until it is read —
- closed by the user (the cross, an action) or by its sender (the chat read in the application
  itself): its drop is taken back in;
- or all of them at once, by opening the notification history: looking at the history is reading
  it. Clearing the history reads them too.

Expiring is not reading: a popup that went by on its own leaves its drop. A notification that has
expired no longer exists for its sender, so from then on only the history reads it.

**Motion** is arrival and reading, nothing else: a drop grows in where its body is (a new body
where the sac has most room), and a read drop shrinks into it while the others close over the
space. Between the two the sac is still and draws no frames. With nothing unread there is no
vacuole; while arranging its blank form is the empty sac and *Nothing unread*.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 424 | template 2 × 2; padding 20 |
| sac | 354 | as large as the square leaves above the caption, centred |
| membrane | 1.5, text at 22 % over text at 3 % | |
| drop | radius 0.2 of the sac's inside | four lobes per body, the drops dealt round them |
| fill | 45 % of the sac at most | past it every body shrinks together, proportions kept |
| bodies | six applications, the most unread first | |
| colour | primary; alert while it holds a critical notification | |
| names | Orbitron 11 label over the count | the cytoplasm's ground; a name wider than its body is left out, the count stays |
| caption | 14 below | `UNREAD 7` lit · `SINCE 14:32` muted (the oldest; a date before it when not today) |

**Unread** lives in `services/Notifications.qml` (`unread`, `read(id)`, `readAll()`), in memory
like the history.

**Options** — `size`, `labels` (NAMES in Settings), `figures`.

---

## 13 · Sediment

*Built 2026-10-07, from "Nuove idee". Present while the desktop has recorded a recent file · the
files used lately, laid down in strata.*

Each file is a layer, the newest on top. A layer is as thick as it is young: a file opened a
moment ago is a wide band with its name in it, and as the days pass it is pressed down under what
came after, thinner and thinner, until the oldest are a fine grain at the bottom. The column is
always full — the layers share its height in proportion, as the growth rings share their disc —
and every layer keeps at least 2 px, so the oldest stay countable.

**Weight** — before the column is shared out, a layer weighs `(1 + hours / 6) ^ −0.7`: one for a
file used now, a third for a day ago, a tenth for ten days. A gentler curve laid every file of the
last days down alike, ruled like paper; a steeper one let a file opened a moment ago take half the
column and every other name with it (2026-10-07, tuned on Akusen's own list).

**Motion** — a deposit: something new on top, a file never seen or one used again, settles there
from nothing while the layers under it are pressed together (`open` × 3, flat curve). A file used
again does not rise through the strata from where it lay: it is laid down anew. Age presses the
strata too, slowly — they are measured again every ten minutes and drawn once, never animated for
it.

| Measure | Value | Note |
|---|---|---|
| panel | 424 × 424 | template 2 × 2; padding 20 |
| column | the square less the caption | |
| layers | primary at 13 % / 19 %, the newest 30 % | alternating |
| bedding plane | primary at 45 %, 1 px | each bed gently uneven, by its own seed; flatter the thinner it is (≤ 3 px, ≤ 12 % of the layer) |
| surface | primary, 1.5 px | the top of the newest |
| name | Spectral 13, text, middle elided | in layers ≥ 22 px; age `2 H` · `3 D` Orbitron 11 muted at the right |
| caption | 14 below | `TODAY 3` lit (files used since midnight) · `16 FILES · SINCE 28 SEP` muted |

**The list** — `services/Recent.qml` reads `recently-used.xbel` (freedesktop's list, written by
GTK applications, the file chooser portal and the file manager), watched rather than polled and
only while an organism holds it. Folders are left out — places, not work — and so is what no longer
exists, asked of the disk once per change of the list. Applications that do not record there
(most Qt and Electron ones) are not in it.

**Limit cases** — nothing recorded: absent; while arranging, *No recent files*.

**Options** — `size`, `depth` (8 · 16 · 32, DEPTH in Settings), `names` (NAMES), `figures`.

---

## Configuration

```json
"organisms": [
  { "type": "clock",    "monitor": "DP-1", "col": 0, "row": 0 },
  { "type": "calendar", "monitor": "DP-1", "col": 0, "row": 1 },
  { "type": "vitals",   "monitor": "DP-1", "col": 2, "row": 0, "layout": "row" },
  { "type": "media",    "monitor": "DP-1", "col": 2, "row": 1 },
  { "type": "weather",  "monitor": "HDMI-A-1", "col": 4, "row": 2, "size": "comfortable" },
  { "type": "note",     "monitor": "DP-1", "col": 4, "row": 0,
    "file": "~/Documents/Vault/Next.md", "height": "medium" },
  { "type": "lava",     "monitor": "HDMI-A-1", "col": 0, "row": 1, "colour": "theme" },
  { "type": "cytoplasm", "monitor": "HDMI-A-1", "col": 0, "row": 0, "labels": false },
  { "type": "rings",    "monitor": "DP-1", "col": 6, "row": 0, "days": 90 },
  { "type": "osmosis",  "monitor": "DP-1", "col": 6, "row": 2, "quiet": 8 },
  { "type": "photoperiod", "monitor": "DP-1", "col": 4, "row": 3 },
  { "type": "vacuole",  "monitor": "HDMI-A-1", "col": 2, "row": 0 },
  { "type": "sediment", "monitor": "HDMI-A-1", "col": 4, "row": 0, "depth": 32 }
],
"weather": { "city": "Milan" }   // place, latitude, longitude, located_for are written back;
                                 // the photoperiod reads the same place
"arrange": { "grid": 2 }         // squares per module: 1, 2, 4 or 8 — written on leaving Arrange
```

The base layer ships `"organisms": []`: nobody's desktop gains furniture by updating. Adding an
organism costs one block, never a structural change.

## Open

- **Bare or glass.** This draft gives every organism the glass panel. A bare variant — text
  straight on the wallpaper — would read as part of the wallpaper and suits the clock most of
  all, but legibility on a light or busy picture then depends on something the style guide
  forbids (glow, halos). Kept as a question, not as an option.

## Settled on the first build

- **niri's overview** (2026-10-04): the Bottom layer is drawn inside each workspace, like the
  wallpaper, so the organisms zoom out with every workspace and are on all of them. Nothing to
  hide.
- **Blur**: the glass blurs the wallpaper under it through `ext-background-effect`; the
  surface's namespace `bioma-organisms` is in niri's `xray false` rule with the others.
