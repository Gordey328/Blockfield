# ADR0013: bounded audio/model caches and cooperative local VXL jobs

Date: 2026-10-11. Accepted for the user-authorized optimization item4
(audio, loading/saving and memory). Godot4.7.2 `ed1daf0bf`, Compatibility,
single-threaded Web. This does not change iteration acceptance or network rules.

## Decision

Cache the native 24-direction gun ambience result for an exact finite eye origin.
Retain at most128 origins for one World/Data identity, epoch, map sequence and
resource generation. Return an independent scalar dictionary. A terrain edit,
map replacement, reset, disabled environmental audio or resource reload makes
old answers unusable. Keep all native rays and sound routes on a cache miss.
The room/obstruction budget remains separate; cumulative counters now include
gun ambience and explosion ground rays. CPU timing is explicitly opt-in.

Retain at most256 exact-color tint materials independently for world and
first-person rendering. Evict the least recently used cache reference. Active
meshes retain their immutable material, so eviction never recolors a live model.
Base materials and scenes keep their existing resource-generation lifecycle.
Exact Color keys also avoid the old string-format rounding collisions.

Local VXL decode/encode use cooperative jobs. Each advance has a hard1024-column
cap and a soft2ms clock target checked between complete columns.
Main selects4096 columns/soft8ms when an operation begins with the menu open;
live-play operations retain1024/2ms. The initial2ms-only Web diagnostic stretched
Title loading to55.55s across877 frames, prompting a measured foreground budget.
Decode owns its input and private64MiB array; only a completed validated map is adopted. Encoding
uses `VoxelData.frozen_copy()` before the first yield, representing one coherent
version despite later live edits. The engine can defer packed-array physical
copying until a write: logical snapshot bytes are not an allocation measurement.
Small-map padding is virtual; default exterior columns use the exact native
8-byte floor span, avoiding an additional64MiB padded array.

World serializes local VXL operations with a token plus Data identity/epoch checks.
Main independently guards notices, reset baseline and downloads against obsolete
completion. New load/save, reset, authoritative map replacement and scene exit
cancel unfinished work. Failure preserves the installed map. Network and existing
synchronous test/authority APIs remain available without partially visible maps.

## Tradeoffs and evidence

Exact origins give little reuse while moving. Sequence-wide invalidation is
conservative even for edits outside the acoustic area; it keeps correctness simple.
Tint limits bound retained cache references, not all active mesh memory.
Web VXL staging yields between batches of at most two16KiB base64 chunks with
a soft2ms target; a new VXL request or scene exit aborts its pending JS buffers.
The visible download link preserves a real user gesture. PNG/JSON retain the
existing synchronous path, with a visible busy notice when another export owns
the dialog. JS retires each dialog independently so its queued close event cannot
clean up a newer export; abort preserves the input pointer callback.

Decode allocation, copy-on-write on a live edit, map adoption, chunk rebuilds and
final browser Blob creation remain indivisible operations outside the budgets.
Cooperative processing can increase total wall time while keeping input callbacks
available. Full load/save latency and memory need browser evidence.

Native isolated audio measurements found120 stationary calls cast5640→47 rays
with identical output. Moving calls retained5640 rays; edits every10 calls used564.
Measured player creation/release was approximately12–20µs per dry logical voice
and31–52µs with EFX. Defer player pooling until real Web gameplay demonstrates
material allocation/free cost: the isolated percentage excludes mixer/decode and
does not establish a frame bottleneck.

Detailed commands, failed attempts, measurements and browser/release identity:
[optimization evidence](../optimization-audio-vxl-memory.md).
