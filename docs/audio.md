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
  offset without falloff. Mono and stereo world gain share
  `volume / max(distance / referenceDistance, 1)`, without an extra 150m linear fade.
- At most 128 voices live at once. Teardown stops streams and releases nodes. Audio
  playback references need a mixing cycle to drain before a test process exits.

Main persists `audio.positional`, `audio.environmental` and master volume while keeping
other settings sections. Turning panning off retains distance gain.

## Verification and remaining work

`tests/audio/test_audio.gd`: **126 checks, 0 failures**, `.cache/logs/test-audio.log`.
Independent fixtures cover source paths/gains/reference distances, every gun layer,
land/water explosions, open/enclosed room goldens, near/distant attenuation and real
mono/stereo Godot voice routing. This is a parameter/routing test, not a listening test.
Full-scene source acceptance was146/0 and integration95/0 at the movement checkpoint; the next combined checkpoint adds tool-use gating and selection regressions.
The dry-fire integration case retains reserve ammo: complete depletion must instead
activate automatic tool selection.

Godot panning and the browser backend replace OpenAL. Native EAX obstruction, low-pass
and reverb sends, HRTF selection and Mumble positional integration are not implemented.
The main scene routes casing contacts through the same service with native .6 reference
distance and water pitch variation. Bullet impacts play the original2-gain Block plus
Ricochet layers or one2-gain Water layer, shifted along the surface normal.
Standalone effect tests retain their isolated fallback player. Browser audibility, balance and gesture
activation need listening acceptance; headless tests do not verify them. U11 remains
incomplete until those requirements are accounted for.

## Post-mixer PCM proof

`tests/audio/render_audio.gd` creates an isolated camera/audio service and a separate
muted bus with [AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html).
It records real mixed samples, rather than rechecking the126 routing fixtures.
Service-created voices are reassigned to the probe bus and restarted before recording;
Master is muted during this process and restored at teardown. The main scene is never
loaded, preferences are never written, and no audio-device settings are changed.

On Godot4.7.2 `ed1daf0bf`, both **WASAPI48kHz + Intel UHD Compatibility** and
**Dummy44.1kHz headless** passed **126 checks, 0 failures**, with clean teardown.
Coverage includes original rifle/SMG/shotgun first-person/world mixes in open air,
head feedback, chat, menu hover/select and alert. Checks measure finite/nonzero PCM,
both channels, buffer overflow, original stereo differences and mirrored mono spatial
panning. Silence before playback and disabling capture are negative controls.
Integrated signal energy gives amplitude ratios `.20000002` for head feedback gain.2
and `.25485709` for a2m→8m mono source with2m reference distance on WASAPI;
the fixtures allow6% for mixer scheduling/smoothing. Headless ratios were `.19996826`
and `.24996635`. These are independent amplitude measurements, not volume metadata.

Each driver writes19 stereo PCM16 WAV files plus `report.json` under
`.cache/previews/audio-pcm/{wasapi,dummy}/`. WAV headers/frame sizes were additionally
checked with Python's `wave` reader. Metrics are unscaled floats; review WAVs use the
reported per-file `wav_scale` to avoid clipping. The gun bus reached raw peaks above1
(maximum11.47564 on WASAPI), before Master gain/output conversion. This evidence does
not establish final output balance or clipping behavior. The process is silent;
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
