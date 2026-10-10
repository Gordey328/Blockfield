# Blockfield binary protocol v1

Implementation: `game/network/protocol.gd`, `class_name BlockfieldProtocol`. This is a transport-independent **codec**, not a connection, server, join implementation or implemented multiplayer. It is unused by the offline main scene. The design context is `multiplayer-plan.md`; this document describes actual implemented bytes.

## API and ownership

```gdscript
var packet := BlockfieldProtocol.make_packet(kind, payload, epoch, tick, sequence)
var encoded := BlockfieldProtocol.encode(packet) # Result
if encoded.ok:
    var decoded := BlockfieldProtocol.decode(encoded.bytes)
    # decoded.packet is a typed Packet containing the validated fields.
```

`Packet` holds typed `kind/epoch/tick/sequence: int` and `payload: Dictionary`. `Result` holds `ok: bool`, `error: String`, `packet: Packet`, `bytes: PackedByteArray`. Failures expose no packet and no encoded bytes; error strings contain no text/token contents. Decode does not retain a second copy of the original frame in `Result.bytes`. `make_packet` retains the supplied dictionary; callers must not mutate it concurrently with encoding.

Payload dictionaries use the exact fields below; unknown/missing fields and wrong types are rejected. Dictionary keys may be `String` or `StringName`; no key is serialized. Known vectors, scalars and byte arrays have explicit layouts. No `var_to_bytes`, `bytes_to_var`, arbitrary objects, callbacks or runtime evaluation are used.

## Envelope, types and bounds

Every message is one complete binary frame. Integers are unsigned **big-endian**. Float32 is IEEE754 binary32, also big-endian; finite values and post-rounding bounds are checked. It is not a native Godot Variant encoding.

| Byte offset | Type | Value |
| --- | --- | --- |
| 0 | u32 | Magic `0x42464E57`, bytes `42 46 4E 57` = `BFNW` |
| 4 | u16 | Protocol version `1` |
| 6 | u8 | Kind `1..13` from the table below |
| 7 | u8 | Reserved, must equal `0` |
| 8 | u32 | Payload length, exactly `frame_size - 24` |
| 12 | u32 | Match epoch |
| 16 | u32 | Simulation tick |
| 20 | u32 | Message sequence |
| 24 | bytes | Typed payload |

Header epoch/tick/sequence range is `0..0xFFFFFFFF`. Zero is allowed for negotiation/loading; the session layer enforces expected epoch, time windows and monotonicity. There is no implicit wrap policy: reset/rebase before exceeding a counter's wire range. Extra/trailing bytes, concatenated frames, unknown version/kind or nonzero reserved bits are errors. Duplicate envelope fields cannot exist in this fixed layout.

| Limit | Actual value |
| --- | --- |
| Ordinary total frame | 32,768 bytes including header |
| `MAP_CHUNK` total frame | 16,384 bytes including header |
| Map chunk data | 16,346 bytes, after 24-byte header and 14-byte chunk prefix |
| Compressed/uncompressed map | Each at most 67,108,864 bytes (64 MiB) |
| Dimensions `(x,y,z)` | `1..512`, `1..64`, `1..512`; Godot Y-up, not native VXL axis order |
| Inputs per batch | `1..8` |
| Actors per snapshot | `0..32` |
| Changes per delta fragment | `1..2048` |
| Delta fragments/transaction | `1..8192`; total changes no more than map cell count |
| Name | `1..64` UTF-8 bytes; bulk HELLO permits an empty name |
| Rejection message / chat | `1..256` / `1..512` UTF-8 bytes |
| Hash / present token | Exactly 32 opaque bytes |

`text(N)` means a u16 byte length followed by that many UTF-8 bytes, with the indicated byte cap. Validate bytes before string conversion: reject truncated/invalid sequences, overlong encodings, surrogates, code points above U+10FFFF, C0 controls, DEL and C1 controls. Ordinary Unicode, including Cyrillic/CJK/emoji, is retained exactly. This does not perform name normalization or moderation. `token` means a u8 length `0` or `32`, followed by those bytes; WELCOME uses fixed 32-byte tokens without length prefixes. Tokens are opaque and must not be exposed in URLs/logs by a future transport.

The decoder checks the envelope and count/available-byte limits before allocating counted records. Transfer metadata is checked before copying chunk data; delta dimensions/fragment counts are checked before allocating its changes. It never allocates/decompresses a map using a descriptor's claimed size. These limits also apply to local encoding; string character count is checked before UTF-8 conversion and byte count afterward.

## Actual payload layouts

Fields in each row occur in the listed order. Sizes exclude the common 24-byte envelope.

