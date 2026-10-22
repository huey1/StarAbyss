extends SceneTree
## Graphical 1v2 bot uses actual player Input actions. No stat overrides or invulnerability.

var _arena: Node3D
var _player: PlayerController
var _coordinator: AttackCoordinator
var _checks: int = 0
var _failures: int = 0
var _deaths: int = 0
var _maximum_action_chains: int = 0
var _saw_skill: bool = false
var _saw_normal: bool = false
var _last_buffered_id: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.grab_focus()
	await _fresh()
	_check(_arena.get_living_enemy_count() == 2, "default P3 scene starts with two living sentinels")
	_check(_player.health.current_health == 100, "P3 player starts at full GDD health")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "graphical 1v2 can capture mouse")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		printerr("FAIL: graphical 1v2 test requires a desktop")
		quit(2)
		return
	var warning: SentinelController
	for frame: int in range(300):
		for actor: Node in get_nodes_in_group("sentinels"):
			var sentinel: SentinelController = actor as SentinelController
			if sentinel.brain.current_state == EnemyBrain.State.TELEGRAPH:
				warning = sentinel
		if warning != null:
			break
		await _ticks(1)
	_check(warning != null, "visible scene reaches enemy telegraph")
	if warning != null:
		await _ticks(8)
		_check(warning.brain.weapon.arc.visible and not warning.brain.hitbox.active, "orange warning is visible before damaging frames")
		RenderingServer.force_draw()
		_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../docs/sentinel_preview.png")) == OK, "P3 telegraph preview saved")

	await _fresh()
	await _fight(1)
	_player.camera_controller.rotation.y = _player.visual.rotation.y
	_player.camera_controller.spring_arm.rotation.x = deg_to_rad(-12.0)
	await _ticks(36)
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../docs/sentinel_complete.png")) == OK, "completed 1v2 training preview saved")
	_arena.get_node("DebugHUD/Reset").pressed.emit()
	await _ticks(20)
	_bind_current()
	_player.camera_controller.set_mouse_captured(true)
	_check(_arena.get_living_enemy_count() == 2 and _player.health.current_health == 100, "training reset restores player and two real enemies")
	_check(_player.combat.skill_cooldown_remaining == 0.0 and _player.state_machine.cooldown_remaining == 0.0, "training reset clears player cooldowns")
	_check(_coordinator.get_active_count() == 0 and _coordinator.get_waiting_count() == 0, "new encounter has no stale attack permits or queue")
	await _fight(2)
	_release()
	_player.camera_controller.set_mouse_captured(false)
	_arena.queue_free()
	current_scene = null
	await process_frame
	# Match other graphical fixtures: let the engine's asynchronous audio service
	# release the last impact playback after its scene has been removed.
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("ENEMY INTEGRATION RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fight(round_number: int) -> void:
	var frames: int = 0
	for frame: int in range(900):
		frames += 1
		if _arena.get_living_enemy_count() == 0 or not _player.health.is_alive():
			break
		_bot_input()
		var active: int = 0
		for node: Node in get_nodes_in_group("sentinels"):
			var actor: SentinelController = node as SentinelController
			if actor.brain.current_state in [EnemyBrain.State.TELEGRAPH, EnemyBrain.State.ATTACK, EnemyBrain.State.RECOVER]:
				active += 1
		_maximum_action_chains = maxi(_maximum_action_chains, active)
		await _ticks(1)
	_release()
	_check(_arena.get_living_enemy_count() == 0, "round %d: input-driven player defeats both sentinels (%d frames, HP %d)" % [round_number, frames, _player.health.current_health])
	_check(_player.health.is_alive(), "round %d: player survives without health/stat cheats" % round_number)
	_check(_deaths == 2, "round %d: exactly two enemy deaths are emitted" % round_number)
	_check(_saw_skill and _saw_normal, "round %d: both skill and normal player hitboxes damage actual enemies" % round_number)
	_check(_maximum_action_chains <= 1, "round %d: actual 1v2 never overlaps enemy action chains" % round_number)
	_check(_coordinator.get_active_count() == 0 and _coordinator.get_waiting_count() == 0, "round %d: kills release all attack permits" % round_number)
	_check(_arena.get_node("EncounterHUD/Status").text.contains("训练完成"), "round %d: status reports successful 1v2 training" % round_number)
	_check(is_equal_approx(Engine.time_scale, 1.0), "round %d: battle leaves global clock unchanged" % round_number)


func _bot_input() -> void:
	Input.action_release("attack")
	Input.action_release("skill")
	var nearest: SentinelController
	var best_distance: float = INF
	for node: Node in get_nodes_in_group("sentinels"):
		var actor: SentinelController = node as SentinelController
		if not actor.health.is_alive():
			continue
		var distance: float = actor.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = actor
	if nearest == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		root.grab_focus()
		_player.camera_controller.set_mouse_captured(true)
	var toward: Vector3 = nearest.global_position - _player.global_position
	toward.y = 0.0
	toward = toward.normalized()
	# Scripted camera aim, then ordinary movement/attack input through PlayerController.
	_player.camera_controller.rotation.y = atan2(-toward.x, -toward.z)
	var state: String = _player.state_machine.get_state_name()
	if state in ["Idle", "Move"]:
		Input.action_press("move_forward")
		var facing: bool = _player.get_facing_direction().dot(toward) > 0.95
		if facing and _player.combat.skill_cooldown_remaining <= 0.0 and best_distance < 4.7:
			Input.action_press("skill")
		elif facing and best_distance < 1.85:
			Input.action_press("attack")
	else:
		Input.action_release("move_forward")
	if state == "Attack" and _player.combat.current_attack != null:
		var attack_id: int = _player.combat.hitbox.damage_info.attack_id
		if _player.combat.elapsed > _player.combat.current_attack.duration - 0.12 and attack_id != _last_buffered_id:
			_last_buffered_id = attack_id
			Input.action_press("attack")


func _fresh() -> void:
	_release()
	if is_instance_valid(_arena):
		current_scene = null
		_arena.free()
	var packed: PackedScene = load("res://scenes/levels/sentinel_arena.tscn") as PackedScene
	_arena = packed.instantiate() as Node3D
	root.add_child(_arena)
	current_scene = _arena
	_bind_current()
	_player.camera_controller.set_mouse_captured(true)
	await _ticks(20)
	_player.camera_controller.rotation = Vector3.ZERO
	_player.camera_controller.spring_arm.rotation.x = deg_to_rad(-12.0)


func _bind_current() -> void:
	_arena = current_scene as Node3D
	_player = _arena.get_node("Player") as PlayerController
	_player.camera_controller.set_process_unhandled_input(false)
	_coordinator = _arena.get_node("AttackCoordinator") as AttackCoordinator
	_deaths = 0
	_maximum_action_chains = 0
	_saw_skill = false
	_saw_normal = false
	_last_buffered_id = -1
	for node: Node in get_nodes_in_group("sentinels"):
		var actor: SentinelController = node as SentinelController
		actor.health.died.connect(_on_death)
		actor.health.damaged.connect(_on_damage)


func _on_death(_info: DamageInfo) -> void:
	_deaths += 1


func _on_damage(_amount: int, info: DamageInfo) -> void:
	_saw_skill = _saw_skill or is_equal_approx(info.base_damage, 35.0)
	_saw_normal = _saw_normal or info.base_damage in [12.0, 16.0, 24.0]


func _ticks(count: int) -> void:
	for frame: int in range(count):
		await physics_frame
		await process_frame


func _release() -> void:
	for action: String in ["move_forward", "move_backward", "move_left", "move_right", "jump", "dodge", "attack", "skill"]:
		Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
