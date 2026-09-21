//! The band contract, taken from Sinestesia's `src/dsp.rs`.
//!
//! Every figure here is that program's, not a new choice: a Hann window over
//! 2048 samples, logarithmic bins from 30 Hz to 16 kHz, the peak bin inside
//! each band, a dB mapping where −70 dB is nothing and 0 dB is full, and an
//! asymmetric one-pole smoothing that rises quickly and falls slowly. Bioma's
//! design fixes the form of the band and states plainly that the behaviour is
//! defined against Sinestesia, which did that work against real audio.
//!
//! What is *not* taken: the stereo imaging analyser. Bioma's band is one
//! spectrum of what leaves the machine, so the two channels are summed before
//! the transform rather than analysed against each other.

use rustfft::{num_complex::Complex, Fft, FftPlanner};
use std::sync::Arc;

pub const FFT_SIZE: usize = 2048;

const FREQ_MIN: f32 = 30.0;
const FREQ_MAX: f32 = 16_000.0;

/// Rising and falling coefficients of the temporal smoothing. Asymmetric on
/// purpose: a transient has to arrive at once and leave slowly, or the band
/// reads as noise rather than as sound.
const ATTACK: f32 = 0.45;
const DECAY: f32 = 0.18;

pub struct Analyzer {
    fft: Arc<dyn Fft<f32>>,
    window: Vec<f32>,
    fft_buf: Vec<Complex<f32>>,
    band_edges: Vec<usize>,
    smoothed: Vec<f32>,
    gain: f32,
}

impl Analyzer {
    pub fn new(bands: usize, sample_rate: u32, gain: f32) -> Self {
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(FFT_SIZE);

        let window: Vec<f32> = (0..FFT_SIZE)
            .map(|n| {
                let x = std::f32::consts::PI * 2.0 * n as f32 / (FFT_SIZE as f32 - 1.0);
                0.5 - 0.5 * x.cos()
            })
            .collect();

        Self {
            fft,
            window,
            fft_buf: vec![Complex::new(0.0, 0.0); FFT_SIZE],
            band_edges: band_edges(bands, sample_rate),
            smoothed: vec![0.0; bands],
            gain,
        }
    }

    /// One frame: the last `FFT_SIZE` samples in, the smoothed bands out.
    pub fn analyze(&mut self, samples: &[f32]) -> &[f32] {
        for i in 0..FFT_SIZE {
            self.fft_buf[i] = Complex::new(samples[i] * self.window[i], 0.0);
        }
        self.fft.process(&mut self.fft_buf);

        for b in 0..self.smoothed.len() {
            let lo = self.band_edges[b];
            let hi = self.band_edges[b + 1].max(lo + 1);

            // The peak bin, not the mean: a mean spreads a sharp partial across
            // a whole band and the band stops following the music.
            let mut peak = 0.0f32;
            for bin in lo..hi {
                let m = self.fft_buf[bin].norm();
                if m > peak {
                    peak = m;
                }
            }

            let mag = peak / (FFT_SIZE as f32 * 0.5);
            let db = 20.0 * (mag + 1e-9).log10();
            let target = (((db + 70.0) / 70.0).clamp(0.0, 1.0) * self.gain).clamp(0.0, 1.0);

            let coeff = if target > self.smoothed[b] { ATTACK } else { DECAY };
            self.smoothed[b] += (target - self.smoothed[b]) * coeff;
        }

        &self.smoothed
    }
}

/// The FFT bin each band starts at, on a logarithmic scale. Music is heard
/// logarithmically, and a linear split gives forty bands of cymbal and two of
/// everything a bass line does.
fn band_edges(bands: usize, sample_rate: u32) -> Vec<usize> {
    let nyquist = sample_rate as f32 / 2.0;
    let bin_hz = nyquist / (FFT_SIZE as f32 / 2.0);
    let log_min = FREQ_MIN.log10();
    let log_max = FREQ_MAX.log10();

    (0..=bands)
        .map(|i| {
            let t = i as f32 / bands as f32;
            let freq = 10f32.powf(log_min + t * (log_max - log_min));
            ((freq / bin_hz).round() as usize).min(FFT_SIZE / 2 - 1)
        })
        .collect()
}

/// The centre frequency of a band, for anything that has to say what it is
/// looking at.
pub fn band_center_hz(band: usize, bands: usize) -> f32 {
    let t = (band as f32 + 0.5) / bands as f32;
    FREQ_MIN * (FREQ_MAX / FREQ_MIN).powf(t)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A tone lands in the band that holds it and nowhere else. This is the
    /// test that says the binning and the dB mapping are right without anyone
    /// having to listen to anything.
    #[test]
    fn a_tone_lights_its_own_band() {
        const RATE: u32 = 48_000;
        const BANDS: usize = 64;
        let mut analyzer = Analyzer::new(BANDS, RATE, 1.0);

        let tone: Vec<f32> = (0..FFT_SIZE)
            .map(|n| {
                (std::f32::consts::TAU * 1000.0 * n as f32 / RATE as f32).sin() * 0.5
            })
            .collect();

        // Several frames, because the smoothing rises over a few of them.
        let mut last = vec![0.0; BANDS];
        for _ in 0..40 {
            last = analyzer.analyze(&tone).to_vec();
        }

        let expected = (0..BANDS)
            .min_by(|&a, &b| {
                let da = (band_center_hz(a, BANDS) - 1000.0).abs();
                let db = (band_center_hz(b, BANDS) - 1000.0).abs();
                da.partial_cmp(&db).unwrap()
            })
            .unwrap();

        let loudest = (0..BANDS)
            .max_by(|&a, &b| last[a].partial_cmp(&last[b]).unwrap())
            .unwrap();

        assert!(
            (loudest as i32 - expected as i32).abs() <= 1,
            "1 kHz landed in band {loudest}, expected about {expected}"
        );
        assert!(last[loudest] > 0.5, "a half-scale tone should be loud, got {}", last[loudest]);

        // And silence goes back down to nothing.
        let quiet = vec![0.0; FFT_SIZE];
        for _ in 0..200 {
            analyzer.analyze(&quiet);
        }
        let resting = analyzer.analyze(&quiet).to_vec();
        assert!(
            resting.iter().all(|v| *v < 0.01),
            "silence should empty the band, got {:?}",
            resting.iter().cloned().fold(0.0f32, f32::max)
        );
    }
}