| Kind | Name | Payload layout |
| --- | --- | --- |
| 1 | HELLO | `role:u8, name:text(64), build_hash:32 bytes, rules_hash:32 bytes, resume_token:token, bulk_token:token` |
| 2 | WELCOME | `actor_id:u32, spawn_generation:u32, server_hz:u16, snapshot_hz:u16, profile:u8, resume_token:32 bytes, bulk_token:32 bytes, build_hash:32 bytes, rules_hash:32 bytes` |
| 3 | REJECT | `code:u16, message:text(256)` |
| 4 | INPUT_BATCH | `count:u8, records:count × 28 bytes` |
| 5 | CHAT | `channel:u8, sender_id:u32, message_id:u32, text:text(512)` |
| 6 | PING | `nonce:u32, client_time_ms:u32` |
| 7 | PONG | `nonce:u32, client_time_ms:u32, server_time_ms:u32` |
| 8 | MAP_BEGIN | `snapshot_id:u32, dimensions:3×u16, compression:u8, compressed_size:u32, uncompressed_size:u32, chunk_count:u32, map_sequence:u32, hash:32 bytes` |
| 9 | MAP_CHUNK | `snapshot_id:u32, index:u32, total_size:u32, data_length:u16, data:data_length bytes` |
| 10 | MAP_END | `snapshot_id:u32, map_sequence:u32, hash:32 bytes` |
| 11 | MAP_DELTA | Fragment prefix and changes described below |
| 12 | MAP_READY | Same layout as MAP_END |
| 13 | SNAPSHOT | Fixed owner prefix, actor count, actor records described below |

HELLO roles: `0` player, `1` spectator, `2` bulk map connection. Role2 requires a 32-byte bulk token; roles0/1 require it empty. Optional resume token has zero or 32 bytes. Role/player names need not contain Latin characters. WELCOME actor ID is a stable positive ID, **not** a network peer ID; spawn generation permits zero during initial loading. Server rate is `1..240`, snapshot rate `1..server_hz`, profile `0` = 0.75, `1` = 0.76. REJECT code is `1..65535`; application-specific codes are not yet assigned.

CHAT channel is `0` global or `1` team. A client request uses sender0; confirmed messages may have a positive sender ID. The codec accepts both directions and does **not** authenticate this field; the server must reject/overwrite forged sender IDs and assign message IDs. PING/PONG millisecond counters are u32 and can wrap; a future clock service computes wrap-safe differences and bounded clock estimates. Their payload is 8/12 bytes.

### INPUT_BATCH: commands only

The payload dictionary is `{records: Array[Dictionary]}`. Each record has exactly:

| Offset in record | Field | Type / validation |
| --- | --- | --- |
| 0 | input_sequence | u32, positive |
| 4 | input_tick | u32 |
| 8 | buttons | u16, only mask `0x007F` |
| 10 | tool | u8, `0` spade / `1` block / `2` weapon / `3` grenade / `255` no selection intent |
| 11 | weapon | u8, `0` rifle / `1` SMG / `2` shotgun / `255` no selection intent |
| 12 | move_x | f32, `[-1,1]` |
| 16 | move_z | f32, `[-1,1]` |
| 20 | yaw | f32, `[-π,π]` including the rounded binary32 boundary |
| 24 | pitch | f32, `[-π/2,π/2]` including the rounded binary32 boundary |

Button bits0..6 are jump, crouch, sprint, sneak, primary, secondary, reload. Movement is in the player's horizontal basis: +X right and -Z forward. The rounded move vector must satisfy `x²+z² <= 1.000001`; the tolerance permits float32 normalization error, not faster diagonal input. Yaw/pitch use the port's Godot-radian convention. Each subsequent record must have input sequence and tick exactly one greater than the preceding record; a single batch cannot duplicate/reorder/gap/wrap them. Cross-batch sequencing and button-edge/action processing are the runtime's responsibility.

There is no client actor ID, position, velocity, hit victim, damage, ammo, capture, kill or client delta-time in this layout. Extra authoritative fields cause encoding failure. Passing the codec does not authorize weapon changes, firing, movement speed or timeline claims.

### Map transfer

The reserved decompressed baseline representation is canonical Godot-axis packed colors, four big-endian bytes per cell, in the existing voxel array's Y-fast order: `index = y + dimensions.y * (x + dimensions.x * z)`. `uncompressed_size` must equal `dimensions.x * dimensions.y * dimensions.z * 4`. No assembler or compression implementation exists here; chunk contents remain opaque to this codec. Compression enum `0` means raw and requires equal compressed/uncompressed lengths; `1` reserves Zstandard. The codec accepts the descriptor but never decompresses data or verifies the supplied hash.

`chunk_count = ceil(compressed_size / 16346)`, at most 4106. MAP_CHUNK repeats the compressed `total_size`, validates `index < chunk_count`, and requires data length exactly `min(16346, total_size - index*16346)`. Chunk offset is implicit `index * 16346`; there is no independent offset that can disagree. Full chunks make an exactly 16 KiB frame. MAP_END/READY carry positive snapshot ID, u32 map barrier sequence and 32-byte hash.

The future transfer manager must bind descriptors/chunks/end/ready to the same snapshot/session/epoch, verify order/duplicates/hash/compression size and apply complete deltas before activating the matching state barrier. The codec does not retain a transfer or assert that a chunk matches a prior MAP_BEGIN.

