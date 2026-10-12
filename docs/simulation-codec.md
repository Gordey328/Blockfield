# Complete simulation snapshot body

> Historical pre-removal design/evidence. Multiplayer was withdrawn on2026-10-12
> under [ADR0031](decisions/0031-offline-only-game.md). Deleted networking paths
> and server instructions below do not apply to the current offline game.

`game/network/simulation_codec.gd` implements `SimulationCodec`, a pure `RefCounted` codec. It reconstructs a complete owner replay checkpoint and public match state from explicit big-endian fields. It has no socket, renderer, physics nodes, scene, generic Variant serialization or dependency on `BlockfieldProtocol`. The protocol envelope and connection/runtime policy are separate; passing these tests does not establish two connected browser clients.

```gdscript
var projected := SimulationCodec.from_snapshot(match.snapshot_for(actor_id))
if projected.ok:
    var encoded := SimulationCodec.encode(projected.payload)
    var decoded := SimulationCodec.decode(encoded.bytes)
    var owner: SharedPlayerState = decoded.payload.owner_state
    prediction.reconcile(owner, decoded.payload.tick,
        decoded.payload.map_sequence, confirmed_map_data)
```

`from_snapshot(Dictionary)` accepts trusted `MatchSimulation.snapshot_for` objects and returns `{ok,error,payload}`. It copies approved owner fields and source motion, builds owned public dictionaries from typed actor/grenade objects and duplicates objectives. It drops trusted debug fields such as block health/colors, line starts, pending cells, secondary state and `owner_id`. Every actor must match the checkpoint's epoch/profile/tick; grenades must match its epoch. `encode(Dictionary)` returns `{ok,error,bytes}`. `decode(PackedByteArray)` returns `{ok,error,payload}` with a new typed owner and owned public dictionaries. Failures expose an empty payload and bytes, with a bounded diagnostic that contains no name or secret contents.

The owner is an **after-tick** checkpoint: `owner.last_tick == tick >= 0`. Source spawn's `last_tick=spawn_tick-1` cannot be published as a completed spawn tick; advance the authority first. The body stores epoch/profile/tick once and reconstructs those owner fields from the header. IDs and spawn generations are positive u32 values. Epoch is positive; tick, map sequence, event counters and input acknowledgement are u32. Reset/rebase before counter exhaustion; no implicit wrap is accepted. The runtime must check envelope epoch/tick/generation against these body values, bind the owner to its connection, and install the matching map barrier before prediction. This codec does not authenticate snapshots or validate client actions.

## Types, limits and canonical order

All integers and IEEE754 floats are **big-endian**. `u8/u16/u32` are unsigned. `i64` holds `-1` inactive tick sentinels without reducing the u32 tick range. `f32` stores existing Godot Vector2/Vector3/Quaternion components; `f64` preserves GDScript scalar values, especially fractional source deadlines and cadence. No quantization or rounded deadline is introduced. Boolean bytes must be exactly `0` or `1`. Every float/vector/quaternion is finite. A name is `u16 byte_count` plus `1..64` validated UTF-8 bytes; reject overlong/truncated sequences, surrogates, values above U+10FFFF, C0 controls, DEL and C1 controls before conversion.

The top-level dictionary contains exactly `epoch,tick,map_sequence,dimensions,event_sequence,profile,mode,owner_state,actors,grenades,objectives`. Unknown fields and wrong types are rejected rather than serialized into an opaque extension. Property names used for owner reconstruction come only from compile-time allowlists; untrusted bytes never choose a property name or object class.

| Body prefix byte | Field | Encoding |
| --- | --- | --- |
| 0 | Body schema version | u16, exactly `1` |
| 2 | Match epoch | u32, positive |
| 6 | Completed simulation tick | u32 |
| 10 | Authoritative map sequence | u32 |
| 14 | Dimensions x,y,z | three u16, `1..512`, `1..64`, `1..512` |
| 20 | Global event sequence | u32 |
| 24 | Profile | u8: `0=0.75`, `1=0.76` |
| 25 | Mode | u8: `0=sandbox`, `1=ctf`, `2=tc` |
| 26 | Owner record | Layout below |
| Variable | Public actors | u8 count `1..32`, then records |
| Variable | Live grenades | u16 count `0..256`, then records |
| Variable | Objectives | Layout below |

