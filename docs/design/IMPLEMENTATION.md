# Bioma — implementation traps

Things that look like design detail and are technical constraints. Each of them has already
cost an error in prototype. **Read this before writing the first QML component, not after.**

---

## Outline and clipping

- The rim is a **separate shape on the edge**, not a border colour: it runs from light at the
  top to green at mid-height.
- **Any clipping on the container eats it**: no `overflow: hidden` on a cell, no `clip: true`
  in QML.
- Ellipsis goes on the **text**, not on the cell. That is exactly what made the outline
  disappear in the first version of the window title.
- Where scrolling must clip — the workspaces list, the settings panels — clip the **well**,
  which has no rim, never the panel.

## Thin lines and scale

- Threads 1.3 px, outlines 1 px and icon strokes are **critical dimensions**: on fractional
  scale they must be rounded to the physical pixel, or they smear and disappear.
- Round only those. Layouts stay fluid in logical units.
- The tissue fill must be drawn **only in the band**, clipping out the cell areas, or the blur
  shows through two layers.

## Threads and anchors

- Threads **touch the edge** of both shapes. Compute them from geometry, never place them by
  eye.
- The attachment is always at the **centre** of the connected shape: vertical centre for
  horizontal threads, cap centre for vertical ones — and the cap is concentric with the first
  element it contains.
- In vector drawing the surface must have **the same measurements as its coordinate system**.
  If the height and the drawing area do not match, everything is rescaled by a few percent and
  the threads come loose without anything looking wrong. This happened in the Vitals card.
- In QML the thread is a child of the common container, with its ends bound to the anchors of
  both shapes: that way it stays attached **during** the opening, which is the only time it is
  seen to move.

## Growth and reversibility

- Animate **width and height**, never a scale: scaling deforms the outline, the radii and the
  text.
- Content enters **after** the shape is at size, with opacity plus 4 px upward. Text is never
  scaled.
- Animations are **reversible from wherever they are**, never queued.
- Radii have a limit: never beyond half the smaller dimension, and the inner radius never goes
  below zero.

## Waves and cycles

- The wave path must extend past the circle **by at least the translation**, on both sides, or
  at the end of a cycle an empty edge is left and the movement appears to stop.
- The translation is **exactly one period** of the wave: only then does the cycle close on
  itself.
- The liquid level is data, not animation: it changes with memory, not with time.

## Colour

- Colour is an **animated singleton**, never a value copied inside cells: that is what makes it
  possible to retint the desktop live.
- The three state colours are **fixed and hand-written**, in a light and a dark variant. They do
  not pass through matugen, or a blue wall would turn them into three blues.
- Derived roles — elevated surface, muted text, borders, shadows — are computed from the
  background, not asked of the user.
- Light or dark is **deduced from the background luminance**, not configured.
- A theme change must cross **all surfaces together** in one transition: if each cell animates
  on its own, the desktop changes colour in patches.

## Text and numbers

- **Tabular figures always**: without them the width dances on every update and the tissue
  reflows for nothing.
- Fonts are declared as **roles** — technical and expressive — not by name: a machine without
  Orbitron or Spectral degrades instead of breaking.
- Gradient digits are **filled** with the gradient, not coloured: in QML that is a text fill,
  not a colour property.
- All durations live in **one named timing set**, never scattered constants.

## Controls and selection

- A segmented control's selection change is **animated**: the pill slides to the chosen option
  with the opening timings. This applies to the time format, the capture modes, the palette
  source, cell visibility.
- The switch moves its knob rather than swapping two images; the slider follows the pointer
  without steps.
- Errors live **where they happened**: the field's outline turns to the alert colour and the
  reason appears underneath, in Spectral. No dialog. The field **does not clear itself**.

## Audio visualiser

- The band's behaviour — response, damping, peak hold, frequency split — is **defined against
  the Sinestesia code**, the author's existing audio application. It is not reinvented here and
  not taken from a library. The design fixes the form (capsule bars, symmetry from the centre,
  gradient over the band); the behaviour comes from there.
