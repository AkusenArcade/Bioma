# Bioma icons

33 glyphs, 24 × 24, `currentColor`, no width/height assumptions beyond the viewBox.

Icons are the one graphic alphabet in Bioma that is not an indicator: they say **what**
something is, never **how hard** it is working.

## Construction

- **Grid 24, live area 20** — two pixels of margin per side, so glyphs of different bulk weigh
  the same in a row.
- **Stroke 1.5**, round caps and joins. Exceptions only where a glyph must read darker at small
  size: `workspaces` 1.4, `bell` / `app-fallback` / chevrons / `plus` / `close` 1.6,
  `search` / `edit` / `sound-*` 1.7, `error` 2.0, `pause` 2.6.
- **Corner radius 3** on rectangles: below it disappears at 16 px, above it turns into a pill
  and changes meaning.
- **No fills**, except nodes (r 1.1–1.5) and glyphs that stand for a filled state (`stop`).
- **Must survive 16 px.** If a detail vanishes there, remove it at 24 too: an icon with two
  versions is two icons to maintain.

## Use

- **Primary gradient** when the icon is a header, an active control, or the only content of a
  cell.
- **Muted text** when it is inactive, secondary or a fallback. Never a state colour.
- **Application icons are third-party** and follow none of these rules. They sit in a dark
  circle with a thin outline, which is what makes them a family despite their styles. When a
  desktop file resolves no icon, use `app-fallback.svg` — never another application's logo.
- **`mark.svg` appears in the settings cell only.** It is built from this set, but it is not an
  interface icon and is not reused elsewhere.
- The **wireless glyph is ours** — two nodes joined by a thread. The Bluetooth mark is
  registered and is never reproduced.

## Files

| File | Used in |
|---|---|
| `workspaces.svg` | workspaces cell; shifts one step on workspace change |
| `capture.svg` | utility cell at rest |
| `screen.svg` `window.svg` `region.svg` | capture targets |
| `lock.svg` | session command; also the secured-network marker at 12 px |
| `suspend.svg` `restart.svg` `power.svg` `logout.svg` | session commands |
| `bell.svg` | notification cell and history rows |
| `ethernet.svg` `wifi.svg` `wireless-link.svg` | one per active connection |
| `headphones.svg` `mouse.svg` | device type in the connectivity list |
| `search.svg` | launcher field and task filter |
| `mark.svg` | settings cell only |
| `sinestesia.svg` | sinestesia cell: its header, and the well where a cover is missing |
| `theme.svg` | theme cell header |
| `loader.svg` | the one icon that moves — see `LOADER.md`. Beside whatever is waiting, never in place of it |
| `app-fallback.svg` | unresolved application icon |
| `play.svg` `pause.svg` `skip-previous.svg` `skip-next.svg` | transport controls |
| `sound-on.svg` `sound-off.svg` | per-application mute; `sound-off` is also the muted volume dial |
| `stop.svg` | stops a recording |
| `chevron-down.svg` `chevron-right.svg` | dropdowns, rows that open something else |
| `plus.svg` `close.svg` `edit.svg` | add, remove, edit |
| `error.svg` | beside the reason, in the alert colour, under the field that refused the input |
| `clock.svg` | ring plus minute pie |
| `brightness.svg` | the sun in the middle of the brightness display's dial |

## QML

Load them through a role, not a path constant:

```qml
Image { source: Icons.get("wifi"); ... }
```

and tint with the theme's primary. In QML an SVG using `currentColor` needs an explicit fill;
keep the source files as they are and set the colour at render time, so a theme change repaints
the icons with everything else.
