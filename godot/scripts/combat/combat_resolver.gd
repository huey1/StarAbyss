class_name CombatResolver
extends RefCounted
## Stateless damage rules. Identity allocation belongs to DamageInfo itself.


static func calculate_damage(base_damage: float, attack_multiplier: float, taken_multiplier: float) -> int:
	return maxi(1, roundi(base_damage * attack_multiplier * taken_multiplier))


static func resolve(info: DamageInfo, target: Hurtbox) -> int:
	if info == null or not is_instance_valid(target) or not is_instance_valid(target.health):
		return 0
	if info.source_team == target.team:
		return 0
	if is_instance_valid(info.source) and info.source == target.get_parent():
		return 0
	return target.health.receive_damage(
		calculate_damage(info.base_damage, info.attack_multiplier, target.health.damage_taken_multiplier), info
	)
