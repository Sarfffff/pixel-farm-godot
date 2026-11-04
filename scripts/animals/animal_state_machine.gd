class_name AnimalStateMachine
extends RefCounted
## 共用动物状态机，只决定行为与期望速度，不依赖场景树、贴图或产出系统。

signal state_changed(previous: int, current: int)

const Profile := preload("res://scripts/data/animal_profile.gd")
const AnimalState := preload("res://scripts/animals/states/animal_state.gd")
const TimedState := preload("res://scripts/animals/states/timed_animal_state.gd")
const WanderState := preload("res://scripts/animals/states/wander_animal_state.gd")
enum State { IDLE, WANDER, GRAZE, SLEEP }

var profile: Profile
var state: int = -1
var home: Vector2
var target: Vector2
var desired_velocity: Vector2 = Vector2.ZERO
var elapsed: float = 0.0
var duration: float = 0.0
var _rng := RandomNumberGenerator.new()
var _states: Dictionary[int, AnimalState] = {}


func _init() -> void:
	register_state(State.IDLE, TimedState.new(&"idle_min", &"idle_max", State.WANDER))
	register_state(State.GRAZE, TimedState.new(&"graze_min", &"graze_max", State.IDLE))
	register_state(State.WANDER, WanderState.new(State.IDLE, State.GRAZE))
	register_state(State.SLEEP, AnimalState.new())


func register_state(id: int, behaviour: AnimalState) -> void:
	assert(behaviour != null)
	_states[id] = behaviour


func setup(settings: Profile, origin: Vector2, random_seed: int = 0) -> void:
	profile = settings
	home = origin
	target = origin
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed
	state = -1
	# 保持开局就能看到小鸡踱步；此后的停留和步行由状态转换控制。
	transition_to(State.WANDER)


func tick(delta: float, world_position: Vector2, sleep_time: bool) -> void:
	if profile == null:
		return
	desired_velocity = Vector2.ZERO
	# 睡眠优先于其他行为；醒来先站稳，再开始新一轮活动。
	if sleep_time:
		transition_to(State.SLEEP)
		return
	if state == State.SLEEP:
		transition_to(State.IDLE)
		return
	elapsed += maxf(delta, 0.0)
	if _states.has(state):
		_states[state].tick(self, delta, world_position)


## 物理层报告撞墙后短暂停留；下次进入游走重新选点，不沿原方向持续顶墙。
func notify_blocked() -> void:
	if state != State.WANDER:
		return
	transition_to(State.IDLE)
	duration = maxf(profile.obstacle_wait, 0.1)


func transition_to(next: int) -> bool:
	if not _states.has(next):
		return false
	if state == next:
		return true
	var previous: int = state
	if _states.has(previous):
		_states[previous].exit(self)
	state = next
	elapsed = 0.0
	duration = 0.0
	desired_velocity = Vector2.ZERO
	_states[state].enter(self)
	state_changed.emit(previous, state)
	return true


func sample_duration(minimum: float, maximum: float) -> float:
	return _rng.randf_range(maxf(minimum, 0.1), maxf(maximum, maxf(minimum, 0.1)))


func choose_target() -> void:
	# 椭圆活动范围；home 始终是出生点，目标不会随着移动向外漂移。
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = _rng.randf_range(0.5, 1.0) * maxf(profile.home_radius, 0.0)
	target = home + Vector2(cos(angle), sin(angle) * clampf(profile.vertical_range_scale, 0.1, 1.0)) * radius


func random_chance(probability: float) -> bool:
	return _rng.randf() < clampf(probability, 0.0, 1.0)
