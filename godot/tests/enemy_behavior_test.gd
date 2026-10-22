extends SceneTree
## Headless real-physics AI tests. Observer invulnerability is used only in scheduling case.

var _arena: Node3D
var _player: PlayerController
var _enemy: SentinelController
var _other: SentinelController
var _coordinator: AttackCoordinator
var _checks: int = 0
var _failures: int = 0
var _states: Array[Dictionary] = []
var _attacks: Array[Dictionary] = []
var _enemy_deaths: int = 0
var _player_deaths: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _fresh(Vector3(0, 0.02, 16), Vector3(0, 0.02, 2))
	var start: Vector3 = _enemy.position
	await _ticks(90)
	_check(_enemy.brain.get_state_name() == "Idle" and _enemy.position.distance_to(start) < 0.05, "out-of-range sentinel stays Idle")
	_check(_player.health.current_health == 100, "idle sentinel cannot damage distant player")
	_player.position = Vector3(0, 0.02, 8)
	await _ticks(60)
	_check(_enemy.position.z > start.z + 2.5, "sensing player starts actual navigation chase")
	_check(Vector2(_enemy.velocity.x, _enemy.velocity.z).length() <= 3.21, "chase speed respects GDD limit")
	_check(_enemy.health.current_health == 45 and _enemy.health.max_health == 45, "shared Health initializes from sentinel Resource")

	await _fresh()
	await _until_state("Telegraph")
	_check(_enemy.brain.get_state_name() == "Telegraph", "chase enters Telegraph within trigger distance")
	_check(_enemy.global_position.distance_to(_player.global_position) <= 1.85, "attack begins within 1.8 meter trigger")
	_check(_enemy.brain.weapon.arc.visible and not _enemy.brain.hitbox.active, "warning geometry appears while damage is disabled")
	_check(_coordinator.get_active_count() == 1, "telegraph owns a close attack slot")
	await _until_action_time(0.45)
	_check(_player.health.current_health == 100, "first 0.45 seconds of warning cannot damage")
	await _until_state("Attack")
	_check(_enemy.brain.action_elapsed >= 0.54, "attack starts after full 0.55 second warning")
	_check(_player.health.current_health == 90, "sentinel strike applies ten damage")
	await _ticks(7)
	_check(_player.health.current_health == 90, "persistent hit window cannot damage twice")
	await _until_state("Recover")
	_check(not _enemy.brain.hitbox.active and not _enemy.brain.weapon.arc.visible, "recovery disables damage and warning")
	_check(_coordinator.has_slot(_enemy), "recovery retains permit until action ends")
	await _until_state("Chase")
	_check(_has_state("Telegraph") and _has_state("Attack") and _has_state("Recover"), "independent enemy FSM completes attack sequence")
	_check(_coordinator.get_active_count() == 0, "complete recovery releases permit")

	await _fresh()
	await _until_state("Telegraph")
	var locked_yaw: float = _enemy.visual.rotation.y
	_player.position.x += 4.0
	await _until_state("Recover")
	_check(_player.health.current_health == 100, "escaping telegraphed cone avoids damage")
	_check(absf(wrapf(_enemy.visual.rotation.y - locked_yaw, -PI, PI)) < 0.01, "committed strike direction cannot track fleeing player")

	await _fresh(Vector3(-5, 0.02, -2.5), Vector3(-5, 0.02, 2.5))
	var max_detour: float = 0.0
	var crossed_solid: bool = false
	for frame: int in range(400):
		max_detour = maxf(max_detour, absf(_enemy.position.x + 5.0))
		crossed_solid = crossed_solid or (absf(_enemy.position.x + 5) < 1.5 and absf(_enemy.position.z) < 1.5)
		if _enemy.brain.get_state_name() == "Telegraph":
			break
		await _ticks(1)
	_check(max_detour > 1.8, "sentinel physically walks around low block")
	_check(not crossed_solid, "navigation and body collision never cross solid obstacle")
	_check(_enemy.brain.get_state_name() == "Telegraph", "sentinel resumes melee after detour (state=%s, pos=%s, nav=%s, stuck=%d)" % [_enemy.brain.get_state_name(), _enemy.position, _enemy.brain.navigation_status, _enemy.brain.stuck_events])

	await _fresh(Vector3(5, 2.02, -4.5), Vector3(0, 0.02, -4.5))
	start = _enemy.position
	await _ticks(180)
	_check(not _has_state("Telegraph") and not _has_state("Attack"), "unreachable elevated player never causes wall/floor attacks")
	_check(_enemy.position.distance_to(start) < 0.3, "unreachable path returns to safe home")
	_check(_coordinator.get_active_count() == 0 and _player.health.current_health == 100, "unreachable target cannot consume permit or take ghost damage")
	_player.position = Vector3(0, 0.02, 0)
	await _ticks(120)
	_check(_enemy.position.z > start.z + 1.0, "AI reengages when player returns to reachable ground")

	await _fresh()
	await _ticks(45)
	_player.position = Vector3(-16, 0.02, 16)
	await _ticks(180)
	_check(_has_state("Return") and _enemy.position.distance_to(Vector3(0, 0, 3)) < 0.5, "losing sensing range returns sentinel to spawn")
	_check(_coordinator.get_active_count() == 0, "losing target releases queue and permit")

	await _fresh(Vector3(-5, 0.02, 8), Vector3(-5, 0.02, 4))
	var barrier: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4, 3, 0.5)
	shape.shape = box
	barrier.add_child(shape)
	_arena.add_child(barrier)
	barrier.position = Vector3(-5, 1.5, 5)
	await _ticks(220)
	_check(_enemy.brain.stuck_events >= 2, "dynamic unbaked blockage triggers measured stuck recovery")
	_check(_has_state("Return") and not _has_state("Attack"), "repeated navigation blockage retreats instead of attacking wall")
	_check(_coordinator.get_active_count() == 0 and _player.health.current_health == 100, "blocked sentinel cannot hold slot or hit through wall")
	barrier.queue_free()
	await _ticks(3)
	await _until_state("Telegraph", 300)
	_check(_enemy.brain.get_state_name() == "Telegraph", "AI recovers after dynamic blockage is removed")

	await _fresh()
	await _until_state("Telegraph")
	var damage: int = CombatResolver.resolve(DamageInfo.create(12, _player, 1), _enemy.get_node("Hurtbox") as Hurtbox)
	_check(damage == 12 and _enemy.health.current_health == 33, "player damage reaches shared enemy health")
	_check(_enemy.brain.get_state_name() == "Hurt", "incoming hit interrupts enemy telegraph")
	_check(not _enemy.brain.hitbox.active and not _enemy.brain.weapon.arc.visible and _coordinator.get_active_count() == 0, "Hurt immediately clears attack and permit")
	await _ticks(20)
	_check(_enemy.brain.get_state_name() == "Chase", "enemy leaves stagger and can chase again")
	_check(_player.health.current_health == 100, "cancelled warning never causes residual damage")

	await _fresh()
	await _until_state("Attack")
	var hp_after_strike: int = _player.health.current_health
	CombatResolver.resolve(DamageInfo.create(999, _player, 1), _enemy.get_node("Hurtbox") as Hurtbox)
	_check(_enemy.brain.get_state_name() == "Dead" and _enemy_deaths == 1, "lethal player hit enters Dead once")
	_check(not _enemy.brain.hitbox.active and _coordinator.get_active_count() == 0, "death during active attack cancels damage immediately")
	await _ticks(3)
	_check(_enemy.get_node("Collision").disabled and not _enemy.get_node("Hurtbox").monitorable, "dead sentinel stops blocking movement and receiving contacts")
	await _ticks(55)
	_check(_player.health.current_health == hp_after_strike, "dead sentinel cannot continue damaging")
	await _ticks(75)
	_check(not is_instance_valid(_enemy) and _enemy_deaths == 1, "corpse is cleaned up without repeating death")

	await _fresh(Vector3(0, 0.02, 8), Vector3(-3, 0.02, 3), true)
	CombatResolver.resolve(DamageInfo.create(90, null, 2), _player.get_node("Hurtbox") as Hurtbox)
	for frame: int in range(600):
		if not _player.health.is_alive():
			break
		await _ticks(1)
	_check(not _player.health.is_alive() and _player_deaths == 1, "real sentinel attack can kill player exactly once")
	await _ticks(60)
	_check(_coordinator.get_active_count() == 0, "player death releases every attack slot")
	_check(not _enemy.brain.hitbox.active and not _other.brain.hitbox.active, "player death synchronously cancels pending enemy damage")
	_check(_arena.get_node("EncounterHUD/Status").text.contains("训练失败"), "P3 status reflects player death")

	await _fresh(Vector3(0, 0.02, 8), Vector3(-3, 0.02, 3), true)
	_player.health.set_invulnerable(&"schedule_observer", true)
	var maximum_active: int = 0
	for frame: int in range(900):
		var active: int = 0
		for actor: SentinelController in [_enemy, _other]:
			if actor.brain.current_state in [EnemyBrain.State.TELEGRAPH, EnemyBrain.State.ATTACK, EnemyBrain.State.RECOVER]:
				active += 1
		maximum_active = maxi(maximum_active, active)
		await _ticks(1)
	_check(maximum_active == 1, "two sentinels never overlap attack action chains")
	var per_actor: Dictionary[int, int] = {}
	var last_frame: Dictionary[int, int] = {}
	var unique_ids: Dictionary[int, bool] = {}
	var cooldown_valid: bool = true
	for event: Dictionary in _attacks:
		var actor_id: int = event["enemy"]
		per_actor[actor_id] = per_actor.get(actor_id, 0) + 1
		if last_frame.has(actor_id):
			cooldown_valid = cooldown_valid and event["frame"] - last_frame[actor_id] >= 77
		last_frame[actor_id] = event["frame"]
		unique_ids[event["attack"]] = true
	_check(per_actor.get(_enemy.get_instance_id(), 0) >= 2 and per_actor.get(_other.get_instance_id(), 0) >= 2, "both sentinels receive multiple FIFO turns without starvation")
	_check(cooldown_valid, "each sentinel respects minimum 1.3 second attack cooldown")
	_check(unique_ids.size() == _attacks.size(), "every enemy swing has a fresh attack instance ID")
	_check(_player.health.current_health == 100, "observer protection blocks damage without changing enemy behavior")
	_arena.queue_free()
	current_scene = null
	await process_frame
	# Scene-local audio has already stopped and cleared its streams in _exit_tree.
	# Godot's audio thread releases the corresponding playback references later.
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("ENEMY BEHAVIOR RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fresh(player_position: Vector3 = Vector3(0, 0.02, 8), enemy_position: Vector3 = Vector3(0, 0.02, 3), duo: bool = false) -> void:
	if is_instance_valid(_arena):
		current_scene = null
		_arena.free()
	_states.clear()
	_attacks.clear()
	_enemy_deaths = 0
	_player_deaths = 0
	var packed: PackedScene = load("res://scenes/levels/sentinel_arena.tscn") as PackedScene
	_arena = packed.instantiate() as Node3D
	_arena.get_node("Player").position = player_position
	_arena.get_node("SentinelLeft").position = enemy_position
	root.add_child(_arena)
	current_scene = _arena
	_player = _arena.get_node("Player") as PlayerController
	_enemy = _arena.get_node("SentinelLeft") as SentinelController
	_other = _arena.get_node("SentinelRight") as SentinelController
	_coordinator = _arena.get_node("AttackCoordinator") as AttackCoordinator
	for actor: SentinelController in [_enemy, _other]:
		actor.brain.state_changed.connect(_on_state.bind(actor.get_instance_id()))
		actor.brain.attack_committed.connect(_on_attack.bind(actor.get_instance_id()))
		actor.health.died.connect(_on_enemy_death)
	_player.health.died.connect(_on_player_death)
	if not duo:
		_other.set_physics_process(false)
		await process_frame
		_other.free()
	var region: NavigationRegion3D = _arena.get_node("NavigationRegion3D") as NavigationRegion3D
	for frame: int in range(240):
		await _ticks(1)
		var map: RID = region.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map, Vector3(0, 0, 8)) == region.get_rid():
			break
	await _ticks(3)


