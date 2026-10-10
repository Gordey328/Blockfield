# Native snapshot and event publication

Runtime publishes full owner replay snapshots at20Hz and ordered event batches
before the matching state. The initial implementation copied and encoded the
same public actors/grenades/objectives for every owner, discarded validation
bytes, then encoded again in Protocol and Transport. Source event bursts repeated
normalization and serialization for every recipient. Measured baseline costs
are in [server-capacity.md](server-capacity.md).

`SimulationCodec.prepare_shared(snapshot)` captures one closed tick. The
unchanged strict encoder validates all common records and relationships once.
An owned26-byte prefix and common tail are retained, alongside read-only public
pose records. `Protocol.prepare_state(shared,owner)` independently validates all
private owner fields, epoch/profile/tick and the exact captured public pose; it
assembles the same existing owner-specific body and envelope. New life, epoch,
tick or changed public pose cannot reuse the capture. Server RNG is never read.

`EventsCodec.prepare_shared(epoch,events)` accepts at most2048 source records,
normalizes/validates chunks of64 once, verifies sequence/ID uniqueness across
chunks, and retains only owned encoded records plus routing metadata.
`Protocol.prepare_events(shared,owner_id)` filters public and that owner's
private records, preserving the original ordered64-record batch boundaries.
Every resulting body/envelope uses the existing limits and exact byte layout.
Malformed authority output closes affected live streams for resynchronization;
the authority does not publish a partially validated event list.

`Protocol.FrozenFrame` is internal trusted output, never a remote input or a
Godot Variant wire object. Its byte getter returns an explicit owned duplicate.
Transport `send_prepared` queues those bytes under the same open-state,
128-frame/byte budgets and heartbeat ordering as ordinary packet output.
GDScript private field conventions do not provide a script security sandbox.
Network input still goes through the ordinary complete strict decoder. Since
both MATCH_STATE/GAME_EVENTS sub-codecs already perform full validation on
decode, Protocol checks their envelope/body identity without encoding the same
body for a second time. Other packet families retain their original validation.

No schema, counter, privacy, cadence, authority or TCP ordering change is made.
Only unsent snapshots remain replaceable; queued events remain ordered and
overflow closes the slow stream rather than discarding acknowledged history.
Custom trusted snapshot factories retain their existing Packet path.

## Verification

`tests/network/test_snapshot_fanout.gd`: **4065 assertions / 0 failures** on
pinned native Godot4.7.2. Both tuning profiles/all three modes, the32-actor
boundary, distinct private inventory, canonical owner identity, ordinary strict
decoding, captured public mutation, owned returned bytes, epoch/tick/life
changes, malformed private/public/objective state,160 mixed public/private
events,32 recipients, cross-batch duplicates/order and private hurt isolation.
Each prepared frame is compared byte-for-byte against the original independent
`from_snapshot/from_events → Protocol.encode` path.

Protocol1591/0, SimulationCodec2316/0, EventsCodec280/0, actual WebSocket602/0
and real event delivery108/0 pass after integration. Logs:
`.cache/logs/snapshot-fanout.log`, `.cache/logs/fanout-*.log` and
`.cache/logs/events-delivery-fanout.log`. Capacity comparison and full
Runtime/Main/browser release acceptance remain separate checks.
