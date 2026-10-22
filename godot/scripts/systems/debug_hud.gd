extends CanvasLayer
## Passive view: reacts to the motor and camera signals, never drives gameplay.

@export var player_path: NodePath = NodePath("../Player")
@export var stage_text: String = "P2 战斗基础 / 灰盒训练场"
@export var hint_text: String = "左键三段剑击 · E 星刃斩 · 西侧橙色圆盘可测试受伤"

@onready var player: PlayerController = get_node(player_path) as PlayerController
@onready var state_label: Label = $Panel/Margin/Rows/State
@onready var speed_label: Label = $Panel/Margin/Rows/Speed
@onready var dodge_label: Label = $Panel/Margin/Rows/Dodge
@onready var cooldown_bar: ProgressBar = $Panel/Margin/Rows/Cooldown
@onready var mouse_label: Label = $Help/Margin/Rows/Mouse
@onready var health_label: Label = $Panel/Margin/Rows/Health
@onready var health_bar: ProgressBar = $Panel/Margin/Rows/HealthBar
@onready var action_label: Label = $Panel/Margin/Rows/Action
@onready var skill_label: Label = $Abilities/Margin/Rows/Skill
@onready var skill_bar: ProgressBar = $Abilities/Margin/Rows/SkillBar
@onready var dodge_status: Label = $Abilities/Margin/Rows/Dodge


func _ready() -> void:
	$Panel/Margin/Rows/Stage.text = stage_text
	$Help/Margin/Rows/Camera.text = hint_text
	player.telemetry_updated.connect(_on_telemetry_updated)
	player.camera_controller.capture_changed.connect(_on_capture_changed)
	player.health.health_changed.connect(_on_health_changed)
	$Reset.pressed.connect(_on_reset_pressed)
	health_bar.max_value = player.health.max_health
	skill_bar.max_value = player.combat.settings.skill_cooldown
	_on_health_changed(player.health.current_health, player.health.max_health)
	cooldown_bar.max_value = maxf(player.movement_settings.dodge_cooldown, 0.001)
	_on_capture_changed(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	_on_telemetry_updated(player.state_machine.get_state_name(), 0.0, 0.0)


func _on_telemetry_updated(state_name: String, speed: float, cooldown: float) -> void:
	state_label.text = "状态   /   %s" % state_name
	speed_label.text = "速度   /   %.2f m/s" % speed
	dodge_label.text = "闪避   /   %.2f 秒" % cooldown if cooldown > 0.0 else "闪避   /   就绪"
	if state_name == "Dodge":
		dodge_label.text = "闪避   /   进行中"
	cooldown_bar.value = cooldown
	var combat: PlayerCombat = player.combat
	skill_label.text = "E  星刃斩  /  %.1f 秒" % combat.skill_cooldown_remaining if combat.skill_cooldown_remaining > 0 else "E  星刃斩  /  就绪"
	skill_bar.value = combat.skill_cooldown_remaining
	dodge_status.text = "Shift 闪避 / %.1f 秒" % cooldown if cooldown > 0 else "Shift 闪避 / 就绪"
	if state_name == "Dodge":
		dodge_status.text += " 〔无敌〕" if player.health.is_invulnerable() else " 〔可受伤〕"
	action_label.text = "动作 / " + combat.current_attack.display_name if combat.current_attack != null else "左键普攻 · 后段点击衔接三连击"
	if not player.health.is_alive():
		action_label.text = "已倒下 · 点击右上角重置训练场"


func _on_capture_changed(captured: bool) -> void:
	mouse_label.text = "Esc 释放鼠标 · 可点击右上角重置" if captured else "左键捕获鼠标并恢复控制（本次点击不攻击）"
	if not player.health.is_alive():
		mouse_label.text = "已倒下 · 点击右上角重置训练场"


func _on_health_changed(current: int, maximum: int) -> void:
	health_label.text = "生命  %d / %d" % [current, maximum]
	health_bar.value = current


func _on_reset_pressed() -> void:
	var error: Error = get_tree().reload_current_scene()
	if error != OK:
		push_error("Failed to reset practice scene: %s" % error_string(error))
