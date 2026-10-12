# ADR0035 — Market-oriented Rush iteration

Accepted 2026-10-12. The user requests mobile/Web market research and a new
iteration, explicitly authorizing changes to any part of the game.

The first playable hypothesis is Blockfield Rush: a fixed three-minute FPS
survival clock, followed by existing cleanup, on authored Crossroads. Preparation
is five seconds. Home starts it in one click using the selected weapon. Classic
survival, training and TDM remain available. This is an incremental product test;
it does not claim that FPS survival is the fastest-growing genre, portal approval,
physical-phone acceptance or completion of the original OpenSpades port.
Research and alternative directions are in [the market study](../market-research-2026-10.md).

SurvivalSettings owns a canonical `run_style=classic|rush`. Rush uses exactly
180 seconds, 30-second waves, initial quota3, linear growth2/minute, 12 live slots,
five-second preparation, zombie player damage15 and block damage40. Production
validation rejects modified Rush values. No test override is exposed through UI.
Rush launch bypasses selection persistence, preserving the user's custom setup.

OfflineSurvivalSession owns kill milestones3/7/12/18/25. Each offers up to three
authoritative choices: Power (+25% firearm actor damage/rank, maximum3), Armor
(-15% zombie bite/grenade damage/rank, maximum3), and Field kit (heal35 up to100,
full reserve without reloading the magazine, blocks+20 up to50, grenade+1 up to3).
Capped choices disappear. These are run upgrades, reset on restart. Human grenade,
terrain firearm damage and classic weapon profiles retain their existing rules.
MatchSimulation stores bounded actor-specific modifiers and applies them on actual
damage commits; presentation never changes profiles or health directly.

A pending choice is an independent authority gate: fixed ticks, grenade fuses,
AI, attacks and survival clocks stop. HUD disables movement/touch/fire, releases
actions and exposes the mouse. Ordinary pause/focus remains independent; choosing
while paused is rejected. Death and final victory take priority over a new offer.
RushUpgradePanel receives copied readout dictionaries and emits one choice ID.

Score is kills*100 + headshots*50 + whole active seconds*5 +1000 for victory.
Technical interruptions score0 and cannot set records. RushRecords stores one
local best for each weapon on Crossroads; no backend/account is introduced.
Current `rush_v1_crossroads` buckets belong to these ADR0035 rules. A future balance change must version
or explicitly reset them before comparing scores. Corrupt storage is recoverable;
failed saving cannot block gameplay. Results identify a newly saved personal best.
One-click replay restores data/perks and waits for the ordinary visual preparation
gate before reopening controls.

Coordinator owns HUD/Main/result/record integration, config, build, docs and release.
Authority specialist owns settings/session/shared damage and its behavioral fixture.
UI specialist owns Home quick launch/new choice panel and its layout fixture.
Research/review specialist owns the market study and actual-scene wiring fixture.
Engine validation is serial in the isolated managed market-iteration worktree.
