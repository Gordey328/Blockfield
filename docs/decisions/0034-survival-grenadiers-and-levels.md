# ADR0034 Responsive survival launch, damage and grenadiers

Accepted user scope2026-10-12. The existing offline mode gains two damage controls,
a grenade-throwing type and small downloaded Teardown adaptations. Prior random
obstacle selection/elevated breach policy remains. No networking is restored.

Entry paints Home, warms a packed survival scene without instantiating a hidden
world, and loads one bounded model resource per frame. Native ResourceLoader uses
a threaded scene request; the single-threaded Web template retains its platform
loader behavior, not an invented Web worker. Loaded resources remain bounded and
transfer to Main before Entry leaves. Entry drains its outstanding request on exit
to avoid shutdown during shader parsing. Model warming uses process steps rather
than an orphaned coroutine. A pending launch waits with a finite error/retry result.

Normal survival Main paints the overlay early, suspends incomplete controller/HUD
callbacks, warms228smoke frames in count/time-limited slices and separates remaining
setup stages. The first selected weapon configures the initial registry once.
First-person equipment binds under the loading overlay. Disabled HDR does not
allocate its capture/exposure pyramid; enabling it later initializes the ordinary
pipeline. HDR initialization no longer rebuilds the identical first pyramid twice.
Initial terrain/minimap/water readiness still gates the live preparation clock.
Cold resource/render work is reduced and redistributed, not declared universally
zero or proven on a phone.

Canonical settings zombie_damage and zombie_block_damage are independent integers
1..100, defaults20/40, saved with the selected level and retained on restart.
Player damage is bite damage and grenade peak damage with ordinary distance falloff;
block damage applies per strike/per exposed blast cell with persistent health.

Every fourth actually admitted life is a grenadier. It uses the same reusable
slot budget and six-part/eight-node pooled rig, with orange/olive clothing,
backpack/hand-grenade geometry and an overhand warning. It has3throws per life,
60tick windup,480tick cooldown, range6..24 and at most4hostile projectiles.
The director proposes an intention; the authority rechecks current life, owner,
distance/metric visibility/cooldown/cap and commits a real ordinary bouncing
grenade with2.5second fuse. Cooldown/empty stock retain ordinary chase/melee/breach.
Source grenade buttons remain forbidden for zombie command inputs.

Trusted MatchSimulation keeps isolated zombie loadout/explosion profiles, leaving
human grenade rules unchanged. A zombie explosion damages the owner within8 with
falloff and at most96nearby exposed cells within3 using configured persistent
block damage; removals/collapse commit in one batch. Protected y0/y1 remain.
Cleanup waits for all real projectiles, including a late explosion after the last
zombie dies; owner death retains priority over victory. Pause and restart own the
whole timeline.

SurvivalLevels loads only trusted catalog BFM identities and validates actual
owner/supply/sectors, body support and the8192column navigation bound. Two actual
downloaded maps are cropped/quantized to one authored walking floor; original Lua,
missions and physics are not executed or ported. The static source geometry is
retained where compatible, with explicitly added foundation/apron and removed
roofs/subsurface spaces. Original author/source/reuse status and source hashes are
preserved, without relabeling assets as repository MIT. See survival-maps.md.

Verification uses changed gameplay/AI/view/scene checks, relevant lab/TDM/weapon/
HDR/effects regressions, parser/import and ordinary local desktop Web acceptance.
User declines deployed-browser and mobile-UI retests; publication uses file hashes
and Pages API. Exact revision/results and remaining limits belong in
survival-expansion.md and status.md. No whole-port acceptance follows.
