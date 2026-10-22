class_name DamageInfo
extends RefCounted
## One immutable-in-use payload per swing/cast/pulse; no global scene singleton.

static var _next_attack_id: int = 0

var attack_id: int = 0
var base_damage: float = 0.0
var attack_multiplier: float = 1.0
var source: Node3D
var source_team: int = 0


static func create(damage: float, attacker: Node3D, team: int, multiplier: float = 1.0) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	_next_attack_id += 1
	info.attack_id = _next_attack_id
	info.base_damage = damage
	info.source = attacker
	info.source_team = team
	info.attack_multiplier = multiplier
	return info