Body limit is **32,744 bytes**, leaving a24-byte protocol envelope inside a32,768-byte ordinary frame. Counts are checked before counted allocation: actors need at least93 bytes each, grenades74 and territories23. The actually largest valid body with a64-byte owner name,32 actor names of64 bytes,256 grenades and16 territories is **24,748 bytes**. Names contribute twice for the owner because its public record accompanies its private checkpoint. The decoder rejects oversized/truncated bodies, all trailing bytes, concatenated bodies, invalid enums/counts and duplicate actor/grenade IDs. Decode reuses the explicit encoder validation after parsing; a failed validation never exposes a partially reconstructed payload.

Actor feet/eye and objective positions allow x/z within `[-16,dimension+16]` and y within `[-256,height+256]`; owner eye permits another4m above the upper bound. These generous sanity bounds permit source edge and above-ground motion, rather than mistaking map occupancy bounds for legal air position. Actor native velocity components are bounded to±128. Grenade x/z permit±1024 beyond the dimensions, y uses the same vertical bounds, and world velocity components are bounded to±4096. These are codec sanity limits, not movement/reach/gameplay authority. Source grenade snapshots may be created at checkpoint tick+1 by a between-step transition; their created/last ticks must stay within that limit, fuse within0..180 ticks after creation, and live `finished` must be false.

## Owner record

Fields are written in the following exact order. Within each row, left-to-right order matters. The fixed portion is279 bytes, plus the name bytes.

| Fields | Encoding |
| --- | --- |
| `player_id,spawn_generation` | two u32 |
| `connected,player_name` | bool, name |
| `team,weapon,tool,displayed_tool,displayed_weapon,health,magazine,blocks,grenades,input_buttons,previous_buttons` | eleven u8 |
| `pending_weapon,reserve` | u8 (`255=-1`, otherwise class0..2), u16 |
| `kills,deaths,score,consumed_input_sequence,cook_action_sequence,event_sequence,walk_steps` | seven u32 |
| `last_shot_tick,cook_started_tick,death_tick,respawn_tick` | four i64 |
| `aiming,sprinting,sneaking,trigger_held,dry_fire_held,reloading,digging,first_dig,cooking,release_pending` | ten bool |
| `tool_raise,sprint_state,aim_down_state,yaw,pitch` | five f64 |
| `input_move.x,input_move.y` | two f32 |
| `next_shot_tick,reload_started_tick,reload_deadline_tick,grenade_deadline_tick,block_deadline_tick,spade_deadline_tick,dig_deadline_tick,walk_distance` | eight f64 |
| `motion.feet_position,motion.native_velocity,motion.eye_position,motion.front` | four Vector3, three f32 each |
| `motion.crouch,motion.sprint,motion.grounded,motion.wading,motion.climbed,motion.vertical_collision,motion.landed,motion.fall_hurt` | eight bool |
| `motion.last_climb_time,motion.fall_speed` | two f64 |

Team is0/1/2; weapons0..2 and tools0..3. Health0..100, blocks0..50 and grenades0..3. Magazine/reserve are bounded by the source profile/class's clip/stock. Button masks permit only seven defined bits. Readiness is0..1; yaw±π and pitch±π/2. Move length is at most1. Inactive spade/dig deadlines permit−1; other action deadlines are nonnegative and bounded by the u32 tick horizon plus600. `last_shot_tick,cook_started_tick,death_tick` permit−1 or a completed tick; respawn may be at most180 ticks ahead. Walk remainder is0..64, last climb time is finite and no more than current seconds+1, and fall speed0..128. A spectator has zero health. Cooking requires a valid started tick, grenade inventory and grenade tool; active reload requires the weapon tool and ordered deadlines.

`shot_rng` is **never inspected, copied or serialized**, including its seed and internal state. The decoded owner gets a new local default RNG from `SharedPlayerState` construction. `ClientPrediction` substitutes its own isolated cosmetic stream before replay. Server pellet directions, victims and damage remain authority outcomes. Exact replay retains consumed/previous inputs, trigger/dry-fire state, readiness, source eye/climb/wade state, walk fraction and all source action deadlines. The scalar SMG cadence can therefore retain6.6-tick intervals rather than silently changing to integer ticks.

## Public actors and grenades

Each actor contains exactly the keys in `SimulationCodec.ACTOR_KEYS`. Wire order:

