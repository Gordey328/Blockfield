# ADR0010 — persistent block damage

Accepted 2026-10-11: the user explicitly requested removal of automatic block
regeneration. This supersedes ADR0009's ten-second recovery rule and deliberately
differs from OpenSpades v0.1.3 `World.cpp:102-115,190-195`.

A surviving damaged block retains its remaining HP and source-style darkening
until destruction, an actual edit/replacement, or explicit map/round reset. Waiting,
respawn or reconnect cannot heal the existing block. Writing the same intrinsic
RGB is a no-op and cannot heal it. Deletion followed by placement, including the
same RGB, creates a healthy new block. Destroyed air stays air. VXL save/reload is
an explicit map reset: VXL does not retain this match's damage table.

Offline Controller and shared MatchSimulation remove automatic expiry, timestamps
used only as deadlines and per-frame/per-tick expiry sweeps. Canonical RGB/solid,
collision, AO, minimap and terrain edit history stay independent of HP and tint.
Real edit transactions and map/epoch reset retain their existing cleanup. Sparse
HP/mask records persist with damaged cells; do not evict them to heal for memory.
Runtime wire snapshots request `snapshot_for(id,false)` so the growing HP table
is not deep-copied at20Hz. Snapshot consumers requiring HP retain the default copy.

Joining/resumed clients receive permanent damage in the existing four-byte bulk
baseline cells: bit `0x02000000` marks damaged canonical solid cells above bedrock.
The encoded baseline hash authenticates the flags. Bounded decoding splits flags
from canonical0x01RRGGBB; the verified END hash remains canonical terrain. Flags
consume no extra map bytes and are frozen with the map at an actual authority tick.
Runtime still advances `data.last_tick` each step for HitHistory's closed-frame
identity and query lease. Frozen sender tick overrides do not mutate live data;
removing the runtime clock would invalidate lag-compensated shooting.
Catch-up terrain edits clear affected masks. Damage acquired while loading is
queued under the existing bounded event budget and delivered before the first
live state. Replica emits these surviving hits as tint-only catch-up, filtering
baseline and same-tick/replacement edits; Main does not replay sound/particles.

Main retains solid-cell edit tick guards until deletion/new baseline rather than
expiring them with the removed damage timer. Baseline adoption/disconnect clear
old presentation; the replacement baseline restores current authority damage.

Compatibility changes to `blockfield-godot-4.7.2-network-5` and
`blockfield-source-v0.1.3-authority-5-no-block-regen`. Packet envelope/body schemas
are unchanged, but baseline flag semantics and gameplay require matching new
client/server artifacts. Old recovering servers are rejected by the handshake.
No hosted service/domain is created by this change.
