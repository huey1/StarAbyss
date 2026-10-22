class_name PlayerCombatSettings
extends Resource

@export var attacks: Array[AttackDefinition] = []
@export var skill: AttackDefinition
@export_range(0.01, 1.0, 0.01) var input_buffer_duration: float = 0.18
@export_range(0.1, 3.0, 0.01) var combo_reset_duration: float = 0.9
@export_range(0.1, 30.0, 0.1) var skill_cooldown: float = 8.0
@export_range(0.0, 4.0, 0.1) var attack_turn_speed: float = 1.5
@export_range(0.0, 0.2, 0.01) var hit_stop_duration: float = 0.04
