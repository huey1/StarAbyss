class_name AudioCues
extends RefCounted
## Immutable original PCM resources, generated offline by build_audio_assets.py.

const STREAMS: Dictionary[StringName, AudioStreamWAV] = {
	&"swing_01": preload("res://assets/audio/swing_01.wav"),
	&"swing_02": preload("res://assets/audio/swing_02.wav"),
	&"swing_03": preload("res://assets/audio/swing_03.wav"),
	&"skill": preload("res://assets/audio/skill.wav"),
	&"dodge": preload("res://assets/audio/dodge.wav"),
	&"impact": preload("res://assets/audio/impact.wav"),
	&"hurt": preload("res://assets/audio/hurt.wav"),
	&"sentinel_warning": preload("res://assets/audio/sentinel_warning.wav"),
	&"guardian_sweep_warning": preload("res://assets/audio/guardian_sweep_warning.wav"),
	&"guardian_shock_warning": preload("res://assets/audio/guardian_shock_warning.wav"),
	&"guardian_slam": preload("res://assets/audio/guardian_slam.wav"),
	&"shatter": preload("res://assets/audio/shatter.wav"),
	&"room_clear": preload("res://assets/audio/room_clear.wav"),
	&"blessing": preload("res://assets/audio/blessing.wav"),
	&"victory": preload("res://assets/audio/victory.wav"),
	&"defeat": preload("res://assets/audio/defeat.wav"),
}


static func get_cue(cue: StringName) -> AudioStreamWAV:
	return STREAMS.get(cue) as AudioStreamWAV
