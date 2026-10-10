# Exported browser audio mixer

Production `OpenSpadesAudio` explicitly sets both stereo and spatial voices to
`AudioServer.PLAYBACK_TYPE_STREAM`. Godot's default Web Sample path lacks
AudioEffects and has documented positional limitations. Stream preserves the
actual source mono/stereo routing, inverse-distance gains and the engine mixer;
its single-threaded browser latency must be measured on target devices.
[Official export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#audio-playback),
[playback enum](https://docs.godotengine.org/en/stable/classes/class_audioserver.html#enum-audioserver-playbacktype).

`tests/audio/export_web_probe.py` exports the real audio service and its native
PCM fixture into an isolated project. Production resource loading, original
sounds, voice creation, attenuation/panning and the post-mixer capture remain
unchanged. The unused terrain type is stubbed with an assertion if queried;
this fixture does not claim world/environmental integration. No Main,
preferences, microphone or browser filesystem writes are involved. A real
Godot Button click starts playback under the browser autoplay policy.

The earlier exported probe reported **106 checks, 0 failures**, AudioWorklet at
48kHz, Stream playback. All three original guns in first/world modes, head
feedback, chat/menu/alert, mono left/center/right, stereo preservation,
distance attenuation and capture enable/disable were exercised. Head-feedback
amplitude ratio was .200000018;8m/2m distance ratio .25485709 within the fixture's
tolerance. Both channels contain finite nonzero samples, without capture
overflow. Headless routing now reports128/0 including explicit Stream policy.

The first isolated export omitted the original manifest, producing JSON
resource-catalog errors although mixer assertions passed. The helper now copies
the real manifest; a fresh-tab re-exported run reported106/0 and an empty
warning/error log. Probe pages are temporary and
do not ship as game entry points.

This proves exported post-mixer signal/routing after a user gesture. Capture
runs on a muted diagnostic bus, so `browser_listening_verified=false` is
explicit. It does not accept perceived sound quality, hardware output latency,
full-client autoplay/focus behavior or sustained frame performance. The fixture
also reports time until it observes the first nonzero captured sample; that
includes polling/mixer scheduling and is not a speaker-output latency measure.
The fresh-tab run observed first signals in8.8–59.9ms (first rifle48.9ms,
first-person SMG19.8ms, shotgun24.4ms). These are individual observations on
the build workstation, not a bound, distribution or end-to-end latency claim.

Export: `python tests/audio/export_web_probe.py --godot .tools/godot/Godot_v4.7.2-stable_win64_console.exe`;
serve `.cache/audio-web-probe/build`, open index.html and click Run browser PCM
proof. The result is the visible `audio-probe-results` JSON element.

## Current source clamp and environmental DSP proof

2026-10-10: the revised original-sound probe passed **113/0** in a fresh tab,
AudioWorklet48kHz/Stream. Full post-DSP head feedback at native gain.2 against
reference gain.1 has amplitude ratio2.000000300; the separate full-gain signal
correctly reaches the limiter rather than serving as a linear reference.
The8m/2m ratio is.254857088. Captured samples are finite, with no discarded
frames. First nonzero-signal observations range14.5–32.1ms; they include
polling/mixer scheduling and do not measure hardware latency. The export PCK
SHA256 is `361999b8bd16002d95c0d12081d6cb7236182996917af3d4405ccab3001ca6a6`.
The complete local DOM report is `.cache/previews/audio-source-web.json`.

The separate `--environment` export passed **64/0** with actual post-DSP PCM,
the same AudioWorklet48kHz/Stream driver and empty fresh-tab warning/error logs.
The deterministic fixture uses real production audio/environment services and
VoxelData source rays: blocked/clear HF amplitude ratio.117376621 and LF
ratio.999824729. A20m early reflection peaks at.061729167s versus source20/324.
Source decay1.00625s measures.9229375s; source minimum.1s measures.7235625s,
the documented Freeverb tail floor. Enabled limiting peaks.966088295; disabled
negative control9.599780083, and reserved Master gain4 peaks.241546929.
EFX-off and UI controls have zero late energy; signals remain finite without
capture overflow. PCK SHA256:
`c6b4c2d3dcc4333d62008b028451e8346002db5cf27d7d9c728210f5da3a33cb`.
The complete report is `.cache/previews/audio-environment-web.json`.

Both exports are isolated diagnostic projects, absent from the game entry point.
They leave preferences untouched and mute their diagnostic output; subjective
listening, actual Main scene integration and hardware output remain separate.
Native companion fixtures passed134/0 original PCM and81/0 environmental PCM
on both WASAPI48kHz and Dummy44.1kHz. See audio.md for source/backend differences.
