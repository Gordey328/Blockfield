# Project status

Updated: 2026-10-12 (Europe/Moscow). This page is the authoritative current entry point.
Earlier evidence and failed attempts are preserved in [2026-10-10 history](history/2026-10-10.md).

## Approved optimization integration into dev — 2026-10-12

The user accepts the optimization and explicitly authorizes merging everything into
`dev`. After `git fetch origin --prune`, remote/local dev is absent and origin/main
is `d5516eb2bfd22bd5d03f32ac751dce7c01086876`, an ancestor of the optimization branch.
Root creates dev from origin/main, fast-forwards it to approved optimization head
`3412b5153a109448006d20df9a0fbdaf7dfeb69c` and pushes origin/dev, then adds this
documentation handoff. Remote SHA verification confirms the push. No conflicts.
The game/tests/tools trees exactly match checked runtime274b360; the existing106
gate, smokes/export and browser evidence remain valid without another engine run.
Root owns integration; world specialist independently verifies runtime tree identity.
Unrelated optimization-plan/Steam edits remain uncommitted and untouched.
The separate optimized Pages build remains checked source274b360/bundle6194640;
the Pages workflow listens to main, so pushing dev does not publish a different
build. Physical-phone30fps acceptance remains open. Next development starts from dev.

## Web optimization branch — 2026-10-12 (published development build)

Checked runtime `274b3608b39a63919f9b1f86470a6f62badff034` is committed/pushed on
`codex/web-max-optimization` and published separately at
https://gordey328.github.io/Blockfield/optimized/ as bundle
`619464014b87325a36af28063dee9a87edf4add8`. Main/reduced Pages metadata is unchanged;
all eight deployed metadata/core/map/license hashes match the frozen export.
Godot4.7.2.stable.official.ed1daf0bf, OpenSpadesdcf449c845d509bbde9d79239b32d201c1389961,
Compatibility/single-thread and the accepted reduced template remain pinned.
Final parser/import, all106 tests (105 Godot fixtures plus latency465/0), both
runtime smokes and normal Web export pass, with no rejected engine diagnostics.
All specialist source handoffs/engine leases are returned; shared integration and
final browser/release evidence belong to root. Exact files/commands/hashes and
retained failed attempts are in [branch evidence](web-max-optimization.md).

The user permits removing corpse physics; original prone static Dead models retain
team tint, source resources,16/6 retention, death camera and teardown, with no
per-render solver. No other graphical reduction or multiplayer removal is applied.
Further CPU changes remove owner readout copies, use typed actor-state copies and
deduplicate terrain invalidation while preserving custom extension behavior.
Same1280×720/DPR1 actual-Main Web comparison: baseline TDM25.93/15.79/7.24fps,
final36.75/38.53/36.40fps, with corresponding5/7/9 bodies and zero solver dispatches;
final Lab56–58fps and Title59.5fps. TDM p95 still exceeds33.33ms in two windows.
The812×375/DPR1 desktop experiment gives31.82–35.87fps and does not establish a
resolution benefit. User target iPhone12 mini/Chrome, sustained30fps, thermal/memory
and physical touch comfort remain unverified; desktop size is not phone hardware.
Fresh normal local Web3×3 starts/fires, shows prone bodies, finishes/restarts and
walks. Actual deployed Mirage loads through the menu, walks/fires, supports mouse
look in the mobile layout, digs floor, places a cube and resets original spawn/view/
terrain; public warning/error list is empty. Captures/profiles retained. Browser
viewport override restored; only the public deliverable tab is retained. Temporary
HTTP helpers are stopped before task completion. Unrelated optimization-plan/Steam
edits remain outside this task. Next action: assess this preview on the actual phone
before claiming physical-device acceptance or selecting another quality tradeoff.

### Implementation and review history

User requests a carefully audited maximum-practical optimization branch; graphical
quality reductions require separate prior approval with an explained benefit.
Branch `codex/web-max-optimization` starts at
`d5516eb2bfd22bd5d03f32ac751dce7c01086876`. Godot remains
`4.7.2.stable.official.ed1daf0bf`, OpenSpades remains
`dcf449c845d509bbde9d79239b32d201c1389961`, Compatibility/single-thread Web.
Root owns Main/post-effects integration, build registration, identical rendered
probes, ADR0027/docs and serial validation/export. `presentation_opt` owns
CharacterView/LabSoldier, hottracking, LabMap/Palette and presentation fixtures;
`gameplay_opt` owns one-shot hit-pose cache, Player/Match adoption and equivalence
fixtures; `world_opt` owns linear collapse traversal and empty-halo stages/fixtures.
Contracts agreed before edits; engine leases serialize isolated checks. Existing
optimization-plan and Steam investigation edits remain outside this task.
Offline code audit shows network clients/polling/prediction are not instantiated
in lab or TDM; TDM uses local shared rules and five bots. Removing multiplayer
does not remove this authority/AI cost. No multiplayer removal or quality change.
Baseline archived at `.cache/maxopt-baseline-d5516eb`; diagnostic baseline import
and reduced-template Web export pass. Two diagnostic preparation mistakes
(LabSoldier path and multiline signature wrapping) are corrected; failed copies
remain retained. Private world/presentation/live-shot/Main/UI/source/AI checks pass,
with paired native component improvements. Actual baseline Web lab/Title retain
about55–58fps but sustained3×3 drops to about7–23fps and Main cost grows to64ms/frame.
Presentation specialist adds exact corpse-query/physics optimization with a preserved
original oracle under agreed exclusive ownership:1590/0, original9046/0, measured
1599/0 and actual TDM62/0 pass;16-body native CPU49–54% lower. No quality/body-count/
collision/substep reduction is authorized or applied. Frozen0a129ec passes all102
test runs (101 Godot plus latency458/0), parser/import, client/server smokes and
normal Web export. Review adds base-Corpse/live-custom-adapter guards: new1635/0,
original9046/0, Main8/0 and TDM62/0 pass. Only corpse runtime changes after0a;
all specialist source handoffs/engine leases returned. Root repeats final affected
archive checks/export, then expanded paired actual-Main Web profiles and a separate
branch preview. Existing main/reduced Pages paths remain separately owned.
Final860 affected gate/export pass. Identical expanded TDM shows remaining corpse
cost even after exact optimization; user specifies iPhone12 mini/Chrome and then
explicitly permits removing corpse physics entirely. [ADR0028](decisions/0028-static-death-models.md)
records the static original Dead-model adaptation. Production Main will no longer
dispatch a solver; existing retention and death/respawn rules remain. Specialists
receive new non-overlapping ownership: presentation only Corpse/static fixture,
gameplay only TDM weapon getter/player-state copy and their fixtures, world only
World dirty/water invalidation and its fixture; root Main/HUD caption/build/docs.
These remaining quality-preserving CPU/invalidation changes need fresh frozen
checks and final scenario-checked Web measurement/publication. Root retains one
mixed-viewport TDM run and a premature Title read as rejected evidence, with no
claims based on them. Ordinary860 mobile layout starts/fires/selects tools at812×375
with no warning/error logs; physical-phone performance is still open.
See [branch evidence](web-max-optimization.md), [ADR0027](decisions/0027-quality-preserving-web-optimization.md).

## Combined Mirage/effects Pages release — 2026-10-11 (published development build)

The user explicitly requests waiting for the concurrent effects chat to finish,
combining its accepted changes with Mirage and publishing the result to Pages.
Root owns bundled-map catalog/export/provenance, actual Main integration fixture,
ADR0026, frozen combined checks, browser verification and serial publication.
The effects task completed its turn and public verification; runtime1b02c64 and
evidence b7d7496 are committed/pushed. Combined integration starts from that source.
Mirage's validated native package is copied unchanged to game/assets/maps; ignored
local maps and raw/Blender source stay excluded. See
[ADR0026](decisions/0026-bundled-map-publication.md). No unrelated Steam/optimization
files are staged. Godot4.7.2.stable.official.ed1daf0bf and OpenSpades
dcf449c845d509bbde9d79239b32d201c1389961 remain pinned.
Frozen4530632b7eb7ff9bca2bd2ca97cb4bcdbefdb385 passes all96 test runs (95 Godot
fixtures plus latency458/0), parser/import, both smokes and reduced normal Web
export. Native format93/0, actual Main25/0, VXLMain15/0; effects20928/0, falling43/0,
fragment43/0, UI284/0, mobile controls10128/0 and TDM62/0 pass. Helper0e39997 accepts
an isolated checked bundle directory and explicit gh-pages tracking ref; main is
pushed. The user steers immediate publication followed by public verification;
the link is supplied during upload and when Pages is built.
Bundleac2fff4caabdb9c881c596c10aeaecc33076344e reports built. All eight public
metadata/core/map/font-notice hashes match; native map hash remains
08b69203a2dde4d276053647312dbcdd5bf20f0730203ee24c4c293934e35d3a.
Real public Web starts, opens Mirage through the menu, walks/fires, digs a floor
cell, builds a cube and resets to original spawn/view/baseline. Final warning/error
list is empty; persisted touch/UI/resources preferences retained. Public tab/
captures retained; temporary combined HTTP helper/tab closed. URL:
https://gordey328.github.io/Blockfield/?v=4530632 . Exact commands, logs and limits:
[combined release evidence](combined-mirage-release.md). Specialist review/handoff
complete; unrelated files remain unstaged. Requested combined publication and
post-publication verification complete; no parity promotion.

## Fixed50 noncolliding effects — 2026-10-11 (published development build)

User authorizes a hard50 decorative particle pool and removal of particle
collisions, with maximum practical performance. Root owns ADR0025, accepted
replacement/contracts/evidence, isolated engine/browser/release integration.
particle_runtime owns only Effects/new slot storage; particle_tests owns the
effects/fragment/browser fixtures; particle_benchmark owns new diagnostic helpers
and FallingVoxelCluster/its fixture after the user's expanded scope.
Contracts agreed before edits: fixed reusable state, one particle update per
rendered frame, no hidden fragment sprite mirroring, real-time age/fade and fresh
combat feedback under saturation. User then also removes casing collisions;
typed16 casing states use2s simple flight. Falling presentation becomes one
group of at most64 cubes for1s with no collisions or impact debris. Authoritative
grenade/collapse/map rules retain their contracts. See
[ADR0025](decisions/0025-fixed-noncolliding-effects.md).
Baseline26ea9883bdef9a7436bece87e36239857651dc8e archived under
.cache/particle50-baseline; Godot4.7.2.stable.official.ed1daf0bf,
upstream dcf449c845d509bbde9d79239b32d201c1389961. Mirage/Steam/optimization
work is separately owned and preserved; root runs frozen/private projects only.
Runtime/test handoffs are integrated and leases returned. Parser/import, effects
20928/0 (three explicit headless skips), fragment43/0 and falling43/0 pass.
Actual Intel UHD Compatibility readbacks pass: effects20931/0, falling45/0;
experimental bulk publication267/0 is slower than retained setters. All13 affected
world/gameplay/presentation/audio/Main suites and runtime/server smoke pass.
Paired public effects CPU is91.0%/96.8% lower across two native runs; equal50
implementation-only results vary, so no stable gain is claimed for that case.
Casings live617.138 to31.877ms with zero terrain queries; falling no longer emits
thousands of secondary particles. Evidence is in
[simple effects performance](simple-effects-performance.md).
Rendered baseline/candidate probes pass4/4 checks per workload; public component
CPU9,083.5 to898.5ms (90.1% lower), with50 peak and full expiry. Actual-Main held
SMG passes7/7, peaks50 particles/16 casings, with no new states/nodes or contacts.
400-cell roof removal displays64 cubes and completes with zero debris/groups;
map cells remain authoritatively removed. GPU/native visual and browser input
checks are recorded in the evidence; initial helper/import/type errors are retained.
Frozen1b02c6451cf6976225c680f1ab77ddfcb9f47aa5 passes parser/import, effects20928/0,
fragment43/0, falling43/0, client/server smokes and reduced-template Web export.
Normal local Web verifies movement, SMG30 to14 rounds, grenade3 to2 and settings
restoration. Source main is pushed; private Pages checkout preserves sibling paths.
Pages bundle6e4c14c21cdf4c297ac85d87cb613461757e232e is built; fresh public metadata,
HTML/JS/WASM/PCK all match the checked source/export. Public URL:
https://gordey328.github.io/Blockfield/. Unrelated Mirage work remains outside this
release. Public startup, forward movement and SMG Fire pass; visible head75 damage
confirms firing with retained mobile controls. All specialist handoffs are complete;
temporary probe tabs/HTTP helper are closed before turn end. Next acceptance:
target-device/whole-game CPU/GPU and broader port parity, with no FPS claim here.

