extends SceneTree
## Headless GDD, FIFO fairness and actual baked-nav path contracts.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: SentinelSettings = load("res://resources/enemies/default_sentinel.tres") as SentinelSettings
	_check(settings.max_health == 45 and is_equal_approx(settings.move_speed, 3.2), "GDD sentinel HP and speed")
	_check(is_equal_approx(settings.detection_radius, 10.0) and is_equal_approx(settings.attack_trigger_distance, 1.8), "GDD sensing and attack trigger ranges")
	_check(is_equal_approx(settings.attack.damage, 10.0) and is_equal_approx(settings.attack_cooldown, 1.3), "GDD attack damage and cooldown")
	_check(is_equal_approx(settings.attack.hit_start, 0.55), "GDD telegraph duration")
	_check(is_equal_approx(settings.attack.hit_end - settings.attack.hit_start, 0.18), "GDD active window duration")
	_check(is_equal_approx(settings.attack.duration - settings.attack.hit_end, 0.55), "GDD recovery duration")
	var container: Node3D = Node3D.new()
	var coordinator: AttackCoordinator = AttackCoordinator.new()
	container.add_child(coordinator)
	var a: Node3D = Node3D.new()
	var b: Node3D = Node3D.new()
	var c: Node3D = Node3D.new()
	container.add_child(a)
	container.add_child(b)
	container.add_child(c)
	root.add_child(container)
	_check(coordinator.request_slot(a), "first actor acquires attack slot")
	_check(coordinator.request_slot(a) and coordinator.get_active_count() == 1, "requesting twice does not duplicate slot")
	_check(not coordinator.request_slot(b) and not coordinator.request_slot(c), "other actors queue while slot is held")
	_check(coordinator.get_waiting_count() == 2, "FIFO has two distinct waiters")
	coordinator.cancel_request(a)
	_check(not coordinator.request_slot(a), "previous attacker cannot jump the queue during handoff")
	_check(not coordinator.request_slot(b), "handoff gap prevents immediate overlapping pressure")
	await _ticks(17)
	_check(coordinator.request_slot(b), "second actor gets next slot")
	coordinator.cancel_request(b)
	await _ticks(17)
	_check(coordinator.request_slot(c), "third actor gets FIFO turn")
	c.free()
	await _ticks(18)
	_check(coordinator.request_slot(a), "freeing holder releases stale permit without deadlock")
	coordinator.cancel_request(a)
	coordinator.request_slot(b)
	b.free()
	await _ticks(18)
	_check(coordinator.get_waiting_count() == 0 and coordinator.get_active_count() == 0, "freed waiting actors are pruned")
	container.queue_free()
	await process_frame

	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = load("res://resources/navigation/sentinel_arena_navmesh.tres") as NavigationMesh
	var geometry: PackedScene = load("res://scenes/levels/arena_geometry.tscn") as PackedScene
	region.add_child(geometry.instantiate())
	root.add_child(region)
	var map: RID = region.get_navigation_map()
	for frame: int in range(240):
		await _ticks(1)
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map, Vector3(-5, 0, 4)).is_valid():
			break
	_check(region.navigation_mesh.get_polygon_count() > 0, "committed navigation mesh contains polygons")
	_check(NavigationServer3D.map_get_iteration_id(map) > 0, "navigation map synchronized")
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(-5, 0, 4), Vector3(-5, 0, -4), true)
	var distance: float = 0.0
	for index: int in range(1, path.size()):
		distance += path[index - 1].distance_to(path[index])
	_check(path.size() > 2 and distance > 8.4, "baked navigation routes around low block instead of through it (points=%s, length=%.2f)" % [path, distance])
	var platform: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(5, 2, -4.5))
	var unreachable: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(0, 0, 8), platform, true)
	_check(unreachable.is_empty() or unreachable[unreachable.size() - 1].distance_to(platform) > 0.5, "high platform is disconnected for ground sentinel")
	region.queue_free()
	await process_frame
	print("ENEMY RULES RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
