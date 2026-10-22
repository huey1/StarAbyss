class_name GuardianBrain
extends EnemyBrain
## Specializes the shared enemy FSM. Actions remain immutable Resources.

signal move_selected(move_name: String)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _selected_attack: AttackDefinition
var _next_shockwave: bool = false
var last_attack_gap: float = 0.0


func initialize_seed(run_seed: int) -> void:
	_rng.seed = run_seed
	_next_shockwave = _rng.randi_range(0, 1) == 1


func _transition(next_state: State) -> void:
	var action_finished: bool = current_state in [State.TELEGRAPH, State.ATTACK, State.RECOVER] and next_state == State.CHASE
	if next_state == State.TELEGRAPH and current_state != State.TELEGRAPH and current_state != State.DEAD:
		var guardian: GuardianSettings = settings as GuardianSettings
		_selected_attack = guardian.shockwave if _next_shockwave else guardian.attack
		_next_shockwave = not _next_shockwave
		last_attack_gap = _rng.randf_range(guardian.minimum_attack_gap, guardian.maximum_attack_gap)
		move_selected.emit(_selected_attack.display_name)
	super._transition(next_state)
	if action_finished:
		# Hit stop can lengthen the action while base cooldown clocks continue.
		# Start the complete configured gap after recovery actually finishes.
		cooldown_remaining = last_attack_gap


func get_attack_definition() -> AttackDefinition:
	return _selected_attack if _selected_attack != null else settings.attack


func get_attack_cooldown() -> float:
	# Gap is measured after recovery, not from the beginning of the warning.
	return get_attack_definition().duration + last_attack_gap


func _on_damaged(_amount: int, _info: DamageInfo) -> void:
	# Resource config gives the guardian zero stagger. Damage/flash still apply;
	# ordinary hits cannot suppress both Boss moves through indefinite stunlock.
	if not health.is_alive():
		_transition(State.DEAD)
