# Progress

Where the work stands. `services/INVENTORY.md` holds the detail and the
reasoning; this is the short version and the list of what is *not* done.

Last worked: 2026-09-24.

## Where to pick up

Phases 0 to 4 are done and phase 6 with them: the engine, ten services, and
fifteen cells — the last of them notifications, with the bus taken off Noctalia,
and the launcher in both its forms. Phase 5 is done: all five settings pages.

Akusen has been driving the whole shell by hand since 2026-09-22, and most of
what is written below the fold came out of that: the settings cell, the
structure page, and a run of engine defects that only a pointer could find.

What is left, in the order it is worth taking:

Nothing in the build order is left, and the first list of features after it
is done too (2026-09-23): the on-screen display, the opened clock, Bluetooth
search and pairing, VPN profiles set up from the panel, a proxy that follows
the networks, the session cell become System with the machine's description,
and the clipboard cell. Since then the palette reaches niri and the
applications (the palette, outside the shell). Each has its section below.

What those left unverified, because nothing here could drive it: pairing a real
Bluetooth device, a VPN that actually connects, a proxy switched through by a
real Wi-Fi network, and the conditions of the tray and connectivity cells.

What CELLS left open in the cells already drawn is closed, except Sinestesia
on a narrow screen and under reduced motion, which wait by Akusen's call
(2026-09-23), and the system-wide OSD, which is one of the features that come
after. A long window title was never open: §01 says ellipsis, never scrolling —
scrolling on hover is the track title's, in Sinestesia.

The PRD's open question — whether there is a tray cell at all — was answered
yes on 2026-09-22, and it is built; see below.

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

- **the Monitors page's drag**, and a press on its Primary switch. The drag
  was driven by calling the handler's own functions from a timer; a real
  pointer has never carried a rectangle.
- **the Keybinds page's presses**: the pencil, the cross that removes a bind,
  the dashed chip, and a row of the picker. Everything *after* a press was
  driven with a synthesised keyboard (see below) — but the press itself came
  from a throwaway timer.

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
| `cells/clock`, `cells/window_title`, `cells/workspaces`, `cells/vitals`, `cells/theme`, `cells/utility`, `cells/recording`, `cells/sinestesia`, `cells/audio`, `cells/connectivity`, `cells/system`, `cells/dock`, `cells/notifications`, `cells/launcher`, `cells/settings` | Fifteen cells. Vitals opens into pods, threads and the process list; theme into the wallpaper carousel and the two palette capsules; utility into the capture panel, and generates the recording cell. |
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

### The cutover, and the notification cell

2026-09-22. `spawn-at-startup "noctalia" "-d"` is commented out in
`~/.config/niri/config.kdl`, the process is stopped, and Bioma took
`org.freedesktop.Notifications` **without being restarted**: Quickshell's
server retries registration when the name is released, which it says it will
do in the warning it prints while another shell holds it.

- **`noctalia-binds.kdl` is still included, deliberately.** Nineteen of its
  binds call `noctalia msg …` and now do nothing; four of them are the
  terminal, the file manager, the browser and Sinestesia, and those are not
  Noctalia's to take away. They stay until each is moved somewhere of its own.
- **What went with it**: the tray, because `org.kde.StatusNotifierWatcher` was
  Noctalia's and Bioma has no tray cell; its clipboard panel; its OSDs. None
  of them is in the catalogue, and the tray is the one worth deciding about.
- **`services/Notifications.qml` is the server plus everything Prisma never
  had**: urgency read and obeyed — four seconds for low, eight for ordinary,
  and a critical one does not leave by itself, which is the convention Prisma
  broke by dismissing everything after four — a queue with a cap of twenty in
  ten seconds that collapses into a count past it, a clock the pointer stops
  and that resumes where it stopped, and a history that groups by
  application. Do not disturb lives with the history, against the PRD and with
  CELLS §10: it is looked for when notifications are bothering somebody, which
  is when they are looking at this cell.
- **A cell can open without claiming attention.** One cell is open at a time,
  and that rule is about attention rather than surfaces — a body that appears
  under the pointer has not been asked for, so `Cell.claimsFocus` is false
  while the notification is merely hovered and true when its history is
  pressed open.

Two things the first parade of real notifications found:

- **Quickshell hands the sender's icon over as `image://icon/<name>`, and its
  provider answers a name it cannot find with a chequerboard** rather than
  with nothing. `dialog-warning`, which this icon theme does not carry, was
  drawn as a missing texture on the membrane. A named icon is checked before
  it is believed now, and the cell's own glyph takes over when it is not
  there — never another application's logo, which is what resolving a free
  text app name would have given.
- **A critical notification has no clock, so on the head of one queue it
  stopped every other notification** for as long as it went unanswered —
  the one thing §10 says must not happen. Urgency wins the cell and the
  ordinary ones do not queue behind it: they are kept and they are in the
  history. Going past it *visibly* needs this cell to be a column of cells,
  which is the vertical tissue's next job.
- **Interaction suspends disappearance, but only while there is something to
  interact with.** Dismissing the last notification with the pointer still on
  the cell left an empty pill sitting there until the hand moved: the rule
  protects what somebody is reading, and there was nothing left to read.
  `Cell.engaging` is how a cell says it has emptied, and the hover stops
  holding it. Akusen saw the empty pill, 2026-09-22.
- **An outline that belongs to the cell is drawn by the cell.** The urgent
  ring was declared in the notification cell, so it landed in the content
  slot — which is inset by the cell's own padding — and what appeared was a
  smaller pill inside the real one, a shape that matched nothing. Same trap
  as the tap and the wheel before it: `Cell.outline` now draws it on the
  cell's own geometry, and a cell says which colour rather than where.
- **And it needed a way to be answered.** A notification with no clock and no
  gesture to close it is a trap: the middle button dismisses, as it does
  everywhere else in the shell — the gesture that acts without opening
  anything. Akusen asked for the visible half of it too, so the cell carries a
  close mark on its right, always: a way out nobody has to be told about. It
  takes the press with a mouse area rather than a handler, because a handler
  would dismiss the notification *and* let the press reach the cell, which
  would open the history of something that had just gone.

Verified on the live bus: an ordinary notification arrives with the sender's
own icon and leaves when its dwell runs out; a critical one arrives with the
alert outline and stays; an ordinary one sent while it is up goes to the
history instead of queueing behind it. The hover body, the actions, the
history and the middle button are drawn and have never been pressed.

### The keys that are not cells

Switching the old shell off took the media keys with it: volume, mic mute,
brightness and the transport were all bound to `noctalia msg …`, and that
daemon is gone. Bioma's own services had answered for all of them since phase
1 and nothing had ever asked.

- **`scripts/key` is what a binding runs**, and it sends each one to whichever
  shell is running. A key that works under one shell and not the other is a
  key that is broken half the time, and the session goes back and forth while
  this one is being built. Noctalia's copies of those binds are commented out
  in its own file, because two bindings on one key is not a thing to leave
  lying around — and a note there says so, since it may rewrite the file.
- **A service nothing reads has never started.** Quickshell's singletons
  initialise on their first property *binding*, not on first access, so
  `brightness up` stepped from nothing and answered `0%`: no cell reads
  brightness yet. Three bindings in `shell.qml` start audio, brightness and
  media, which is what lets a key work before the cell for it exists. The
  oldest lesson in this project, found again from the other end.

Verified on the machine: volume down and up either side of 40%, mute and
back, brightness 50 → 55 → 50 over DDC on the real monitors.

### The launcher, which is the mechanism and nothing else

The last of the catalogue, and built last on purpose: by the time a launcher
exists, everything it needs has to work already — a cell asked for by name,
given somewhere to be, holding the keyboard and giving it back. There is
almost nothing in the file that is not one of those.

- **It is the first cell that is not a pill.** Every other one is a shape of
  one height because a membrane is a row of them; this is a field and six
  rows. `Cell.bodyHeight` is how a cell says how tall it is, and a tissue now
  makes room for the tallest it holds and centres what is shorter — the same
  rule a column already had for the widest.
- **It needs no configuration at all.** Nothing declares it anywhere: it is a
  cell with no place of its own, so asking for it by name is what builds it,
  in the middle of the screen the keyboard is pointed at.
- **A floating tissue asks for the keyboard *exclusively*, which a membrane
  never does.** On-demand means "the compositor may focus this surface", and
  niri does that when the pointer crosses it or a press lands on it — a cell
  summoned by a shortcut has had neither, so the launcher came up and
  swallowed nothing. Exclusive is the layer-shell way of saying the keys are
  mine while I am here, which is what an invoked cell means; the selection
  rectangle already did it so that Escape cancels a capture.
- **Placed, not open.** The first ask was for cells that were *open*, and
  this cell never opens: it has no panel to grow, it *is* the panel. Which
  also means it claims the shell's attention directly when it is summoned, or
  the sheet that closes an open cell would not know it was there and a press
  outside would leave it standing.
