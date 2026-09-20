# Mockups

Every state of every cell, rendered at 2× from the design page. These are the reference
images: when a measurement in `CELLS.md` and an image disagree, the measurement wins — the
images are there to show the result, not to be pixel-measured.

Captions are not baked into the images. The description of each state is in `CELLS.md`, in the
matching cell's section.

Naming: `<cell number>-<cell>-<state>.png`. `limit-N` are the limit cases, in the order they
appear in the cell's section.

| File | What it shows |
|---|---|
| **01 · Window title** | |
| `01-window-title-at-rest.png` | normal state, resolved icon and title |
| `01-window-title-limit-1.png` | long title: ellipsis at the limit, never wrapped, never shrunk |
| `01-window-title-limit-2.png` | unresolved icon: neutral fallback glyph |
| `01-window-title-limit-3.png` | no focused window: the cell is gone, the tissue closed on the clock |
| **02 · Vitals** | |
| `02-vitals-at-rest.png` | desktop, three indicators: CPU under load, memory half, GPU calm |
| `02-vitals-at-rest-laptop.png` | laptop, fourth shape for the battery: CPU past threshold, faster beat and wave |
| `02-vitals-expanded-desktop.png` | three horizontal pods, bottoms aligned with the panel |
| `02-vitals-expanded-laptop.png` | four vertical pods in a 2 × 2 matrix, longer list |
| **03 · Workspaces** | |
| `03-workspaces-at-rest.png` | icon and name; width changes only on workspace change |
| `03-workspaces-limit-1.png` | unnamed workspace: number in Orbitron, cell at its minimum |
| `03-workspaces-limit-2.png` | long name: ellipsis at the limit |
| `03-workspaces-limit-3.png` | shortcut change: the bars shift one step, 180 ms |
| `03-workspaces-expanded.png` | buttons left, names right; thread from the cell centre |
| `03-workspaces-expanded-scrolling.png` | past five rows: scrolls with the active workspace inside |
| **04 · Sinestesia** | |
| `04-sinestesia-at-rest.png` | band left, track in Spectral; band symmetrical from the centre |
| `04-sinestesia-limit-1.png` | no track: band alone, cell narrowed |
| `04-sinestesia-limit-2.png` | long title: ellipsis, scrolls only on hover |
| `04-sinestesia-limit-3.png` | silence past the dwell: the cell is gone |
| `04-sinestesia-expanded.png` | visualiser capsule on top, track panel hung underneath |
| `04-sinestesia-expanded-no-metadata.png` | no MPRIS: the panel does not exist, it is not empty |
| **05 · Volume** | |
| `05-volume-at-rest.png` | the dial alone: track, primary arc, node at the head |
| `05-volume-limit-1.png` | muted: arc gone, a cut across the track |
| `05-volume-limit-2.png` | above 100%: the excess as a thinner outer arc |
| `05-volume-limit-3.png` | at zero: arc closed, node back at the top |
| `05-volume-expanded.png` | dial, figure, main slider; output, input, per-application |
| `05-volume-invoked-floating.png` | the same cell as a floating tissue: no thread, deeper shadow |
| **06 · Utility** | |
| `06-utility-at-rest.png` | icon only, no number, no state colour |
| `06-utility-expanded.png` | what is captured above, where from below |
| `06-utility-limit-1.png` | while recording: a separate conditional cell with elapsed time and stop |
| `06-utility-limit-2.png` | on stop: the confirmation grows from the cell itself |
| **07 · Theme** | |
| `07-theme-at-rest.png` | the seven roles of the current theme, in view |
| `07-theme-limit-1.png` | light theme: same form, different content |
| `07-theme-limit-2.png` | another palette: always seven chips |
| `07-theme-expanded-matugen.png` | carousel, source, palette; dropdown picks the matugen method |
| `07-theme-expanded-bioma-palette.png` | same composition; dropdown picks the preset theme by name |
| `07-theme-live-moss.png` | the same slice of membrane in the default theme |
| `07-theme-live-black.png` | the same slice in an all-black theme |
| `07-theme-live-light.png` | the same slice in a light theme |
| **08 · Session** | |
| `08-session-at-rest.png` | avatar only, no name |
| `08-session-expanded.png` | large avatar, five commands in order of gravity, keys on the right |
| `08-session-confirmation.png` | the row becomes the question; red only on the button that acts |
| **09 · Dock** | |
| `09-dock-at-rest.png` | pinned left, running right of the divider; primary ring means running |
| `09-dock-limit-1.png` | nothing running: the divider disappears |
| `09-dock-limit-2.png` | hover: the name appears above in Spectral |
| `09-dock-limit-3.png` | too many windows: only the running group scrolls |
| **10 · Notifications** | |
| `10-notifications-at-rest.png` | icon and title only |
| `10-notifications-limit-1.png` | critical urgency: alert outline, never expires on its own |
| `10-notifications-limit-2.png` | past the queue cap: the cell becomes a count |
| `10-notifications-limit-3.png` | dwell expired: the cell is gone, the tissue closed |
| `10-notifications-hover.png` | the whole notification with the actions it carries |
| `10-notifications-history.png` | grouped by application; do not disturb lives here |
| **11 · Connectivity** | |
| `11-connectivity-at-rest.png` | three active connections, one glyph each |
| `11-connectivity-limit-1.png` | Wi-Fi only: the cell at its minimum |
| `11-connectivity-limit-2.png` | two connections: one more glyph |
| `11-connectivity-limit-3.png` | none: the cell is gone, the tissue closed on its neighbours |
| `11-connectivity-expanded.png` | one well per family, each with its switch |
| `11-connectivity-expanded-password.png` | the network row opens into a field, primary outline and caret |
| `11-connectivity-expanded-password-error.png` | wrong password: alert outline, reason below, text kept |
| **12 · Settings** | |
| `12-settings-at-rest.png` | the mark; the only place it appears |
| `12-settings-expanded-appearance.png` | opacity, blur, radius, scale, three margins, timing |
| `12-settings-expanded-structure.png` | monitor, six tissue slots, membrane visibility, chosen tissue |
| `12-settings-expanded-structure-cell-picker.png` | "+ Cell": a capsule opens to the side with what is missing |
| `12-settings-expanded-cells.png` | visibility as a segmented control, unavailable options dimmed |
| `12-settings-expanded-monitors.png` | dragged and snapped, including one below the other |
| `12-settings-expanded-keybinds.png` | add, edit, remove; one row recording a combination |
| **13 · Launcher** | |
| `13-launcher-at-rest.png` | field, results, matched letters in the primary |
| `13-launcher-limit-1.png` | no results: one line, the field stays put |
| `13-launcher-limit-2.png` | just invoked, empty field: the most used |
