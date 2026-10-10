# Confirmed game events body

`game/network/events_codec.gd` is a pure, explicit binary codec for confirmed authority events. It has no Protocol preload, transport, nodes, main scene, preferences or Variant serialization. The runtime wraps these bytes in the agreed `GAME_EVENTS` envelope and validates that its epoch matches the decoded body. This file does not establish browser multiplayer acceptance.

`encode({epoch,first_sequence,last_sequence,events})->{ok,error,bytes}` accepts only normalized fields below. `decode(bytes)->{ok,error,payload}` returns deeply immutable dictionaries/arrays. `from_events(epoch,events:Array[Dictionary])->{ok,error,payload}` adapts the current immutable `MatchSimulation.drain_events()` journal, then validates and copies the bounded result. A failure has an empty bytes/payload result; unknown types/fields are errors, never skipped. `visibility(type)` returns `public`, `owner` or `invalid` for the runtime router.

Use `drain_events()`, which adds a frozen copied `match_sequence` in global journal order. `step_fixed()` and direct rule return arrays retain their unsequenced source envelopes and are not valid inputs. Split a journal into batches of at most64 **before** calling the adapter. An empty batch has first/last0. Otherwise first/last must equal the first/last included event's positive global sequence. Included sequences strictly increase; event IDs must be unique within a batch. Gaps are permitted because owner privacy routing omits other actors' personal events. A stream consumer tracks the authoritative snapshot/event cursor and deduplicates IDs; it must not infer packet loss from a gap caused by routing. Sequence rollover requires an explicit new epoch.

## Byte layout (version1)

All integers are unsigned big-endian; numeric/vector components are IEEE754 finite f32. Body maximum32744 bytes leaves24 bytes for the ordinary protocol envelope. Strings are length-prefixed UTF-8 with maximum96 bytes, no C0/DEL/C1 controls, overlong sequences, surrogates or code points above U+10FFFF.

| Part | Layout |
| --- | --- |
| Body header (14 bytes) | `version:u8=1, epoch:u32>0, first_sequence:u32, last_sequence:u32, count:u8<=64` |
| Event descriptor | `type:u8, record_length:u16` |
| Common record | `tick:u32, owner_id:u32, spawn_generation:u32, action_sequence:u32, match_sequence:u32>0, event_id_length:u8, event_id:UTF8` |
| Event details | Fixed allowlisted schema selected by type below |

The decoder checks body size, count and minimum remaining record bytes before event allocation, then bounded record length before copying each record. It checks UTF-8 byte validity before engine text conversion and validates nested array counts before allocation. Unknown types, trailing bytes, missing fields, extra fields, wrong scalar/vector types, NaN/Inf, out-of-range values and semantic identity mismatches fail. Accepted decoded payloads re-encode canonically. Numeric writes reject values whose f32 rounding would exceed the same read-side bounds.

Each normalized event contains the eight common fields `type,epoch,tick,owner_id,spawn_generation,action_sequence,match_sequence,event_id`, with epoch inherited from the header. Source actor ordinals are validated against IDs, then omitted as redundant. No per-actor RNG state or future spread is serialized.

Canonical IDs use decimal u32 components without signs/leading zeroes: actor `epoch:owner:generation:actor_ordinal`, objective `epoch:o:ordinal`, projectile `epoch:g:grenade_id:ordinal`, system `epoch:m:match_sequence`. Actor and projectile owner/generation are positive; system owner/generation/action are0. Objective owner/generation are both0 or both positive; objective action is0. A source-linked confirmed hit/tracer/spade/impact must identify the same owner/generation action. References accept empty (no linked action), a canonical same-epoch event ID, or a bounded colon-free trusted external ID. Arbitrary colon-bearing custom namespaces fail rather than introduce ambiguous identities.

## Type enum and details

This ordered table is the frozen v1 type enum. Changing its order or byte schemas requires a version change. `point`/`velocity` are three finite f32 values within ±4096; direction vectors additionally have length squared within.001 of1. `cell` is `x:u16(0..511),y:u8(0..63),z:u16(0..511)`; actual map dimensions are checked by authority/replica, not supplied by this body. `normal` is three u8 values encoding components−1..1 as0..2, with Manhattan length≤1 (zero covers a ray originating in a solid cell). `bool` is canonical0/1. Actor/objective/projectile IDs are u32.

