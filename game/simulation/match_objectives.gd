class_name MatchObjectives
extends RefCounted
## Authored LocalSession CTF/TC policy applied to every stable actor.
const RULES = preload("res://simulation/player_rules.gd")
const DT: float = 1.0 / 60
const PICKUP_DISTANCE: float = 2.0
const RESUPPLY_DISTANCE: float = 2.0
const TC_DISTANCE: float = 16.0
const TC_RATE: float = .05
var epoch: int = 1
var mode: String = "sandbox"
var last_tick: int = -1
var event_sequence: int = 0
var capture_limit: int = 3
var winning_team: int = -1
var scores: Array[int] = [0,0]
var bases: Array[Vector3] = [Vector3(16,5,48),Vector3(80,5,48)]
var flags: Array[Dictionary] = []
var territories: Array[Dictionary] = []
var _resupply_ticks: Dictionary[int,int] = {}

func configure(match_epoch: int, game_mode: String, flag_bases: Array[Vector3],
		territory_positions: Array[Vector3], limit: int = 3) -> bool:
	if match_epoch <= 0 or game_mode not in ["sandbox","ctf","tc"] or flag_bases.size()!=2 \
			or territory_positions.size()>16 or limit<1 or limit>65535: return false
	for point: Vector3 in flag_bases + territory_positions:
		if not point.is_finite(): return false
	epoch=match_epoch
	mode=game_mode
	bases=flag_bases.duplicate()
	capture_limit=limit
	scores=[0,0]
	winning_team=-1
	last_tick=-1
	event_sequence=0
	_resupply_ticks.clear()
	flags.clear()
	for team in range(2): flags.append({"team":team,"position":bases[team],"carrier":-1,"at_base":true})
	territories.clear()
	for point: Vector3 in territory_positions:
		territories.append({"position":point,"owner":2,"capturing_team":-1,"progress":0.0,"contested":false})
	return true

