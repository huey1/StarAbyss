class_name CombatVFX
extends Node3D
## Scene-local cosmetic fragments. No collision, damage or gameplay clocks.

signal burst_emitted(fragment_count: int, terminal: bool)

class Fragment:
	var visual: MeshInstance3D
	var velocity: Vector3
	var age: float = 0.0
	var lifetime: float
	var initial_scale: float

@export var actor_path: NodePath = NodePath("..")
@export_range(0.0, 1.0, 0.05) var effect_strength: float = 0.7
@export_range(1, 24, 1) var max_fragments: int = 12
@export_range(1, 8, 1) var impact_fragments: int = 4
@export_range(1, 16, 1) var death_fragments: int = 10
var _actor: Node3D
var _health: HealthComponent
var _feedback: CombatFeedback
var _fragments: Array[Fragment] = []
var _fragment_mesh: PrismMesh
var _impact_material: StandardMaterial3D
var _death_material: StandardMaterial3D
var _burst_serial: int = 0
var _burst_height: float = 1.0
var _death_emitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 20
	_actor = get_node(actor_path) as Node3D
	_health = _actor.get_node("Health") as HealthComponent
	_feedback = _actor.get_node("Feedback") as CombatFeedback
	for child: Node in _actor.get_children():
		if child is CollisionShape3D:
			var capsule: CapsuleShape3D = (child as CollisionShape3D).shape as CapsuleShape3D
			if capsule != null:
				_burst_height = capsule.height * 0.58
				break
	_fragment_mesh = PrismMesh.new()
	_fragment_mesh.size = Vector3(0.055, 0.12, 0.055)
	var is_player: bool = _actor is PlayerController
	_impact_material = _make_material(Color(1.0, 0.46, 0.13) if is_player else Color(0.34, 0.86, 1.0))
	_death_material = _make_material(Color(0.3, 0.8, 0.95) if is_player else Color(1.0, 0.52, 0.13))
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	# Living impacts follow pause and local hit stop. Terminal shards may finish
	# behind the result panel, like the existing terminal skeletal collapse.
	if not _death_emitted and (get_tree().paused or _feedback.freeze_remaining > 0.0):
		return
	for index: int in range(_fragments.size() - 1, -1, -1):
		var fragment: Fragment = _fragments[index]
		fragment.age += delta
		if fragment.age >= fragment.lifetime:
			_remove_fragment(index)
			continue
		fragment.velocity.y -= 9.0 * delta
		fragment.visual.global_position += fragment.velocity * delta
		fragment.visual.rotate_y(delta * 5.0)
		fragment.visual.rotate_z(delta * 3.0)
		var remaining: float = 1.0 - fragment.age / fragment.lifetime
		fragment.visual.scale = Vector3.ONE * fragment.initial_scale * remaining
	if _fragments.is_empty():
		set_physics_process(false)


func _on_damaged(_amount: int, _info: DamageInfo) -> void:
	if not _death_emitted:
		_burst(impact_fragments, false)


func _on_died(_info: DamageInfo) -> void:
	if _death_emitted:
		return
	_death_emitted = true
	clear_effects()
	_burst(death_fragments, true)


func _burst(requested: int, terminal: bool) -> void:
	if effect_strength <= 0.0 or max_fragments <= 0:
		return
	_burst_serial += 1
	var count: int = mini(requested, max_fragments)
	for index: int in range(count):
		while _fragments.size() >= max_fragments:
			_remove_fragment(0)
		var angle: float = TAU * (float(index) / float(count) + float(_burst_serial) * 0.6180339)
		var speed: float = (1.0 if terminal else 2.0) * (0.6 + effect_strength * 0.4)
		var fragment: Fragment = Fragment.new()
		fragment.visual = MeshInstance3D.new()
		fragment.visual.name = "CrystalFragment" if terminal else "ImpactSpark"
		fragment.visual.mesh = _fragment_mesh
		fragment.visual.material_override = _death_material if terminal else _impact_material
		fragment.visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fragment.visual)
		fragment.visual.top_level = true
		fragment.visual.global_position = _actor.global_position + Vector3.UP * _burst_height
		fragment.visual.rotation = Vector3(angle, angle * 0.5, angle * 0.3)
		fragment.initial_scale = (1.0 if terminal else 0.55) * (0.5 + effect_strength * 0.5)
		fragment.visual.scale = Vector3.ONE * fragment.initial_scale
		fragment.velocity = Vector3(cos(angle) * speed, 1.5 + float(index % 3) * 0.3, sin(angle) * speed)
		fragment.lifetime = 0.65 if terminal else 0.24
		_fragments.append(fragment)
	set_physics_process(true)
	burst_emitted.emit(count, terminal)


func active_effect_count() -> int:
	return _fragments.size()


func clear_effects() -> void:
	for index: int in range(_fragments.size() - 1, -1, -1):
		_remove_fragment(index)
	set_physics_process(false)


func _remove_fragment(index: int) -> void:
	var fragment: Fragment = _fragments[index]
	if is_instance_valid(fragment.visual):
		fragment.visual.free()
	_fragments.remove_at(index)


func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.1
	return material


func _exit_tree() -> void:
	clear_effects()
