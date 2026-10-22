class_name RoomDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var enemy_spawns: Array[Vector3] = []
@export var player_spawn: Vector3 = Vector3(0, 0.02, 8)
@export var boss_staging: bool = false
@export var boss_room: bool = false
@export var boss_spawn: Vector3 = Vector3(0, 0.02, 1)
