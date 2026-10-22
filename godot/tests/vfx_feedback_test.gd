extends SceneTree
## Signal/lifecycle fixture. Direct damage and clock sampling are not an unaided run.

var _run: RunManager
var _player: PlayerController
var _enemy: SentinelController
var _effects: CombatVFX
var _checks: int = 0
var _failures: int = 0
var _terminal_bursts: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.grab_focus()
	_run = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	root.add_child(_run)
	current_scene = _run
	await _ticks(4)
	_player = _run.player
	_player.set_physics_process(false)
	_player.camera_controller.set_process_unhandled_input(false)
	for actor: SentinelController in _run.room.enemies:
		actor.set_physics_process(false)
	_enemy = _run.room.enemies[0]
	_effects = _enemy.get_node("VFX") as CombatVFX
	_effects.burst_emitted.connect(_on_burst)
	_check(_effects.active_effect_count() == 0, "no cosmetic fragments exist before damage")
	_check(_effects.find_children("*", "CollisionObject3D", true, false).is_empty(), "VFX component creates no physics bodies")
	var weapon: WeaponVisual = _player.combat.weapon
	var trail: MeshInstance3D = weapon.get_node("ActionTrail") as MeshInstance3D
	var rim: MeshInstance3D = weapon.get_node("RangeRim") as MeshInstance3D
	var ring: MeshInstance3D = weapon.get_node("ShockRing") as MeshInstance3D
	_player.combat.start_attack()
	var attack: AttackDefinition = _player.combat.current_attack
	_check(weapon.arc.visible and rim.visible and not trail.visible and not ring.visible, "windup shows exact ground warning without an active slash")
	_player.combat.advance_action(attack.hit_start)
	_check(trail.visible and weapon.arc.visible and not ring.visible, "normal slash appears only after the real hit boundary")
	_check(_within_sector(trail, attack), "normal slash mesh stays inside configured reach and sector")
	_player.combat.interrupt()
	_check(not weapon.arc.visible and not rim.visible and not trail.visible and not ring.visible, "interrupt removes every action effect immediately")
	_player.combat.start_skill()
	attack = _player.combat.current_attack
	_player.combat.advance_action(attack.hit_start)
	_check(trail.visible and _within_sector(trail, attack), "skill crescent matches the actual five-meter seventy-degree fan")
	var outer_reach: float = _maximum_radius(trail)
	_check(absf(outer_reach - 5.0) < 0.001, "skill energy edge reaches the actual five-meter boundary")
	_player.combat.interrupt()
	var shockwave: AttackDefinition = load("res://resources/boss/guardian_shockwave.tres") as AttackDefinition
	weapon.begin(shockwave)
	weapon.pose(shockwave, shockwave.hit_start - 0.01, false)
	_check(not ring.visible and weapon.arc.visible, "shockwave keeps the complete warning before its damaging moment")
	weapon.pose(shockwave, shockwave.hit_start, true)
	_check(ring.visible and not trail.visible and absf(_maximum_radius(ring) - shockwave.reach) < 0.001, "active shockwave edge appears across the full configured radius at once")
	weapon.clear_pose()
	weapon.effect_strength = 0.0
	weapon.begin(shockwave)
	weapon.pose(shockwave, shockwave.hit_start, true)
	_check(weapon.arc.visible and not ring.visible and not rim.visible, "zero extra-effect strength still preserves the gameplay danger fan")
	weapon.clear_pose()
	weapon.effect_strength = 0.7
	var before_hp: int = _enemy.health.current_health
	_enemy.health.receive_damage(1, DamageInfo.create(1, _player, 1))
	_check(_enemy.health.current_health == before_hp - 1 and _effects.active_effect_count() > 0, "accepted Health damage emits sparks without extra damage")
	var first_spark: Node3D = _effects.get_child(0) as Node3D
	var spark_position: Vector3 = first_spark.global_position
	paused = true
	_effects._physics_process(0.1)
	_check(first_spark.global_position.is_equal_approx(spark_position), "living impact fragments freeze with game pause")
	paused = false
	_enemy.feedback.start_hit_stop(0.2)
	_effects._physics_process(0.1)
	_check(first_spark.global_position.is_equal_approx(spark_position), "living impact fragments respect actor-local hit stop")
	_enemy.feedback.freeze_remaining = 0.0
	_effects._physics_process(0.3)
	_check(_effects.active_effect_count() == 0, "impact fragments expire within their short lifetime")
	_effects.max_fragments = 8
	for index: int in range(8):
		_enemy.health.receive_damage(1, DamageInfo.create(1, _player, 1))
	_check(_effects.active_effect_count() <= 8 and _effects.get_child_count() <= 8, "repeated hits cannot exceed the fragment/node cap")
	var lethal: DamageInfo = DamageInfo.create(100, _player, 1)
	_enemy.health.receive_damage(100, lethal)
	_check(_terminal_bursts == 1 and _effects.active_effect_count() <= 8, "one death replaces old sparks with a bounded crystal burst")
	_enemy.health.receive_damage(100, lethal)
	_check(_terminal_bursts == 1, "duplicate or late damage cannot emit another terminal burst")
	paused = true
	_effects._physics_process(0.8)
	_check(_effects.active_effect_count() == 0, "terminal fragments clean up after their finite lifetime even behind paused results")
	paused = false
	var player_effects: CombatVFX = _player.get_node("VFX") as CombatVFX
	player_effects.effect_strength = 0.0
	_player.health.receive_damage(1, DamageInfo.create(1, _enemy, 2))
	_check(player_effects.active_effect_count() == 0 and _player.health.current_health == 99, "disabled cosmetics preserve normal accepted gameplay damage")
	player_effects.effect_strength = 0.7
	_player.health.protection_remaining = 0.0
	_player.health.receive_damage(1, DamageInfo.create(1, _enemy, 2))
	var retained: WeakRef = weakref(player_effects.get_child(0))
	if DisplayServer.get_name() != "headless":
		await _render_preview()
	paused = false
	_run.queue_free()
	current_scene = null
	await process_frame
	_check(retained.get_ref() == null, "scene teardown frees all remaining cosmetic nodes")
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("VFX FEEDBACK RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _render_preview() -> void:
	root.size = Vector2i(1280, 720)
	_player.combat.start_skill()
	_player.combat.advance_action(_player.combat.current_attack.hit_start + 0.04)
	var view: ActorPresentation = _player.get_node("Visual/ActorPresentation") as ActorPresentation
	view._physics_process(0.0)
	RenderingServer.force_draw(false)
	await process_frame
	var frame: Image = root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "Forward+ draws a real active VFX frame")
	frame.save_png(ProjectSettings.globalize_path("res://").path_join("../docs/p7_vfx_preview.png"))
	_player.combat.interrupt()


func _within_sector(instance: MeshInstance3D, attack: AttackDefinition) -> bool:
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		var radius: float = Vector2(vertex.x, vertex.z).length()
		var angle: float = absf(rad_to_deg(atan2(vertex.x, -vertex.z)))
		if radius > attack.reach + 0.001 or angle > attack.arc_degrees * 0.5 + 0.01:
			return false
	return true


func _maximum_radius(instance: MeshInstance3D) -> float:
	var maximum: float = 0.0
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		maximum = maxf(maximum, Vector2(vertex.x, vertex.z).length())
	return maximum


func _on_burst(_count: int, terminal: bool) -> void:
	if terminal:
		_terminal_bursts += 1


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
