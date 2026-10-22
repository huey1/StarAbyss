class_name PlayerStateMachine
extends Node
## Explicit priority. Health owns stagger/protection; combat owns attack clocks.

signal state_changed(previous: String, current: String)
signal dodge_started(direction: Vector3)
signal dodge_finished

enum State { IDLE, MOVE, JUMP, FALL, DODGE, ATTACK, SKILL, HURT, DEAD }

var current_state: State = State.IDLE
var cooldown_remaining: float = 0.0
var dodge_cooldown_multiplier: float = 1.0
var dodge_remaining: float = 0.0
var dodge_elapsed: float = 0.0
var dodge_direction: Vector3 = Vector3.FORWARD
var _player: PlayerController


func initialize(player: PlayerController) -> void:
	_player = player
	_player.health.damaged.connect(_on_damaged)
	_player.health.died.connect(_on_died)
	transition_to(State.FALL)


func physics_step(delta: float) -> void:
	if not _player.health.is_alive():
		transition_to(State.DEAD)
	elif _player.health.stagger_remaining > 0.0 and current_state != State.SKILL:
		transition_to(State.HURT)
	elif current_state == State.HURT:
		transition_to(_locomotion_state())

	if current_state == State.DODGE:
		dodge_elapsed += delta
		dodge_remaining = maxf(0.0, _player.movement_settings.dodge_duration - dodge_elapsed)
		if dodge_remaining <= 0.00001:
			transition_to(_locomotion_state())
	elif current_state in [State.ATTACK, State.SKILL]:
		if current_state == State.ATTACK and _player.dodge_requested and _can_dodge() and _player.combat.can_cancel_with_dodge():
			transition_to(State.DODGE)
		else:
			_player.combat.advance_action(delta)
			if _player.combat.current_attack == null:
				transition_to(_locomotion_state())
	elif current_state in [State.IDLE, State.MOVE, State.JUMP, State.FALL]:
		transition_to(_locomotion_state())
		if current_state in [State.IDLE, State.MOVE] and _player.is_on_floor():
			_request_ground_action()

	match current_state:
		State.IDLE, State.MOVE:
			_player.move_horizontal(delta, false)
		State.JUMP, State.FALL:
			_player.move_horizontal(delta, true)
		State.DODGE:
			var settings: PlayerMovementSettings = _player.movement_settings
			_player.health.set_invulnerable(&"dodge", dodge_elapsed + 0.00001 >= settings.dodge_invulnerable_start and dodge_elapsed < settings.dodge_invulnerable_end - 0.00001)
			_player.move_dodge(dodge_direction, delta)
		State.ATTACK, State.SKILL:
			_player.move_action(delta, true)
		State.HURT, State.DEAD:
			_player.move_action(delta, false)
	_player.apply_gravity(delta)


func tick_cooldown(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)


func _request_ground_action() -> void:
	if _player.dodge_requested and _can_dodge():
		transition_to(State.DODGE)
	elif _player.skill_requested and _player.combat.skill_cooldown_remaining <= 0.0:
		transition_to(State.SKILL)
	elif _player.attack_requested:
		transition_to(State.ATTACK)
	elif _player.jump_requested:
		_player.start_jump()
		transition_to(State.JUMP)


func _can_dodge() -> bool:
	return _player.is_on_floor() and cooldown_remaining <= 0.0 and _player.health.stagger_remaining <= 0.0


func after_move() -> void:
	if current_state in [State.IDLE, State.MOVE, State.JUMP, State.FALL]:
		transition_to(_locomotion_state())


func transition_to(next_state: State) -> void:
	if next_state == current_state or current_state == State.DEAD:
		return
	var previous_name: String = get_state_name()
	if current_state == State.DODGE:
		_player.health.set_invulnerable(&"dodge", false)
		_player.stop_horizontal()
		dodge_remaining = 0.0
		dodge_finished.emit()
	if current_state in [State.ATTACK, State.SKILL]:
		_player.combat.interrupt()
	current_state = next_state
	match current_state:
		State.DODGE:
			dodge_elapsed = 0.0
			dodge_remaining = _player.movement_settings.dodge_duration
			cooldown_remaining = get_dodge_cooldown_duration()
			dodge_direction = _player.move_direction.normalized() if _player.move_direction.length_squared() > 0.001 else _player.get_facing_direction()
			dodge_started.emit(dodge_direction)
		State.ATTACK:
			_player.combat.start_attack()
		State.SKILL:
			_player.combat.start_skill()
		State.HURT:
			_player.stop_horizontal()
		State.DEAD:
			_player.combat.interrupt()
			_player.stop_horizontal()
			_player.health.set_invulnerable(&"dodge", false)
			_player.camera_controller.set_mouse_captured(false)
			if not _player.visual.has_node("ActorPresentation"):
				_player.visual.rotation.z = -1.2
	state_changed.emit(previous_name, get_state_name())


func _on_damaged(_amount: int, _info: DamageInfo) -> void:
	if not _player.health.is_alive():
		transition_to(State.DEAD)
	elif current_state != State.SKILL:
		transition_to(State.HURT)


func _on_died(_info: DamageInfo) -> void:
	transition_to(State.DEAD)


func _locomotion_state() -> State:
	if not _player.is_on_floor() or _player.velocity.y > 0.0:
		return State.JUMP if _player.velocity.y > 0.0 else State.FALL
	if _player.move_direction.length_squared() > 0.001 or _player.get_horizontal_speed() > 0.1:
		return State.MOVE
	return State.IDLE


func get_state_name() -> String:
	return ["Idle", "Move", "Jump", "Fall", "Dodge", "Attack", "Skill", "Hurt", "Dead"][current_state]


func get_dodge_cooldown_duration() -> float:
	return _player.movement_settings.dodge_cooldown * dodge_cooldown_multiplier
