# Zombie survival: implementation and evidence

Updated: 2026-10-12 (Europe/Moscow). This report records the implemented offline
mode and available development checks. Frozen release acceptance and publication
are pending; the coordinator adds their exact source/bundle identities and Web
evidence after completing those gates.

Godot is `4.7.2.stable.official.ed1daf0bf`, Compatibility renderer. Upstream
OpenSpades remains `dcf449c845d509bbde9d79239b32d201c1389961`. Development starts
from offline-only `b35f694793b9e58ab9400e7c9008288bbb686c14` on branch
`codex/zombie-survival`, in the attached
`zombie-survival/Blockfield` worktree. The source was mutable during the checks
below; a passed individual fixture is not a checked frozen release identity.

## Accepted user choices and delivered scope

The user authorizes the zombie mode after completion of the chat «Удалить
мультиплеер из игры», permits reference research and delegates remaining game
design. Their subsequent choices are:

- Survive the selected duration, then kill the remaining zombies.
- New waves arrive by time even while previous-wave enemies remain alive.
- Zombies choose whichever is easier: detour around cover or breach it.
- Begin after multiplayer removal and its integration/checks, which already
  depend on the first game UI delivery.

The implementation provides one-player finite survival on the authored
Crossroads arena, one unarmed walker type, the three existing firearms and
standard spade/blocks/grenades. Existing training and offline 3×3 remain separate.
Survival appears in Home, has persistent validated settings, and launches its
own scene. Other imported maps do not claim zombie navigation support.
An endless run is not offered by this first delivery: production settings admit
only finite durations. Bosses, special infected, purchases and permanent upgrades
are outside the delivered cycle. This addition does not accept the full
OpenSpades port.

## Settings and clock semantics

The canonical boundary is `game/gameplay/survival_settings.gd`; the shell and map
catalog validate the same values before crossing into the scene. Unknown values
cannot enable fixture-only timing through a normal launch.

| Field | Default | Production bounds / behavior |
| --- | --- | --- |
| `duration_seconds` | 600 | 60–1800; UI uses 1–30 minutes |
| `wave_interval_seconds` | 60 | 30–120; UI step is 5 seconds |
| `zombies_per_wave` | 6 | 1–24; explicitly **up to** the quota |
| `growth_per_minute` | 1.0 | 0–6; UI step is 0.5 |
| `growth_mode` | `linear` | `constant`, `linear`, `step` |
| `live_limit` | 12 | Validated 1–12; normal form uses 12 |
| `preparation_seconds` | 20 | Exactly 20 in production |

Tests may explicitly request `test_overrides=true` to use 1-second minimum
duration/interval and 0–20 seconds of preparation. Catalog validation does not
admit these shortened production launches.

Twenty seconds of preparation precede the active survival clock. Movement,
building and shooting already work in preparation. Rules advance in fixed 60 Hz
steps. Menu pause, focus loss and a hidden browser tab pause the local session;
return does not advance the clock from wall-clock time.

The first wave starts at active `t=0`; subsequent starts are `k × interval`,
strictly before the selected duration. Each wave snapshots its quota from active
time, not from kills or from the number of previously successful appearances:

```text
constant: N = clamp(round(N0), 1, 24)
linear:   N = clamp(round(N0 + G × t / 60), 1, 24)
step:     N = clamp(round(N0 + G × floor(t / 60)), 1, 24)
```

These formulas and numerical values are authored Blockfield balance. With
defaults, starts at 0:00…9:00 plan quotas 6…15, totaling up to 105 appearances.
No wave starts at 10:00 in a ten-minute run. The shell's start/5/10-minute
forecast describes the growth curve, including times outside a shorter run;
it does not schedule an attack after the duration boundary.

## Appearance windows, skips and outcome

Each production wave has a twelve-second appearance window. Its quota slots
are distributed at `wave_start + floor(j × window_ticks / N)`, `j=0…N−1`.
The start is included and the end is excluded. Existing enemies continue attacking
after the window and across later waves.

