# sinestesia-bands

Capture and FFT, split out of the shell, emitting bands on stdout.

`docs/design/IMPLEMENTATION.md` requires the split and says why: two processes
capturing the same audio is an error that does not show immediately and is paid
for later. Quickshell cannot read a PipeWire stream in any case.

Everything about how a band behaves — Hann window over 2048 samples,
logarithmic bins from 30 Hz to 16 kHz, the peak bin inside each band, −70 dB to
0 dB mapped onto 0 to 1, attack 0.45 and decay 0.18 — is taken from
**Sinestesia**, the author's own visualiser, which did that work against real
audio. `docs/design/CELLS.md` §04 fixes the form of the band and states that the
behaviour is defined there. Nothing here is a new choice; the stereo imaging
analyser is the one part deliberately left behind, because Bioma's band is one
spectrum of what leaves the machine.

## Build

```sh
cargo build --release
```

`services/Sinestesia.qml` looks for the binary at
`tools/sinestesia-bands/target/release/sinestesia-bands`. Without it the service
reports itself unavailable and the cell does not appear: half a visualiser is
worse than none.

Needs the PipeWire development headers (`libpipewire-0.3`), which the Rust
bindings link against.

## Running it by hand

```sh
./target/release/sinestesia-bands --bands 64 --fps 60 --gain 1.0 --source output
```

One line per frame, two hexadecimal digits per band, no separators — the left
channel's bands first, then the right channel's, so a line is twice `--bands`
pairs long:

```text
00040b1f3a5c…   left, low to high, then right, low to high
```

Two channels because the band is mirrored from the middle: the left half of the
drawing is the left channel and the right half the right one, with the low
frequencies meeting at the centre and the high ones at the outside. Which way
round each half is drawn is the shell's business; this emits both in their
natural order.

Hexadecimal rather than JSON because the reader is a QML string parser running
sixty times a second: fixed width, two characters per band, no allocation per
value, and still readable in a terminal. `--source input` listens to the
microphone instead of the sink's monitor.

The process exits when its stdout closes, so the shell stops it by stopping
reading.

## Tests

```sh
cargo test
```

One test, and it is the one that matters: a 1 kHz tone has to land in the band
that holds 1 kHz and silence has to empty the band. It runs without a sound
card and without anyone having to listen to anything.
