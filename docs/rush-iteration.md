# Blockfield Rush — 2026-10-12

The user requests mobile/Web market research and a new trend-oriented iteration,
authorizing changes to any part of the game. [The study](market-research-2026-10.md)
supports accessible repeatable play with progression, without identifying a
guaranteed winning genre. The chosen incremental hypothesis retains FPS and adds
a three-minute survival clock plus cleanup, five-second preparation, kill-based
run choices, local records and one-click entry/replay. [ADR0035](decisions/0035-market-oriented-rush.md)
contains the fixed rules and boundaries.

Managed market-iteration/Blockfield starts at dev
76eae15a63882f729dc7b9225235a818cec84c49 (checked survival runtime1630770).
The stale dirty primary checkout is preserved. No other user chat is created or
messaged. Pinned Godot4.7.2.stable.official.ed1daf0bf/Compatibility/single-thread
and upstream OpenSpadesdcf449c845d509bbde9d79239b32d201c1389961 remain.

## Ownership and implementation

Authority specialist owns SurvivalSettings, OfflineSurvivalSession,
MatchSimulation and test_rush_session. UI specialist owns GameShell,
RushUpgradePanel and test_rush_upgrade_panel. Research/scene specialist owns
the market study and test_rush_scene. Coordinator owns Main/HUD/LaunchOverlay,
result/record integration, config, build, existing catalog regression, docs and
release. All source/engine leases close before the frozen gate.

Rush starts canonical Crossroads using the selected weapon without overwriting
ordinary saved map/wave preferences. Fixed choice milestones are3/7/12/18/25 kills.
Firepower and armor cap at3; field kits cap resources under existing rules.
Choices freeze fixed authority, including projectiles; HUD releases all actions,
disables touch/movement/fire and exposes the cursor. Death/win takes priority.
Replay restores the baseline/perks and waits for terrain readiness. Versioned
per-weapon local records require a completed eligible run; interruptions score0.
Storage errors remain recoverable and visible.

## Mutable validation and review

Authority parser/import, Rush850/0, settings37/0, survival156/0,
shared Match244/0 and hostile ordnance66/0 pass. UI parser/import,
Rush172/0, shell436/0, survival panel158/0 and setup42/0 pass.
New UI tests include four sizes and both normal/scaled logical viewports.
Coordinator checks records13/0, initial actual scene57/0, launch46/0,
startup16/0, TDM81/0/scene68/0, player141/0, mobile10059/0,
look224/0 and aim assist79/0. Runtime smokes pass. These are native/desktop
layout checks; physical-phone performance/comfort are separate.

Review confirms original weapon profiles are unchanged and modifiers default to1
outside Rush. Initial authority fixture mistakenly mutated an owned actor copy;
it is corrected to use the simulation's live actor. Existing shell test still
expected five maps despite baseline survival expansion; it now asserts all seven.
An initial multi-file documentation patch matched the stale primary parity row
and failed atomically; narrow corrected patches preserve current dev evidence.

Review adds an independent launch input/authority gate. The first new Escape test
incorrectly expected a loading overlay to remain in-game; Escape intentionally
cancels to Home. This exposed actual detached-tree resize/deferred-launch errors.
Main now guards cancellation at each staged process boundary and LaunchOverlay
ignores detached layout callbacks. The final fixture checks Resume/focus during
loading and separately cancels with real Escape. Retained failed log:
`.cache/logs/test-rush-scene-cancel-failed.log`.

```powershell
$python_runtime = 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $python_runtime -X utf8 tools/build.py --suite rush-session --suite survival-settings --suite survival-session --suite match-simulation --suite zombie-grenades
& $python_runtime -X utf8 tools/build.py --suite rush-upgrade-panel --suite game-shell --suite survival-panel --suite survival-setup
& $python_runtime -X utf8 tools/build.py --suite rush-records --suite rush-scene --suite game-launch --suite startup-work --suite offline-tdm-scene --suite offline-tdm --suite player-rules --suite mobile-controls --suite mobile-look --suite mobile-aim-assist
```

## Frozen export and browser/publication

Full frozen runtime **f451aadcf536eae0cd1bee159c4821d1a74f9b48** passes30 selected
fixtures, parser/import, runtime smoke and normal Web export. Log:
`.cache/logs/rush-frozen.log`. Final **3dd42ab0cce287257fdd9954a784673c292c7b77**
changes only Home/HUD rendering and the Home layout fixture. Its gameplay,
simulation, AI and world trees match f451aad byte-for-byte (`git diff --exit-code
f451aad 3dd42ab -- game/gameplay game/simulation game/ai game/world`). Final
seven fixtures/parser/runtime/export pass: UI282/0, shell436/0, launch46/0,
records13/0, RushUI274/0, actual Rushscene66/0, startup16/0. Log:
`.cache/logs/rush-final-frozen.log`. All failures remain0. This selected gate is
not described as a repeat of every original port fixture.