At most one allocation attempt is performed per fixed tick. Missing intervals
are counted as skips instead of being processed as a burst. A full live cap,
expired window or unavailable safe point never creates debt for a later wave.
Deferred navigation may retry within the current allocation interval; expired
intervals are discarded. There is at most one pending visible appearance warning,
and it is cleared when its window closes.

The director checks up to twelve authored sectors. A candidate needs support,
free standing-body volume, at least twelve map units of distance from the player,
and a proven route or supported breach route. Hidden candidates are preferred.
For a visible candidate, the session emits a one-second warning before committing
the appearance. The scene shows a bounded marker and an alert sound. Geometry and
the live cap are checked again; changed geometry requires route revalidation.
The combat HUD displays the next-wave countdown and actual appearance/planned
counts. The pause panel also exposes skipped appearances. The implemented wave
announcement occurs at wave start; there is no separate five-second advance-wave
warning. The corresponding early draft-plan promise is superseded by this
description.

At the duration boundary, the remaining appearance quota and pending warning
expire and the phase becomes `cleanup`. Victory requires a living player and no
living zombies after at least one actual appearance. Player death wins the
outcome tie if the last zombie dies in the same step. There is no player or zombie
automatic respawn; a new zombie life comes only from the bounded scheduler.
Missing spawn availability or an unrecoverable route produces `interrupted`,
not a victory or record. The implementation uses a twenty-second no-progress /
spawn-stall horizon; cleanup also prevents a no-appearance free win.

Restart recreates the baseline map and resets lives/generations, clock, quota,
supply, attacks, AI and presentation. The restart menu waits for Resume. Home
tears down the session. Final state is read-only and the panel hides/disables
Resume after a result.

## Shared rules, AI and resource loop

`OfflineSurvivalSession` owns the scheduler, phases, windups, supply and outcome.
It adapts the existing shared simulation/controller interface; it does not use
the TDM kill-limit, team-score or respawn policy. Actor 1 is the human; reusable
zombie IDs are 2…13 with a `registry_kind` and fresh `spawn_generation` per life.
The simulation alone resolves damage and voxel transactions. AI emits movement
commands and bite/breach intents, with no firearm or original spade-button attacks.
Rendering adopts the same authoritative `VoxelData` and does not apply a second
copy of a breach transaction.

| Rule | Implemented value |
| --- | --- |
| Walker health | 100; no time-dependent HP growth |
| Bite | 27-tick / 0.45 s windup, 20 damage, 72-tick / 1.2 s cycle |
| Bite reach | 2.2 map units; metric wall LOS rechecked by shared rules |
| Crowd bite protection | 24 ticks / 0.4 s across attackers |
| Breach | 45-tick / 0.75 s windup, 40 damage, 90-tick / 1.5 s cadence |
| Shared cell breach cadence | At most one accepted hit per cell per 90 ticks |
| Protected floor | Cells at `y <= 1` excluded from breaches |

Route costs are estimated arrival seconds: approach, travel, queue pressure,
remaining health of every body-clearance cell, hit cadence and post-breach travel.
A damaged thin wall can beat an existing long detour; thick cover can favor the
short walk around it. Close estimates preserve the committed choice. Map edits
invalidate geometry; direct walking segments are validated and cached with their
geometry version. This is an authored single-surface planner, not general
navigation for stacked tunnels, bridges or imported maps.

Supply is a marked point at the authored player start. It opens between appearance
windows and remains usable during cleanup only if the last wave's refill is
unused. It requires 120 consecutive safe ticks / two seconds, distance below
2.5 units, sufficiently low horizontal velocity, no enemy within eight units,
and no player damage during the preceding two seconds. Danger, leaving the point
or moving resets progress. Each wave grants at most one refill:

- Add 25 HP, capped at 100.
- Fill reserve to the selected weapon's existing maximum; leave the magazine alone.
- Restore blocks to 50; add one grenade, capped at three.

The player must still reload. Construction/destruction stay available in combat;
blocks retain persistent damage and maps are not repaired automatically.

## Bounded presentation and work

