# Progress

Where the work stands. `services/INVENTORY.md` holds the detail and the
reasoning; this is the short version and the list of what is *not* done.

Last worked: 2026-09-22.

## Where to pick up

Phase 1 is nine services of ten, every one verified. Phase 0's engine draws and
has been exercised by nine cells; phase 2 is finished — window title,
workspaces and vitals, the last of them opening into pods and a process list;
phase 3 is finished — the theme cell retints the shell live, the utility cell
captures with Bioma's own selection rectangle rather than `slurp`, and
sinestesia draws the sound. Phase 4 has started with the audio cell.

Three ways in, and they are independent:

1. **Phase 4 is done but for notifications.** Audio, connectivity, session and the dock are drawn —
   the dial, the capsule and the three wells against the real PipeWire graph,
   and one glyph per live connection with the two family wells under it. What
   is left of the cells already drawn is what CELLS left open: sinestesia on a
   narrow screen and whether a long title scrolls on hover, and reduced motion,
   which asks for the band to become a single bar rather than stop.
2. **Notifications**, which closes phase 1 and burns the bridge — the only work
   that cannot be done without switching the running shell off. See the
   pre-flight below.
3. **The rest of the engine**: the last user of the full-screen input surface,
   cells positioned at the pointer. **Vertical tissues stack** and **auto-hide
   hides**, see below; what auto-hide has never done is come back, because
   only a pointer at the edge can ask it to. **Invocation and floating tissues are done**, see below; what is
   left of the audio cell's invoked form is what it *shows* there, because
   CELLS §05 draws the capsule alone with no thread and the cell currently
   arrives as itself and opens in the usual way.

### Confirmed by a real hand, at last

2026-09-21, driving the shell on both monitors: a tap opens a cell; the capture
panel's three sources act on the press; the selection rectangle is drawn,
measured and released; a screenshot of a whole output lands with the panel
absent from it; a recording runs, stops and is saved or discarded from its own
cell; and text recognition reaches the clipboard from a rectangle drawn by hand.

Four defects came out of that hour and are fixed: a tissue that laid its cells
outside itself on a narrow membrane, a save-or-discard control dropped by the
rule that replaced it, a cell frozen on the membrane when its condition lapsed
under the pointer, and a selection region 44 px too high because a full-screen
surface asked for `exclusiveZone: 0`.

### Still waiting for a pair of hands

Nothing here can press a mouse button — there is no `ydotool` or `wtype` on
this machine — so these are written, look right in a screenshot, and have never
been confirmed by a real press:

- **a press outside an open cell dismisses it**, through `structure/InputSurface.qml`;
- **the scrollbar** in both lists, which appears while the list is moving;
- **pressing the vitals search field**, which used to dismiss the cell and
  should not any more: the masks are rebound when an expansion finishes
  growing, not only when it appears;
- **the theme cell's controls**: the carousel's wheel and its two neighbours,
  the source switch, the dropdown and its rows. Each was driven from a
  throwaway timer instead — the list opens, the switch slides, and a palette
  written through `Config.set` retints the whole shell in a screenshot taken
  three seconds later — but no press has ever reached any of them.
- **every gesture of the audio cell**: the wheel on the pill, the middle
  button, the main slider, the per-application sliders and their mute rings,
  and picking an output or an input. What they *show* is confirmed against the
  live graph — the volume was moved with `wpctl` and the dial followed, three
  applications were given three different volumes and one of them muted, and
  the rows drew it — but the path from a press back to PipeWire has only ever
  been driven from the other end.

The way to verify anything visual here is a temporary `Timer` that sets
`open = true` a couple of seconds after start, then `grim` for a frame or a
burst of them. Take the patch out before committing.

## How to try it without touching the running shell

Noctalia owns the DP-1 membrane; HDMI-A-1 is free. `~/.config/bioma/override.json`
declares one membrane there and nothing else, so

```sh
qs -p "$PWD/shell.qml"
```

draws Bioma on the second monitor while the session's own shell keeps running.
The override file is outside the repository, and replaces `membranes` wholesale
because arrays are replaced, not merged.

## Phase 0 — Foundations

Drawn, and verified on screen against the design handoff.

| Piece | State |
|---|---|
| `core/Config.qml` | Working. Two layers, deep merge, hot reload. |
| `core/Theme.qml` | Working. Four roles from a source, three fixed, the rest derived in HSL — surfaces, the outline family, the two gradient stops. With the shipped palette the derivations reproduce `docs/design/tokens.css` to within a step or two. |
| `core/Metrics.qml` | The token geometry. **Renamed from `Scale`**: `QtQuick` exports a `Scale` type and shadows a singleton of that name everywhere. |
| `core/Timing.qml`, `core/Typography.qml` | Aligned to the handoff: one named set, curves included; two voices, Orbitron and Spectral. |
| `core/Regions.qml` | Region trees built at runtime, for the input mask and the blur region. |
| `structure/Membrane.qml` | Real. Slot placement from percentages, anchors derived from the list, exclusive zone, input mask, blur region, auto-hide written. |
| `structure/Tissue.qml` | Real. Ceiling-not-reservation widths, elastic share, reflow, the punched band. |
| `structure/Cell.qml` | Real, contracted. Glass, rim, config-driven width and visibility, growth mechanics written. |
| `structure/Visibility.qml` | **Exercised at last** — the window title appears and disappears with focus. |
| `components/` | `Rim`, `Ring`, `DashedRing`, `Disc`, `Dial`, `Gauge`, `Slider`, `Switch`, `Strength`, `Portrait`, `Icon`, `LightGradient`, `Thread`, `Panel`, `Well`, `Band`, `Sweep`, `Segmented`, `WorkspaceBars`, `Vital`. |
| `structure/InputSurface.qml` + `core/Focus.qml` | The full-screen surface of PRD §8, and the register of what is open. Built; the press path still needs a human to click. |
| `cells/clock`, `cells/window_title`, `cells/workspaces`, `cells/vitals`, `cells/theme`, `cells/utility`, `cells/recording`, `cells/sinestesia`, `cells/audio`, `cells/connectivity`, `cells/session`, `cells/dock` | Twelve cells. Vitals opens into pods, threads and the process list; theme into the wallpaper carousel and the two palette capsules; utility into the capture panel, and generates the recording cell. |
| `structure/SelectionSurface.qml` | Bioma's own selection rectangle, over the whole desktop, in place of `slurp`. Up only while a region is being asked for, and it holds the keyboard for that long so Escape means cancel. |
| `components/Segmented.qml` | The segmented control, shared: the theme cell's source switch and the utility cell's three kinds are the same object. |
| `core/Config.qml` write-back | `Config.set` writes one key into the override layer. Brought forward from phase 5 because the theme cell has to keep a choice. |

Verified on HDMI-A-1: cells float with no band, the rim reads, the app icon
resolves and the fallback glyph is tinted, the title elides and cross-fades, the
minute dial fills, and **blur through `ext-background-effect` is confirmed** —
the wallpaper is sharp outside the pills and smoothed inside them.

Expansion works, and the workspaces list is the first one drawn: the thread
draws out of the cell, the panel grows from its far node, and the content
arrives once the shape is at size. Closing reverses it, quicker.

A membrane on the **bottom** edge is exercised too: DP-1 carries one in the test
override, with every cell built so far on it. Expansions grow upward from the
window line, and the two compositions are ordered from the cell outwards —
which is where the bug was: both were built against a cell above them, so on a
bottom membrane the theme cell's carousel ended up at the far end and the
capsules against the cell, and the shapes grew away from the thread that ties
them there instead of out of it.

