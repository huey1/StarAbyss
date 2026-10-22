class_name RunMetrics
extends Node
## Opt-in local release profiling: StarAbyss.exe -- --profile-run
## Inactive by default. Never changes input, combat, time scale or quality settings.

const MAX_SAMPLES: int = 36000
var _enabled: bool = false
var _run: RunManager
var _previous_usec: int = 0
var _phase: String = ""
var _warmup_frames: int = 60
var _samples: Dictionary[String, Array] = {}
var _sample_count: int = 0
var _peak_nodes: int = 0


func _ready() -> void:
	_enabled = "--profile-run" in OS.get_cmdline_user_args()
	set_process(_enabled)
	if not _enabled:
		return
	if DisplayServer.get_name() == "headless":
		_enabled = false
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run = get_parent() as RunManager
	_run.state_changed.connect(_on_state_changed)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_previous_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = float(now - _previous_usec) / 1000.0
	_previous_usec = now
	if get_tree().paused or _run.current_state not in [RunManager.State.COMBAT, RunManager.State.EXPLORING]:
		return
	var next_phase: String = "room_%d_%s" % [_run.room_index + 1, "combat" if _run.current_state == RunManager.State.COMBAT else "traversal"]
	if next_phase != _phase:
		_phase = next_phase
		_warmup_frames = 60
	if _warmup_frames > 0:
		_warmup_frames -= 1
		return
	if _sample_count >= MAX_SAMPLES:
		return
	if not _samples.has(_phase):
		_samples[_phase] = []
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	_samples[_phase].append([
		frame_ms,
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
	])
	_sample_count += 1
	_peak_nodes = maxi(_peak_nodes, get_tree().get_node_count())


func _on_state_changed(state: RunManager.State) -> void:
	if state in [RunManager.State.WON, RunManager.State.FAILED]:
		_write_report.call_deferred()


func _write_report() -> void:
	if not _enabled:
		return
	var report: Dictionary = {
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(), "editor_feature": OS.has_feature("editor"),
		"gpu": RenderingServer.get_rendering_device().get_device_name(),
		"cpu": OS.get_processor_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"framebuffer": [get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()],
		"fps_cap": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"result": "won" if _run.current_state == RunManager.State.WON else "failed",
		"rooms_cleared": _run.rooms_cleared, "kills": _run.kills,
		"sample_count": _sample_count, "peak_nodes": _peak_nodes, "phases": {},
		"limits": "Opt-in local measurement, first 60 rendered frames per phase excluded, max 36000 samples. Actual user/OS input; does not automate play. Wall time includes pacing. No human feel or long-term stability claim.",
	}
	for phase_name: String in _samples:
		var wall: Array[float] = []
		var cpu: Array[float] = []
		var gpu: Array[float] = []
		var total_ms: float = 0.0
		for sample: Array in _samples[phase_name]:
			wall.append(sample[0])
			cpu.append(sample[1])
			gpu.append(sample[2])
			total_ms += sample[0]
		wall.sort()
		cpu.sort()
		gpu.sort()
		report.phases[phase_name] = {
			"samples": wall.size(), "seconds": total_ms / 1000.0,
			"mean_fps": wall.size() * 1000.0 / total_ms,
			"wall_ms_p50": _percentile(wall, 0.5), "wall_ms_p95": _percentile(wall, 0.95),
			"wall_ms_p99": _percentile(wall, 0.99), "wall_ms_max": wall[-1],
			"cpu_render_ms_p95": _percentile(cpu, 0.95), "gpu_ms_p95": _percentile(gpu, 0.95),
		}
	var path: String = "user://p7_runtime_profile.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save local runtime performance report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("RUNTIME PROFILE: " + ProjectSettings.globalize_path(path))


func _percentile(values: Array[float], fraction: float) -> float:
	return values[mini(values.size() - 1, int(ceil(values.size() * fraction)) - 1)]
