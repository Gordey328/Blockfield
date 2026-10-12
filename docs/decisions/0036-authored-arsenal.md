# 0036 Authored arsenal and bounded local ordnance

Date: 2026-10-13 (Europe/Moscow). Status: accepted implementation; verification and
release are in progress. User request starts on 2026-10-12.

The user requests twenty imaginative additional weapons, bombs and stratagems.
Finished Rush branch3a39e6445e942855ac202714bbdc8a42cddd3921 is the base; it is
fast-forwarded into dev before this implementation. Original OpenSpades weapon
IDs0–2 and tool IDs0–3 retain their own rules, resources and golden checks.

ArsenalCatalog defines stable authored string IDs x01–x20. ArsenalRuntime owns
finite inventory, charging, cooldowns, swept ordnance, elemental states, impulses,
deployables and delayed support on the host's fixed60Hz boundary. ArsenalBridge
adapts the real local lab or shared offline match to existing damage/kill credit,
native motion and canonical VoxelData. Active elemental status and lab impulse
state each cap at 32 entries; expired/dead/recycled identities retire. Overflow
refuses a new effect state while ordinary damage remains valid. Active freeze
immunity is not evicted, and heavy shatter checks the target life identity. It does not simulate presentation nodes.
Survival advances it immediately after shared motion/shooting and before the
normal outcome/card checks. Pause, upgrade choice and world-loading readiness
stop every new clock. The playable preparation countdown continues normally.

ArsenalTerrain introduces an additional cooperative edit/collapse path. Original
VoxelData.remove_blocks remains unchanged. New direct cuts and connected-component
work have per-step limits, ordered already-committed receipts and epoch/generation
cancellation. Concurrent support and replacements invalidate relevant candidates;
foam ownership cannot be inferred from color alone. Cut coordinates also need
mutation guards during queued/deferred work. A small blast radius is not treated
as a bound on connected-component size. Damage visibility is evaluated before
terrain edits; world presentation adopts each receipt once.

Home supplies one primary, one bomb and two support slots. Survival/Rush equipment
is fixed for the attempt; changing the saved setup during a run affects the next
attempt, including one-click replay. Selecting the source backup during a run
does not overwrite the pending saved kit. Lab selection retains stock when switching. Death does not restore the
map; lab respawn reuses its terrain helper and resets per-life ordnance/inventory.
Only restart/reset/new-map disposal releases its mutation observers and ownership.

Arsenal runs use a separate versioned Rush record section, keyed by canonical full
loadout, source backup class and map. Existing source record writes preserve valid arsenal buckets and
arsenal writes preserve original buckets. Field-kit upgrades refill primary reserve
only; they do not refill single-use bombs or support charges.

ArsenalView consumes committed events/snapshots using bounded authored geometry;
critical warnings take priority. ArsenalPanel emits validated equipment/application
intents and owns its pointer claims. Coordinator connects the existing controls,
modal pause/capture, HUD, loading and restart; extra touch regions cannot become
movement/look/fire input. Procedural authored sound resources use a bounded voice
pool. The existing total50 decorative-particle cap is unchanged.

Acceptance requires all twenty distinct real mechanisms, lifecycle/saturation and
source regressions, actual desktop/touch Web interaction and verified publication.
Native timing and desktop viewport dimensions do not establish phone performance.
This addition does not accept the full OpenSpades port.