```powershell
& $python_runtime -X utf8 tools/release_checkpoint.py --revision f451aadcf536eae0cd1bee159c4821d1a74f9b48 --import-cache game/.godot --suite world --suite session --suite integration --suite voxel-adapter --suite world-preparation --suite offline-tdm --suite offline-tdm-scene --suite game-shell --suite game-launch --suite survival-settings --suite survival-session --suite survival-panel --suite survival-setup --suite survival-scene --suite rush-session --suite rush-records --suite rush-upgrade-panel --suite rush-scene --suite zombie-grenades --suite player-rules --suite match-simulation --suite match-reset --suite shared-grenade --suite mobile-controls --suite mobile-look --suite mobile-aim-assist --suite startup-work --suite zombie-ai --suite zombie-view --suite ui
& $python_runtime -X utf8 tools/release_checkpoint.py --revision 3dd42ab0cce287257fdd9954a784673c292c7b77 --import-cache game/.godot --suite rush-upgrade-panel --suite game-shell --suite rush-scene --suite game-launch --suite startup-work --suite ui --suite rush-records
& $python_runtime -X utf8 tools/serve.py --directory build/web --port 8115
& $python_runtime -X utf8 tools/publish_pages_variant.py --folder build/web --slug rush
```

Ordinary local final Web shows Rush Home, full terrain and selected SMG30/120,
five-second preparation, three-line wave/score/progress readout, movement,
finite firing30to1 and reloading120to91, original weapon recoil and pause.
Earlier normal f451aad runs show real hostile deaths at23/29seconds, record115
then145 and one-click replay. Only UI changes separate these runtime trees.
375x812 desktop browser with touch-On shows reachable Home, toolbar and buttons;
actual Fire changes SMG30to26 and Menu freezes the match. This is simulated
viewport/mouse-on-touch input, not physical phone performance/comfort. Initial
resize screenshots captured an unsettled canvas; settled canvas is375x812 with
CSS374x811. Desktop IAB pointer capture reports Chromium UnknownError and uses
the existing drag fallback; no GDScript error is recorded from normal final play.

The isolated ignored **diagnostic**, sourced from frozen3dd42ab, uses the actual
offline scene and three real spawn/death commits to reach the kill milestone.
It never sets upgrade levels/pending directly. Dirty=true and
status=diagnostic-not-for-publication prevent its release. Native parser,
threshold,15 frozen frames and Web export pass. Final Web shows tick40 while
frozen frames372to1020 advance; all cards visibly render at1280x720/375x812.
Actual mobile Power card click hides the modal, yields rank1 and advances tick62.
Final console warning/error list is empty. Original game manifest SHA256:
8f45a34cb9ab037b621631aa19f03d4d3ff81e5676903642b0770493e6e36af4.
Final harness SHA256:
965f7dc6cc0400f39672e7cf1cad53bc20ceaf9d637c5e33fe9f036080c653ca.
Probe summaries/logs are in `.cache/rush-choice-probe/` and screenshots in
`.cache/previews/rush/`. These controlled UI checks supplement ordinary gameplay.

The first diagnostic assumed four process frames guaranteed a fixed authority
step. Web timing opened the real offer later, so its banner falsely failed;
attempt-1 preserves its harness/logs/screenshot. Final harness waits for actual
pending with a10second bound and uses private touch-On preferences, matching the
tested mobile/public layout. Desktop touch-Off portrait correctly letterboxed
and was not accepted as phone layout. Automatic approval rejected the helper's
initial Start-Process command with `blocked by policy`; a managed localhost-only
Python HTTP session succeeds. One later CDP Menu click times out after successful
card selection; no additional interaction is needed, and tab closure/reset succeed.
These harness/provider failures are not relabeled as game failures or clean runs.

Public [Rush preview](https://gordey328.github.io/Blockfield/rush/?v=3dd42ab)
is Pages bundle **bcc4463691f5cb71eb201e48a483f81555fee3f0**, built/no API error.
All30 public files SHA-match the frozen final export (58,124,055bytes total).
Git publication diff contains only rush/; root/sibling builds are preserved.
Public Home, selected shotgun6/48, actual Fire6to5, hostile damage, progress/score,
pause and return Home pass; public warning/error list is empty. Receipts:
`.cache/rush-export-hashes.json`, `.cache/rush-public-hashes.json`,
`.cache/logs/rush-publish.log`, public-console.json and public-home.jpg under the
preview folder. [Draft PR4](https://github.com/Gordey328/Blockfield/pull/4) targets
dev; source codex/market-rush is pushed and attached, rather than merging into
the concurrent dirty primary checkout.

Uncompressed engine31,835,587 + pack25,317,988 + JavaScript247,836 bytes are measured in the export;
the loading shell reports approximately57.2decimalMB including JS. Total public
files are58.124MB. This is not asserted to be compressed CDN transfer size or
portal budget compliance. Portals need a substantially lighter initial payload
and SDK-specific acceptance; physical-phone FPS/comfort, manual full-duration
victory and measured retention/voluntary repeat remain open. Original port parity
is not promoted. Own HTTP helpers49540/45236 stop by verified PID/command line;
temporary local/diagnostic tabs close, viewport resets and only the public
deliverable tab remains. Ignored diagnostic evidence is retained.