- **It grows from its own centre**, and getting there took three wrong
  answers and one measurement. The first guess — animate the height as well
  as the width — changed nothing; the numbers said why. A floating tissue was
  animating *its own* size while the cell inside it was already drawn at full
  size, so the cell sat in the corner of a band that was still growing and
  slid across the screen with it. That is the entrance Akusen saw coming from
  the bottom right, twice.
  - A floating tissue does not reflow: what it holds arrives and leaves
    whole. The band is placed at its final size and the **cell** grows.
  - A summoned cell grows into place from 0.82 in both measures, translated
    by half of what it has not grown yet — the tissue puts a corner somewhere
    and a corner is not a centre. Translating, never scaling: the rim keeps
    its weight and the text its size.
  - And the reflow `Behavior` had to be let out of the way. It smooths every
    change, growth included: two hundred and twenty milliseconds chasing a
    value that moves in two hundred and fifty leaves the shape standing at
    full size while the number underneath it travels. Measured, not guessed —
    `emergence` was animating and `width` never moved.
  - The content waits for `Cell.grown`, so a field is never drawn into a
    shape that is still moving.
- **Its height is fixed, and that is the whole of it.** A panel that grew and
  shrank with the number of results re-centred its tissue on every letter
  typed, and the blur region chased a shape that had already moved: the field
  jumped under the fingers and the glass tore. The design says it plainly —
  with nothing found the field stays where it is and the panel does not
  collapse under your fingers — so six rows is what it always holds, full or
  not. Akusen saw the jumping, 2026-09-22.
- **The matched letters are lit.** It is the one place in this shell where
  colour enters a word, and it earns it: it shows the search's reasoning, so
  a wrong answer is visibly wrong rather than broken. Built as markup,
  because a `Text` can colour a run of characters and still elide.
- **`escape` is not a name QML will take for a method** — it is a JavaScript
  global, and the compiler calls it an illegal method name rather than a
  clash.

Verified on screen: `ipc call cell toggle launcher` builds it centred, the
field takes the caret, six rows of applications with their icons, the first
one selected with the primary fill and its icon ringed. Typing, the arrows
and Enter have never been pressed.

### The launcher, anchored as well

Akusen asked for the button form — some people would rather have something to
aim at than a shortcut to remember — and drew its glyph. The body moved into
`cells/launcher/LauncherBody.qml` and both forms wear it: summoned, the cell
*is* the panel; on a membrane, the cell is a forty-pixel button and the same
body hangs off it as an ordinary expansion. What changes is where it is born.

- **`Cell.floating` is how a cell knows which of the two it is being asked to
  be**, passed down by the tissue that holds it.
- **A panel may be told its size.** `Panel` measures its content, and content
  that arrives through a loader has no size at the moment it is measured — so
  the shape stayed too small for what came. `Cell.panelWidth` and
  `panelHeight` state it instead.
- **`setSource` loads whether the loader is active or not.** It was used to
  hand the cell over at construction, and it built the panel form's body
  inside the button form as well — twenty pixels wide, its rows hanging down
  the screen under the button. A plain `source` binding does not.
- **The doubled glyph and the stray text were one mistake, and it was mine.**
  When the body moved into its own file the new file was written and
  `Launcher.qml` was **not** rewritten without it: the cell carried two
  bodies, the new one in a loader and the old one inline in the contracted
  slot, twenty pixels wide. That drew a second lens over the cell's glyph —
  the "doubled icon" — and hung a field and six rows down the screen beside
  the button. Removing the leftover fixed both at once.
  - It took three wrong explanations first: a blur artefact, the window
    behind, a leaked cell. The one that settled it was changing the
    placeholder text to a nonsense word and seeing "Search" stay — which
    ruled out the file I was editing and pointed at the *other* copy. Grep
    for the literal, not for the theory.
  - On the way, one real improvement: `shell.qml` holds the membrane and
    floating models still. `Config.get` answers with a fresh array every
    time, and a `Variants` model that changes identity is a model that
    changed, so the delegates were rebuilt on every read.

### Settings, two pages of five

The mark, and the only place it appears. Five category capsules with the thread
leaving the chosen one and feeding the panel — **the selection *is* the
thread**, which is CELLS §12's decision and applies to every two-level case
after it. The panel is as wide as its category asks and always the same height.

Written: **Appearance**, which is the five numbers the whole shell is drawn
from — cell opacity, radius, and the screen edge, tissue and gap margins — plus
blur, the density step and the timing set. Every row writes into the override
layer and every surface is bound to it, so a slider moved here is the desktop
changing under the hand; there is no apply button because there is nothing to
apply. **Cells**, one row per cell in the catalogue with its visibility as a
small segmented control, and the options a cell cannot wear left in the track
and dimmed.

Structure, Monitors and Keybinds say "Not built yet" rather than showing an
empty panel. The last two write niri's own configuration, which is why they are
last.

- **The cascade's span depends on how many shapes are in it.** Every expansion
  carried the same line — `grow + stagger * 2` — which is right for three
  shapes and wrong for seven: the settings panel's last two capsules never
  finished growing, so they sat half-size and textless for as long as the cell
  was open, and the page with them. The arithmetic moved to `Timing.stage`,
  which is told the count; the four expansions that had a copy now call it.
- **`Registry` learned to speak about cells, not only build them**: a name for
  each domain and which visibilities it can wear. A settings page that knew
  those itself would be a second catalogue to keep in step.
- **One row per cell means every declaration of it changes.** The same cell on
  two monitors is two blocks in the configuration, and a clock always visible
  on one edge and invoked on the other is not a setting anybody asked for.
- **What is written is the list, not the key.** A membrane list is one value to
  the merge — arrays replace, they never append — so the whole array goes into
  the override with one word changed. Verified with a throwaway timer that
  wrote `clock` to `invoked` and back: the other keys of the override, the
  `$comment` included, came through untouched.
- No heading inside the panel: the capsule the thread leaves from already says
  which category it is, twenty-four pixels away.

Verified on screen, both pages, on the bottom membrane of DP-1. Nothing here
has been pressed by hand — the capsules, the sliders and the segmented controls
are drawn and bound, and the writing path was checked without a pointer.

Akusen drove it and found four things, 2026-09-22. Three of them were the
settings cell telling the truth about a shell that was not listening:

- **Two keys for one margin.** The tissue-to-cell distance is `tissue.padding`,
  read in four places, each repeating the 2–12 clamp; `appearance.tissue` was a
  second key for the same distance that nothing read, so the row moved nothing.
  One key now, clamped once in `Metrics`, and the three places that re-read the
  configuration ask `metrics.tissuePadding` instead — which also means the
  margin scales with the density step, as a density value should.
- **The gap between shapes was a literal in three expansions.** Vitals, theme
  and sinestesia each wrote `24 * factor` rather than `metrics.gap`, which is
  the token the row moves. That is the rule about durations, applied to a
  distance: the value comes from the set or it is not the value.
- **Scale is a membrane's, and there is no global one to write.** The row was
  writing `appearance.scale`, which nothing reads — every membrane block
  declares its own. It writes the membranes now, all of them together; the
  per-membrane choice belongs to the Structure page, beside the edge it applies
  to.
- **The switch's knob sat high.** Two pixels of inset against a 24 px pill
  holding a 16 px knob. The inset is what is left over now, so the same figure
  holds it off the top, the bottom and the end.

And two things it was missing rather than lying about: the cell now wears its
header when open — the mark and the name, like every other cell — and lists
that are longer than their room say so. The scrollbar was written out by hand
in four cells, twice as a file-local `component Scroller` and twice as a bare
`Rectangle`; it is `components/Scroller.qml` now, and the settings catalogue
and the launcher's results have one too.

### Asking for a cell that is already on the membrane

`ipc call cell toggle workspaces` looked like it did nothing. It did: it built
a **second** workspaces cell in the middle of the screen, where I was not
looking, and left the one on the membrane shut. Two engine faults under it,
both about a cell that is somewhere already.

- **The register held only the cells whose block said `invocable`.** Everything
  else was, as far as a shortcut could tell, nowhere — so asking for it summoned
  a copy into the floating host. Every cell is in the register now, and
  `Focus.cellFor` ranks the answers instead: a cell that exists only when asked
  for, then one that says it answers, then one that is merely on screen. A cell
  that is neither declared nor currently shown is not an answer at all, and that
  asking still gets the summoned copy — which is what the host is for.
- **A floating tissue was deriving a window line from its own position.** There
  is no line to hang from on a floating surface, and `Float` invented one from
  `tissue.y`; the tissue's `originGap` came out of it, the cell's `gap` out of
  that, `Cell.reach` out of that, and `Float` places a centred tissue by
  `reach` — a circle, logged twice on every open as a binding loop on `reach`.
  A floating tissue uses `metrics.gap` now and is given no window line.

Also quieted: `LauncherBody` read its measurements straight off the cell, which
a Loader hands over only after the body exists, so every summon logged a page
of "cannot read property of null". They come through guarded properties now.

### One radius for the whole shell

`appearance.radius` moved the cells on the membrane and nothing else: every
panel, capsule, well, row and control carried its own `height / 2` or its own
literal, so at 40 % the shell had square cells with round capsules inside them.

The percentage lives in `Metrics` now — `radiusPercent` and `shaped()` — and
`radiusFor()` and the `radiusPanel` / `radiusWell` steps pass through it, which
carries most of the shell on its own. The rest was a sweep: every container
radius written by hand now asks `Metrics.radiusFor` for a pill or
`Metrics.shaped` for a literal. Verified at 100 (identical), 40 and 0.

