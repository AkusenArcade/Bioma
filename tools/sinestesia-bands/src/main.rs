//! Capture and FFT, split out of the shell, emitting bands.
//!
//! `docs/design/IMPLEMENTATION.md` requires this separation and says why: two
//! processes capturing the same audio is an error that does not show
//! immediately and is paid for later. So there is one capture, here, and the
//! shell draws what it is told.
//!
//! One line per frame on stdout, two hexadecimal digits per band, no
//! separators, newline at the end — the left channel's bands first, then the
//! right channel's, so a line is twice `--bands` pairs long:
//!
//! ```text
//! 00040b1f3a5c…  ← left, low to high, then right, low to high
//! ```
//!
//! Two channels because the band is mirrored from the middle: the left half of
//! the drawing is the left channel and the right half the right one, low
//! frequencies meeting at the centre. Which way round each half is drawn is the
//! shell's business; this emits both in their natural order.
//!
//! Hexadecimal rather than JSON or decimals because the reader is a QML
//! string parser running sixty times a second: two characters per band, a fixed
//! width, no allocation per value, and it is still readable by a person with a
//! terminal. A band is 0–255, which is finer than any screen can draw it.
//!
//! The process exists only while the shell is listening: when stdout closes it
//! stops, so nothing has to be told to shut it down.

mod audio;
mod dsp;

use std::io::Write;
use std::time::{Duration, Instant};

struct Options {
    bands: usize,
    fps: u32,
    gain: f32,
    source: audio::Source,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            // Per channel, and the finest the shell asks for: it folds them
            // down to the seven or seventeen a half of the cell draws. One
            // process serves both the contracted band and the expanded one.
            bands: 64,
            fps: 60,
            gain: 1.0,
            source: audio::Source::Output,
        }
    }
}

fn parse(args: impl Iterator<Item = String>) -> anyhow::Result<Options> {
    let mut options = Options::default();
    let mut args = args.peekable();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--bands" => {
                options.bands = args
                    .next()
                    .ok_or_else(|| anyhow::anyhow!("--bands wants a number"))?
                    .parse::<usize>()?
                    .clamp(1, 256)
            }
            "--fps" => {
                options.fps = args
                    .next()
                    .ok_or_else(|| anyhow::anyhow!("--fps wants a number"))?
                    .parse::<u32>()?
                    .clamp(1, 240)
            }
            "--gain" => {
                options.gain = args
                    .next()
                    .ok_or_else(|| anyhow::anyhow!("--gain wants a number"))?
                    .parse::<f32>()?
                    .clamp(0.1, 10.0)
            }
            "--source" => {
                options.source = match args
                    .next()
                    .ok_or_else(|| anyhow::anyhow!("--source wants output or input"))?
                    .as_str()
                {
                    "input" => audio::Source::Input,
                    "output" => audio::Source::Output,
                    other => anyhow::bail!("unknown source: {other}"),
                }
            }
            "--help" | "-h" => {
                println!(
                    "sinestesia-bands — spectrum bands for Bioma, on Sinestesia's contract\n\
                     \n\
                     --bands N    bands per channel (default 64)\n\
                     --fps N      frames per second (default 60)\n\
                     --gain F     multiplier applied after the dB mapping (default 1.0)\n\
                     --source S   output (the sink's monitor) or input (default output)\n\
                     \n\
                     One line per frame: the left channel's bands then the\n\
                     right channel's, two hex digits each, 00 to ff."
                );
                std::process::exit(0);
            }
            other => anyhow::bail!("unknown option: {other}"),
        }
    }

    Ok(options)
}

fn main() -> anyhow::Result<()> {
    let options = parse(std::env::args().skip(1))?;

    // Two frames of headroom: the capture thread writes in bursts and the
    // analyser reads a whole window at a time.
    let ring = audio::Ring::new(dsp::FFT_SIZE * 2);
    let _capture = audio::start(ring.clone(), options.source);

    // One analyser per channel: each keeps its own smoothing, which is the
    // point — a sound that moves across the image has to arrive on one side
    // and leave the other, not average into the middle.
    let mut left = dsp::Analyzer::new(options.bands, audio::SAMPLE_RATE, options.gain);
    let mut right = dsp::Analyzer::new(options.bands, audio::SAMPLE_RATE, options.gain);
    let mut samples = vec![0.0f32; dsp::FFT_SIZE];

    // Written once and reused: at sixty frames a second, an allocation per
    // frame is an allocation sixty times a second for as long as the cell is
    // on screen.
    let mut line = String::with_capacity(options.bands * 4 + 1);

    let frame = Duration::from_secs_f64(1.0 / options.fps as f64);
    let mut next = Instant::now();
    let stdout = std::io::stdout();

    loop {
        line.clear();

        ring.snapshot(audio::Channel::Left, &mut samples);
        write_bands(&mut line, left.analyze(&samples));

        ring.snapshot(audio::Channel::Right, &mut samples);
        write_bands(&mut line, right.analyze(&samples));

        line.push('\n');

        // A closed pipe is how the shell says it has stopped looking.
        let mut handle = stdout.lock();
        if handle.write_all(line.as_bytes()).is_err() || handle.flush().is_err() {
            return Ok(());
        }
        drop(handle);

        next += frame;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            // Behind — a suspend, a stalled reader. Start again from now
            // rather than running a burst of frames to catch up on a band
            // nobody saw.
            next = now;
        }
    }
}

fn write_bands(line: &mut String, bands: &[f32]) {
    for value in bands {
        let byte = (value.clamp(0.0, 1.0) * 255.0).round() as u8;
        line.push(nibble(byte >> 4));
        line.push(nibble(byte & 0x0f));
    }
}

fn nibble(value: u8) -> char {
    char::from_digit(value as u32, 16).unwrap_or('0')
}
