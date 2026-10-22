extends SceneTree
## Exercise the configured main scene, then allow asynchronous audio deletion before exit.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_path: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("Configured main scene failed to load")
		quit(1)
		return
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	current_scene = instance
	for frame: int in range(120):
		await physics_frame
		await process_frame
	current_scene.queue_free()
	current_scene = null
	await process_frame
	# Godot's audio server frees stopped playback asynchronously in wall-clock time.
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	quit(0)
