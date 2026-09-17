# Bioma

A Wayland desktop shell built as independent, living surfaces rather than a bar.

The machine is an organism. Bioma shows its vital signs: surfaces appear when
they have something to say, animate in proportion to what they measure, and go
quiet when nothing is happening.

- **Compositor**: Niri
- **Toolkit**: Quickshell (Qt/QML)
- **Status**: design closed, implementation starting at Phase 0

## Requirements

| Requirement | Notes |
|---|---|
| Niri | 26.04 or later for `ext-background-effect` blur |
| Quickshell | recent build; the PRD assumes current API |
| matugen | optional, wallpaper-reactive palette |
| grim, slurp, tesseract | screenshot and OCR |
| wl-screenrec (VAAPI) | video capture; `wf-recorder` as fallback |
| Spectral, Barlow | fonts; declared as roles, so absence degrades rather than breaks |

## Running

Quickshell loads a configuration by directory name. Link this repository into
the Quickshell configuration directory and start it:

```sh
ln -s "$PWD" ~/.config/quickshell/bioma
quickshell -c bioma
```

## Layout

```
shell.qml          entry point
core/              Config, Theme, Timing, Scale — global singletons
structure/         Membrane, Tissue, Cell — the layout engine
components/        shared primitives
services/          one singleton per system domain
cells/<name>/      one directory per cell
config/            default.json + palettes/
docs/              bioma-prd.md — the specification
```

## Configuration

Two layers. `config/default.json` ships with the shell; a user override file
written by the settings UI is loaded last and wins. The default is functional
and demonstrates the vocabulary — it is not exhaustive.

## Documentation

- `docs/bioma-prd.md` — the product requirements, and the source of truth
- `CLAUDE.md` — architecture rules for anyone (or anything) writing code here
