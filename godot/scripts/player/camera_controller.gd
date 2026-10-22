class_name CameraController
extends Node3D
## Yaw stays on this pivot; pitch stays on the spring arm, independent of the model.

signal capture_changed(captured: bool)

@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity: float = 0.0025
@export_range(-89.0, 0.0, 1.0) var minimum_pitch_degrees: float = -55.0
@export_range(0.0, 89.0, 1.0) var maximum_pitch_degrees: float = 35.0
@export_range(1.0, 10.0, 0.1) var camera_distance: float = 4.5
@export var capture_on_start: bool = true

var _ignore_next_mouse_motion: bool = false

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	spring_arm.spring_length = camera_distance
	if capture_on_start:
		set_mouse_captured(true)


func exclude_body(body: PhysicsBody3D) -> void:
	spring_arm.add_excluded_object(body.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		set_mouse_captured(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				set_mouse_captured(true)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Windows can send a pointer-warp delta when capture begins.
		if _ignore_next_mouse_motion:
			_ignore_next_mouse_motion = false
		else:
			rotate_view(event.relative)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_mouse_captured(false)


func rotate_view(relative_motion: Vector2) -> void:
	rotation.y = wrapf(rotation.y - relative_motion.x * mouse_sensitivity, -PI, PI)
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x - relative_motion.y * mouse_sensitivity,
		deg_to_rad(minimum_pitch_degrees), deg_to_rad(maximum_pitch_degrees)
	)


func set_mouse_captured(captured: bool) -> void:
	if captured and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_ignore_next_mouse_motion = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	capture_changed.emit(captured)


func get_movement_direction(input_vector: Vector2) -> Vector3:
	var direction: Vector3 = global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
	direction.y = 0.0
	return direction.normalized() * minf(input_vector.length(), 1.0)
