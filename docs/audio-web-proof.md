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

The actual exported probe reported **106 checks, 0 failures**, AudioWorklet at
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
