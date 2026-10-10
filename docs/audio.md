# Original audio layers and browser backend

Baseline: OpenSpades v0.1.3 `dcf449c845d509bbde9d79239b32d201c1389961`.
Source: `Resources/Scripts/Skin/{Rifle,SMG,Shotgun}/{View,ThirdPerson}.as`,
`Sources/Client/ClientPlayer.cpp:1056–1161`, `Client_Update.cpp:529–541,583–795,963–1066,1107–1215`,
`Sources/Audio/ALDevice.cpp:206–287` and `Sources/Client/IAudioDevice.h`.

`game/audio/openspades_audio.gd` owns source sound layers and bounded playback.
Main owns one service with the current camera listener; gameplay calls it through
events. Its private random generator selects sound variations independently of
projectile spread. Resource lookup goes through OpenSpadesExtensions, preserving
converted-path aliases and active ZIP overrides.

## Migrated behavior

- Rifle and shotgun play four original fire layers in both views. SMG first person
  plays V2Local1–4 plus V2AmbienceSmall/Large1–4; third person adds far/stereo layers.
  Gains and reference distances follow each source skin.
- Environmental ambience casts the source 24 fixed directions plus their opposite
  directions, up to 40m. Integer-corner distances, the strict seven-hit threshold,
  feedback, room size and small/large choice are retained. The environmental-audio
  switch suppresses the room layer.
- Reload gains are .2; shotgun shell completion plays CockLocal/Cock. Tool-swap
  signals play the appropriate RaiseLocal after lowering the old tool. Dry fire and
  restock use the native listener-relative offset.
- Explosions play five land or three underwater layers with native gains/reference
  distances. Debris uses the downward voxel hit. Footsteps, jumping/landing, collapse,
  grenade bounce/water entry, flesh and objective feedback are routed separately.
- Ogg identification packets determine channel count. Mono voices use Godot spatial
  panning. Stereo world voices keep their channels and use manual inverse-distance
  gain, as native OpenAL does for stereo. Listener-relative mono sources pan at their
  offset without falloff. Inverse attenuation is
  `volume / max(distance / referenceDistance, 1)`, without an extra 150m linear fade.
  The effective source gain is then clamped to OpenAL's default MAX_GAIN1.
  Raw gain8/20/30 metadata is retained: it extends range before this cap.
- At most 128 voices live at once. Teardown stops streams and releases nodes. Audio
  playback references need a mixing cycle to drain before a test process exits.

Main persists panning, weapon ambience, native `s_gain` and `s_eax`, and separate
Master volume. Turning panning off retains distance gain. `cg_environmentalAudio`
selects gun ambience layers; `s_eax` controls obstruction and room DSP independently.

## Verification and remaining work

`tests/audio/test_audio.gd`: **128 checks, 0 failures**, `.cache/logs/test-audio.log`.
Independent fixtures cover source paths/gains/reference distances, every gun layer,
land/water explosions, open/enclosed room goldens, near/distant attenuation and real
mono/stereo Godot voice routing. This is a parameter/routing test, not a listening test.
Full-scene source acceptance was146/0 and integration95/0 at the movement checkpoint; the next combined checkpoint adds tool-use gating and selection regressions.
The dry-fire integration case retains reserve ammo: complete depletion must instead
activate automatic tool selection.

Godot panning and the browser backend replace OpenAL. Obstruction and parallel room
sends are implemented as the bounded Godot DSP adapter described below. HRTF backend
selection and Mumble positional integration remain platform adaptations.
The main scene routes casing contacts through the same service with native .6 reference
distance and water pitch variation. Bullet impacts play the original2-gain Block plus
Ricochet layers or one2-gain Water layer, shifted along the surface normal.
Standalone effect tests retain their isolated fallback player. Browser audibility, balance and gesture
activation need listening acceptance; headless tests do not verify them. U11 remains
incomplete until those requirements are accounted for.

## Post-mixer PCM proof

`tests/audio/render_audio.gd` creates an isolated camera/audio service and a separate
muted bus with [AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html).
It records real mixed samples. The service-owned output sends to the probe after all
DSP; voices are never reassigned around the filters or limiter. Master is muted during
this process and restored at teardown. The main scene is never
loaded, preferences are never written, and no audio-device settings are changed.

