# Bioma — the thirteen cells

One section per cell, in PRD order. Each gives the contracted state, the limit cases, the
expanded state where there is one, behaviour, measurements, and what was decided or left open.
Cross-cutting rules are in `STYLE_GUIDE.md` and are assumed here, not repeated.

Three decisions close open questions from the PRD **against** what the PRD suggested. They are
marked, so a later reading does not mistake them for oversights: workspaces list their own
monitor (§9.3), the theme cell animates only on theme change (§9.7), do-not-disturb lives in
the notification history (§9.10).

---

## 01 · Window title

*Conditional · elastic width · no expanded state.*

The cell that says which window has focus. One of the two exceptions to the silence rule: the
text is always there, because without a name a window cannot be recognised. Lives in the
floating centre tissue, next to the clock.

**At rest** — resolved application icon in a dark circle with a thin outline, then the title in
Spectral 14.5.

**Limit cases** — long title: ellipsis at the limit, never wrapping, never shrunk. Unresolved
icon: neutral fallback glyph, never another application's logo. No focused window: the cell
disappears and the tissue closes symmetrically.

**Behaviour**
- Conditional visibility: it exists only while a window has focus.
- Elastic width with a declared minimum and a cap as a percentage of screen width. The minimum
  stops a title change from making the tissue dance.
- Click centres the window on screen through the niri action.
- Title changes: browsers rewrite on every tab. The text must be delayed and cross-faded, not
  swapped abruptly.

**Why** — the title is **human language**, so Spectral: it is the choice that gives the shell
its identity, because at rest this is one of the few visible strings. The icon sits in a dark
circle with a thin outline: application icons are third-party and stylistically unrelated, and
the circle makes them a family. The icon is the only element that does not follow the palette,
because it belongs to the application; the fallback does follow it. No expanded state, because
expanding this cell would add nothing the window does not already say.

| Measure | Value | Note |
|---|---|---|
| cell height | 40 px | normal scale, like every contracted cell |
| icon | 30 px | circle, 1 px outline |
| min width | 186 px | stabiliser |
| max width | 28% of screen | then ellipsis |
| title change | 180 ms debounce | then cross-fade |

**Open** — the fallback glyph. The one in the design is a neutral placeholder; the real one
will be drawn with the icon series, from the mark's parameters.

---

## 02 · Vitals

*Always or conditional · animated indicators · click sorts.*

The machine's vital signs. At rest they are only shapes that move: no digits, ever. Expanded it
becomes a small process manager, where the indicators double as the sort control. The
composition changes with the hardware: three indicators on a desktop, four on a laptop.

**At rest** — CPU ring with a beating dot, RAM ring filling with liquid, GPU ring with an
orbiting satellite, battery where one exists. 26 px each, 10 px apart.

**Expanded, desktop (three domains)** — three horizontal pods 236 × 108 in a column, each hung
on its own thread, and a 372 px list panel to the right. Pod bottoms align with the panel.

**Expanded, laptop (four domains)** — the pods become **vertical capsules** 120 × 178 in a 2 × 2
matrix, and the list gets one more row. With four domains, stretching the column would turn the
cell into a tall strip.

**Behaviour**
- Click an indicator: sorts the list by that domain. The dot beside the label says which sort is
  active, repeated in words in the search field.
- **Sorting stays a user choice**: it does not change by itself, not even when a domain goes
  critical.
- Closing a process: the row turns into the confirmation, with Cancel and Close. No dialog
  arriving from outside.
- Visibility: always, or conditional on a vital going critical; either way invokable by
  shortcut.
- The search field is the launcher's: lens in the primary, Spectral, no well.

**Why** — the battery fills **horizontally**, left to right, precisely so it cannot be confused
with the RAM liquid, which rises from the bottom. At 100% the RAM ring becomes a full disc
pulsing in the alert colour — never a dot inside a ring, or it would look like a critical CPU
exactly when the two need telling apart.

