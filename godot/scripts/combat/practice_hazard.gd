extends Area3D
## Visible periodic damage fixture, not an enemy AI. New instance ID for each pulse.

@export var damage: float = 10.0
@export var warning_duration: float = 0.9
@export var active_duration: float = 0.18
@export var recover_duration: float = 0.7
var _elapsed: float = 0.0
var _info: DamageInfo
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	$Disc.material_override = _material


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= warning_duration + active_duration + recover_duration:
		_elapsed = 0.0
		_info = null
	var active: bool = _elapsed >= warning_duration and _elapsed < warning_duration + active_duration
	if active:
		if _info == null:
			_info = DamageInfo.create(damage, self, 2)
		for area: Area3D in get_overlapping_areas():
			if area is Hurtbox:
				CombatResolver.resolve(_info, area as Hurtbox)
		_material.albedo_color = Color(1.0, 0.15, 0.07, 0.8)
	else:
		_material.albedo_color = Color(1.0, 0.5, 0.1, 0.15 + 0.35 * minf(_elapsed / warning_duration, 1.0))