func _ticks(count: int) -> void:
	for frame: int in range(count):
		await physics_frame
		await process_frame


func _until_state(state: String, limit: int = 240) -> void:
	for frame: int in range(limit):
		if _enemy.brain.get_state_name() == state:
			return
		await _ticks(1)
	_check(false, "bounded wait for enemy %s (actual %s, pos=%s, nav=%s)" % [state, _enemy.brain.get_state_name(), _enemy.position, _enemy.brain.navigation_status])


func _until_action_time(value: float) -> void:
	for frame: int in range(100):
		if _enemy.brain.action_elapsed + 0.00001 >= value:
			return
		await _ticks(1)
	_check(false, "bounded wait for enemy action clock")


func _has_state(state: String) -> bool:
	for event: Dictionary in _states:
		if event["state"] == state:
			return true
	return false


func _on_state(_previous: String, state: String, actor_id: int) -> void:
	_states.append({"enemy": actor_id, "state": state, "frame": Engine.get_physics_frames()})


func _on_attack(attack_id: int, actor_id: int) -> void:
	_attacks.append({"enemy": actor_id, "attack": attack_id, "frame": Engine.get_physics_frames()})


func _on_enemy_death(_info: DamageInfo) -> void:
	_enemy_deaths += 1


func _on_player_death(_info: DamageInfo) -> void:
	_player_deaths += 1


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