Exercised since: floating tissues, vertical tissues, keyboard focus, and
auto-hide as far as hiding goes — a membrane declared `auto_hide` slides its
content out, stops reserving its strip, and leaves the two-pixel band that
catches the pointer. Coming back is the half a pointer has to ask for, and no
test here can. Not yet exercised: several elastic cells in one tissue. Clicking outside to close is
written and mapped — `niri msg layers` shows `bioma-input` appear on every
monitor the moment a cell opens — but no test here can press a mouse button,
so the dismissal itself is verified by hand.

### Decisions taken while building it

- **`Scale` → `Metrics`.** Name collision with `QtQuick.Scale`, which wins in
  every file that imports QtQuick.
- **A membrane's surface is the size of its output, for the whole session.**
  It used to take the screen when a cell opened and give it back when the last
  one closed, and that resize is not atomic: Qt changes the window's height on
  one frame and the compositor applies it on another, so everything positioned
  from that height — the tissue on a bottom membrane sits at
  `height − margin − thickness` — is drawn once at the old size and once at the
  new. The bar appears twice, one of them near the top of the screen, and every
  cell loses its glass for that frame. A transparent surface the size of the
  output costs a buffer; it still reserves only its strip, and outside its cells
  it catches nothing, because the mask is built from the cells themselves.
  Which makes the mask load-bearing in a way it was not: a **null** mask means
  the whole surface takes the pointer, so both the membrane and the catcher now
  fall back to an empty region until their first rebuild.
- **A region tree is grown and never shrunk.** Rebuilding one is the single
  frame a surface has no region at all — the old object is destroyed, the new
  one assigned, and in between the compositor is told to blur nothing. Every
  cell on the membrane loses its glass and gets it back, and closing a cell
  whose expansion is a composition did it twice in a row, because the shapes
  leave the list one after the other. `core/Regions.qml` now allocates leaves
  in steps of eight, parks the ones a shape list does not use, and rebuilds
  only to grow: an open and a close cost four trees at startup and none after
  that. Akusen saw it as the whole bar flickering on close, 2026-09-22.
- **A lookup that misses before the list exists must not be remembered.**
  `core/Apps.qml` caches its answers, misses included, because the process
  list asks the same sixty questions every few seconds — and Quickshell's
  models fill on their first property binding, not on first access. So every
  icon asked for before `DesktopEntries` had filled was recorded as "no such
  application" for the life of the session: the dock's kept applications drew
  the neutral glyph while the running ones, asked for later, drew their own.
  The list is now bound in `Apps` itself, where the lookups are, and the cache
  is emptied whenever it changes — which is also what happens when an
  application is installed.
- **Dynamic `Region` children do not work.** An object created with
  `Qt.createQmlObject` or `Component.createObject` and given a Region as parent
  never joins its `regions` list. The tree is built from a QML string that
  contains the children, and the leaves are bound afterwards — `core/Regions.qml`.
- **Icons are recoloured as text, not tinted as bitmaps.** The files paint in
  `currentColor`, which Qt renders black; `components/Icon.qml` substitutes the
  colour in the SVG source. It must emit `rgb()`: Qt writes a colour as
  `#AARRGGBB`, SVG reads that as `#RRGGBBAA`, and the glyph silently vanishes.
- **A cell's content declares an unelided width.** Binding a `Text`'s width to
  its own `contentWidth` collapses it to nothing once it elides, so a cell that
  elides reports `implicitWidth` through `Cell.contentWidth` and elides against
  what it is granted.
- **The tissue is one continuous fill behind its cells**, at the token's 0.5.
  `docs/design/IMPLEMENTATION.md` asks for the band to be drawn only around the
  cells, punching their shapes out of it, so that cell blur is not seen through
  two layers. That was built first and it is wrong at this scale: with a 2 px
  margin a punched band *is* a one-pixel outline around every cell plus a rule
  standing in the gap between two of them — the outline and the divider the
  design forbids. The design page draws the tissue as a plain background behind
  its cells, and so does this. The cost, stated rather than hidden: a cell
  composites over the band, so its declared opacity reads a little heavier than
  the number says.
- **A cell's private visual pieces live in `components/`.** Quickshell
  generates no QML module for a cell's own directory — `import qs.cells.clock`
  is not installed and a relative `import "."` does not resolve either — so a
  sibling type is invisible to the cell beside it. `Dial` and `WorkspaceBars`
  are there for that reason as much as for reuse.
- **An expansion can be a composition, not only a panel.** `Cell.panel` is the
  single-surface case; `Cell.expansion` hands a cell the anchor and lets it lay
  out its own shapes and threads, which is what the vitals pods needed. The
  cell asks whatever it loaded for the shapes it occupies, so the membrane's
  mask and blur region follow a composition as readily as a rectangle.
- **A Loader sets its item's properties after that item is built.** Anything a
  loaded expansion has to do on arrival belongs in `onCellChanged`, not in
  `Component.onCompleted` — the first pod cascade never ran because of it.
- **A liquid's level is measured against its vessel.** The memory indicator
  fills the inside of the ring, not the square the ring is drawn in: half full
  lands on the centre line either way, which is what the design draws, but a
  fifth of the memory has to read as a fifth rather than as a sliver below the
  glass.
- **A mask's source has to render itself.** Qt Quick clips rectangles only, so
  the liquid is held inside the ring by an `OpacityMask` — and in Qt 6 an item
  that is merely `visible: false` draws nothing for a mask to sample. Both the
  source and the mask carry `layer.enabled`.
- **The edge margin is measured to the cell, not to the band.** The outermost
  cell on a membrane sits at the margin from the screen edge and its tissue's
  padding hangs outside it, so the cell lines up with the left and right edges
  of the windows — which niri insets by the same `gaps`. Measured: cell and
  window both at x 12.
- **An expansion hangs from the line the compositor draws windows on.** Not
  from the cell, and not from the edge of the reserved strip: niri insets its
  windows by `gaps` and by any `struts`, so a panel hung at the strip's edge
  floats a gap above the windows and the alignment the eye actually checks is
  the one that is wrong. `services/Niri.qml` reads those two figures out of
  niri's own `config.kdl` and watches it — `niri msg` has no configuration
  query, only outputs, workspaces, windows and layers — and the tissue makes
  each thread however long it must be to reach that line. Measured with
  `gaps 12`: the panel's upper rim and the window's top edge both at y 68.
  Akusen's rule, 2026-09-20.
- **The input surface's region is the screen minus what the shell claims.**
  Layer-shell surfaces of one layer stack in creation order, which is not
  something to build a behaviour on: the catcher subtracts every cell and panel
  from its own input region instead, so the two never overlap and the right
  surface receives a press whatever the compositor stacked where.
- **One cell is open at a time.** `core/Focus.qml` holds it: opening a second
  closes the first, because two panels on screen are two conversations.
- **A cell keeps its content when it opens**, unless it says otherwise.
  PRD §6.7 says the contracted content is entirely replaced by the expanded
  one; that is true of vitals, whose cell becomes the header of its own
  expansion, and wrong for the workspaces cell, which the mockup shows keeping
  its mark and its name while the list hangs below. `Cell.replacesContent`
  carries the difference.
- **The window title has no minimum width.** CELLS.md §01 gives it 186 px as a
  stabiliser; on the machine it read as a wide empty pill next to a short
  title, so it now takes exactly the width of its text. Akusen's call,
  2026-09-20.
- **A cell's panel content is loaded by URL, not imported.** There is no QML
  module for a cell's directory, so `cells/<name>/` holds the contracted cell
  and its expansion as separate files, and the cell loads the second with
  `Qt.resolvedUrl` — which keeps the layout CLAUDE.md describes.
