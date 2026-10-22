extends SceneTree
## Offline rebuild after editing arena_geometry.tscn. Not a runtime dependency.


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var guardian: bool = OS.get_cmdline_user_args().has("--guardian")
	var geometry: PackedScene = load("res://scenes/levels/arena_geometry.tscn") as PackedScene
	var region: NavigationRegion3D = NavigationRegion3D.new()
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.agent_radius = 0.75 if guardian else 0.5
	mesh.agent_height = 2.75 if guardian else 1.75
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	region.navigation_mesh = mesh
	region.add_child(geometry.instantiate())
	root.add_child(region)
	await process_frame
	region.bake_navigation_mesh(false)
	if mesh.get_polygon_count() == 0:
		printerr("FAIL: navigation bake produced no polygons")
		quit(1)
		return
	var destination: String = "res://resources/navigation/guardian_arena_navmesh.tres" if guardian else "res://resources/navigation/sentinel_arena_navmesh.tres"
	var error: Error = ResourceSaver.save(mesh, destination)
	print("NAV BAKE: %d polygons, save=%s" % [mesh.get_polygon_count(), error_string(error)])
	region.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
