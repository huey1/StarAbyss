extends SceneTree
## M1 tempo probe (measurement only, NOT a registered verify.py check).
##
## Purpose: measure the real, emergent attack cadence of a room from the shipped AI, instead of
## predicting it from `handoff_delay`. The player stands still and is made invulnerable so the
## measurement is about enemy scheduling, not about bot skill.
##
## Reports, per room: permit budget, number of telegraph starts observed in a fixed simulated
## window, the gap between consecutive telegraph starts (any attacker), and the maximum number
## of permit holders seen at once.
##
## Run:
##   Godot_..._console.exe --headless --path godot --fixed-fps 60 --audio-driver Dummy `
##     --script res://tests/m1_tempo_probe.gd

const WINDOW_SECONDS: float = 60.0
const SETTLE_FRAMES: int = 90

var _run: RunManager
var _prev_states: Dictionary[int, int] = {}
var _starts: Array[int] = []
var _frame: int = 0
var _max_holders: int = 0


func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	await _measure_room(0, "room_01")
	await _measure_room(1, "room_02")
	quit(0)


func _measure_room(room_index: int, label: String) -> void:
	await _fresh(room_index)
	var coordinator: AttackCoordinator = _run.room.coordinator
	_prev_states.clear()
	_starts.clear()
	_max_holders = 0
	_frame = 0
	for enemy: SentinelController in _run.room.enemies:
		_prev_states[enemy.get_instance_id()] = enemy.brain.current_state

	# Let the sentinels walk in from their spawns before the window starts.
	for index: int in range(SETTLE_FRAMES):
		await _step()

	var window_frames: int = int(WINDOW_SECONDS * 60.0)
	for index: int in range(window_frames):
		await _step()

	var gaps: Array[float] = []
	for index: int in range(1, _starts.size()):
		gaps.append(float(_starts[index] - _starts[index - 1]) / 60.0)
	print("M1 TEMPO %s max_attackers=%d telegraph_starts=%d window=%.1fs max_concurrent_holders=%d" % [
		label, coordinator.max_attackers, _starts.size(), WINDOW_SECONDS, _max_holders])
	if not gaps.is_empty():
		var sorted_gaps: Array[float] = gaps.duplicate()
		sorted_gaps.sort()
		var total: float = 0.0
		for gap: float in sorted_gaps:
			total += gap
		print("M1 TEMPO %s gap_mean=%.2fs gap_median=%.2fs gap_p90=%.2fs gap_min=%.2fs gap_max=%.2fs" % [
			label, total / float(sorted_gaps.size()),
			sorted_gaps[sorted_gaps.size() / 2],
			sorted_gaps[mini(sorted_gaps.size() - 1, int(floor(float(sorted_gaps.size()) * 0.9)))],
			sorted_gaps[0], sorted_gaps[sorted_gaps.size() - 1]])
		var head: String = ""
		for index: int in range(mini(12, sorted_gaps.size())):
			head += "%.2f " % sorted_gaps[index]
		print("M1 TEMPO %s first_gaps=%s" % [label, head.strip_edges()])
	else:
		print("M1 TEMPO %s no telegraph observed" % label)
	print("M1 TEMPO %s player_hp=%d alive=%s" % [label, _run.player.health.current_health, _run.player.health.is_alive()])
	await _teardown()


func _step() -> void:
	await physics_frame
	await process_frame
	_frame += 1
	# The player never attacks: it only stands there, so every telegraph is the AI's choice.
	_max_holders = maxi(_max_holders, _run.room.coordinator.get_active_count())
	for enemy: SentinelController in _run.room.enemies:
		if not is_instance_valid(enemy):
			continue
		var id: int = enemy.get_instance_id()
		var now: int = enemy.brain.current_state
		var before: int = _prev_states.get(id, now)
		if before != EnemyBrain.State.TELEGRAPH and now == EnemyBrain.State.TELEGRAPH:
			_starts.append(_frame)
		_prev_states[id] = now


func _fresh(room_index: int) -> void:
	_run = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	_run.run_seed = 2468
	root.add_child(_run)
	current_scene = _run
	_run.player.camera_controller.set_process_unhandled_input(false)
	for index: int in range(12):
		await _step()
	if room_index > 0:
		_run.room_index = room_index
		_run._set_state(RunManager.State.TRANSITION)
		_run._advance_room()
		for index: int in range(20):
			await _step()
	_run.player.health.set_invulnerable(&"probe", true)


func _teardown() -> void:
	var audio: Node = _run.find_child("RunAudio", true, false)
	if audio != null and audio.has_method("stop_all"):
		audio.stop_all()
	current_scene = null
	_run.queue_free()
	var deadline: int = Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
		await process_frame
