# Three fidelity repairs — 2026-10-10

Authorized after mobile FPS release31 completed. OpenSpades v0.1.3 reference:
`dcf449c845d509bbde9d79239b32d201c1389961`; Godot
`4.7.2.stable.official.ed1daf0bf`, Compatibility, single-threaded Web.

Production implementation is source `0898d6c4bf373b4cd653ecc9342affde7c0ba03e`.
Test-only browser button isolation/fixture override is `8b1eeed`; mobile fixture
audio drain is `dcee15f0b7bcb4bf15bf70a638935bcd973d49f4`; socket fixture audio
drain is `07b3a1b`. All three change no production game files. Published client is
the clean frozen dcee15f archive. These repairs are not whole-port acceptance.

## Source behavior and implementation

- W07: `GLMapChunk.cpp:247-252` uses `(RGB & 0xfefefe) >> 1` below100HP;
  `World.cpp:102-115,190-195` recovers ten seconds after the latest hit.
  `VoxelWorld`/`VoxelChunk` implement a separate mesh-color mask. Controller
  health and Main's confirmed hit events supply expiry. Repeated hits extend it;
  edits, deletion, replacement, map adoption/reset and disconnect clear marks.
  RGB/occupancy, collision, AO, minimap, VXL and map journal are unchanged.
  [ADR0009](decisions/0009-block-damage-presentation.md) describes event ordering.
- P15 offline: `Player.cpp:136-159,490-494` distinguishes effective press edges,
  pin minimum and automatic/manual release. Controller retains the same press
  after automatic throw; a release/new press starts the next cook. LocalSession
  omits automatic cooldown and retains manual0.5s. Temporary input denial before
  the0.15s pin minimum preserves the same cook when control returns.
- U05: `ScoreboardView.cpp:278,291-298` shares the minimap player palette for
  #IDs. Actual RichTextLabels now split ID color from name/score tint. Live
  checkbox/console and loaded preferences update all three views. Disabled IDs
  are white; canonical network IDs wrap only the32-color lookup.

## Native verification

`tools.build.run` uses the pinned engine with `--headless --path game --script
<absolute script>`; actual-scene integration/mobile/network-damage fixtures use
`--fixed-fps 60`. Logs `.cache/logs/fidelity-*` contain exact commands/results.

| Check | Assertions / failures |
| --- | --- |
| World damage mesh/data/collider/streaming | 31 / 0 |
| LocalSession | 166 / 0 |
| Actual controller/source parity | 189 / 0 |
| Actual HUD/UI | 284 / 0 |
| Authority/codec/sockets/Main damage | 32 / 0 |
| Actual lab scene | 119 / 0 |
| Mobile controls | 2381 / 0 |
| Actual touch look/settings | 144 / 0 |
| Network controller | 511 / 0 |
| Existing shared player rules | 144 / 0 |
| Native damage GPU | 5 / 0 |
| Native scoreboard GPU | 23 / 0 |

GPU commands omit `--headless`, add `--rendering-method gl_compatibility`, and run
`tests/world/render_block_damage.gd` or `tests/ui/render_scoreboard_colors.gd`
with `-- --output=<absolute cache path>`. Damage changed10,568 rendered pixels;
healthy versus recovered had zero pixel difference. Scoreboard pixel goldens are
independent source RGB calculations for black, green and yellow, including
local/alive/dead rows, preferences and canonical owner35.
Images: `.cache/previews/{block-damage,scoreboard-colors}`.

Failed fixture attempts remain saved: noncanonical direct-helper event ID and
frozen Dictionary mutation; immediate lab assertion before controller's next
post-pin step; and a manual network controller that did not retry retained team
intent after a pending-class ACK/stream wait. Corrected tests preserve source
timing, codec, input clock and admission rules; no production workaround was made.

## Frozen export and browser acceptance

