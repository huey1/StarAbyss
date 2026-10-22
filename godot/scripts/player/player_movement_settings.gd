class_name PlayerMovementSettings
extends Resource
## Shared, read-only tuning. Runtime timers belong to each state machine.

@export_group("Ground movement")
@export_range(0.1, 30.0, 0.1) var move_speed: float = 6.0
@export_range(0.1, 100.0, 0.1) var acceleration: float = 22.0
@export_range(0.1, 100.0, 0.1) var deceleration: float = 28.0
@export_range(0.1, 30.0, 0.1) var rotation_speed: float = 12.0

@export_group("Air movement")
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.45
@export_range(0.1, 30.0, 0.1) var jump_velocity: float = 6.5
@export_range(0.1, 4.0, 0.1) var gravity_scale: float = 1.0
@export_range(1.0, 100.0, 0.1) var terminal_fall_speed: float = 40.0

@export_group("Dodge")
@export_range(0.1, 40.0, 0.1) var dodge_speed: float = 8.888889
@export_range(0.05, 2.0, 0.01) var dodge_duration: float = 0.45
@export_range(0.0, 10.0, 0.01) var dodge_cooldown: float = 1.2
@export_range(0.0, 2.0, 0.01) var dodge_invulnerable_start: float = 0.10
@export_range(0.0, 2.0, 0.01) var dodge_invulnerable_end: float = 0.30