What deliberately does **not** follow it is what is round because of what it
is: the avatar, the dial and the gauge, the radio marks, the workspace rings,
the thread's nodes, the sound bars. Those are drawings, not surfaces, and an
oval avatar is a defect at any setting.

Also taken out on the way: `ThemeCell`'s chips anchored to a parent a `Row`
gives them and takes away, which logged "cannot read property verticalCenter of
null" on every rebuild.

### A band has a floor as well as a ceiling

Akusen's window title was not on the HDMI membrane: its band was granted 20 %
of 1920 px and held a clock, the sound cell, the dock and the title, so the
title — elastic, and therefore the one that gives way — was never placed. The
band is 44 % there now, the corner one 16 %, and the title is back.

The general half is the one that matters. A tissue now knows what it was asked
to hold: `Registry.minimums` is each cell's own floor, `Metrics.roomFor` adds
the gaps and the tissue's margins, and `Tissue.required` / `fits` answer for a
live band. The membrane checks every band once the surface has settled and
warns in the unit that fixes it — "tissue 2 holds 4 cells and needs 12 % rather
than 5 %".

`Registry.roomFor` answers the same question for a **list of cell blocks**,
which is what the settings cell needs: the Structure page has to refuse a cell
that would not fit before the cell exists, rather than let somebody build a
membrane with cells missing from it. Conditional cells count — a band that fits
only while the notification is away breaks when one arrives.

### The tray, which the PRD left open

Sixteen cells now. `Quickshell.Services.SystemTray` is a StatusNotifierItem
host, and the protocol allows several hosts on one watcher — unlike the
notification bus, which has one owner — so this was safe to build with another
shell still startable.

Verified through `probe.qml` before the cell existed, as every service is:
three items live on this machine (a package updater, Steam, Telegram), each
with an icon URL, a category, a status and a menu.

- **The content is not ours.** An application hands over an icon drawn in its
  own style — PRD §6.4 says they stay that way whatever we do — so the row
  adds one thing only, which is the shell's to say: a ring on the item asking
  for attention, in the alert colour, and the same ring in the primary on the
  one whose menu is open.
- **The gestures are the protocol's.** A press activates, the middle button is
  the secondary action, the wheel scrolls, and an item that declares
  `onlyMenu` gets its menu rather than an activation it says it does not have.
  The right button always asks for the menu.
- **The menu is drawn in the shell's hand**, from `QsMenuOpener` — the same
  well, rows, separators and marks as everything else the shell lists. A
  submenu replaces the list with a way back rather than opening a second
  capsule: a menu is already a digression.
- **A name the icon theme does not have** is a chequerboard from the image
  provider rather than a failure — the notification cell's lesson — so a name
  is asked of `Quickshell.iconPath` first and the glyph stands in when it
  answers nothing. A URL that carries its own `path=` is trusted as it stands.

### What a condition means depends on the domain

The window title stayed on an empty workspace as a pill with the fallback icon
and no text. The condition was lapsing correctly — measured, `focusedWindowId`
went to -1 and the condition to 0 — but the block, written by the settings
cell, named no `dwell`, and the engine's generic figure is two seconds. Two
seconds of a cell with nothing to say is exactly what the silence rule forbids.

A conditional cell is not conditional in the abstract. `Registry.grammar` holds
what a condition means per domain — the figures `config/default.json` already
shipped — and a block that names none now falls back to its own domain's:
the window title goes in 200 ms, a recording the moment it stops, sinestesia
takes four seconds to be forgotten. The settings cell writes the same figures
when it adds a cell, so a block is still self-describing.

(The same pass found that `SettingsStructure.addCell` was calling a `ruled`
that lives in `SettingsCells` — it has its own now.)

### What a cell claims is not what it draws

The notification's actions could not be reached: the pointer left the pill to
go to them, and the cell — which lives in its hover state — closed under it.
Two reasons, and the second is a rule the engine was missing.

- **A cell's hover ended at its own edge.** An expansion and a panel hang
  outside the cell's item, so the pointer standing on the body was, as far as
  the cell knew, nowhere. `Cell.touched` is the pill, the panel, the expansion
  and the gap between them, and it is what suspends disappearance now.
- **A surface only receives what its mask claims, and the gap is not drawn.**
  Between the pill and what hangs off it there is the thread's gap: claiming
  it would blur a rectangle of glass with no shape in it, so it was claimed by
  nobody and the pointer fell through halfway down. `Cell.claims()` is the
  input side of `shapes()` — the same list plus the gap — and the membrane and
  the floating host now mask what is claimed and blur what is drawn.

The history panel also counted only its rows: the well and the list have
margins of their own and the rows carry an application label every few, so a
panel that promised seven rows held five and had nothing left to scroll in. It
counts all of it now, from the same figures the well and the list are drawn
with.

### A cell that is closing is still on screen

Akusen: only the launcher closes properly. It is the one summoned cell with no
expansion — which is what pointed at the rule the others were breaking.

`shown` goes false the instant a cell is dismissed, and everything that places
or measures a cell was reading exactly that, while the composition hanging off
it takes the whole closing time to retract. Measured on a summoned vitals at an
eighth speed, at the frame of the dismissal:

- the tissue's width fell from 314 to 4, because the cell no longer counted;
- `Float.reach` fell from 396 to 0, and the tissue's y went from 500 to 698 in
  one frame — carrying the retracting composition two hundred pixels down the
  screen, which is the "something appears in the middle and goes away";
- the pill itself faded out from under its own expansion, and its header went,
  which narrowed the tissue again and moved it sideways.

So: a cell counts for its tissue while it is `shown`, **expanded or leaving**;
`Float` measures its reach the same way and holds the last figure while the
cell is leaving, because the expansion unloads a frame before the departure
starts; the pill keeps its opacity and its header until the last of the
composition has gone. Measured again afterwards: the tissue stays at 1563, 500
and the reach at 396 from the open through the retraction and the shrink, and
nothing moves but what is meant to.

### And the cell has to wait for what hangs off it

With the curve fixed, the closing still read wrong: the pill snapped back to
its contracted width the instant the cell was closed, while the whole
composition was still on screen. An expansion is placed against the cell's own
edge, so the shapes were dragged sideways as the pill narrowed under them, and
what was left at the end was one pod on its own in the middle — Akusen's
"something appears in the middle and then goes away".

The header now stands while the cell is **expanded** rather than while it is
open: the shapes retract into a pill that is still there, and the pill returns
to its contracted self once the last of them has gone. Which is the opening,
backwards: the pill widens first and the composition grows out of it.

### The opening curve run backwards is not a closing curve

Every expansion drove its cascade with `easeOpenFlat` in both directions. That
curve starts fast and ends slow, which is what opening wants — and backwards it
means the shapes fall out of the composition in the first fifty milliseconds
and then crawl the rest of the way. Akusen saw it on audio and vitals.

Measured at quarter speed, closing: the cascade went 1.00, 0.87, 0.49, 0.27,
0.14 while the cell's own thread and panel went 1.00, 0.99, 0.96, 0.92, 0.86.
Two different closings in one movement. With `easeClose` the cascade now tracks
the cell exactly — 0.99, 0.96, 0.92, 0.86 — which is the whole point of having
one timing set.

Fixed in all six expansions: audio, vitals, theme, session, sinestesia and
settings.

### A summoned cell leaves the way it arrived

There was no closing animation on the floating cells at all: they were there,
and then they were not. Three things, each of which was enough on its own to
delete the movement.

- **The cell had no departure.** The arrival is an animation of its own —
  Behaviors do not run on a first value — and nothing was its mirror.
  `Cell.depart()` shrinks it about its own centre and fades it over the
  closing time, and says `gone` when it has.
- **Whoever summoned it dropped it on the spot.** `Float` cleared `summoned`
  the moment the cell was dismissed, which destroys it; it asks the cell to
  leave now and clears when the cell says it has. `Focus.invoke` and
  `Focus.retire` ask the host to retire rather than to dismiss.
- **The tissue went before the cell did.** A tissue is invisible when it holds
  nothing placed, and a dismissed cell stops being placed immediately — so the
  container vanished and took the leaving with it. It stays while anything in
  it is on its way out.

Two more came out of driving it, and the first is the one Akusen saw: the cell
**moved** and then vanished.

- **The tissue measured itself without it.** `tallest` and `widest` count what
  is *shown*, and a dismissed cell is not — so the container shrank around the
  hole and carried the cell, still drawn, somewhere else. A cell on its way out
  now counts for everything the tissue measures: what leaves, leaves from where
  it stood.
- **And it was not shrinking at all.** The width and height Behaviors stand
  aside for the arrival — a reflow smoothing a value that moves faster than it
  does leaves the shape standing still — and nobody had told them about the
  departure. Same gate, both animations.

Measured frame by frame at quarter speed: 480 × 382 down to 394 × 313 with the
centre fixed at 960, then hidden and let go.

### The order of a band is dragged, not retyped

The cells in a band sit in the order they are declared, from the anchor inward,
so changing that order is changing the layout — and it is changed the way the
dock's icons are: pick a chip up and carry it. The gap follows the pointer and
crosses as many slots as the hand does; the others travel to where it leaves
them; the list is written once, on release, and refused if the result is not
the same cells in another order.