func drop_actor(actor: SharedPlayerState, tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if actor.match_epoch != epoch: return RULES.frozen(events)
	for flag: Dictionary in flags:
		if int(flag.carrier)!=actor.player_id: continue
		flag.carrier=-1
		flag.position=actor.feet()
		flag.at_base=false
		events.append(_event(tick,"intel_drop",actor,{"flag_team":flag.team,"position":flag.position}))
	_resupply_ticks.erase(actor.player_id)
	return RULES.frozen(events)

func step_fixed(tick: int, actors: Array[SharedPlayerState]) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if tick != last_tick+1: return RULES.frozen(events)
	if actors.size()>32: return RULES.frozen(events)
	var seen: Dictionary[int,bool]={}
	for actor: SharedPlayerState in actors:
		if actor==null or actor.player_id<=0 or seen.has(actor.player_id): return RULES.frozen(events)
		seen[actor.player_id]=true
	last_tick=tick
	if winning_team>=0: return RULES.frozen(events)
	var ordered: Array[SharedPlayerState] = actors.duplicate()
	ordered.sort_custom(func(a: SharedPlayerState,b: SharedPlayerState):return a.player_id<b.player_id)
	# Death, removal and spectator/team transitions must drop a carrier once.
	for flag: Dictionary in flags:
		if int(flag.carrier)<0: continue
		var carrier: SharedPlayerState
		for actor: SharedPlayerState in ordered:
			if actor.player_id==int(flag.carrier): carrier=actor;break
		if carrier==null:
			flag.carrier=-1
			flag.at_base=false
			events.append(_event(tick,"intel_drop",null,{"flag_team":flag.team,"position":flag.position}))
		elif not _eligible(carrier) or carrier.team==int(flag.team): events.append_array(drop_actor(carrier,tick))
	if mode=="ctf":
		for actor: SharedPlayerState in ordered:
			if _eligible(actor): events.append_array(_step_ctf(actor,tick))
			if winning_team>=0: break
	elif mode=="tc": events.append_array(_step_tc(ordered,tick))
	return RULES.frozen(events)

func _eligible(actor: SharedPlayerState) -> bool:
	return actor.match_epoch==epoch and actor.is_alive()

func _step_ctf(actor: SharedPlayerState,tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var enemy: Dictionary = flags[1-actor.team]
	var own: Dictionary = flags[actor.team]
	if int(enemy.carrier)<0 and actor.feet().distance_to(enemy.position)<PICKUP_DISTANCE:
		enemy.carrier=actor.player_id
		enemy.at_base=false
		events.append(_event(tick,"intel_pickup",actor,{"flag_team":enemy.team}))
	if int(enemy.carrier)==actor.player_id:
		enemy.position=actor.feet()
		if actor.feet().distance_to(bases[actor.team])<PICKUP_DISTANCE:
			enemy.carrier=-1
			enemy.position=bases[1-actor.team]
			enemy.at_base=true
			scores[actor.team]+=1
			actor.score+=10
			events.append(_event(tick,"intel_capture",actor,{"flag_team":enemy.team,"score":scores[actor.team]}))
			if scores[actor.team]>=capture_limit:
				winning_team=actor.team
				events.append(_event(tick,"round_won",actor,{"winning_team":winning_team,"mode":mode}))
	if not bool(own.at_base) and int(own.carrier)<0 and actor.feet().distance_to(own.position)<PICKUP_DISTANCE:
		own.position=bases[actor.team]
		own.at_base=true
		events.append(_event(tick,"intel_return",actor,{"flag_team":own.team}))
	if tick>=int(_resupply_ticks.get(actor.player_id,0)) and actor.feet().distance_to(bases[actor.team])<RESUPPLY_DISTANCE:
		events.append_array(RULES.restock(actor,tick,true))
		_resupply_ticks[actor.player_id]=tick+60
	return events

func _step_tc(actors: Array[SharedPlayerState],tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index in range(territories.size()):
		var territory: Dictionary=territories[index]
		var counts: Array[int]=[0,0]
		for actor: SharedPlayerState in actors:
			if _eligible(actor) and actor.feet().distance_to(territory.position)<TC_DISTANCE: counts[actor.team]+=1
		var balance: int=counts[0]-counts[1]
		territory.contested=counts[0]>0 and counts[1]>0
		if balance==0: continue
		var team: int=0 if balance>0 else 1
		var change: float=absi(balance)*TC_RATE*DT
		if int(territory.owner)==team:
			territory.progress=maxf(0,float(territory.progress)-change)
			continue
		if int(territory.capturing_team)>=0 and int(territory.capturing_team)!=team:
			territory.progress=maxf(0,float(territory.progress)-change)
			if float(territory.progress)<=0: territory.capturing_team=team
		else:
			territory.capturing_team=team
			territory.progress=minf(1,float(territory.progress)+change)
		if float(territory.progress)>=1:
			territory.owner=team
			territory.capturing_team=-1
			territory.progress=0.0
			events.append(_event(tick,"territory_capture",null,{"team":team,"territory":index,"position":territory.position}))
	scores=[0,0]
	for territory: Dictionary in territories:
		if int(territory.owner)<2: scores[int(territory.owner)]+=1
	if not territories.is_empty():
		for team in range(2):
			if scores[team]==territories.size():
				winning_team=team
				events.append(_event(tick,"round_won",null,{"winning_team":team,"mode":mode}))
				break
	return events

func snapshot() -> Dictionary:
	var result: Dictionary={"epoch":epoch,"mode":mode,"capture_limit":capture_limit,"winning_team":winning_team,
		"scores":scores.duplicate(),"bases":bases.duplicate(),"flags":flags.duplicate(true),"territories":territories.duplicate(true)}
	RULES.freeze_value(result)
	return result

func _event(tick: int,type: String,actor: SharedPlayerState,detail: Dictionary) -> Dictionary:
	event_sequence+=1
	var result:=detail.duplicate(true)
	result.merge({"event_id":"%d:o:%d"%[epoch,event_sequence],"type":type,"epoch":epoch,"tick":tick,
		"owner_id":actor.player_id if actor!=null else 0,"spawn_generation":actor.spawn_generation if actor!=null else 0,
		"team":actor.team if actor!=null else detail.get("team",2)},true)
	RULES.freeze_value(result)
	return result