- Read it **before** writing the renderer, not after: if Sinestesia draws with a shader it ports
  to a QML `ShaderEffect`; if it draws with Cairo or a GTK4 snapshot it does not port — and
  those are two different work estimates.
- Capture and FFT must be split from rendering into a headless process emitting bands. Two
  processes capturing the same audio is an error that does not show immediately and is paid for
  later.
- The gradient is defined over the height of the **band**, not of the single bar: a short bar
  samples the middle of the gradient, a tall one runs its whole length. It is the only way to
  keep one light source on an element that changes shape thirty times a second.

## Capture

- **H.264 requires even dimensions**, and a hand-drawn region produces odd numbers: round the
  region before passing it to the recorder, or encoding fails.
- Region coordinates are in **physical pixels**; full-screen capture starts from the output's
  logical geometry multiplied by its scale. Convert before passing on.
- Window mode needs **window geometry from the niri IPC** — the third service depending on it.
- Record into a temporary directory and move to the final location **only on save**, or a
  discarded video still lands among the user's files.
- The selection surface is **Bioma's own**, not `slurp`: it reuses the full-screen input
  surface so the visual identity holds across the whole screen. Capture itself stays with
  `grim` and the recorder.

## Visibility and focus

- **Interaction suspends disappearance.** If the user is interacting with a cell when its
  condition lapses, it does not vanish under their hands. On pointer exit the timer **resumes
  where it stopped**; it does not restart, or a stray hover would keep the cell alive
  indefinitely. This is **mandatory** for notifications, because the actions live in hover.
- **Invoked cells acquire keyboard focus** and release it on close.
- The **Wi-Fi password field** is the edge case of the whole visibility system: an expanded
  conditional cell must be able to request focus and give it back, and meanwhile "interaction
  suspends disappearance" must keep it alive — a network dropping while the password is being
  typed cannot make the field disappear.
- **Highly intermittent cells** (volume) either get a longer dwell or live in a tissue of their
  own, so they do not make their neighbours dance.

## Per-cell notes

- **Dock** — the reveal zone must be **inside the surface bounds**: an error Prisma already hit
  and fixed, and it comes back identical on an auto-hiding membrane.
- **Dock** — the expensive part is invisible: window tracking, desktop-file icon resolution,
  matching processes to applications. It is in Prisma's dock components and ports from there.
- **Notifications** — the queue needs a cap: twenty notifications in ten seconds (a system
  update) would otherwise occupy the cell for minutes. Past the cap, collapse to a count and
  defer to the history. Non-expiring urgent notifications must not block the queue.
- **Session** — the user avatar lives in AccountsService and must be written **over DBus**, not
  by copying a file. More work than it appears for a function used twice in the life of an
  installation: mark it optional, not first-pass. The cell must work perfectly reading it only.
- **Theme** — the wallpaper folder is a config value and **thumbnails must be generated and
  cached**, or a carousel reading fifty images on every open is not the same component.
- **Settings** — writing into niri's own config is accepted and already implemented in Prisma;
  the rule is to **preserve the sections not being touched**. Monitor drag-and-drop with
  magnetic snap and the keybinds page that parses the `binds` block both exist there.
- **Launcher** — Prisma's launcher gives the easy 20%: enumerating desktop files and launching.
  The real work — **fuzzy matching, frequency ranking, robust icon resolution** — is absent and
  must be written. The highlighted letters in the design are not a graphic flourish: they imply
  the algorithm returns **which** characters it matched, not just a score. Discovering that
  later means rewriting it.

## Accessibility

- `prefers-reduced-motion` stops indicator animation. But the audio band does not stop
  completely — it would be indistinguishable from silence — it becomes a single bar following
  overall loudness.
- Every animated indicator must still be readable when still: the value is in the form and the
  colour, not only in the movement.