| Measure | Value | Note |
|---|---|---|
| contracted indicators | 26 px | 10 px pitch, in a 40 px cell |
| horizontal pod | 236 × 108 px | three domains, 24 px pitch |
| vertical pod | 120 × 178 px | four domains, 2 × 2 matrix |
| indicator in pod | 62 / 56 px | horizontal / vertical, 1.5 px ring |
| list panel | 372 × 372 / 376 px | height matches the pod column |
| search field | 40 px | lens 16 in primary, Spectral 14.5 |
| process row | 30 px | icon 20, name Spectral 13, value Orbitron 13 |
| threads | 24 px | pod → pod and pod → panel, nodes at both ends |
| cascade | 250 ms | header → thread → panel → pods at 16 ms |

---

## 03 · Workspaces

*Always visible · opens downward · one per monitor.*

The active workspace, and on demand the list of the ones on its screen. Lives in the left
tissue and opens downward, aligned left.

**At rest** — the two-stacked-bars icon and the workspace name in Spectral; if the workspace has
no name, its number in Orbitron. Width changes only on workspace change.

**Limit cases** — unnamed workspace: the number, cell at its minimum. Long name: ellipsis at the
limit. Shortcut change: the bars **shift one step** in the direction of the jump, 180 ms.

**Expanded** — a rectangular panel: round buttons with the numbers on the left, names in
Spectral on the right. Five rows visible, then it scrolls with the active workspace always
inside. The well clips the scroll, never the panel.

**Behaviour**
- Click the cell opens and closes the list; click a row jumps and closes immediately — the
  action is done, staying open would be noise.
- Wheel on the cell: previous and next workspace without opening anything.
- Shortcut change: even without touching the cell, the icon shifts one step. It is the
  confirmation that the command arrived, for someone changing workspace from the keyboard.
- One cell per monitor, each listing its own screen. No grouping and no monitor labels.

**Why** — buttons left, names right: the button column reads at a glance — how many and where
you are — and the names stay outside, where they can be long without deforming anything. The
number is machine and sits in the button in Orbitron; the name is human and sits beside it in
Spectral: two languages, kept apart in space too. A workspace with no name shows its focused
window in plain text — repeating "Workspace 4" next to the button with a 4 adds nothing. The
trailing empty workspace, which niri always keeps, has a dashed button: it is a place, not a
content. The icon does **not** count workspaces: how many there are is what the list is for, and
an indicator repeating in miniature something already legible elsewhere adds noise.

| Measure | Value | Note |
|---|---|---|
| contracted cell | 40 px | min 96, max 220 px with ellipsis |
| icon | 16 px | two bars, 1.4 stroke, primary gradient |
| icon shift | 180 ms | one step of 9.5 units, opening curve |
| panel | 236 px | padding 10, radius 20 |
| well | radius 10 | concentric; it clips the scroll |
| row | 44 px | button 36, name Spectral 14 at 12 px from the button |
| visible rows | 5 | panel 240 px tall, then scrolls |
| button states | 3 | active (filled), occupied (line ring), empty (dashed ring) |
| scrollbar | 3 px | inside the well, 4 px from the edge |
| thread | 24 px | cell centre to panel top edge |

**Decided, against PRD §9.3** — one cell per monitor with its own workspaces. Grouping every
screen into one cell would force labelling the groups, and a label says worse what position
already says.

---

## 04 · Sinestesia

*Conditional on audio signal · two independent inputs · identity.*

The sound leaving the machine, made visible, and when there is a track, the track too. The one
cell no other shell has, and the only one where motion does not measure a load: it measures the
sound itself. The bars are small **vertical capsules** — the mark's shape, put in a row. Lives
in the floating centre tissue; when silence makes it disappear, the tissue redistributes
symmetrically.

**At rest** — the band on the left, the track in Spectral. The band is symmetrical **from the
centre**, because filling from the bottom already means memory.

**Limit cases** — no track (browser video, a game): the band alone, cell narrowed. Long title:
ellipsis, scrolling only on hover. Silence past the dwell: the cell disappears — never between
two tracks.

**Expanded** — the visualiser capsule on top, the track panel hung underneath: cover, title,
progress, transport. The player selector appears only with more than one source.

**Expanded without metadata** — no MPRIS: the panel does not exist, it is not empty. It opens
and closes by itself as a track appears or goes, without the cell closing.

**Behaviour**
- Visibility on the **audio signal**, not on playback. Hysteresis and a few seconds of dwell are
  required, or the silence between two tracks makes it flicker.
- Click opens the track panel. Wheel does nothing — volume is another cell, and confusing them
  here would be easy.
