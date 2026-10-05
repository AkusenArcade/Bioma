# Bioma — cursors

Bioma draws its own cursor theme, in the palette, and redraws it when the palette changes.
This file is the whole contract: the grammar the drawings follow, the two colourings, and how
the theme reaches niri, the toolkits and the greeter. The drawings themselves are data, in
`assets/cursors/drawings.json`. `pages/cursors.html` draws them for review, and you can wear
each one by hovering it.

Decided on 2026-10-05, on the proof that is now `pages/cursors.html`.

---

## 1. Grammar

The cursors are drawn on the **icon grid** (`icons/README.md`): 24 units, round caps and
joins, nodes and threads. Two things differ, because a cursor is drawn over anything at all
and the icons are not.

- **Every shape has a contour**, outside it, 1.25 units: the body is one colour, the contour
  another, so the cursor reads on a white page, a black terminal and a photograph alike.
- **Threads get a halo** instead of a contour: a 1.6 line over a 1.1 band on each side.

| Part | Drawn as | Examples |
|---|---|---|
| body | filled, contoured outside; parts that overlap read as one silhouette | the arrow, the hands, resize heads |
| thread | stroked, haloed | the text beam, the crosshair, resize shafts |
| node | a dot in the accent | inside the arrow, the ends of the text beam |
| badge | a small body laid **over** the arrow with its own contour | help, copy, alias, no drop, context menu, the progress loader |
| ink | detail on top of a body or badge, never a line inside a silhouette | `?`, `+`, the zoom signs |

### The arrow

Soft, after Bibata Modern Classic. It has no tail. A sharp core, with its lower edge bowed
inwards, is grown by 1.6 units with round joins, so every corner is a true arc of the same
radius. The hotspot sits on the tip's arc.

### The node

The arrow carries a dot in the primary: the thread's **node**, the point where the pointer
attaches to the world. In the Bioma theme it is the only part that carries the palette, so a
retint changes the cursor without making it louder.

### Hands: outline only

The hands are silhouettes: no lines between the fingers, nothing inside. Fingers **overlap**
their neighbours by at least half a unit. Where two fills only touch, the contour drawn under
them shows through the seam as a hairline.

### Wait and progress

They carry the **loader**, under the exception `icons/LOADER.md` already makes for it: a busy
cursor means "no value yet", and the application takes it away when it is no longer busy.
Wait is the loader alone. Progress is the arrow with the loader **beside** it, as a badge,
never in place of it. The cycle and its easing are `Timing.loader` and `Timing.sweep`, so the
animation speed setting reaches the cursor. At 0, the segment holds still at the left end.

### Not allowed

There is no red. A refused drop is not a measurement past threshold, so it gets no state
colour (`STYLE_GUIDE.md` §3).

---

## 2. Two themes

Both come from the same drawings and the same palette. Each ink names a palette role; `@rim`
is the outline family's gradient, rim to line at 165°, the light of a contracted cell.

| Ink | **Bioma** (default) | **Bioma Cell** |
|---|---|---|
| body | `background` | `cell` |
| contour | `text` | `@rim` |
| thread | `text` | `rim` |
| halo | `background` | `background` |
| detail | `text` | `rim` |
| node | `primary` | `primary` |

**Bioma** reads on every backdrop. **Bioma Cell** is the more faithful to the cells, and the
weaker of the two on a mid-grey surface. The primary-filled variant was drawn and dropped: it
made the cursor the brightest thing on the screen, all day.

The colours are the shell's own (`services/Looks.qml` takes them from `core/Theme.qml`'s
targets), so the cursor and the cells always agree.

---

## 3. Coverage

25 drawings. Each lists every name it answers to: the CSS cursor names, their X11 aliases,
and the hashed names older toolkits ask for. The legacy X11 shapes nobody draws any more
(pirate, pencil, the tees and angles) fall back to the nearest drawing. Mostly that is the
pointer; the tees and angles get the resize arrow of their axis.

---

## 4. How the theme is built and shown

| Step | Where |
|---|---|
| The palette settles; the colours and the loader's timing go to the builder | `services/Looks.qml` |
| One SVG sheet per size, rendered by librsvg, premultiplied by ImageMagick | `scripts/cursors` |
| XCursor files at 24, 32, 48, 64, 72 and 96 px; the aliases are symlinks | `$XDG_DATA_HOME/icons/bioma`, `bioma-cell` |
| Nothing is rebuilt when the request and the drawings have not changed | the theme's `.stamp` |

**Slots.** niri loads a cursor theme once per name. It reloads only when its `cursor` section
changes, and it caches each shape the first time it is used. GTK does the same. A theme
rewritten in place is therefore never seen. Each theme has two slots, `bioma.a` and `bioma.b`:
empty themes that inherit everything from it. The desktop is set to a slot, never to the theme
itself. After a rebuild, the shell moves it to the other slot. That change of name is what
makes the new colours appear. The theme cell lists the themes, not the slots
(`scripts/looks`).

**The greeter** gets the theme and the slot in its copy (`scripts/greeter-sync`, `data/icons/`),
and finds them first on its cursor path (`scripts/greeter-session`).

**Known limit.** Some clients draw the cursor themselves instead of asking niri for a shape:
XWayland, some Electron builds. They read the theme when they start, so a palette change
reaches them at their next start. This is a platform limit. Document it, don't fight it.

---

## 5. Changing a drawing

1. Edit `assets/cursors/drawings.json`.
2. Run `scripts/cursors page` to copy it into `pages/cursors.html`, then look at it there, on
   every backdrop.
3. The shell rebuilds the themes at its next start, or at the next palette change: the
   drawings are part of the stamp, so an unchanged palette still gets the new drawings.