Frozen validation is a recorded chain: full0898d6c successful prefix through
mobile-controls, then import/mobile-look144/0/block-damage31/0 on dcee15f0b7bc;
socket damage32/0 with the test-only07b3a1b audio-drain follow-up; shaped latency
459/0 (7.36s), runtime/server-launcher smoke and Web export on dcee15f.
The new archive's `game/` is byte-identical to0898d6c; only the test-only browser
probe and mobile fixture cleanup changed. The entire suite did not rerun on dcee15f.
Manifests/logs: `.cache/release-{0898d6c4bf37,dcee15f0b7bc}`.

Initial fixed-FPS mobile and socket-damage fixtures passed144/0 and32/0 but left
Vorbis playback resources at exit (two and four respectively). Verbose mobile
diagnostics identify Limbo/Select. Like existing lab/UI fixtures, cleanup now waits
200ms wall time rather than virtual fixed-FPS time. Clean repeats passed; no
production audio change or ignored diagnostic. The initial mobile failure and
verbose diagnostic are retained in `.cache/logs/mobile-look-frozen-*` and frozen logs.

Commands for a fresh full validation and the separate probe; the recorded release
used the exact unchanged prefix/suffix validation chain described above:

```powershell
python tools/release_checkpoint.py --revision 07b3a1b
python tools/browser_fidelity_probe.py --release .cache/release-dcee15f0b7bc
```

The second command creates a separate test-only Web export of genuine Main,
Controller and HUD, with buttons for timed block recovery, held-grenade input and
live scoreboard colors. It isolates preferences and removes mouse primary binding
so fixture-button clicks cannot fire an extra shot. The normal Pages export keeps
its regular entry scene/controls; no probe scene is inside the production project.

Actual IAB Chromium/WebKitWebGL WebGL2 Compatibility, single-threaded Emscripten4.0.20:
eight checks passed, zero failed. Visible source shot changed the surviving pillar
cell to dark brown; unchanged RGBff8041 returned orange after10.342s between the
two logged checks. Actual controller hold crossed automatic throw; continued hold
kept stock2/cook false, new press cooked, and manual release kept0.5s delay. Live
scoreboard ON rendered #07 green/#03 yellow/#00 dark gray; OFF rendered all IDs
white while local/dead name tint remained. Log/screenshots:
`.cache/previews/fidelity-browser/{probe-logs.json,block-healthy.png,block-damaged.png,
block-recovered.png,grenade.png,scoreboard-on.png,scoreboard-off.png}`.
The probe preference directory is isolated. Its initial automatic pointer capture
reported IAB WrongDocumentError; no GDScript error/failed check occurred.

Regular local production export was entered from the menu with Shotgun6/48,
preserved mobile UI, visible target kill and drag-look. Public Pages loaded
genuine Title.vxl, terrain/minimap/rifle/HUD, and drag-look after the same IAB
pointer-lock error. This is scene/input evidence, not audible audio, physical-phone
feel, sustained performance or the full browser gesture/export acceptance gate.

Published at https://gordey328.github.io/Blockfield/ on2026-10-11 local:
source dcee15f0b7bc, bundle `812b31680bd84c06be42ccfed64e9551bc77ceaa`.
Public clean metadata matches; HTML5568bytes SHA256
`b8596db84d25586e1631acc9eb4157f3787e449d4d6efa4e4c855c3e29e53f78`
and PCK16,170,288bytes SHA256
`4ad38a3f478501eff4b166c5c8410e31fc8abb3da5813d07a760da0dac4e099f`
equal the local frozen export. Hash report `.cache/previews/public-fidelity-dcee15f0b7bc.json`;
public/local screenshots and logs under `.cache/previews/fidelity-browser/`.
Automation `blockfield` is PAUSED after this verified publication.

## Remaining scope

The three specific omissions are implemented. W07/U05 are IMPLEMENTED pending
full feature acceptance. P15 stays partial/NOT_STARTED: the separately discovered
shared raw-button gate during manual cooldown/tool raising remains open in
[acceptance gaps](acceptance-gaps.md#authorized-fidelity-repair-2026-10-10).
Network/simulation files are byte-identical to the compatible published57 server;
no server/protocol release is needed here. Phone feel, public WSS deployment,
original-map/effects/performance and other full-port acceptance work remain open.
