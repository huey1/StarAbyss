class_name RunAudio
extends Node
## Scene-local result/reward cues remain audible while the result UI is paused.

signal cue_played(cue: StringName)

@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready() and not value:
			stop_all()
@export_range(-40.0, 0.0, 1.0) var volume_db: float = -8.0
@export_range(1, 3, 1) var max_voices: int = 2
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"scene_audio")
	for index: int in range(max_voices):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "Voice%d" % index
		voice.bus = &"UI"
		voice.finished.connect(_release_voice.bind(voice))
		add_child(voice)
		_voices.append(voice)
	var run: RunManager = get_parent() as RunManager
	assert(run != null, "RunAudio requires a run parent")
	run.state_changed.connect(_on_state_changed)
	(run.get_node("BlessingManager") as BlessingManager).selection_completed.connect(_on_blessing_selected)


func play_cue(cue: StringName) -> bool:
	if not enabled or not is_inside_tree() or _voices.is_empty():
		return false
	var stream: AudioStreamWAV = AudioCues.get_cue(cue)
	if stream == null:
		return false
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.play()
	cue_played.emit(cue)
	return true


func stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		_release_voice(voice)


func get_active_voice_count() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in _voices:
		if voice.stream != null:
			count += 1
	return count


func _release_voice(voice: AudioStreamPlayer) -> void:
	voice.stop()
	voice.stream = null


func _on_state_changed(state: RunManager.State) -> void:
	match state:
		RunManager.State.PAUSED, RunManager.State.TRANSITION:
			stop_all()
		RunManager.State.CHOOSING, RunManager.State.STAGE_COMPLETE:
			stop_all()
			play_cue(&"room_clear")
		RunManager.State.WON:
			stop_all()
			play_cue(&"victory")
		RunManager.State.FAILED:
			stop_all()
			play_cue(&"defeat")


func _on_blessing_selected(_blessing: BlessingDefinition) -> void:
	play_cue(&"blessing")


func _exit_tree() -> void:
	stop_all()
