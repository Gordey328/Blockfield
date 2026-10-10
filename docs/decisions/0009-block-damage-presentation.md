# ADR0009 — transient block damage presentation

Accepted 2026-10-10 for the authorized W07 fidelity repair.

OpenSpades v0.1.3 `GLMapChunk.cpp:247-252` halves terrain RGB channels, rounding
down, whenever the packed block health is below100. `World.cpp:102-115,190-195`
restores health ten seconds after the latest hit. RGB, occupancy and map edits
remain separate from that transient state in Blockfield's shared VoxelData.

VoxelWorld owns a sparse cosmetic mask exposed through `set_block_damaged`,
`is_block_damaged`, `clear_block_damage` and `get_render_color`. Chunk vertex
colors apply `(RGB & 0xfefefe) >> 1` before the existing AO alpha. Updating this
mask dirties only the containing mesh; collision, journal, VXL, minimap and
authoritative map hashes remain unchanged. Actual edits clear affected masks;
map adoption/reset clears all masks. World owns no damage timer.

The offline controller supplies surviving-hit and latest-hit recovery transitions
from its existing health state. Network Main consumes confirmed `block_hit` and
non-dig `spade_block_hit` events, ignoring predicted hits, air and bedrock. Its
sparse timer expires on the confirmed authority tick, using the existing server
rule `tick > last_hit + 600`. Repeated hits extend expiry, without repeated mesh
work while the mask is already set.

Ordered map deltas arrive before queued effects. Main records the tick of changes
that leave a solid cell and rejects hits no newer than that edit, preventing late
effects from darkening a replacement. A same-tick edit/hit has no incarnation
identity in the existing wire schema, so the edit wins for presentation. Entries
expire after the same600-tick window; removals discard them immediately.

Fresh map baselines start with undamaged presentation, as original map loading
initializes block health to100. Baseline, epoch reset and disconnect clear all
transient marks. This change adds no protocol fields or server authority; the
published network-4 server remains compatible. These presentation decisions do
not alter hit validation, damage, destruction or map synchronization.
