# Bioma

A Wayland desktop shell built as independent, living surfaces rather than a bar.

The machine is an organism. Bioma shows its vital signs: surfaces appear when
they have something to say, animate in proportion to what they measure, and go
quiet when nothing is happening.

- **Compositor**: Niri
- **Toolkit**: Quickshell (Qt/QML)
- **Status**: services ported and verified; the layout engine draws, with the first two cells on it

## Requirements

| Requirement | Notes |
|---|---|
| Niri | 26.04 or later for `ext-background-effect` blur |
| Quickshell | recent build; the PRD assumes current API |
| matugen | optional, wallpaper-reactive palette |
| grim, slurp, tesseract | screenshot and OCR |
| wl-screenrec (VAAPI) | video capture; `wf-recorder` as fallback |
| Spectral, Orbitron | fonts; declared as roles — expressive and technical — so absence degrades rather than breaks |

## Running

Quickshell loads a configuration by directory name. Link this repository into
the Quickshell configuration directory and start it:

```sh
ln -s "$PWD" ~/.config/quickshell/bioma
quickshell -c bioma
```

## Verifying a service without a UI

```sh
qs -p "$PWD/probe.qml"
```

Creates no surfaces. It binds each service the way a cell would, waits for the
data to arrive, prints what came back, and exits. Every service is verified
through this before a cell is built on it.

## Layout

```
shell.qml          entry point
probe.qml          headless service verification
core/              Config, Theme, Timing, Metrics — global singletons
structure/         Membrane, Tissue, Cell — the layout engine
components/        shared primitives
services/          one singleton per system domain
cells/<name>/      one directory per cell
config/            default.json + palettes/
assets/icons/      the 33 glyphs, at runtime
docs/              bioma-prd.md — the specification
docs/design/       the visual specification: style guide, cells, tokens, mockups
```

## Configuration

Two layers. `config/default.json` ships with the shell; a user override file
written by the settings UI is loaded last and wins. The default is functional
and demonstrates the vocabulary — it is not exhaustive.

## Trying it on one monitor

Bioma is not finished, and `org.freedesktop.Notifications` has one owner per
session, so it is not meant to replace a running shell yet. It can run beside
one: declare a membrane on a monitor the other shell does not occupy in
`~/.config/bioma/override.json`, then

```sh
qs -p "$PWD/shell.qml"
```

## Documentation

- `docs/bioma-prd.md` — the product requirements, and the source of truth
- `docs/design/` — the visual specification: `STYLE_GUIDE.md`, `CELLS.md`,
  `IMPLEMENTATION.md`, `tokens.css`, the icon set and 68 mockups
- `PROGRESS.md` — where the work stands, and what is not done
- `services/INVENTORY.md` — the Prisma inventory and every decision taken since
- `CLAUDE.md` — architecture rules for anyone (or anything) writing code here

## Licence

GPL-3.0-or-later. See `LICENSE`.

The design material in `docs/design/` — the style guide, the cell
specifications, the icons and the mockups — is part of the same work and
travels under the same terms.
