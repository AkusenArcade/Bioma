# Bioma — organisms

*Approved 2026-10-04, media redrawn at Akusen's request. Built: the structure, arranging, clock, media, vitals, calendar, weather. Still to come: the Settings section.*

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
- Conditional presence where it has a meaning: media is absent with nothing playing, weather is
  absent when there is no reading young enough to trust.
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
- **Position** is stored as the organism's centre in **fractions of the free area** (0–1 on each
  axis), so it survives a resolution, scale or membrane change and stays in the same part of
  the screen.
- **Overlap** is not prevented, as with floating tissues — but snapping makes the 24 px gap the
  natural distance, so it only happens on purpose.

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
  radius 20.
- Each organism wears a **dashed primary outline** 8 px outside its panel, and its name and
  position — `CLOCK  X 0.31 · Y 0.51`, Orbitron 11 — above its top-left corner. Hover brightens
  the outline; press and drag moves it. Drag is not scaled, not tilted: the panel moves whole,
  and where the press landed inside it stays under the pointer.
- **Snapping** (magnetic, 8 px reach): the edges of the free area; the screen's centre lines;
  the edges and centre lines of the other organisms, and the 24 px gap beside them. A guide line
  in primary, 1.3 px, shows the snap that holds.
- An organism dropped onto **another monitor** moves there; its position is recomputed in that
  monitor's free area. It leaves the first screen from where it was let go and grows on the
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

Settings → Cells gets a section **Organisms**, after the membranes:

- one row per monitor, its organisms as chips (`cellchip`), a dashed **+** chip to add one —
  the added organism appears at the centre of the free area and the mode enters *Arrange*;
- a chip's × removes it (the organism shrinks into its centre on the desktop);
- *Arrange* — the button that enters the mode;
- per organism, the options below.

---

## 01 · Clock

*Always present · the time, large.*

The time in Spectral, the clock cell's face beside it, the date under them in words. The face
is the cell's own — the hour filling (or, while a timer runs, what is left of it emptying) and
the disc round the rim where the second hand is, moving continuously. Without it the organism
read as unfinished (Akusen, 2026-10-04); it is the same live value the cell shows.

| Measure | Value | Note |
|---|---|---|
| panel | 340 × 168 | padding 20 |
| time | Spectral 72 / 500 | tabular figures, primary gradient fill |
| date | Spectral 19 / 400 | `Sunday 4 October`, text muted |
| face | 62 | the cell's `Dial`, the size of the vitals organism's rings, 16 right of the figures |
| gap time → date | 4 | |
| format | the clock cell's | 24 h / 12 h, read from the clock cell's option |

**Limit cases** — 12 h: `9:41` with `PM` in Orbitron 15 beside it, baseline-aligned. A long date
(`Wednesday 30 September`): the panel is as wide as its content, never ellipsed.

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
| panel | 420 × 420 | square, like the art; radius 20 |
| cover | the whole panel | edge to edge, cropped to the panel's radius on the **image**, never by clipping the panel — the rim is drawn over it. Non-square art (a video thumbnail) is cropped centred |
| scrim | over the cover | the theme's `background`, transparent down to 36 % of the height, 0.80 at 60 %, 0.92 at the bottom — the words are read on the shell's own colour whatever the picture is |
| band | 380 × 96 | 48 bars of 4 px, 8 px pitch, symmetric from the centre line, primary gradient over the band's height; it rises out of the picture where the scrim begins |
| title | Spectral 22 / 700 | one line, ellipsis; 16 under the band |
| artist | Spectral 16 / 400 | text muted, one line, ellipsis |
| album | Spectral 13 / 400 | italic, text faint; omitted when absent |
| progress | 3 px | primary, 7 px node at the head; times in Orbitron 11 tabular under it; 14 under the words |
| padding | 20 | the content sits on the bottom edge |