- **A cell knows its monitor.** The membrane passes its screen name down
  through the tissue, so the workspaces cell answers for its own output, as
  CELLS.md §03 decided against PRD §9.3.
- **A tissue's place on its membrane is derived from its order**: first is the
  start corner, last the end corner, anything else centred, `growth: symmetric`
  forces the centre and an explicit `anchor` overrides all of it. The
  configuration declared growth but never where the tissue sits.

- **A setting the user changes is written one key at a time.** `Config.set`
  rewrites the override document with that key changed, never the merged values:
  a membrane list, a font, a hand-written `$comment` all survive a theme being
  chosen. It also keeps the document in memory, because two settings changed in
  the same breath — source and palette, when the switch moves — would otherwise
  both read the file as it was before either had landed, and the first would be
  lost. Brought forward from phase 5; the settings page will want exactly this.
- **The palette has a destination as well as a journey.** Every visible role is
  animated, which is what makes a theme change cross the whole shell at once —
  and it is also what makes a chip bound to one arrive late: a delay restarted on
  every frame of the transition never elapses. `Theme.targetRoles` is the seven
  roles computed from the palette as loaded, and the theme cell's chips follow
  that instead, sixteen milliseconds apart.
- **The wallpaper's thumbnails belong to the wallpaper service.** Not to the
  cell that shows them: the settings page will want the same small copies, and
  the cache is the wallpaper's own business. `magick` makes them one at a time
  into `~/.cache/bioma/thumbnails`, and without ImageMagick the carousel reads
  the photographs themselves — slower on the first look, and the same cell.
- **A converter creates its output before it finishes writing it.** The
  directory model announces the file at that moment, Qt reads a fragment, and
  reports "Unsupported image format" for good. The file being written is left
  out of the cache set until the process writing it has exited.
- **A binding must not start work.** `Wallpaper.thumbnail()` looks a path up and
  nothing else; asking for one to be *made* is `prepare()`, called from a change
  handler. The first version did both in one call and Qt stopped evaluating the
  binding — a binding that changes what it reads is a loop, and the tile went
  blank rather than wrong, which is the harder kind of failure to see.
- **The theme cell does not carry the wallpaper's "how".** Fill, fit, span and
  per-monitor are requirements, but CELLS.md §07 draws a carousel and two
  capsules and no mode control, and there is no room inside 268 × 96 for one
  that would not be a fourth thing to read. The mode stays in the wallpaper
  service, where it already lives, and lands in the settings cell.

- **A capture waits for the shell to be gone.** Everything Bioma draws is on the
  screen being photographed, and closing the cell is an animation: `grim` run in
  the same instant catches the panel mid-close, and the recorder catches it in
  its first frames. The wait is in the service, once, where every path goes
  through it — `Timing.close` plus a frame — rather than in each caller.
- **A pair that cannot be done is shown as unavailable.** The recorder takes an
  output or a region and never a window, and text is recognised from a region,
  which a window does not have here — niri reports no window position, so the
  compositor captures it by id. Two independent choices are still two, and the
  ones that cannot meet are dimmed rather than offered and then refused.
- **The selection rectangle is one surface per monitor**, so a rectangle drawn
  across two outputs is not possible: the pointer leaves the surface it started
  on. `slurp` has the same limit for the same reason, and the region grim wants
  is one output's anyway.
- **The recording cell is conditional on the file, not on the recorder.** It
  stands while `wl-screenrec` runs and stays for the question afterwards,
  because the file it is asking about is the one it just made. When the answer
  arrives the condition lapses and the cell leaves on its own.

- **A composition is ordered from the cell outwards, not top to bottom.** A
  single panel already handled both edges — `structure/Cell.qml` computes its
  anchor and its node from `opensDown` — but a composition places its own
  shapes, and both of them had the cell's direction written into them as a
  constant. The rule, now stated once per composition: the shape the cell's
  thread lands on is the one nearest the cell, and everything the expansion
  opens afterwards opens away from it. The theme cell's dropdown list is the
  case that shows why — hung downwards on a bottom membrane it would lie over
  the carousel.

- **Interaction suspends disappearance, and something has to un-suspend it.**
  `structure/Visibility.qml` paused a running dwell on hover and resumed it on
  exit, which is right — but when the condition lapses *while* the pointer is on
  the cell no timer was ever started, so there was nothing to resume and the
  cell stayed for ever. Found on the recording cell: stop and save with the
  pointer still on it, and the counter stood frozen on the membrane. The pointer
  leaving now re-evaluates the condition. This matters most for notifications,
  where the actions live in the hover state.

- **Precedence before position, when the room runs out.** The first version of
  the rule above handed out space in anchor order alone, and the first thing it
  threw away was the recording cell asking whether to save — twice the width of
  the counter, and the one cell in the shell that has to be answerable. A cell
  that is there because something is happening now outranks one that is simply
  always there, and an open cell outranks both: it is the one being looked at.
  On a crowded membrane the theme chips wait and the question stands.
- **A ceiling the band respects and the cells ignore is not a ceiling.** The
  tissue clamped its own length to the declared percentage and then laid its
  cells out in a row regardless, so on a narrow monitor the last of them stood
  outside the band — and far enough over, outside the screen. Found on a 1920 px
  monitor whose right tissue was 20%: the recording cell appearing pushed its
  neighbours off the edge. The tissue now hands out room in anchor order and
  leaves out what it cannot fit, saying so once; the cell comes back by itself
  when its neighbours need less. The two monitors behaved differently only
  because 30% of 3440 is room enough for anything.

- **A full-screen surface asks for `exclusiveZone: -1`, not 0.** Zero does not
  mean "reserve nothing": it asks the compositor to keep the surface clear of
  every *other* exclusive zone, which it does by shrinking it. The selection
  rectangle was therefore drawn on a surface whose origin was 44 px below the
  output's — the height of the other shell's bar — and it handed `grim` its own
  coordinates as though they were the screen's. Select a line of text and the
  line above it lands in the clipboard. Measured both ways: a rectangle drawn at
  400,400 sits at 444 on screen with a zone of 0 and at 400 with -1. The input
  surface had the same declaration and the same flaw waiting in it: the holes in
  its region are computed from items on other surfaces, and the pointer position
  it exists to report is read straight out of it.

- **A cell's own tap target is the pill, not its content.** Everything a cell
  declares goes into `contractedSlot`, which is inset by the cell's padding — so
  the `TapHandler` each cell declared answered over its icons and nowhere else.
  On a 40 px square cell that is the icon and two pixels of frame, which is why
  opening one was fiddly. Opening is the same gesture on every cell that has an
  expansion, so it lives in `structure/Cell.qml` now, on the cell itself, and
  the cells declare nothing.
- **A surface that shrinks on `open` clips the closing away.** The membrane took
  the whole screen while a cell was open and went back to its strip the instant
  the cell stopped being open — which is the first frame of the retraction, not
  the last. The animation ran the whole time (measured: growth 0.99 → 0 over
  144 ms) and nobody could see it. The surface now follows `expanded` — open, or
  still on its way back — and outlives the closing by the 169 ms it takes.

- **A thread's ends belong to the shapes, not to their coordinates.**
  `IMPLEMENTATION.md` says it — the thread is a child of the common container
  with its ends bound to both shapes — and both compositions had them at the
  coordinates the shapes come to rest at instead. Opening hides the difference,
  because everything arrives where the arithmetic said it would. Closing does
  not: the panel retracts towards the cell while the pods and capsules retract
  towards points it has already left, so the composition comes apart instead of
  going home. Bound to the live geometry, the pod chases the panel's edge all
  the way in — measured, the gap between them closes from 18.5 px to 0 while
  both travel towards the cell.

