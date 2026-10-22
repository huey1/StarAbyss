class_name PlayerCombat
extends Node
## Action timing, bounded buffering and hitbox ownership. FSM decides when actions may start.

signal action_started(action_name: String, combo_step: int)
signal hit_landed(target: Hurtbox, damage: int)

@export var settings: PlayerCombatSettings
@export var attack_multiplier: float = 1.0
var normal_attack_multiplier: float = 1.0
var current_attack: AttackDefinition
var elapsed: float = 0.0
var combo_index: int = -1
var is_skill: bool = false
var skill_cooldown_remaining: float = 0.0
var _buffer_remaining: float = 0.0
var _buffered_at: float = 0.0
var _combo_idle_remaining: float = 0.0
@onready var hitbox: Hitbox = $"../Visual/Hitbox"
@onready var weapon: WeaponVisual = $"../Visual/CombatVisual"


func _ready() -> void:
	assert(settings != null and settings.attacks.size() == 3 and settings.skill != null)
	hitbox.hit_confirmed.connect(_on_hit_confirmed)


func tick_cooldowns(delta: float) -> void:
	skill_cooldown_remaining = maxf(0.0, skill_cooldown_remaining - delta)
	_buffer_remaining = maxf(0.0, _buffer_remaining - delta)
	if current_attack == null:
		_combo_idle_remaining = maxf(0.0, _combo_idle_remaining - delta)
		if _combo_idle_remaining <= 0.0:
			combo_index = -1


func start_attack() -> void:
	combo_index = (combo_index + 1) % settings.attacks.size()
	_begin(settings.attacks[combo_index], false)


func start_skill() -> void:
	skill_cooldown_remaining = settings.skill_cooldown
	_begin(settings.skill, true)


func _begin(attack: AttackDefinition, skill_action: bool) -> void:
	current_attack = attack
	is_skill = skill_action
	elapsed = 0.0
	_buffer_remaining = 0.0
	_combo_idle_remaining = 0.0
	var source: Node3D = get_parent() as Node3D
	var multiplier: float = attack_multiplier * (1.0 if skill_action else normal_attack_multiplier)
	hitbox.begin_attack(attack, DamageInfo.create(attack.damage, source, 1, multiplier))
	weapon.begin(attack)
	weapon.pose(attack, 0.0, false)
	action_started.emit(attack.display_name, 0 if is_skill else combo_index + 1)


func buffer_attack() -> void:
	if current_attack != null and not is_skill:
		_buffer_remaining = settings.input_buffer_duration
		_buffered_at = elapsed


func can_cancel_with_dodge() -> bool:
	return current_attack != null and not is_skill and elapsed >= current_attack.dodge_cancel_open and elapsed <= current_attack.dodge_cancel_close


func advance_action(delta: float) -> void:
	if current_attack == null:
		return
	var previous_time: float = elapsed
	elapsed += delta
	# Intersect the step with the hit interval; a slower frame cannot skip the whole window.
	var active_window: bool = previous_time < current_attack.hit_end and elapsed >= current_attack.hit_start
	hitbox.active = active_window
	weapon.pose(current_attack, elapsed, active_window)
	hitbox.sample()
	# Synchronous hit/death listeners may settle a run and interrupt this action.
	if current_attack == null:
		return
	if elapsed + 0.00001 >= current_attack.duration:
		var chain: bool = not is_skill and _buffer_remaining > 0.0 and elapsed >= current_attack.combo_open and _buffered_at <= current_attack.combo_close
		interrupt()
		if chain:
			start_attack()


func interrupt() -> void:
	if current_attack != null and not is_skill:
		_combo_idle_remaining = settings.combo_reset_duration
	current_attack = null
	is_skill = false
	_buffer_remaining = 0.0
	hitbox.end_attack()
	weapon.clear_pose()


func _on_hit_confirmed(target: Hurtbox, damage: int) -> void:
	hit_landed.emit(target, damage)