**Present** while the source is Playing or Paused with a track. **Absent** when stopped or no
source has a track. Paused: the band lies still as a row of dots (there is no sound) and the
progress holds — the organism stays, because a paused track is still the track.

**The band runs only while it can be seen**: while this screen's active workspace has no window
(the desktop is showing), or while the organisms are being arranged. Under the windows it would
cost a capture process and sixty frames a second for nobody, so it lies still there.
`Sinestesia.hold(owner, on)` keeps the capture running while anything holds it — a cell on
screen, an organism on a showing desktop.

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
| panel | 4 columns × 96 + 3 × 16 gap + padding = 472 × 176 | 3 columns without a battery: 360 × 176. A column widens to its longest line (`6.7 / 30.5 GB`) rather than cutting a figure short |
| indicator | 62 | 1.5 px ring, as in the pods |
| label | Orbitron 15 / 500, +0.06 em | `CPU` `RAM` `GPU` `BAT` |
| value | Orbitron 20 / 500 | state gradient fill (calm / active / alert) |
| secondary | Orbitron 13 / 400 | `4.8 GHz`, `14 / 32 GB`, `1.9 GHz`, `2 h 10` |

Battery appears only on a machine that has one, as in the cell.

**Options** — `size`, `layout` (row / 2 × 2 square: 232 × 316).

## 04 · Calendar

*Always present · this month.*

The clock cell's month, alone and read-only: no arrows, no navigation — a calendar on the wall,
not a planner. Today is the only lit day.

| Measure | Value | Note |
|---|---|---|
| panel | 299 × 302 | padding 20: 7 × 37 wide, header + weekdays + 6 × 34 tall |
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

*Present with a reading under two hours old · now, and the next hours.*

The weather where Akusen is: the city from Settings, geocoded once by Open-Meteo, then the
forecast every 30 minutes through the proxy when one is on. No key, metric units.

| Measure | Value | Note |
|---|---|---|
| panel | 340 × 196 | padding 20 |
| city | Spectral 15 / 700 | the name as geocoded |
| condition glyph | 44 | primary gradient, new weather glyphs (below) |
| temperature | Orbitron 40 / 500 | primary gradient, `18°` |
| condition | Spectral 15 / 400 | `Light rain`, text muted |
| high / low | Orbitron 13 | `24° · 12°`, text muted |
| hours well | 300 × 64, radius 10 | next 5 hours: Orbitron 11 hour, 20 glyph, Orbitron 13 temperature |

The temperature is **not** a state: it measures the weather, not the machine, so it is primary
and never calm, active or alert — the same reason a timezone dial never changes colour.

**Glyphs** — eight new icons for `docs/design/icons/`, built to the icon rules (grid 24, stroke
1.5, round caps, no fills): `weather-clear`, `weather-clear-night`, `weather-partly`,
`weather-cloudy`, `weather-fog`, `weather-rain`, `weather-snow`, `weather-storm`. Open-Meteo's
WMO codes map onto them.

**Limit cases** — offline: the last reading stays until it is two hours old, then the organism
leaves. No city set: absent, and Settings says why under the field. A city that geocodes to
nothing: the field's error, as every field's — outline in alert, reason under it.

**Options** — `size`, `city` (shared by every weather organism, stored once under `weather`).

---

## Configuration

```json
"organisms": [
  { "type": "clock",    "monitor": "DP-1", "x": 0.18, "y": 0.22 },
  { "type": "calendar", "monitor": "DP-1", "x": 0.18, "y": 0.62 },
  { "type": "vitals",   "monitor": "DP-1", "x": 0.80, "y": 0.80, "layout": "row" },
  { "type": "media",    "monitor": "DP-1", "x": 0.80, "y": 0.25 },
  { "type": "weather",  "monitor": "HDMI-A-1", "x": 0.5, "y": 0.5, "size": "comfortable" }
],
"weather": { "city": "Milan" }   // place, latitude, longitude, located_for are written back
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
