# Camera shake and sustained-fire effects

Date: 2026-10-11. Engine: Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility.
Reference: OpenSpades v0.1.3 `dcf449c845d509bbde9d79239b32d201c1389961`.

## Confirmed defects

`Sources/Client/Client_LocalEnts.cpp:340-349,464-468` rejects grenade explosions
beyond170 units before calling KickCamera. The port previously kicked first and
culled only particles. The corrected manager rejects both land/water blasts first.
Distance is measured from the current camera, including spectator views.

Native land strength is `2/(distance+5)`, water `1.5/(distance+5)`. Fast vibration
scales by10, slow accumulates at5 times strength then scales by4 and squares.
Thus land's initial fast peak saturates through15 units, slow through35; water
through10/25. Duration still decreases with distance. Those source curves remain.

The port used a0.1s-capped delta for both collision integration and effect age.
Long frames prolonged vibration, smoke, fragments, lights and casings and increased
the number of live effects. The manager now consumes actual elapsed time for age,
animation, fade, damping/growth, tracer travel and vibration. Particle/casing movement
and collision retain at most six60Hz substeps over0.1s, so a hitch cannot trigger
unbounded catch-up work. This bounded trajectory adapter is not exact long-frame
native movement; elapsed lifetime is independent of it.

## Reuse and rendering

See [ADR0011](decisions/0011-effect-pools-and-fragment-batching.md).
`OpenSpadesEffects.setup` prewarms configured Sprite3D, Rifle/SMG casing model,
tracer and flash pools and complete180/48-frame smoke caches. Normal defaults are
512 live particles,48 live casings,64 tracers and8 lights. Separate idle shell pools
retain at most48 models per weapon. Node allocation counters are cumulative, while
`stats` reports live and idle counts. Emission retains original source counts.
Clear hides/resets and returns live nodes; resource reload detaches stale nodes,
clears caches and prewarms fresh resources. Managers may be set up before entering
the tree, as actual Main does.

Default White.png fragment/blood sprites share one fixed-capacity MultiMesh draw.
Their pooled Sprite nodes hold simulation transforms but stay hidden. After bounded
substeps, the batch copies camera-facing global poses, inherited scale, spin, color
and fade alpha into contiguous visible instances. Smoke/water remain individual
pooled animated sprites. Transparency sorts as one fragment draw rather than each
fragment independently; overlapping translucent fragments may composite differently.
The manager continues voxel collision queries and per-particle simulation; this
does not remove every CPU/render bottleneck.

## Validation and reproduction

Coordinator-only engine work uses isolated `.cache/effects-probe-*` projects so the
other active persistent-block-damage release retains its own import/release lease.
Specialist `effects_pool` edited only the manager and `test_effects.gd`; two other
specialists completed read-only camera and shot-hotspot audits. Files were returned
to the coordinator before matching-source validation.

Build an actual-Main test-only Web scene with:

```
python tools/export_effects_probe.py --source .cache/release-dcee15f0b7bc --effects .cache/release-dcee15f0b7bc/game/presentation/openspades_effects.gd --name baseline
python tools/export_effects_probe.py --source .cache/release-dcee15f0b7bc --effects game/presentation/openspades_effects.gd --name batched --import-cache .cache/effects-probe-baseline/game/.godot
python -m http.server 8077 --bind 127.0.0.1 --directory .cache/effects-probe-baseline/build/web
```

Use a distinct port for the patched export. Click `SMG into wall: 12 seconds`;
the fixture drives actual offline primary-fire input, source SMG/unlimited ammo,
terrain edits and audio, compensating aim recoil to keep hits on the thick wall.
It exposes a visible JSON report and console `EFFECTS_RENDERED_STRESS` record.
Grenade buttons expose5/80/180-unit accumulators and actual camera presentation.
This fixture has a separate user directory and never replaces the production entry.

Baseline actual WebKitWebGL run reached512 particles and571 draw calls. It reported
111 frames/12.0549 game seconds,9.2079FPS,118.3ms median,144.967ms p95. Concurrent
engine activity and an externally changed browser viewport make that FPS result
diagnostic, not a controlled performance comparison. Screenshot/log:
`.cache/previews/effects/baseline.{jpg,json}`. Patched actual-Main WebGL sustained
fire reached87 draw calls while admitting512 particles; final report is pending.

Matching manager SHA256 `099e258c612ce53c0f88b6ab1b9323ca99c54e92ad85abf0bc3fd34d0173e710`
passed parser/import/Web export; headless effects32588/0 (three explicit GPU
readback skips), native Intel UHD Compatibility effects32591/0 and source camera45/0.
The effects fixture drives180 source-cadence SMG shots and700 saturated emissions,
checking no node creation after warmup, source emission counts, active/idle caps,
170-unit culling, real-time hitch lifecycle, clear/model reuse/resource reload and
batch transforms/colors. Native visual previews preserve visible colored blood,
fragments, smoke, muzzle and water at `.cache/previews/effects/batched-gpu/`.
Logs are under `.cache/effects-probe-batched/.cache/logs/`.

An early pool-only archive captured the manager before automatic reload prewarm
while its fixture was newer, causing3 reset/reload assertions. Preserve
`.cache/effects-probe-pooled/.cache/logs/effects-pool.log`; it is stale-snapshot
evidence and does not verify the final matching files. The first matching headless
run32591/6 exposed fixture issues: queued audio children were included in live-pool
inventories, and dummy-renderer MultiMesh readbacks returned defaults. Inventories
now ignore already queued nodes; the three readback checks run with a GPU and are
explicitly skipped headlessly. Production effect code was unchanged for these
fixture corrections. Both corrected runs above passed.

Other read-only suspects remain: weapon ambience casts24..48 acoustic rays per
shot; dry/wet audio players still allocate; terrain destruction remeshes chunks.
These were not changed without measured isolation. Browser/device sustained
original-map performance remains unaccepted; U12 remains IMPLEMENTED.
