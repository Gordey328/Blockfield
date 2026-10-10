extends SceneTree
const REGISTRY = preload("res://network/session_registry.gd")
const P = preload("res://network/protocol.gd")
var assertions := 0
var failures := 0
var allocations := 0
var next_actor := 23
var build_hash := "blockfield-test-build".sha256_buffer()
var rules_hash := "blockfield-test-rules".sha256_buffer()

func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("SESSION REGISTRY: "+message)
func allocate(_name: String, _role: int) -> Dictionary:
	allocations += 1
	var id := next_actor
	next_actor += 37
	return {"ok":true,"actor_id":id}
func hello(role: int = 0, resume: PackedByteArray = PackedByteArray(), bulk: PackedByteArray = PackedByteArray()) -> BlockfieldProtocol.Packet:
	return P.make_packet(P.Kind.HELLO,{"role":role,"name":"Player","build_hash":build_hash.duplicate(),
		"rules_hash":rules_hash.duplicate(),"resume_token":resume.duplicate(),"bulk_token":bulk.duplicate()})

func _run() -> void:
	var registry := REGISTRY.new()
	check(registry.configure(7,build_hash,rules_hash),"trusted configuration")
	check(not registry.configure(0,build_hash,rules_hash) and registry.epoch == 7,"invalid configuration atomic")
	var malformed := hello()
	malformed.payload.build_hash[0] ^= 1
	check(not registry.admit_game(1,malformed,0,allocate).ok and allocations == 0,"build mismatch never allocates")
	var joined := registry.admit_game(1,hello(),1,allocate)
	check(joined.ok and joined.actor_id == 23 and allocations == 1,"stable identity differs from connection")
	var welcome: BlockfieldProtocol.Packet = joined.welcome
	check(P.encode(welcome).ok and welcome.payload.resume_token.size() == 32,"welcome strict wire-valid")
	check(welcome.payload.resume_token != welcome.payload.bulk_token,"independent capabilities")
	check(registry.owner_of_game(1) == 0 and registry.owner_of_game(1,false) == 23,"map barrier blocks gameplay")
	check(not registry.admit_game(1,hello(),2,allocate).ok and allocations == 1,"duplicate connection cannot allocate")
	check(not registry.admit_game(2,hello(0,welcome.payload.resume_token),3,allocate).ok,"active owner cannot be taken over")
	check(not registry.admit_bulk(1,hello(2,PackedByteArray(),build_hash),4).ok,"forged bulk token")
	check(registry.admit_bulk(1,hello(2,PackedByteArray(),welcome.payload.bulk_token),5).actor_id == 23,"separate socket bound to same owner")
	check(registry.owner_of_bulk(1) == 23 and registry.get_stats().actors == 1,"bulk does not allocate actor")
	check(not registry.admit_bulk(2,hello(2,PackedByteArray(),welcome.payload.bulk_token),6).ok,"bulk capability single-use")
	var end := P.make_packet(P.Kind.MAP_END,{"snapshot_id":19,"map_sequence":81,"hash":"barrier".sha256_buffer()},7,45,81)
	check(registry.set_barrier(23,end),"authority installs complete barrier")
	var ready := P.make_packet(P.Kind.MAP_READY,end.payload.duplicate(true),7,45,81)
	var forged := P.make_packet(P.Kind.MAP_READY,end.payload.duplicate(true),7,45,81)
	forged.payload.hash[0] ^= 1
	check(not registry.accept_ready(1,forged) and registry.owner_of_game(1) == 0,"wrong hash cannot ready")
	ready.tick += 1
	check(not registry.accept_ready(1,ready),"wrong state tick cannot ready")
	ready.tick -= 1
	check(registry.accept_ready(1,ready) and registry.owner_of_game(1) == 23,"matching identity/epoch/sequence/hash opens owner")
	check(not registry.accept_ready(1,ready),"duplicate ready rejected")
	check(registry.set_generation(23,5) and not registry.set_generation(23,0),"trusted generation update")
	var detached := registry.disconnect_game(1,10)
	check(detached.ok and detached.actor_id == 23 and detached.close_bulk == 1,"disconnect returns exactly owner and paired socket")
	check(registry.owner_of_bulk(1) == 0 and registry.owner_of_game(1,false) == 0,"both bindings invalidated")
	check(not registry.disconnect_game(1,11).ok,"repeat disconnect no duplicate transition")
	check(not registry.admit_game(2,hello(1,welcome.payload.resume_token),12,allocate).ok,"resume cannot change role")
	var resumed := registry.admit_game(2,hello(0,welcome.payload.resume_token),13,allocate)
	check(resumed.ok and resumed.resumed and resumed.actor_id == 23 and allocations == 1,"reconnect preserves identity without allocation")
	check(resumed.welcome.payload.spawn_generation == 5 and resumed.welcome.payload.resume_token != welcome.payload.resume_token,"generation retained and credentials rotated")
	check(registry.owner_of_game(2) == 0,"reconnect needs fresh map barrier")
	var renewed := registry.refresh_bulk_token(23,14)
	check(renewed.ok and renewed.token != resumed.welcome.payload.bulk_token,"slow preparation renews bulk capability before delivery")
	check(not registry.admit_game(3,hello(0,welcome.payload.resume_token),14,allocate).ok,"old resume token revoked")
	var new_welcome: BlockfieldProtocol.Packet = resumed.welcome
	check(not registry.admit_bulk(2,hello(2,PackedByteArray(),renewed.token),14+REGISTRY.BULK_TOKEN_MS).ok,"bulk capability expires at exact deadline")
	check(registry.disconnect_game(2,16000).ok,"reconnected owner disconnect")
	check(registry.expire(15999).is_empty(),"clock rollback cannot expire identity")
	check(registry.expire(45999).is_empty(),"grace includes last preceding millisecond")
	check(registry.expire(46000) == [23] and registry.get_stats().actors == 0,"exact grace expiry frees actor")
	check(not registry.admit_game(3,hello(0,new_welcome.payload.resume_token),46001,allocate).ok,"expired identity cannot resume")
	for index in range(REGISTRY.MAX_ACTORS):
		check(registry.admit_game(index+100,hello(index%2),46002+index,allocate).ok,"admit bounded population")
	check(not registry.admit_game(999,hello(),47000,allocate).ok and registry.get_stats().actors == 32,"actor capacity enforced including reserved identities")
	var view := registry.session_view(60)
	check(view.size() == 6 and not view.has("resume_hash") and not registry.get_stats().has("tokens"),"public diagnostics omit capabilities/hashes")
	view.ready = true
	check(registry.owner_of_game(100) == 0,"returned view cannot ready authority")
	check(registry.configure(8,build_hash,rules_hash) and registry.owner_of_game(100,false) == 0,"epoch reset clears all old ownership")
	print("SESSION REGISTRY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)
