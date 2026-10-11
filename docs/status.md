# Project status

Updated: 2026-10-11 (Europe/Moscow). This page is the authoritative current entry point.
Earlier evidence and failed attempts are preserved in [2026-10-10 history](history/2026-10-10.md).

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
- Published client source: `2d60434b7534ff75c2a1b3863d235b643d0ea0b8`, merged/pushed (iPhone touch repair).
- NexQuake mobile controls are merged into main through PR1, merge0fd90e75e508.
  All completed optimization commits through922f230 remain intact. Subsequent
  documentation does not change the checked game bytes. Mobile engine/release and
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
  source `1c046655fef23dcf46257dc10649d345ec4256d0`.
  Bundle `83ce7fa206d7f4e602fff2a01dfe0071e32d6b11`, Pages status built/no error.
  PR1 merged in main as `0fd90e75e508e83adbab410628940ca689d00da0`; game/test/tool
  bytes match the frozen source. Later documentation commits do not change them.
- Independently downloaded public metadata/HTML/JS/WASM/PCK and both audio worklets
  match the frozen export. PCK16,202,560bytes SHA256
  `c098fb35b23d33d771dfc4d669bf117cf6735b5560359fc1d039db88e1573289`;
  HTML5568bytes SHA256 `60c75e2e53041b707a7e72354d0c5be06e77fd31de09c434b29b9e71d1b18966`.
  Hash report `.cache/browser/nexquake-public-hashes.json`; normal public screenshot
  `.cache/browser/nexquake-public-mobile.jpg`. Movement/swipe/fire-drag exercised
  with100% touch gain; the pre-test public Auto setting was restored.
- Compatible [server prerelease](https://github.com/Gordey328/Blockfield/releases/tag/godot-66e4b5b7eb89)
  stays unchanged:29,344,396bytes SHA256
  `76935d2fc59be4d5af6387266714001292a9c11a5adbf1c276a4e0a7799e168b`.
  Network5 / authority5-no-block-regen remain byte-identical; client/server source
  commits now differ because this release changes mobile presentation/input only.
  Earlier66e4b5b/22fd630 optimization,4c/57 and31 artifacts retain their historical
  evidence. See [optimization evidence](optimization-audio-vxl-memory.md).
- Windows exported-PCK smoke on66e did not execute Linux. No server export/PCK smoke
  was repeated on1c; its full native server-launcher/network checks passed. Docker,
  Linux execution and deployed TLS/WSS remain unverified; see [server deployment](server-deployment.md).

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