- **Content arrives the way it leaves: growing from its own centre.**
  STYLE_GUIDE §6 asks for opacity plus a 4 px rise on the way in; on the machine
  that reads as the content dropping in from above, and a shell where things
  arrive one way and leave another has two gestures where it needs one. The
  guide still says 4 px — this is a decision against it, not an oversight.
  Akusen's call, 2026-09-21.
- **A panel's content is laid out at the size the panel settles at, not the
  size it is at.** The slot was bound to the animated width, so everything
  centred in it re-centred on every frame: at rest nothing shows, and on the way
  out the content shot sideways while the capsule retracted under it. Akusen
  caught it and named the cure — the content should shrink in place about its
  own centre and go before its container does. So the slot keeps the target
  size, is centred on the shape, and leaves by fading and scaling to 0.88 over
  `contentFade`, which is shorter than the `close` the shape takes. Content is
  the one thing in the shell allowed to scale: a shape that scales deforms its
  rim and its radii, and content that is on its way out has neither.

- **A region belongs to one surface; an item answers for another.** The
  full-screen catcher subtracted the cells from its own input region by handing
  `Region.item` the cells themselves — and an item asked where it is answers in
  the coordinates of *its own* window. For a membrane on the top edge those are
  the screen's and nothing showed; for one on the bottom edge in its resting
  strip they are a screen's height out, so the catcher covered every cell on it.
  A press there closed whatever was open and never reached the cell under the
  pointer, which is exactly what it looked like: clicking a second cell closed
  the first and opened nothing. The membranes now hand over rectangles on the
  output — they know their own edge and size, which is the only way a layer
  surface can know where it is — and the catcher subtracts those.

- **An image decodes at the size it can reach, not the size it has.** The
  carousel's tiles bound `sourceSize` to their live width, so a step was a
  different decode on every frame: nothing hit Qt's image cache, each frame
  started an asynchronous load, and the pictures blinked through the whole
  animation. Decoded once at the middle place's width, a step finds four of the
  five tiles already `Ready` and only the one arriving loads — off the strip,
  where it cannot be seen. Scaling a decoded image down is free; decoding it
  again is not.
- **The wallpaper carousel travels rather than swapping.** A step is a movement
  that answers a gesture — the class the style guide allows beside the segmented
  pill and the slider — so it takes the transition timing and is still again
  afterwards. The strip is five places wide and clipped to the panel's inside:
  the wallpaper arriving grows from the neighbour's width to the middle one's
  while the one leaving shrinks, which is the movement itself rather than a
  slide with a swap at the end. The wallpaper changes first and the strip is
  displaced one place against the direction of travel, so the first frame is
  what was on screen before the step. Akusen asked for it, 2026-09-21.

- **A window that is working says so in its own title, and the shell says it
  its own way.** Terminals, browsers and editors all put a spinner glyph in
  front of the name and rewrite it several times a second. The window title cell
  now takes that glyph out of the string and shows `components/Sweep.qml` in its
  place — one drawing for "working", whichever application asked — which also
  settles the title: a spinner rewrites faster than the debounce, so the cell
  was never watching a string that had stopped changing. The loader appears only
  after `debounce` and goes the frame the glyph does, per
  `docs/design/icons/LOADER.md`.
- **The loader is drawn, not loaded.** `assets/icons/loader.svg` is deliberately
  static and an SVG cannot move without being rasterised again every frame, so
  the component carries the file's own geometry in its own 24-unit space. It is
  called `Sweep` because `QtQuick` exports `Loader` — the same trap that cost
  `Scale` its name.
- **The theme and utility cells become their own title when they open**, like
  workspaces and vitals: the glyph of the domain and the name in the technical
  voice, with the contracted content standing down. Akusen's request, with the
  theme cell's icon drawn for it, 2026-09-22. The utility cell says `UTILITY`
  and not `CAPTURE`, which would describe what it does today: the cell is named
  for its category because it is expected to grow other functions, and a title
  that has to be renamed when it does is the wrong title.

### Sinestesia, read rather than guessed

The author's own visualiser is at `~/Documents/Development/Sinestesia` — Rust,
Relm4/GTK4, PipeWire capture, `rustfft`, and a renderer in OpenGL through
`glow` and `GtkGLArea`. `IMPLEMENTATION.md` asks which of those two it is
because they are two different work estimates; it is the portable one, and it
turns out not to matter, because what Bioma needs from it is not the renderer.

What it needs is `src/dsp.rs`, and that is 338 lines. The contract, copied
figure by figure into `tools/sinestesia-bands` rather than reinvented:

| | |
|---|---|
| window | Hann over `FFT_SIZE 2048`, 48 kHz |
| bands | 64, logarithmic from 30 Hz to 16 kHz |
| inside a band | the **peak** bin, never the mean |
| normalisation | dB, −70 → 0 and 0 → 1, then gain, clamped |
| smoothing | one pole, asymmetric: attack 0.45, decay 0.18 |
| cadence | 60 Hz |

There is no peak hold: the word "peak" in that code is the aggregation inside a
band, not a mark that falls back. Sinestesia's stereo imaging analyser — ITD,
ILD, the duplex crossover, the tangent law — is deliberately left behind: it is
beautiful and it is about two channels, and Bioma's band is one spectrum of
what leaves the machine, summed before the transform.

- **The tool is a build step, and the first one this repository has.** `cargo
  build --release` inside `tools/sinestesia-bands`, needing the PipeWire
  headers. Without it the service says so and the cell does not appear; there is
  no fallback, because half a visualiser is worse than none.
- **It speaks in hexadecimal, not JSON.** One line per frame, two digits per
  band. The reader is a QML string parser running sixty times a second: fixed
  width, no allocation per value, and still readable in a terminal.
- **It runs only while a cell is looking**, and it is stopped by closing its
  stdout rather than by being told to stop. Whether the cell exists at all is a
  separate question that `services/Audio.qml` already answers from the peak
  monitor, without any of this running.
- **The one test is the one that matters**: a 1 kHz tone has to land in the band
  that holds 1 kHz, and silence has to empty the band. It needs no sound card
  and nobody has to listen to anything.

Verified end to end with real audio playing: 64 bands arriving, level 0.35, and
the fold to fourteen showing the shape of the music rather than a flat line.

- **The band is a mask over one gradient, not a row of filled bars.** The
  design says the gradient is defined over the height of the band and not of the
  single bar — a short bar samples the middle of it, a tall one runs its whole
  length — which is the only way to keep one light source on something that
  changes shape thirty times a second. So `components/Band.qml` draws the bars
  into a layer, draws the gradient into another, and shows the first through the
  second.
- **Two symmetries, and they are not the same one.** A bar grows from the middle
  *line*, up and down, because filling from the bottom already means memory in
  this shell and sound has no floor. And the row is mirrored about its *middle*:
  the left half is the left channel, the right half the right one, the low
  frequencies meeting at the centre and the high ones at the outside — the shape
  Sinestesia draws, which makes the picture the stereo image rather than a
  spectrum twice. Akusen asked for it, 2026-09-22, and the tool keeps the two
  channels apart from the capture onwards to give it.
- **A band at zero is a row of dots**, not a row of gaps: an instrument with
  missing teeth reads as broken rather than as quiet.
- **The track panel hangs from the visualiser, and does not exist without a
  track.** Sound is always there and a track only sometimes, so the thread says
  which of the two holds the other. With no MPRIS source the panel is absent
  rather than empty, and it arrives and goes as a track appears and ends without
  the cell closing.
