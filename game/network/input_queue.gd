class_name BlockfieldInputQueue
extends RefCounted
## One connection owner's commands. Server time never comes from client dt.
const PROTOCOL = preload("res://network/protocol.gd")
const RULES = preload("res://simulation/player_rules.gd")
const MAX_PENDING := 32
const MAX_LATE_TICKS := 15
const MAX_FUTURE_TICKS := 8
const LEASE_TICKS := 6
var epoch: int = 0
var generation: int = 0
var input_ack: int = 0
var needs_resync: bool = false
var _last_server_tick: int = -1
var _last_command_tick: int = -1
var _tail_sequence: int = 0
var _tail_input_tick: int = -1
var _pending: Array[Dictionary] = []

func reset(match_epoch: int, spawn_generation: int, server_tick: int, acknowledged_sequence: int = 0) -> bool:
	if match_epoch <= 0 or match_epoch > PROTOCOL.U32_MAX or spawn_generation <= 0 or spawn_generation > PROTOCOL.U32_MAX \
			or server_tick < -1 or server_tick > PROTOCOL.U32_MAX or acknowledged_sequence < 0 or acknowledged_sequence > PROTOCOL.U32_MAX: return false
	epoch = match_epoch
	generation = spawn_generation
	input_ack = acknowledged_sequence
	_last_server_tick = server_tick
	_last_command_tick = server_tick
	_tail_sequence = acknowledged_sequence
	_tail_input_tick = -1
	needs_resync = false
	_pending.clear()
	return true

func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func accept(packet: BlockfieldProtocol.Packet, server_tick: int) -> Dictionary:
	if epoch == 0 or needs_resync or packet == null or packet.kind != PROTOCOL.Kind.INPUT_BATCH \
			or packet.epoch != epoch or packet.sequence != generation or server_tick != _last_server_tick or not PROTOCOL.encode(packet).ok:
		return _failure("invalid owner clock, generation or input schema")
	var records: Array = packet.payload.records
	if packet.tick != records.back().input_tick or records[0].input_sequence != _tail_sequence+1 \
			or records[0].input_tick <= _tail_input_tick or _pending.size()+records.size() > MAX_PENDING:
		return _failure("input gap, replay or queue capacity")
	var staged: Array[Dictionary] = []
	for record: Dictionary in records:
		if record.input_tick < maxi(0,server_tick-MAX_LATE_TICKS) or record.input_tick > server_tick+MAX_FUTURE_TICKS:
			return _failure("input outside admitted tick window")
		var command := RULES.Command.from_record(record,generation)
		if not command.valid(): return _failure("invalid command")
		staged.append({"input_tick":record.input_tick,"command":command})
	_pending.append_array(staged)
	_tail_sequence = records.back().input_sequence
	_tail_input_tick = records.back().input_tick
	return {"ok":true,"error":"","queued":_pending.size()}

func take(server_tick: int) -> Dictionary:
	if epoch == 0 or needs_resync or server_tick != _last_server_tick+1 or server_tick > PROTOCOL.U32_MAX: return _failure("invalid server step")
	_last_server_tick = server_tick
	if not _pending.is_empty() and _pending[0].input_tick < server_tick-MAX_LATE_TICKS:
		_pending.clear()
		needs_resync = true
		return _failure("input backlog expired; owner resync required")
	var command: PlayerRules.Command = null
	var input_tick := -1
	if not _pending.is_empty() and _pending[0].input_tick <= server_tick:
		var admitted: Dictionary = _pending.pop_front()
		command = admitted.command
		input_tick = admitted.input_tick
		input_ack = command.sequence
		_last_command_tick = server_tick
	return {"ok":true,"error":"","command":command,"input_tick":input_tick,"clear_controls":server_tick-_last_command_tick >= LEASE_TICKS,"input_ack":input_ack}

func get_stats() -> Dictionary:
	return {"pending":_pending.size(),"input_ack":input_ack,"tail_sequence":_tail_sequence,"epoch":epoch,"generation":generation,"needs_resync":needs_resync}
