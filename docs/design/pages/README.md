# Live pages

The three design pages, self-contained. Open them in a browser: the mockups here are **live**,
so the things that move actually move — the CPU beat, the RAM wave, the GPU satellite, the
audio band, the workspaces icon shifting on a workspace change.

| File | What it is |
|---|---|
| `cells.html` | the design page: all thirteen cells, every state, with the reasoning |
| `style-guide.html` | the style guide, with live component examples |
| `icons.html` | the icon set with SVG source |

Two notes:

- The **prose in `cells.html` and `style-guide.html` is Italian** — it is the design
  conversation, kept as it was written. Every string *inside the mockups* is English, as the
  shell's strings are. The English specification is in `CELLS.md`, `STYLE_GUIDE.md` and
  `IMPLEMENTATION.md`; these pages are the visual reference.
- They load Orbitron and Spectral from Google Fonts. Offline they fall back to a generic sans
  and serif, so the layout holds but the type does not represent the design.
