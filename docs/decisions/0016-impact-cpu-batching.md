# 0016 — Retain local work buffers across bounded impact slices

Date: 2026-10-11. Status: accepted; integrated verification in
[Title impact evidence](../title-impact-performance.md).

ADR0015 split chunk builds into bounded halo columns, mesh columns and collision
planes. Re-entering GDScript and transferring ten packed output fields for every
column introduced enough overhead to exceed the original monolithic aggregate
CPU cost, despite reducing the blocking slice. Title shooting also repeatedly
evaluated identity damping and fade calculations for batched white fragments.

A chunk callback now advances several original logical units while retaining
sole ownership of mutable output buffers in local variables. Every column/plane
still checks the same absolute deadline and remaining unit cap. Buffers return
to the private job before yielding; no live full-map packed reference survives
the callback. The existing current-job cancellation and complete mesh/shape
publication contract remains. Synchronous flush uses the same path. Stage CPU
and unit counters are opt-in and include work subsequently cancelled.

Effects skip exact identity damping, zero growth and unused animation frame
arithmetic. White-fragment fade is calculated at the final publication boundary;
animated sprites retain substep writes. Concrete VoxelWorld particle collision
queries use its typed Data contract within one substep. Subclass/custom world
overrides retain the dynamic adapter. Counts, lifetime, integration order, bounce,
smoke/water sprites and external node transforms are preserved.

HUD gathers full world/render diagnostics only while the statistics or lab label
is visible. Opening a panel gathers fresh data in that same callback. Gameplay
state and continuously visible HUD elements keep their existing update cadence.

Wet audio copies skip exact-equal pitch and global-transform writes, retaining
every actual change. Pinned Godot's [pitch setter](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/audio/audio_stream_player_internal.cpp#L292-L299)
visits active playbacks without an equality guard; AudioServer performs a
[linear lookup](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_server.cpp#L658-L665)
for each. Volume/gain, bus routes, ray work, sound layers and voice budgets retain
their existing behavior.

The complete Main profile subsequently located the larger audio cost after
player creation, in repeated decoder startup. Upstream already predecodes Opus
into PCM16 (`ALDevice.cpp:59–75,96–143`): its conversion floors decoded48kHz
float samples multiplied by32768 before the int16 cast. A bounded whitelist of
49 frequent fire/impact/block/casing clips now uses that native sample format.
The derivative tool decodes the original pinned r33 Opus, with explicit libopus,
and applies the source quantization without dithering, resampling, channel mixing,
normalization or trimming. Imported sample SHA256 must equal generated PCM SHA256.
It does not decode the previously transcoded Vorbis derivative.

The49 clips total7,442,462 PCM bytes, below8MiB. Extensions checks active uploaded
ZIP overrides first, preserves original canonical keys and converted aliases,
then strongly retains only the immutable whitelist. Missing/invalid derivatives
fall back to the legacy146-sound catalog. Clear releases the cache. Manifest size,
paths, format, channels/rate/frames and aggregate memory are bounded. Full hashes
are checked by the behavioral fixture rather than on every playback request.
Godot's WAV importer [defaults to QOA compression](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/import/resource_importer_wav.cpp#L71-L84),
so checked-in import settings explicitly disable compression and conversion.
The PCM path requires imported-byte checks and paired real-browser CPU evidence
before release; reducing sound layers/counts or quality is not part of this choice.

Acceptance requires both aggregate completed work and latency evidence. Native
fixed-cadence world tests and fixed60Hz Main throughput are separate from the
production4ms queue. Browser comparisons use a warmed original Title cliff with
positive removals, settled visual/minimap preparation, drained tail and reported
counts. A smaller individual call alone does not establish reduced overall CPU
or improved frame rate.
