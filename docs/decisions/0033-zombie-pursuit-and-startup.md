# ADR0033 Zombie pursuit and launch work

Accepted: 2026-10-12. This follow-up supersedes ADR0032's selection by full
detour/breach time, following the user's latest explicit request.

Each zombie randomly chooses detour or breach when it encounters a direct
obstacle. The approximately equal choice is seeded per reusable life and retained
while the obstacle remains, rather than rerolled each frame or selected by damage
cost. Both alternatives still require a validated bounded path; if only one is
available it is used. Remaining block health still controls real damage and the
reported time estimate. Protected ground is never a destruction candidate.

Pursuit skips a rear source-center waypoint when the next edge is safe, consumes
passed waypoints, and clamps steering/braking and crowd separation so they do not
produce reverse movement. Close pursuit follows the owner's current bite boundary
only after full body clearance, not torso visibility alone. Forward recovery
retains the original one-block automatic climb.

Elevated targets project to a reachable lower approach for planning and safe spawn
validation. When the owner is above the normal step height, the director may
propose an exposed, accessible forward block for breach. It cannot remove distant
support through walls or bite beyond the existing true 3D distance/visibility
check. Committed breaches use existing persistent health/collapse and may bring
the player down through ordinary authoritative motion. Stacked tunnels/bridges and
imported maps remain outside the Crossroads navigation acceptance.

Only actual movement or confirmed attack damage refreshes stall progress. A real
shared-cell strike also refreshes eligible queued attackers, whose cell cadence
prevents simultaneous damage; repeated invalid intentions or windups alone cannot
hide an unavailable route indefinitely.

Main disables VoxelWorld's default lab bootstrap before match children become
ready, avoiding a synchronous lab generation/mesh that was immediately discarded.
The standalone lab still bootstraps once. Match streaming and the first player
camera pose start at the authoritative spawn. Entry yields two presentation turns
so the shell's pending state can draw before synchronous scene loading. This does
not claim to eliminate cold script/resource/shader work or all launch latency.
Normal match launch also keeps the authority clock/input paused until the initial
budgeted chunk jobs publish and progressive minimap/water columns finish, with a
30-second finite error/retry deadline. It leaves
World's normal work budget intact and shows preparation rather than running the
first combat frames concurrently with initial terrain work.

Verification uses changed AI/session/startup fixtures and relevant lab/TDM/scene
regressions, parser/import, runtime smoke and ordinary local desktop Web export.
The user explicitly declines repeated deployed-browser and mobile UI inspection;
release checks use public asset hashes and Pages API status instead. Full-suite
checks remain the build default; an explicit repeatable --suite option records the
bounded follow-up gate without silently claiming that every fixture was rerun.

Exact commands, source revision and results belong in docs/zombie-survival.md and
docs/status.md. The original release evidence remains historical.
