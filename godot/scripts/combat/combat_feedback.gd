class_name CombatFeedback
extends Node
## Actor-local hit stop: never writes Engine.time_scale or leaves global pause behind.

@export var visual_path: NodePath = NodePath("../Visual")
@export var health_path: NodePath = NodePath("../Health")
@export_range(0.0, 0.2, 0.01) var hit_stop_duration: float = 0.04
var freeze_remaining: float = 0.0
var _flash_remaining: float = 0.0
var _meshes: Array[MeshInstance3D] = []
var _white: StandardMaterial3D


func _ready() -> void:
	process_physics_priority = -20
	var visual: Node3D = get_node(visual_path) as Node3D
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		if node.name != &"Arc" and not node.is_in_group(&"combat_effect_mesh"):
			_meshes.append(node as MeshInstance3D)
	_white = StandardMaterial3D.new()
	_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_white.albedo_color = Color.WHITE
	var health: HealthComponent = get_node(health_path) as HealthComponent
	health.damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	freeze_remaining = maxf(0.0, freeze_remaining - delta)
	if _flash_remaining > 0.0:
		_flash_remaining = maxf(0.0, _flash_remaining - delta)
		if _flash_remaining == 0.0:
			for mesh: MeshInstance3D in _meshes:
				mesh.material_overlay = null


func start_hit_stop(duration: float) -> void:
	freeze_remaining = maxf(freeze_remaining, duration)


func _on_damaged(amount: int, _info: DamageInfo) -> void:
	start_hit_stop(hit_stop_duration)
	_flash_remaining = 0.10
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = _white
	var actor: Node3D = get_parent() as Node3D
	var number: Label3D = Label3D.new()
	number.text = str(amount)
	number.font_size = 72
	number.pixel_size = 0.006
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.no_depth_test = true
	number.modulate = Color(1.0, 0.85, 0.35)
	actor.get_parent().add_child(number)
	number.global_position = actor.global_position + Vector3(0, 2.0, 0)
	var tween: Tween = number.create_tween().set_parallel(true)
	tween.tween_property(number, "position:y", number.position.y + 0.7, 0.6)
	tween.tween_property(number, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(number.queue_free)
