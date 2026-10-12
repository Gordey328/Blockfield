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

Pending coordinator gate. Parser/behavioral checks, ordinary Web export,
interactive browser evidence, actual public hashes and release identities will
be recorded here before closing the task. SDK/advertising, portal acceptance,
retention/market-fit measurements and physical-phone acceptance are outside this
first iteration's achieved claims; this does not complete OpenSpades parity.