| ID | Type | Ordered details |
| --- | --- | --- |
| 1 | spawn | `feet:point,team:u8(0..1),weapon:u8(0..2)` |
| 2–5 | actor_joined, actor_disconnected, actor_reconnected, actor_removed | none |
| 6 | team_changed | `team:u8(0..2)` |
| 7 | class_pending | `weapon:u8(0..2)` |
| 8 | tool_selected | `tool:u8(0..3)` |
| 9 | tool_swapped | `tool:u8(0..3),weapon:u8(0..2)` |
| 10 | reload_started | `weapon:u8(0..2)` |
| 11–14 | reload_cancelled, shell_loaded, reload_completed, dry_fire | none |
| 15 | restock | none |
| 16 | blocks_used | `count:u8(1..50)` |
| 17–18 | block_recovered, grenade_pin | none |
| 19 | grenade_thrown | `position:point,native_velocity:velocity,fuse:f32(0..3),cook_time:f32(0..u32max/60),drop:bool,team:u8(0..2),cook_action_sequence:u32,automatic:bool` |
| 20 | hurt | `amount:u8(1..100),attacker_id:u32,cause:u8,action_id:UTF8` |
| 21 | death | `attacker_id:u32,cause:u8,action_id:UTF8` |
| 22 | shot | `weapon:u8(0..2),profile:u8,origin:point,pellet_count:u8,directions:pellet_count×direction` |
| 23 | jump | none |
| 24 | land | `hurt:bool` |
| 25 | footstep | `wade:bool` |
| 26–27 | spade_bash, spade_dig | none |
| 28 | kill_credit | `victim_id:u32>0,victim_generation:u32>0,cause:u8,source_event_id:UTF8` |
| 29 | hit_confirmed | `victim_id:u32>0,part:u8,damage:u8(1..100),position:point,friendly:bool,source_event_id:UTF8,pellet:u8(0..7)` |
| 30 | block_hit | `cell,position:point,normal,source_event_id:UTF8,pellet:u8(0..7)` |
| 31 | tracer | `origin:point,position:point,weapon:u8(0..2),source_event_id:UTF8,pellet:u8(0..7)` |
| 32 | spade_miss | `source_event_id:UTF8` |
| 33 | spade_block_hit | `cell,position:point,normal,dig:bool,source_event_id:UTF8` |
| 34 | build_error | `reason:u8` |
| 35 | blocks_built | `count:u8(1..50),cells:count×cell,line:bool,color:u32(0x01000000..0x01ffffff)` |
| 36–38 | grenade_exploded, grenade_water, grenade_bounced | `grenade_id:u32>0,position:point` |
| 39 | intel_drop | `team:u8(0..2),flag_team:u8(0..1),position:point` |
| 40 | intel_pickup | `team:u8(0..1),flag_team:u8(0..1)` |
| 41 | intel_capture | `team:u8(0..1),flag_team:u8(0..1),score:u32` |
| 42 | intel_return | `team:u8(0..1),flag_team:u8(0..1)` |
| 43 | territory_capture | `team:u8(0..1),territory:u8(0..15),position:point` |
| 44 | round_won | `team:u8(0..2),winning_team:u8(0..1),mode:u8` |
| 45 | events_resync_required | `resync_required:bool=true` |

Enums: cause0..4 = `weapon,melee,grenade,fall,team_change`; part0..4 = `head,torso,arms,legs,melee`; profile0..1 = `0.75,0.76`; mode0..2 = `sandbox,ctf,tc`; build reason0..2 = `line has no support,invalid line start,invalid placement`. Other values fail. A shotgun shot has exactly8 confirmed rays; rifle/SMG exactly1. Build cells must be unique. Enemy intel pickup/capture require differing team/flag_team; return requires equal teams.

## Source adapters and privacy

Adapters retain all source details except explicit redundancies/personal recoil: actor `actor_event_sequence` is checked then omitted; `shot.recoil_direction` is checked as a finite unit vector then omitted (own recoil comes from prediction/owner state); source objective/system events receive normalized action0; melee `hit_confirmed` receives pellet0; a resync marker's optional `event_sequence` must equal `match_sequence` and is omitted. Unknown source extras fail. Normalization never freezes or mutates caller-owned nested arrays.

`visibility()` marks `hurt,hit_confirmed,class_pending,dry_fire,build_error,blocks_used,block_recovered,restock` as **owner only**. The runtime must select the authenticated event owner, including the victim for hurt and attacker for hit confirmation; codec validation alone does not enforce a destination. All other supported types are public and reveal no remaining ammo/stock, private RNG or personal hurt amount. Public death/kill credit give explicit attacker/victim/cause/action feed attribution. Reload/tool/motion events are public cosmetic cues; actor identity/name/team and current states come from snapshots. A future public nonlethal blood event must use its own redacted schema rather than broadcasting private confirmation payloads.

Shot directions describe an already-confirmed discharge and are public; clients never submit them as authority. Tracer endpoint, impact normal/cell and pellet index are retained. `grenade_thrown` preserves owner generation, release input and original `cook_action_sequence`, remaining fuse, native velocity, forced drop and automatic release flags. Native velocity is converted to world meters/second by multiplying32. Fuse must agree with `max(0,3-cook_time)` within.00001; drop and automatic cannot both be true. The thrown source event does not contain grenade_id; snapshots and flight events identify the authoritative projectile. Consumers correlate release with owner/generation/cook action, not a client-assigned projectile.

Source hurt has no damage-origin field. A view can use an available attacker/projectile pose or a nondirectional fallback; this codec does not invent a point. Restock/reload events contain no resulting resource totals; install the authoritative owner state separately. Source objects remain authoritative simulation values; these messages are presentation outcomes, never client commands.

When the bounded journal overflows, the one `events_resync_required` marker uses the current positive global cursor as its first/last range and identifies loss explicitly. It does not claim the lost events were delivered. The runtime invalidates the affected event stream and installs a fresh state baseline; replaying guessed effects is forbidden. Map recovery uses the separate ordered map transaction/baseline contract.

## Verification

Godot4.7.2 pure tests load no main scene or preferences:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --check-only --script res://network/events_codec.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_events_codec.gd --verbose
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/test_match_simulation.gd --verbose
```

Result: **280 assertions / 0 failures**, exit0, stderr empty and no resource/ObjectDB leaks; the cursor regression is **208 / 0**. Ignored local evidence: `.cache/logs/test-events-codec.log` and `.cache/logs/test-match-simulation.log`. Tests cover all45 emitted schemas, exact independent byte golden, actual Match gun→hit/hurt/death/credit/tracer, validated colored block outcome and surface impact, pin→release→flight/explosion/death-drop, CTF disconnect/reconnect/capture and TC capture, lifecycle events, owner/public privacy routing and replay ID deduplication. Hostile checks include every truncated prefix,500 deterministic byte mutations,250 arbitrary noise frames, malformed UTF-8, wire NaN/nested counts, unknown keys/types/enums, invalid identities/epoch/generation, array/cell/color/point bounds and exact64-event/50-cell limits. Headless serialization proof does not establish socket delivery, browser rendering or multiplayer acceptance.
