# Application templates

The palette leaves the shell through these: one template per application, the
script that hooks the rendered file into that application's own configuration
(`apply.sh`), and the one that unhooks it (`undo.sh`). `builtin.toml` lists them
and says where each one is written.

They are **Noctalia's**, taken from `noctalia-dev/noctalia` at
`61aa22730c434500fd3f2048eba47658b1f20aad` under the MIT licence below, with
the rendered files renamed from `noctalia.*` to `bioma.*` so that the two shells'
hooks never touch each other's. Bioma's changes on top:

- `niri/`: the rendered file is `bioma-theme.kdl` — `bioma.kdl` is the
  repository's own niri file, which the upstream include pattern would have
  matched and `undo.sh` would have removed — and it sets the windows' corner
  radius from the shell's (`{{bioma.window_radius}}`).
- `qt/apply.sh` is new, and `qt/undo.sh` extended: qt5ct and qt6ct read the
  colour scheme their own config names, so the rendered scheme is pointed at
  there (`color_scheme_path`, `custom_palette`) and unpointed on undo.
- `btop/apply.sh` and `cava/apply.sh` write a config holding only the theme
  when there is none, instead of reporting it: both programs fill a partial
  config with their defaults.
- `scripts/themes` runs every hook after every file is written, and one shared
  command once: GTK's hook rewrites both gtk.css files.

`scripts/themes` renders them. Colours are named as matugen names them
(`{{colors.primary.default.hex}}`, `rgb_csv`, `hex_stripped`, `| darken x`);
`services/Templates.qml` translates Bioma's palette into those names, so the
same templates serve a matugen palette and a Bioma one.

---

MIT License

Copyright (c) 2026 noctalia-dev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
