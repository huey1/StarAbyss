extends SceneTree
## Headless transition/physics fixtures, including deliberate kills and lethal player damage.

var _run: RunManager
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	await _fresh()
	_check(_run.room_index == 0 and _run.room.get_living_enemy_count() == 2, "first fixed room spawns two sentinels")
	_check(not _run.room.gate.is_open and _run.room.gate.barrier.collision_layer == 1, "combat exit is visibly and physically locked")
	_run.room.exit_requested.emit()
	await _ticks(2)
	_check(_run.room_index == 0, "early exit request cannot skip combat")
	_check(not _run.select_blessing(&"blessing_wind"), "rewards cannot be selected during combat")
	var player: PlayerController = _run.player
	player.position = Vector3(0, 0.02, -15.1)
	await _ticks(3)
	var collision: KinematicCollision3D = player.move_and_collide(Vector3(0, 0, -2))
	_check(collision != null and collision.get_collider() == _run.room.gate.barrier, "closed gate blocks actual CharacterBody movement")
	_run.pause()
	_check(paused and _run.current_state == RunManager.State.PAUSED, "pause freezes entire encounter tree")
	var position_before: Vector3 = _run.room.enemies[0].position
	var elapsed_before: float = _run.elapsed
	player.combat.skill_cooldown_remaining = 4.0
	await _ticks(20)
	_check(_run.room.enemies[0].position == position_before and is_equal_approx(_run.elapsed, elapsed_before), "pause freezes enemy movement and run clock")
	_check(is_equal_approx(player.combat.skill_cooldown_remaining, 4.0), "pause freezes skill cooldown")
	_run.resume()
	_check(not paused and _run.current_state == RunManager.State.COMBAT, "resume returns to combat")
	player.health.receive_damage(40, DamageInfo.create(40, null, 2))
	_kill_all()
	_check(paused and _run.current_state == RunManager.State.CHOOSING, "last enemy death opens a paused reward selection")
	_check(_run.rooms_cleared == 1 and _run.kills == 2, "clear and kill counts increment exactly once")
	_check(_run.room.gate.is_open and _run.blessings.candidates.size() == 3, "clear opens exit and offers all three blessings")
	var selection_position: Vector3 = player.position
	await _ticks(20)
	_check(player.position == selection_position and is_equal_approx(player.combat.skill_cooldown_remaining, 4.0), "reward modal freezes physics and cooldown")
	_run.room.exit_requested.emit()
	await _ticks(2)
	_check(_run.room_index == 0, "open exit cannot bypass mandatory reward selection")
	_check(_run.select_blessing(&"blessing_vitality") and player.health.current_health == 80, "UI request applies vitality through manager")
	_check(not _run.select_blessing(&"blessing_flame"), "reward selection commits once")
	await _walk_through_gate()
	_check(_run.room_index == 1 and _run.room.get_living_enemy_count() == 3, "crossing actual threshold loads second room with three enemies")
	_check(player.health.current_health == 80 and _run.blessings.acquired.size() == 1, "current HP and blessings survive room change")
	_check(player.combat.skill_cooldown_remaining > 3.0, "room change preserves ongoing cooldown")
	_check(_run.room.coordinator.get_active_count() == 0 and _run.room.coordinator.get_waiting_count() == 0, "room change starts clean attack coordination")
	_check(not _run.room.gate.is_open, "second room closes its own exit")
	_kill_all()
	_check(player.health.current_health == 95, "three real enemy death signals each heal 5 HP with vitality")
	_check(_run.kills == 5 and _run.rooms_cleared == 2, "second clear totals five kills and two ordinary rooms")
	_check(_run.blessings.candidates.size() == 2 and not _run.blessings.candidates.has(_run.blessings.acquired[0]), "second modal excludes owned blessing")
	_check(_run.select_blessing(&"blessing_wind"), "second reward selection works")
	await _walk_through_gate()
	_check(_run.room_index == 2 and _run.room.definition.boss_staging, "second exit enters fixed third room")
	_check(_run.current_state == RunManager.State.STAGE_COMPLETE and paused, "P4 ends at a paused stage summary")
	_check(_run.room.enemies.is_empty() and _run.rooms_cleared == 2, "Boss staging never counts as a cleared Boss encounter")
	_run.restart()
	await _ticks(12)
	_run = current_scene as RunManager
	_disable_external_mouse()
	_check(not paused and _run.room_index == 0 and _run.rooms_cleared == 0 and _run.kills == 0, "restart restores room and counters")
	_check(_run.player.health.current_health == 100 and _run.blessings.acquired.is_empty(), "restart restores full HP and clears blessings")
	_check(_run.player.combat.skill_cooldown_remaining == 0.0 and _run.player.state_machine.cooldown_remaining == 0.0, "restart clears both cooldowns")
	_check(is_equal_approx(_run.player.combat.normal_attack_multiplier, 1.0) and is_equal_approx(_run.player.state_machine.get_dodge_cooldown_duration(), 1.2), "restart removes all runtime blessing effects")
	_run.player.health.receive_damage(100, DamageInfo.create(100, null, 2))
	_check(_run.current_state == RunManager.State.FAILED and paused, "lethal damage produces paused failure summary")
	_check(_run.player.state_machine.current_state == PlayerStateMachine.State.DEAD, "player FSM remains sole death-state owner")
	for sentinel: SentinelController in _run.room.enemies:
		_check(sentinel.brain.hitbox.damage_info == null and not sentinel.brain.hitbox.active, "player death cancels pending enemy attack")
	_run.resume()
	_check(_run.current_state == RunManager.State.FAILED and paused, "resume cannot escape failure modal")
	_run.restart()
	await _ticks(12)
	_run = current_scene as RunManager
	_disable_external_mouse()
	_check(_run.player.health.current_health == 100 and _run.room.get_living_enemy_count() == 2, "failure restart creates a fresh encounter")
	_run.free()
	current_scene = null
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("ROOM FLOW RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fresh() -> void:
	_run = (load("res://scenes/levels/room_run.tscn") as PackedScene).instantiate() as RunManager
	_run.run_seed = 2468
	root.add_child(_run)
	current_scene = _run
	_disable_external_mouse()
	await _ticks(12)


func _disable_external_mouse() -> void:
	_run.player.camera_controller.set_process_unhandled_input(false)


func _kill_all() -> void:
	for sentinel: SentinelController in _run.room.enemies:
		sentinel.health.receive_damage(45, DamageInfo.create(45, _run.player, 1))


func _walk_through_gate() -> void:
	# Place at the door, then use real CharacterBody motion into its Area3D threshold.
	_run.player.position = Vector3(0, 0.02, -15)
	await _ticks(2)
	var collision: KinematicCollision3D = _run.player.move_and_collide(Vector3(0, 0, -1.9))
	_check(collision == null, "open gate no longer blocks physical traversal")
	await _ticks(8)


func _ticks(count: int) -> void:
	for frame: int in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
