extends SceneTree
## P8 design-landing fixture (game-dev / D6).
##
## Covers exactly the three batch-1 items of docs/DESIGN_REVIEW.md §3.1 and nothing else.
## Every assertion here is NEW; no existing suite is modified, and no expectation of the
## frozen 501 L1 assertions is touched.
##   I-1 perfect-dodge confirmation  -> GAMEPLAY_DESIGN §5.5 G-04A (SYSTEM_DESIGN §5.2)
##   I-2 failure attribution         -> GAMEPLAY_DESIGN §5.8 G-07
##   I-3 onboarding ONB-1..ONB-4     -> GAMEPLAY_DESIGN §4.4
##
## Direct HealthComponent calls are used so the fixture never depends on enemy AI timing.

var _checks: int = 0
var _failures: int = 0
var _run: RunManager
var _blocked_count: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	await _test_dodge_confirmation()
	await _test_fail_attribution()
	await _test_boss_attribution()
	print("DESIGN LANDING RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# --- I-1 完美闪避确认 (G-04A) ------------------------------------------------

func _test_dodge_confirmation() -> void:
	await _fresh()
	var health: HealthComponent = _run.player.health
	var ui: RunUI = _run.ui
	var confirm: Label = ui.find_child("DodgeConfirm", true, false) as Label
	_check(confirm != null, "I-1 HUD owns a dedicated dodge-confirmation label")
	_check(confirm != null and not confirm.visible, "I-1 dodge confirmation starts hidden")
	if confirm == null:
		await _teardown()
		return
	health.blocked.connect(_on_blocked)

	# 1. A hit inside a dodge i-frame is still worth 0 damage and now reports itself.
	_blocked_count = 0
	health.set_invulnerable(&"dodge", true)
	var blocked_damage: int = health.receive_damage(20, DamageInfo.create(20.0, null, 2))
	_check(blocked_damage == 0, "I-1 a dodge i-frame still returns 0 damage (combat rules unchanged)")
	_check(_blocked_count == 1, "I-1 a hit inside a dodge i-frame emits blocked exactly once")
	_check(confirm.visible and confirm.text.contains("完美闪避"), "I-1 HUD shows 完美闪避 when the dodge i-frame blocks a hit")

	await create_timer(0.75).timeout
	_check(not confirm.visible, "I-1 完美闪避 confirmation hides by itself after 0.6 s")

	# 2. A normal hit must behave exactly as before and must not claim a perfect dodge.
	health.set_invulnerable(&"dodge", false)
	health.protection_remaining = 0.0
	_blocked_count = 0
	var health_before: int = health.current_health
	var applied: int = health.receive_damage(12, DamageInfo.create(12.0, null, 2))
	_check(applied == 12 and health.current_health == health_before - 12, "I-1 a normal hit still applies its full damage")
	_check(_blocked_count == 0, "I-1 a normal hit does not emit blocked")
	_check(not confirm.visible, "I-1 a normal hit never shows 完美闪避")

	# 3. Post-hit protection is invulnerability too: it reports blocked, but is not a dodge.
	_blocked_count = 0
	var protected_damage: int = health.receive_damage(12, DamageInfo.create(12.0, null, 2))
	_check(protected_damage == 0 and health.current_health == health_before - 12, "I-1 post-hit protection still absorbs damage (return value unchanged)")
	_check(_blocked_count == 1, "I-1 post-hit protection reports a block through the new signal")
	_check(not confirm.visible, "I-1 only dodge i-frames show 完美闪避, post-hit protection does not")

	# 4. One attack can never report two blocks (the existing attack-id memory still applies).
	health.set_invulnerable(&"dodge", true)
	_blocked_count = 0
	var repeated: DamageInfo = DamageInfo.create(20.0, null, 2)
	health.receive_damage(20, repeated)
	health.receive_damage(20, repeated)
	_check(_blocked_count == 1, "I-1 one attack id can never report two blocks")

	await _teardown()


# --- I-2 失败归因 (G-07) -----------------------------------------------------

func _test_fail_attribution() -> void:
	await _fresh()
	var player: PlayerController = _run.player
	var ui: RunUI = _run.ui
	var sentinel: SentinelController = _run.room.enemies[0]
	var subtitle: Label = ui.find_child("ModalSubtitle", true, false) as Label
	_check(_run.last_hit_summary.is_empty(), "I-2 no failure cause is invented before the player dies")

	# The cause is derived from the attacker's own Resources, not from hardcoded text.
	var sentinel_cause: String = _run.describe_damage_source(DamageInfo.create(10.0, sentinel, 2))
	_check(sentinel_cause.contains("遗迹哨兵") and sentinel_cause.contains("哨兵横扫"),
		"I-2 a sentinel hit names the sentinel and the move that landed (%s)" % sentinel_cause)
	_check(sentinel_cause.contains("10 伤害"), "I-2 the cause reports the move's own damage, not the overkill amount")
	_check(_run.describe_damage_source(null) == "未知来源", "I-2 a hit without an attacker degrades to 未知来源 instead of crashing")

	# The death screen itself carries the attribution, and the FAILED state is unchanged.
	var lethal: int = player.health.receive_damage(100, DamageInfo.create(10.0, sentinel, 2))
	await _ticks(4)
	_check(lethal == 100 and player.health.current_health == 0, "I-2 the killing blow still resolves through the frozen damage rules")
	_check(_run.current_state == RunManager.State.FAILED, "I-2 death still enters FAILED (state machine untouched)")
	_check(not _run.last_hit_summary.is_empty() and _run.last_hit_summary.contains("遗迹哨兵"),
		"I-2 RunManager records the cause of the killing blow")
	_check(subtitle != null and subtitle.text.contains("最后一击：") and subtitle.text.contains("遗迹哨兵"),
		"I-2 the failure screen shows 最后一击 with the attacker and move")
	_check(subtitle != null and subtitle.text.contains("倒在第 1 房") and subtitle.text.contains("剩余生命 0 / 100"),
		"I-2 the failure screen shows the room reached and the remaining health")
	_check(_has_label_containing(ui, "探索者已倒下"), "I-2 the failure title is unchanged")

	await _teardown()


# --- I-2 boss branch: real guardian wiring, not a standalone instantiation ---------

func _test_boss_attribution() -> void:
	await _fresh()
	# Walk the production transition path instead of instantiating the boss alone:
	# a detached guardian has no ../../Player target and would log SCRIPT ERRORs.
	_run.room_index = 1
	_run._set_state(RunManager.State.TRANSITION)
	_run._advance_room()
	await _ticks(10)
	var boss: SentinelController = _run.room.boss
	_check(boss != null, "I-2 the boss room still spawns the guardian through the normal transition")
	if boss != null:
		var cause: String = _run.describe_damage_source(DamageInfo.create(25.0, boss, 2))
		_check(cause.contains("晶核守卫") and cause.contains("重锤横扫"),
			"I-2 a guardian hit names 晶核守卫 and its move (%s)" % cause)
	await _teardown()


# --- helpers ---------------------------------------------------------------

func _has_label_containing(container: Node, needle: String) -> bool:
	for node: Node in container.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label != null and label.text.contains(needle):
			return true
	return false


func _on_blocked(_info: DamageInfo) -> void:
	_blocked_count += 1


func _fresh() -> void:
	_run = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	_run.run_seed = 2468
	root.add_child(_run)
	current_scene = _run
	_run.player.camera_controller.set_process_unhandled_input(false)
	await _ticks(12)
	for enemy: SentinelController in _run.room.enemies:
		enemy.set_physics_process(false)


func _teardown() -> void:
	# Damage cues are still playing when the fixture ends; stop them and give the audio
	# server real time to release the playbacks. The wait is on the wall clock, not a
	# SceneTreeTimer: under `--fixed-fps 60` a simulated 0.25 s elapses in a few real
	# milliseconds, which is why this class of leak is recorded as DEF-03 in docs/FIXES.md.
	var audio: Node = _run.find_child("RunAudio", true, false)
	if audio != null and audio.has_method("stop_all"):
		audio.stop_all()
	current_scene = null
	_run.queue_free()
	var deadline: int = Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
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
