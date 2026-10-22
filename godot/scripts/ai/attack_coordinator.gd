class_name AttackCoordinator
extends Node
## Scene-local FIFO permits: approach, telegraph, hit and recovery share one permit.

signal slots_changed(active_count: int)

@export_range(1, 4, 1) var max_attackers: int = 1
@export_range(0.0, 2.0, 0.05) var handoff_delay: float = 0.25
var _holders: Array[Node3D] = []
var _waiting: Array[Node3D] = []
var _handoff_remaining: float = 0.0


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	_handoff_remaining = maxf(0.0, _handoff_remaining - delta)
	_prune_invalid()


func request_slot(actor: Node3D) -> bool:
	_prune_invalid()
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	if _holders.has(actor):
		return true
	if not _waiting.has(actor):
		_waiting.append(actor)
	if _holders.size() >= max_attackers or _handoff_remaining > 0.0 or _waiting.front() != actor:
		return false
	_waiting.pop_front()
	_holders.append(actor)
	slots_changed.emit(_holders.size())
	return true


func cancel_request(actor: Node3D) -> void:
	_waiting.erase(actor)
	if _holders.has(actor):
		_holders.erase(actor)
		_handoff_remaining = handoff_delay
		slots_changed.emit(_holders.size())


func has_slot(actor: Node3D) -> bool:
	return _holders.has(actor)


func get_active_count() -> int:
	return _holders.size()


func get_waiting_count() -> int:
	return _waiting.size()


func _prune_invalid() -> void:
	var before: int = _holders.size()
	for index: int in range(_holders.size() - 1, -1, -1):
		if not is_instance_valid(_holders[index]) or not _holders[index].is_inside_tree():
			_holders.remove_at(index)
	for index: int in range(_waiting.size() - 1, -1, -1):
		if not is_instance_valid(_waiting[index]) or not _waiting[index].is_inside_tree():
			_waiting.remove_at(index)
	if _holders.size() != before:
		_handoff_remaining = handoff_delay
		slots_changed.emit(_holders.size())