- Track change: the title cross-fades and the tissue settles with the window title's delay. On
  hover a long title scrolls; at rest it never scrolls.
- More sources: the selector appears only when there is more than one, and changes **only** the
  panel.
- Reduced motion: the band stops oscillating and becomes a single bar following overall
  loudness. It does not stop completely: that would be indistinguishable from silence.

**Why** — **two independent inputs.** The band shows everything leaving the machine; the panel
shows the chosen MPRIS source. Changing player does not touch the band: if they were one thing,
choosing Spotify would switch off the browser video. The panel is hung **from** the band, not
the other way round: sound is always there, a track only sometimes, and the thread says which of
the two holds the other.

| Measure | Value | Note |
|---|---|---|
| contracted band | 81 × 22 px | 14 bars of 3 px, 6 px pitch |
| expanded band | 268 × 52 px | 34 bars of 4 px, 8 px pitch |
| visualiser capsule | 372 × 88 px | full pill, band centred |
| track panel | 372 × 164 px | padding 10, radius 20 |
| cover | 88 px | radius 10, concentric |
| transport | 44 / 36 px | filled play in the centre, ringed skips, 14 px pitch |
| progress | 3 px | 7 px node at the head, times in Orbitron 11 tabular |
| threads | 24 px | membrane → capsule → panel, in a column |
| exit dwell | 4 s | after the last signal above threshold, with hysteresis on the threshold |

**Open** — the band's effects are **not decided here**: they are defined against the Sinestesia
code, which has already done that work against real audio. This spec fixes the form, not the
behaviour. Still to settle: band count and frequency split, and what to do on a narrow screen —
drop bars from the sides or pack them closer.

---

## 05 · Volume

*A control, not a measurement · always or invoked · floating tissue.*

The audio level and who is producing it. The first **control** in the catalogue, not an
indicator: the wheel moves it, so the colour stays primary for the whole travel.

**At rest** — the dial alone: track, primary arc, node at the head. The arc follows the wheel in
real time.

**Limit cases** — muted: the arc disappears and a cut remains across the track — no red, it is
not a fault. Above 100%: the excess restarts as a thinner arc further out, still primary. At
zero: the arc is closed and the node is back at the top; it differs from muted because there is
no cut.

**Expanded** — a capsule with dial, figure and main slider; below, output, input and
per-application volume, one well each. Each application row has its own **mute**: the same cut
ring as the cell, at a smaller size. The slider stays where it was, dimmed, because muting does
not zero it.

**Invoked** — the same cell as a floating tissue centred on screen. Not a second
implementation: what changes is where it is born, not what it does. Without a membrane there is
no thread; the tissue wraps it and the shadow is deeper because it floats.

**Behaviour**
- Wheel on the cell raises and lowers, with the arc responding immediately. The only cell where
  the wheel is the main interaction.
- Click opens devices and applications. Middle click mutes.
- One slider and one mute per application: PipeWire nodes appear and disappear constantly, so
  rows are added and removed without the panel jumping — the well height is fixed, the scroll is
  inside.
- If it stays always visible, give it a tissue of its own: it is intermittent by nature and
  would make its neighbours dance on every turn of the wheel.

**Why** — a dial, not a beating ring: form says the domain, and volume is a travel with a start
and an end, so an arc with a node at the head — and the node is the same sign as the threads,
where something attaches. **Muted is not zero**: zero is a position in the travel, muted is a
state that suspends it, which is why muted has an extra sign.

| Measure | Value | Note |
|---|---|---|
| contracted dial | 26 px | 3 px track, 3.4 px node |
| expanded dial | 56 px | 1.5 px track, 4 px node |
| capsule | 372 × 88 px | dial, 20/500 figure, 168 px slider |
| slider | 3 px | 14 px handle, primary gradient fill |
| device row | 38 px | 16 px dot, name in Spectral 13.5 |
| per-app slider | 80 px | deliberately short: a fine adjustment, not the main one |
| per-app mute | 22 px | empty ring when audible, cut ring in primary when muted |
| over 100% arc | r 30 px | 0.7× stroke, same gradient |

**Open** — with visibility set to invoked, turning the wheel gives no feedback because the cell
is not there. A system-wide OSD would fill this, but it concerns brightness and others too: it
is a system decision, not a property of this cell, and stays deferred. Prisma's OSD components
exist and port when decided.

