extends SceneTree
## Deterministic Boss-only fixtures. Explicit placement/damage is separate from full-run play.

var _run: RunManager
var _boss: SentinelController
var _brain: GuardianBrain
var _player: PlayerController
var _checks: int = 0
var _failures: int = 0
var _commits: Array[AttackDefinition] = []
var _attack_ids: Array[int] = []


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	var settings: GuardianSettings = load("res://resources/boss/default_guardian.tres") as GuardianSettings
	_check(settings.max_health == 350 and is_equal_approx(settings.move_speed, 2.6), "guardian GDD HP and speed")
	_check(settings.attack.damage == 20 and is_equal_approx(settings.attack.hit_start, 0.8), "sweep GDD damage and warning")
	_check(settings.shockwave.damage == 25 and is_equal_approx(settings.shockwave.hit_start, 1.2), "shockwave GDD damage and warning")
	_check(is_equal_approx(settings.shockwave.arc_degrees, 360) and is_equal_approx(settings.shockwave.reach, 4.2), "shockwave is a full ground circle")
	_check(settings.minimum_attack_gap == 1.6 and settings.maximum_attack_gap == 2.4, "GDD recovery-to-next-action gap range")
	for shockwave: bool in [false, true]:
		await _fresh(shockwave)
		var initial_position: Vector3 = _boss.position
		await _wait_telegraph()
		var attack: AttackDefinition = _brain.get_attack_definition()
		_check(_boss.position.distance_to(initial_position) > 2, "guardian actually pursues before selecting move")
		_check(attack == (settings.shockwave if shockwave else settings.attack), "seed selects expected opening move")
		_check(_brain.weapon.arc.visible and not _brain.hitbox.active, "warning is visible before hitbox activation")
		_check(_brain.last_attack_gap >= 1.6 and _brain.last_attack_gap <= 2.4, "selected post-recovery gap is within GDD bounds")
		_check(_brain.weapon.arc.mesh != null and _brain.hitbox.definition == attack, "visual and hitbox share selected attack definition")
		var hp_before: int = _player.health.current_health
		await _ticks(int(attack.hit_start * 60) - 3)
		_check(_player.health.current_health == hp_before, "full warning precedes any damage")
		await _ticks(22)
		_check(_player.health.current_health == hp_before - int(attack.damage), "active window applies exact move damage once")
		await _ticks(16)
		_check(_player.health.current_health == hp_before - int(attack.damage), "recovery never repeats the same attack damage")

	# Escaping either warning must work without any invulnerability override.
	for shockwave: bool in [false, true]:
		await _fresh(shockwave)
		await _wait_telegraph()
		var attack: AttackDefinition = _brain.get_attack_definition()
		var locked_yaw: float = _boss.visual.rotation.y
		_player.position = _boss.position + (Vector3.RIGHT * 5.5 if shockwave else Vector3.BACK * -2.0)
		await _ticks(int((attack.hit_end + 0.08) * 60))
		_check(_player.health.current_health == 100, "leaving warning avoids %s without i-frames" % attack.display_name)
		_check(is_equal_approx(_boss.visual.rotation.y, locked_yaw), "guardian never tracks target rotation during committed move")

	await _fresh(true)
	await _wait_telegraph()
	_player.position = _boss.position + Vector3.BACK * -3.5
	await _ticks(86)
	_check(_player.health.current_health == 75, "circular shockwave also hits behind guardian")

	await _fresh(false)
	await _wait_telegraph()
	_boss.health.receive_damage(12, DamageInfo.create(12, _player, 1))
	_check(_boss.health.current_health == 338 and _brain.current_state == EnemyBrain.State.TELEGRAPH, "ordinary damage applies without indefinitely staggering Boss")
	_player.health.set_invulnerable(&"observer", true)
	_commits.clear()
	_attack_ids.clear()
	_brain.attack_committed.connect(_record_commit)
	for frame: int in range(1800):
		await _ticks(1)
		if _commits.size() >= 3:
			break
	_check(_commits.size() == 3 and _commits[0] != _commits[1] and _commits[1] != _commits[2], "automatic FSM alternates both moves over multiple cycles")
	_check(_attack_ids.size() == 3 and _attack_ids[0] != _attack_ids[1] and _attack_ids[1] != _attack_ids[2], "each Boss action gets a unique shared damage ID")

	await _fresh(false)
	await _wait_telegraph()
	# A static low block blocks a real sampled attack, even in its nominal radius.
	_boss.position = Vector3(-5, 0.02, 1.3)
	_player.position = Vector3(-5, 0.02, -1.3)
	_boss.visual.rotation.y = 0
	await _ticks(68)
	_check(_player.health.current_health == 100, "Boss attack cannot hit through static World obstacle")

	await _fresh(true)
	await _wait_telegraph()
	_player.health.receive_damage(40, DamageInfo.create(40, null, 2))
	_run.blessings.offer()
	_run.blessings.choose(&"blessing_vitality")
	var hp_before_boss_death: int = _player.health.current_health
	_boss.health.receive_damage(350, DamageInfo.create(350, _player, 1))
	_check(_brain.current_state == EnemyBrain.State.DEAD and _brain.hitbox.damage_info == null and not _brain.hitbox.active, "Boss death immediately clears committed damage")
	_check(not _brain.weapon.arc.visible and _run.room.coordinator.get_active_count() == 0, "Boss death clears warning and permit")
	_check(_run.current_state == RunManager.State.WON and paused, "Boss death produces frozen victory")
	_check(_run.kills == 1 and _run.rooms_cleared == 1, "Boss-only fixture counts one kill and one clear")
	_check(_player.health.current_health == hp_before_boss_death and _run.blessings.candidates.is_empty(), "Boss grants neither ordinary-kill healing nor a third reward")
	_boss.health.receive_damage(350, DamageInfo.create(350, _player, 1))
	_check(_run.kills == 1 and _run.rooms_cleared == 1, "duplicate death cannot settle twice")
	_run.resume()
	_check(paused and _run.current_state == RunManager.State.WON, "Esc resume cannot escape victory")
	_run.return_to_menu()
	await _ticks(8)
	_check(current_scene is MainMenu and not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "victory returns to unpaused mouse-visible menu")
	var menu: MainMenu = current_scene as MainMenu
	menu.start_game()
	menu.start_game()
	await _ticks(12)
	_run = current_scene as RunManager
	_check(_run != null and _run.room_index == 0 and _run.player.health.current_health == 100 and _run.kills == 0, "double-click start still creates one clean first-room run")
	_check(_run.blessings.acquired.is_empty() and _run.player.combat.skill_cooldown_remaining == 0, "menu restart carries no effects or cooldown")
	await _fresh(true)
	await _wait_telegraph()
	_player.health.receive_damage(100, DamageInfo.create(100, null, 2))
	_check(_run.current_state == RunManager.State.FAILED and paused, "player death during Boss warning produces failure")
	_check(_brain.hitbox.damage_info == null and not _brain.weapon.arc.visible, "player death cancels Boss warning and damage")
	_boss.health.receive_damage(350, DamageInfo.create(350, _player, 1))
	_check(_run.current_state == RunManager.State.FAILED and _run.rooms_cleared == 0, "late Boss death cannot overwrite player failure")
	_run.return_to_menu()
	await _ticks(8)
	_check(current_scene is MainMenu and not paused, "failure also returns cleanly to menu")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("GUARDIAN BEHAVIOR RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fresh(shockwave: bool) -> void:
	if current_scene != null:
		current_scene.free()
		current_scene = null
	_run = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	_run.room_index = 2
	var probe: RandomNumberGenerator = RandomNumberGenerator.new()
	for candidate: int in range(100):
		probe.seed = candidate
		if (probe.randi_range(0, 1) == 1) == shockwave:
			_run.run_seed = candidate
			break
	root.add_child(_run)
	current_scene = _run
	_player = _run.player
	_player.camera_controller.set_process_unhandled_input(false)
	_boss = _run.room.boss
	_brain = _boss.brain as GuardianBrain
	await _ticks(12)


func _wait_telegraph() -> void:
	for frame: int in range(600):
		if _brain.current_state == EnemyBrain.State.TELEGRAPH:
			return
		await _ticks(1)
	_check(false, "Boss reaches telegraph within bounded chase")


func _record_commit(id: int) -> void:
	_commits.append(_brain.get_attack_definition())
	_attack_ids.append(id)


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
