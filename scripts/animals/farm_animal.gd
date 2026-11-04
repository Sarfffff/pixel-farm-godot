class_name FarmAnimal
extends CharacterBody2D
## 动物通用宿主：接入时钟与模态暂停，执行物理移动，再交给具体外观表现。
## 可直接配 AnimatedSprite2D，也可像小鸡一样继承并覆写 _update_visual。

const Profile := preload("res://scripts/data/animal_profile.gd")
const Brain := preload("res://scripts/animals/animal_state_machine.gd")

@export var profile: Profile
@export_node_path("AnimatedSprite2D") var animated_sprite_path: NodePath = ^"AnimatedSprite2D"

var brain := Brain.new()
var facing: StringName = &"down"
var _time: Node
var _player: Node


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group(&"farm_animal")
	add_to_group(&"world_actor")
	if profile == null:
		profile = Profile.new()
	brain.setup(profile, global_position)
	_bind_systems.call_deferred()
	_update_visual(0.0, false)


func _bind_systems() -> void:
	_time = get_tree().get_first_node_in_group(&"time")
	_player = get_tree().get_first_node_in_group(&"player")


func _physics_process(delta: float) -> void:
	if _is_interrupted():
		velocity = Vector2.ZERO
		_update_visual(0.0, false)
		return
	var sleep_time: bool = is_instance_valid(_time) and profile.is_sleep_time(int(_time.get("minutes")))
	brain.tick(delta, global_position, sleep_time)
	velocity = brain.desired_velocity
	var before: Vector2 = global_position
	if not velocity.is_zero_approx():
		_update_facing(velocity)
		move_and_slide()
		if get_slide_collision_count() > 0:
			brain.notify_blocked()
			velocity = Vector2.ZERO
	var moving: bool = brain.state == Brain.State.WANDER and global_position.distance_squared_to(before) > 0.0001
	_update_visual(delta, moving)


func _is_interrupted() -> bool:
	return get_tree().paused or (is_instance_valid(_player) and bool(_player.get("input_locked")))


func _update_facing(direction: Vector2) -> void:
	if absf(direction.x) >= absf(direction.y):
		facing = &"right" if direction.x > 0.0 else &"left"
	else:
		facing = &"down" if direction.y > 0.0 else &"up"


## 动画命名：walk/idle/graze/sleep 加 _down/_up/_left/_right，或单独动作名。
## 缺少觅食/睡眠动画时回退到站姿，避免播放不存在的动画报错。
func _update_visual(_delta: float, moving: bool) -> void:
	var sprite := get_node_or_null(animated_sprite_path) as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	var action: String = "walk" if moving else "idle"
	if not _is_interrupted() and brain.state == Brain.State.GRAZE:
		action = "graze"
	elif not _is_interrupted() and brain.state == Brain.State.SLEEP:
		action = "sleep"
	var candidates: Array[StringName] = [
		StringName(action + "_" + String(facing)), StringName(action),
		StringName("idle_" + String(facing)), &"idle",
	]
	for animation: StringName in candidates:
		if sprite.sprite_frames.has_animation(animation):
			sprite.play(animation)
			return
	sprite.stop()