The original pre-EFX baseline on Godot4.7.2 `ed1daf0bf`, both **WASAPI48kHz + Intel UHD
Compatibility** and **Dummy44.1kHz headless**, passed **126 checks, 0 failures**.
Coverage includes original rifle/SMG/shotgun first-person/world mixes in open air,
head feedback, chat, menu hover/select and alert. Checks measure finite/nonzero PCM,
both channels, buffer overflow, original stereo differences and mirrored mono spatial
panning. Silence before playback and disabling capture are negative controls.
Integrated signal energy gives amplitude ratios `.20000002` for head feedback gain.2
and `.25485709` for a2m→8m mono source with2m reference distance on WASAPI;
the fixtures allow6% for mixer scheduling/smoothing. Headless ratios were `.19996826`
and `.24996635`. These are independent amplitude measurements, not volume metadata.

The current post-DSP version passed **134 checks, 0 failures** on both **WASAPI48kHz
with headless display** and **Dummy44.1kHz**. It uses native head-feedback gain.2
against a.1 reference, both below the limiter ceiling: measured amplitude ratios were
2.00000030 on both drivers. Full gain1 remains a separate limited diagnostic, because
its original PCM exceeds1 and cannot be a linear post-limiter reference. Gun and
full-head peaks stayed at.96605. Distance ratios were.25485709/.24996635 respectively.