- **A cell whose content is a name needs a ceiling.** Sinestesia asked for its
  band plus a whole track title with nothing capping it, and being conditional
  it outranks the cells that are simply always there — so on a narrow membrane
  it took the tissue and the clock and the window title stood down. The window
  title has carried a cap since it was written, for exactly this; sinestesia has
  one now too, elastic with the band as its floor. Below the room a name needs
  it shows the band alone and centres it, which is the answer the design already
  gives for a track with no metadata, arrived at from the other direction.
- **The player selector takes what the transport leaves.** The controls that act
  are not negotiable and a name can be shortened: with one player the selector
  is absent, with a long identity it elides, and below sixty pixels of room it
  stands down rather than overlapping the buttons.

- **The blur was arriving and niri was blurring the wrong thing.** The protocol
  was negotiated, `set_blur_region` was sent, and the region was right — the
  rounded pill decomposed into scanlines. niri's own source says why nothing
  showed: with a background effect visible and xray unset, it defaults xray to
  **true** because it is cheaper, and xray blurs the compositor's backdrop
  rather than what is behind the surface. Bioma draws its own wallpaper on its
  own layer surface, so that backdrop is a flat colour — which is what the cells
  showed. `config/niri/bioma.kdl` says `xray false` and nothing else: the region
  still comes from the protocol, and the rule only settles which thing gets
  blurred.
- **A shape a cell draws and does not declare is not blurred and takes no
  presses.** The vitals pods were missing from `shapes()`, so the wallpaper
  behind them stayed sharp while the panel beside them was glass — and the taps
  that sort the list by a domain were never claimed either. Akusen saw the first
  and the second came with it.

- **A header keeps its own margins, and the engine works them out.** A cell
  built around a 30 px avatar leads with five pixels so the avatar is
  concentric with the cap; the same five in front of the 20 px glyph of its
  header leave the glyph against the edge, which is what Akusen saw on the
  session cell. The leading margin now follows whichever mark is actually
  there and the name keeps the full margin on its side — and the four cells
  that were each doing this arithmetic by hand with `open ? … : …` have
  stopped.
- **The face a cell wears when it opens is built once, in `structure/Cell.qml`.**
  Every cell with an expansion wears the same one — the glyph of its domain and
  its name in the technical voice — so each of them was carrying its own copy of
  the same `TextMetrics`, the same Row and the same `open ? … : …` width. Now a
  cell says `headerMark` and `headerTitle` and nothing else, and the rule that
  needed a home lives there too: when the tissue grants less than the name
  needs, the cell shows the glyph alone, centred in what it was given. Found on
  the 1920 px membrane, where the name ran out of its own pill — measured at the
  moment it happens, 135 px granted against 143 asked. Akusen's rule,
  2026-09-22.
- **`Repeater.itemAt` notifies nothing.** A binding that reads it without
  reading `count` first is evaluated once, while the Repeater is still empty,
  and keeps the null for ever — which for the vitals threads meant a length of
  zero and no threads at all. The same shape of mistake as reading a service
  from inside a function instead of binding it: the value is right and the
  dependency is missing.

- **`mark.svg` is the settings cell's and nobody else's.** The icon handoff says
  so in as many words, and the sinestesia cell was wearing it anyway until
  Akusen drew the glyph that belongs to it — four bars, the band itself. It now
  stands in the cover well too, where a record without a picture is a record
  without a picture rather than the shell introducing itself.

### Audio, the first control

The catalogue's first cell that is not an indicator. Everything else in the
shell is coloured by something the machine measured on its own; this one is
moved by a hand, so it keeps the primary for its whole run — a hundred per cent
is the top of the travel, not an alarm — and nothing in it ever takes a state
colour.

- **`components/Gauge.qml` is the dial, and it is not `Dial.qml`.** A dial
  fills a sector because a minute is a fraction of a whole. This is a travel
  with a head: a track, an arc, a node at the end of it, and three limit
  drawings that are genuinely three drawings — muted is the arc gone and a cut
  left across the track, zero is the arc closed with the node back at the top
  and *no* cut, and above a hundred the excess restarts as a thinner arc
  further out. All three are photographed against the real service, with the
  machine's own volume moved by `wpctl` and put back.
- **The handoff draws it in a 64-unit box, so the component is that box
  scaled.** Track at r 24, node r 3.4, the outer arc at r 30, stroke 3 —
  figures which at the contracted 26 px and the capsule's 56 px both come out
  at about 1.3 px, which is the thread's weight and not a coincidence. One
  component serves both sizes because the ratios, not the pixels, are what the
  handoff states.
- **An opacity set on a layer that is only ever read as a texture goes
  nowhere.** The muted dial faded its gradient source and kept a lit node
  hanging over the cut. The fade belongs on the `OpacityMask` — the thing that
  is actually drawn — and then the arc and the node leave together.
- **The wheel and the middle button are the cell's, not the content's.** The
  wheel is this cell's main interaction and the whole pill has to answer it,
  which is the rule `structure/Cell.qml` already carries for the tap: a handler
  a cell declares lands in the content slot, and on a forty pixel cell that is
  the glyph and two pixels around it. `Cell` now offers `acceptsWheel` and
  `acceptsMiddle` with a signal each, so a cell says which gestures it takes
  and what they mean, and the engine decides where they are heard.
- **The main slider runs to a hundred and stops.** PipeWire allows more and the
  service does too, but a bar that silently held a hundred and fifty would put
  every ordinary setting in its first two thirds. Above the travel the figure
  says so and the dial's outer arc draws it; the wheel is how you get there,
  deliberately.
- **Three wells of fixed height, not three tabs.** Output, input and
  applications are looked at together — the cell is usually opened *because*
  the sound is coming out of the wrong place. Nodes appear and disappear
  constantly, so the applications well keeps its three rows whether or not
  anything is playing, and says it is empty rather than collapsing and taking
  the panel's height with it. Devices scroll past three as well: this machine
  publishes five sinks and five sources, which is exactly the case a fitted
  panel would have grown to a page for.
- **A device row says how the device is attached** — `USB`, `PCI`, `WEBCAM` —
  from `device.form-factor` where it is published and `device.bus` otherwise.
  Verified against the graph before the row was drawn: the property is on the
  node, which is not something to find out from an empty column.
- **It is the audio cell, not the volume cell.** The dial is what it shows at
  rest, and naming it after that would be naming it after a tenth of itself:
  it already chooses the output and the input and holds a volume per
  application. `VOLUME` is a title that would have to be renamed the first
  time the cell grows, which is the same reason the utility cell is not called
  `CAPTURE`. Akusen's call, 2026-09-22 — the design handoff still numbers the
  section `05 · Volume`, and the type in the configuration is `audio`.
- **Per-application mute is the cell's own sign at a smaller size.** Silencing
  Spotify and silencing everything are said the same way, and the slider stays
  where it was and only dims, because muting is not zeroing. Confirmed with
  three players at three volumes, one of them muted from `wpctl`.

### Keyboard focus is asked for by the cell, not by the membrane

`focus-follows-mouse` is on in this session's niri, and a layer surface that
declares on-demand keyboard interactivity is one the compositor focuses the
moment the pointer crosses it. The membrane declared it whenever *any* cell was
open, so with a cell open the focused window was dropped and picked up again as
the pointer travelled over the other cells — and the window title cell, which
exists on that focus, blinked with it. Akusen saw the title; the fault was the
focus.