---

## 06 · Utility

*Icon only · no state · generates another cell.*

Screenshots, regions, OCR and recording. The first purely functional cell: at rest it has
nothing to represent, so it shows only its icon. It is also the only one that **generates
another**: a recording has a duration, and what has a duration needs a cell to say so.

**At rest** — the icon alone. No number, no state colour.

**Expanded** — what is captured on top (Image, Video, Text), where it is captured from below
(Screen, Window, Region). Two independent choices, never a list of six.

**While recording** — a separate conditional cell with the elapsed time and a stop control. The
dot pulses in the alert colour, because here the machine really is measuring something: it is
writing to disk, and that must be visible from across the room.

**On stop** — save or discard. The confirmation grows from the cell itself, like closing a
process, and the video sits in a temporary directory until it is saved.

**Behaviour**
- Two independent choices; the last pair used stays selected.
- The selection surface is **Bioma's own**, not `slurp`: it reuses the full-screen input
  surface, so the visual identity holds across the whole desktop. Capture stays with `grim` and
  the recorder.
- Image: the result goes to the clipboard **and** the screenshots folder. Text: recognises the
  region, text to the clipboard.
- Video: no audio, H.264 High Profile, 60 fps, MP4 container.
- Also invokable: same implementation, two placements.

**Why** — **recording is a cell, not a state of this one.** The capture cell stays put and
available while recording; if it changed shape you could no longer take a screenshot during a
recording. General rule, not just here: what has a duration deserves its own cell, because it
must be stoppable without going through whoever started it.

| Measure | Value | Note |
|---|---|---|
| contracted cell | 40 px | icon 20 px, no text |
| panel | 372 × 154 px | segmented 32 px, buttons 112 × 92 px |
| mode button | 112 × 92 px | radius 20, icon 28, label 11/500 |
| recording cell | 40 px | dot 9 px, time in Orbitron 14 tabular |
| confirmation | 40 px | grows in width from the cell; not a window |

See `IMPLEMENTATION.md` → Capture for even dimensions, physical pixels and window geometry.

---

## 07 · Theme

*Invoked · theme switcher · immediate effect.*

The wallpaper and the palette derived from it. At rest it is not an icon that *represents* the
theme: it is the palette itself, in a row inside a pill. And it does **not** animate except when
the theme changes.

**At rest** — the seven roles of the current theme, in view. Change theme and the chips replace
each other in 250 ms, one at a time, 16 ms apart.

**Expanded** — the wallpaper carousel on top: the current one at full light in the centre, the
neighbours dimmed at the sides. Below, two capsules joined by a thread: the palette **source**
(matugen | Bioma) and **what comes out of it** — the seven chips and a dropdown. With matugen
the dropdown picks the calculation method (content, tonal spot, fruit salad…); with Bioma it
picks the preset theme by name.

**Immediate effect** — no preview and no "apply": choosing a theme **retints the shell while you
watch it**, in 250 ms, cell by cell.

**Behaviour**
- The carousel scrolls with the wheel or the arrows; the choice is immediate.
- The wallpaper is "which image and how": fill, fit, **span** across monitors, or one per
  monitor. Span scales to the total bounding box and clips per output.
- Bioma themes are **data files**, one per theme: add one without touching the shell, and it
  appears in the dropdown.
- Visibility: invoked, optionally always present.

**Why** — the contracted cell **is** the data: change the wallpaper and the cell changes, and
that is visible without opening anything. The chips are vertical pills, like the Sinestesia bars
and like the mark. Wallpapers are looked at **inside pills**, which also solves the carousel
practically: the neighbours are half-seen without fake edge fades. Source and result in two
separate capsules joined by a thread: they are two different questions — *where it comes from*
and *which one* — and the thread says which is first. A dropdown rather than a row of swatches:
themes have a name, and the name is what is remembered. **No preview panel**: a preview is a
promise; here the shell *is* the preview, and it is the only honest way to judge a theme — on
every cell at once.

