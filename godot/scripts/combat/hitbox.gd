class_name Hitbox
extends Area3D
## Broad-phase Area stays enabled. Each active sample applies range, cone, height and LOS.

signal hit_confirmed(target: Hurtbox, damage: int)

@export var block_by_world: bool = true
var active: bool = false
var definition: AttackDefinition
var damage_info: DamageInfo
var _contacted_health: Dictionary[int, bool] = {}


func begin_attack(attack: AttackDefinition, info: DamageInfo) -> void:
	definition = attack
	damage_info = info
	_contacted_health.clear()
	active = false


func end_attack() -> void:
	active = false
	damage_info = null
	definition = null
	_contacted_health.clear()


func sample() -> void:
	if not active or definition == null or damage_info == null:
		return
	for area: Area3D in get_overlapping_areas():
		# A damage/death signal can synchronously cancel this attack during iteration.
		if not active or definition == null or damage_info == null:
			break
		var target: Hurtbox = area as Hurtbox
		if target == null or target.team == damage_info.source_team or not target.health.is_alive():
			continue
		var health_id: int = target.health.get_instance_id()
		if _contacted_health.has(health_id) or not contains_target(target.global_position):
			continue
		if block_by_world:
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, target.global_position, 1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
		_contacted_health[health_id] = true
		var applied: int = CombatResolver.resolve(damage_info, target)
		if applied > 0:
			hit_confirmed.emit(target, applied)


func contains_target(target_position: Vector3) -> bool:
	if definition == null:
		return false
	var offset: Vector3 = target_position - global_position
	if absf(offset.y) > 1.4:
		return false
	offset.y = 0.0
	if offset.length() > definition.reach:
		return false
	if offset.length_squared() < 0.001:
		return true
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(offset.normalized()) >= cos(deg_to_rad(definition.arc_degrees * 0.5))
