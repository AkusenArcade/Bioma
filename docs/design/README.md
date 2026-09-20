# Bioma — design handoff

Bioma is a Wayland shell for **niri**, built as a set of **independent cells**, not as a bar.
This package is the visual and behavioural specification: what to build, at what size, moving
how, and — where it matters — why, so that a judgement call made during implementation lands
on the same side as the ones already made here.

It does not contain architecture, service design or build order. Those live in the project PRD.

## Vocabulary

Three words, used consistently everywhere, including in code:

| Word | Meaning |
|---|---|
| **cell** (`cellula`) | one autonomous unit: a clock, the workspaces, the dock. It has a contracted state and, sometimes, an expanded one. |
| **tissue** (`tessuto`) | a group of cells sharing an anchor and a slice of an edge. Cells reflow inside it. |
| **membrane** (`membrana`) | everything on one edge of one output. Owns auto-hide; the cells on it do not. |

The project is discussed in Italian, but **every user-facing string in the shell is English**.
This package is English throughout.

## What is in here

| File | What it is |
|---|---|
| `STYLE_GUIDE.md` | the rules that apply to every component: principles, type, colour, form, motion, controls |
| `CELLS.md` | the thirteen cells, one section each: states, behaviour, measurements, decisions |
| `IMPLEMENTATION.md` | the traps — things that look like design detail and are technical constraints |
| `tokens.css` | the design tokens as custom properties, ready to translate into QML singletons |
| `icons/` | 33 SVG glyphs, 24×24, `currentColor`, plus their own README |
| `mockups/` | 68 renders at 2×: every state of every cell, indexed in its own README |
| `pages/` | the three design pages as live HTML — the animated indicators actually move there |

**Text wins over pictures.** Where a measurement in `CELLS.md` and a mockup disagree, the
measurement is right: the images show the result, they are not there to be pixel-measured.

## Reading order

1. `STYLE_GUIDE.md` — principles first. They decide ties; everything else derives from them.
2. `IMPLEMENTATION.md` — before writing the first QML component, not after.
3. `CELLS.md` — one cell at a time, when you build that cell, with the matching images from
   `mockups/` open beside it.

If something in the spec is easier to see than to read — how the threads join the pods, how the
audio band moves — open `pages/cells.html` in a browser. The indicators there are live.

## How to use this with Claude Code

Drop the folder into the repository and point at it from `CLAUDE.md`:

```md
## Design
The visual specification lives in `design/`. Read `design/STYLE_GUIDE.md` and
`design/IMPLEMENTATION.md` before writing any UI code, and the matching section of
`design/CELLS.md` before building a cell. `design/mockups/` shows every state of every
cell; `design/icons/` holds the glyphs. Measurements in the documents are normative and
win over the images; when something is not specified, follow the principle it falls
under rather than inventing a new rule.
```

## Status

Every measurement here has been drawn and checked at real size. Three things are
deliberately **not** decided, and are marked as open in the relevant section:

- the fallback glyph for applications whose desktop file resolves no icon (cell 01);
- the band count and frequency split of the audio visualiser, which is decided against the
  existing Sinestesia code and against real audio, not against a mockup (cell 04);
- a system-wide OSD, deferred on purpose because it concerns brightness and others too and is
  not a property of the volume cell (cell 05).

Everything else is decided. Where a decision went against what the PRD suggested, the section
says so, so that a later reading does not mistake it for an oversight.
