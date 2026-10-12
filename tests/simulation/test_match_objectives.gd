extends SceneTree
const OBJECTIVES = preload("res://simulation/match_objectives.gd")
const STATE = preload("res://simulation/player_state.gd")
const RULES = preload("res://simulation/player_rules.gd")
var assertions:=0
var failures:=0

func check(value: bool,message: String) -> void:
	assertions+=1
	if not value:
		failures+=1
		push_error("FAIL: "+message)

func actor(id: int,team: int,position: Vector3,epoch: int=9) -> SharedPlayerState:
	var result:=STATE.new(id,"P%d"%id,epoch)
	RULES.spawn(result,0,position,team)
	return result

func has(events: Array[Dictionary],type: String,owner: int=-1) -> bool:
	for event: Dictionary in events:
		if event.type==type and (owner<0 or int(event.owner_id)==owner): return true
	return false

func _initialize() -> void:
	var objectives:=OBJECTIVES.new()
	var bases: Array[Vector3]=[Vector3(5,5,5),Vector3(40,5,5)]
	check(objectives.configure(9,"ctf",bases,[],1),"configure authored CTF policy")
	var blue:=actor(23,0,bases[1])
	var other:=actor(4,0,bases[1])
	var green:=actor(81,1,Vector3(20,5,5))
	var players: Array[SharedPlayerState]=[blue,green,other]
	var events: Array[Dictionary]=objectives.step_fixed(0,players)
	check(int(objectives.flags[1].carrier)==4,"simultaneous pickup resolves by stable ID, not array/local order")
	check(has(events,"intel_pickup",4) and not has(events,"intel_pickup",23),"only one actor owns pickup")
	check(events.is_read_only() and events[0].is_read_only(),"objective events immutable")
	check(objectives.step_fixed(0,players).is_empty() and objectives.event_sequence==1,"duplicate tick cannot repeat pickup")
	other.motion.feet_position=bases[0]
	other.magazine=3
	other.reserve=0
	events=objectives.step_fixed(1,players)
	check(has(events,"intel_capture",4) and has(events,"round_won",4),"carrier captures and wins at its own base")
	check(objectives.scores==[1,0] and objectives.winning_team==0,"team score independent of local identity")
	check(other.score==10 and other.kills==0 and blue.score==0,"capture score belongs to carrier, not other actor/kills")
	check(other.magazine==3 and other.reserve==50,"source resupply preserves clip and restores reserve")
	check(objectives.step_fixed(2,players).is_empty(),"won round stops objective authority")
	var snapshot: Dictionary=objectives.snapshot()
	check(snapshot.is_read_only() and snapshot.flags.is_read_only() and snapshot.flags[0].is_read_only(),"snapshot recursively read only")
	check(objectives.configure(9,"ctf",bases,[],3),"fresh objective round resets clocks")
	other.motion.feet_position=bases[1]
	blue.motion.feet_position=Vector3(20,5,20)
	green.motion.feet_position=Vector3(20,5,20)
	objectives.step_fixed(0,players)
	other.health=0
	events=objectives.step_fixed(1,players)
	check(has(events,"intel_drop",4) and int(objectives.flags[1].carrier)==-1,"death drops stable actor intel")
	check(not has(objectives.step_fixed(2,players),"intel_drop"),"death cannot drop twice")
	green.motion.feet_position=bases[1]
	events=objectives.step_fixed(3,players)
	check(has(events,"intel_return",81) and bool(objectives.flags[1].at_base),"another actor returns its dropped own intel")
	blue.motion.feet_position=bases[1]
	objectives.step_fixed(4,players)
	players.erase(blue)
	events=objectives.step_fixed(5,players)
	check(has(events,"intel_drop"),"removing a local actor drops intel promptly")
	players.append(blue)
	blue.health=100
	blue.motion.feet_position=bases[1]
	green.motion.feet_position=Vector3(20,5,20)
	objectives.step_fixed(6,players)
	blue.team=1
	events=objectives.step_fixed(7,players)
	check(has(events,"intel_drop",23) and has(events,"intel_return",23),"team transition cannot retain own intel")
	check(objectives.configure(9,"ctf",bases,[],3),"reset clears carrier/resupply state")
	blue.team=2
	other.team=0
	other.health=0
	var old:=actor(3,0,bases[1],8)
	players=[blue,other,old]
	check(objectives.step_fixed(0,players).is_empty() and int(objectives.flags[1].carrier)==-1,"spectator/dead/old epoch cannot capture")
	check(objectives.configure(9,"tc",bases,[Vector3(20,5,20)]),"configure one TC territory")
	blue=actor(23,0,Vector3(20,5,20))
	other=actor(4,0,Vector3(20,5,20))
	green=actor(81,1,Vector3(20,5,20))
	players=[blue,other,green]
	objectives.step_fixed(0,players)
	check(bool(objectives.territories[0].contested) and is_equal_approx(objectives.territories[0].progress,.05/60),"TC counts all actors once and retains authored balance while contested")
	other.health=0
	objectives.step_fixed(1,players)
	check(is_equal_approx(objectives.territories[0].progress,.05/60),"equal living teams freeze TC progress")
	green.health=0
	for tick in range(2,1203): events=objectives.step_fixed(tick,players)
	check(int(objectives.territories[0].owner)==0 and objectives.scores==[1,0] and objectives.winning_team==0,"one remaining actor captures TC and wins")
	check(objectives.configure(10,"tc",bases,[Vector3(20,5,20)]),"epoch reset clears TC win/progress")
	check(objectives.territories[0].progress==0 and objectives.scores==[0,0] and objectives.winning_team==-1,"new epoch state clean")
	players=[blue,blue]
	check(objectives.step_fixed(0,players).is_empty() and objectives.last_tick==-1,"duplicate registry IDs rejected before clock/mutations")
	check(not objectives.configure(0,"ctf",bases,[]) and objectives.epoch==10,"invalid config atomic")
	print("MATCH OBJECTIVES: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