| Measure | Value | Note |
|---|---|---|
| contracted chip | 10 × 22 px | radius 5, 13 px pitch, seven roles → 88 px |
| carousel | 560 px | radius 20, padding 10, 10 px inner pitch |
| current wallpaper | 320 × 140 px | radius 10, concentric · neighbours 100 px at 40% |
| capsules below | 268 × 96 px | pill: under the 110 px ceiling the cap does not disturb the content |
| dropdown | 30 px | name in Orbitron 12, chevron 9 |
| threads | 24 px | carousel → source, source → palette |
| theme change | 250 ms | whole shell at once, chips 16 ms apart |

**Decided, against PRD §9.7** — the cell animates only on theme change. Continuous motion with
no data driving it would be the first exception to a rule that costs effort elsewhere.
**Also decided** — matugen's method is a user choice, not a constant: content and tonal spot from
the same wallpaper give different desktops, and hiding it would imply the derived palette is the
only possible one.

---

## 08 · Session

*Avatar · five commands · three ask for confirmation.*

Who is logged in and how to leave. The smallest cell in the catalogue and the most delicate: it
holds the only actions that can lose work.

**At rest** — the avatar only, no name. If no avatar is set, the silhouette remains — never an
initial in a coloured circle.

**Expanded** — large avatar with the mark to change it, name in Spectral and login in Orbitron;
below, the five commands in increasing order of gravity, each with its number on the right.

**Confirmation** — the row itself becomes the question. No dialog arriving from outside, and red
appears only here, on the button that performs the action.

**Behaviour**
- Order of gravity: lock, suspend, restart, shut down, log out.
- Only shut down, restart and log out ask — the ones that close programs. Lock and suspend undo
  themselves with a movement of the mouse: asking would be noise.
- Numbers 1 to 5 run the matching command while the cell is open. Whoever opens this cell is
  often already using the keyboard, and the second time round there is nothing left to read.
- Lock is delegated to an external lock screen, for now.
- Changing the avatar opens the system file picker. It is the only action in the cell that is
  not about the session but about identity, which is why it sits on the avatar.

**Why** — the labels are in Orbitron: they are commands, not human language; the person's name
is in Spectral. Red only on the confirmation: colouring "shut down" red all the time would make
it invisible exactly when it matters. The confirmation grows from the row that asked for it,
like closing a process in Vitals and like saving a recording — three different cells, one
grammar for "are you sure?".

| Measure | Value | Note |
|---|---|---|
| contracted avatar | 30 px | inside a 40 px cell, like the window title icon |
| expanded avatar | 88 px | 26 px edit mark at the bottom right |
| capsule | 300 × 108 px | full pill, avatar flush with the padding |
| command panel | 300 px | five rows of 44, radius 20 |
| command row | 44 px | icon 20, label Orbitron 13/500 uppercase, key on the right |
| key | 11 px | Orbitron 11 in a 1 px box, radius 6, tabular figures |
| confirmation | 44 px | radius 22, alert outline, two 26 px buttons |

**Decided** — confirm only where something is lost. Confirming everything teaches people to
press twice without reading, which is the fastest way to make the confirmation that matters
useless.

---

## 09 · Dock

*No expanded state · elastic width · lives on the membrane.*

Pinned and running applications, separated by a divider. It is **one cell**, not a tissue: the
row of icons is its content, the way digits are the clock's content. It does not open, because
everything it has to say it already says.

**At rest** — pinned on the left, running on the right of the divider. The primary ring on the
icon means running.

**Limit cases** — no running application: the divider disappears; a line that does not separate
two groups is decoration. Hover: the name appears above in Spectral, one at a time. Too many
windows: only the running group scrolls, the pinned stay put — icons never shrink.

**Behaviour**
- Click brings to front, or launches. Middle click: new instance. Drag reorders the pinned.
- Several windows of the same application: one icon, and the click cycles through its windows.
  The ring stays one: it says "running", not how many times.
- **Pinned applications are optional.** With none pinned, only the running group remains and the
  divider never appears: the dock becomes a window list, which is a legitimate way to use it.
- With **conditional visibility**, the cell disappears when there is neither an open window nor
  a pinned application — that is, when it would have nothing to show. With always-on visibility
  it stays at its minimum, empty.
- **Auto-hide is not its own.** It belongs to the membrane: if that hides, the dock hides with
  the whole edge.

