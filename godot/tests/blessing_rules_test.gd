extends SceneTree
## Rule fixtures intentionally inject damage; graphical flow uses unmodified combat/input.

var _checks: int = 0
var _failures: int = 0
var _player: PlayerController
var _manager: BlessingManager


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_player)
	_manager = BlessingManager.new()
	_manager.pool.assign([
		load("res://resources/blessings/blessing_flame.tres"),
		load("res://resources/blessings/blessing_wind.tres"),
		load("res://resources/blessings/blessing_vitality.tres")
	])
	root.add_child(_manager)
	_manager.initialize(_player, 1729)
	var first: Array[BlessingDefinition] = _manager.offer()
	_check(first.size() == 3 and _ids(first).size() == 3, "first reward contains exactly three unique blessings")
	var ordering: Array[StringName] = _ids(first)
	_manager.initialize(_player, 1729)
	_check(_ids(_manager.offer()) == ordering, "same seed reproduces candidate order")
	_check(not _manager.choose(&"invalid") and _manager.acquired.is_empty(), "unknown candidate cannot be selected")
	_check(_manager.choose(&"blessing_flame"), "offered flame can be acquired")
	_check(not _manager.choose(&"blessing_flame") and _manager.acquired.size() == 1, "double click cannot stack an acquired blessing")
	var expected: Array[int] = [14, 19, 29]
	for index: int in range(3):
		_player.combat.start_attack()
		var info: DamageInfo = _player.combat.hitbox.damage_info
		_check(roundi(info.base_damage * info.attack_multiplier) == expected[index], "flame changes actual combo payload %d" % (index + 1))
		_player.combat.interrupt()
	_player.combat.start_skill()
	var skill_info: DamageInfo = _player.combat.hitbox.damage_info
	_check(is_equal_approx(skill_info.base_damage * skill_info.attack_multiplier, 35.0), "flame leaves skill payload at 35 damage")
	_player.combat.interrupt()
	var second: Array[BlessingDefinition] = _manager.offer()
	_check(second.size() == 2 and not _ids(second).has(&"blessing_flame"), "second reward excludes acquired blessing")
	_check(_manager.choose(&"blessing_wind"), "wind can be selected from remaining candidates")
	_player.state_machine.transition_to(PlayerStateMachine.State.DODGE)
	_check(is_equal_approx(_player.state_machine.cooldown_remaining, 0.9), "wind starts actual dodge timer at 0.9 seconds")
	_check(is_equal_approx(_player.movement_settings.dodge_cooldown, 1.2), "wind never mutates shared movement Resource")
	_check(is_equal_approx(_player.movement_settings.dodge_duration, 0.45) and is_equal_approx(_player.movement_settings.dodge_invulnerable_start, 0.1), "wind preserves dodge duration and invulnerability tuning")
	_manager.offer()
	_player.health.receive_damage(45, DamageInfo.create(45, null, 2))
	_check(_manager.choose(&"blessing_vitality") and _player.health.current_health == 75, "vitality immediately heals exactly 20 HP")
	_manager.on_ordinary_enemy_killed()
	_check(_player.health.current_health == 80, "vitality restores 5 HP per ordinary kill")
	for index: int in range(8):
		_manager.on_ordinary_enemy_killed()
	_check(_player.health.current_health == 100, "kill healing never exceeds max HP")
	_check(_manager.offer().is_empty(), "exhausted pool produces no duplicated rewards")
	_manager.clear()
	_check(_manager.acquired.is_empty() and _manager.candidates.is_empty(), "clear removes acquired and pending collections")
	_check(is_equal_approx(_player.combat.normal_attack_multiplier, 1.0) and is_equal_approx(_player.state_machine.get_dodge_cooldown_duration(), 1.2), "clear restores baseline combat and dodge effects")
	_player.health.protection_remaining = 0.0
	_player.health.set_invulnerable(&"dodge", false)
	_player.health.receive_damage(20, DamageInfo.create(20, null, 2))
	_manager.on_ordinary_enemy_killed()
	_check(_player.health.current_health == 80, "clear revokes future vitality kill healing")
	_check(is_equal_approx(_player.combat.settings.attacks[0].damage, 12.0), "shared attack Resource remains unchanged")
	_manager.offer()
	_manager.choose(&"blessing_vitality")
	_player.health.protection_remaining = 0.0
	_player.health.receive_damage(100, DamageInfo.create(100, null, 2))
	_manager.on_ordinary_enemy_killed()
	_check(not _player.health.is_alive(), "vitality never resurrects a dead player")
	_check(not _manager.choose(&"blessing_wind"), "dead player cannot choose a reward")
	_manager.free()
	_player.free()
	await process_frame
	print("BLESSING RULES RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _ids(values: Array[BlessingDefinition]) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: BlessingDefinition in values:
		if not result.has(value.id):
			result.append(value.id)
	return result


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
