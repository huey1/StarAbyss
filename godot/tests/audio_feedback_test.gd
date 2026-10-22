extends SceneTree
## Signal/audio lifecycle fixture; direct actions and damage are not a playthrough.

var _checks: int = 0
var _failures: int = 0
var _actor_cues: Array[StringName] = []
var _enemy_cues: Array[StringName] = []
var _run_cues: Array[StringName] = []


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	var hashes: Dictionary[int, bool] = {}
	for cue: StringName in AudioCues.STREAMS:
		var stream: AudioStreamWAV = AudioCues.get_cue(cue)
		_check(stream != null and not stream.stereo and stream.mix_rate == 44100 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.get_length() > 0.1 and stream.get_length() < 1.5, "%s imports as short nonlooping mono PCM cue" % cue)
		var peak: int = 0
		var data: PackedByteArray = stream.data
		for offset: int in range(0, data.size(), 2):
			peak = maxi(peak, absi(data.decode_s16(offset)))
		_check(peak > 1000 and peak < 20000 and data.decode_s16(0) == 0 and absi(data.decode_s16(data.size() - 2)) < 300, "%s has headroom and click-free endpoint envelope" % cue)
		hashes[hash(data)] = true
	_check(hashes.size() == 16, "all sixteen event cues have distinct waveform content")
	_check(AudioServer.get_bus_index(&"SFX") >= 0 and AudioServer.get_bus_index(&"UI") >= 0, "SFX and UI route through configured buses")
	var limiter: AudioEffect = AudioServer.get_bus_effect(0, 0)
	_check(limiter is AudioEffectHardLimiter and is_equal_approx((limiter as AudioEffectHardLimiter).ceiling_db, -1.0), "Master uses the configured hard limiter and ceiling")
	var run: RunManager = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	root.add_child(run)
	current_scene = run
	await _ticks(3)
	var player: PlayerController = run.player
	player.set_physics_process(false)
	for enemy: SentinelController in run.room.enemies:
		enemy.set_physics_process(false)
	var actor_audio: ActorAudio = player.get_node("Audio") as ActorAudio
	var enemy_audio: ActorAudio = run.room.enemies[0].get_node("Audio") as ActorAudio
	var run_audio: RunAudio = run.get_node("RunAudio") as RunAudio
	_check(actor_audio != null and enemy_audio != null and run_audio != null, "production actor and run scenes include audio components")
	actor_audio.cue_played.connect(_record_actor)
	enemy_audio.cue_played.connect(_record_enemy)
	run_audio.cue_played.connect(_record_run)
	for index: int in range(3):
		player.combat.start_attack()
		player.combat.interrupt()
	_check(_actor_cues == [&"swing_01", &"swing_02", &"swing_03"], "three accepted combo actions emit exactly one corresponding swing cue each")
	player.combat.start_skill()
	player.combat.interrupt()
	_check(_actor_cues.back() == &"skill" and _actor_cues.size() == 4, "accepted skill action emits a distinct single cue")
	player.state_machine.transition_to(PlayerStateMachine.State.DODGE)
	_check(_actor_cues.back() == &"dodge" and _actor_cues.size() == 5, "FSM dodge signal emits a single dodge cue")
	player.state_machine.transition_to(PlayerStateMachine.State.IDLE)
	var hit: DamageInfo = DamageInfo.create(10, run.room.enemies[0], 2)
	player.health.receive_damage(10, hit)
	_check(_actor_cues.back() == &"hurt" and _actor_cues.size() == 6, "actual Health damage emits player hurt once")
	player.health.receive_damage(10, hit)
	_check(_actor_cues.size() == 6, "deduplicated contact never emits another hurt cue")
	var brain: EnemyBrain = run.room.enemies[0].brain
	brain.attack_committed.emit(701)
	_check(_enemy_cues == [&"sentinel_warning"], "enemy commitment signal announces sentinel warning once")
	brain.state_changed.emit("Telegraph", "Attack")
	_check(_enemy_cues.back() == &"swing_02" and _enemy_cues.size() == 2, "enemy active state has its own swing sound")
	for index: int in range(24):
		actor_audio.play_cue(&"impact")
	_check(actor_audio.get_active_voice_count() <= actor_audio.max_voices and actor_audio.get_child_count() == actor_audio.max_voices, "bursts reuse a fixed voice pool without growing nodes")
	actor_audio.enabled = false
	_check(not actor_audio.play_cue(&"impact") and actor_audio.get_active_voice_count() == 0, "component mute immediately stops playback and rejects new cues")
	actor_audio.enabled = true
	actor_audio.play_cue(&"skill")
	run.pause()
	await _ticks(2)
	_check(actor_audio.get_active_voice_count() == 0 and enemy_audio.get_active_voice_count() == 0, "pause cleans actor playback instead of leaving voices running")
	_check(not actor_audio.play_cue(&"impact"), "paused actors cannot begin another cue")
	run.resume()
	run.state_changed.emit(RunManager.State.CHOOSING)
	_check(_run_cues == [&"room_clear"], "room-clear state emits one UI cue")
	run.blessings.selection_completed.emit(run.blessings.pool[0])
	_check(_run_cues.back() == &"blessing" and _run_cues.size() == 2, "blessing choice signal emits one reward cue")
	run.state_changed.emit(RunManager.State.WON)
	_check(_run_cues.back() == &"victory", "victory state selects victory fanfare")
	run.state_changed.emit(RunManager.State.FAILED)
	_check(_run_cues.back() == &"defeat", "failure state selects distinct defeat cue")
	run_audio.enabled = false
	_check(run_audio.get_active_voice_count() == 0 and not run_audio.play_cue(&"victory"), "UI mute also stops and suppresses result audio")
	run_audio.enabled = true
	paused = true
	_check(run_audio.play_cue(&"victory") and run_audio.get_active_voice_count() == 1, "result UI audio can play while gameplay is paused")
	run_audio.stop_all()
	_check(run_audio.get_active_voice_count() == 0, "explicit shutdown clears all UI stream references")
	paused = false
	run.free()
	current_scene = null
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("AUDIO FEEDBACK RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _record_actor(cue: StringName) -> void:
	_actor_cues.append(cue)


func _record_enemy(cue: StringName) -> void:
	_enemy_cues.append(cue)


func _record_run(cue: StringName) -> void:
	_run_cues.append(cue)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
