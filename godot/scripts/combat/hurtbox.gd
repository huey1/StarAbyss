class_name Hurtbox
extends Area3D

@export var health_path: NodePath = NodePath("../Health")
@export_enum("Neutral:0", "Player:1", "Enemy:2") var team: int = 2
@onready var health: HealthComponent = get_node(health_path) as HealthComponent


func _ready() -> void:
	assert(health != null, "Hurtbox must reference a HealthComponent")
