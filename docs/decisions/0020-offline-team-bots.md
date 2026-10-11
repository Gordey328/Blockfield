# ADR0020 — Offline 3×3 team combat

Accepted: 2026-10-11. User requested one human and five active bots, with shooting,
cover and flanking in a playable offline match.

`OfflineTDMSession` adapts `MatchSimulation` to the existing `LocalSession`
presentation interface. The controller samples one human command per fixed 60 Hz
tick; `TdmBotDirector` supplies five commands at the same boundary. PlayerRules,
SourcePlayerMotion, shared firearms and grenades determine movement, ammunition,
hits, deaths and terrain edits for every actor. Presentation never applies damage
or commits an already committed map transaction a second time. No server, socket,
client prediction or wire-format extension is required.

Each completed authority step mirrors its result once. Camera and weapon poses,
and the five actor views, update once per rendered frame; low render rates must
not repeat pose work for every fixed physics tick. The mobile score line sits
below the actual toolbar bounds, including a toolbar that wraps to two rows.

The separate offline scene contains one blue human plus two blue bots and three
green bots. The authored 80×24×56 Crossroads map has three approaches, tall cover,
flank routes and distinct spawn positions. First to 25 enemy kills wins; after five
minutes the higher score wins, with equal scores ending in a draw. Friendly damage
is disabled. Shared respawn rules apply. Menus and loss of focus stop the authority
clock. A new match restores the arena, rotates the map epoch and resets actors,
bot memory, score and visual effects. The original test lab remains accessible.

Finite ammunition remains authoritative. Each team can recover health and reserve
supplies within 2.5 map units of its own spawn positions, at most once per second.
Restocking preserves the current magazine. Bots with exhausted reserve ammunition
return to those positions instead of receiving an invisible inventory refill.

The original bot implementation uses role-dependent goals, 7.5 Hz staggered
decisions, line-of-sight/FOV observations, bounded last-seen memory and imprecise
gunshot hints. Reaction delay, limited turning and aim error constrain shooting.
Cover selection tests occlusion and bots use authored flank routes; reload and
injury can interrupt an attack. Lazy voxel-column A* navigation rechecks paths
after journal edits, with local obstacle recovery and digging commands. Bots do
not teleport or call a separate damage implementation.

ABBS and other sources in [the research](../game-modes-and-bots.md) informed the
design; their implementation is not copied. Initial navigation and tactical hints
are scoped to this authored arena. Arbitrary imported maps, difficulty presets,
coordinated construction and other game modes need separate acceptance. This is
an additional gameplay feature and does not establish full OpenSpades parity.

Behavior and actual-scene fixtures are registered in `tools/build.py`. Browser
acceptance must exercise the real exported scene and its normal input; the separate
probe export provides diagnostic counters without changing the Pages entry point.
