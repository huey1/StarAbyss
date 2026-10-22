extends StaticBody3D
## Stationary P2 test fixture, deliberately has no perception, navigation or attacks.

@onready var health: HealthComponent = $Health
@onready var label: Label3D = $Label


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	label.text = "训练靶\n%d / %d" % [current, maximum]


func _on_died(_info: DamageInfo) -> void:
	label.text = "训练靶 · 已击破"
	$Collision.set_deferred("disabled", true)
	$Hurtbox.set_deferred("monitorable", false)
	$Visual.rotation.z = PI / 2.0
	$Visual.position.y = 0.4
