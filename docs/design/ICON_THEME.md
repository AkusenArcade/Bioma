# Bioma — icon theme

Bioma draws the icons it has something to say about, in the palette: **folders, places and
files**. Everything else, applications first, comes from the icon theme the user chooses
under it. The drawings are data, in `assets/icon-theme/drawings.json`.

Decided on 2026-10-05, on the proof at https://claude.ai/artifact/EbbwUcxJ3qewQcWJUTN6GF.
This is the first of two phases. The symbolic set, the small monochrome icons the toolkits
recolour, comes second (§5).

---

## 1. Grammar

- **Glyphs** are the shell's own: the 24 grid of `icons/README.md`, stroked, round caps and
  joins, nodes filled. Places that had no glyph got one in the same hand. *Public* is three
  nodes joined by threads, *remote* is the wireless link, and the full trash has a node inside.
- **Folders and pages** are drawn on a 64 grid. The folder is a back plate with its tab and a
  front plate, radius 6. The page is a sheet with its corner folded.
- **The light** is the shell's: 165°, from above and slightly from the left. It falls on the
  gradients and on the rim, which runs from `rim` at the top to `line` at mid-height.
- **Small sizes lose detail rather than blur it.** Below 32 px a folder drops its emblem, and
  below 24 px a file drops its glyph. The shape alone has to carry it there.
- **The glyph's weight does not scale with the icon.** It stays near 1.5 px, the weight of the
  shell's own icons: 1.5 grid units at 64 px, 2.4 at 40 px, 3.0 at 28 px. A weight that grew with
  the icon clogged on screen. Each range is a scalable directory drawn for its own size
  (`sizes` in the data).

## 2. Two themes

| Part | **Bioma** (default) | **Bioma Primary** |
|---|---|---|
| folder back | `line` | the primary, in shade |
| folder face | `cell`, with the rim | the primary gradient, 165° |
| folder emblem | `primary` | `background`, cut into the face |
| file page | `cell`, with the rim | the same |
| file glyph | `primary` | the same |

**Bioma** is the faithful one: folders and files are cells. **Bioma Primary** makes folders
the thing a grid is scanned for, and keeps files quiet. A line-only variant was drawn and
dropped: it got thin at 32 px and below.

**Files share one page and differ only by their glyph.** Most themes tint by type; here colour
says state, so a PDF is not red (`STYLE_GUIDE.md` §1, rule 3).

## 3. Coverage

| Group | Drawn |
|---|---|
| places | folder, home, desktop, documents, downloads, music, pictures, videos, templates, public, remote, recent, bookmarks, saved search, trash, full trash |
| files | generic, text, code, document, spreadsheet, presentation, PDF, image, audio, video, archive, font, executable, disc image, calendar, desktop entry |

Each drawing answers to every freedesktop name the data lists for it: the generic names and the
common specific ones (`text-x-python`, `application-zip`, the OpenDocument and OOXML types).

## 4. The base, and how it is shown

**The base.** Bioma's themes inherit from one theme, then `hicolor`. The first time one of them
is chosen, the theme that was on the desktop becomes the base, so the applications look as
they did. From then on the theme cell shows **BASE** under ICONS while a Bioma theme is on,
and the base can be changed there. It is kept in the configuration as `theme.icon_base`
(Adwaita until one is chosen).

**Rebuilt with the palette** by `scripts/icon-theme`, which writes plain SVG: a few
milliseconds, and nothing when the request has not changed. The colours come from
`core/Theme.qml`'s targets through `services/Looks.qml`, never from the script.

**Slots**, as for the cursors (`CURSORS.md` §4). GTK and Qt keep an icon theme loaded by its
name, so the desktop is set to `bioma-icons.a` or `.b`: hidden, empty themes that inherit
from the real one. After every rebuild the shell moves the desktop to the other slot.

**Known limits.**
- Qt applications and the shell itself read the icon theme when they start, so for them a new
  palette arrives at their next start. The theme cell says "SHELL: NEXT START" only when the
  theme changes, not when the palette does: the shell's own interface is drawn live anyway.
- Applications that ship their own folder icons keep them.

## 5. Next: the symbolic set

The `-symbolic` icons toolbars, sidebars and panels ask for. They are monochrome, and the
toolkit recolours them itself. So they do not depend on the palette: they are drawn once and
committed. GTK's recolouring is built around filled shapes. Whether it reaches strokes has to
be checked on the installed GTK 3 and GTK 4 first. If it does not, the shell's stroked glyphs
are outlined before they ship.
