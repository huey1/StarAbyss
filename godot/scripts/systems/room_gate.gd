class_name RoomGate
extends Node3D
## Physical barrier plus a one-shot player threshold. Progression also validates room state.

signal crossed
var is_open: bool = false
var _used: bool = false
var _player: PlayerController
@onready var barrier: StaticBody3D = $Barrier
@onready var threshold: Area3D = $Threshold
@onready var caption: Label3D = $Caption


func configure(player: PlayerController) -> void:
	_player = player
	set_open(false)


func set_open(opened: bool) -> void:
	is_open = opened
	barrier.visible = not opened
	barrier.set_deferred("collision_layer", 0 if opened else 1)
	caption.text = "出口已开启 · 穿过青色门前往下一房" if opened else "出口封锁 · 击破全部哨兵"
	caption.modulate = Color(0.3, 1.0, 0.85) if opened else Color(1.0, 0.65, 0.35)


func _physics_process(_delta: float) -> void:
	if is_open and not _used and is_instance_valid(_player) and threshold.overlaps_body(_player):
		_used = true
		crossed.emit()