- Twelve reusable zombie slots, one human; no growing actor-ID registry.
- One shared planning job per tick, consisting of at most two searches, each with
  1800 expansions; at most 8192 cached columns. Spawn and pursuit share this budget.
- Per zombie visual: six mesh parts, one rig, eight nodes including the view root.
  Four part meshes and one vertex-color material are shared across views. Voxel
  details are baked into part surfaces; no node per decorative cube.
- Unarmed authored walker: separate head/jaw, torn clothing, skin patches,
  asymmetric reaching arms, shuffle and attack windup. No equipped soldier
  weapon/spade, five hit Areas, per-enemy HP labels or presentation damage.
- Death lays down the same rig for two active presentation seconds, then hides it.
  Pause freezes retention; a new generation resets the rig immediately. Main's
  survival route creates no ordinary soldier corpse for these deaths.
- A single reusable visible-spawn marker and one supply marker/caption pair.
- Read-only `SurvivalPanel` shows state, supply and result with scrolling detail
  and pinned 48 CSS px actions. It uses the Web canvas's CSS extent, so DPR does not
  halve touch targets; it does not modify the Window's global scale. LabHUD skips
  its generic recursive menu adaptation for this subtree. Tab opens the survival
  panel instead of a green-team roster.

## Initial ray failure and retained repair evidence

`zombie-ai-first.log` and `zombie-ai-diagnostic.log` each retain **302 assertions,
1 failure**. The real demolished-corridor traversal stopped at
`(11.5, 4.001259, 12.5)` after three accepted breaches had removed only the middle
clearance cell.

The newly added attack paths had passed metric `difference.length()` into
`VoxelData.cast_source_ray(..., max_steps: int)`. That source CastRay2 API counts
crossed grid planes, not metric distance. A short angled ray needed both X and Y
crossings but its metric length implicitly truncated the available step count;
remaining lower/upper clearance cells were not reached. The separate
`cast_source_ray_legacy` API was not involved.

The repair changes only the new survival LOS paths to metric
`cast_voxel(origin, difference, difference.length() + epsilon)`: two director
helpers and four bite/breach checks across session and shared simulation. It
does not change the original source ray APIs globally. The authority adds a
three-height anchored-wall case with three accepted strikes per cell and the
90-tick cadence, preserving the floor. Real movement through the demolished
passage now passes. Final retained logs are `survival-session-metric-rays.log`
**131/0** and `zombie-ai-metric-rays.log` **302/0**.

## Development verification results

Every listed successful fixture has zero failures/rejected engine diagnostics in
its retained log. These are mutable-source development runs, not the final frozen
gate. Logs are local under `.cache/logs/`; the table provides their exact names.

| Fixture / evidence | Result | Log |
| --- | --- | --- |
| Canonical survival settings | 28/0 | `survival-authority-settings-1.log` |
| Survival session, initial / expanded | 98/0; 104/0 | `survival-authority-session-1.log`; `survival-authority-session-2.log` |
| Final survival session, metric rays | 131/0 | `survival-session-metric-rays.log` |
| Final zombie AI and real traversal | 302/0 | `zombie-ai-metric-rays.log` |
| Zombie view, headless | 82/0 | `specialist-zombie-view.log` |
| Zombie view, normal Compatibility GPU | 83/0 | `specialist-zombie-view-gpu.log` |
| Survival panel formatting/layout | 158/0 | `specialist-survival-panel.log` |
| Survival setup, layout rerun | 42/0; 42/0 | `root-survival-setup.log`; `root-survival-setup-layout.log` |
| Actual survival scene/controller | 34/0 | `root-survival-scene.log` |
| Offline TDM rules regression | 81/0 | `survival-authority-tdm.log` |
| Shared player rules | 141/0 | `survival-authority-player-rules.log` |
| Shared match simulation | 234/0 | `survival-authority-match-simulation.log` |
| Player state-copy contract | 2314/0 | `survival-authority-player-copy.log` |
| Shared match reset | 106/0 | `survival-authority-match-reset.log` |
| Actual TDM scene | 68/0 | `root-survival-regression-tdm-scene.log` |
| Existing shell / real launch | 434/0; 46/0 | `root-survival-regression-shell.log`; `root-survival-regression-launch.log` |

