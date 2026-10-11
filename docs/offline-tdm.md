# Offline team combat 3×3

Implemented for the user's 2026-10-11 request. This is an additional playable mode,
not evidence that the full OpenSpades port is complete.

## Playing

Open the normal game menu and choose **Командный бой 3×3 · Вы и пять ботов**,
then **Начать матч 3×3**. The human and two blue bots fight three green bots on
Crossroads. The first team to 25 enemy kills wins; after five minutes, the higher
score wins. Equal scores end in a draw. Deaths use three-second respawn. Esc opens
the pause menu; a new match restores the arena. The menu offers a return to the lab.

WASD moves; left click fires; right click aims; R reloads; 1–4 select tools;
Tab opens the scoreboard. The existing touch controls remain available. Choose
rifle, SMG or shotgun before starting, or for the next life during a match.
Blue spawn pads restore health and reserve supplies nearby; magazines still need
normal reloads. Friendly fire is disabled. Terrain damage survives until restart.

Bots advance through voxel collision, choose occluded cover when reloading or hurt,
patrol sightlines, follow flank routes, search last-seen positions and return for
supplies. Their commands use the same rules as the human. Reaction delay, aim error,
turn speed and actual line of sight constrain their fire. There is no separate bot
damage or teleport movement. [ADR0020](decisions/0020-offline-team-bots.md) records
the authority, navigation and round contract; [research](game-modes-and-bots.md)
records external design sources. Bot code is original.

## Native evidence

Engine: `4.7.2.stable.official.ed1daf0bf`, Compatibility. OpenSpades reference:
`dcf449c845d509bbde9d79239b32d201c1389961`.

Import/parser passes. AI fixture passes 4440 assertions; session fixture passes
81 assertions. The final actual-scene fixture passes 62 assertions after patrol
tuning and the spawn correction (`.cache/logs/tdm-final-scene.log`): all five bots
move, attempt fire and follow their shared positions, with 10 cover decisions,
10 flank decisions and a natural score of 3:4 after 1222 ticks. The frozen
`3d1199cb0251f1cfe9c13cbd66a553264a34c1e5` build passed all 92 registered
fixtures, parser/import, runtime smoke, server-launcher smoke and Web export.
Three explicit headless GPU skips remain in the existing MultiMesh checks.
Logs are in `.cache/release-3d1199cb0251/.cache/logs/`.

A 3600-tick shared-session diagnostic run with a stationary human confirmed shots
from every bot: IDs2–6 accepted 31/14/18/31/13 shots and 20/40/17/21/30 hits.
Final score was 12:15, with 25 cover decisions and 25 flank decisions. Every bot
moved and attempted fire within the first 20 seconds. The diagnostic was run before
the final spawn-boundary epsilon correction. Native mean/max authority step was
1.415/42.787 ms in that single run; this is not a Web/rendering benchmark.
Comparison and raw logs: `.cache/tdm-ai-profile-comparison.json`,
`.cache/logs/tdm-ai-final.log`, `.cache/logs/tdm-ai-profile-after.log`.

Failed attempts are retained: actual-scene WeakRef inference was corrected in the
fixture (`tdm-scene-first.log`); session alternate-spawn assertion exposed a real
source-motion floor-boundary climb (`tdm-final-session.log`,
`tdm-session-spawn-diagnostic.log`). Initial and respawn coordinates now use a
0.01-unit surface epsilon while preserving support and actor-overlap validation;
the same 81 assertions pass (`tdm-session-spawn-fixed.log`).

The first frozen full build (`f888fe92a68e7d14308381ae74b443513ba4e678`)
passed the earlier suites, then exposed a stale pre-existing SilentAudio fixture
override after ADR0019 added the optional blast-falloff argument. The override in
`tests/audio/test_audio_optimization.gd` now matches the production signature;
application audio behavior is unchanged. The failed archive/log is preserved.

The `52bbc1d7ac8f` full-build attempt stopped on a pre-existing HDR settings
assertion: a command already equal to a persisted setting reported no change.
Frozen checkpoints now give fixtures their own per-revision user directory and
restore the byte-exact archived project configuration before export. The failed
log remains in that archive; production user-directory settings are unchanged.

Reproduce with bundled Python `tools/build.py --export`; it registers AI,
session and actual-scene fixtures and the existing regression suite. The scene
fixture runs at `--fixed-fps 60` and verifies normal controller input, accepted
shots, movement of all five bots, cover/flanks, deaths, score, pause, respawn,
kill/time completion, fresh epoch/map restart and the unchanged lab entry.

## Browser and publication evidence

The initial interactive Web round reached 13:25, displayed the result and returned
to the lab. It exposed a mobile score/toolbar overlap, now corrected using the
actual toolbar bounds. Redundant offline state mirroring and per-physics-tick
weapon poses were also removed; the updated scene fixture passes the same 62
assertions (`tdm-render-scene.log`). Final frozen export and browser checks are
pending. The separate
`tools/export_offline_tdm_probe.py --release .cache/release-<commit>` exports the
actual scene with diagnostic controls and `window.offlineTDMProbe`; it does not
modify the production Pages entry point.

## Current limits

The first mode uses one prepared arena and one bot tuning preset. Navigation uses
one walkable surface per voxel column and authored tactical hints. Stacked tunnel
maps, general imported-map bots, strategic construction and coordinated squads
need later work. If all three team spawn positions are occupied or unsupported,
respawn waits for a clear supported position or a match restart.
