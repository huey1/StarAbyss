class_name BlessingManager
extends Node
## Scene-local run effects. Never writes shared combat or movement Resources.

signal collection_changed
signal candidates_offered(candidates: Array[BlessingDefinition])
signal selection_completed(blessing: BlessingDefinition)

@export var pool: Array[BlessingDefinition] = []
var acquired: Array[BlessingDefinition] = []
var candidates: Array[BlessingDefinition] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _player: PlayerController
var _base_normal_multiplier: float = 1.0
var _base_dodge_multiplier: float = 1.0
var _kill_heal: int = 0


func initialize(player: PlayerController, run_seed: int) -> void:
	_player = player
	_base_normal_multiplier = player.combat.normal_attack_multiplier
	_base_dodge_multiplier = player.state_machine.dodge_cooldown_multiplier
	_rng.seed = run_seed
	clear()


func offer() -> Array[BlessingDefinition]:
	candidates.clear()
	var seen: Dictionary[StringName, bool] = {}
	for blessing: BlessingDefinition in pool:
		if blessing != null and not has_blessing(blessing.id) and not seen.has(blessing.id):
			candidates.append(blessing)
			seen[blessing.id] = true
	for index: int in range(candidates.size() - 1, 0, -1):
		var other: int = _rng.randi_range(0, index)
		var swap: BlessingDefinition = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = swap
	if candidates.size() > 3:
		candidates.resize(3)
	candidates_offered.emit(candidates.duplicate())
	return candidates.duplicate()


func choose(id: StringName) -> bool:
	if not is_instance_valid(_player) or not _player.health.is_alive() or has_blessing(id):
		return false
	for blessing: BlessingDefinition in candidates:
		if blessing.id == id:
			acquired.append(blessing)
			candidates.clear()
			_apply_effects()
			_player.health.heal(blessing.acquisition_heal)
			collection_changed.emit()
			selection_completed.emit(blessing)
			return true
	return false


func has_blessing(id: StringName) -> bool:
	for blessing: BlessingDefinition in acquired:
		if blessing.id == id:
			return true
	return false


func on_ordinary_enemy_killed() -> void:
	if is_instance_valid(_player):
		_player.health.heal(_kill_heal)


func clear() -> void:
	acquired.clear()
	candidates.clear()
	_apply_effects()
	collection_changed.emit()


func _apply_effects() -> void:
	_kill_heal = 0
	if not is_instance_valid(_player):
		return
	_player.combat.normal_attack_multiplier = _base_normal_multiplier
	_player.state_machine.dodge_cooldown_multiplier = _base_dodge_multiplier
	for blessing: BlessingDefinition in acquired:
		_player.combat.normal_attack_multiplier *= blessing.normal_attack_multiplier
		if blessing.dodge_cooldown >= 0.0:
			_player.state_machine.dodge_cooldown_multiplier = blessing.dodge_cooldown / _player.movement_settings.dodge_cooldown
		_kill_heal += blessing.ordinary_kill_heal