The first fresh import returned exit 1 without a script diagnostic; retain
`survival-first-import.log`. The subsequent cached import passed; retain
`survival-second-import.log`. Do not relabel the first attempt successful.

The panel fixture covers 375×812, 812×375, 568×320 and 1280×720 with both direct
and scaled canvas layouts, paused/result states, non-overlapping pinned actions
and scroll containment. The setup fixture uses desktop/portrait/landscape and
actual persisted choices. The scene fixture launches the selected shotgun,
uses ordinary movement/fire, pauses preparation, then explicitly adopts a short
fixture-only run to check real timed enemies, separate zombie views, restart,
bounded supply views and final player defeat. A short fixture is not a completed
ten-minute playthrough.

Normal GPU verification used Intel UHD Graphics, OpenGL 3.3.0 / driver
31.0.101.2127. The locally retained images are
`.cache/previews/zombies-native/empty.png` and
`.cache/previews/zombies-native/idle-walk-windup-corpse.png`; the latter was visually
inspected for unarmed appearance and the four distinct poses. This proves the
native presentation renders, not browser input or physical-phone performance.

## Reproduction commands

Run in the worktree root. The normal Windows `python` alias did not launch Python
in the presentation specialist's first attempt, before any engine process.
Successful commands use the bundled runtime below. `tools/build.py` retains logs
and fails on nonzero exit or rejected engine diagnostics.

```powershell
$python_runtime = 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'

# Exact final authority/AI reruns, sequentially.
& $python_runtime -c "import sys; sys.path.insert(0,'tools'); import build; build.run('survival-session-metric-rays',['--script',str(build.ROOT/'tests/session/test_survival_session.gd')],timeout=240); build.run('zombie-ai-metric-rays',['--script',str(build.ROOT/'tests/ai/test_zombie_ai.gd')],timeout=240)"

& $python_runtime -c "import sys; sys.path.insert(0,'tools'); import build; build.run('specialist-zombie-view',['--fixed-fps','60','--script',str(build.ROOT/'tests/presentation/test_zombie_view.gd')],timeout=180)"
& $python_runtime -c "import sys; sys.path.insert(0,'tools'); import build; build.run('specialist-survival-panel',['--fixed-fps','60','--script',str(build.ROOT/'tests/ui/test_survival_panel.gd')],timeout=180)"

# Ordinary renderer, not headless. Output path is absolute through build.ROOT.
& $python_runtime -c "import sys; sys.path.insert(0,'tools'); import build; build.run_command('specialist-zombie-view-gpu',[str(build.engine()),'--path',str(build.ROOT/'game'),'--rendering-method','gl_compatibility','--resolution','1024x640','--script',str(build.ROOT/'tests/presentation/test_zombie_view.gd'),'--','--gpu','--output='+str(build.ROOT/'.cache/previews/zombies-native')],timeout=180)"
```

The root setup/scene commands use the same `build.run` with `--fixed-fps 60` and
`tests/ui/test_survival_setup.gd` / `tests/integration/test_survival_scene.gd`.
The registered `tools/build.py` gate also contains the seven new settings,
session, AI, view, panel, setup and scene fixtures and the existing regressions.
Do not run concurrent engine/import/export processes against this project.

## Native 12-slot decision measurement

The final AI fixture measures only `ZombieDirector.commands`, using the real
authored map and shared movement over 900 fixed simulation ticks with twelve
living zombies. The player moves for the last 300 ticks. This is an accelerated
native/headless component measurement, not the full frame or render cost.

| Metric | Final retained value |
| --- | --- |
| Mean decision work | 1.736923333 ms / tick |
| p95 | 4.424 ms |
| Maximum | 40.404 ms |
| Planning jobs / searches | 192 / 384 |
| Expanded nodes, total / maximum per job | 28509 / 520 |
| Maximum planning jobs in one tick | 1 |
| Exhausted searches | 0 |
| Competitive prunings | 192 |

