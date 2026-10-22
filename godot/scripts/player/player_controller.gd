class_name PlayerController
extends CharacterBody3D
## Movement motor. All state decisions live in PlayerStateMachine.

signal telemetry_updated(state_name: String, speed: float, cooldown: float)

@export var movement_settings: PlayerMovementSettings

var move_direction: Vector3 = Vector3.ZERO
var jump_requested: bool = false
var dodge_requested: bool = false
var attack_requested: bool = false
var skill_requested: bool = false
var _ignore_attack_until_release: bool = false
var _ignore_actions_until_release: bool = false
var _gravity: float = 18.0

@onready var visual: Node3D = $Visual
@onready var camera_controller: CameraController = $CameraRig
@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var health: HealthComponent = $Health
@onready var combat: PlayerCombat = $Combat
@onready var feedback: CombatFeedback = $Feedback


func _ready() -> void:
	assert(movement_settings != null, "Player requires movement settings")
	camera_controller.exclude_body(self)
	_ignore_attack_until_release = Input.is_action_pressed("attack")
	camera_controller.capture_changed.connect(_on_capture_changed)
	combat.hit_landed.connect(_on_hit_landed)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	state_machine.initialize(self)


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)
	# Releasing the mouse also releases movement control for editor/window interaction.
	var accepts_input: bool = health.is_alive() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _ignore_actions_until_release and not (Input.is_action_pressed("jump") or Input.is_action_pressed("dodge") or Input.is_action_pressed("skill")):
		_ignore_actions_until_release = false
	move_direction = camera_controller.get_movement_direction(input_vector) if accepts_input else Vector3.ZERO
	jump_requested = accepts_input and not _ignore_actions_until_release and Input.is_action_just_pressed("jump")
	dodge_requested = accepts_input and not _ignore_actions_until_release and Input.is_action_just_pressed("dodge")
	if not Input.is_action_pressed("attack"):
		_ignore_attack_until_release = false
	attack_requested = accepts_input and not _ignore_attack_until_release and Input.is_action_just_pressed("attack")
	skill_requested = accepts_input and not _ignore_actions_until_release and Input.is_action_just_pressed("skill")
	combat.tick_cooldowns(delta)
	state_machine.tick_cooldown(delta)
	if attack_requested:
		combat.buffer_attack()
	if feedback.freeze_remaining > 0.0 and health.is_alive():
		_publish_telemetry()
		return
	state_machine.physics_step(delta)
	move_and_slide()
	state_machine.after_move()
	_publish_telemetry()


func _publish_telemetry() -> void:
	telemetry_updated.emit(state_machine.get_state_name(), get_horizontal_speed(), state_machine.cooldown_remaining)


func _on_capture_changed(captured: bool) -> void:
	if captured and Input.is_action_pressed("attack"):
		_ignore_attack_until_release = true


func suppress_action_input() -> void:
	_ignore_attack_until_release = true
	_ignore_actions_until_release = true


func _on_hit_landed(_target: Hurtbox, _damage: int) -> void:
	feedback.start_hit_stop(combat.settings.hit_stop_duration)


func move_horizontal(delta: float, airborne: bool) -> void:
	var target: Vector3 = move_direction * movement_settings.move_speed
	var rate: float = movement_settings.acceleration if move_direction.length_squared() > 0.0 else movement_settings.deceleration
	if airborne:
		rate *= movement_settings.air_control
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	face_direction(move_direction, delta)


func apply_gravity(delta: float) -> void:
	velocity.y = maxf(velocity.y - _gravity * movement_settings.gravity_scale * delta, -movement_settings.terminal_fall_speed)


func move_action(delta: float, allow_aim: bool) -> void:
	var horizontal: Vector3 = Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, movement_settings.deceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if allow_aim and move_direction.length_squared() > 0.001:
		visual.rotation.y = rotate_toward(visual.rotation.y, atan2(-move_direction.x, -move_direction.z), combat.settings.attack_turn_speed * delta)


func stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func start_jump() -> void:
	velocity.y = movement_settings.jump_velocity


func move_dodge(direction: Vector3, delta: float) -> void:
	velocity.x = direction.x * movement_settings.dodge_speed
	velocity.z = direction.z * movement_settings.dodge_speed
	face_direction(direction, delta)


func face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-movement_settings.rotation_speed * delta))


func get_facing_direction() -> Vector3:
	return -visual.global_basis.z.normalized()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