### MAP_DELTA: transaction fragments

Prefix order (32 bytes):

`map_sequence:u32, transaction_id:u32, actor_id:u32, action_id:u32, dimensions:3×u16, fragment_index:u16, fragment_count:u16, total_changes:u32, count:u16`.

Map sequence and transaction ID are positive. Actor/action ID0 is permitted for system changes. Counts are canonical: `fragment_count = ceil(total_changes/2048)` and `count = min(2048, total_changes - fragment_index*2048)`. Each change is 15 bytes:

`cell_x:u16, cell_y:u16, cell_z:u16, before:u32, after:u32, flags:u8`.

Dictionary representation is `{cell:Vector3i, before:int, after:int, flags:int}`. Cell coordinates must lie inside the declared dimensions. Color0 is air; nonzero solid colors must be exactly `0x01RRGGBB`. Flags only permits `0` or `1` (collapsed). Duplicate cells within a fragment are rejected. At 2048 changes the total frame is 30,776 bytes, within the ordinary cap.

Cross-fragment duplicate detection, transaction identity/ordering, before-color comparison, ordered collapse application and historical terrain are future runtime responsibilities. The codec rejects an inconsistent fragment count but does not apply or commit any transaction. Sender ownership of actor/action fields also requires server validation.

### SNAPSHOT: actor poses and owner state only

Fixed prefix (41 bytes) in order:

`map_sequence:u32, event_sequence:u32, input_ack:u32, profile:u8, owner_id:u32, owner_state`.

`owner_state` is 24 bytes:

`health:u8, magazine:u16, reserve:u16, grenades:u8, blocks:u16, fire_tick:u32, reload_tick:u32, cook_tick:u32, respawn_tick:u32`.

Health is `0..100`, magazine `0..30`, reserve `0..150`, grenades `0..3`, blocks `0..50`. These are schema-family caps, not proof of a particular rifle/shotgun's valid clip size or authoritative inventory. Profile is0/1. Deadline0 can mean inactive; interpretation, current tick/cooldown and private-state recipient validation are upcoming.

Then `actor_count:u8` and that many actor records, minimum 47 bytes each:

`id:u32, spawn_generation:u32, team:u8, flags:u16, tool:u8, weapon:u8, name:text(64), feet:3×f32, native_velocity:3×f32, yaw:f32, pitch:f32`.

Dictionary keys are exactly `id, spawn_generation, team, flags, tool, weapon, name, feet, native_velocity, yaw, pitch`; vector fields use `Vector3`. ID and spawn generation are positive. IDs must be unique; a nonzero owner ID must appear in the actors array. Owner0/empty actors permits a loading replica. Team0/1 are playing teams,2 spectator; a spectator cannot set alive. Tools0..3 and weapons0..2 have the same meanings as INPUT.

Flag bits0..7 are alive, crouch, sprint, wade, grounded, connected, reloading, cooking. All other bits are rejected. Positions/velocities must be finite binary32 values; world-bound/speed legality is checked by simulation, not this codec. Native velocity uses the source magnitude in Godot axes (`displacement = velocity * 32 * dt`). Actor yaw/pitch use the same finite bounds as INPUT. Public actors carry no other actor's private ammo/health; only owner state includes resources.

The current snapshot has **no** CTF flags, territories, team metadata/score, grenades, block-health timers, kill/event payloads, animation action timestamps or corpse state. `event_sequence` is only a cursor and implements no event delivery. This snapshot is not a complete match/join snapshot.

## Deliberately unimplemented families and integration

ACTION_RESULT, GAME_EVENT, reconnect close/resync messages, team/class/mode requests, discovery/catalog, objectives/projectiles and compression/transfer assembly require a later schema change and tests. No WebSocket, authentication, clock scheduling, prediction/reconciliation, lag compensation, server authority or client replica is implemented by this file. New kind IDs are rejected until explicitly defined; do not silently encode an arbitrary dictionary as a substitute. Version compatibility will be recorded when peers exist.

## Verification

Godot4.7.2 `ed1daf0bf`: parser check and standalone test suite **1591 assertions, 0 failures**, exit0, with no warnings, script errors or leaked-resource diagnostics in `.cache/logs/protocol-tests.log`. Reproducible commands from the workspace root:

```powershell
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/protocol.gd
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_protocol.gd --verbose
```

The suite does not instantiate main or save preferences. It covers independent envelope/float-endian goldens, all13 family roundtrips, every prefix truncation of the representative frames, oversize/length/version/reserved errors, hostile counts, NaN/Inf, malformed/overlong UTF-8 and controls without string-conversion warnings, opaque token lengths, duplicate records/actors/cells, cell/color/fragment limits, owner state and deterministic scalar-byte mutations. Test counts/results are handed to the coordinator; passing these tests establishes a bounded codec only, not N-row or multiplayer acceptance.