The initial failed run kept a stationary player; it is not a controlled baseline
for a speedup claim. No FPS inference follows from this component's mean: shared
rules, meshes, terrain, effects, UI, audio and browser runtime are excluded.
The 40.404 ms maximum also remains visible in the evidence. Physical iPhone 12
mini / Chrome sustained 30 FPS, thermals, memory growth and touch comfort remain
unverified.

## Pending coordinator gates

First frozen attempt at `4e93e1375df79a6fc589df5fb44d406e5f9adeb9` stopped
at the panel fixture's old Russian headshot caption expectation after the display
was clarified as head hits. Its preceding parser/import, original lab HDR119/0,
TDM/shell/launch and new settings/session/AI/view checks pass. The updated fixture
continues to assert the independent example's 17 kills, 8 head hits and 40 damage.
This failed freeze is retained in `.cache/logs/survival-frozen-gate.log` and is not
the publishable gate. The complete gate is repeated on the corrected revision.

Ordinary mutable export was exercised at 1280×720, 375×812 and 812×375 using
the in-app Chromium browser at localhost:8096. Home → Zombie waves restores
settings; setup now puts the wave controls before the small map card. Keyboard
movement with held W/S and Shift, drag fallback, mobile look and joystick gestures,
Fire, reload and tool buttons are exercised. Viewing through the mobile look region
does not consume ammunition. Pause holds the exact preparation/active countdown.
Restart creates a fresh paused preparation; Continue begins it. Pursuit, a 20HP
bite, repeated death, Home, three firearm kills in a horde and a single-enemy
60-second victory are observed in the ordinary game. The successful run ends at
01:00 with 1 kill, 0 live and 60 damage taken; it does not establish a normal Web
cleanup run with live enemies at the deadline. That boundary has meaningful
authority/actual-scene fixtures. The result caption now clarifies head hits rather
than implying headshot kills. No new GDScript diagnostic is observed; earlier
Chromium UnknownError pointer capture entries use the existing drag fallback.

Retained JPEGs: `.cache/previews/zombies-web/settings-portrait.jpg`,
`defeat-landscape.jpg`, `horde-12-desktop.jpg`, `horde-fire-desktop.jpg` and
`victory-desktop.jpg`. At the full 12-live limit the visible normal HUD reads
40FPS / 25.0ms / 447 draw calls; while firing/retreating, 3 kills reduce live
population to 9 and the sample reads 29FPS / 34.5ms / 499 draw calls. These are
short observations on this desktop, with rendering, sound and effects active;
they are not sustained benchmarks or mobile-hardware claims. The Web static
memory monitor reads 0.0MiB and is unavailable for a heap-growth conclusion.
Pool/life bounds are separately exercised by the behavioral fixtures. Mutable
ordinary export command: bundled Python `-c "import sys; sys.path.insert(0,'tools');
import build; build.export_web()"`, retained in
`.cache/logs/survival-export-layout-only.log`. It is not the publishable frozen gate.

- **Frozen source/full gate: PENDING.** The coordinator's mutable full pass
  encountered an existing Native HDR fixture expectation of `changed == true`
  while setting an already-saved speed of zero. The intended frozen fixture uses
  a new private user directory; HDR idempotent behavior is unchanged. This failed
  mutable run is not accepted as a full pass. Coordinator adds exact retained
  failure/final command logs, source SHA and final gate result.
- **Ordinary Web acceptance: PENDING.** Coordinator reports preliminary ordinary
  browser observations of preparation/countdown, pause with frozen time, a
  20-HP bite, death/restart and Home. Those observations still need their frozen
  bundle identity and retained browser evidence here. Victory/cleanup, full
  population, mobile input/layout and all-weapon resource loops are not yet
  accepted by this report.
- **Publication: PENDING.** Add the checked bundle commit, Pages URL, public hash
  comparison and actual public gameplay/result/reload checks after publication.
  There is no new public zombie-mode delivery claim in this draft.

Further development of additional maps or enemy types follows this first
finite-mode acceptance. The reference research and evolving game design remain in
[the zombie plan](zombie-waves-plan.md); this report describes code/evidence
instead of claiming every early design suggestion was implemented.
