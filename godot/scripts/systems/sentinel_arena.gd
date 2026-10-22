extends Node3D
## P3 encounter fixture and status view only. No room progression or run manager.

@onready var _sentinels: Array[SentinelController] = [$SentinelLeft, $SentinelRight]
@onready var _player: PlayerController = $Player
@onready var _coordinator: AttackCoordinator = $AttackCoordinator
@onready var _status: Label = $EncounterHUD/Status


func _ready() -> void:
	for sentinel: SentinelController in _sentinels:
		sentinel.health.died.connect(_on_health_died)
	_player.health.died.connect(_on_health_died)
	_coordinator.slots_changed.connect(_refresh_status)
	_refresh_status()


func _on_health_died(_info: DamageInfo) -> void:
	_refresh_status()


func _refresh_status(_active: int = 0) -> void:
	if not is_inside_tree():
		return
	var remaining: int = get_living_enemy_count()
	if not _player.health.is_alive():
		_status.text = "训练失败 · 角色已倒下\n点击右上角重置可再战"
	elif remaining == 0:
		_status.text = "1v2 训练完成 · 两名哨兵已击破\nEsc 释放鼠标，右上角重置可再战"
	else:
		_status.text = "1v2 哨兵训练 · 存活 %d / 2\n近身名额 %d / %d · 橙色预警后红色生效" % [remaining, _coordinator.get_active_count(), _coordinator.max_attackers]


func get_living_enemy_count() -> int:
	var count: int = 0
	for sentinel: SentinelController in _sentinels:
		if is_instance_valid(sentinel) and sentinel.health.is_alive():
			count += 1
	return count
