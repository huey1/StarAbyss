class_name SentinelSettings
extends Resource
## GDD combat values and configurable navigation/spacing policies.

@export var display_name: String = "遗迹哨兵"
@export var localization_key: StringName = &"enemy_sentinel"
@export_range(1, 1000, 1) var max_health: int = 45
@export_range(0.1, 12.0, 0.1) var move_speed: float = 3.2
@export_range(0.1, 60.0, 0.1) var acceleration: float = 20.0
@export_range(0.1, 30.0, 0.1) var turn_speed: float = 12.0
@export_range(1.0, 30.0, 0.1) var detection_radius: float = 10.0
@export_range(0.5, 5.0, 0.1) var attack_trigger_distance: float = 1.8
@export_range(0.1, 10.0, 0.1) var attack_cooldown: float = 1.3
@export var attack: AttackDefinition

@export_group("Navigation and spacing")
@export_range(0.05, 1.0, 0.05) var repath_interval: float = 0.2
@export_range(0.1, 2.0, 0.05) var target_nav_tolerance: float = 0.65
@export_range(1.0, 6.0, 0.1) var waiting_distance: float = 2.8
@export_range(1.0, 30.0, 0.1) var home_leash_distance: float = 14.0
@export_range(0.1, 5.0, 0.1) var stuck_timeout: float = 0.8
@export_range(0.1, 5.0, 0.1) var reengage_delay: float = 1.0
@export_range(0.0, 1.0, 0.05) var stagger_duration: float = 0.2
@export_range(0.1, 10.0, 0.1) var corpse_duration: float = 2.0
