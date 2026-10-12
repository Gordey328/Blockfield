# Zombie pursuit and startup follow-up

2026-10-12. Latest user scope replaces cost-based obstacle selection with random
detour/breach, fixes approach/retreat, requires reachable forward destruction for
an elevated player, and reduces startup stutter. The user explicitly excludes
repeated deployed-browser and mobile-UI tests. Original release16874505fa75 and
its 85-fixture/mobile/public-browser acceptance remain historical evidence in
[zombie-survival.md](zombie-survival.md). [ADR0033](decisions/0033-zombie-pursuit-and-startup.md)
records the updated contracts. This is not full-port acceptance.

The attached zombie-survival/Blockfield worktree starts from151ce9be8b56f8e11144446cbfb89092158e5dca.
Shared dirty primary checkout is preserved. Godot is4.7.2.stable.official.ed1daf0bf,
Compatibility; OpenSpades remainsdcf449c845d509bbde9d79239b32d201c1389961.
AI specialist owns director/navigation/AI fixture; authority specialist owns
survival session/session fixture. Coordinator owns existing launch/world
integration, startup/scene fixtures, build/docs/release. Engine calls are serial;
specialists have returned source and engine leases.

## Delivered changes

- Random obstacle choice is seeded per life and locked across replans until the
  obstacle resolves. Both branches require bounded valid paths; block-health
  costs no longer select the branch. The seeded64-life sample yields33breaches.
- Forward steering removes the stale rear center/anchor and negative braking;
  crowd separation cannot reverse the intended direction. Short direct pursuit
  checks full body clearance. Ordinary source one-block climb is retained.
- High targets project to a safe lower approach. Search radius2 expands to8 only
  if no lower approach is found, including a solid5×5 two-block platform. Only
  exposed reachable forward blocks are attacked; protected y0/y1 and remote
  support remain untouched. Real windup/damage/collapse can drop the player.
  Bite range/3D distance/visibility remain authoritative.
- Actual movement or confirmed damage refreshes stall progress. A confirmed hit
  refreshes valid same-cell queued attackers; repeating a windup alone does not.
- Match Main skips the discarded synchronous lab bootstrap, streams from the
  real authority spawn and adopts the first owner camera pose immediately. Entry
  leaves two turns for the pending state to draw. Match launch waits for initial
  bounded chunk publication and progressive minimap/water preparation before
  enabling input/clock, with a30second error/
  retry deadline. Standalone training lab still bootstraps once.

## Mutable verification

All logs below are ignored `.cache/logs/` evidence in this managed worktree.

| Check | Result | Log |
| --- | --- | --- |
| AI parser/import | pass | zombie-random-platform-import.log |
| AI final behavior | 523/0 | zombie-random-ai-platform-final.log |
| Survival authority parser/import | pass | survival-tower-import-1.log |
| Session with real tower/collapse/queue | 147/0 | survival-tower-session-1.log |
| Real launch regression | 46/0 | startup-scene-gate-final.log |
| Actual survival scene | 36/0 | startup-scene-gate-final.log |
| Actual startup/Entry gate | 16/0 | startup-scene-gate-final.log |
| Parser/import and runtime smoke | pass | startup-scene-gate-final.log |

Retain failures: the initial AI short approach bypassed a remaining upper block;
full body-clearance fixed it. A forward-recovery guard initially stopped source
one-block climb at partially supported edges; bounded climb recovery fixed it.
The initial terrain-readiness scene test fired before the original weapon raise
finished; the final fixture waits for and asserts that real state before firing.
`.cache/logs/test-survival-scene.log` is the final rerun; the original failure was
reported in the engine output and is not claimed as a pass.

Startup samples are headless native wall time in `root.add_child`/ready, not Web
FPS, phone performance or complete click-to-play latency. A first cold pair was
survival2159.015→2078.237ms and warm TDM1122.767→856.448ms. A paired script-preloaded
sample is survival1982.025→1570.071ms and warm TDM1066.746→659.777ms. The stable
behavioral result is discarded lab generations1→0; OS/resource caches change
timings. Phase instrumentation finds effects/scene334.906ms and graphics/HUD/
player-rig1215.692ms in the latter survival sample. Those cold costs remain;
loading feedback and chunk readiness do not eliminate all resource/shader work.
Logs: startup-before.log, startup-after.log, startup-baseline-paired.log and
test-startup-work.log. The baseline is the preserved original release directory.

AI-only native sample:12actors,900ticks including300 moving-owner ticks; mean2.822ms,
p9510.403ms, max55.957ms. There are192jobs/280searches/56432nodes, max1491expanded
nodes per job, at most one pair per tick and0exhausted. This is planning CPU,
not exported frame time. Crossroads/single standing surface remains the scope;
stacked/imported map navigation is not accepted.

Reproduction (PowerShell, bundled Python):

```powershell
$python_runtime = 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $python_runtime -X utf8 -c "import sys; sys.path.insert(0,'tools'); import build; build.run('zombie-random-platform-import',['--editor','--import','--quit'],timeout=240); build.run('zombie-random-ai-platform-final',['--script',str(build.ROOT/'tests/ai/test_zombie_ai.gd')],timeout=240)"
& $python_runtime -X utf8 -c "import sys; sys.path.insert(0,'tools'); import build; build.run('survival-tower-session-1',['--script',str(build.ROOT/'tests/session/test_survival_session.gd')],timeout=300)"
& $python_runtime -X utf8 tools/build.py --suite startup-work --suite survival-scene --suite game-launch
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path .cache/release-16874505fa75/game --fixed-fps 60 --script 'C:/Users/Gordey/.codex/worktrees/zombie-survival/Blockfield/tests/integration/test_startup_work.gd' -- --baseline
```

## Frozen export and publication

Pending. Follow-up build supports explicit repeatable `--suite` selection; import
and runtime smoke always run, and default remains all registered fixtures. The
frozen gate will use changed/relevant native suites, no mobile-UI suite, ordinary
Web export and local desktop input/render inspection. Public verification uses
asset hashes and Pages API status, without reopening deployed gameplay.
Heartbeat ui-2 remains PAUSED.
