# ADR0032 Timed zombie survival

Accepted user scope: 2026-10-12. Implementation and release evidence belong in
docs/zombie-survival.md and docs/status.md.

The user requests an offline mode with configurable time, zombies per wave and
spawn dependence on elapsed time. Confirmed choices: begin after completed
multiplayer removal; survive the selected time then clear surviving enemies;
waves arrive on the timer and may overlap; enemies choose the easier detour or
barrier breach. The finished offline-only dev base preserves the new game shell
and bundled maps. No networking is introduced.

OfflineSurvivalSession extends OfflineTDMSession to reuse the explicit local
command/presentation bridge, not its TDM roster or round policy. Survival overrides
roster admission, step policy, target mirroring, supply, restart, clock and finish.
The base bridge has a small virtual mode query. The legacy Main flag
offline_tdm_mode denotes the shared controller path; the new survival scene also
sets offline_survival_mode so setup, views and outcomes are mode-specific. Existing
TDM and lab scene behavior remains independently checked.

The shared fixed60Hz MatchSimulation owns movement, original firearms, hit volumes,
health, grenades and committed VoxelData changes. A private zombie-kind registry
uses internal hostile faction1 and at most12 reusable slots with separate life
generations. Zombie commands are sanitized: they cannot shoot, throw grenades,
build or use the original100-damage spade melee. The AI produces movement and
bite/breach intentions; trusted mode rules validate windup, range, visibility,
cooldown and damage. No presentation node applies damage.

Production settings admit60–1800seconds,30–120seconds between wave starts,1–24
attempted appearances per wave and constant/linear/step growth0–6 per minute.
Twenty seconds of preparation precede the active combat clock. Each twelve-second
spawn window fixes its up-to quota from active elapsed time. Scheduled slots that
cannot admit a safe actor are explicitly counted as skipped and never form debt.
Visible fallback points receive a short warning and are checked again at admission.
Pause/focus loss freezes the clock; expired deadlines cannot produce a catch-up
burst. End time stops new spawning and requires cleanup. Owner death is defeat,
including simultaneous final-enemy death. No safe admission or unrecoverable route
failure produces a visible interrupted outcome without a victory or record.

Navigation is authored for Crossroads and one standing surface per column. A
bounded pair of searches shares the authority tick across spawn and pursuit.
Detour cost includes travel; breach cost also includes remaining block health,
body-clearance cells and shared cell attack cadence. A cheap breach can beat an
existing long detour. The planner caches geometry, invalidates after committed
terrain changes and avoids rapid switching for nearly equal alternatives.
Imported maps and stacked bridges/tunnels require separate navigation acceptance.

The original weapon selection and finite inventories remain. A visible supply
point grants one safe two-second refill per wave: reserve ammunition and blocks,
one grenade up to the existing maximum and25HP, without replacing the magazine.
Danger clears progress; cleanup can use only the unused final-wave refill.

ZombieView supplies a distinct unarmed voxel rig with shared resources and no
physics hit Areas or HP labels. A killed life uses the same node's bounded prone
pose before hiding/reuse. Main never manufactures a soldier corpse for a zombie.
Main adopts committed terrain once, including partial breach tint. GameShell
whitelists canonical settings; SurvivalPanel displays pause/results; combat HUD
shows wave/time/population/actual quota instead of team scores. Tab opens survival
status rather than the team roster.

Initial cap12 is an engineering bound for measurement, not a physical-phone FPS
claim. Behavioral fixtures and actual exported keyboard/mouse/mobile interaction,
visual checks and documented full-population measurement precede publication.
This addition does not establish full OpenSpades port completion.