`Cell.wantsKeyboard` now says which cells need keys, and a membrane is
focusable only while one of those is open. Verified through `niri msg layers`:
with the audio cell open both membranes report `none`, with vitals open the
membrane carrying it reports `on-demand` and the other still reports `none`.

Vitals is that cell, and it asks only where the keyboard could be wanted:
while the pointer is over **its own panel**, and afterwards for as long as the
field is engaged — the press on the field sets that, Escape and closing the
cell put it down. The pointer on the other cells of the same membrane no
longer disturbs the window at all, which is what was actually being reported:
niri's own focus ring blinking on and off as the pointer travelled.

Two attempts before it, both worth not repeating. Asking for the whole time
the cell is open is what caused the blinking. Asking only on the press cannot
work: the press that makes the surface focusable is the press that should
have reached the field, so nothing can be typed. Arriving over the panel is
what earns the focus, and by the time the field is pressed the surface
already has it.

So the window title cell answers for it instead, which is the better answer
and Akusen's: **the title says what has the focus, and sometimes that is a
cell.** With the keyboard on a cell the title takes the cell's own glyph — the
live one, built from the cell's `headerMark`, so the audio dial keeps moving
in there — and its name in the machine's voice, and hands the window back the
moment the window has it back. The cell no longer goes out and comes back as
the pointer crosses the membrane; it says who is speaking.

Verified in a screenshot with vitals open and `focusedWindowId` forced to −1
from a throwaway timer, which is exactly what niri reports when it moves the
focus to the membrane: the title shows the vitals indicator and
`MACHINE VITALS & T…`, elided at its cap like any long name. The real path
needs a hand, because only a pointer can make the compositor move the focus.

### Hover is the light, and only the light

A closed cell that answers the pointer says so before it is pressed: the glass
lifts a step, the rim catches more of the light, `Timing.transition`. Nothing
moves. A cell with no expansion and no action does not light up — the light is
a promise — so the window title declares itself interactive by hand, because a
press on it centres the window.

Two louder answers were built first and taken out the same day, both worth not
rebuilding:

- **The dock's hover label** (CELLS §09), a pill with the name beside the row.
  It needs the membrane surface to hold something outside the strip, and
  growing the surface when the label appears **cannot work**: the surface
  reconfigures, its input mask is rebuilt, the pointer comes off the cell for
  those frames, the hover that asked for the label lapses, and the two states
  chase each other — the whole interface flickering, and a stray bar at the
  top of the other monitor, which is that surface mid-resize. Keeping the room
  permanently does fix it, and the label is still a second thing to read.
- **The cell opening its own header under the pointer** — the origin alone, no
  thread, no panel. The gesture is right and the cost is the tissue: the row
  reflows on every pass, and vitals, whose header is `MACHINE VITALS & TASKS`,
  shifts its neighbours by a third of the membrane.

### Connectivity, the cell that composes itself

One glyph per live connection — the wire first, then Wi-Fi, then the wireless
devices — so the width says how many there are without writing a number. With
none it goes: a struck-through icon would claim a fault, and being offline is
a condition.

- **One glyph is a round cell.** CELLS §11 gives the contracted cell a minimum
  of 64 px with a single glyph, and on the membrane that is a short bar with a
  small mark adrift in it — a cell that has lost its content. The configured
  minimum belongs to the composed form, where the width *is* the count; with
  one connection the cell is square around its glyph and reads as a pill like
  utility's. Akusen's call, 2026-09-22, against the figure in the handoff.
- **The header composes itself too.** The mark is whichever connection leads
  the row, so the glyph that was on the membrane a moment ago is the glyph the
  cell wears when it opens.
- **Two wells, two truths about choice.** The radio dot is on the Wi-Fi rows,
  where you are on one network at a time and the dot tells the truth; the
  devices have none, because several can be connected at once. A device says
  what it is with its glyph — headset, mouse, or the shell's own wireless mark
  for everything else — lit when connected and dim when only paired.
- **The switch turns the family off, not the well.** With the radio off the
  well stays, says so, and is still there to turn back on.
- **`components/Switch.qml` follows the value, never the press.** A radio takes
  a moment to answer; for that moment the knob stays where it is and the pill
  dims. A switch that snapped over and back would be lying twice.
- **`components/Strength.qml` is never state-coloured.** A weak signal is not
  past a threshold — nothing is wrong with a network that is far away — so the
  four bars are primary and the ones not reached are the same colour, faded.
- **The password is a field in the row, not a dialog.** The network being
  joined stays visible above what is typed, the list behind it is not covered,
  and a wrong password turns the outline to the alert colour and says why under
  it without taking away what was typed. The keyboard is asked for the way
  vitals asks: over the panel, and while a password is actually being asked
  for, because the pointer may leave while it is being typed.
- **The scanner belongs to the open panel.** It wakes the radio and costs
  power, so it starts when the panel is built and stops when it is destroyed.

Verified against the live machine: the cell shows the ethernet glyph alone with
the wire connected and nothing else on, the panel draws both wells and their
empty states, and with the radio briefly switched on — and put back
soft-blocked, as it was — the list fills with real networks, locks and strength
bars. The password field, the taps and the switches have never been pressed.

### Session, the five ways to leave

The smallest cell and the one with the sharpest edges. At rest it is the
avatar alone; open, the person above and the five commands below in the order
of gravity, each with its number.

- **`services/Session.qml` is new, and every command is a configuration key.**
  None of them is universal: a lock screen is a choice the machine's owner has
  already made, systemd is not the only init, and leaving the session is a
  different sentence on every compositor. The defaults are what this machine
  runs. Verified headlessly before the cell was drawn — login, full name from
  the GECOS field, the avatar found at
  `/var/lib/AccountsService/icons/<user>`, the five commands and which of them
  ask.
- **Nothing here opens the avatar file to see whether it is there.** The one
  thing that can say whether an image is readable is the thing that reads
  images, so the service publishes the candidates in order and whoever draws
  it reports a failure — AccountsService first, then `~/.face`.
- **Only the three that close programs ask**, and the question *is* the row:
  no dialog arrives from outside, nothing is covered, and the alert colour
  appears there and nowhere else. Colouring `SHUT DOWN` red at all times would
  make it invisible exactly when it matters. It is the same grammar as killing
  a process in vitals and keeping a recording — three cells, one way of asking
  "are you sure?".
- **This cell holds the keyboard for as long as it is open**, unlike vitals,
  which asks only over its own panel. One to five are part of the design —
  whoever opens this cell is often already on the keyboard — and five rows and
  a question are a short moment. While it lasts the window title says which
  cell has the focus rather than going out, which is what that rule is for.
- **Changing the avatar is in after all.** PRD §9.8 marks it optional because
  the picture has to be written over DBus rather than copied into place, and
  measured on this machine that is one `gdbus` call: `accounts-daemon` is
  running, `SetIconFile` is on `/org/freedesktop/Accounts/User<uid>`, the
  daemon copies the image itself, and `QtQuick.Dialogs.FileDialog` works in
  this build, so the picker is declarative. Verified end to end from the shell
  by writing the current picture back as an identical copy: polkit allowed it
  with no password, exit 0, and the file came out byte for byte the same.
  Akusen asked for it, 2026-09-22.
- **The picker is the desktop's, and that is an environment setting rather
  than code.** Qt's `FileDialog` asks the platform theme for a native dialog
  and draws its own when there is none; this machine runs `qt6ct`, which
  provides none, so what came up was Qt's — a dialog that looks like nothing
  else on the screen. With `QT_QPA_PLATFORMTHEME=xdgdesktopportal` the same
  call opens the portal's chooser, confirmed in a screenshot. `scripts/bioma`
  sets it for Bioma's process alone and is now the way to start the shell.