## Local Mirage conversion — 2026-10-11 (verified local conversion)

User supplies C:/Users/Gordey/Downloads/csgo_mirage and requests Blender first,
then Blockfield blocks. Root owns bootstrap_blender.py, Main/HUD/World optional
spawn, export/build registration, native Main integration fixture and ADR0024/docs.
Specialist goldsrc_decoder owns only tools/map_import/goldsrc.py and its Python
fixture; blender_pipeline owns only its scene/voxel/helper tools; native_map_loader
owns only BlockfieldMap and its Godot fixture. Contracts agreed before parallel
edits; root owns shared config and serial Godot integration. Baseline remains
26ea9883bdef9a7436bece87e36239857651dc8e, Godot4.7.2.ed1daf0bf, upstream
dcf449c845d509bbde9d79239b32d201c1389961. Portable Blender4.5.14LTS official ZIP
SHA256 b9533d2397ac1984db4466fb23a7a4649391cca93f6e84209f9bcc60d071c8b9 verified.
Actual input is GoldSrc BSP30; hash13ded0fee37ae9e9ccb2c50d798fe7c008503edba3a7f41cbb54ea012386b2b8.
Extractor returns176models/12,242BSPfaces plus all301placed props/64MDLfiles,
281textures/materials and646entities, with no missing model/texture resources.
Binary/real-data Python9/9 pass;15sprites/58decals and animation/lightmap/script
behavior remain explicit omissions. Valve format ref b1b5cf5892918535619b2937bb927e46cb097ba1.
Final saved Blender scene has472meshes,129,796polygons/281packed images. A separate
Blender process reopens it and converts at28units/block to171×61×165 without height
cropping:298,384 solid cells,6,884,460 raw bytes,327,461-byte native package.
All40 original team spawns pass full0.9×2.7 standing clearance/four-corner support;
32,232 safe standing cells found. QA removed technical overlays and unbounded BSP
exterior fill using visible structural envelopes, retaining original room air.
Native package loader95/0 includes the final actual map; Main21/0 and VXLMain15/0
pass. Actual Compatibility GPU6/0 verifies input movement/rifle terrain destruction/
reset and captures both first-person and whole-map renders. Final exported Web8091
loads/walks/fires; spade digs, new blocks are placed, and map reset restores spawn/
view/baseline. Real browser screenshots are retained. Blender/source renders checked.
Shared workspace effects were temporarily incomplete during unrelated parallel
edits; final checks/export use HEAD plus this task's explicit hashed overlay in
.cache/mirage-inspection. All specialist handoffs complete and engine leases returned.
Outputs live outside Git under Downloads/csgo_mirage_converted; final blend SHA256
d3d86443f0ec58c45147dee3cf04a8d7d0cf31e5a5deaa69f92c49a19123e208, map SHA256
08b69203a2dde4d276053647312dbcdd5bf20f0730203ee24c4c293934e35d3a. Default export
excludes local map assets; isolated build/mirage-web is served at127.0.0.1:8091.
Native save chooses another supported feet position if the original spawn floor
is edited; dry-map metadata/water preference restored. Scripts/doors/animations,
all-route connectivity and Mirage bot navigation remain explicit limitations.
No public publication or parity promotion. Commands, logs, artifacts and limits:
[conversion evidence](mirage-conversion.md), [ADR0024](decisions/0024-local-map-conversion.md).
Final sanity:16 frozen/workspace overlay hashes, three map copies/Blender hash,
live HTTP metadata, restored presets, Python compile9 and whitespace checks pass.
Requested conversion and local verification complete. Optional next work: walk
every route, simplify thin decoration and author Mirage navigation/gameplay metadata.

## Blender map conversion research — 2026-10-11

User requests options for downloading Blender scenes and creating Blockfield block
maps from them. Root owns only new [pipeline proposal](blender-map-pipeline.md) and
this insertion. Read-only specialists `blender_voxel_research` and
`blender_map_sources` own no files or engine leases; their evidence is integrated.
Inspected HEAD26ea9883bdef9a7436bece87e36239857651dc8e and existing workspace edits.
Godot remains4.7.2.stable.official.ed1daf0bf; reference OpenSpades remains
dcf449c845d509bbde9d79239b32d201c1389961. Current packed cells support compact
dimensions up to512×64×512; VXL import always retains64MiB cells and reconstructs
hidden interior with earth color. Current TDM navigation has one stand level per
horizontal column. Recommend offline evaluated geometry/color extraction plus
explicit SOLID/SHELL/CARVE/IGNORE labels, compact full-color data/gameplay metadata
and optional VXL compatibility export. This is advisory, not an adopted ADR or
implemented importer. Primary Blender/Godot and asset listings/licenses checked;
no files downloaded and no actual source scene converted. Commands: Get-Content,
rg, git status/rev-parse and primary web research. `git diff --check -- docs/status.md`
passes; new-file `git diff --no-index --check -- NUL docs/blender-map-pipeline.md`
reports no whitespace diagnostics (exit1 for an added file). No engine/import/gameplay/browser/export/publication run or parity
promotion. Existing optimization-plan/status/Steam investigation edits preserved.
Next proposed action: a small authored room/door/stairs/interior-color fixture,
then one cropped source scene and exported-browser movement/destruction checks.

## Runtime cost assessment — 2026-10-11

User asks which part currently demands the most resources. Coordinator reads current
HEAD b6fb8ff41543032d04cbb848d8b10c08aaabfe83 plus ongoing workspace edits,
code and retained measurements; only this status entry is added. The latest paired
Title Web G reports measure mean particle integration929.53ms and fragment
publication375.8ms over roughly8s shooting, versus World self290.07ms; the two
particle functions account for about45% of instrumented shoot script CPU.
This is earlier measured Title gameplay, not a fresh profile of current3x3/mobile
changes or total engine/GPU CPU. TDM's separate native authority mean/max
1.415/42.787ms does not establish the browser bottleneck. Full-map storage is64MiB;
retained snapshot first-write adds another64MiB and13.397–14.786ms in native fixtures.
Evidence: [Title profile](title-impact-performance.md), [TDM](offline-tdm.md),
[memory](optimization-audio-vxl-memory.md). Godot4.7.2.stable.official.ed1daf0bf,
upstream dcf449c845d509bbde9d79239b32d201c1389961 remain pinned.
Commands: Get-Content, rg, git status/rev-parse and ConvertFrom-Json inspection of
`.cache/benchmarks/warm-title-candidate-web-g-a.json` and the paired summary; reports
read successfully. No engine/browser/export/test/publication run or parity change.
Next measurement: a controlled current3x3 whole-frame CPU/GPU profile.

## Mobile UX and aim friction — 2026-10-11 (verified development release)

