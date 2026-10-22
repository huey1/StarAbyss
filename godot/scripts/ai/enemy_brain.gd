class_name EnemyBrain
extends Node
## Independent enemy FSM. Communicates with the motor through movement commands.

signal state_changed(previous: String, current: String)
signal attack_committed(attack_id: int)

enum State { IDLE, CHASE, TELEGRAPH, ATTACK, RECOVER, RETURN, HURT, DEAD }

@export var settings: SentinelSettings
@export var target_path: NodePath = NodePath("../../Player")
@export var coordinator_path: NodePath = NodePath("../../AttackCoordinator")

var current_state: State = State.IDLE
var desired_direction: Vector3 = Vector3.ZERO
var look_direction: Vector3 = Vector3.FORWARD
var movement_locked: bool = false
var action_elapsed: float = 0.0
var cooldown_remaining: float = 0.0
var navigation_status: String = "等待导航同步"
var stuck_events: int = 0
var _home_position: Vector3
var _repath_remaining: float = 0.0
var _reengage_remaining: float = 0.0
var _blocked_time: float = 0.0
var _blocked_retries: int = 0
var _has_path_request: bool = false
var _path_goal: Vector3 = Vector3.ZERO
var _target_probe_remaining: float = 0.0
var _target_reachable: bool = false

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var agent: NavigationAgent3D = $"../NavigationAgent3D"
@onready var health: HealthComponent = $"../Health"
@onready var hitbox: Hitbox = $"../Visual/Hitbox"
@onready var weapon: WeaponVisual = $"../Visual/CombatVisual"
@onready var visual: Node3D = $"../Visual"
@onready var target: CharacterBody3D = get_node(target_path) as CharacterBody3D
@onready var target_health: HealthComponent = target.get_node("Health") as HealthComponent
@onready var coordinator: AttackCoordinator = get_node(coordinator_path) as AttackCoordinator


func _ready() -> void:
	assert(settings != null and settings.attack != null)
	assert(target != null and target_health != null and coordinator != null)
	_home_position = body.global_position
	agent.max_speed = settings.move_speed
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	target_health.died.connect(_on_target_died)


func tick_cooldowns(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	_reengage_remaining = maxf(0.0, _reengage_remaining - delta)
	_repath_remaining = maxf(0.0, _repath_remaining - delta)
	_target_probe_remaining = maxf(0.0, _target_probe_remaining - delta)


func physics_step(delta: float) -> void:
	desired_direction = Vector3.ZERO
	if not health.is_alive():
		_transition(State.DEAD)
	if current_state == State.DEAD:
		return
	if health.stagger_remaining > 0.0:
		_transition(State.HURT)
	elif current_state == State.HURT:
		_transition(State.CHASE if _can_sense_target() else State.RETURN)
	if not _navigation_ready():
		navigation_status = "等待导航同步"
		return
	match current_state:
		State.IDLE:
			if _reengage_remaining <= 0.0 and _can_sense_target():
				_transition(State.CHASE)
		State.CHASE:
			_step_chase(delta)
		State.TELEGRAPH, State.ATTACK, State.RECOVER:
			_step_action(delta)
		State.RETURN:
			_step_return(delta)
	movement_locked = current_state in [State.TELEGRAPH, State.ATTACK, State.RECOVER, State.HURT, State.DEAD]


func _step_chase(delta: float) -> void:
	if not _can_sense_target():
		_transition(State.RETURN)
		return
	var goal: Vector3 = target.global_position
	var closest_target: Vector3 = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), goal)
	if closest_target.distance_to(goal) > settings.target_nav_tolerance:
		navigation_status = "目标离开可行走区域"
		_transition(State.RETURN)
		return
	if _target_probe_remaining <= 0.0:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(agent.get_navigation_map(), body.global_position, closest_target, true)
		_target_reachable = not path.is_empty() and path[path.size() - 1].distance_to(closest_target) <= 0.3
		_target_probe_remaining = settings.repath_interval
	if not _target_reachable:
		navigation_status = "目标路径不可达"
		_transition(State.RETURN)
		return
	var offset: Vector3 = target.global_position - body.global_position
	var distance: float = Vector2(offset.x, offset.z).length()
	var visible_for_attack: bool = distance <= settings.waiting_distance + 0.2 and _target_visible()
	var can_request: bool = visible_for_attack and cooldown_remaining <= 0.0 and absf(offset.y) < 1.2
	if not can_request:
		coordinator.cancel_request(body)
	var has_permit: bool = can_request and coordinator.request_slot(body)
	if has_permit:
		look_direction = Vector3(offset.x, 0, offset.z).normalized()
	elif visible_for_attack:
		# Wait outside melee range. Do not occupy the active attacker's approach lane.
		var away: Vector3 = Vector3(-offset.x, 0, -offset.z).normalized()
		if away.length_squared() < 0.001:
			away = Vector3.RIGHT
		goal = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), target.global_position + away * settings.waiting_distance)
		look_direction = Vector3(offset.x, 0, offset.z).normalized()
	# One agent update per physics step, including while waiting on a permit.
	if not _navigate_to(goal, delta):
		_transition(State.RETURN)
		return
	if has_permit and distance <= settings.attack_trigger_distance:
		look_direction = Vector3(offset.x, 0, offset.z).normalized()
		_transition(State.TELEGRAPH)


func _step_return(delta: float) -> void:
	coordinator.cancel_request(body)
	var safe_home: Vector3 = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), _home_position)
	if _flat_distance(body.global_position, safe_home) <= 0.35:
		navigation_status = "已回到待机位置"
		_transition(State.IDLE)
	elif not _navigate_to(safe_home, delta):
		# A changed/disconnected map must never cause endless walking against a wall.
		_home_position = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), body.global_position)
		_reengage_remaining = settings.reengage_delay
		_transition(State.IDLE)