**Why** — one cell, not a tissue of cells: if every application were a cell, the dock would have
ten glowing outlines in a row and the membrane would become a keyboard. **The ring instead of a
dot**: a dot under the icon steals height and forces every icon upward, leaving the dock with a
row of icons off-centre compared to every other cell. The ring sits **inside** the footprint and
moves nothing. Flat primary, not the gradient: it is a thin state line, not a surface, and
keeping them distinct stops a running icon from looking like a cell inside a cell.

| Measure | Value | Note |
|---|---|---|
| cell | 40 px | like every contracted cell, padding 12 px |
| icon | 28 px | dark circle with outline, like the window title icon |
| running ring | 1.5 px | icon outline in flat primary, no extra footprint |
| icon pitch | 10 px | divider 1 × 22 px with 6 px each side |
| hover label | 26 px | dark pill above the icon, Spectral 13 |

**Decided** — the running group scrolls, not the whole dock. The pinned are the fixed point: if
they scrolled too, the one thing that always sits in the same place would stop doing so exactly
when there are many windows.

---

## 10 · Notifications

*Conditional on event · capped queue · hover suspends.*

It appears when something happens and leaves by itself. The only cell where **hover is a state**
and not a courtesy: the actions live there, so "interaction suspends disappearance" is not
optional here — it is what stops a notification with two buttons from vanishing while you decide
which to press.

**At rest** — icon and title only, in Spectral. Body and actions do not appear until the pointer
comes near.

**Limit cases** — critical urgency: outline in the alert colour, and it does not expire on its
own. Past the queue cap: the cell becomes a count and defers to the history. Dwell expired: the
cell disappears and the tissue closes — the timer resumes where it stopped, not from the start.

**On hover** — application in Orbitron, title and body in Spectral, and the actions the
notification carries. While the pointer is there, time does not run.

**Expanded** — history, grouped by application, most recent first. **Do not disturb** lives
here.

**Behaviour**
- Dwell by urgency: low 4 s, normal 8 s, critical never — as the freedesktop convention
  requires.
- Hover suspends disappearance, and on exit the time **resumes where it stopped**. If it
  restarted, a distracted hover would keep the notification alive indefinitely.
- Capped queue: close notifications queue, but past the cap — twenty in ten seconds, that is, a
  system update — they collapse into a count. Without a cap the cell would be occupied for
  minutes.
- Critical notifications do not block the queue: one that never expires sits on top, but the
  others keep scrolling past it.
- Click opens the history. Actions are pressed on hover, without opening anything.

**Why** — only the title at rest: the same exception as the window title, since without a line
of text a notification is nothing. The body stays outside, or the membrane becomes a reading
panel. **The outline for urgency, not the fill**: a red fill would make the text unreadable and
the shell look broken; the outline is already where Bioma puts light. The count is in Orbitron
and the title in Spectral: "14 notifications" is a machine measurement, not someone's sentence.
The history groups by application because people come back looking for "that browser thing", not
"that 14:32 thing".

| Measure | Value | Note |
|---|---|---|
| contracted cell | 40 px | min 220, max 300 px with ellipsis |
| hover panel | 340 px | padding 14 × 16, radius 20 |
| body | 3 lines | Spectral 13.5/19, then ellipsis: the rest is in the history |
| actions | 26 px | at most three; beyond that, the first two and the rest in the history |
| dwell | 4 / 8 / ∞ s | low, normal, critical |
| queue cap | 20 in 10 s | past it: count and deferral to the history |
| history row | 38 px | title in Spectral, relative time in Orbitron 11 |

**Decided, against PRD §9.10** — do not disturb lives in the history, not in settings. People
look for it when notifications are bothering them, which is when they are looking at this cell;
putting it in settings means sending them elsewhere at the worst moment. Settings may carry the
same switch, but home is here.

---

## 11 · Connectivity

*Composes itself · disappears entirely · asks for focus.*

Ethernet, Wi-Fi and wireless devices. The only cell that **composes itself**: one glyph per
active connection, so its width says how many there are without writing a number. With no
connection it does not shrink — it disappears.

**At rest** — one glyph per active connection. No wireless device, no wireless glyph; the same
for the others. The cell never shows what is switched off.

