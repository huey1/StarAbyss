extends SceneTree
## Runs the real main scene and injects Input actions. No gameplay test hooks.
## Exit code is nonzero on any failed assertion; bounded by verify.ps1 timeout.

var _player: PlayerController
var _arena: Node3D
var _failures: int = 0
var _checks: int = 0
var _states: Array[String] = []
var _telemetry_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.grab_focus()
	var packed: PackedScene = load("res://scenes/levels/test_arena.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	_arena = packed.instantiate() as Node3D
	root.add_child(_arena)
	current_scene = _arena
	_player = _arena.get_node("Player") as PlayerController
	# Movement fixtures own yaw; native pointer warps must not steer synthetic WASD.
	_player.camera_controller.set_process_unhandled_input(false)
	_player.state_machine.state_changed.connect(_record_state)
	_player.telemetry_updated.connect(_record_telemetry)
	_player.camera_controller.set_mouse_captured(true)
	await _ticks(30)
	# Fast fixed-fps fixtures may reach input checks before Windows finishes the
	# preceding test window's focus handoff. Give native messages actual time,
	# then request focus/capture again without changing production focus behavior.
	var focus_deadline: int = Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < focus_deadline:
		await process_frame
	root.grab_focus()
	_player.camera_controller.set_mouse_captured(true)
	await _ticks(3)
	_check(_player.is_on_floor(), "spawn settles on ground")
	_check(_player.state_machine.get_state_name() == "Idle", "settled state is Idle")
	_check(_telemetry_count > 0, "telemetry signal reaches listeners")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse can be captured")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		printerr("Input integration tests require a graphical display; headless mouse capture is unavailable.")
		quit(2)
		return
	_check(_arena.get_node("DebugHUD/Panel/Margin/Rows/State").text.contains("Idle"), "HUD receives state telemetry")
	if DisplayServer.get_name() != "headless":
		_player.camera_controller.rotation = Vector3.ZERO
		_player.camera_controller.spring_arm.rotation.x = deg_to_rad(-12.0)
		await _ticks(3)
		RenderingServer.force_draw()
		var preview: Image = root.get_texture().get_image()
		_check(preview.save_png(ProjectSettings.globalize_path("res://../docs/preview.png")) == OK, "viewport preview saved")
	_check(InputMap.action_has_event("dodge", _key(KEY_SHIFT)), "Shift input mapping")
	_check(InputMap.action_has_event("release_mouse", _key(KEY_ESCAPE)), "Escape input mapping")

	var start: Vector3 = _player.position
	Input.action_press("move_forward")
	await _ticks(45)
	_check(_player.position.z < start.z - 3.0, "W moves toward camera forward")
	_check(absf(_player.get_horizontal_speed() - 6.0) < 0.1, "walk reaches configured speed")
	_check(_player.state_machine.get_state_name() == "Move", "movement enters Move")
	Input.action_press("move_right")
	await _ticks(30)
	_check(_player.get_horizontal_speed() <= 6.01, "diagonal input is normalized")
	_release_actions()
	await _ticks(30)
	_check(_player.get_horizontal_speed() < 0.01, "deceleration stops movement")

	await _reset_player(Vector3(0, 0.02, 8))
	Input.action_press("jump")
	await _ticks(2)
	Input.action_release("jump")
	_check(_player.velocity.y > 0.0 and _player.position.y > 0.1, "jump creates upward motion")
	_check(_player.state_machine.get_state_name() == "Jump", "jump enters Jump")
	Input.action_press("dodge")
	await _ticks(1)
	Input.action_release("dodge")
	_check(_player.state_machine.get_state_name() != "Dodge", "air dodge is rejected")
	await _ticks(28)
	_check(_player.state_machine.get_state_name() == "Fall", "apex transitions to Fall")
	await _ticks(35)
	_check(_player.is_on_floor() and _player.state_machine.get_state_name() == "Idle", "landing returns to Idle")

	await _reset_player(Vector3(0, 0.02, 8))
	var dodge_start: Vector3 = _player.position
	Input.action_press("dodge")
	await _ticks(1)
	Input.action_release("dodge")
	_check(_player.state_machine.get_state_name() == "Dodge", "ground Shift enters Dodge")
	_check(absf(_player.get_horizontal_speed() - 8.888889) < 0.1, "dodge uses GDD distance/duration speed")
	_check(_player.state_machine.cooldown_remaining > 1.18, "dodge cooldown starts at initiation")
	Input.action_press("move_right")
	await _ticks(6)
	_check(absf(_player.velocity.x) < 0.01, "dodge direction stays locked")
	Input.action_release("move_right")
	await _ticks(22)
	_check(absf(_player.position.distance_to(dodge_start) - 4.0) < 0.2, "no-input dodge travels approximately four meters")
	_check(_player.state_machine.cooldown_remaining > 0.6 and _player.state_machine.cooldown_remaining < 0.8, "cooldown continues through dodge duration")
	Input.action_press("dodge")
	await _ticks(1)
	Input.action_release("dodge")
	_check(_player.state_machine.get_state_name() != "Dodge", "cooldown blocks repeated dodge")
	await _ticks(60)
	_check(_player.state_machine.cooldown_remaining == 0.0, "cooldown expires")
	_player.camera_controller.set_mouse_captured(true)
	Input.action_press("dodge")
	await _ticks(1)
	Input.action_release("dodge")
	_check(_player.state_machine.get_state_name() == "Dodge", "dodge becomes available again (state=%s, floor=%s, cd=%.3f, captured=%s)" % [_player.state_machine.get_state_name(), _player.is_on_floor(), _player.state_machine.cooldown_remaining, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED])
	await _ticks(80)

	await _reset_player(Vector3(0, 0.02, 8))
	_player.camera_controller.rotation.y = PI / 2.0
	start = _player.position
	Input.action_press("move_forward")
	await _ticks(35)
	Input.action_release("move_forward")
	_check(_player.position.x < start.x - 2.0, "movement follows camera yaw")
	_check(absf(wrapf(_player.visual.rotation.y - PI / 2.0, -PI, PI)) < 0.15, "visual turns smoothly toward movement")
	_player.camera_controller.rotate_view(Vector2(0, 100000))
	_check(is_equal_approx(_player.camera_controller.spring_arm.rotation.x, deg_to_rad(-55.0)), "minimum pitch clamps")
	_player.camera_controller.rotate_view(Vector2(0, -100000))
	_check(is_equal_approx(_player.camera_controller.spring_arm.rotation.x, deg_to_rad(35.0)), "maximum pitch clamps")

	await _reset_player(Vector3(0, 0.02, 8))
	var escape: InputEventKey = _key(KEY_ESCAPE)
	_player.camera_controller.set_process_unhandled_input(true)
	escape.pressed = true
	Input.parse_input_event(escape)
	await _ticks(2)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases mouse via input event")
	start = _player.position
	Input.action_press("move_forward")
	await _ticks(20)
	Input.action_release("move_forward")
	_check(_player.position.distance_to(start) < 0.01, "released mouse disables movement control")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _ticks(2)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "left click recaptures mouse via input event")
	_check(_player.combat.current_attack == null, "capture click does not trigger a sword attack")
	click.pressed = false
	Input.parse_input_event(click)
	await _ticks(10)
	# Explicitly exercise the first-motion guard without relying on native pointer timing.
	_player.camera_controller.set_mouse_captured(false)
	_player.camera_controller.set_mouse_captured(true)
	var yaw_before_capture: float = _player.camera_controller.rotation.y
	var warp_motion: InputEventMouseMotion = InputEventMouseMotion.new()
	warp_motion.relative = Vector2(1200, 800)
	root.push_input(warp_motion, true)
	_check(is_equal_approx(_player.camera_controller.rotation.y, yaw_before_capture), "first pointer-warp event is ignored")
	var yaw_before_motion: float = _player.camera_controller.rotation.y
	var mouse_motion: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(100, 0)
	root.push_input(mouse_motion, true)
	# push_input dispatches synchronously. Sample this event before yielding to
	# Windows, whose unrelated pointer/capture motion may arrive next frame.
	var yaw_delta: float = wrapf(_player.camera_controller.rotation.y - yaw_before_motion, -PI, PI)
	_player.camera_controller.set_process_unhandled_input(false)
	await _ticks(2)
	_check(absf(yaw_delta + 0.25) < 0.01, "mouse event rotates camera horizontally (delta %.3f)" % yaw_delta)

	await _reset_player(Vector3(0, 0.02, 17.5))
	await _ticks(10)
	var hit_length: float = _player.camera_controller.spring_arm.get_hit_length()
	_check(hit_length > 0.1 and hit_length < 3.0, "spring arm retracts against south wall")
	await _reset_player(Vector3(0, 0.02, 8))
	await _ticks(5)
	_check(_player.camera_controller.spring_arm.get_hit_length() > 4.4, "spring arm extends in clear space and ignores player")

	await _reset_player(Vector3(-5, 0.02, 4))
	Input.action_press("move_forward")
	await _ticks(65)
	Input.action_release("move_forward")
	_check(_player.position.z > 1.8, "solid obstacle blocks walking")

	await _reset_player(Vector3(0, 0.02, -17.5))
	Input.action_press("dodge")
	await _ticks(17)
	Input.action_release("dodge")
	_check(_player.position.z > -18.7, "dodge cannot tunnel through boundary wall")
	await _ticks(70)

	await _reset_player(Vector3(5, 2.05, -4.5))
	_check(_player.is_on_floor(), "high platform has collision")
	Input.action_press("move_left")
	await _ticks(42)
	Input.action_release("move_left")
	_check(_player.state_machine.get_state_name() == "Fall", "walking off platform enters Fall (state=%s, pos=%s, captured=%s)" % [_player.state_machine.get_state_name(), _player.position, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED])
	await _ticks(50)
	_check(_player.is_on_floor(), "fall from platform lands on ground")
	for required_state: String in ["Idle", "Move", "Jump", "Fall", "Dodge"]:
		_check(_states.has(required_state), "observed state signal: " + required_state)

	_release_actions()
	_player.camera_controller.set_mouse_captured(false)
	_arena.queue_free()
	current_scene = null
	await process_frame
	# Drain actor sound playback after scene release before shutting down the engine.
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("SMOKE RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _reset_player(position: Vector3) -> void:
	_release_actions()
	_player.position = position
	_player.velocity = Vector3.ZERO
	_player.visual.rotation = Vector3.ZERO
	_player.camera_controller.rotation = Vector3.ZERO
	_player.camera_controller.spring_arm.rotation.x = deg_to_rad(-12.0)
	_player.camera_controller.set_mouse_captured(true)
	await _ticks(20)


func _release_actions() -> void:
	for action: String in ["move_forward", "move_backward", "move_left", "move_right", "jump", "dodge", "attack", "skill"]:
		Input.action_release(action)


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	return event


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)


func _record_state(_previous: String, current: String) -> void:
	if not _states.has(current):
		_states.append(current)


func _record_telemetry(_state_name: String, _speed: float, _cooldown: float) -> void:
	_telemetry_count += 1