Each driver writes20 stereo PCM16 WAV files plus `report.json` under
`.cache/previews/audio-pcm/{wasapi,dummy}/`. WAV headers/frame sizes were additionally
checked with Python's `wave` reader. Metrics are unscaled floats; review WAVs use the
reported per-file `wav_scale` to avoid clipping. That baseline bypassed DSP and reached
raw peaks above1 (maximum11.47564 on WASAPI); it is retained under
`.cache/previews/audio-pcm/baseline-unclamped/`. It exposed the missing AL_MAX_GAIN stage;
the current service preserves raw metadata while applying the native per-source cap
and an explicit final limiter. The process is silent;
actual exported-browser listening, autoplay activation and balance remain separate
acceptance items. The [AudioServer documentation](https://docs.godotengine.org/en/stable/classes/class_audioserver.html)
identifies the Dummy driver used by `--headless`.

From the repository root, after project resource import:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/audio/render_audio.gd --verbose
$pcmProcess = Start-Process .tools/godot/Godot_v4.7.2-stable_win64_console.exe -ArgumentList @('--path','game','--rendering-method','gl_compatibility','--script','../tests/audio/render_audio.gd','--verbose') -WindowStyle Hidden -RedirectStandardOutput .cache/logs/audio-pcm-wasapi.log -RedirectStandardError .cache/logs/audio-pcm-wasapi-errors.log -PassThru
```

Evidence: `.cache/logs/audio-pcm-headless.log`, `audio-pcm-wasapi.log` and the empty
`audio-pcm-wasapi-errors.log`. This helper is deliberately independent of main-scene
GPU/UI tests and does not turn parameter or PCM success into listening acceptance.

## Native EFX parameters and bounded Godot adapter

Source: `Sources/Audio/ALDevice.cpp:268–348,630–742`. The non-macOS default backend is
OpenAL (`Sources/Gui/SDLRunner.cpp:52–54`), with `s_eax=1`, `s_gain=1` and96 native
sources. The port keeps its existing128 logical-voice limit. OpenSpades dynamically
loads the audio backend; its repository does not pin an OpenAL Soft implementation.

The [OpenAL1.1 specification](https://www.openal.org/documentation/openal-1.1-specification.pdf)
defines default source MIN_GAIN0/MAX_GAIN1, applied after distance/cone attenuation
and before listener gain. Mono world gain is `clamp(volume*clamp(s_gain,0,4)/max(d/ref,1),0,1)`;
local gain omits distance. Native world-stereo `UpdateObstruction` rewrites AL_GAIN
without `s_gain`; that source quirk is preserved. Master is a separate output control.
`inverse_gain()` remains the raw attenuation helper; `effective_gain()` applies the cap.

`audio_environment.gd` retains the room128-sample ring: initial distances20000,
four independent triangular-random normalized directions per update, CastRay40m,
integer-corner distance, miss80, and strict distance<40 / hitCount>32 thresholds.
A forward miss retains that slot's previous opposite-hit feedback. With enough hits,
`V=mean(d²)*4π/3`, `A=mean(d)*4π`, `size=mean(d)` and `r=hits/128`; otherwise
`V=8,A=100,size=100,r=.2`. `f` is the mean of all128 feedback slots.

| Runtime parameter | Source value |
| --- | --- |
| Decay/T60 | `clamp(.161*V/A/.4,.1,20)` |
| Overall gain | `.8*r` |
| Early delay / gain | `min(size/324,.3)` / `.25*r` |
| Late relative delay / gain | `min(size/324,.1)` / `.34*r⁴*f³` |
| Static ROOM HF/LF gain | `.5929` / `1` |
| Static HF/LF decay ratio | `.83` / `1` |
| Density / diffusion | `.4287` / `1` |
| Air HF gain / HF reference / LF reference | `.9943` / `5000Hz` / `250Hz` |
| Room rolloff / HF decay limit | `0` / `true` |

The [EFX guide](https://openal-soft.org/misc-downloads/EffectsExtensionGuide.pdf)
defines late delay relative to early reflections. Thus absolute late onset is
early+late, up to.4s. Native echo/modulation depths are0; the adapter adds neither.
ALDevice has no underwater filter switch: underwater explosions use their original
separate samples. It also has no teleport-distance or SetGameMap history reset.

A world source is obstructed only when **all27** rays eye→source+{- .2,0,.2}³ hit
terrain. One clear ray proves the same predicate and permits an early exit. Listener
relative sources bypass obstruction; UI Set2D also bypasses room sends. Native direct
and auxiliary sends use the same low-pass filter with GAIN1/GAINHF.1. The port uses
the source fixed-point `cast_source_ray_legacy`, preserving native wrap/tie/corner
semantics; metric casting is only a fallback for query implementations without it.

There are **nine unique owned buses** per audio service:

- Clear/blocked dry inputs send to owned Output.
- Clear/blocked early inputs send to one HF shelf and a wet-only Delay, then Output.
- Clear/blocked late inputs send to a wet-only Delay, one HF shelf and one Reverb,
  then Output. At most one Reverb processor exists, regardless of voice count.
- Output uses one HardLimiter and sends to Master or an explicitly chosen capture bus.

Eligible logical voices have at most two synchronized stream copies; max128 logical
voices therefore means max384 physical players. Plain/stereo voices start under one
AudioServer lock; 3D voices queue together for a physics turn. This retains original
stereo content and provides a diffuse wet return. It is not a claim of sample-exact
OpenAL scheduling. Every player explicitly uses STREAM, so Web sample playback cannot
bypass bus effects. `stop()` removes only this instance's buses, copies and tails;
subsequent playback lazily recreates the graph. UI voices always have zero wet copies.

Godot's high-shelf adapter has unity LF/.1 HF for obstruction and unity LF/.5929 HF
for ROOM input, with5kHz reference. Its biquad gain is sqrt(HF gain), resonance.5.
This preserves the finite HF shelf rather than replacing it with an infinite-rolloff
cutoff. EAX density, diffusion, frequency-dependent decay, directional reflections and
early/late network topology are adapted to Godot Freeverb, not coefficient-identical.
Freeverb uses damping.2/spread1 and eight fixed combs; low-frequency decay maps through
`feedback=exp(log(.001)*.036666667/T60)`, `room_size=clamp((feedback-.7)/.28,0,1)`.
Its feedback floor prevents matching native.1s rooms; this difference is measured below.
Early return gain is `.2*r²`; late wet is `.272*r⁵*f³/.6` to account for Freeverb's wet
scale. Separate Delay effects implement true early and late onset; Freeverb predelay
feedback is disabled. Wet source gain uses the explicit historical
[OpenAL Soft1.17.2 automatic-wet policy](https://github.com/kcat/openal-soft/blob/openal-soft-1.17.2/Alc/ALu.c),
with roomRolloff0 and MAX_GAIN1; other native backend versions can differ.

The [Godot HardLimiter](https://docs.godotengine.org/en/stable/classes/class_audioeffecthardlimiter.html)
is an output adaptation, not a native game setting: ceiling-.3dB, pre_gain0, release.1s.
OpenSpades does not install a final limiter; native final conversion/limiting depends
on its loaded backend. The owned limiter reserves additional headroom when Master
amplifies after the DSP graph, without changing source metadata or shared bus settings.

Scheduling bounds are explicit: at most four room samples per1/60s wall-clock turn,
no catch-up after stalls,128 ray calls and a1.5ms query budget per render turn. The
time budget is checked before a ray or room pair; one in-progress ray/pair can overrun
it. Exact eye/origin cache entries refresh after.1s, remain known for at most.25s if
budget is exhausted, then become unknown/clear. Cache capacity is128; refresh priority
rotates. Map transactions invalidate obstruction answers. These bounded scheduling
and lifecycle rules are browser adaptations to native random1/8 active-source refresh.
The separate48-ray skin ambience query is unchanged except for selecting native CastRay.
New epochs/baseline sequence rewinds reset the room ring; ordinary block edits retain
it. This map lifecycle reset is explicit port behavior, unlike native SetGameMap.

Integration: `efx_enabled`, `source_gain`, `get_output_bus()`, `set_output_bus(name)`
and copied `debug_environment()`. Output capture must use `set_output_bus`, not change
individual voice buses; create the capture destination before the service-owned buses
so Godot's leftward bus routing applies. Setup/stop reset histories; stop releases the
query reference. World.data replacement is detected at the next render turn and releases
the old query reference. `reset_environment()` handles an in-place map replacement
with the same epoch/sequence. Neither ordinary map transactions nor player movement
reset native room statistics.

`tests/audio/test_environment.gd` covers source numeric goldens, strict32/40 boundaries,
feedback retention, all27 obstruction endpoints, clear early exit, bounded stale/unknown
answers, wall-clock/ray limits, block transaction invalidation, native gain ordering,
dry UI, max128 voices, unique buses, EFX off, query replacement/epoch/reference release
and teardown: **70 checks, 0 failures**. No Main/preferences are loaded.
`tests/audio/render_environment.gd` captures actual production DSP using independent
400Hz/10kHz tones and impulses; each driver writes16 PCM16 review WAVs and a compact
JSON report under `.cache/previews/audio-environment/<driver>/`.

On Godot4.7.2 **Dummy44.1kHz**, environmental PCM passed **81 checks, 0 failures**.
Blocked/clear amplitude was `.99983` at400Hz and `.11575` at10kHz. The20m early peak
arrived.06175s after the dry onset (source20/324=.0617284s). Schroeder -5→-25dB decay
estimates were.92408s for source1.00625s and.72320s for source.1s; the tiny-room mismatch
is retained as an explicit Freeverb limitation. EFX-off and UI cases had zero late
energy. Twelve loud sources produced peak9.59978 with limiter disabled and.96610 with
it enabled; with Master gain4, captured pre-Master peak.24156 retained the same final
ceiling. Source gain8 and1 produced equal capped PCM, while s_gain.05 gave amplitude.4.
These are mixer/DSP measurements, not browser listening acceptance.

The final **WASAPI48kHz with headless display** run also passed **81 checks, 0 failures**,
with clean teardown and no GPU window. Ratios were.99982/.11738 at400Hz/10kHz, early
delay.06173s, room/tiny decay estimates.92294/.72356s, limited/unlimited peaks.96609/9.59978,
and Master4 pre-Master peak.24155. WAV headers for both drivers were independently
checked as stereo PCM16 at their reported mix rate; PCM overflow checks passed.

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/audio/test_environment.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/audio/render_environment.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --display-driver headless --audio-driver WASAPI --path game --script ../tests/audio/render_environment.gd
```

`tests/audio/export_web_probe.py --godot <engine>` exports the original-resource
post-DSP proof; add `--environment` for the DSP signal proof. Both probes begin from
a browser button gesture, expose copied results in DOM and write no preferences or
browser WAV files. Export success alone does not verify Web PCM or listening.

The updated source and environment probes exported successfully to
`.cache/audio-web-probe/build/index.html` and
`.cache/audio-environment-web-probe/build/index.html`; their expected browser check
counts are113 and64, since file/WAV checks are omitted. Their audio source/helper
copies match production SHA256. One first environment editor import crashed at
shutdown without a script error; import with three idle frames and the full subsequent
export completed cleanly. The helper now uses `--quit-after 3` for editor teardown.
Actual browser DOM PCM results and listening are separate acceptance evidence.