**Limit cases** — Wi-Fi only: the cell shrinks to its minimum and stays there. Two connections:
one more glyph, width growing in 250 ms like an opening. No connection: the cell is gone and the
tissue closes on its neighbours — a struck-through icon would say something is broken.

**Expanded** — one well per family, each with its own switch. Names in Spectral, state in
Orbitron, strength in bars that are never state-coloured.

**Password** — the network row opens into a field: primary outline and caret say the keyboard
has been borrowed here, and that it will be given back.

**Wrong password** — the outline turns to the alert colour and the reason appears under the
field. The text stays, the focus stays, no dialog arrives.

**Behaviour**
- One glyph per active connection; the cell disappears with none. That is a condition, not an
  error state: if you need to know you are offline, the application trying will say so.
- Elastic width with a minimum. It changes less often than the window title, but when it changes
  it is a hard jump: the minimum stabilises it.
- The password field takes focus and gives it back on close. It is the only point in the system
  where a cell anchored to an edge, and a conditional one at that, needs the keyboard.
- **Devices have no selection.** More than one can stay connected at a time, so each row stands
  alone: clicking connects or disconnects that one. The lit glyph means connected, the dim one
  paired but idle.
- Switches turn off the family, not the cell: with Wi-Fi off its glyph leaves the contracted
  cell and the well stays, empty and available.

**Why** — **width is the data**: three glyphs mean three connections, a count read without
reading, and the reason this cell does not have a single icon. Strength bars stay primary: a
weak signal is not "past threshold". The **wireless glyph is ours** — two nodes joined by a
thread: it says the same thing as the registered mark, using the vocabulary the shell already
owns, without reproducing someone else's trademark. **The radio dot only where the choice is
exclusive**: you join one Wi-Fi network at a time and there it tells the truth; among devices it
would lie.

| Measure | Value | Note |
|---|---|---|
| glyph | 18 px | 10 px pitch, 1.5 stroke |
| contracted cell | 40 px | min 64 px with a single glyph, padding 14 |
| panel | 340 px | one well per family, radius 20 / 10 |
| network row | 38 px | dot 16, name in Spectral, lock 12, 4 bars |
| device row | 38 px | glyph 18 lit or dim, no dot: the choice is not exclusive |
| strength bars | 3 px | heights 5 / 8 / 11 / 14, always primary |
| password field | 34 px | radius 17, primary outline, 1 px caret |
| error | outline + line | alert outline, reason in Spectral 12.5 under the field |

---

## 12 · Settings

*Two levels · separate capsules · as wide as it needs.*

Bioma's own settings: appearance, structure, cell conditions, monitors, keybinds. Not a system
control panel — anything that has its own cell does not come back here as a category. At rest it
is the mark, and this is the only place it appears.

**Expanded** — five category capsules on the left; the thread leaves the chosen one and feeds
the panel. **The panel is as wide as the category needs**: Appearance fits in 440 px, Structure
wants 720.

**Appearance** — opacity, blur, radius, scale, and three distinct margins: screen **edge**,
**tissue** to cell, and the **gap** between the shapes of an open cell. Plus the timing set.

**Structure** — pick the monitor, then switch on up to **six tissues**: three on the top
membrane, three on the bottom. An unlit slot is dashed with a plus: click it to light it, empty
it to switch it off. Each membrane is **fixed or auto-hide**, and that applies to the whole
edge. The chosen tissue opens at the bottom with its max width and its cells: each cell is a
chip with a cross to remove it, and a dashed chip adds one. **"+ Cell" opens a capsule to the
side**, hung on a thread, listing only the cells not already in that tissue.

**Cells** — one row per cell with visibility as a segmented control: Always, Conditional,
**Invoked only**. Options a cell cannot have stay visible but dimmed.

**Monitors** — dragged and snapped, including one below the other. Name and mode on two lines
inside the rectangle, so they stay centred at any size.

**Keybinds** — added, edited and removed. The combination is recorded by pressing it, not by
typing it.

**Behaviour**
- Fixed height, scrolling inside: a settings window that changes height on every category is
  unbearable to navigate.
- The thread follows the selection. There is no "selected" outline to invent: the chosen capsule
  is the one the thread starts from, and the others stay identical.
- **"Invoked only" is named that way because *every* cell is invokable**, even when it is always
  visible or conditional: a shortcut opens it anyway. The option does not decide whether it can
  be invoked, it decides whether it exists without being invoked.