- **A new picture lands at the old path**, so the URL has to change or nothing
  reloads: the service bumps a revision into the fragment, which is dropped
  when the path is resolved.
- **One thing is still not here.** The silhouette for a user with no picture:
  the icon set has no person glyph, and the empty well is the honest shape
  until `user.svg` is drawn. An initial in a coloured circle is what the
  design forbids by name.

Verified on screen: the avatar loads, the name reads in Spectral over the
login in Orbitron, the five rows carry their glyphs and their key boxes, and
the shutdown row becomes the question with the alert outline and the one
filled surface in the shell that is not primary.

### The dock, one cell and not a tissue

The row of icons is its content the way digits are the clock's. If every
application were a cell the membrane would be ten glowing outlines in a row
and would have stopped being a membrane.

- **Kept on the left, running on the right, and never both.** A kept
  application that is running says so on its own icon with the ring rather
  than appearing twice, and the divider is absent when there is nothing on
  one side of it — a line that does not separate two groups is decoration.
- **The ring is flat primary, not the gradient**, and it sits inside the
  footprint: it is a thin state line and not a surface, and nothing moves when
  it appears. One ring however many windows there are.
- **A press raises, and raises the next one after that.** Two windows of an
  application are one icon, so the press cycles; the middle button starts
  another instance, which is the only way to ask for a second window of
  something that would otherwise just raise the first.
- **The name arrives above the icon**, in the pill the design gives the dock
  (§09) — and it is affordable here only because a membrane's surface is now
  the size of its output: the hover label that flickered on the cells was the
  surface resizing to hold it, and there is nothing to resize any more.
- **`left` is not a signal name.** An Item declares it final — it is one of
  its own anchor lines — and the compiler refuses it, which is the same trap
  `components/Band.qml` hit with `left` and `right`.
- **The right button keeps an application, or lets it go.** Neither CELLS §09
  nor the PRD gives the dock a gesture for pinning, and the settings cell is
  phases away, so it lives on the right button: one press, one effect, and the
  sign that it worked is the icon moving to the other side of the divider. It
  writes the desktop entry's own id where one resolves, so the list stays in
  the vocabulary the configuration is read in. Akusen asked how to pin one,
  2026-09-22, which was a fair question with no answer but a text editor.
  Verified by calling both functions from a throwaway timer: the override file
  gained `steam` and lost OBS, and the cell recomposed from the file without a
  restart.
- **Dragging a kept application reorders the row**, and the icon in the hand
  goes exactly where the hand goes. The first attempt rearranged the *list*
  while the drag was live and it read as nothing at all: rearranging moves the
  held icon too, which moves the frame the pointer is measured in, so the two
  chase each other and the icon crawls one neighbour at a time. Akusen said it
  was unclear and that it should cross more than one slot, and both were the
  same fault.
  - The list is left alone during the drag. The held icon leaves the row's
    arithmetic and follows the pointer — carried from where it was touched,
    not by its middle — the gap is a number the pointer's position divides
    out, so it can cross the whole row at once, and the others step aside by
    one slot, animated at the reflow. The list is rebuilt once, on release.
  - The pointer is measured **in the row, from the scene**. Measured through
    the icon it would stand still, because a pointer that carries an item
    keeps the same position inside it.
  - **Nothing is written until it is let go**, so a drag abandoned halfway
    leaves the file alone, and the write is refused unless the result is the
    same set of applications in a different order. This list is the user's own
    and is not worth losing to a bug in a gesture nothing here can perform.
    Both paths verified from throwaway timers: a reorder reached the file and
    the cell recomposed from it, and a deliberately mangled list was refused
    with the file untouched.

Verified on screen against the real graph: three kept applications resolve
their own icons, the two running ones that are not kept sit past the divider
with their rings, and the kept application that *is* running wears the ring
in place rather than appearing a second time.

### A shortcut is a cell, asked for by name

The compositor holds the keys and the shell holds the cells, and the whole of
the connection is `qs ipc call cell toggle <domain>`. No second model for
invoked surfaces: a shortcut asks a register for a cell of that domain and
toggles it, which is what makes PRD §5's "launcher, session menu and settings
are not a separate category" true in code rather than in prose.

- **`core/Focus.qml` keeps the register.** A cell offers itself when it is
  invocable and withdraws when it goes, so nothing enumerates cells by hand.
- **The cell reached is the one on the output the keyboard is pointed at.**
  The same cell exists once per monitor, and `Niri.focusedOutput` — the
  focused workspace's output — says which one is meant.
- **What the gesture does depends on what the cell is.** One that exists only
  when asked for arrives and opens together; one that is always on the
  membrane is already there, so the gesture is the opening. And a cell whose
  visibility is `invoked` goes when it is closed, however it was closed: the
  press outside that shut it is also the answer to "do you still want this?".
- **`config/niri/bioma-binds.kdl`** is the keybind file, ready to include, and
  the shell will say what it answers to: `ipc call cell list`.

Verified against the running shell: `list` returned the five invocable
domains, `toggle audio` opened the audio cell on the focused monitor and
`close audio` shut it — the first interaction in this project that has been
driven end to end without a pointer, because a shortcut is not a pointer.

### A tissue with no edge

`structure/Float.qml`: a tissue anchored to a corner or centred, over the
windows, ceding nothing. The three levels are unchanged — it is the edge that
is missing, so the tissue is placed by an anchor and a pair of margins instead
of a percentage of a strip, and there is no window line to hang an expansion
from but the one it works out for itself.

- **The surface is the size of the output and never resizes**, for the reason
  the membranes learnt: a layer surface that changes size draws its content
  twice for a frame. It reserves nothing, and outside its cells it claims
  nothing, with the same empty-region fallback until the first rebuild.
- **It registers with `Focus` exactly as a membrane does**, so the catcher
  subtracts its cells from the sheet that closes an open cell. Nothing in
  `Focus` needed changing: it asks a surface for its screen and its rectangles
  and does not care which kind it is.
- **A cell with no place of its own is summoned into one.** Akusen's rule,
  2026-09-22, and it is the one that makes the floating form free: a cell that
  is somewhere on this screen already — on a membrane, or in a floating tissue
  the configuration declares — is opened where it lives, and the invocation is
  the ordinary anchored opening. A cell that is nowhere has no place to be
  opened *in*, so it appears in the middle of the screen the keyboard is
  pointed at. Nothing has to be declared twice, and the `floating` block stays
  for the cells that want a corner of their own rather than the middle.
  - **One host surface per monitor**, empty until something is asked for, and
    the cell is built from a configuration of one line the way every other
    cell is built. It is opened when it arrives rather than when it is asked
    for, because it arrives a moment later; it is let go once it has finished
    leaving, because a cell cleared at the moment it closes takes its own
    closing animation with it.
  - **What is centred is the whole cell**, not the shape it grew from. A
    tissue knows where its pills are and nothing else, so a composition
    hanging off one of them left the pill in the middle of the screen and the
    panel somewhere below it. `Cell.reach` says how far a cell draws past
    itself on the side it opens, and a centred floating tissue is placed by
    the pill plus that. Akusen's correction, 2026-09-22.
  - **Only this monitor answers.** A cell of the same domain on the other
    screen is not the one meant: something opening where you are not looking
    is worse than nothing opening, and now there is somewhere for it to appear
    here.
  - **Asked for is asked for, whatever the visibility says.** A conditional
    cell that is not currently on the membrane still answers a shortcut: the
    person pressing it wants to see the thing, not to be told its condition is
    false.