User requests asymmetric mobile UX and slight enemy aim stickiness. Root owns
TouchAimAssist, Player integration, Main/settings/HUD clearance, build registration,
ADR0023/docs and serial engine/release checks. touch_ui owns MobileControls geometry
and its component tests; hud_checks owns actual-scene aim/readout and browser probe
fixtures. Contracts agreed before edits; both handoffs complete, engine leases
returned. Baseline b6fb8ff41543032d04cbb848d8b10c08aaabfe83, accepted reduced-template
integration0714e489f07939d3f4ca7800c73859bf2fa83f2d retained,
Godot4.7.2.stable.official.ed1daf0bf, upstream
dcf449c845d509bbde9d79239b32d201c1389961. Aim module and persisted toggle implemented;
parser/import, actual Main aim79/0, touch look226/0, source input35/0,
controls8778/0, CombatHUD680/0 and UI284/0 pass. Root integrates mirrored/adaptive
minimap clearance, touch-specific reload copy and compact mobile event feed.
The first aim fixture's inferred WeakRef parse warning was corrected with explicit
typing; no production parse errors. Native Compatibility produces11 actual-scene
captures under .cache/previews/mobile-ux; portrait/landscape, max scale, mirror and
TDM readouts checked. Frozen0f582d74679cd8dc1a60a7777cfabddadc6344ae passes
all94 test runs (93 Godot fixtures plus latency458/0), parser/import, both runtime
smokes and reduced-template Web export. Actual Web fine-touch enemy gain is0.82;
ally, foreground wall and fast8-degree swipe retain full gain. Normal Web inspection
finds two CSS defects: integer canvas rounding hides controls on568×320, and default
captions clip at1280×720. Root fixes the minimum-edge tolerance and CSS-scaled type/
icon margins; touch_ui adds four real CSS/logical-size regression cases. Import and
controls9678/0 pass. Frozen9f15dfe005a5db5627b52723e206c60f17a8d943 passes
affected controls/UI/combat/look/aim and both smokes/export;1280×720 captions fit.
Its outer568×320 browser view reports canvas567×319, exposing a further1px canvas
edge loss; root corrects tolerance to2px and touch_ui adds these exact landscape/
portrait cases. First actual probe finishes39/0 (the planned42 count was incorrect).
Other template, optimization and Steam work is preserved.
Final frozen2561c83b4297ef8611eb8334930d5878237700a8 passes import/parser,
controls10128/0, UI284/0, CombatHUD680/0, touch look225/0, actual Main aim79/0,
both smokes and reduced-template normal Web export. Full94 remain tied to0f;
only affected checks repeat for the final CSS-only changes. Native captures11
and local normal Web1280×720/390×844 plus final568×320 visually checked; compact
controls now remain visible at canvas567×319. Final actual DOM→JS/WASM touch
probe passes39/0 each at844×390,390×844,568×320 (117/0); enemy gain0.82, ally/
wall/fast-swipe full gain, simultaneous move/look/fire, all-item drag, lifecycle,
mirroring/minimap and actual live movement with2 shots each pass. Evidence:
.cache/mobile-ux-browser-evidence.json and .cache/mobile-probe-mobile-ux-2561c83.
Probe inspection reports one MutationObserver TypeError without that identifier
in exported/probe source; all authored checks pass. Normal local warnings/errors
are empty. Templates retain accepted SHA256 a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922.
Commands: bundled Python tools/release_checkpoint.py --revision 0f582d74679c
--import-cache game/.godot; .cache/freeze_mobile_css.py archives finalHEAD and runs
the named affected suites/smokes/export; tools/export_mobile_probe.py --source
.cache/release-2561c83b4297 --name mobile-ux-2561c83 --import-cache game/.godot.
Source main pushed; tools/publish_pages.py publishes bundle
3f8c0517b9f242068fcf42f7ba8bc6b0a97c1734; Pages API reports built.
.cache/verify_mobile_ux_pages.py 2561c83b4297ef8611eb8334930d5878237700a8
confirms frozen metadata and7 core/OFL SHA256s; /reduced sibling metadata is
preserved. Evidence .cache/mobile-ux-pages-verification.json. Actual public normal
game starts, displays new controls/captions, responds to stick movement and fire,
and displays all13 actions at568×320. Captured public warning/error list is empty.
[Published game](https://gordey328.github.io/Blockfield/). Browser viewport reset;
published tab retained for the user, touch preference preserved. No own server
helper was started; specialist leases returned. Original parity remains IMPLEMENTED.
Next: user assessment on their physical phone; browser evidence does not establish
physical-phone comfort or complete-port acceptance.

## Modern combat UI — 2026-10-11 (verified development release)

User requests researched modern combat styling. Root owns LabHUD, new
CombatTheme/CombatReadout, Inter font/provenance/import, build registration,
ADR0022, docs and serial engine/release integration. Specialist touch_ui owns
only MobileControls presentation; all29 nonvisual methods compare unchanged.
Specialist hud_checks owns only new tests/ui/test_combat_hud.gd. Both handoffs
are complete and engine leases returned. Baseline d2c9acbd47ccf51e4b45f68919ce95cc27ba1550;
Godot4.7.2.stable.official.ed1daf0bf, upstream dcf449c845d509bbde9d79239b32d201c1389961.
Adds translucent rounded edge readouts, tabular ammo, slim HP, line icons,
centered TDM score and circular touch actions; [ADR0022](decisions/0022-modern-combat-ui.md).
Existing template/optimization/Steam edits are preserved. Frozen source
2f1e1147099e102c792b629df82033e5c44df774 passes all93 test runs (92 Godot
fixtures plus latency462/0), import/parser, both smokes and normal Web export. UI284/0,
controls3099/0, look225/0, combat readout166/0, lab119/0 and TDM62/0 pass.
Initial fixture WeakRef parse error and live saved-HDR lab119/1 are retained;
the latter passes in the checkpoint's private test settings without changing
gameplay. Native Compatibility helper produces7 desktop/mobile/TDM captures
under .cache/previews/combat-ui. Local normal exported browser checks rifle
10→8, reload18%→10/48, block palette/50 stock, movement, portrait390×844
Fire10→9/reload10%, landscape844×390 and TDM3:6 at4:31. Score clears toolbar/
minimap in portrait; settings return to Auto and viewport reset. Local IAB
records two known pointer-lock WrongDocumentErrors; fallback remains available.
Command with bundled Python: `tools/release_checkpoint.py --revision 2f1e1147099e102c792b629df82033e5c44df774 --import-cache game/.godot`.
Publication: source main pushed, Pages bundleed057d408453cda87c588787eb3a0f6f7b773ffa
reports built; .cache/verify_combat_pages.py compares metadata/core artifacts/
Inter notice to the frozen export: all7 SHA256s match. Public normal UI starts
and displays the new touch/HUD treatment; captured warning/error list is empty.
[Published game](https://gordey328.github.io/Blockfield/).
Own specialist leases are returned and no own server helper was started.
Original parity rows remain IMPLEMENTED; physical-device feel/full-port
acceptance remain separate. Next: user assessment of the new combat style.

## Reduced Web engine template — 2026-10-11 (verified isolated export)

User requested a reduced Godot Web build, working-game verification and sizes.
Complete:20 retained modules versus46 eligible;26 removals. Exact engine
4.7.2.stable ed1daf0bf001b61586d9930840f2f1394092c079, Emscripten4.0.11,
SCons4.9.1, Node24.19.0; -Os/thinLTO, jobs2/link2, single-thread/no extensions.
Build passed in1:02:27. Profile17ac32fffba5b52fe9becd7c9e4313d79c3d53d6cd9e0c9d894a9aebcf5726c1.
Both exports use frozen3d1199cb0251f1cfe9c13cbd66a553264a34c1e5, with identical
PCK71ef67d7b0681fdde5f5571b279bd9efeceff37d513c3f443b875649e31e6265.
WASM39514754→31835587bytes (−19.434%); gzip10054758→8043492 (−20.003%).
Complete Web folder63855150→56144228bytes; gzip sum25828498→23811261.
Parser/import/exports pass; identical source's92 native suites pass, probe47/0,
stock/reduced real browser54/0 each. After compile, unchanged network-session
repeat passes505/0; earlier failed attempts remain in the logs. Normal reduced
Web manually passes Russian settings, original VXL, movement, tools1–4, map,
drag-look fallback and TDM combat (3:5 at25s). IAB pointer capture rejection also
affects stock; fallback works. Fonts/audio/game resources remain intact.
Deliverables: build/web-reduced-3d1199/, build/blockfield-web-reduced-3d1199.zip,
build/templates/godot-4.7.2-web-blockfield.{zip,json}, build/web-template-report.json.
Copied/ZIP-extracted files match all measured SHA256s. Local preview8087 is left
running with the normal TDM paused for user inspection; helper session71290.
Owned files: tools/build_web_template.py, tools/web_template/{blockfield.py,module-audit.json},
tests/browser/template_probe.gd, tools/export_template_probe.py,
tools/compare_web_builds.py, docs/web-template-size.md, ADR0021 and this section.
Specialist leases returned; root owns completed integration. Reproducible commands,
pins, counts, failed attempts and limits: [size evidence](web-template-size.md),
[ADR0021](decisions/0021-reduced-web-template.md). Source/output/evidence are
isolated under .cache/web-template-verification and .cache/template-probe-*.
Shared live gameplay/HUD, default presets, stock templates and build/web remain
owned by offline3x3 chat. Original parity promotion is not claimed.
Next release can explicitly select the accepted custom ZIP; repeat browser
acceptance if enabling a removed capability or changing the retained contracts.

User approved default integration. Release exports now select the hash-pinned
reduced ZIP; presets are restored and metadata records its hash. Frozen main integration verified and published. New helper: tools/web_release_template.py.
Sibling https://gordey328.github.io/Blockfield/reduced/ was published as bundle
c1a5d66e0793a0944cca725eed8398e1772bfbc3 (built). Public metadata/WASM/PCK
hashes match; normal Russian menu/TDM/keyboard movement work and public
warning/error list is empty. Evidence: build/reduced-public-verification.json
and build/reduced-public-browser.jpg. Publisher: tools/publish_pages_variant.py.

Main integration source20889b25bbd035639c88bc4b6cc63d2b57d8e90b passed all93
test runs, import/parser, runtime/server smokes and reduced export. Modern UI,
movement, tools and finite TDM shots pass locally; public TDM movement and
rifle10-to8 pass with no captured warnings/errors. Pages bundle
88bae197fcfed3aed1c33d7dcb1e1f2d21c1c6cf built at
https://gordey328.github.io/Blockfield/. Public WASM/PCK hashes match the frozen
export; sibling retained (build/integrated-public-verification.json). Screenshot:
build/integrated-public-browser.jpg. Preset restoration checked byte-for-byte.
Command: bundled Python tools/release_checkpoint.py --revision 20889b25bbd035639c88bc4b6cc63d2b57d8e90b --import-cache game/.godot; tools/publish_pages.py.
Python compilation and diff checks pass. Unfinished mobile UX and other chats
remain owned by their coordinators; their next release inherits reduced export.

## Offline 3×3 team combat — 2026-10-11 (verified Crossroads addition)

User authorized an offline match: one human, two allied bots and three opponents,
with movement, shooting, cover and flanking. Coordinator owns Main/controller/HUD,
the offline scene, build registration, ADR0020, documentation and release integration.
Specialist `bot_research` owns only new game/ai and tests/ai; `mode_research` owns
only OfflineTDMSession and its session fixture; `tdm_validation` owns only new
actual-scene/browser fixtures and the diagnostic export helper. Contracts were
agreed before edits; one serial Godot lease is used. Baseline HEAD fe843a1fa369670dea92ea15643639543e61d44b;
Godot 4.7.2.stable.official.ed1daf0bf; upstream dcf449c845d509bbde9d79239b32d201c1389961.
The adapter runs all six actors through existing shared rules; no transport/wire
mode changes. Crossroads, finite ammo/supply, 25-kill/five-minute finish and frozen
menu clock are specified in [ADR0020](decisions/0020-offline-team-bots.md).
Command: bundled Python `-c "import sys; sys.path.insert(0,'tools'); import build;
build.run('tdm-import',['--editor','--import','--quit'])"`: parser/import passed.
All specialist engine leases are returned. AI4440/0, session81/0 and final
actual-scene62/0 pass. The first WeakRef fixture parse failure and real spawn-floor
boundary climb are retained in the logs; the latter is corrected with a 0.01-unit
epsilon preserving support/overlap checks. Final scene at1222ticks has all five
bots moving and attempting fire, 10cover/10flank decisions and score3:4.
Commands/results and limits are retained in [offline TDM evidence](offline-tdm.md).
Coordinator owns the serial engine/release lease. Frozen3d1199cb0251 passed all92
registered fixtures, import/smokes and export. Its actual exported diagnostic scene
passed5/0 movement/fire/roster/pause/resume checks; all five bots moved and attempted
fire, and the visible overlay reached72 bot shots,17 cover/17 flank decisions.
Normal Web completed a13:25 round and returned to the lab. Initial mobile score
overlap is corrected; authority mirroring occurs once per tick and pose/view work
once per rendered frame. Camera now precedes frame effects; the TDM brand survives
locale changes. Final source a1a177c6bdc0a08607cb133e9bcc811789d9d1dc.
First f888 freeze exposed a stale SilentAudio fixture override, repaired in3d1199c;
52bbc1d stopped on an existing HDR assertion dependent on saved preferences.
Failed archives/logs are retained. Frozen checkpoints now use private fixture
settings and restore exact original project bytes before export. Full3a865e425903
passes all92 fixtures, import, both smokes and export; mobile controls3099/0 and
look225/0. Final source differs only by camera ordering/HUD caption; final parser,
scene62/0, UI284/0, runtime and export pass. The unchanged final actual-scene Web
probe passes5/0; all five bots move111–181units/attempt fire at tick2310, with55
confirmed bot shots,14cover/14flank decisions and score5:8. Generic Chromium
UnknownError messages persist in the separate probe; normal local/public captured
error/warning lists are empty. Normal final Web physical W/mouse fire and mobile
Fire are exercised, with390×844 two-row toolbar/score checked and preferences/
viewport restored. Public normal UI starts, shows natural death/respawn and5:11,
then resets to0:0/5:00 Ready. Public Fire ammo change is not claimed across respawn.
Published clean source a1a177c6bdc0a08607cb133e9bcc811789d9d1dc, bundle
114f58611fb8c0d9775180c7034264b6b63c8e96, [Pages](https://gordey328.github.io/Blockfield/).
Pages reports built; public build-info and SHA256 of all six core artifacts match
the frozen export (`.cache/tdm-pages-verification.json`). Commands/results/screens
and remaining arena/navigation/frame-pacing limits are in [offline TDM](offline-tdm.md).
Normal in-app combat snapshots show3–13FPS on a concurrently loaded host; stable
Web FPS/physical-phone acceptance remains open. Only added A01 is VERIFIED for
this authored arena; no original parity row is promoted. All specialists finished;
engine leases returned. Existing optimization-plan/Steam/template edits are
preserved. Next: assess bot difficulty and Web frame pacing in a controlled run.

## Game modes and bot design research — 2026-10-11

User requests researched game-design recommendations and sources for enjoyable bots.
Coordinator owns only new [modes and bots research](game-modes-and-bots.md) and this
status insertion. Read-only specialists `mode_research` and `bot_research` return
primary mode/code/license evidence with no file ownership or engine lease.
Recommended additions: TDM, sequential Frontline, authored cooperative Fort Defense,
then Babel; existing CTF/TC are IMPLEMENTED, not newly proposed original features.
ABBS v55 pinned 332a5b7f947e80e514469ca31cc0a6f1e38536c5 is a behavior reference:
its license exception and custom damage shortcuts preclude assuming direct reuse.
Quake III team/combat sources, Luanti voxel paths and Valve's L4D AI talk supply
separate design references. Proposed shared-command authority, bounded voxel
navigation and initial bot counts are advisory, not an adopted ADR or benchmark.
Inspected HEAD 4a522ceca4edb7b007397331403915a24e689bc6; pinned Godot remains
4.7.2.stable.official.ed1daf0bf and upstream dcf449c845d509bbde9d79239b32d201c1389961.
Commands: Get-Content on status/iterations/parity/architecture/match contracts and
LocalSession/PlayerRules; rg; git status --short/rev-parse; primary web research;
documentation git diff --check (existing status and new research: passed).
Existing gameplay/mobile/audio/research changes
are preserved. No engine/import/gameplay/browser/export/publication run and no
parity promotion. Specialists are complete. Next proposed action: one prepared
compact map and a shared-authority bot combat slice, followed by 3x3 TDM playtests.

## Grenade distance feedback — 2026-10-11

User reports almost constant shake/loudness after a distant throw. Root owns
Effects/Audio and new shared GrenadeFeedback range, related fixtures, ADR0019,
evidence and release integration. Two read-only camera/audio specialists returned
their audits without edits/engine leases. No unit/listener defect: native slow
camera peaks saturate through35 units, main blast sound through150/240. User-selected
shorter presentation envelope now also bounds grenade-triggered collapse kicks;
damage/map scale/particle sizes stay intact. All-tool Fire/look, optimization
advisory and Steam AoS research remain separately owned. Frozen d8e5ddb09d0f
passes import/parser, ten affected native fixtures, runtime and normal Web export:
effects32601/0 (3 explicit headless GPU skips), audio158/0, mixer43/0,
environment76/0, camera45/0, fragment44/0, actual Main119/0, grenade17/0,
controls3099/0 and mobile-look226/0. Exact native captures/failures/limits are
retained in the evidence. Actual-Main Web5/32/80 clicks each capture144000 finite
48k stereo frames/zero overflow with five layers/58 particles; amplitude32/5
is.142805 and80/5 .023605, with much smaller camera accumulators. Initial DOM
click's suspended audio is retained as a failed negative case; canvas-activated
repeat passes. Local normal grenade throw/crater and public Fire-drag camera turn
plus300ms Fire are exercised. Local host pointer-lock errors remain; public
console captures no warnings/errors. No physical-device/listening/full-port claim.
[Contract](decisions/0019-grenade-feedback-range.md),
[evidence](grenade-feedback.md). Frozen d8e5ddb09d0ff63917d3312a758a2f9f4c584430
includes both all-tool Fire/look commits4833050/6d61ea9 and the grenade repair;
its publication supersedes the older6d-only export. Pages bundle2f786bedd3e1c33c41010f382b05b7b37e476ff0
is built/no error; public metadata and all six files match. Main is pushed and
the normal build/web checkout fast-forwards to the same bundle. Avoid replacing
it with an older client build. Two read-only specialists and all engine/release
leases are returned; owned HTTP helpers are stopped before turn end. Next:
user/device feel acceptance; broader parity, performance and listening remain open.

## Web build file-size inventory — 2026-10-11

User requests the twenty largest files. Coordinator reads current local
`build/web`, source `4a522ceca4edb7b007397331403915a24e689bc6`, Godot
`4.7.2.stable.official.ed1daf0bf`, upstream unchanged. The PCK v4 directory has
1258 entries; every payload MD5 and the complete directory boundary check pass.
Ranking combines export files and individual PCK payloads, excluding `.git`
and counting the PCK contents instead of the outer container. Source names are
resolved from exported `.import` descriptors; sizes are exported payload bytes.
WASM39514754bytes, Unifont5343042bytes, Title2106956bytes; PCK23750832bytes.
Reproduce: `& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .cache/build_file_sizes.py`.
Report `.cache/build-size-ranking.json`; helper is ignored under `.cache`.
Follow-up font/audio size advisory: original bitmap Unifont has57085 glyphs
and one4096x4096 atlas; import already enables lossless compression. The49
curated PCM sounds deliberately avoid per-play Vorbis startup cost, as recorded
in Title performance evidence. Read-only gzip9 experiment on their WAV sources:
7444618→3720772bytes, all49 exact decompress round trips pass. Existing matching
Ogg derivatives total731895bytes but are lossy derivatives, not PCM-identical.
This measures source-file storage size only, not an implemented export or new
browser/CPU result. Proposed compact lossless storage with loading-time expansion
can retain gameplay PCM; QOA remains an alternative requiring listening/CPU checks.
Reproduce: `& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .cache/font_audio_size_audit.py`.
Report `.cache/font-audio-size-audit.json`; no font/audio import settings change.
Further read-only index breakdown on the independently refreshed local export
`d8e5ddb09d0ff63917d3312a758a2f9f4c584430` (no export run by this audit):
WASM39514754bytes is byte-identical
to installed official `web_nothreads_release.zip!/godot.wasm`. Code section
34491944bytes, data4718879bytes, other sections/header303931bytes; no custom
debug/name sections occur. PCK groups including import/remap metadata: PCM7469042,
fonts5376794, images2972614, Ogg2877323, Title2106956, locales964091,
models614590, other1239583bytes; container overhead130923bytes. PCK23751916bytes,
game GDC scripts total817195bytes. No per-engine-subsystem sizes are inferred from
stripped sections. Reproduce:
`& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .cache/index_size_breakdown.py`.
Report `.cache/index-size-breakdown.json`; no compression/build change is applied.
Standard-template necessity follow-up: user recalls another5MB Godot export but
does not remember whether this is raw or downloaded size. Read-only source audit
finds actual3D physics, UI including RichTextLabel/ItemList/ColorPicker/FileDialog,
WebSocket, ZIPReader, runtime GLTFDocument, RegEx and JavaScriptBridge dependencies.
No current2D-physics/CSG/GridMap/video/ENet/WebRTC/UPnP usage is found; these are
custom-template candidates, not an accepted disable list. Original translations
include Japanese/Korean/Chinese, and dynamic ZIP/skins remain within accepted scope.
Pinned Web source already disables Vulkan and raycast module, optimizes for size
and enables LTO; no new savings are claimed for those existing settings.
Current WASM39514754bytes compresses to10054758bytes at gzip9, exact round trip
passes. Public HEAD with Accept-Encoding gzip/br returns Content-Encoding gzip,
Content-Length10248949, HTTP200: disk size is distinct from compressed delivery.
Reproduce: `& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .cache/wasm_template_audit.py`.
Report `.cache/wasm-template-audit.json`; original one-shot reports are
`.cache/wasm-compression-size.json` and `.cache/wasm-public-head.json`.
No custom template compile, runtime/browser acceptance or5MB target claim.
Only this status entry and ignored audit files change; no engine lease,
gameplay/import/browser/export/publication run or parity promotion. Existing
optimization advisory, startup release and Steam research work remain separately owned.

## Further optimization advisory — 2026-10-11

User asks for more optimization ideas. Read-only coordinator audit at HEAD
`4a522ceca4edb7b007397331403915a24e689bc6`, with two specialists owning no files
and no engine lease, checks remaining client repetition, collapse/streaming and
snapshot memory against the completed warmed Title/PCM work. Candidate ordering
and evidence limits are recorded in [optimization plan](optimization-plan.md):
one built-in pose application, disabled-flare work gate, shot-scoped hit volumes,
packed collapse traversal, paged snapshot COW, bounded streaming retention,
GPU-dependent 3D scaling and custom Web template delivery. Only snapshot first-write
cost is already measured in the cited prior native fixture; proposed savings have
no new benchmark. Pinned Godot `4.7.2.stable.official.ed1daf0bf` and upstream
`dcf449c845d509bbde9d79239b32d201c1389961` are unchanged. This turn edits only
docs/optimization-plan.md and this entry; startup download/release and Steam AoS
research work are preserved. Commands: Get-Content, rg, git status/rev-parse,
primary Godot documentation browsing and documentation git diff --check.
No engine/import/gameplay/browser/export/publication run or parity promotion.
Specialists return read-only handoffs; no leases remain. Next suggested work:
measure and remove redundant pose/disabled-effect/shot geometry work, then choose
collapse or COW changes by scenario-specific evidence.

## All-item held primary camera look — 2026-10-11

User requests camera turning with held Fire for every weapon. All three firearms
already share this gesture; root removes only MobileControls' firearm-only gate,
extending it to spade/block/grenade. Root owns `game/ui/mobile_controls.gd`, the
mobile component/Main/browser fixtures, mobile docs, ADR0018 and this status block.
No subagents or shared engine/build lease is used. Validation/export
uses an isolated frozen copy under `.cache/all-tool-look-*`; existing grenade
effects/audio work, optimization notes and AoS research remain separately owned.
Frozen source6d61ea9cc26037e3c26553fdfed677dde3cfdc45, Godot4.7.2.stable.official.ed1daf0bf,
upstream unchanged: import/parser, MobileControls3099/0, actual Main look225/0,
UI284/0, source-input35/0, source-parity194/0, network-controller511/0,
camera-target-rays11/0, grenade17/0, runtime and normal export pass in isolated
userdata. Baseline overlay3099/3 reproduces the three excluded
tools; initial Main225/1 was a fixture's silent direct selection, repaired by
normal selection callbacks. Failed logs are retained. Actual-Main exported DOM
touch27/0 at844x390 and27/0 at390x844 verifies all six held-primary yaw/pitch/UP
paths, lifecycle/mirroring and actual movement/shots. Normal local rifle/spade/
block/grenade fire drag and grenade throw pass; both captured browser warning/error
lists are empty. Physical phone and full parity remain open. [Evidence/commands](mobile-controls.md#all-item-primary-look--2026-10-11).
Own helper publication was stopped during Git history fetch; no own Pages write
occurred. The integrated d8e5ddb grenade release owns publication and contains
byte-identical checked MobileControls. Logs/manifest and ignored diagnostic scripts
are under `.cache/all-tool-look-*`; portrait JSON/JPEG and ordinary local JPEG are
saved under `.cache/previews/all-tool-look-*`. No parity rows promoted.
Integrated public source d8e5ddb09d0ff63917d3312a758a2f9f4c584430,
bundle2f786bedd3e1c33c41010f382b05b7b37e476ff0, Pages built/no error. Independent
metadata/all six file hashes match that frozen export, and public MobileControls
matches checked6d exactly. Ordinary public spade/block/grenade Fire drags turn
yaw/pitch; captured browser warning/error list is empty. Public JSON/JPEG are saved.
Input-owned files are complete and all own engine/file leases are returned; own
HTTP helper and temporary browser tabs are stopped. Changed files: MobileControls,
three mobile fixtures, ADR0008/0018, mobile controls/parity docs and this status
block. No remaining input task action; physical-device feel remains an acceptance
limit. Other grenade/performance/research ownership remains separate.

## Startup download megabytes — 2026-10-11

User asks to show downloaded MB on the startup screen. Root owns only the new
`game/web/loading.html`, Web preset selection and documentation/release integration;
no specialist or gameplay/engine lease is outstanding. The shell derives from
Godot4.7.2's installed `godot.html`; original startup/feature/error paths are kept.
Existing Engine.onProgress supplies actual engine/pack bytes, exported fileSizes
supplies the full denominator, decimal MB with one decimal appears beneath the
bar, then a separate startup caption remains until the overlay is removed.
Parser/import and normal Web export pass. A real throttled browser download
visibly shows1.2/63.3MB, then removes the overlay and enters the offline rendered
lab. Only the existing host pointer-lock UnknownError occurs during lab entry;
visible drag fallback works. No gameplay code changes; the prior89 native checks
are not presented as a new run. Frozen clean4a522ceca4edb7b007397331403915a24e689bc6
passes parser/import, runtime smoke and normal Web export; engine/upstream unchanged.
Production diff since19c4d51 is only the new HTML shell and Web preset selection.
Pages bundle56bbc6f09724a5e51b3d732b5a9a08df16c4141e reports built/no error.
Public metadata and all six downloaded export files match the frozen export;
public reload shows12.3→53.7/63.3MB, then removes the overlay and enters the
rendered offline lab. Public console has only startup messages, no warnings/errors.
Local/public logs, screenshots and reproducible commands:
[contract/evidence](decisions/0017-web-download-progress.md).
Both owned loading-test HTTP helpers are stopped; all leases are returned.
Next: no MB-display implementation work remains; broader port/performance
acceptance remains as recorded below.
Separate Steam AoS research files/status insertion remain untouched.

## Published warmed Title / aggregate CPU optimization — 2026-10-11

User requests continuing the impact work: remove remaining Title shooting stalls
and reduce aggregate CPU. Baseline0d69907d05922316185333594e7a5ead29820c9b
has the published b3e game bytes, archived under `.cache/title-impact-baseline`.
Root owns integration/Main/UI audit, docs/config/release and serial engine lease.
`impact_world` owns only Chunk/World; approved bounded-unit batching with buffer
ownership retained across callback, each original unit deadline still checked.
`impact_rules` owns only Effects and effect regression fixture; approved exact
identity/final-fade/direct concrete Data query optimization, unchanged counts
and physics. `impact_tests` owns new native/warmed actual-Main diagnostics plus
isolated profile export helper; previous probe stays intact. Idle/shoot/tail,
settled visual/minimap preparation and inclusive/exclusive CPU will be recorded.
Existing Steam AoS research remains separately owned and untouched. World tests
pass; native completed Title destruction median10.005→7.720ms, mean12.069→9.342ms,
also below the old monolithic baseline. Effects fragment34/0, existing32588/0
and actual Compatibility987/0 pass;400-fragment dense aggregate CPU falls15.0%.
Bulk MultiMesh upload trial is slower and stays diagnostic-only. HUD skips hidden
world/render statistics scans; wet audio copies skip exact-equal pitch/transform.
Clean native actual-Main f pair:73shots/24removals, identical trajectory/counts,
shoot exclusive CPU3803.4→3546.3ms; World self−24.3%, particle integration−29.7%.
Audio decoder startup remains a hotspot. World produced49 native PCM16 derivatives
from original Opus,7,442,462 PCM bytes, exact48k/channel/EOSframes, finite/overflow0,
reproducible99 hashes. Rules owns Extensions bounded cache/override precedence and
new imported-PCM fixture; both leases returned. Root owns audio wet-change fixture
and89th suite registration. Diagnostics has the serial engine lease for import,
PCM/environment checks and new G paired exports. First f Web baseline had
suspended audio and remains separate from the activated G evidence below.
Exact commands, fixture failures and limits: [Title evidence](title-impact-performance.md).
PCM523/0 and environment76/0 pass; all specialist leases returned. Three paired
gesture-activated actual-Main browser runs remove24 Title cells each, baseline
shots73/73/72 versus73/73/73. Median of shoot p95 values114.1→46.6ms; mean
instrumented script CPU per shot−9.1%, idle CPU/realsecond−20.3%. Candidate tail
audio/World/effects drain; rare63.9ms frames and host pointer-lock limits remain.
First frozen427c64b9 validation stopped on fragment34/1: random-spin basis roundoff
legitimately caused one scale correction despite matching source state. Failed
logs retained; test-only zero-spin setup and separate1.234rad correction cases
pass44/0 ten times. Production game bytes remain identical to the measured G.
Frozen19c4d51c73db4d51775fdafe556c8eb0b1ad6b9a now passes import/parser, all89
native behavioral/latency invocations, runtime/server-launcher smoke and normal
Web export; source_dirty=false, Godot4.7.2.stable.official.ed1daf0bf, same upstream.
Normal local Web SMG/Title terrain destruction, magazine depletion/reload and
F7/Verification fresh statistics are exercised; host pointer-lock errors remain
and visible drag fallback works. Public source19c4d51c73db, Pages bundle
836f49c0a54310024686a8e91af9c63a37e55853 reports built/no error. Independently
downloaded metadata and all six export files match the frozen normal Web export.
Normal public Title/SMG held touch fire, permanent cliff opening,30→0 magazine,
reload30/90 and fresh Verification Title.vxl/324chunks/SMG are exercised; the
public console has only engine startup messages, no warnings/errors. Screenshots
and public hash report are linked in the Title evidence. Main Actions38129657978
never starts the build because of the account billing lock; deploy skipped.
Pages internal deployment38129671799 succeeds; this is not Linux CI acceptance.
All specialist/release engine leases are returned and the five owned HTTP helpers
are stopped. Files changed: World/Chunk, Effects, Audio, Extensions, HUD, curated
PCM assets/converter, fixtures/build/release helpers and the subsystem/ADR docs.
Reproducible frozen command and exact logs/results are in the evidence document.
Next performance acceptance: sustained physical-device Title profiling and rare
remaining peaks; iteration/full-port/listening/Linux deployment acceptance stay open.

## Weapon/block impact optimization — 2026-10-11

Terrain surviving-hit damage/repaint now updates only cell color attributes,
retaining mesh/AO/collider; geometry prepares bounded columns/planes and publishes
the complete current mesh/shape together. Stale jobs cancel on invalidation;
authority/HP/collapse/network remain unchanged. Minimap skips unchanged uploads;
hidden batched fragments mirror final node state once per frame.
Root integrated specialists, scoped files and serial engine runs; all leases
returned. Separate Steam AoS research files/status insertion are preserved.

Frozen `b3e29b38c5733612a19ebc5529dd5c1d02cacea5`, Godot
`4.7.2.stable.official.ed1daf0bf`, upstream unchanged: all88 registered native
behavioral/latency invocations, parser/import, runtime/server-launcher smoke and
normal Web export pass. New impact4441/0 (all256 RGB raw-byte sweep), minimap37/0,
fragment29/0; effects32588/0 with three explicit headless GPU skips. Initial cold
font import failure is retained; unchanged frozen source passes seeded-cache retry.

Native first-hit presentation median9.256→0.026ms lab/7.098→0.030ms Title;
destructive peak slices11.867→4.636ms/10.032→4.049ms. Aggregate destruction CPU
retains14–15% median overhead after hot-loop/scheduler repair. Actual-Main Web
wall repeats73/73/71 shots,14/18/15 removals, p9548.1/55.3/62.1ms versus
51.7/64.3/73.8ms; rare stalls remain. Shallow Title p9583.7ms versus60.3ms,
including visual preparation, does not establish overall Title/FPS improvement.
Normal local/public SMG terrain hits and local Title reload/render exercised.
Pointer-lock host errors and workload/device limits are explicit in
[evidence](block-impact-performance.md), with exact commands, logs and hashes.
Full-port and sustained physical-device performance acceptance remain open.
Main Actions build38123984500 never started: account billing lock; deploy skipped.
Legacy branch Pages4827fa is successfully built/hash-verified. Linux CI acceptance
is not implied by the local88-check release.

## Recover context

1. Read [AGENTS.md](../AGENTS.md), this page and [accepted iterations](iterations.md).
2. Open affected rows of the [68-row parity ledger](parity.md) and [acceptance gaps](acceptance-gaps.md).
3. Read the relevant [architecture](architecture.md), subsystem contract and [decision](decisions/).
4. Select only the relevant workflow from [skills](skills.md); agree file ownership before editing.
5. Consult [history](history/2026-10-10.md) for old measurements/failures, not current assignments.

Chat supplements these documents; it is not the sole record of authorization or completion.

## Objective and authorization

Full OpenSpades v0.1.3 port to Godot: iteration1 offline client/test lab without a server;
iteration2 authoritative multiplayer. A development export is not full-port acceptance.
The user authorized the specialist team, repository creation and GitHub Pages publication.
Do not ask for repeated publication approval. Server hosting/domain remain unselected;
the user's chosen deployment scope is Docker/configuration preparation.

## Pinned environment and identity

- Godot4.7.2 `4.7.2.stable.official.ed1daf0bf`, GDScript, Compatibility, single-threaded Web templates.
- Upstream `dcf449c845d509bbde9d79239b32d201c1389961`; `.cache/openspades` is reference-only.
- [Repository](https://github.com/Gordey328/Blockfield): `main` source, `gh-pages` generated export.
- Published client source: `d8e5ddb09d0ff63917d3312a758a2f9f4c584430`, pushed (grenade distance feedback and all-item held Fire/look; startup MB and warmed Title work retained).
- NexQuake mobile controls are merged into main through PR1, merge0fd90e75e508.
  All completed optimization commits through922f230 remain intact. Subsequent
  documentation does not change the checked game bytes. Client engine/release and
  specialist leases are returned; the separate Steam AoS research files remain pending.

## Frozen validation

- iPhone combat-input repair: frozen2d60434 passed parser/import, controls3090/0,
  actual mobile-look209/0, UI284/0, source-input35/0, network-controller514/0,
  camera-target-rays11/0, runtime smoke and normal Web export. DOM touch IDs
  -1/-2/INT_MIN/INT_MAX/0 now pass15/0 in both orientations, versus baseline15/5.
  MutationObserver diagnostic is recorded separately. Only MobileControls changes
  in game/; all optimization work and pending AoS research are retained. PR2 merged
  asaffaf0a; Pages bundle812ea41 is built and all six public file hashes match.
  Normal public input/Menu/Fire10→8 pass with no captured warnings/errors.
  Physical iPhone acceptance remains pending. [Evidence](nexquake-mobile-camera.md).
- Integrated NexQuake mobile release (2026-10-11): clean frozen1c046655fef2 passed
  all85 registered native behavioral/latency invocations, import/parser, runtime,
  server-launcher smoke and Web export on pinned Godot4.7.2. Actual-Main exported
  touch probe passed15/0 at844x390 and15/0 at390x844, including genuine movement/fire.
  Normal local and public mobile movement, horizontal/vertical look and fire-drag
  were exercised; both normal-game captures had no warnings/errors. Probe-only
  unattributed MutationObserver exception is retained in [evidence](nexquake-mobile-camera.md).
  Public metadata/HTML/JS/WASM/PCK and both audio worklets match local SHA256.
  Physical-phone feel/safe areas/performance remain pending; no parity rows promoted.
- Optimization item4 (2026-10-11): frozen66e4b5b7eb89 passed all85 registered
  native behavioral/latency invocations, import/runtime/Web/server export and PCK
  smoke. Separate Web PCM113/0+DSP64/0 and JS lifecycle3/3 passed. Actual Main
  cancel/restart/save downloads match exact raw/synchronous bytes; normal local
  and public lab/Title rendering/input/progress checked. Independent public
  HTML/JS/WASM/PCK and server ZIP hashes match. Earlier failure/benchmark chain,
  fixture fixes and remaining stalls: [optimization evidence](optimization-audio-vxl-memory.md).
  Current source is stable/pushed; all optimization leases returned. Full-port,
  controlled device FPS/RSS and Linux/Docker/TLS acceptance remain open.
- Permanent block damage (2026-10-11): implemented/published on frozen4c051639e286
  under [ADR0010](decisions/0010-persistent-block-damage.md). Offline/shared HP and
  darkening persist; joining/resumed clients receive flags and bounded loading hits.
  Root integrated specialist files, retained mobile/grenade/scoreboard and committed
  effects16f1e70. All81 registered checks covered on this same frozen source, including
  Controller194/0, Match226/0, MapTransfer1186/0, Runtime223/0, actual socket/Main
  damage42/0, controls2381/0, touch-look144/0 and native latency458/0. Web11/0 and
  normal local rendering/input/tool/map checks passed. Web/server export/PCK smoke
  passed; public metadata/HTML/PCK and server ZIP match local hashes. Initial
  import/controller failures and repeats are retained; this is a recorded validation
  chain, not an uninterrupted first pass. [Detailed evidence](persistent-block-damage.md).
  Specialists are complete with no outstanding file ownership; root release lease
  is returned; public browser and final documentation verification completed. No automatic expiry
  or public hosted server was introduced; full-port acceptance remains open.
- Fidelity repairs: recorded frozen0898d6c successful full prefix through mobile-controls;
  dcee15f import/mobile-look144/0/damage31/0; test-only07b3a1b socket-damage32/0;
  dcee15f shaped latency459/0, runtime/server-launcher smoke and Web export. `game/`
  bytes are identical across this chain. Full suites did not rerun on dcee15f; original
  cleanup diagnostics and manifest are retained. Actual exported WebGL probe8/0 plus
  regular local/public gameplay checks passed. [Detailed evidence](fidelity-repairs.md).
- Mobile FPS: complete79 behavioral/latency checks, parser/import, runtime/server-launcher
  smoke and Web export passed on frozen3c408e818859. Exact subsequent UI-only diffs
  move building feedback, keep captions readable, shorten the grenade caption and
  raise the button floor to56CSSpx. Final frozen31c513d0aa18 repeated import,
  controls2381/0, actual Main/HUD272/0, touch-look/settings144/0, runtime smoke and export.
  This is a validation chain, not a claim that all network/world suites reran on31.
  Logs/manifests: `.cache/release-{3c408e818859,8f04c2240a22,aa6f03e6e23a,31c513d0aa18}`.
  Final31 public metadata/HTML/PCK match the export; exported browser landscape,
  portrait and small-screen checks are described in [mobile controls](mobile-controls.md).

- Previous mobile96 update uses a recorded frozen validation chain:62 successful unchanged prefix
  suites on876 plus affected UI/every remaining registered check on310. Later exact HUD
  placement-only diffs repeated import/UI/runtime/export; mobile808/0 also repeated on0c51.
  Final96 Main/HUD270/0, parser/import/runtime/Web export are clean. This does not mean
  every suite was rerun on96. Manifests/logs: `.cache/release-{876a9828067e,31028524ad3b,0c51c5bae956,96c36cdc740d}`.
- Original scene-epoch fixture failed89/7, reproduced unchanged94/12; repaired real-clock
  pacing/readiness passed170/0 with all37 actual commands ACKed and neutral controls.
  Production clocks, input limits, protocol and simulation were unchanged. Failed attempts
  remain saved. See [history](history/2026-10-10.md) and [mobile evidence](mobile-controls.md).
- Frozen310 shaped latency483/0; scheduler47/0:128 callbacks,339 inputs, lead1..8,
  pending8, wall6.735s. These results do not establish32-client capacity.
- The earlier57 complete suite/Web/Linux/PCK smoke remains the server artifact evidence
  under `.cache/release-57ad43b2b740`; Docker/Linux execution is still unverified.

## Published artifacts

- [Pages development build](https://gordey328.github.io/Blockfield/) serves clean
  source `d8e5ddb09d0ff63917d3312a758a2f9f4c584430`.
  Bundle `2f786bedd3e1c33c41010f382b05b7b37e476ff0`, Pages built/no error. All game changes are pushed to main;
  later evidence/documentation commits do not change checked game bytes.
- Independently downloaded public metadata/HTML/JS/WASM/PCK and both audio worklets
  match the frozen export. PCK23751916bytes SHA256
  `2b9f1d81c4190fce199a805f58eb89ad91cb2b6daaaeba252dd37b45168ea71c`;
  HTML7092bytes SHA256 `99f3debfa2f144aa1e234492f8a9f25eeb86c76b86a4831908d56fd4d141a5a4`.
  Hash report `.cache/grenade-public-verification.json`; current browser/mixer
  evidence is [grenade feedback](grenade-feedback.md). Public grenade selection,
  lab entry, held Fire-drag camera rotation and300ms Fire are exercised, with no
  warnings/errors captured. Earlier actual downloaded/total MB, overlay removal
  and offline entry on4a522ce remain in the loading evidence. The earlier19c4d51
  Title evidence/screenshots remain retained separately: Title load/SMG selection,
  held touch fire, cliff destruction,30→0 magazine/reload30/90 and current
  Verification map/profile exercised. Public startup has no warnings/errors;
  local pointer-lock limits and rare measured peaks remain explicit. Three paired
  warmed actual-Main Web runs establish the recorded improvement, not zero stalls
  everywhere or sustained physical-device FPS acceptance.
- Compatible [server prerelease](https://github.com/Gordey328/Blockfield/releases/tag/godot-66e4b5b7eb89)
  stays unchanged:29,344,396bytes SHA256
  `76935d2fc59be4d5af6387266714001292a9c11a5adbf1c276a4e0a7799e168b`.
  Network5 / authority5-no-block-regen remain byte-identical; client/server source
  commits differ because this release changes client presentation only. Previous
  release evidence remains in subsystem documents and frozen validation above.
- Windows exported-PCK smoke on66e did not execute Linux. No server export/PCK
  smoke was repeated after66e. Prior frozen19c4d51's89 native checks include
  server-launcher/network verification;4a522ce repeats parser/runtime/Web export,
  with no gameplay-code change. Docker, Linux and deployed TLS/WSS remain unverified;
  see [server deployment](server-deployment.md).

## Earlier frozen57 Web evidence

- Exact57 local HTTP export: both receivers ACKed73/73 chunks, rendered blue/green CTF
  with10/50 inventory, and the second displayed the first client's chat. Native input
  rejections/map resyncs/timeouts/backpressure stayed0. Explicit disconnect after more than
  the30s grace correctly rejected resume; a new admission and quick same-actor resume passed.
- Final pre-cleanup totals: admissions3, chat1, closed3, resumes1, stale_inputs0. Screenshot,
  safe trace and summary: `.cache/previews/browser-frozen-57-network.{jpg,log,json}`;
  the expired-resume attempt is separately preserved. Test clients/server were stopped.
- Local offline Shotgun6/48, block tool/palette, drag-look and PNG preview/link were observed.
  PNG automated download timed out; fullscreen DOM did not enter. IAB pointer-lock reported
  Chromium UnknownError with visible drag fallback. One client showed24–27FPS; a hidden
  second showed1FPS, so this proves connection scenarios, not rendering performance.
- Earlier dirty Web diagnostics and native shaped-retirement proof remain separate history.
- Public Pages57 loaded genuine Title.vxl in offline SANDBOX with rendered terrain/minimap,
  weapon and targets. Edited player name and later Russian selection survived page reload;
  the temporary test name was restored. This does not verify all preferences, optional effects
  or saved downloads.

## Acceptance and next work

- Steam Ace of Spades comparison (2026-10-11): user requested research of their
  installed game and specifically Universal Modder. Located Steam app224540,
  build889629, under `C:/Program Files (x86)/Steam/steamapps/common/aceofspades`.
  Installed mod-any-game/game-recon/reverse-engineering from Universal Modder0.2.0,
  pinned550651675153070cce68066e07c3c8f95df86d08. `python -m um scan <install> --json`
  indexed4651 files, unknown native/x86; local static PE/PYZ records establish
  Python2.7/pyglet/native aoslib, not the OpenSpades C++/AngelScript runtime.
  Root owns only `tools/inspect_aos_install.py`, `docs/aos-steam/{MODDING_PLAN,MODLOG}.md`
  and this insertion. Two read-only specialists returned source/resource handoffs
  without file/engine leases; existing mobile/optimization work is retained.
  Bounded resource audit: VXL40 exact EOF, coloredZ79..239,39 maps512² column counts
  and LunarBase250000 (500² is inference); KV6736, dense interior extension382;
  AOS244 with243 stride36 and1 stride32. Actual existing importer accepts354,
  rejects373 count mismatches and9 depth>64. SHA256 matches27 retail KV6 against
  38 reference entries (34 resources+4 weak fallbacks). Classic shotgun declares
  12 pellets; Classic SMG fields differ from0.75. Static fields are not runtime
  measurements. Source pin remainsdcf449c845d509bbde9d79239b32d201c1389961.
  Reproduction: bundled Python `tools/inspect_aos_install.py <install> --resources
  --openspades .cache/openspades --pack .cache/assets/OpenSpadesDevPackage-r33.zip`;
  module diagnostic flags and installer commands in [research log](aos-steam/MODLOG.md).
  Resource run and repeated affected comparison passed; final JSON assertions,
  Python py_compile, local doc links and scoped git diff --check passed. Initial
  installer/JSON/PE/34-versus38 diagnostic issues are recorded. `godot --version`
  reports4.7.2.stable.official.ed1daf0bf only; no game/parser/import/export or original
  Steam gameplay run. No resources were copied into game or published, no parity
  status changed. [Comparison and route](aos-steam/MODDING_PLAN.md) distinguish
  exact heritage from unverified engine naming, map semantics, native physics,
  modern tint/animation and retail wire/services. Next: one-map/model/prefab local
  viewer and controlled real-game traces if expanding this research; Blockfield
  accepted scope remains OpenSpadesv0.1.3. All research specialist leases returned.

- NexQuake mobile integration (2026-10-11): the user requested checking the other
  chat, merging into main and updating Pages while preserving all its changes.
  Chat "Изучить проект и составить план" is idle/completed; optimization item4 is
  published and all its leases are returned. Mobile branch now incorporates all
  main commits through922f230, including browser staging774e506 and corrected
  audio evidence66e4b5b. Implementation4af719a and documentation3e75233 remain in
  history. Only the mobile controller/HUD/UI paths, their fixtures/probe and mobile
  documents differ from that main source; optimization code is preserved exactly.
  Reference: NexQuakef9fd869074f13f3ad6aad55dca95427f8935027e; Godot4.7.2 and
  upstreamdcf449c845d509bbde9d79239b32d201c1389961 are unchanged. Previous isolated
  validation passed4635/0 native and15/0 Web touch assertions in each orientation;
  normal rendered Mobile On/mirrored look/fire/reload settings were checked.
  [Evidence](nexquake-mobile-camera.md), [ADR0014](decisions/0014-nexquake-mobile-camera.md),
  [PR1](https://github.com/Gordey328/Blockfield/pull/1). Main's pending research
  records are incorporated; their original bytes and unrelated untracked
  tools/inspect_aos_install.py snapshot are retained in .cache/nexquake-integration-backup-20261011.
  The live inspection helper continues under its separate research chat ownership.
  Frozen combined1c04665 passed all85 registered native behavioral/latency checks,
  parser/import, runtime/server-launcher smoke and Web export. Actual integrated
  Web probe passed15/0 each at844x390 and390x844, including real movement and shots.
  Normal rendered Mobile On/mirrored look/fire-drag also passed with empty logs.
  Probe-only unattributed MutationObserver exception is retained in the evidence.
  No game bytes changed in subsequent documentation. PR1 is merged in main0fd90e75;
  checked Pages bundle83ce7fa is built, hash-verified and interactively checked.
  Pending AoS status insertion and research files were preserved during the local
  main fast-forward, without committing them as part of this release. Own browser
  tabs and preview servers8877/8878 closed; engine/release leases returned.
  Next: user's physical-phone camera feedback; parity rows are not promoted.

- Optimization item4 completed/published (2026-10-11): user approved audio,
  VXL loading/saving and memory. Frozen66e4b5b7eb89956657f97d7f623856080ea117b5
  passed all85 registered native behavioral/latency checks, import/runtime,
  Web/server export and exported-PCK smoke. New checks: ambience46/0, VXL62/0,
  bounded materials1555/0, actual Main15/0. Native latency461/0, corrected PCM134/0
  +81/0; exported AudioWorklet PCM113/0+DSP64/0; production JS lifecycle3/3.
  Initial failed PCM fixtures are retained and corrected through full audio-frame
  windows and actual27-ray DSP setup; production128/1.5ms budgets unchanged.
  Exact stationary ambience rays5640->47 (moving unchanged); tint caches256 each.
  Coherent private VXL jobs and bounded browser staging cancel stale work and keep
  input callbacks available; raw/canonical downloaded bytes verified exactly.
  Full85 ran on the same frozen source; earlier benchmarks/diagnostics are an
  explicitly described validation chain. Normal local/public lab and Title render,
  movement/tools/shot and progress checks passed; Chromium drag fallback remains.
  Source and Pages/server package pushed; public metadata/HTML/JS/WASM/PCK and
  independently downloaded ZIP match hashes. [Evidence](optimization-audio-vxl-memory.md),
  [ADR0013](decisions/0013-audio-vxl-memory.md). First-write COW13-15ms/64MiB and
  reset/initial allocation stalls remain; controlled FPS/phone/RSS/subjective audio
  and Linux/Docker/TLS acceptance are open. Parity statuses are not promoted.
  All specialists returned leases; root engine/release leases returned, owned
  preview helpers stopped, public game tab retained. Concurrent mobile files and
  records remain untouched by this task. Main source66e4b5b is stable/pushed for
  separate mobile integration. Next optimization: controlled device baseline and
  the remaining measured stages of the plan, rather than unmeasured pooling.

- Mobile addon research (2026-10-11, examples/discussion only): root compared primary
  Godot/GitHub sources with the existing touch contract; two read-only specialists
  reviewed current routing and candidate libraries, with no file/engine leases.
  Native VirtualJoystick/TouchScreenButton and MIT Virtual Joystick DX are the movement
  shortlist; MIT Action Manager is a button-behavior reference. MarcoFazio's class_name
  VirtualJoystick matches the new engine class and needs adaptation. Detailed pros,
  cons, source links and Web limitations are in [candidate research](mobile-controls.md#open-source-control-candidates--2026-10-11).
  Base HEAD556c6dce324f; pinned Godot4.7.2/upstream unchanged. Commands: Get-Content,
  rg and git status/rev-parse plus primary-source browsing; documentation-only
  git diff --check passed. Files changed: docs/mobile-controls.md and docs/status.md.
  No game/test/export edits, addon installation or device verification. Specialists
  returned read-only handoffs; next action is user selection/discussion of examples.
  Camera-specific follow-up: user narrowed the target to rotation settings. Read-only
  controller/HUD inspection confirms existing touch/ADS gain, inversion and fire-look;
  recommend our native-event per-pointer swipe layer for camera rotation. DX remains
  a movement reference. Optional separate X/Y gain/smoothing would need later work.
  Root updated only the two research documents; documentation diff check passed;
  no new engine/test/export run. Unrelated voxel/optimization documents belong to
  concurrent work and were not edited. Next action: discuss desired camera tuning.
  Expanded search follow-up: the user reports current camera control still feels
  poor and requested a concrete refined reference. This supersedes the provisional
  recommendation to retain the existing handler as sufficient. Released Android
  FPS candidates now include Open Touch Gaming / MobileTouchControls (UX/source
  correspondence explicitly limited), Xash3D FWGS (clearest open camera source)
  and idTech4A++; Luanti covers voxel/tools, NexQuake and Ashworth cover runnable Web
  comparisons. Exact inspected revisions, licensing, source links and caveats are in
  [expanded camera research](mobile-controls.md#expanded-camera-reference-search--2026-10-11).
  Two specialists returned read-only handoffs, with no file/engine leases. Root
  inspected primary sources, used public git ls-remote to pin two references, opened
  NexQuake's rendered server menu and launched/rendered Ashworth on desktop; physical
  touch feel and multitouch remain unverified. Temporary tabs closed; no viewport
  override or engine/test/export run. Only the two mobile research documents changed
  under root ownership; unrelated optimization/voxel work is preserved.
  Documentation-only git diff --check passed (exit0); no new gameplay validation.
  Next action:
  compare the chosen released-app reference against Blockfield on a physical phone,
  then select camera response/layout changes from that evidence. No new architecture
  or parity acceptance is claimed.

- Optimization planning (2026-10-11): completed a read-only three-specialist audit
  of World, simulation/network and presentation/audio/UI, plus coordinator
  Main/config/export review. [Optimization plan](optimization-plan.md) prioritizes
  controlled current Web/device baselines, repeated client work, indivisible chunk
  rebuilding, audio/shot work, VXL/memory, collapse/streaming and server history.
  Historical measurements and current code candidates are explicitly distinguished;
  existing effects pools, prepared publication and progressive visual preparation
  are retained. HEAD `556c6dce324f1c33817cb182bb50118113195648` has no `game/`
  diff against published4c051639e286. Read-only `rg`/file/evidence inspection,
  `git -c safe.directory=C:/Users/Gordey/Documents/ChatGPT/Blockfield status --short`,
  `git ... diff --stat 4c051639e286 HEAD -- game` and engine `--version` completed;
  version is `4.7.2.stable.official.ed1daf0bf`. This turn owns only
  `docs/optimization-plan.md`, this planning entry and the obsolete synchronous
  preparation summary in `docs/voxel.md`; concurrent mobile research records
  remain under their existing ownership. Documentation `git diff --check` passed
  (exit0); all9 local plan links resolve. Specialist reviews corrected minimap
  dirty/revision wording, the ambience source path and event-burst mean wording.
  No new import, behavioral tests, benchmarks, browser checks or exports
  are claimed by this planning turn. Specialists supplied read-only analysis and
  returned all leases. Next action: stage1 controlled baseline before selecting
  the first measured optimization; iteration/parity acceptance remains unchanged.

- Previous mobile-control checkpoint96 returned specialist/engine leases to root;
  its evidence is retained below separately from the current31 release.
  New `game/ui/mobile_controls.gd` and `tests/ui/test_mobile_controls.gd` exercise real
  touch ownership and source/network handoff; native component suite808/0 on Godot4.7.2.
  Root owns HUD/controller/settings/scale integration and publication. Landscape844×390
  and portrait390×844 exported-browser views were inspected; initial anchored HUD and
  portrait minimap/palette overlaps are corrected. Final Main/HUD regression270/0 passed,
  including preference/mode lifecycle, action bridges, chat/focus cleanup and desktop
  input restoration. Frozen96 is published/hash-verified. Recorded browser previews
  did not exercise physical-phone multitouch. See [mobile contract](mobile-controls.md).
  Actual public844×390/390×844 preview exercised stick/look/fire/Jump/reload/block
  selection, readable footer and palette/map separation. Mode On survived reload;
  Auto restored desktop presentation. Screenshot/report under
  `.cache/previews/public-mobile-96c36cdc740d.*`, portrait JPEG alongside it.
  Temporary test servers/tabs stopped; viewport override reset. Root owns the
  clean source and finished publication; no specialist or engine lease remains.

- Mobile input research (2026-10-10): the user reports camera jitter during simultaneous
  joystick and look touches. Root inspected current routing, official Godot Web sources
  at ed1daf0bf and public input issues/practices; see [research and proposed checks](mobile-controls.md#research-2026-10-10).
  Finger roles are already isolated, but look consumes engine relative motion; the pinned
  Web source computes that motion using a changed-touch list slot rather than touch ID.
  This is a strong cause candidate, not a reproduced device diagnosis. Device/browser
  details remain pending. The research turn changed no game/test/export/skill files.
  The user has since authorized implementation and broadened the scope to comfortable
  mobile FPS controls; the implementation and new release are recorded below.
  Changed documents: `docs/status.md`, `docs/mobile-controls.md`; documentation-only
  `git diff --check` passed (exit0).

- Mobile FPS release (2026-10-10): root owned player/HUD/settings,
  `test_ui.gd`, build registration, docs and release. `source_audit` owned only
  `game/ui/mobile_controls.gd` and `tests/ui/test_mobile_controls.gd`; `voxel` owned
  only new `tests/integration/test_mobile_look.gd`. `assets` completed a read-only
  input/layout review. Specialists do not run the engine. New pinned skills:
  input-handling/responsive-ui. [ADR0008](decisions/0008-mobile-fps-input.md) records
  immutable per-ID look history, linear touch gain, floating stick, fire-and-look,
  persistent preferences and minimum physical targets. All three specialists
  handed off and closed their leases. Initial code checkpoint
  `3c408e8`: import/parser clean, native controls2381/0, actual Main/HUD touch-look144/0,
  actual HUD271/0 and source input35/0. Commands use `tools.build.run` with the
  corresponding registered scripts; logs `.cache/logs/mobile-fps-{import,controls-final,
  look,ui,source-input}.log`. The first controls2381/1 was float32 canvas-roundtrip
  fixture rounding; diagnostic confirmed0.000061px error and exactly two events.
  The fixture checks event count/independent transform with0.0001px ideal-coordinate
  tolerance. No production change for that issue. Frozen full3c plus final31
  UI follow-up passed; public metadata/HTML/PCK match31, and actual public
  landscape/portrait checks exercised move/look/fire-drag/block selection and
  clean HUD placement. Local568×320 default size confirms56px targets/readable labels.
  Native tests and browser mouse preview do not prove physical-phone feel or touch.
  Next action: device acceptance/tuning after user feedback; no code/server blocker.
  Public On survived reload; public Auto/local touch defaults restored. Temporary
  browser tabs/HTTP helper stopped and viewport override reset; browser report/shots
  `.cache/previews/mobile-fps-31c513d0aa18-browser.json` and accompanying JPEGs.

- Neither iteration is fully accepted; use the ledger's evidence-bound statuses.
- Block damage presentation audit (2026-10-10, user requested discussion only): pinned
  OpenSpades `Sources/Draw/GLMapChunk.cpp:247-252` halves each terrain RGB channel
  whenever block health is below100; `Client/World.cpp:102-115,190-195` restores100HP
  ten seconds after the latest hit. This is a binary darkened state, not progressive
  cracks or a health bar. Current offline `game/gameplay/player_controller.gd:802-812`
  stores partial health separately without updating terrain appearance; network
  `game/main.gd:1079-1084` presents hit particles/audio without persistent darkening.
  W07 therefore has a confirmed presentation gap; the follow-up audit below corrects
  its earlier IMPLEMENTED status. Read-only source searches/line inspection completed;
  no game/test/export changes or engine checks for this audit. Next action: discuss
  source-matching darkening and await the user's implementation instruction.
- Follow-up fidelity audit (2026-10-10, discussion only): root coordinated three
  specialists, read-only ownership split into gameplay feedback, renderer/effects,
  and UI/audio. Confirmed W07 missing darkening, P15 offline held-grenade/forced-release
  input discrepancy (also present in published96), and U05 missing map-linked scoreboard
  ID colors. Source paths, tests and documented adaptations are in
  [acceptance gaps](acceptance-gaps.md#discussion-only-fidelity-audit-2026-10-10).
  W07/P15/U05 are partial and reset to NOT_STARTED per the ledger's complete-code rule;
  existing subsystem test evidence is preserved. This limited audit is not an
  exhaustive parity pass. Changed files: `docs/status.md`, `docs/parity.md`,
  `docs/acceptance-gaps.md`; read-only rg/Get-Content/git log/git show inspection and
  documentation `git diff --check` passed. No game/test/export edits or engine runs
  were made by this audit; unrelated in-progress workspace edits belong to other work.
  Next action: discuss findings and audit source-visible state transitions before
  implementing repairs under a later user instruction.
- Continue integrated original-map/optional-effects and browser gesture/export acceptance.
- Queued fidelity repairs (2026-10-10): user authorized implementation of the three
  confirmed omissions W07/P15/U05 after the previous chat finishes its mobile FPS work.
  Dependency: Codex thread `01a12458-d660-7c80-814f-2b4c0b641c15`, title
  `Проверить запуск кода в web`, host local. Its final response and idle status were
  confirmed after the mobile31 publication. Implementation started from source
  `309eda544a5cfc5e79ef4504164932ce11aa6957`, preserving that mobile release.
  Current-thread heartbeat automation `blockfield` was created ACTIVE to check every
  five minutes, wait for completion/lease release, then implement/test/browser-check
  and publish the three fixes without further approval. Disable it after verified
  completion. Scope: damaged-block darkening/color recovery (offline/network), source
  offline grenade press/forced-release behavior, and minimap-linked scoreboard ID colors.
  Root owns Main network presentation, network integration fixture, build registration,
  shared contracts/docs, engine validation and release. `renderer_fidelity_audit` owns
  only World/Chunk and new world damage fixtures; `gameplay_feedback_audit` owns
  Controller/LocalSession and source/session/offline grenade fixtures;
  `ui_audio_fidelity_audit` owns HUD/Scoreboard and UI/color fixtures. Specialists do
  not run the engine or publish. Existing protocol/server rules stay unchanged.
  Next action: integrate confirmed-event damage expiry, review specialist handoffs,
  then run parser and behavioral/browser validation. No new verification claim yet.
- Fidelity handoff milestone: specialists returned all files/leases to root. Initial
  parser/import, World damage31/0, session166/0, source parity186/0 and UI284/0 passed.
  A final source pin-minimum refinement adds temporary denial/re-entry coverage;
  repeated source parity189/0 passed. The first network fixture used a noncanonical
  direct-helper source event ID, causing codec rejection/remote close; its diagnostic
  also tried mutating a frozen event. Failed logs remain `.cache/logs/fidelity-network-
  damage*.log`; the fixture now supplies canonical action IDs and mutable copies,
  and has a bounded recovery wait. Production codec/authority were not changed.
  A separate test-only actual-Main Web probe is being prepared for visible timed
  damage/recovery and held-grenade input; it is excluded from the Pages game.
  Full validation/export/browser/publication remain pending.
- Integration follow-up: lab119/0, mobile controls2381/0 and touch-look/settings144/0
  passed. Lab's immediate quick-release assertion needed one real controller frame
  after advancing the pin timer, consistent with original SetWeaponInput. A network
  controller fixture timed out1249/2 after reading pending-class authority before
  the client ACK/fresh-stream barrier. Its manually driven controller now retries
  the retained team intent as actual Main does, and verifies one request cursor
  advance. No input clock, admission, network or server production changes.
  Failed logs are retained; corrected fixture/native GPU checks are pending.
- Coherent fidelity code checkpoint: import clean; world31/0, session166/0,
  source189/0, UI284/0, actual socket/Main damage32/0, lab119/0, mobile2381/0,
  look144/0, network controller511/0 and shared rules144/0 passed on Godot
  `4.7.2.stable.official.ed1daf0bf`. Native Compatibility damage5/0 changed10,568
  pixels and restored with zero pixel difference; scoreboard23/0 verifies source
  palette glyphs, live/saved preference and canonical network slots. Logs
  `.cache/logs/fidelity-*`; PNGs `.cache/previews/{block-damage,scoreboard-colors}`.
  W07/U05 are IMPLEMENTED; P15 stays partial for the additional shared gate case
  documented in acceptance-gaps. Next: freeze this source, complete registered
  checks/Web export, interact with separate actual-Main Web probe and production
  export, publish/verify Pages, then disable automation. No new browser proof yet.
- Saved browser downloads, subjective listening, sustained original-map performance and
  32-client60Hz capacity remain open. Separate native/probe evidence from browser acceptance.
- Fidelity frozen-chain milestone (2026-10-11 local): full0898d6c prefix through mobile
  controls passed; mobile-look144/0 then reported two Vorbis resources at exit. Verbose
  diagnostics identify the Limbo/Select playback, not gameplay failures. The fixture
  now drains200ms real mixer time, like existing lab/UI tests, rather than200ms virtual
  fixed-FPS time. Root owns the engine/release lease. Frozen dcee15f0b7bc has byte-identical
  `game/` and unchanged prefix fixtures compared with0898d6c; only test-only probe and
  mobile-look cleanup differ. Import/look144/0/damage31/0 passed; remaining suffix/export
  and actual browser/public verification are in progress. Initial failures are preserved;
  no claim that the entire suite reran on dcee15f. Details: [fidelity repairs](fidelity-repairs.md).
- Fidelity completion (2026-10-11 local): all three authorized repairs are implemented
  and checked in the separate actual-Main WebGL probe8/0: source shot darkening,
  original RGB recovery after10s, held automatic grenade/new press/manual cooldown,
  ID palette ON/OFF. Ordinary local export ran with preserved mobile controls,
  Shotgun/target kill and drag-look; public dcee15f loaded original Title.vxl with
  terrain, HUD, rifle/minimap and drag fallback. IAB pointer lock reported
  WrongDocumentError; drag-look remains usable. No broad performance/audio/phone
  acceptance is implied. Published metadata/HTML/PCK match the exact frozen export.
  Automation `blockfield` is PAUSED after completion. Specialists and engine/release
  leases are returned to root; temporary probe/local tabs and HTTP helpers are stopped.
  W07/U05 remain IMPLEMENTED; P15's separate shared raw-button gate remains open.
  No remaining action in this authorized three-fix task. Next project work: remaining
  source fidelity and integrated acceptance under the existing scope.
- Keep offline lab usable without a server; retain owner privacy, fixed authority, bounded
  input/history/map queues and same-time terrain/player rewind. [Multiplayer contracts](multiplayer-plan.md).
- GitHub Actions account billing blocks runs before steps (run38031633237); local frozen
  validation/publication works. No billing settings changed. [Publication decision](decisions/0003-pages-publication.md).

## Commands and durable records

### Camera/effects repair handoff (2026-10-11)

Follow-up user report: camera still shakes at a distance. Fresh public metadata/PCK
fetch confirms4c051639e286 and SHA25610be980d25073beab27914f28c6a709d4fea4fa4f571165d9dc96fa46437f518,
equal to the local export. The previous repair is published, but retained native
nonzero shake through170 units and slow-peak saturation through35 units. It did
not redesign distant attenuation. Read-only source/metadata/hash verification only;
no game/test/export edits or engine runs. [Clarification](effects-performance.md#user-follow-up-distant-shake-2026-10-11).

Chat `01a1290b-3aaf-79f3-bc3d-a98e264cf7f5` owns only
`game/presentation/openspades_effects.gd`, `tests/presentation/test_effects.gd`,
new `tests/browser/effects_probe.gd` and `tools/export_effects_probe.py`, plus its
effects evidence document. Specialist `effects_pool` returned those first two files;
`grenade_audit` and `shot_hotspots` completed read-only source audits.
Main/controller/world/network/persistent-block-damage changes belong to the other
active chat; this repair does not edit those files. Engine checks use
isolated `.cache/effects-probe-*` projects, not the shared import cache.

Confirmed: grenade kick precedes the source170m cutoff; clamped0.1s effect time
prolongs shake and particle lifetime during hitches. Native near-amplitude saturation
is intentional source behavior. Effects have active caps but no reuse pools.
Actual-Main baseline WebGL held-SMG wall scenario reached512 particles and571 draw
calls. Committed effects repair16f1e70 adds prewarmed bounded pools, cached smoke
frames, one White.png fragment MultiMesh draw, cutoff-before-kick and actual elapsed
lifetimes/shake. Matching native headless effects32588/0 (3 explicit GPU skips),
GPU32591/0 and camera45/0 passed; native previews preserve particle groups/colors.
Frozen16 additionally passed parser/import, presentation504/0, extensions68/0,
actual Main lab119/0, lifecycle19/0, mobile-look144/0, runtime smoke and Web export.
Actual-Main patched WebGL SMG stress reached87 draw calls versus baseline571 with
the original512 particle cap; browser grenade5/80/180-unit states match the source
curves/cutoff. Browser throttling/concurrent engine/viewport changes prevent a
controlled FPS claim. Details, exact hashes/commands, failures and corrected fixtures:
[effects performance](effects-performance.md), [ADR0011](decisions/0011-effect-pools-and-fragment-batching.md).
All specialist leases returned. No shared `.godot` cache, production build folder,
server artifact or public Pages branch was changed by this chat.

Release handoff: later integrated source4c05163 (other-chat authority-clock repair)
already contains16's byte-identical manager. The persistent-block-damage chat owns
its shared export/publication lease; include this checked effects change in that
newer release rather than publishing the older16 archive. U12 remains IMPLEMENTED;
sustained target-device/original-map performance and audio/terrain hotspots remain
unaccepted. No remaining code action in the effects repair; integrated publication
belongs to the active shared release. Temporary probe tabs/HTTP helpers are stopped
before ending this chat's turn.

Python: `C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
Usual flow: `python tools/bootstrap.py` → `python tools/release_checkpoint.py --revision HEAD --server`;
`python tools/serve.py` for local review, `python tools/publish_pages.py` for publication.
`python tools/build.py --export` is the direct workspace validation/export command.
Release checkpoints validate frozen Git archives; an existing same-SHA archive is preserved.
Logs/previews/runtime/reference archives remain ignored under `.cache/`; never print credentials.
Update this page and affected ledger rows at milestones; append detailed history and subsystem
evidence with exact artifact identity. Record decisions in numbered ADRs, procedures in skills.