- Sliders are controls, so primary for the whole travel: there are no thresholds here.
- Visibility: invoked, optionally also an always-present icon.

**Why** — separate capsules, not a list in a panel: a sidebar inside a box would be the one part
of the shell not speaking its language. **Structure is composed, not listed**: six slots drawn
where they will actually be say at a glance what a list of tissues with numbers beside them
never would — and it is the only form in which "add a tissue" has an obvious place: the empty
slot. **Dimmed options stay visible**: seeing that the window title can only be conditional
teaches how the shell is built. **Monitors need real space**: a column layout is as common as a
side-by-side one. **The mark appears only here**: a shell putting its logo in several places is
advertising itself on someone else's desktop.

| Measure | Value | Note |
|---|---|---|
| category capsule | 160 × 44 px | full pill, 52 px pitch |
| panel | 440 – 720 px | as wide as the category asks; fixed height with scrolling |
| setting row | 44 px | label 92 px in Orbitron 12, slider 150 px |
| list row | 38 px | cells, monitors, shortcuts |
| tissue slot | 196 × 26 px | three per edge, radius 11, dashed when empty |
| cell chip | 26 px | 9 px cross to remove, dashed to add |
| picker capsule | 220 px | opens to the side on a 24 px thread, 36 px rows |
| small segmented | 22 px | inside list rows, radius 14 |
| monitor area | 640 × 320 px | holds a column layout, not only side by side |
| thread | 24 px | horizontal, from the centre of the chosen capsule |

**Decided** — the selection **is** the thread. Instead of inventing a "selected" state for the
capsules, use the one thing that already means "this feeds that" in the shell. It applies to any
future two-level case. **Also decided** — six tissues per monitor, three per edge. A design
limit, not a technical one: beyond three per side the tissues get too narrow for percentages to
mean anything, and the membrane stops reading as a single line.

---

## 13 · Launcher

*Invoked only · no thread · the largest.*

Search and launch. The only cell with **no contracted state**: it sits on no membrane, is hung
from nothing, and when it appears it is already open at the centre of the screen. That is also
why it is the only one without a thread: it is not born from a cell, it is born from a shortcut.

**Expanded** — field in Spectral, results in Spectral, category in Orbitron. The letters the
search matched are in the primary: you can see *why* a result is there.

**Limit cases** — no results: one line, and the field stays where it is; the panel does not
collapse under your fingers. Just invoked, empty field: the most used applications, not the
first ones alphabetically.

**Behaviour**
- Takes focus on open and gives it back on close. The simplest case of an invoked cell, and the
  reason to build it last: by the time it arrives, the mechanism must already work.
- Arrows to move, Enter to launch, Esc to close. The first result is already selected: typing
  two letters and pressing Enter must be enough.
- Six visible rows, then it scrolls. A launcher filling the screen with results is saying the
  search did not work.
- It floats: its own tissue, deeper shadow, no edge anchor. It also closes on a click outside.

**Why** — **matched letters are coloured.** It is the one place in the shell where colour enters
a word, and it earns it: it shows the fuzzy search's reasoning, so when it is wrong you can see
why instead of thinking it is broken. Row height 52, more than list rows elsewhere, because here
you aim with the mouse after reading, and the application icon deserves 36 px instead of 20. **No
thread, no membrane**: the form says how it was born — everything else in the shell hangs from
something, this arrives from the keyboard and leaves. **Selection is a fill, not an outline**:
the glowing outline means "surface" in Bioma, and using it on a row would make it look like a
cell inside a cell.

| Measure | Value | Note |
|---|---|---|
| panel | 480 px | radius 20, shadow 0 24 52 / 60% |
| field | 44 px | Spectral 16, lens 17, 1 px caret |
| result row | 52 px | icon 36, name Spectral 15, category Orbitron 11 |
| visible rows | 6 | then scrolls, with the selection always inside |
| selection | radius 14 | primary fill at 12%, icon outline in primary |
| opening | 250 ms | grows from the centre in width and height, no thread |

**Decided** — with an empty field, the most used. The PRD puts the launcher last because it
carries identity, and a launcher's identity is entirely in what it shows *before* you type. An
alphabetical list is an archive; the most used are an answer.
