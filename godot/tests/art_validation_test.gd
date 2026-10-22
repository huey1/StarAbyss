extends SceneTree
## Asset deformation, stationary root and authoritative action-clock integration.
## Direct action sampling is an art fixture, not an unaided combat run.

const MODELS: Array[String] = [
	"res://assets/models/characters/player.glb",
	"res://assets/models/characters/sentinel.glb",
	"res://assets/models/characters/core_guardian.glb",
]
const WEAPONS: Array[String] = [
	"res://assets/models/characters/sword.glb",
	"res://assets/models/characters/sentinel_blade.glb",
	"res://assets/models/characters/guardian_hammer.glb",
]
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	for index: int in range(MODELS.size()):
		_test_model(MODELS[index], index)
	var run: RunManager = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	root.add_child(run)
	current_scene = run
	await _ticks(4)
	var player: PlayerController = run.player
	player.set_physics_process(false)
	for enemy: SentinelController in run.room.enemies:
		enemy.set_physics_process(false)
	var view: ActorPresentation = player.get_node("Visual/ActorPresentation") as ActorPresentation
	_check(view.skeleton.find_bone("WeaponSocket") >= 0 and view.weapon_attachment.get_child_count() == 1, "runtime weapon attached to imported right-hand socket")
	_check(not player.get_node("Visual/Body").visible and not player.get_node("Visual/CombatVisual/WeaponPivot").visible, "legacy body and procedural weapon hidden")
	for index: int in range(3):
		player.combat.start_attack()
		var attack: AttackDefinition = player.combat.current_attack
		_check(is_equal_approx(view.animation_player.get_animation("Attack_%02d" % (index + 1)).length, attack.duration), "combo %d imported clip matches full action duration" % (index + 1))
		player.combat.advance_action(attack.hit_start)
		view._physics_process(0.0)
		_check(view.current_clip == StringName("Attack_%02d" % (index + 1)) and is_equal_approx(view.sampled_time, player.combat.elapsed), "combo %d warning-to-hit clock is synchronized" % (index + 1))
		var hand: int = view.skeleton.find_bone("Hand_R")
		var first_pose: Transform3D = view.skeleton.get_bone_global_pose(hand)
		player.combat.advance_action(attack.hit_end - attack.hit_start)
		view._physics_process(0.0)
		var last_pose: Transform3D = view.skeleton.get_bone_global_pose(hand)
		_check(first_pose.origin.distance_to(last_pose.origin) > 0.03 or not first_pose.basis.is_equal_approx(last_pose.basis), "combo %d weapon hand actually sweeps during active window" % (index + 1))
		player.feedback.start_hit_stop(0.04)
		view._physics_process(0.02)
		_check(is_equal_approx(view.sampled_time, player.combat.elapsed), "combo %d hit stop cannot advance animation beyond combat" % (index + 1))
		player.combat.interrupt()
	player.combat.start_skill()
	player.combat.advance_action(player.combat.current_attack.hit_start)
	view._physics_process(0.0)
	_check(view.current_clip == &"Skill_01" and is_equal_approx(view.sampled_time, player.combat.elapsed), "skill samples actual hit boundary")
	var before_pause: float = view.sampled_time
	paused = true
	view._physics_process(0.2)
	_check(is_equal_approx(view.sampled_time, before_pause), "living presentation freezes while tree is paused")
	paused = false
	player.combat.interrupt()
	var geometry: Node3D = run.room.get_node("NavigationRegion3D/Geometry") as Node3D
	var dressing: Node = geometry.get_node("RuinsDressing")
	_check(dressing.find_children("*", "CollisionObject3D", true, false).is_empty(), "Blender dressing adds no collision objects")
	_check(dressing.find_children("*", "NavigationRegion3D", true, false).is_empty(), "Blender dressing adds no navigation regions")
	_check(geometry.get_node("Ground/Collision").shape.size == Vector3(40, 1, 40), "physical arena floor remains 40 by 40 meters")
	_check(not geometry.get_node("Ground/Mesh").visible and geometry.get_node("Ground/Collision").disabled == false, "visual replacement preserves floor collision")
	player.health.receive_damage(100, DamageInfo.create(100, run.room.enemies[0], 2))
	_check(view.current_clip == &"Death" and is_zero_approx(view.sampled_time), "synchronous defeat clears attack pose before result pause")
	view._physics_process(0.4)
	_check(view.current_clip == &"Death" and view.sampled_time > 0.3, "only terminal visual collapse can finish behind paused results")
	paused = false
	run.queue_free()
	current_scene = null
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _gallery()
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("ART VALIDATION RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_model(path: String, index: int) -> void:
	var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		for child: Node in model.find_children("*", "Skeleton3D", true, false):
			skeleton = child as Skeleton3D
	var animation_player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_check(skeleton != null and skeleton.get_bone_count() >= 18, "%s skeleton and socket import" % model.name)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skinned_meshes: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.skin != null:
			skinned_meshes += 1
			_check(mesh.skin.get_bind_count() >= 16, "%s has actual skin bindings" % model.name)
	_check(skinned_meshes > 0, "%s contains skinned geometry" % model.name)
	var root_index: int = skeleton.find_bone("Root")
	var stationary: bool = true
	var finite_poses: bool = true
	for clip: StringName in animation_player.get_animation_list():
		if clip == &"RESET":
			continue
		animation_player.play(clip)
		var animation: Animation = animation_player.get_animation(clip)
		for fraction: float in [0.0, 0.5, 1.0]:
			animation_player.seek(animation.length * fraction, true)
			stationary = stationary and skeleton.get_bone_pose_position(root_index).length() < 0.0001
			for bone: int in range(skeleton.get_bone_count()):
				var pose: Transform3D = skeleton.get_bone_global_pose(bone)
				finite_poses = finite_poses and pose.origin.is_finite() and pose.basis.is_finite() and absf(pose.basis.determinant() - 1.0) < 0.01
	_check(stationary, "%s all clips have stationary root" % model.name)
	_check(finite_poses, "%s clip samples have finite unscaled bone transforms" % model.name)
	for clip: StringName in [&"Idle", &"Run", &"Jump", &"Fall", &"Dodge", &"Attack_01", &"Attack_02", &"Attack_03", &"Skill_01", &"Hurt", &"Death"]:
		_check(animation_player.has_animation(clip), "%s includes %s" % [model.name, clip])
	ToonPalette.apply_to(model)
	var first_mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var toon: ShaderMaterial = first_mesh.get_surface_override_material(0) as ShaderMaterial
	_check(toon != null and toon.next_pass != null, "%s uses Godot cel material and outline pass" % model.name)
	_test_trajectory(model, skeleton, animation_player, index)
	model.free()


func _test_trajectory(model: Node3D, rig: Skeleton3D, animator: AnimationPlayer, index: int) -> void:
	var configs: Array[Array] = [
		[["Attack_01", "res://resources/combat/attack_01.tres"], ["Attack_02", "res://resources/combat/attack_02.tres"], ["Attack_03", "res://resources/combat/attack_03.tres"], ["Skill_01", "res://resources/combat/star_blade.tres"]],
		[["Attack", "res://resources/enemies/sentinel_slash.tres"]],
		[["Attack_Sweep", "res://resources/boss/guardian_sweep.tres"], ["Attack_Shockwave", "res://resources/boss/guardian_shockwave.tres"]],
	]
	var weapon: Node3D = (load(WEAPONS[index]) as PackedScene).instantiate() as Node3D
	model.add_child(weapon)
	var minimum_z: float = INF
	for child: Node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		var to_weapon: Transform3D = weapon.global_transform.affine_inverse() * mesh.global_transform
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				minimum_z = minf(minimum_z, (to_weapon * vertex).z)
	var mesh_lengths: Array[float] = [0.88, 0.72, 1.34]
	_check(weapon.transform.is_equal_approx(Transform3D.IDENTITY) and absf(minimum_z + mesh_lengths[index]) < 0.005, "%s actual imported weapon geometry extends along root -Z with unit root transform" % model.name)
	var socket_index: int = rig.find_bone("WeaponSocket")
	weapon.basis = rig.get_bone_global_rest(socket_index).basis.orthonormalized().inverse()
	var lengths: Array[float] = [0.88, 0.72, 0.93]
	for config: Array in configs[index]:
		var clip: StringName = StringName(config[0])
		var attack: AttackDefinition = load(config[1]) as AttackDefinition
		_check(is_equal_approx(animator.get_animation(clip).length, attack.duration), "%s %s full clip matches immutable action duration" % [model.name, clip])
		animator.play(clip)
		var inside_sector: bool = true
		var minimum_angle: float = INF
		var maximum_angle: float = -INF
		var final_height: float = INF
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			animator.seek(lerpf(attack.hit_start, attack.hit_end, fraction), true)
			var grip: Transform3D = rig.get_bone_global_pose(socket_index) * weapon.transform
			var tip: Vector3 = grip * Vector3(0, 0, -lengths[index])
			var angle: float = rad_to_deg(atan2(tip.x, -tip.z))
			minimum_angle = minf(minimum_angle, angle)
			maximum_angle = maxf(maximum_angle, angle)
			final_height = tip.y
			inside_sector = inside_sector and absf(angle) <= attack.arc_degrees * 0.5 + 5.0 and tip.y > -0.15
		if attack.arc_degrees < 359.0:
			_check(inside_sector, "%s %s active weapon tip stays in forward sector (5 degree edge tolerance)" % [model.name, clip])
			_check(minimum_angle < 0.0 and maximum_angle > 0.0, "%s %s weapon actually sweeps across forward center" % [model.name, clip])
		else:
			_check(final_height >= -0.15 and final_height <= 0.35, "guardian shockwave hammer reaches ground during active window")
	weapon.free()


func _gallery() -> void:
	root.size = Vector2i(1280, 720)
	var gallery: Node3D = (load("res://scenes/art/ruins_arena.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(gallery)
	var animators: Array[AnimationPlayer] = []
	for index: int in range(MODELS.size()):
		var model: Node3D = (load(MODELS[index]) as PackedScene).instantiate() as Node3D
		gallery.add_child(model)
		model.position = Vector3((index - 1) * 2.0, 0, 5)
		ToonPalette.apply_to(model)
		var animation_player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animation_player.play("Idle")
		animation_player.seek(0.0, true)
		animators.append(animation_player)
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var socket: BoneAttachment3D = BoneAttachment3D.new()
		socket.bone_name = "WeaponSocket"
		skeleton.add_child(socket)
		var weapon: Node3D = (load(WEAPONS[index]) as PackedScene).instantiate() as Node3D
		socket.add_child(weapon)
		weapon.basis = skeleton.get_bone_global_rest(skeleton.find_bone("WeaponSocket")).basis.inverse()
		ToonPalette.apply_to(weapon)
	var camera: Camera3D = Camera3D.new()
	gallery.add_child(camera)
	camera.position = Vector3(4, 3.3, -2.5)
	camera.look_at(Vector3(0, 1.1, 5))
	camera.current = true
	camera.fov = 44
	await _ticks(3)
	RenderingServer.force_draw(false)
	await process_frame
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot != null and not screenshot.is_empty(), "Forward+ produces actual imported-asset frame")
	screenshot.save_png(ProjectSettings.globalize_path("res://").path_join("../docs/p6_character_preview.png"))
	for index: int in range(animators.size()):
		var clips: Array[String] = ["Skill_01", "Attack", "Attack_Shockwave"]
		var times: Array[float] = [0.325, 0.64, 1.4]
		animators[index].play(clips[index])
		animators[index].seek(times[index], true)
	await _ticks(3)
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../docs/p6_attack_preview.png"))
	gallery.queue_free()
	await process_frame


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