func _step_action(delta: float) -> void:
	if not is_instance_valid(target) or not target_health.is_alive():
		_transition(State.RETURN)
		return
	var previous: float = action_elapsed
	action_elapsed += delta
	var attack: AttackDefinition = get_attack_definition()
	if action_elapsed + 0.00001 >= attack.duration:
		_transition(State.CHASE)
		return
	if action_elapsed + 0.00001 >= attack.hit_end:
		_transition(State.RECOVER)
	elif action_elapsed + 0.00001 >= attack.hit_start:
		_transition(State.ATTACK)
	var crossed_window: bool = previous < attack.hit_end and action_elapsed + 0.00001 >= attack.hit_start
	hitbox.active = crossed_window
	weapon.pose(attack, action_elapsed, current_state == State.ATTACK)
	hitbox.sample()
	# Damage signals may synchronously kill the target and cancel this action.
	if current_state not in [State.TELEGRAPH, State.ATTACK, State.RECOVER]:
		return
	hitbox.active = current_state == State.ATTACK


func _navigate_to(goal: Vector3, _delta: float) -> bool:
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), goal)
	if closest.distance_to(goal) > settings.target_nav_tolerance:
		navigation_status = "目标离开可行走区域"
		return false
	if not _has_path_request or _repath_remaining <= 0.0 or _path_goal.distance_to(closest) > 0.6:
		agent.target_position = closest
		_path_goal = closest
		_has_path_request = true
		_repath_remaining = settings.repath_interval
	var next_position: Vector3 = agent.get_next_path_position()
	# Agent path points are offset to foot height; compare planar endpoint here.
	# The independent map query above validates full 3D target connectivity.
	if agent.get_current_navigation_path().is_empty() or _flat_distance(agent.get_final_position(), closest) > 0.3:
		navigation_status = "路径不可达，撤回"
		return false
	if agent.is_navigation_finished():
		desired_direction = Vector3.ZERO
	else:
		desired_direction = next_position - body.global_position
		desired_direction.y = 0.0
		desired_direction = desired_direction.normalized()
		look_direction = desired_direction
	navigation_status = "导航正常"
	return true


func report_motion(distance_moved: float, delta: float) -> void:
	if current_state not in [State.CHASE, State.RETURN] or desired_direction.length_squared() < 0.01:
		_blocked_time = 0.0
		return
	if distance_moved < 0.005:
		_blocked_time += delta
	else:
		_blocked_time = 0.0
		_blocked_retries = 0
	if _blocked_time >= settings.stuck_timeout:
		_blocked_time = 0.0
		_blocked_retries += 1
		stuck_events += 1
		_has_path_request = false
		navigation_status = "受阻，重新寻路"
		if _blocked_retries >= 2:
			_blocked_retries = 0
			if current_state == State.RETURN:
				_home_position = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), body.global_position)
				_reengage_remaining = settings.reengage_delay
				_transition(State.IDLE)
			else:
				_transition(State.RETURN)


func _transition(next_state: State) -> void:
	if next_state == current_state or current_state == State.DEAD:
		return
	var previous: String = get_state_name()
	var action_states: Array[State] = [State.TELEGRAPH, State.ATTACK, State.RECOVER]
	if current_state in action_states and next_state not in action_states:
		hitbox.end_attack()
		weapon.clear_pose()
		coordinator.cancel_request(body)
	current_state = next_state
	desired_direction = Vector3.ZERO
	movement_locked = current_state in [State.TELEGRAPH, State.ATTACK, State.RECOVER, State.HURT, State.DEAD]
	_has_path_request = false
	_target_probe_remaining = 0.0
	match current_state:
		State.TELEGRAPH:
			action_elapsed = 0.0
			cooldown_remaining = get_attack_cooldown()
			visual.rotation.y = atan2(-look_direction.x, -look_direction.z)
			var attack: AttackDefinition = get_attack_definition()
			hitbox.begin_attack(attack, DamageInfo.create(attack.damage, body, 2))
			weapon.begin(attack)
			weapon.pose(attack, 0.0, false)
			attack_committed.emit(hitbox.damage_info.attack_id)
		State.RECOVER:
			hitbox.active = false
		State.RETURN:
			coordinator.cancel_request(body)
			_reengage_remaining = settings.reengage_delay
		State.HURT, State.DEAD:
			coordinator.cancel_request(body)
			hitbox.end_attack()
			weapon.clear_pose()
	state_changed.emit(previous, get_state_name())


func _navigation_ready() -> bool:
	var map: RID = agent.get_navigation_map()
	return NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map, body.global_position).is_valid()


func _can_sense_target() -> bool:
	return is_instance_valid(target) and target_health.is_alive() and body.global_position.distance_to(target.global_position) <= settings.detection_radius and _flat_distance(body.global_position, _home_position) <= settings.home_leash_distance


func _target_visible() -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.9, target.global_position + Vector3.UP * 0.9, 1)
	return body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_damaged(_amount: int, _info: DamageInfo) -> void:
	_transition(State.HURT if health.is_alive() else State.DEAD)


func _on_died(_info: DamageInfo) -> void:
	_transition(State.DEAD)


func _on_target_died(_info: DamageInfo) -> void:
	if health.is_alive():
		_transition(State.RETURN)


func _exit_tree() -> void:
	if is_instance_valid(coordinator):
		coordinator.cancel_request(get_parent() as Node3D)


func get_state_name() -> String:
	return ["Idle", "Chase", "Telegraph", "Attack", "Recover", "Return", "Hurt", "Dead"][current_state]


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func get_attack_definition() -> AttackDefinition:
	return settings.attack


func get_attack_cooldown() -> float:
	return settings.attack_cooldown
