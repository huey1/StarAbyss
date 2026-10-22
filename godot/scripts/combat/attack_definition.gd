class_name AttackDefinition
extends Resource
## Timings drive both the placeholder weapon pose and the actual hit window.

@export var display_name: String = "横斩"
@export var localization_key: StringName = &"attack_01"
@export_range(1.0, 200.0, 1.0) var damage: float = 12.0
@export_range(0.1, 3.0, 0.01) var duration: float = 0.48
@export_range(0.0, 3.0, 0.01) var hit_start: float = 0.16
@export_range(0.0, 3.0, 0.01) var hit_end: float = 0.28
@export_range(0.1, 10.0, 0.1) var reach: float = 2.2
@export_range(1.0, 360.0, 1.0) var arc_degrees: float = 110.0
@export_range(0.0, 3.0, 0.01) var combo_open: float = 0.30
@export_range(0.0, 3.0, 0.01) var combo_close: float = 0.48
@export_range(0.0, 3.0, 0.01) var dodge_cancel_open: float = 0.30
@export_range(0.0, 3.0, 0.01) var dodge_cancel_close: float = 0.44
@export var reverse_swing: bool = false
