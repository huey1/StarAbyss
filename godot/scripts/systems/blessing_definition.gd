class_name BlessingDefinition
extends Resource
## Immutable metadata and tuning; acquired IDs belong to BlessingManager.

@export var id: StringName
@export var localization_key: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: String
@export var color: Color = Color.CYAN
@export var normal_attack_multiplier: float = 1.0
@export var dodge_cooldown: float = -1.0
@export var acquisition_heal: int = 0
@export var ordinary_kill_heal: int = 0
