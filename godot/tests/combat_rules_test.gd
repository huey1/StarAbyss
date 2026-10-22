extends SceneTree
## Headless, deterministic domain checks. Actual Area contacts are covered by window tests.

var _checks: int = 0
var _failures: int = 0
var _deaths: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(CombatResolver.calculate_damage(12, 1.0, 1.0) == 12, "base damage")
	_check(CombatResolver.calculate_damage(12, 1.2, 1.0) == 14, "rounded attack multiplier")
	_check(CombatResolver.calculate_damage(35, 1.0, 0.5) == 18, "target damage multiplier")
	_check(CombatResolver.calculate_damage(1, 0.0, 0.0) == 1, "minimum damage is one")
	var settings: PlayerCombatSettings = load("res://resources/combat/default_player_combat.tres") as PlayerCombatSettings
	var damages: Array[float] = [12.0, 16.0, 24.0]
	var durations: Array[float] = [0.48, 0.56, 0.72]
	var starts: Array[float] = [0.16, 0.20, 0.25]
	var ends: Array[float] = [0.28, 0.34, 0.44]
	for index: int in range(3):
		var attack: AttackDefinition = settings.attacks[index]
		_check(is_equal_approx(attack.damage, damages[index]) and is_equal_approx(attack.duration, durations[index]) and is_equal_approx(attack.hit_start, starts[index]) and is_equal_approx(attack.hit_end, ends[index]), "GDD attack %d damage/duration/hit window" % (index + 1))
	_check(is_equal_approx(settings.input_buffer_duration, 0.18) and is_equal_approx(settings.combo_reset_duration, 0.9), "GDD buffer and combo reset configuration")
	_check(is_equal_approx(settings.skill.damage, 35.0) and is_equal_approx(settings.skill.duration, 0.7) and is_equal_approx(settings.skill_cooldown, 8.0), "GDD skill damage/duration/cooldown")
	var geometry: Hitbox = Hitbox.new()
	root.add_child(geometry)
	geometry.definition = settings.skill
	_check(geometry.contains_target(Vector3(0, 0, -4.99)), "skill includes forward target within five meters")
	_check(not geometry.contains_target(Vector3(0, 0, -5.01)), "skill excludes target beyond five meters")
	_check(geometry.contains_target(Vector3(sin(deg_to_rad(34.9)), 0, -cos(deg_to_rad(34.9))) * 4.0), "skill includes target within half-angle")
	_check(not geometry.contains_target(Vector3(sin(deg_to_rad(35.1)), 0, -cos(deg_to_rad(35.1))) * 4.0), "skill excludes target beyond half-angle")
	_check(not geometry.contains_target(Vector3(0, 1.5, -1)), "vertical separation prevents attacks through platforms")
	geometry.queue_free()
	var target: Node3D = Node3D.new()
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	target.add_child(health)
	var hurtbox: Hurtbox = Hurtbox.new()
	target.add_child(hurtbox)
	root.add_child(target)
	health.died.connect(_on_death)
	var info: DamageInfo = DamageInfo.create(12, null, 1)
	_check(CombatResolver.resolve(info, hurtbox) == 12 and health.current_health == 88, "resolver updates HP")
	_check(CombatResolver.resolve(info, hurtbox) == 0 and health.current_health == 88, "same attack ID cannot damage twice")
	_check(CombatResolver.resolve(DamageInfo.create(20, null, 1), hurtbox) == 0, "post-hit protection blocks new attacks")
	_check(health.stagger_remaining > 0.0, "damage starts independent stagger")
	health.protection_remaining = 0.0
	health.stagger_remaining = 0.0
	health.set_invulnerable(&"dodge", true)
	var blocked: DamageInfo = DamageInfo.create(20, null, 1)
	_check(CombatResolver.resolve(blocked, hurtbox) == 0, "explicit invulnerability blocks damage")
	_check(health.stagger_remaining == 0.0, "invulnerable hit does not cause stagger")
	health.set_invulnerable(&"cutscene", true)
	health.set_invulnerable(&"dodge", false)
	_check(health.is_invulnerable(), "removing dodge does not erase another protection reason")
	health.set_invulnerable(&"cutscene", false)
	_check(CombatResolver.resolve(blocked, hurtbox) == 0, "blocked attack stays consumed after invulnerability ends")
	_check(CombatResolver.resolve(DamageInfo.create(12, null, 2), hurtbox) == 0, "same team cannot damage itself")
	_check(health.heal(999) == 12 and health.current_health == 100, "heal clamps to maximum")
	_check(CombatResolver.resolve(DamageInfo.create(999, null, 1), hurtbox) == 100, "lethal damage clamps HP to zero")
	_check(not health.is_alive() and _deaths == 1, "death is emitted once")
	_check(CombatResolver.resolve(DamageInfo.create(999, null, 1), hurtbox) == 0 and _deaths == 1, "dead target rejects more damage")
	_check(health.heal(100) == 0, "heal cannot resurrect dead targets")
	target.queue_free()
	await process_frame
	print("COMBAT RULES RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _on_death(_info: DamageInfo) -> void:
	_deaths += 1


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
