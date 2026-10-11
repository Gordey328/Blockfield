# 0019 — Shorter grenade and collapse feedback range

Date: 2026-10-11. User reports almost unchanged camera shake and sound after a
distant throw and asks to reduce the effective size or repair the cause.

The world scale and listener position are correct. Native land camera slow shake
saturates through35 voxel units; native sound gain/reference pairs30/5 and6/40
remain at OpenAL MAX_GAIN1 through150/240 units. Those source parameters obscure
the distance of a normal32-unit throw. This is an intentional presentation change
requested by the user, rather than a source-parity bug repair.

`GrenadeFeedback.distance_gain(d) = 1 / (1 + (d/12)^2)` supplies a continuous
distance envelope. Point-blank gain stays1,12 units gives.5,32 gives.123288,
80 gives.022005. One voxel remains one world unit. Original grenade trajectories,
damage, craters, particle/light sizes and170-unit particle cutoff remain intact.

Effects multiply the native grenade kick by this envelope before accumulating
fast/slow intensities. Collapse slow-kick contributions are capped at the existing
maximum1 before the envelope, so a large grenade-triggered breakup cannot undo
the distance response. Aggregate intensity caps, source camera noise and elapsed
decay stay unchanged. Ordinary firing/movement camera effects are unaffected.

Audio retains all five land/three water source clips and layer metadata. Explosion
voices opt into the envelope before their initial playback; every gain update
applies it after native caps to dry and early/late room voices. Listener movement,
stereo and disabled panning follow the same range. Other spatial/local audio keeps
its previous attenuation. Debris still uses its actual downward-ground origin.

Verification: `test_effects.gd` checks distance/large-collapse response and actual
SourceCameraEffects output; `test_audio.gd` checks all layer routes, wet copies,
listener movement and ordinary-audio control; `render_grenade_feedback.gd` captures
fixed-variant production mixes after the limiter at5/32/80 units. Evidence and
browser/release identity are recorded in docs/grenade-feedback.md. U11/U12 remain
IMPLEMENTED; this adjustment does not establish complete port/listening acceptance.
