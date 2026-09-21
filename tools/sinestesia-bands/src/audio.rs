//! PipeWire capture, adapted from Sinestesia's `src/audio.rs`.
//!
//! One stream on the default sink's monitor — what leaves the machine — or on
//! the default source, negotiated as stereo f32 at 48 kHz and summed to one
//! channel as it arrives. Bioma's band is a single spectrum, so there is no
//! reason to carry two.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

pub const SAMPLE_RATE: u32 = 48_000;
const CHANNELS: u32 = 2;

/// What to listen to.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// The default sink's monitor: everything the machine is playing.
    Output,
    /// The default source: a microphone.
    Input,
}

/// The samples the capture thread writes and the analyser reads.
pub struct Ring {
    inner: Mutex<VecDeque<f32>>,
    capacity: usize,
}

impl Ring {
    pub fn new(capacity: usize) -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(VecDeque::with_capacity(capacity)),
            capacity,
        })
    }

    fn push_interleaved(&self, data: &[f32], channels: usize) {
        if channels == 0 {
            return;
        }
        let frames = data.len() / channels;
        let mut buf = self.inner.lock().unwrap();
        for f in 0..frames {
            let base = f * channels;
            // Summed to mono here rather than in the analyser: it is one add
            // per frame at the edge instead of a second transform later.
            let mut sum = 0.0;
            for c in 0..channels {
                sum += data[base + c];
            }
            buf.push_back(sum / channels as f32);
        }
        let overflow = buf.len().saturating_sub(self.capacity);
        if overflow > 0 {
            buf.drain(0..overflow);
        }
    }

    /// The last `out.len()` samples, zero-padded on the left when there are not
    /// yet enough of them.
    pub fn snapshot(&self, out: &mut [f32]) {
        let buf = self.inner.lock().unwrap();
        let n = out.len();
        let available = buf.len();
        if available >= n {
            for (i, s) in buf.iter().skip(available - n).enumerate() {
                out[i] = *s;
            }
        } else {
            let pad = n - available;
            out[..pad].iter_mut().for_each(|x| *x = 0.0);
            for (i, s) in buf.iter().enumerate() {
                out[pad + i] = *s;
            }
        }
    }
}

/// Starts the capture on its own thread and returns once it is running. The
/// thread lives as long as the process: this program exists only while
/// something is listening to it, and the shell stops it by closing it.
pub fn start(ring: Arc<Ring>, source: Source) -> std::thread::JoinHandle<()> {
    std::thread::Builder::new()
        .name("sinestesia-capture".into())
        .spawn(move || {
            if let Err(error) = run(ring, source) {
                eprintln!("sinestesia-bands: capture stopped — {error}");
                std::process::exit(1);
            }
        })
        .expect("cannot start the capture thread")
}

struct UserData {
    format: pipewire::spa::param::audio::AudioInfoRaw,
    ring: Arc<Ring>,
}

fn run(ring: Arc<Ring>, source: Source) -> anyhow::Result<()> {
    use pipewire as pw;
    use pw::spa;
    use spa::param::format::{MediaSubtype, MediaType};
    use spa::param::format_utils;
    use spa::pod::Pod;

    pw::init();

    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;

    let capture_sink = source == Source::Output;

    let mut props = pw::properties::properties! {
        *pw::keys::MEDIA_TYPE => "Audio",
        *pw::keys::MEDIA_CATEGORY => "Capture",
        *pw::keys::MEDIA_ROLE => "Music",
        *pw::keys::NODE_NAME => "bioma-sinestesia",
    };
    if capture_sink {
        props.insert(*pw::keys::STREAM_CAPTURE_SINK, "true");
    }

    let stream = pw::stream::StreamRc::new(core, "bioma-sinestesia", props)?;

    let data = UserData {
        format: Default::default(),
        ring,
    };

    let _listener = stream
        .add_local_listener_with_user_data(data)
        .param_changed(|_, user_data, id, param| {
            let Some(param) = param else { return };
            if id != pw::spa::param::ParamType::Format.as_raw() {
                return;
            }
            let Ok((media_type, media_subtype)) = format_utils::parse_format(param) else {
                return;
            };
            if media_type != MediaType::Audio || media_subtype != MediaSubtype::Raw {
                return;
            }
            let _ = user_data.format.parse(param);
        })
        .process(|stream, user_data| {
            let Some(mut buf) = stream.dequeue_buffer() else { return };
            let datas = buf.datas_mut();
            if datas.is_empty() {
                return;
            }
            let channels = user_data.format.channels().max(1) as usize;
            let data = &mut datas[0];
            let chunk = data.chunk().size() as usize;
            let Some(slice) = data.data() else { return };
            let floats = (chunk / std::mem::size_of::<f32>()).min(slice.len() / 4);
            if floats == 0 {
                return;
            }
            let samples =
                unsafe { std::slice::from_raw_parts(slice.as_ptr().cast::<f32>(), floats) };
            user_data.ring.push_interleaved(samples, channels);
        })
        .register()?;

    let mut info = spa::param::audio::AudioInfoRaw::new();
    info.set_format(spa::param::audio::AudioFormat::F32LE);
    info.set_rate(SAMPLE_RATE);
    info.set_channels(CHANNELS);
    let mut position = [0u32; spa::param::audio::MAX_CHANNELS];
    position[0] = pw::spa::sys::SPA_AUDIO_CHANNEL_FL;
    position[1] = pw::spa::sys::SPA_AUDIO_CHANNEL_FR;
    info.set_position(position);

    let values: Vec<u8> = pw::spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &pw::spa::pod::Value::Object(pw::spa::pod::Object {
            type_: pw::spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
            id: pw::spa::param::ParamType::EnumFormat.as_raw(),
            properties: info.into(),
        }),
    )?
    .0
    .into_inner();

    let mut params = [Pod::from_bytes(&values).ok_or_else(|| anyhow::anyhow!("invalid pod"))?];

    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::AUTOCONNECT
            | pw::stream::StreamFlags::MAP_BUFFERS
            | pw::stream::StreamFlags::RT_PROCESS,
        &mut params,
    )?;

    mainloop.run();
    Ok(())
}