Verified against the running shell, with the theme cell taken off this
monitor's membrane: `ipc call cell toggle theme` built it in the middle of
the screen — carousel, source switch and palette capsules, blurred and
shadowed at the floating depth — and the same call again put it away.

### A tissue runs the way it is pointed

A column advanced by the *width* of its cells, because the length of a cell
along a row is what it is granted and the same arithmetic was used both ways.
It never showed, since nothing had asked for a vertical tissue yet — the
notification column is the first, and it is a column of cells that are not
all the same size.

- **Along the tissue**: what it is granted on a row, its own height in a
  column. A cell in a column is granted the width it asks for rather than a
  share of anything: elasticity is about sharing a length, and the length of
  a column is its height, which no cell stretches along yet.
- **Across the tissue**: the height every cell shares on a row, and the widest
  cell in a column — a notification is not the width of a clock. Cells are
  centred across a column, because different widths against one edge read as
  ragged.

Verified with a floating column declared in the test layer: clock, audio and
workspaces stacked downward, each centred, the column as wide as the widest
of them.

## Phase 1 — Service porting

Nine of ten done, each verified headlessly through `probe.qml` before moving
on. Nine items, ten services: network and bluetooth are separate domains and
therefore separate singletons.

| Service | State |
|---|---|
| `services/Niri.qml` | Done. IPC socket event stream, 14 event types, actions. |
| `services/Wallpaper.qml` + `structure/WallpaperSurface.qml` | Done. Four modes, crossfade, persisted state. |
| `services/Matugen.qml` + `config/matugen/` | Done. Template-rendered palette, watched by Theme. |
| `services/Media.qml` | Done. MPRIS metadata, art, position, transport, player selection. |
| `services/Audio.qml` | Done. Devices, per-application volume, peak monitor. |
| `services/Brightness.qml` | Done. Backlight and DDC backends. |
| `services/Network.qml` | Done. Wired and Wi-Fi, native, no `nmcli` and no poll. |
| `services/Bluetooth.qml` | Done. Adapter, devices, pairing, native. Nothing taken from Prisma's page. |
| `services/SystemMonitor.qml` | Done. Load, memory, CPU clock, GPU, battery, processes. No process on the sampling path at all. |
| `services/Capture.qml` | Done. Stills, window capture through niri, text recognition, video with save or discard. The selection rectangle is now Bioma's own — the service raises a flag and `structure/SelectionSurface.qml` answers with a region. |
| `tools/sinestesia-bands` + `services/Sinestesia.qml` | Done. Capture and FFT in a process of their own, on Sinestesia's contract; the service reads the bands and folds them for whichever form the cell is in. |
| Notifications | **Next, and last.** See below. |

### Verified, and not

Everything above was checked against live state. Six gaps are known, and all
but the last two are missing hardware rather than missing work:

- **The backlight path of `Brightness.qml`** has only ever run against a
  fabricated `/sys/class/backlight` tree. This machine has no backlight. The DDC
  path is verified against both real monitors.
- **Joining a Wi-Fi network** — the radio, the scanner, the list and the
  security detection are all verified, but every network in range belongs to
  someone else, so `join`, `joinWithPassword` and the failure path have never
  run.
- **Every device-level bluetooth path**, including the battery scale, which is
  a documented guess. There is no paired device on this machine.
- **Everything battery**, in `SystemMonitor.qml`. There is no battery here, and
  UPower's percentage scale is deliberately left raw rather than converted on a
  guess (§16.6).
- **The drag inside Bioma's own selection rectangle.** The surface is written
  and comes up; nothing here can draw a rectangle with it.
- **`structure/Visibility.qml`** has no test at all. It is the heart of the
  temporal grammar and the first cell will be its first exercise.

### What the notification cell already owes

Asked for while using the capture cell, and recorded here so it is not
rediscovered later: **a capture that succeeded has to say so.** A screenshot is
instantaneous and leaves nothing on screen — the file is written, the clipboard
is set, and the shell says nothing at all. That is the notification cell's job
(§10) rather than a second state of the utility cell, and it is the first real
consumer of it: image, text and video each end with something worth announcing,
and the video's announcement is the one that carries a path.

### Before notifications can be touched

`org.freedesktop.Notifications` has one owner per session, and on this machine
that owner is **Noctalia**, which is the running shell. It also holds
`org.kde.StatusNotifierWatcher`. It has to be switched off first, and that is
the point of no return the PRD describes.

Checked on 2026-09-18, so the cutover does not have to be worked out from
scratch:

| Fact | Value |
|---|---|
| Owner of both bus names | one process, `noctalia`, pid 1776 at the time of checking |
| How it starts | `spawn-at-startup "noctalia" "-d"` in `~/.config/niri/config.kdl`, with `include "noctalia-binds.kdl"` on the next line |
| Parent | `systemd --user` — niri spawns it detached, so killing niri's child does not help and there is no user unit to stop |

The cutover is therefore: comment out those two lines in the niri config, kill
the process, and start Bioma in its place. The keybind file goes with it, which
means every shortcut the machine currently has for a shell stops working at the
same moment — worth doing when there is time to finish, not at the end of a
session.

Confirm the names are free before writing the cell:

```sh
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus GetConnectionUnixProcessID s org.freedesktop.Notifications
```

## How to check the state of things

```sh
qs -p "$PWD/probe.qml"      # every service, headless, no surfaces
```

Allow six seconds: DDC detection alone costs three and a half.

The probe reports the Wi-Fi radio as it finds it and never turns it on. The
scan path was verified with a throwaway probe that toggled the radio through
`Network.setWifiEnabled` and put it back; it is not kept in the repository,
because a file that flips the machine's radio as a side effect of being run is a
trap. Rebuild it from §15.6 if the Wi-Fi path needs checking again.

`scripts/mpris-dummy.py` publishes a silent MPRIS player for testing the media
service; run two with different `--name` values to exercise player selection.

## Decisions taken since the PRD was written

Recorded in full in `services/INVENTORY.md` §9–§17. The ones that change the
plan rather than an implementation detail:

- There is no `Quickshell.Niri` module. The compositor service reads niri's own
  IPC socket, and is richer for it (§9.1).
- Battery, bluetooth and wired networking are native in Quickshell 0.3.1, so
  three items the inventory called new work are mostly not (§9.2).
- Per-application volume is far less work than the PRD estimated; the expense in
  that cell is its interface (§13).
- Sinestesia's visibility condition needs no capture and no FFT —
  `PwNodePeakMonitor` gives the signal directly. The split of Sinestesia is still
  required for the bands the visualiser draws (§13.3).
- The palette goes through a matugen template, so format drift lands in a text
  file rather than in the shell (§11).
- §9.4's trap has a second half: a bound property is still at its default for an
  instant after binding, so a function that *gates an action* on one silently
  does nothing. Properties display state; they do not decide whether to call the
  backend (§15.1).
- Prisma's Wi-Fi signal bars were wrong — `signalStrength` is 0–1, not 0–100 —
  which is worth knowing as a measure of how much of Prisma to trust on sight
  (§15.2).
- The vitals sampler needs no persistent process either: `FileView` reads
  `/proc` and `/sys` directly, so the shell spawns nothing to sample the
  machine. `reload()` is asynchronous, though, and reading the text back
  immediately returns the previous sample — a third instance of the same trap
  (§16.1).
- Capture is bigger than §8 assumed. Prisma has no clipboard, no destination
  folder and no recorder, so only two command lines were ported; and a window
  cannot be captured with `grim` at all, because niri reports no window
  position — the compositor does it by id instead (§17.1).
