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
- Published production source: `57ad43b2b740c13323d96433ec863e6790846ad2`, committed/pushed.
- Subsequent documentation records do not change the published binaries. All specialist leases
  are closed; root owns integration/release.

## Frozen validation

- The complete registered frozen `build.py` suite passed, followed by Web and Linux exports
  and matching Windows-engine exported-PCK smoke, with clean final diagnostics/metadata.
- First import exited1 without `ERROR` or an identified cause; its artifact remains saved.
  An unchanged diagnostic retry and then full import/all tests passed. Cause remains unknown.
- Frozen shaped latency **459/0**: safe stale retirement, exact replay/resources/map convergence,
  separate heartbeat timeout/resume and cleanup. See [latency contract](network-latency.md).
- Frozen scheduler **47/0**:130 callbacks,345 inputs, lead2..8, pending8, wall6.670s.
  See [scheduler contract](client-schedule.md); these measurements do not establish capacity.
- Logs: `.cache/release-57ad43b2b740/.cache/logs`; latency JSON in that archive's `.cache/benchmarks`.

## Published artifacts

- [Pages development build](https://gordey328.github.io/Blockfield/) reports built/noerror.
  Bundle `0fe5f806a253e8ffa02d35541f8fc0a552ef32d3`; public metadata confirms clean57 source.
- Public `index.pck` equals the local export, SHA256:
  `835be72829cde3e26dbf1bd15aa67840f1014b364f343234b49d62a11fea0cb8`.
- [Server prerelease](https://github.com/Gordey328/Blockfield/releases/tag/godot-57ad43b2b740)
  ZIP publicly downloaded/hash-verified:29,332,846bytes; SHA256:
  `054a6c9dc437cbe7d17541fc4f9428ada190cb410dab356ac833c4e0180d0974`.
- Export/PCK smoke did not execute Linux. Docker/container/Linux execution and deployed
  TLS/WSS remain unverified. See [server deployment](server-deployment.md).

## Actual frozen Web evidence

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

- Mobile-control update is in integration: specialist ownership has returned to root.
  New `game/ui/mobile_controls.gd` and `tests/ui/test_mobile_controls.gd` exercise real
  touch ownership and source/network handoff; native component suite808/0 on Godot4.7.2.
  Root owns HUD/controller/settings/scale integration and publication. Landscape844×390
  and portrait390×844 exported-browser views were inspected; initial anchored HUD and
  portrait minimap overlaps are corrected. Actual Main/HUD regression267/0 passed,
  including preference/mode lifecycle, action bridges, chat/focus cleanup and desktop
  input restoration. Frozen publication remains pending. Physical phone hardware
  has not been tested. See [mobile contract](mobile-controls.md).

- Neither iteration is fully accepted; use the ledger's evidence-bound statuses.
- Continue integrated original-map/optional-effects and browser gesture/export acceptance.
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
