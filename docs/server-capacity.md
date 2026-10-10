# Native server capacity investigation

Date: 2026-10-10. This is a measured development baseline, **not a supported
player-count or sustained 60 Hz guarantee**. The original c4/contended baseline
and later same-checkpoint comparisons are separate sections. Production files were read-only;
the benchmark owns only `tests/network/benchmark_server_capacity.gd`.

## Environment and reproduction

- Godot 4.7.2 `ed1daf0bf`, official Windows editor/console binary, headless.
  This is not the Linux release-server template.
- Intel Core i5-10400H 2.60 GHz, 4 cores / 8 logical processors, approximately
  7.61 GiB usable physical RAM. Other project/browser work ran concurrently;
  CPU frequency, scheduler isolation and process working-set peaks were not
  controlled. Maxima therefore include workstation contention/preemption.
- Source HEAD was `c4f808990b84d068242dde47b8fe4f2951e322fe` with current dirty
  integration. The JSON records startup SHA256 for eight production modules.
  In particular the measured Runtime hash is
  `d7d159169f3d2286a63005340b654593fef5250a795a1db2597830952c582477`,
  SimulationCodec
  `50e30eba9aeba5c29823c6da078f1e03f981fc5ebd6373713466e32f4238b925`,
  HitHistory
  `15621a23b55335b3f60440593244284943e340ddb7f30b9e8f2a3e9a422a07e3`.
