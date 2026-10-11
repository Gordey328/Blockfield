# Grenade distance feedback

2026-10-11. Engine Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility;
upstream `dcf449c845d509bbde9d79239b32d201c1389961`.

The user requested quieter, weaker distant explosions. Two read-only specialists
audited camera and audio; neither edited files or ran the engine. Root owns
`game/presentation/grenade_feedback.gd`, Effects/Audio, their fixtures, this evidence,
ADR0019 and integration. Mobile Fire/look, optimization advisory and Steam AoS
research remain separately owned. Root runs serial engine validation; diagnostics
use isolated frozen copies and never replace another chat's import cache.

Native shake/audio saturation, selected range and collapse confounder are explained
in [ADR0019](decisions/0019-grenade-feedback-range.md). At32 units, deterministic
maximum grenade roll falls from17.65degrees to.967degrees, before elapsed decay.
Audio additionally attenuates every land/water layer and both room branches.

Validation and publication pending. Reproduction will include exact frozen revision,
commands, native checks, raw mixed-audio ratios and exported browser interaction.
