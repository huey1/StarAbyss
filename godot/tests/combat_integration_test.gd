extends SceneTree
## Real main scene, real Input actions, physical Area contacts, and independent fresh fixtures.

var _arena: Node3D
var _player: PlayerController
var _targets: Array[Node3D] = []
var _checks: int = 0
var _failures: int = 0
var _actions: Array[int] = []
var _deaths: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _fresh()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		printerr("FAIL: combat input integration requires a graphical desktop")
		quit(2)
		return
	_targets[0].position = Vector3(-0.55, 0, 6.4)
	_targets[1].position = Vector3(0.55, 0, 6.4)
	await _ticks(3)
	await _press("attack")
	_check(_state() == "Attack", "left attack enters Attack")
	await _elapsed(0.12)
	_check(_hp(0) == 45 and _hp(1) == 45, "windup has no damage")
	await _elapsed(0.21)
	_check(_hp(0) == 33 and _hp(1) == 33, "one slash damages multiple targets for 12")
	_check(_player.feedback.freeze_remaining > 0.0 or _player.combat.elapsed < 0.24, "confirmed impact engages local hit stop")
	await _elapsed(0.37)
	_check(_hp(0) == 33 and _hp(1) == 33, "persistent overlap cannot hit twice")
	_check(not _player.combat.hitbox.active, "hitbox disables during recovery")
	await _press("attack")
	await _wait_combo(1)
	_check(_player.combat.combo_index == 1, "late buffered input links attack two")
	await _elapsed(0.44)
	_check(_hp(0) == 17 and _hp(1) == 17, "second slash uses 16 damage")
	await _press("attack")
	await _wait_combo(2)
	_check(_player.combat.combo_index == 2, "second buffer links attack three")
	await _elapsed(0.50)
	_check(_hp(0) == 0 and _hp(1) == 0, "third slash uses 24 damage and kills both targets")
	_check(_actions == [1, 2, 3], "combo signal reports exactly three actions")
	await _ticks(80)
	_check(_player.combat.combo_index == -1, "combo resets after 0.9 seconds idle")
	await _press("attack")
	_check(_player.combat.combo_index == 0, "new chain restarts at attack one")

	await _fresh()
	await _press("attack")
	await _elapsed(0.04)
	await _press("attack")
	await _ticks(45)
	_check(_actions == [1] and _state() == "Idle", "early buffer expires instead of queuing forever")
	await _ticks(60)
	Input.action_press("attack")
	await _ticks(90)
	Input.action_release("attack")
	_check(_actions == [1, 1], "holding attack does not auto-repeat")

	await _fresh()
	await _press("attack")
	await _elapsed(0.05)
	await _press("dodge")
	_check(_state() == "Attack", "startup cannot be cancelled with dodge")
	await _elapsed(0.32)
	await _press("dodge")
	_check(_state() == "Dodge", "recovery cancel window permits dodge")
	_check(_player.combat.current_attack == null and not _player.combat.hitbox.active, "cancel clears pending attack and hitbox")
	var cooldown_at_start: float = _player.state_machine.cooldown_remaining
	await _press("dodge")
	_check(_player.state_machine.cooldown_remaining < cooldown_at_start, "repeated Shift cannot reset/bypass cooldown")

	await _fresh()
	_targets[0].position = Vector3(0, 0, 3.5)
	_targets[1].position = Vector3(3.0, 0, 4.5)
	_targets[2].position = Vector3(0, 0, 10)
	await _ticks(3)
	await _press("skill")
	_check(_state() == "Skill" and _player.combat.skill_cooldown_remaining > 7.9, "E starts skill and eight-second cooldown")
	await _press("attack")
	await _press("dodge")
	_check(_state() == "Skill", "normal attack and dodge cannot interrupt skill")
	await _elapsed(0.18)
	_check(_hp(0) == 45, "skill telegraph precedes damage")
	await _elapsed(0.46)
	_check(_hp(0) == 10, "star blade deals exactly 35 inside five-meter fan")
	_check(_hp(1) == 45 and _hp(2) == 45, "skill rejects targets outside 70-degree fan or behind player")
	await _ticks(30)
	await _press("skill")
	_check(_state() != "Skill", "skill cooldown blocks rapid recast")
	await _ticks(480)
	await _press("skill")
	_check(_state() == "Skill", "skill can be cast when cooldown expires (state=%s, floor=%s, cd=%.3f, captured=%s)" % [_state(), _player.is_on_floor(), _player.combat.skill_cooldown_remaining, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED])

	await _fresh()
	_player.position = Vector3(0, 0.02, -17.5)
	_targets[0].position = Vector3(0, 0, -20.5)
	await _ticks(5)
	await _press("skill")
	await _elapsed(0.46)
	_check(_hp(0) == 45, "world wall blocks skill damage through it")

	for time: float in [0.05, 0.10, 0.20, 0.30, 0.40]:
		await _fresh()
		await _press("dodge")
		await _dodge_elapsed(time)
		var should_block: bool = time >= 0.10 and time < 0.30
		var amount: int = _damage_player(10)
		_check(amount == (0 if should_block else 10), "dodge invulnerability boundary t=%.2f" % time)
		_check(_state() == ("Dodge" if should_block else "Hurt"), "blocked dodge hit has no stagger t=%.2f" % time)

	await _fresh()
	_player.position = Vector3(-11, 0.02, 5)
	await _ticks(10)
	_check(_player.health.current_health == 100, "practice hazard warns before damaging player")
	await _ticks(35)
	_check(_player.health.current_health == 90, "visible hazard pulse damages player once for ten")
	await _ticks(8)
	_check(_player.health.current_health == 90, "remaining hazard contact cannot repeat pulse damage")

	await _fresh()
	await _press("attack")
	_check(_damage_player(10) == 10 and _state() == "Hurt", "incoming damage interrupts normal attack with Hurt")
	_check(not _player.combat.hitbox.active and _player.combat.current_attack == null, "Hurt cancels all outgoing hit windows")
	await _press("dodge")
	_check(_state() == "Hurt", "stagger forbids dodge")
	_check(_damage_player(10) == 0, "post-hit protection prevents repeated damage")
	await _ticks(20)
	_check(_state() == "Idle", "independent stagger timer recovers to Idle")
	_check(_damage_player(10) == 0, "post-hit protection outlasts stagger")
	await _ticks(15)
	_check(_damage_player(10) == 10, "damage is accepted after 0.5 second protection ends")
	_check(_arena.get_node("DebugHUD/Panel/Margin/Rows/Health").text.contains("80 / 100"), "HUD reflects real HP changes")

	await _fresh()
	await _press("skill")
	_check(_damage_player(10) == 10 and _state() == "Skill", "skill takes damage but resists stagger cancellation")
	await _ticks(35)
	_check(_damage_player(999) == 90 and _state() == "Dead", "death interrupts skill immediately")
	_check(_deaths == 1 and _player.combat.current_attack == null and not _player.combat.hitbox.active, "death stops pending damage exactly once")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "death releases mouse for practice reset")
	_player.camera_controller.set_mouse_captured(true)
	var dead_position: Vector3 = _player.position
	for action: String in ["attack", "skill", "dodge", "jump", "move_forward"]:
		Input.action_press(action)
	await _ticks(40)
	_release()
	_check(_state() == "Dead" and _player.position.distance_to(dead_position) < 0.01, "Dead rejects all movement and battle inputs")
	_check(_damage_player(999) == 0 and _deaths == 1, "extra hits cannot repeat death")
	_check(is_equal_approx(Engine.time_scale, 1.0), "hit stop never changes global time scale")
	_arena.get_node("DebugHUD/Reset").pressed.emit()
	await _ticks(25)
	_arena = current_scene as Node3D
	_player = _arena.get_node("Player") as PlayerController
	_player.camera_controller.set_process_unhandled_input(false)
	_check(_player.health.current_health == 100 and _state() == "Idle", "reset button restores living player")
	_check(_player.combat.skill_cooldown_remaining == 0.0 and _player.state_machine.cooldown_remaining == 0.0, "reset clears all combat cooldowns")
	_check(_arena.get_node("TargetCenter/Health").current_health == 45, "reset restores target HP")
	_player.camera_controller.rotation = Vector3.ZERO
	_player.camera_controller.spring_arm.rotation.x = deg_to_rad(-12.0)
	await _ticks(3)
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../docs/preview.png")) == OK, "updated P2 scene preview saved")
	await _press("skill")
	await _elapsed(0.30)
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../docs/combat_preview.png")) == OK, "active skill preview saved")
	_release()
	_player.camera_controller.set_mouse_captured(false)
	_arena.queue_free()
	current_scene = null
	await process_frame
	# Let stopped impact/skill playbacks be released by Godot's audio thread.
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("COMBAT INTEGRATION RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fresh() -> void:
	root.grab_focus()
	_release()
	if is_instance_valid(_arena):
		current_scene = null
		_arena.free()
	var packed: PackedScene = load("res://scenes/levels/test_arena.tscn") as PackedScene
	_arena = packed.instantiate() as Node3D
	root.add_child(_arena)
	current_scene = _arena
	_player = _arena.get_node("Player") as PlayerController
	_player.camera_controller.set_process_unhandled_input(false)
	_targets = [_arena.get_node("TargetCenter"), _arena.get_node("TargetLeft"), _arena.get_node("TargetRight")]
	for index: int in range(_targets.size()):
		_targets[index].position = Vector3(12 + index * 2, 0, -12)
	_actions.clear()
	_deaths = 0
	_player.combat.action_started.connect(_on_action)
	_player.health.died.connect(_on_death)
	_player.camera_controller.set_mouse_captured(true)
	await _ticks(20)
	_player.camera_controller.rotation = Vector3.ZERO
	_player.camera_controller.spring_arm.rotation.x = deg_to_rad(-12.0)


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _press(action: String) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _player.health.is_alive():
		root.grab_focus()
		_player.camera_controller.set_mouse_captured(true)
		await _ticks(2)
	Input.action_press(action)
	await _ticks(1)
	Input.action_release(action)


func _elapsed(value: float) -> void:
	for index: int in range(150):
		if _player.combat.current_attack == null or _player.combat.elapsed + 0.00001 >= value:
			return
		await _ticks(1)
	_check(false, "bounded wait for action time %.2f" % value)


func _dodge_elapsed(value: float) -> void:
	for index: int in range(90):
		if _player.state_machine.dodge_elapsed + 0.00001 >= value:
			return
		await _ticks(1)
	_check(false, "bounded wait for dodge time")


func _wait_combo(index: int) -> void:
	for frame: int in range(90):
		if _player.combat.combo_index == index:
			return
		await _ticks(1)
	_check(false, "bounded wait for combo step")


func _damage_player(amount: float) -> int:
	return CombatResolver.resolve(DamageInfo.create(amount, null, 2), _player.get_node("Hurtbox") as Hurtbox)


func _hp(index: int) -> int:
	return (_targets[index].get_node("Health") as HealthComponent).current_health


func _state() -> String:
	return _player.state_machine.get_state_name()


func _release() -> void:
	for action: String in ["move_forward", "move_backward", "move_left", "move_right", "jump", "dodge", "attack", "skill"]:
		Input.action_release(action)


func _on_action(_action_name: String, combo_step: int) -> void:
	_actions.append(combo_step)


func _on_death(_info: DamageInfo) -> void:
	_deaths += 1


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