- No Main, renderer, model/audio service or preference access. Listeners use
  ephemeral ports bound to `127.0.0.1` and are explicitly stopped.

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/benchmark_server_capacity.gd
```

Outputs: `.cache/benchmarks/server-capacity.json` and the captured
`.cache/logs/server-capacity.log`. Final result **556 checks, 0 failures**;
run wall time **156.16 seconds**. It is an opt-in diagnostic, not a routine CI
test. Although all loops/allocations are bounded, this slow baseline took
longer than intended; do not rerun repeatedly on a loaded workstation.

## Pure authority and source cadence

Each case has a 128×16×64 colored data map (512 KiB canonical block storage),
60 warm-up ticks, then **300 measured fixed ticks**. Trusted isolated actors
use production source motion, a small rightward movement, held fire, normal
inventory and natural magazine depletion. Weapons rotate Rifle/SMG/Shotgun,
profile 0.75; friendly fire is disabled. Production Runtime records actor
history and resolves an admitted tick eight closed ticks behind current time.

These cases have no registered sockets, input queues or connection admission.
Their trusted fixture controls are not client network inputs. Every actor
produced the expected **10 rifle / 30 SMG / 5 shotgun** shots over 300 ticks;
SMG and rifle then exhaust their normal magazines. There are no ammo cheats,
reload cycles or unlimited-fire claims. Recorded rifle ticks are
60,90,...,330; shotgun 60,120,...,300. SMG ticks preserve the source fractional
6.6-tick cadence, ending at 252 after its thirtieth round. All rewinds in these
cases succeeded without missing-history denial.

Times below are milliseconds, mean / p95 / max. Tick samples: 300 per case.
The percentile is sorted sample index `floor((n-1)*.95)`.

| Actors | Runtime fixed step | All-owner snapshot encoding | Peak source event burst fanout |
|---:|---:|---:|---:|
| 1 | 4.740 / 16.530 / 72.019 | 61.264 / 76.088 / 92.278 | 21.602 / 36.979 / 52.741 |
| 8 | 30.977 / 87.084 / 847.598 | 270.925 / 274.352 / 376.339 | 481.379 / 504.571 / 507.763 |
| 16 | 54.596 / 142.490 / 930.078 | 1038.228 / 1190.392 / 1251.420 | 2649.149 / 3038.122 / 3132.900 |
| 32 | 65.490 / 194.705 / 1359.804 | 2738.009 / 2933.474 / 4261.971 | 5636.538 / 6117.232 / 8092.296 |

Serialization is measured **separately**, five full all-owner samples. Each
snapshot batch follows the production `snapshot_for` → `from_snapshot` →
Protocol.encode path. Its cost is relevant to the 20 Hz publication interval;
the test does not sustain 100 such publications during the 300 pure ticks.
Event samples route one real maximum observed step burst through the same
public/private selection, bounded batching, EventsCodec and Protocol path for
every owner. Burst sizes are 2 / 30 / 67 / 134 events. They are peak-shot
fanout costs, not average event traffic at 60 Hz.

A discarded interleaved prototype showed lower numbers: 1-actor Runtime
mean 1.505 ms and snapshot mean 7.626 ms; 8-actor Runtime mean 8.464 ms and
snapshot mean 155.031 ms. This variance is why these numbers cannot certify
capacity. The prototype's external pre-step edit also invalidated some closed
history queries; those samples are not source-cadence or rewind acceptance.
The final harness removes that artificial timing error and covers terrain
separately. Prototype log is preserved as
`.cache/logs/server-capacity-interleaved-prototype.log`.

## Bounded terrain history stress

One committed 32,768-cell transaction is applied away from actor spawn space.
History retains two matching actor/terrain frames and reconstructs the prior
air cells. This reaches the default change-count cap. Its reported encoded
journal estimate is **492,416 bytes**, not 8 MiB. The independent 8 MiB byte
cap does not mean this fixture stores an 8 MiB serialized journal; Dictionary
memory overhead was not measured.

| Work | Mean ms | p95 ms | Max ms | Samples |
|---|---:|---:|---:|---:|
| One historical query | 132.673 | 133.876 | 136.187 | 3 |
| Eight independent queries | 1084.012 | 1156.247 | 1165.560 | 3 |
| Thirty-two independent queries | 4927.299 | 4649.857 | 5672.940 | 3 |
| One actual 32-shot Match preplan step | 5687.294 | — | — | 1 |

Single full transaction apply: 1243.207 ms; history validation/record:
926.194 ms. The 32-shot case has 32 valid plans and zero denials. It uses the
same-time historical map and actors, current-generation checks and production
source pellet rays. It demonstrates the cost of rebuilding the inverse map
for every shot, not live transaction frame safety.

A separate 12-sample faithful support-removal case removes one support cell
and four collapsed cells in an atomic ordered authority receipt:
remove/collapse mean .569 ms / p95 .370 / max 4.833;
matching history record mean .141 / p95 .210 / max .375. The occasional maximum
and the larger-than-p95 mean are consistent with a small contaminated sample.
These five-cell results cannot be extrapolated to a full-map collapse.

## Real native sockets

Production ServerRuntime and complete ClientReplica clients connect over
actual game and bulk WebSocket/TCP sockets. Two clients join sequentially,
validate the 512 KiB baseline/barrier, then submit owned input during measured
batches. Each count has 60 measured steps; Runtime makes real 20 Hz snapshots.
No fake transport or main-scene presentation is involved.

| Clients | Server step mean / p95 / max ms | Server poll mean / p95 / max ms | All clients poll/decode mean / p95 / max ms |
|---:|---:|---:|---:|
| 1 | 6.783 / 22.484 / 43.231 | 4.637 / 12.504 / 15.217 | 9.648 / 35.984 / 42.602 |
| 2 | 13.508 / 42.293 / 66.915 | 10.392 / 27.053 / 54.379 | 20.336 / 78.560 / 104.316 |

Whole-harness compute (input submission/prediction + server poll/step + client
poll/decode) is mean/p95/max 26.291/47.530/54.997 ms for one client,
58.829/104.171/145.221 ms for two. This includes client work in the same process
and is not a dedicated-server-only tick cost. Wall batches were 1.648 s and
3.602 s; sequential join times 1.061 s and 3.076 s. Simulation ticks are
explicit fixed advances with event-loop yields, not real-time 60 Hz pacing.

Peak observed per-peer queue was **one frame, 693 bytes** including the
socket outbound buffer during measured batches. All clients remained live;
protocol errors, timeouts, backpressure, input rejection and resync counters
were zero. All sockets/listeners were released. This is not TCP saturation,
WAN latency, browser/WSS, or 32-client network capacity evidence. Actual
socket count stays small because the large-count codec baseline is already
slow and a full 32-client run would add substantial redundant decode work.

## Concrete bottlenecks and next validation

1. `MatchSimulation.snapshot_for:799` copies all actor state plus owner state
   for each recipient. `SharedPlayerState.copy:84` enumerates/copies script
   properties. `SimulationCodec.from_snapshot:181` converts and validates an
   encoded body, and Protocol encoding serializes that body again. Per-owner
   public actor work repeats across the whole roster. Cache canonical public
   state once per closed snapshot tick, with explicit owner-private bodies,
   then use byte-differential regressions before changing the production path.
2. Runtime `_route_events:512` repeats public event conversion/validation and
   binary encoding for every recipient. Share immutable encoded public batches
   while preserving owner-only health/hit/resource privacy and connection
   queue bounds. Measure source shotgun bursts as well as quiet ticks.
3. `HitHistory.query_at:182` traverses the same inverse transactions and clones
   historical actor poses independently for every shot. A validated same-time
   cache or one grouped query per admitted tick could avoid repeated inverse
   reconstruction. Preserve stale-authority guards, query isolation, same-time
   terrain/actor identity and all-shot preplanning before mutation.
4. The 300-step simulation itself also exceeds the 16.667 ms tick budget in
   this loaded debug baseline. Profile source motion, actor hit-volume/ray
   scans and copied event/pose data after removing serialization overhead;
   do not assume network encoding is the only cost.

The coordinator owns production changes. Repeat the opt-in benchmark against
a frozen source snapshot after optimizations, with identical actor/weapon/map
fixtures, then measure the pinned Linux release template on a quiet host.
Only after real paced socket/load tests can a supported player count be chosen.

## Focused history-cache follow-up

The earlier tables above remain the original loaded-workstation baseline. A
separate nearer pre-cache fixture was run before changing HitHistory, then
three cached fixtures with identical Match/RULES/Data and original hit-volume
code. `--history-only --output-name=<name>.json` runs only the bounded 32768
committed-change case; no sockets, Main or preferences. Every final run passes
194 checks with zero failures. Production fanout was changing independently,
but this isolated case does not perform snapshot/event fanout; startup hashes
pin each artifact.

| Work | Nearer uncached baseline | Final cached runs |
|---|---:|---:|
| 32-query group, warm cache when available | 546.092 ms mean of3 | 3.061 ms mean of9; run means2.999..3.178 |
| First cold index/query | ~18.152 ms old individual-query mean | 44.834..49.813 ms |
| Actual32-shot Match step, cache cold before step | 752.053 ms, one sample | 259.006/261.457/325.522 ms; mean281.995 |

The first query builds one frozen closed-context cell timeline index, bounded
by the existing32768 receipt cap; subsequent queries, including different
requested frames of that context, reuse it. Per-query leases and actor copies
remain independent. Each shot step begins with an explicitly evicted cache
so it includes a rebuild. All32 shots plan successfully without denials;
cache entries1, records32768. The helper skips index work for current-map
queries. Context revocation releases its records even with retained query
references. See `hit-history.md` for lifetime and same-color limitations.

Observed warm group speedup is ~178× and the actual cold shot step ~2.7×
against this nearer baseline; CPU load is not isolated and the baseline has
one shot sample. First-build cost increased compared with a single old
query. This does not prove60 Hz or32-client capacity. Full map transaction
apply/history validation still costs hundreds of milliseconds; remaining
actor-volume/pellet work is a separate bottleneck. HITS optimization and
root fanout changes must be measured in another coherent comparison.

Evidence: `.cache/benchmarks/history-query-baseline.json` (193/0) and
`history-query-cache-final-1.json` through `-3.json` (194/0 each); logs with
the same stems. The original `server-capacity.json` remains unchanged.

## Paired publication modes

The benchmark accepts `--publication=legacy|prepared`, default `legacy`.
It changes the isolated snapshot/event batch encoder only; all300 simulation
ticks use the same current Runtime/Match/history/hit-volume code. Every actual
socket case uses Runtime's production default prepared publication. No custom
SnapshotFactory is installed, so socket results must not be read as a
legacy-versus-prepared transport comparison.

The legacy snapshot path uses `snapshot_for(owner)` -> `CODEC.from_snapshot`
-> `P.encode` for every owner. Prepared uses one `CODEC.prepare_shared` from
one snapshot, then `P.prepare_state` for each actor and counts the returned
`FrozenFrame.bytes()`. Prepared event bursts use one `EVENTS.prepare_shared`
over the full committed source burst, then `P.prepare_events` per owner.
Owner-only event routing remains the production codec's responsibility.
Every timed sample includes common capture/validation and per-owner envelope
creation; a prepared body is not reused across the five measured batches.

Run a pair only after a coherent production handoff, saving distinct JSONs:

```powershell
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/benchmark_server_capacity.gd -- --publication=legacy --output-name=capacity-paired-legacy.json
& ./.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/network/benchmark_server_capacity.gd -- --publication=prepared --output-name=capacity-paired-prepared.json
```

Confirm startup source hashes match, along with actor counts, source weapon
cadence, burst events and encoded byte totals, before reporting a ratio.
The publication mode and actual socket path are explicit in each result.
The nearer history and original baseline JSONs must remain unchanged.

Prepared publication still owns captured public pose/context records plus
encoded common bodies and per-owner frames; it is not one universal frame
for every recipient. `FrozenFrame.bytes()` returns an owned duplicate, and
that call is included in the measurement. Total encoded bytes are wire-size
accounting, not peak heap/queue memory. Contexts live only within one encoder
batch in this harness; production queued frames may live longer. No prepared
heap reduction, sustained20Hz/60Hz or supported player count is inferred from
the API or byte-exact regression tests.

### Same-checkpoint results

Both runs pass **557 checks / 0 failures**; wall17.493 s legacy and11.172 s
prepared. All15 recorded production hashes match, as do all source weapon
counts/shot ticks/magazines, peak burst counts and aggregate wire bytes. HITS
SHA `b73a05a5f5b9e4138eaebcc7333e27e4455eaad23ef3a352ba98c1a1ab1c0828`;
Match SHA `d9f578a66824e335e6e20ad5fd860573ffcecb6092c770ef3e543debef9c9816`;
history SHA `479f6c7fe4e6e819b8e23374ee665924548932eae22fedb2f0e90c238fcec1a7`.
Root's other engine/GPU workloads were paused during these runs; OS process
scheduling/frequency still were not isolated. These are the same Windows
editor/hardware fixtures, not Linux release or public WSS measurements.

Runtime tick mean/p95/max milliseconds over300 ticks (isolated publication
encoding runs afterward; Runtime has no admitted sockets in these cases):

| Actors | Legacy-labelled run | Prepared-labelled run |
|---:|---:|---:|
| 1 | .250 / .205 / 2.634 | .625 / 1.285 / 7.089 |
| 8 | 2.582 / 8.534 / 47.099 | 4.181 / 17.351 / 114.469 |
| 16 | 5.396 / 15.750 / 117.551 | 6.470 / 18.848 / 150.227 |
| 32 | 11.888 / 39.322 / 253.148 | 13.220 / 43.692 / 271.132 |

The simulation path is identical in both runs. Its timing differences are
sample/load variation, not an effect of the selected publication flag.
Natural ammo depletion means later ticks have no bullets; means below the
16.667 ms budget do not establish sustained firing or60 Hz acceptance. The
32-actor p95 is around40 ms and maxima around250..270 ms.

Five timed all-owner batches, mean/p95/max ms:

| Actors | Snapshot legacy | Snapshot prepared | Peak burst legacy | Peak burst prepared |
|---:|---:|---:|---:|---:|
| 1 | 1.932 / 2.700 / 3.083 | 2.567 / 2.811 / 2.881 | .724 / .844 / 1.143 | .783 / .800 / .859 |
| 8 | 25.850 / 25.762 / 27.794 | 4.058 / 4.098 / 4.114 | 49.267 / 49.669 / 50.934 | 4.345 / 4.402 / 4.450 |
| 16 | 84.455 / 85.065 / 86.326 | 8.048 / 8.016 / 9.054 | 208.970 / 210.600 / 210.814 | 12.120 / 11.694 / 14.796 |
| 32 | 323.118 / 325.658 / 328.807 | 13.598 / 13.626 / 13.733 | 917.909 / 957.429 / 1047.733 | 23.705 / 23.829 / 23.957 |

At32 owners, prepared snapshot publication is about23.8× faster and the
134-event burst about38.7× faster in these samples. One-owner preparation
has overhead rather than a win. Snapshot/event wire totals over five samples
are identical: at32 owners582030/1576480 bytes; peak burst counts2/30/67/134
for1/8/16/32. These are batch costs, not five sustained20Hz streams.

The same-checkpoint heavy32768-change cases remain expensive: transaction
apply277.198/266.065 ms, history validation/record210.004/199.182 ms,
first cold index/query50.327/47.906 ms, warm32-query mean3.284/3.195 ms,
and actual32-shot cold-cache step322.952/261.962 ms (legacy/prepared-labelled
runs). Both plan32 shots and deny0. Publication flags do not alter these
paths, so do not attribute their difference to prepared encoding. Small
support/collapse receipts still contain one primary and four collapsed cells:
remove means .173/.077 ms; history means .117/.053 ms over12 samples.

Both actual2-client socket cases use production prepared Runtime. Server
step mean/p95/max is1.122/3.571/4.237 ms in the legacy-labelled run and
.936/1.853/3.311 ms in the prepared-labelled run. All clients remain live;
observed queues peak1 frame/693 bytes, protocol/timeout/backpressure/input
rejection/resync counters0 at the measured batches. This is repeated
same-path socket evidence, not a transport-mode speedup. Parser and logs are
clean and all listeners/sockets are explicitly stopped.

### Bounded32-client attempt

An opt-in `--sockets-only --socket-clients=32 --publication=prepared` run
uses the same15 production hashes and actual full ClientReplicas on game+
bulk WebSocket/TCP connections. It sequentially joins clients and measures
60-step batches at1/2/8/16/32, with a global60000 ms work deadline. The
benchmark now records terminal runtime/queue/client status summaries for
future runs; they were not recorded in this first attempt and are not
retroactively inferred.

The attempt reaches complete batches through16 clients. Eight clients
joined by5.685 s, sixteen by17.299 s and twenty-four by42.500 s. Twenty-eight
joins completed; attempt29 hit the global deadline. The raw first JSON's
`joined_clients=29` counts allocated attempts, including the incomplete last
join. Work-loop wall60.085 s, whole run60.158 s includes synchronous poll
overshoot and cleanup. **335 checks / 2 failures** are the unmet join/32-roster
budget assertions; this is an incomplete diagnostic, not product protocol
failure or32-client support. No32-client measured batch exists.

| Live clients in completed batch | Server step mean / p95 / max ms | Server poll mean / p95 / max ms | Whole harness mean / p95 / max ms |
|---:|---:|---:|---:|
| 1 | 1.047 / 2.673 / 3.432 | .438 / .731 / 1.197 | 3.739 / 7.062 / 8.009 |
| 2 | 1.108 / 2.803 / 3.010 | .519 / 1.064 / 1.211 | 4.932 / 12.025 / 12.968 |
| 8 | 2.520 / 5.295 / 7.109 | 1.251 / 1.520 / 2.263 | 14.107 / 26.561 / 26.721 |
| 16 | 5.664 / 14.130 / 18.010 | 2.990 / 4.768 / 5.623 | 39.579 / 94.912 / 128.073 |

At16 clients, client poll/decode alone averages22.895 ms/p9571.157/max105.226;
the whole harness also includes owned input/prediction for16 complete clients
in the server process. These are quiet moving clients, not simultaneous
gunfire/large map edits. Measured queues peak one frame/2156 bytes at16;
protocol/timeouts/backpressure/input rejection/resync counters are0 at that
last completed batch. Terminal totals after later joins are unavailable.
The final cleanup check passed with zero game and bulk connections; the
process exits1 for the explicit incomplete-budget assertions, without
resource leaks. No background service remains. The run is not repeated
merely to extend its limit. A dedicated server with clients on other hosts,
large original maps, real paced scheduling and WAN/TCP stalls is still a
different measurement.

Artifacts: `.cache/benchmarks/capacity-paired-legacy.json`,
`capacity-paired-prepared.json` and incomplete `capacity-real-sockets32.json`;
matching `.cache/logs/*.log`. Original c4/contended and focused history
artifacts remain unchanged.
