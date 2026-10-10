# Project status

Updated: 2026-10-10 (Europe/Moscow). This page is the authoritative current entry point.
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
- Published client source: `31c513d0aa182aaf42db51146b83a7aa22d1cd2c`, committed/pushed.
- Subsequent documentation records do not change the published binaries. Specialist
  handoffs and the mobile release are complete. Current fidelity-repair ownership is
  recorded below; root now owns the engine/release lease.

## Frozen validation

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

- [Pages development build](https://gordey328.github.io/Blockfield/) serves the verified31 export.
  Bundle `e28bfddd165209defbc388e398c9fc35d5bfae84`; public metadata confirms clean31 source.
- Public `index.pck` equals the local export, SHA256:
  `7be6d3864fe75fa089082d0b4ad4cf1c99f350940ff1284b9592af675a0356bd` (16,167,776bytes).
  Public HTML also hash-matches; report `.cache/previews/public-mobile-fps-31c513d0aa18.json`.
- [Server prerelease](https://github.com/Gordey328/Blockfield/releases/tag/godot-57ad43b2b740)
  ZIP publicly downloaded/hash-verified:29,332,846bytes; SHA256:
  `054a6c9dc437cbe7d17541fc4f9428ada190cb410dab356ac833c4e0180d0974`.
- Export/PCK smoke did not execute Linux. Docker/container/Linux execution and deployed
  TLS/WSS remain unverified. See [server deployment](server-deployment.md).
- Existing57 server remains compatible: production network/simulation files and network-4
  IDs are byte-identical. This update exports/publishes only the client.

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
- Keep offline lab usable without a server; retain owner privacy, fixed authority, bounded
  input/history/map queues and same-time terrain/player rewind. [Multiplayer contracts](multiplayer-plan.md).
- GitHub Actions account billing blocks runs before steps (run38031633237); local frozen
  validation/publication works. No billing settings changed. [Publication decision](decisions/0003-pages-publication.md).

## Commands and durable records

Python: `C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
Godot: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
Usual flow: `python tools/bootstrap.py` → `python tools/release_checkpoint.py --revision HEAD --server`;
`python tools/serve.py` for local review, `python tools/publish_pages.py` for publication.
`python tools/build.py --export` is the direct workspace validation/export command.
Release checkpoints validate frozen Git archives; an existing same-SHA archive is preserved.
Logs/previews/runtime/reference archives remain ignored under `.cache/`; never print credentials.
Update this page and affected ledger rows at milestones; append detailed history and subsystem
evidence with exact artifact identity. Record decisions in numbered ADRs, procedures in skills.