The chips are uniform and laid out by hand rather than by a `Flow`, for the
reason the dock found first: a row that positions its own children cannot have
one of them follow the pointer. Equal widths also make "which slot is the hand
over" one division rather than a search, wrapping included — the grid is
`perRow` wide and the dashed add-chip keeps the slot after the last cell.

Verified without a pointer, by calling the same three functions a drag calls:
`[vitals, settings, utility]` carried from slot 2 to slot 0 came out
`[utility, vitals, settings]` in the override, and nowhere else changed.

### Regions are rectangles read at one moment, and the moment has to be the last

Akusen kept losing the settings cell: the first presses on a control near the
right of the panel closed it instead. The catcher punches its holes as
rectangles read when it builds them, and **everything the shell draws
animates** — so the hole was the panel mid-growth, 567 px wide where the panel
finished at 644, and a press in the seventy-seven pixels that arrived last
reached the catcher.

Bumping on `reach` was not enough: an expansion grows *inside itself*, through
a cascade the cell cannot see, and a page that widens from one category to the
next animates a `fixedWidth` no property of the cell follows. So a cell now
says once, a beat after anything that moves its shapes, that they have settled
— `Cell.shapeRevision`, on a timer of `reflow + 80`. Measured: the hole for the
settings panel is now 440 × 420 on Appearance and 644 × 420 on Structure, which
is what is drawn.

The same read explains the reveal that never came back. An auto-hidden membrane
claimed two pixels at the screen edge; the moment the pointer called it out,
the mask became the cells — which sit a frame margin above that edge — so the
membrane stopped being hovered the instant it appeared and began hiding again
under the hand. Revealed, it claims the whole band it occupies, and the strip
sits above the sliding content rather than under it, where the pointer could
not reach it at all.

### Two things a membrane that outlives its configuration exposed

Keeping a membrane across a configuration change — which is what stopped the
settings cell closing on every edit — brought out two things the rebuild had
been hiding.

- **Auto-hide stopped answering.** `revealed` starts as a binding on
  `autoHide`, and the pointer reaching the edge *assigns* it, which ends that
  binding for good. It used to be re-established every time the membrane was
  rebuilt; now the membrane stays, so switching auto-hide on has to be
  answered explicitly. It is, and it waits for the hand to leave rather than
  vanishing under it.
- **Pressing a control closed the cell instead.** The full-screen catcher
  punches its holes as *rectangles*, read at the moment it builds them, and a
  panel that changes size while it is open never said so: the settings cell is
  440 wide on one category and 644 on another, so a press in the part of the
  panel that grew reached the catcher and dismissed the cell. The tissue now
  bumps on `reach` and `reachWidth` as well, which is exactly "what this cell
  draws changed size".

### A hidden membrane blurs nothing

Akusen put the dock on an auto-hiding edge: the membrane slid away and left its
silhouette behind, blurring the window underneath it. The cells are still there
when a membrane hides — a transform on their container takes them out of view —
and a `Region` bound to an item does not follow that transform, so the blur
region went on describing where the cells would have been. Hidden, the membrane
now blurs nothing at all; the input mask already kept only the reveal strip.

### Settings: Structure, the third page of five

Six slots drawn where the bands will be — three on the top membrane, three on
the bottom — with the monitor chosen above them. An unlit slot is dashed;
pressing it lights a tissue there and choosing it opens, on a thread, what is
in it: the width as a percentage, and the cells as chips with a cross. The
dashed chip opens the picker on a second thread, listing only the cells that
are not in that band already.

- **The page refuses rather than breaks.** A cell that would not fit stays on
  the list, dimmed and saying "no room", and the width slider stops at the
  percentage its own cells need, with that figure written beside it. Both come
  from `Registry.roomFor`, so the page and the membrane's own warning are the
  same arithmetic.
- **Slots are positional, so anchors are written out.** The engine derives an
  anchor from a tissue's place in the list; a page that draws three slots
  cannot, or lighting the middle one alone would make it the last and therefore
  the end. Every tissue the page writes carries `anchor`.
- **Emptying a slot switches it off**, and a membrane with no tissues left goes
  with it: a surface with nothing on it is not a membrane.
- **`Config.set` now says so out loud.** Most of the shell reads the
  configuration through bindings and follows `values` by itself, but what is
  *built* from it — the membranes and floating tissues in `shell.qml` — waits
  for `reloaded()`, and the file watcher does not report our own atomic write.
  A membrane added from the settings cell stayed unbuilt until the next start;
  now the surface appears as the slot lights.

Verified by driving the page from throwaway timers: lighting the centre slot of
DP-1's top edge, adding the clock and vitals to it, and watching the membrane
appear on screen with both cells in it. Then taken back out.

Akusen used it and found two things, 2026-09-22. A band could be lit and never
put out, so the chosen slot carries the cross that switches it off — on the
chosen one only, or a press meant for the slot beside it would take a band with
it. (Not "emptying switches it off", as CELLS §12 puts it: a band emptied while
its cells are being swapped should not vanish under the fingers.)

The second was the interesting one: **every add and every remove closed the
settings cell**, because everything built from the configuration was being
built again.

- `Variants` in `shell.qml` was keyed on the membrane's own block, and the
  configuration hands out a fresh object on every change — so adding a cell
  to a band destroyed the whole membrane it was on. It is keyed on the
  **edge** now, which is a string and compares by value, and the membrane
  reads its block out of the configuration.
- The tissue `Repeater` had the same shape: a new array means every delegate
  rebuilt, and a tissue rebuilt is every cell in it rebuilt. It runs over the
  **count** now, and each delegate reads its own entry.
- `Tissue.build()` destroyed every cell and built them again. It keeps what is
  still declared: a cell of that domain keeps its instance and is handed the
  new block — everything a cell reads from its block is a binding — and only
  what arrived is built, only what left is destroyed.

So a cell added from the settings page now appears on the membrane while the
page stays open, which is what makes the page usable at all.

And the cross on a slot did nothing, which was the same tap answered twice:
both the cross's handler and the slot's own are offered it, so the band was
removed and lit again in the same frame — an empty band at 25 %, which is what
Akusen kept finding. The slot's handler now stands aside when the pointer is on
the cross. The removal path itself was never at fault; a throwaway timer
calling `clear()` took the band out and left it out.

### Settings: Keybinds, the fourth page of five

Every bind niri reads, in the order it reads them, one row each: what it does
and the keys that do it, drawn as keycaps. The pencil turns the keycaps into a
field that listens; the next key pressed with its modifiers is the new
combination and is written at once. A taken one is refused in the field, in
the alert colour, saying by what. Escape leaves the bind as it was, and the
cross that replaces the pencil removes it. The dashed chip opens a picker on a
thread — the cells first, then every niri action that needs no argument, asked
of niri itself — with a filter at its top; what is chosen arrives at the end
of the list, already listening for its keys.

- **niri's files are edited as text, never re-printed.** `services/niri-binds.js`
  is a small KDL scanner that finds positions — where a bind's key is, where a
  bind starts and ends, where the block closes — and an edit replaces exactly
  that span. Comments, blank lines and spelling survive; a removed bind takes
  its own comment line and one blank line with it. It is plain JavaScript and
  was tested with node against copies of the real files.
- **Each bind is written back into the file it came from**, following
  `include` the way niri does (positional; the later bind wins, and an
  overridden one is listed faint). New binds go into `config.kdl`'s own block,
  created at its end if it has none.
- **Nothing is written that niri would refuse.** The resulting `binds` block is
  piped to `niri validate -c /dev/stdin` first; niri's own objection — "invalid
  key: Foo" — is what the footer says. niri watches every included file and
  reloads by itself.
- **The combination is read by position where Qt reads it by symbol.** niri
  names keys by their unshifted keysym, so `Mod+Shift+1`; Qt reports `!`. The
  digit row and the punctuation come from the scan code, which on Wayland is
  the xkb keycode.
- **Recording takes the keyboard, it does not ask for it.** A new
  `Cell.takesKeyboard` makes the membrane `Exclusive` rather than
  `OnDemand`: under focus-follows-mouse an on-demand surface loses the keys the
  moment the pointer crosses a window, and a hand reaching for a modifier moves
  the mouse. `ShortcutInhibitor` holds niri's own binds back for as long as the
  field listens, or pressing a taken combination would do what it is taken for.
- **The list is a `ScriptModel`.** A ListView handed a new array starts again
  from the top, and every edit is a new array.
- Giving a cell a key marks every declaration of it `invocable`, as the Cells
  page writes visibility: a key that opens nothing is not a setting.

Verified with a keyboard synthesised through `/dev/uinput` (python `evdev`) and
the shell restarted with `NIRI_CONFIG` on a scratch copy of the configuration:
Super+V refused as Clipboard Manager; Super+Shift+1 recorded as `1`;
Super+Alt+K rewrote the one line of `Mod+N`; a filter typed, Enter taking
"Close window", and Super+Ctrl+Alt+J appended to `config.kdl`; a mid-list edit
leaving the list where it was. The presses that start each of those came from
a throwaway timer.

### A finger is not a right button

His HDMI monitor is a touchscreen, and a tap on a dock icon pinned or unpinned
it. Qt does not filter a touch point by `acceptedButtons` (a finger has no
buttons), so one tap reached every `TapHandler` under it:
- on the dock it raised the application, started a second one and toggled the
  pin;