| Fields | Encoding |
| --- | --- |
| `id,spawn_generation,name,team,flags` | two u32, name, two u8 |
| `feet,native_velocity` | two Vector3/f32 |
| `yaw,pitch` | two f64 |
| `tool,weapon,displayed_tool,displayed_weapon` | four u8 |
| `tool_raise,sprint_state,aim_down_state` | three f64 |
| `kills,deaths,score` | three u32 |

Fixed size is92 bytes plus name bytes. `flags` bits are1 alive,2 crouch,4 sprinting,8 wading,16 grounded,32 connected,64 reloading,128 cooking. Decoding also exposes those eight boolean dictionary views. Encoding verifies every view agrees with the bitset. Alive spectators are rejected. The owner's public record must exactly match the private owner's public projection. Remote health, magazine, reserve, blocks, grenades, controls, consumed inputs, action deadlines and RNG are not included. Altering any of those private remote values cannot affect bytes.

Each grenade contains exactly `id,owner_id,owner_generation,action_sequence,team,position,velocity,orientation,created_tick,last_tick,fuse_deadline_tick,finished`. Wire order is four u32 IDs/action values, u8 team, two Vector3/f32, quaternion x/y/z/w as four f32, two u32 ticks, f64 fuse and bool finished: **74 bytes**. Orientation must be normalized within0.001 squared-length tolerance. Owner ID/generation remain positive even after its actor is removed; a live grenade need not have a current public actor. Hidden grenade epoch/event ordinal are omitted; its epoch derives from the match header. Team comes from the authority's retained grenade-team table, with source-neutral team2 fallback.

Decoded actor dictionaries satisfy the existing [RemotePoseBuffer](client-prediction.md) `flags/feet/native_velocity/yaw/pitch/id/generation` contract. Its current interpolation reads the established pose subset; this codec also retains tool-display/readiness, reload/cook flags and scores for a later presentation adapter. It does not change that buffer's100ms interpolation/extrapolation limits or imply those extra fields are already animated in a connected client.

## Typed objectives

The objective dictionary contains exactly `epoch,mode,capture_limit,winning_team,scores,bases,flags,territories`. Epoch/mode must agree with the body and are reconstructed from it rather than written again. The wire starts with u16 capture limit, u8 winning team (`255=-1`,0/1), two u32 scores, and two Vector3/f32 bases.

Exactly two ordered flags follow, each `team:u8,position:Vector3/f32,carrier:u32,at_base:bool` (18 bytes). Flag teams must be0 then1; carrier0 encodes dictionary−1/no carrier. An at-base flag must have no carrier and exactly its base position. A carried flag requires a currently alive, connected enemy actor. The rule layer supplies drop transitions before snapshotting; the codec cannot invent them.

Finally u8 territory count0..16 precedes records `position:Vector3/f32,owner:u8,capturing_team:u8,progress:f64,contested:bool` (23 bytes). Owner is0/1/2; capturing team is0/1 or255 for dictionary−1; progress is0..1. Fixed objective bytes total72. Sandbox/CTF may retain the configured territory records and TC may retain flags; unused configured state is not erased or guessed from the mode.

## Verification and remaining acceptance

Godot `4.7.2.stable.official.ed1daf0bf`, standalone headless, without main/preferences:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/simulation_codec.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_simulation_codec.gd
```

Result: **2,316 assertions / 0 failures**, exit 0. Actual `MatchSimulation` after-tick snapshots round trip in sandbox/CTF/TC scenarios with profile 0.76; replay/privacy/max-size fixtures use profile 0.75. Pre-step owners fail. An explicit BE prefix fixture, every truncation prefix of a real-sized body, malformed UTF-8/bool/enum/count/NaN/infinity bytes, unknown/missing properties, duplicate IDs, invalid flag carriers and exact maxima are checked. Every owner/source-motion value except server RNG survives a complete nondefault checkpoint. Four resumed shared-rule scenarios check fractional automatic fire, shotgun reload, held grenade release and movement/tool readiness through tick 160, with identical source cadence and final state. Server RNG and private remote controls/resources/debug changes produce identical encoded bytes.

Envelope wiring, authenticated owner selection, map/state barriers, event delivery/deduplication, real connection scheduling and exported native/Web cross-runtime replay remain runtime and acceptance work. This body addresses the earlier incomplete rounded-deadline owner payload; it does not itself implement server hosting, reconnect, historical terrain, network latency or browser multiplayer acceptance.
