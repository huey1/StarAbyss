class_name ToonPalette
extends RefCounted
## Imported Blender colors become shared Godot cel materials; no Blender runtime.

const SURFACE: Shader = preload("res://assets/materials/cel_surface.gdshader")
const OUTLINE: Shader = preload("res://assets/materials/cel_outline.gdshader")
static var _materials: Dictionary[String, ShaderMaterial] = {}


static func apply_to(root_node: Node, outlined: bool = true) -> void:
	var meshes: Array[Node] = root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		meshes.append(root_node)
	for node: Node in meshes:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var source: BaseMaterial3D = mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			mesh_instance.set_surface_override_material(surface, _from_source(source, outlined))


static func _from_source(source: BaseMaterial3D, outlined: bool) -> ShaderMaterial:
	var key: String = "%s:%s:%s:%s:%s" % [source.resource_name, source.albedo_color, source.emission, source.emission_energy_multiplier, outlined]
	if _materials.has(key):
		return _materials[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = source.resource_name + "_Cel"
	material.shader = SURFACE
	material.set_shader_parameter("base_color", source.albedo_color)
	if source.emission_enabled:
		material.set_shader_parameter("glow_color", source.emission)
		material.set_shader_parameter("glow_energy", minf(source.emission_energy_multiplier, 0.5))
	if outlined:
		var outline: ShaderMaterial = ShaderMaterial.new()
		outline.shader = OUTLINE
		material.next_pass = outline
	_materials[key] = material
	return material