- on the tray it pressed the item, opened its menu and sent the secondary
  action;
- on audio and notifications (`structure/Cell.qml`) it opened the cell and
  middle-tapped it.

Every right- and middle-button handler now takes `acceptedDevices:
PointerDevice.Mouse | PointerDevice.TouchPad`, and a touch reaches only the
left one.

What the right button did is now a long press, on the touchscreen only: it
toggles the pin on the dock and opens the menu on the tray. The threshold is
Qt's, 0.8 s. A finger that moves before then starts a drag instead, so
reordering the dock by touch still works.

Verified: a synthetic uinput touch held for 1.5 s unpinned a dock icon, and
still did with up to 3 px of jitter. The same hold opened a tray menu. Then he
tried both with his own finger, and they worked.

### LOCK is unavailable until there is a lock screen

`session.lock` defaulted to `loginctl lock-session`, which locks nothing without
a locker listening, and this machine has none now that Noctalia is gone. At his
request the row is disabled until Bioma's own lock screen exists. The default is
now `[]`. `Session.available` says whether an action has a command. The System
cell draws a row without one at 0.38, the same way the utility cell draws a
capture source it cannot use, and neither a press nor its number key runs it.
Setting `session.lock` to a locker brings the row back.

### A saved capture says where it went

From his list ("Dopo aver fatto screenshot con utility bioma, generare notifica
push con azione che apre la cartella…, anche dopo aver salvato un video").
`Capture` announces every saved still and every saved recording through
`notify-send`, answered by whichever server owns the bus, which is Bioma's
own:
- The text is "Screenshot saved" or "Recording saved", with the file's name.
- A still shows itself as the picture (`image-path`), and says when it is also
  on the clipboard.
- The action, "Open folder", runs `xdg-open` on the folder.
- Each announcement waits for its action in a process of its own, so several
  captures in a row each keep a working action.
- `capture.notify` turns it off.

Verified: a screenshot through `capture screen` showed the notification with
its thumbnail, file name and action. He pressed "Open folder" himself, and
the folder opened.

### 1.0.0-beta.1

The first release, 2026-09-23, at Akusen's word ("direi che siamo pronti per
una release beta 1.0"). Before tagging, what would have stopped anybody else:

- **The keys named this machine.** `config/niri/bioma-binds.kdl` carried
  `/home/akusen/Documents/Development/Bioma` twenty times. It is now a template,
  `bioma-binds.kdl.in`, with `@BIOMA@` in place of the path.
- **`scripts/install`** checks what is missing (required and optional, with
  Arch package names). It writes `bioma-binds.kdl` next to niri's `config.kdl`
  once; after that the file is the user's, and the Keybinds page edits it. It
  adds the includes, and with `--autostart` the `spawn-at-startup`. It replaces
  an include of the repository's old binds file. It copies `config.kdl` aside
  and puts it back if `niri validate` refuses the result. Running it twice
  changes nothing. Tested on a scratch configuration, then on Akusen's.
  - The font check first reported both fonts missing when both were installed:
    `grep -q` under `pipefail` makes a found font read as absent.
- **Direct screenshot keys** (his request, while the release was being
  prepared): `Print` for a region and `Mod+Print` for the whole monitor, through
  a new IPC target, `capture` (`region`, `screen`). Neither changes what the
  utility cell remembers. They are in the template, where they replace niri's
  own `Print { screenshot; }`, and in his copy. Verified with synthetic keys:
  Mod+Print saved a file, Print raised the selection veil, and Escape took it
  down.
- **The README** now lists every requirement the scripts actually call, has an
  Install section and a table of the default keys, and says plainly that Bioma
  has no lock screen.

Akusen's own niri configuration was cleaned at the same time, at his request:
Noctalia's and Prisma's pieces are gone.
- His general keys moved from `noctalia-binds.kdl` to `binds.kdl`.
- The eight keys that called `noctalia msg` now open the matching Bioma cells.
  Examples: Mod+V is the clipboard, Mod+N the notifications, Ctrl+Alt+Delete
  vitals. Mod+Alt+L, the lock, is left free, since there is no locker.
- The `noctalia-backdrop` rule, Prisma's layer rules and `cliphist` are gone.
- A full copy is in `~/.cache/bioma-niri-cleanup-20260923-233757`.

### From his list of bugs, 2026-09-23

His notes ("Bug e Migliorie") had three items:

- **The APPS panel's radius differed from the rectangular capsules.** This was
  already gone: APPS had moved into DESKTOP, which is a panel.
- **Escape should close an open cell.** Two routes, because most cells have no
  keyboard while open: the window keeps it.
  - The input surface, up only while a cell is open, now takes the keyboard
    exclusively while the open cell has no field of its own (`Focus.anyOpen &&
    !Focus.holdsKeyboard`). Escape on it dismisses the cell. This is the claim
    the press outside already makes: while a cell is open it has the attention.
    niri's own keys stay niri's, so the shortcuts still work.
  - A cell with a field holds the keyboard on its own surface. Escape that the
    field does not use for itself comes up to the tissue, which dismisses the
    cell. Examples of a field using it: clearing a filter, cancelling a key
    being recorded.
  - Verified with a synthetic Escape, on an empty workspace so that a stray key
    could reach no window: the theme cell (top membrane), vitals (bottom
    membrane, other monitor) and the clipboard (floating, field focused) all
    closed.
- **The brightness display came up at every start.** Over DDC the first reading
  arrives about 3.5 s after start, past `Timing.settle`, and it looked like
  somebody changing the brightness. `Brightness.known` now says when the value
  is a reading. The display remembers the first reading and speaks only when a
  later one differs from it. Verified: nothing at start; +5 and −5 through IPC
  each showed it.

### APPS moves into DESKTOP

Akusen, the same evening: "sposta le impostazioni dei template delle app nella
capsula desktop, così semplifichiamo". The APPS button beside the palette
dropdown is gone, and so is the panel it called up. Its chips now sit in the
DESKTOP capsule, under the icons and the cursor, with the failure line under
them, labelled APP TEMPLATES, which says what they are (his word). The palette capsule is back to its dropdown alone.

- DESKTOP is a panel, not a pill (his other correction: a pill's round ends
  put the labels at its corners too close to the edge).
- Its height now comes from what it holds: 20 of padding, the icons/cursor
  row, and the chips wrapping inside the carousel's width.
- The lists open past it, as before.

### Icons and cursor, in the theme cell

This is from the same list of ideas ("Selettore icon package in theme",
"Selettore cursore in theme"). The theme cell has a third capsule, **DESKTOP**,
under the source and the palette. Akusen chose where it goes. It hangs from the
source capsule, on the same vertical line that joins the carousel to the
source. It has two dropdowns, the icon theme and the cursor, plus the cursor's
size (24 / 32 / 48, with the current size kept among them if it is another).

- **Where a choice goes:**
  - **Icons:** the desktop's setting (`org.gnome.desktop.interface
    icon-theme`), which GTK reads live, and `icon_theme` in qt5ct/qt6ct.
  - **Cursor:** the same setting's `cursor-theme`/`cursor-size`, and niri's
    `bioma-cursor.kdl` through `scripts/niri-include`. The file is included
    last, so it overrides the user's `cursor.kdl`.
  - Nothing is written until something is chosen. What is shown is read from
    the desktop (`scripts/looks list`), and `services/Looks.qml` holds it.
- **The shell's own icons:** they now follow the desktop's theme at all.
  `scripts/bioma` passes the theme to Quickshell as `QS_ICON_THEME`. Before
  that, Qt found nothing but hicolor: `Quickshell.iconPath("folder")` answered
  empty, and a themed icon never appeared. Quickshell reads the variable only
  at start. Until the next start, the capsule says so under the icons
  dropdown ("SHELL: NEXT START"). Keeping the row the same width is why the
  capsule is 108 tall.
- **The lists:** the palette list, the two new lists and APPS all open in the
  same place, past the last capsule, one at a time. The list is now a scrolling
  view of at most eight rows (there are 24 cursors here). It opens scrolled to
  the current choice, recomputed after its rows exist. Opening the cursors
  after the icons first showed the icons' scroll position, with the current
  cursor out of view.

Verified by pressing with the absolute pointer, on DP-1:
- The cursor list opened and Bibata-Modern-Ice was picked, with size 32. The
  desktop's setting and `bioma-cursor.kdl` followed.
- Breeze Dark was picked for the icons. The desktop's setting and qt5ct/qt6ct
  followed, and nothing else in those files changed.
- After a restart the shell's own icons were Breeze Dark. Choosing Qogir back
  showed the note.
- Everything was then set back from the capsule itself. The setting and both
  qtct files are byte-identical to the backup taken first.

### The keyboard cell

This is from Akusen's list of new ideas, 2026-09-23 (from his notes: "Switcher
layout tastiera con keybind e cellula"). The eighteenth cell, `keyboard`:

- **At rest** it shows the layout's code (US, IT) in the machine's voice.
- **Always or conditional** is his choice from the Cells page. Conditional, it
  is there for five seconds after the layout changes.
- **Open**, it lists the layouts niri has loaded, with the active one marked by
  a dot. A press switches to a layout, and a cross removes one (never the
  last). Typing in the field turns the list into the catalogue, all 598 layouts
  and variants, filtered by name or code. A press or Enter adds the one found.
- **Keys:** `Mod+Alt+K` opens it. `Mod+Shift+Space` switches to the next
  layout, straight from niri.
- **Where the layouts are written:**
  - The cell writes the list to `keyboard.layouts`.
  - `scripts/niri-include keyboard` turns it into
    `~/.config/niri/bioma-keyboard.kdl`, but only after `niri validate` has
    accepted it, and only if it changed.
  - The same script adds the `include` line to the end of `config.kdl` once.
  - niri merges sections property by property, so the file overrides only the
    xkb layout and variant.
  - Until the list is first changed from the cell, nothing is written.
- **Services:**
  - `services/Keyboard.qml` matches niri's layout names back to their codes
    through `scripts/xkb list`, which reads xkeyboard-config's `evdev.lst`.
  - Its headless probe is in `probe.qml`.

Verified on the desktop. The panel opened in the middle of DP-1 with the field
focused. Typing "italian" and pressing Enter loaded a second layout in niri.
`switch-layout` moved to it and back. The cross on the Italian row removed it,
and niri was left with the original layout only. Not yet seen: the cell on a
membrane, always or conditional. It is placed nowhere until he puts it
somewhere from the Structure page.

### Dismissing the last notification with the history open

Akusen's report: with the history open, the cross took only the title off the
pill, and the whole cell froze. The log showed why. A press on the pill opened
the history without marking the cell as asked for (`visibility.invoked`), as the
key does. So when the cross dismissed the last notification, the cell's
condition fell while the history was still open. The cell stopped being placed
and dropped out of the input region, leaving an empty pill and a panel that
took no presses. And because the body had opened on hover first, the history
had never claimed the attention, so a press outside did not close it either.

- A press on the pill now marks the cell invoked, as the key does, and closing
  clears it.
- `Cell` claims the attention when `claimsFocus` turns on while the cell is
  already open, and releases it when `claimsFocus` turns off.
- On an empty pill the cross closes the cell: it is still the way out.

Verified with the absolute pointer: hover, press, cross, press outside — the
history stays usable after the cross, and the outside press closes the cell and
sends it away. Hover then cross, with no history, still dismisses and leaves.

### A notification on a side edge flickered under the pointer

Akusen's report: the notifications in the floating tissue flickered on hover
instead of opening. The tissue is anchored `left`, halfway down DP-1, and the
side anchors had taken the centred rule, which re-centres the whole composition
on what it opens. So the pill rose by half of what it opened, left the pointer
below it, and closed. Then it dropped back under the pointer and opened again.
Measured with an absolute pointer: `tissue.y` went 698 → 634.5 → 698 for as
long as the pointer stayed.

- `left` and `right` now keep their place, like every other edge anchor, and
  the composition hangs from them.
- A centred tissue holds its place while the pointer is on a cell it opened.
  It lets go once the pointer has left and the cell has closed. The rule is
  that what the pointer opens never moves out from under it. A summoned cell
  is exempt, because the pointer neither opens nor closes it and it still has
  to be centred.

Verified: the notification opens on hover and stays open for as long as the
pointer is on it, with the pill at y 698 throughout. The clipboard, summoned
with the pointer resting in the middle of the screen, is still centred.

### The overview's backdrop

Akusen noticed that under Noctalia, niri's overview showed a blurred wallpaper
around the workspaces, and under Bioma it showed a flat colour. The reason is
that niri draws a background-layer surface inside each workspace, so the
wallpaper shrinks with the workspaces. Noctalia keeps a second surface for the
space around them. Bioma now does the same: a second `WallpaperSurface` per
screen with `backdrop: true`, which uses the namespace `bioma-backdrop`. It
shows the same picture, decoded at a quarter of the size and blurred once by
`MultiEffect`, and it extends 96 px past the screen's edges so the blur has no
dark frame. `config/niri/bioma.kdl` places it with `place-within-backdrop`.
Verified in the overview on DP-1; the normal view is unchanged.

### The palette, outside the shell

Akusen asked for the theme to reach the rest of the desktop, the way Noctalia's
template page does: niri's colours, niri's window corners following the RADIUS
slider (20 px at 100 %, in proportion below), and the applications' own
configuration.

- **The templates are Noctalia's**, vendored under `config/templates/` with
  their licence and Bioma's changes listed in its README. Every rendered file
  is `bioma.*`, never `noctalia.*`, so the two shells' hooks never touch each
  other's files; niri's is `bioma-theme.kdl`, since `bioma.kdl` is the repo's own
  include and upstream's pattern would have matched it.
- **The colours are named as matugen names them**, and `services/Templates.qml`
  derives all 51 names from the palette's four targets the way the shell derives
  its own surfaces. The terminal's red, green and yellow are the state roles, so
  they carry the same meaning in the terminal as in the shell. One set of
  templates serves both a matugen palette and a Bioma one.
- `scripts/themes` renders every enabled template and writes a file only when it
  changed. It runs a hook only for a changed file, a template just switched on,
  or one whose hook failed last time, so starting the shell does not make every
  terminal reload.
- Qt gets a hook of its own: qt5ct and qt6ct read only the scheme their config
  names, so the hook points them at the rendered one.
- btop and cava, with no config yet, get a config holding only the theme line
  instead of an error.
- **In the theme cell, APPS** is a button beside the palette dropdown. It calls
  up a panel with every application in the catalogue as a chip:
  - lit when on;
  - dimmed, and unable to switch on, when not installed;
  - red, with the reason under it, when its hook failed.

  The panel is born from the button and opens where the dropdown's list
  opens, so the two take turns: asking for one puts the other away. At
  first it was fixed, a third capsule. Akusen asked for it to be called up
  instead, since it is set once and should not stand in the dropdown's way.
- On by default: niri, GTK 3, GTK 4, Qt, Alacritty, btop, cava
  (`theme.templates`).

Verified on the desktop:
- niri's config gained `include "bioma-theme.kdl"` last and still validates.
  The windows took the primary border and the 20 px corner.
- gtk.css imports `bioma.css`, including through Noctalia's symlinked file (GTK
  accepts an import after the rules, checked).
- Alacritty imports its theme; qt5ct/qt6ct point at the scheme; btop and cava
  are set to `bioma`.
- APPS opened, then the dropdown opened in its place, with the list now born
  under the dropdown, which is no longer the capsule's centre.

The originals of the configs the hooks touched are in
`~/.cache/bioma-template-backup-1790180862`.

### The clipboard cell

A seventeenth cell, `clipboard`: what was copied, kept, and put back with a
press. At rest it is its glyph — the history is somebody's text, and the
membrane does not read it out; conditional, it is there for five seconds after
a copy. Open: a filter, then the copies newest first — text as its first words
in Spectral, an image as itself, small — with how long ago in Orbitron; a press
restores one, a cross drops one, CLEAR (asked twice) drops them all. It is
placed nowhere by default, so a key brings it up in the middle of the screen.

- **Bioma's own history**, Akusen's choice over cliphist: one `wl-paste --watch`
  for the life of the shell runs `scripts/clip`, which saves each copy as a
  file (mode 600, in a 700 directory under `~/.cache/bioma/clipboard`) and
  prints a line of JSON. What a password manager marks sensitive
  (`CLIPBOARD_STATE`, `x-kde-passwordManagerHint`) is never saved; the same
  content copied again moves up rather than being kept twice; the list is
  capped at `clipboard.history`.
- One copy can reach the watcher twice, a millisecond apart, and the second
  file is never in the list — so after every change the directory is swept of
  whatever the list does not name.
- `clipboard.svg` joins the icon set.

Verified on the desktop: two texts, an image and a repeated command copied —
four entries, the repeat once at the top, the image as a thumbnail, the long
text on two lines; a restored entry back on the clipboard and at the top; the
directory's files matching the list after the sweep. The test copies were
cleared afterwards; Akusen's clipboard itself was overwritten by them.

### Session becomes System

Where the machine's description belongs was Akusen's question — vitals or
session — and the answer was neither as they stood: vitals is load, and moves;
the description is identity, and is read, like the account beside it. So the
session cell is now **System**: the account capsule above, the five ways to
leave below, and on a thread beside them, opening toward the middle of the
screen, what the machine is — host, system, kernel, niri, CPU, each GPU,
memory, disk, uptime. The restart row says DUE while the restart the cell's
condition watches for is due.

- The type is `system`; `session` stays an alias everywhere a type is read —
  the layout, the IPC call, the keybind — and the settings pages write the new
  name whenever they write a list (`Registry.canonical`, `Registry.renamed`).
  Akusen's override still says `session` and works.
- `services/Machine.qml` reads the kernel's files and asks `lspci`, `df` and
  niri once, the first time the panel opens; the uptime is read again each
  minute while it is open. Two lessons on the way: a binding on a FileView's
  `text()` is not told when the file loads — the facts are set in `onLoaded` —
  and an expansion is handed its cell after the cell has opened, so what starts
  with the panel starts in `onCellChanged`.

Verified from `ipc call cell toggle session` — the old name — on the running
desktop: the SYSTEM header, the account and the commands, and ten facts, among
them the RX 9070 and the Raphael integrated graphics.

### A proxy that follows the networks

Asked for while the VPN was being built: a system-wide proxy with a switch,
turning on by itself with a VPN or a particular network. Akusen chose several
profiles, each with its own triggers, applied both as the desktop's setting and
to the programs the shell starts.

- **A fourth well, PROXY.** One row per profile — name, then `HTTP · host:port ·
  triggers` — with a switch that forces it on (or everything off), and an AUTO
  pill that gives the choice back to the triggers. A row pressed opens it for
  editing: name, HTTP or SOCKS5, host and port, the hosts that go around it,
  and its triggers as chips — every VPN profile, the Wi-Fi network the machine
  is on, the wire. While it is edited the other wells step aside; the form and
  four wells do not fit above a membrane on 1080 lines.
- **`services/Proxy.qml`** picks the profile on and writes it to
  `org.gnome.system.proxy` (browsers and GTK programs read it live), and hands
  `http_proxy`, `https_proxy`, `all_proxy` for SOCKS and `no_proxy` to what the
  launcher and the dock start — `Apps.run` now starts an entry by its command
  with that environment. With no profiles it leaves the desktop's proxy alone;
  having set it and lost its last profile, it puts it back to none, once.
- Found on the way, and fixed: services that act by themselves — the proxy, the
  OSD, the alarm — started only when something first *bound* them, which for
  the proxy meant when the panel first opened. `shell.qml` binds them at start.
  And `execDetached` refuses a plain object as its process context unless the
  file imports `Quickshell.Io`: `core/Apps.qml` does now.

Verified against the real desktop setting, backed up first and put back after:
a profile triggered by the wire set `mode manual` and `proxy.example:3128` at
start, without the panel ever opening; removing it set `mode none`. The
environment reached a started program (`http_proxy`, `NO_PROXY` read back from
its `env`). The switches and the form were driven from a throwaway timer.

### VPN, set up from the panel

A third well in connectivity, VPN: one row per profile NetworkManager keeps
(OpenVPN and WireGuard), each with its own switch, and a lock in the contracted
cell while one is up — a tunnel is a connection like the others. "+ PROFILE"
opens a form in the well: the provider's `.ovpn` chosen through the system's
file chooser, the user name, the password, IMPORT. Removing a profile asks
first, the row becoming the question, because it takes its credentials with it.
Noctalia lists and toggles profiles made elsewhere; here they are made here,
which is what Akusen asked for.

- `services/Vpn.qml` reads `nmcli` — profiles and active states — again on every
  burst from one `nmcli monitor` kept for the life of the shell. Nothing polls.
- The import is `nmcli connection import`; the credentials go through
  `scripts/vpn`, which takes the password **on stdin** and hands it to
  NetworkManager over D-Bus (libnm), stored with the profile
  (`password-flags 0`). An argument would have been readable by any process
  through `/proc` while nmcli ran.

Verified against NetworkManager with throwaway profiles pointing at a
documentation address: the script stored `username = bob`, `password = hunter2`,
`password-flags = 0`; the form imported a second profile with its credentials
and the list showed both; switching one on failed as it had to, with
NetworkManager's own reason under the list. Both profiles and their CA files
were deleted afterwards.

### Bluetooth: searching and pairing

The devices well learns to look. A SEARCH pill beside its switch starts
discovery, with the loader running beside the word while it looks — the one
movement that means "nothing yet" — and what is found with a name joins the
list under the paired devices, said more quietly. A press pairs it, trusts it
and connects it: somebody pressing a headset wants to hear it. A cross under
the pointer forgets a paired device. Discovery ends with the panel.

Quickshell registers no BlueZ agent, so a device that asks nothing — headsets,
mice, speakers — pairs, and one that shows a code to confirm cannot; it says
`Failed`.

Verified: the search starts from the panel — STOP with the loader, "Looking…".
Not verified: pairing, connecting and forgetting — no discoverable device with
a name was in range, and none is paired on this machine.

### The clock, opened

Nothing in CELLS draws it; the style guide leaves the clues — a city's name
above a Spectral clock, `Europe/Rome` and `UTC+2` as metadata, month names in
Spectral — and Akusen asked for a calendar, other places, and a timer with an
alarm. The month hangs from the cell; other places on a thread to one side, the
timer and the alarm on a thread to the other. The cell keeps the time when it
opens rather than becoming a header that says CLOCK.

- **The month**: six weeks from the Monday before the first, so the grid never
  changes height; today on the primary disc; chevrons turn it, the name brings
  today back.
- **Other places**: the city in Spectral 700 above its time, the offset and
  `TOMORROW`/`YESTERDAY` beside it; a field finds a zone among the system's and
  adds it, a cross on hover removes one. QML has no time zones, so
  `services/Time.qml` asks `TZ=… date +%z` when the list changes and every half
  hour, and draws the rest from the machine's clock.
- **Timer and alarm**, in `services/Time.qml` so they outlive the panel: presets,
  the wheel on the figure, start, pause, reset; the alarm's hour and minute
  turned by the wheel, and a switch. They end in a critical notification and the
  freedesktop alarm sound. While a timer runs, the small dial beside the time
  shows what is left of it instead of the minute.

Verified in a scratch configuration: the three panels with three places,
Tokyo and Sydney marked tomorrow; "lond" finding London; a four-second timer
counting down on the dial and ending in the critical "Timer" notification.

### The on-screen display

The first of the features after the build order (Akusen's list, 2026-09-23).
The volume or the brightness, said for `Timing.osd` after it changes, low in the
middle of the monitor the keyboard is on — **only where no cell says it
already**: the brightness always, having no cell; the volume only on a monitor
that declares no audio cell, since a declared one, conditional or always, is
the answer there. Akusen's rule, and the thing CELLS §05 left open.

- It is the audio cell's summoned capsule — dial, figure, slider — because it
  says the same thing; the brightness wears the same capsule with a sun in the
  middle of its dial, `brightness.svg`, new in the icon set.
- `services/Osd.qml` decides what is said and where; `structure/OsdSurface.qml`
  is one overlay per monitor that takes no input, blurs its capsule and grows
  it from its own centre. Nothing in the first `Timing.settle` is said.

Verified on the desktop: a one-percent `wpctl` nudge with HDMI-A-1 focused
showed nothing (its audio cell answers); with DP-1 focused, the capsule at 96 %.
The brightness through DDC, 50 → 55 → 50 on HDMI-A-1: the capsule with the sun
at 55 %, gone a second and a half later, and the monitor back at 50.

### What conditional means, cell by cell

Akusen's conditions, 2026-09-23: the clock for the minute the hour strikes;
workspaces, audio and connectivity for five seconds after a change; vitals while
an indicator is critical; the tray from a change of state until the pointer has
been over it, then five seconds.

- **An event is a pulse.** `Cell.pulse()` makes the condition true for
  `Timing.pulse`, and the dwell of the domain's grammar is how long the cell
  stays — held while the pointer is on it and resumed where it stopped, and a
  block may set its own. Nothing in the first `Timing.settle` counts: the
  services filling in after start are the shell learning the machine, not the
  machine changing.
- **Critical is the alert colour.** Vitals watches the worst of CPU, RAM, GPU
  and the battery's emptiness against `Theme.thresholdAlert`, with hysteresis
  under it and a second to be believed.
- The workspace change is told by the workspace's id — the service hands out a
  new object on every event. Connectivity pulses only for a connection that was
  not there before; going away is not news.
- **The pages write only the kind.** Cells and Structure used to copy the
  grammar's figures into the block, which froze a condition at whatever it
  meant that day. They write `type` now, and switching drops copied figures.

Four more, proposed and kept the same day: the theme for five seconds after
the palette changes (its *targets*, not the animated roles that move every
frame); the utility for five seconds after a screenshot — Bioma's own, or
niri's, which `services/Niri.qml` now hears as `ScreenshotCaptured`; the
session while a restart is due, which on this machine is exactly when the
running kernel's `/usr/lib/modules/<release>` is gone, watched rather than
polled; and the dock while the desktop is showing, the active workspace on its
monitor empty.

The theme was driven: a palette switched in a scratch configuration brought the
cell up wearing the new swatches, and it went five seconds later. The restart
check was run headless (false, the modules are there) and its watcher tried on
a scratch directory removed under it. The dock's test is headless too: both
active workspaces have windows, so it is away. niri's screenshot event was not
driven — a screenshot writes a file and takes the clipboard.

Verified in a scratch configuration with the six cells conditional: nothing on
screen after start; the audio dial came up on a one-percent nudge with `wpctl`
and went five seconds later; vitals came up with every core busy, the CPU dot
in the alert colour, and went when the load stopped; the workspaces cell came up
on a flip down and back and went five seconds later. The clock, the tray and
connectivity were not driven — the hour did not strike, and nothing here can
make a tray item change state or a device connect on demand.

### One place per cell per monitor, and every cell answers its key

Akusen's simplification, 2026-09-23. Where a cell is and when it shows are two
separate questions, each answered in one place:

- **Where — Structure, per monitor.** A cell is in one band of one membrane or
  in one floating slot, never two. The picker offers only what is nowhere on
  that monitor yet.
- **When — Cells, and only always or conditional.** "Invoked only" is gone
  from the page. A cell placed nowhere on any monitor is listed as keybind
  only. What each condition means per cell is Akusen's to give, next.
- **The keybind, for every cell.** `Cell` is always invocable. On a membrane the
  cell opens where it is; in a floating slot it appears there, even if its
  condition is not met, and goes again when it is put away; placed nowhere on
  the monitor it is summoned into the middle. Asking twice puts it away.
  `"invocable": true` is gone from the default layer — it no longer decides
  anything — and a block of type `invoked` still reads.
- The notification cell opened by a key opens its history: there is no body to
  show a hand that is not there.
- The Keybinds page's picker no longer dims cells as "not placed": every cell
  has somewhere to come up.

Verified on the running desktop with `ipc call cell toggle`: notifications came
up in Akusen's left floating slot with the history, vitals — on HDMI-A-1 only —
in the middle of DP-1, the clock opened nothing because it has nothing to open,
and each went away when asked again. The picker on DP-1 offered vitals, audio,
connectivity, dock and tray, the five cells not on it.

### Structure shows what floats

A part of the layout the settings cell could not see is a part nobody can fix.
Akusen put the notification cell on DP-1's top membrane, and every notification
still came twice: the override declares `membranes`, lists replace wholesale,
and `floating` — which the page did not show — kept coming from the default
layer with its own notification column in the top-right corner.

- **The places are the slots.** Between TOP and BOTTOM, nine slots in three
  rows — the screen in small, the columns lined up with the bands' — and a
  `POINTER` slot beside the FLOATING label, because the pointer is not a place
  on the screen. Lit, a slot says its first cell and how many more; dashed, a
  press puts a tissue there. One tissue per anchor on a monitor.
  The first version drew a row of slots whose order meant nothing and chose the
  anchor on a map inside the detail; Akusen asked what the difference was
  between a tissue in the right slot anchored top-left and one in the middle
  slot anchored top-left — none, which is the defect.
- **Chosen, it opens the band's own detail**: where it is and on which
  monitors, the remove control, the chips, the picker and the drag to reorder
  — every write to the chosen tissue goes through one `editChosen`, whichever
  list it lives in. Two cells of one domain are told apart by `options.show`.
- **The panel is taller rather than scrolling**, Akusen's call: 540 rather than
  420, one height for every category as §12 asks, measured so Structure holds
  the floating places and three rows of cell chips — 512 of 512 with the
  top-right band's five cells and the picker open. The page keeps a Flickable
  only as a fallback for a band with more cells than that; it does not move
  while the content fits.
- The thread to the detail leaves the chosen slot and runs under the rows below
  it. It used to start under the last row whatever was chosen, which read as
  the bottom membrane's empty slot being the one open.

Verified against a scratch copy of the configuration: a cell removed, a
floating tissue removed and a new one added — each written as the `floating`
list into the override. Akusen then moved the notification column himself,
from the page, and the grid draws his layout: the column at the left edge, the
launcher in the middle.

### A cell at the pointer

The last piece of the engine, and the third user of the full-screen surface
PRD §8 names. A floating tissue may say `"anchor": "pointer"`: when its cell
appears, the tissue is centred on the pointer, kept on the screen, and opens
towards the larger half of it.

- **The pointer is asked for by being under it.** Wayland has no query, but a
  surface that appears under the pointer is told where the pointer is — and
  niri tells it without the pointer moving. Prototyped first, alone: a
  full-screen surface mapped under a still pointer reported (2805, 396); the
  cursor in a `grim -c` frame of the same moment was drawn at (2804, 397).
- `core/Pointer.qml` is the register: the full-screen surfaces report what
  they see, and a question is answered by a sighting newer than itself. The
  floating surface takes input everywhere for the moment it takes to be
  entered, draws nothing until then, and gives the region back to its cells.
  No answer within `Timing.locate` (120 ms, not scaled by the speed setting)
  and it takes the middle.
- Found on the way: `Focus.invoke` opened every declared invoked cell that had
  a panel, ignoring `opensOnArrival` — the audio capsule came up with its wells
  open. It honours it now, and a cell that arrives unopened claims the
  attention instead, so a press outside still sends it off.

Verified with a pointer-anchored audio cell in a scratch configuration: the
capsule came up centred on the cursor to the pixel, closed, and the same
shortcut put it away.

### The silhouette, for a session with no picture

`components/Portrait.qml` draws what the design page draws when there is no
avatar: a head and the top half of a disc for shoulders, in the rim colour at
0.55 and 0.45, on the page's 64-unit grid and cut by the same round mask as a
picture. It is not an interface icon — it is filled and it only ever lives in
this well — so it is drawn here rather than added to the icon set. Checked
with the avatar forced off by a throwaway patch: the 30 px cell and the 88 px
expansion both match `08-session-expanded`.

### The audio cell, summoned, is the capsule

CELLS §05's invoked form, drawn as `05-volume-invoked-floating`: in the middle
of the screen the audio cell is the capsule itself — dial, figure, slider — with
no thread above it, because there is no membrane to hang from. The launcher's
rule: what changes is where it is born, not what it does. A press hangs the
three wells below it on the cell's own thread, and folding them away leaves the
capsule; the press outside is what sends it off.

- `cells/audio/AudioCapsule.qml` is the capsule's content, loaded in both
  places — the first shape of the expansion on a membrane, the cell's body
  when floating. A sibling file is reached through a `Loader`: cells are built
  from `qs:@` addresses and their directory is not imported from there
  (`import qs.cells.audio` is "not installed").
- Two engine switches on `Cell`, both defaulting to what was: `opensOnArrival`
  — a summoned cell with a panel opened on arrival, and the capsule arrives
  closed — and `leavesOnClose` — an invoked cell went when it closed, and the
  capsule only folds its wells.

Verified from `ipc call cell toggle audio` on the running desktop, where the
audio cell lives on HDMI-A-1 only and so is summoned on DP-1: the capsule
alone, matching the mockup; and, with the panel driven by a throwaway timer,
the wells hung below it and folded away with the capsule left standing.

### A critical notification sits on top, and the others go past it

The notification cell takes `options.show`: `all` (as before), `urgent` or
`ordinary`. Two of them in a column, urgent above ordinary, are the "column of
cells" §10 asks for, and `config/default.json`'s floating column is now that.

- **The only clock is the ordinary head's.** It runs while that head can be
  seen and nobody is reading it; the pointer on the urgent cell does not stop
  the ordinary ones going past.
- **With one `all` cell nothing changes**: urgency wins the cell and ordinary
  ones arriving meanwhile go to the history, because nobody would see them
  queue. The service knows which case it is in by counting the cells showing
  `ordinary`.
- Dismissing names the notification — the close button and the middle click
  close what *their* cell shows, not whatever is at the head of a queue.

Verified with `XDG_CONFIG_HOME` pointed at a scratch copy of the configuration
and `notify-send`: a critical one held the top cell while a normal one expired
under it after eight seconds and a low one took its place.

Found on the way, not changed: Akusen's override puts a notification cell on
DP-1's top membrane, and the default floating column is inherited as well, so
every notification is shown twice on the primary monitor.

### Settings: Monitors, the last page of five

Every output niri reports, drawn to scale in the area as a rectangle with its
name and mode on two lines in the middle. A rectangle is carried from where it
was touched; the edges and centres it can line up with pull it in within
twelve units of the area, and the line it snapped to is drawn across the area
for as long as it holds. Let go, and the whole layout is written with its
top-left at the origin; niri moves the desktop and the rectangles settle on
what niri then reports. A drop that overlaps another monitor goes back, saying
so. Below: the chosen monitor — shared with the Structure page — whether niri
focuses it at startup, and its scale.

- **The niri configuration is one service now.** `services/NiriConfig.qml`
  owns the files — reading every include, watching them, validating before
  writing, one write at a time — and `Keybinds` and `Monitors` are views on
  it. The scanner is `services/niri-config.js`, with output sections beside
  binds.
- **Two sources for a monitor.** Where it is and what mode it runs come from
  `niri msg --json outputs`, asked again after every write and whenever the
  screens change; what was *asked for* comes from the `output` sections.
- **niri does not merge `output` sections.** This machine has `DP-1` in both
  `config.kdl` and `outputs.kdl`; a position is written into every section
  that names the output, by connector or by make-model-serial. An output with
  no section gets one, beside the last section there is.
- **"Primary" is `focus-at-startup`**, niri's only notion of one: set on the
  chosen output, taken off every other.
- Known limit: the area's scale is frozen while a rectangle is carried, so a
  rectangle dragged past the area's edge is cut off until it is dropped and
  the area refits.

Verified against a scratch copy of the configuration: the services from
`probe.qml`; positions written into both `DP-1` sections, primary moved and
taken off again; and a drag driven from a timer — HDMI-A-1 carried to the right
of DP-1 snapped to both its right edge and its top, drew both guides, and wrote
`position x=3440 y=0` into the one line it had.

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

### Before notifications could be touched — done, 2026-09-22

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
- **Two of §2's exclusions were lifted by Akusen on 2026-09-23.**
  - Third-party theming: the theme cell now sets the desktop's icon theme and
    cursor, and its application templates carry the palette to other programs'
    configuration.
  - The lock screen: decided, and planned for the week after. Its triggers
    are the key and the System cell's LOCK, before suspend, and after an idle
    time. Its content is the wallpaper blurred, the clock, the account and the
    password field. Until it exists, `session.lock` is empty and LOCK is shown
    unavailable, because `loginctl lock-session` with no locker listening
    locked nothing.
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
