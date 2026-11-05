extends SceneTree
## 通用动物状态机，以及小鸡的移动/动画、每日产蛋、满包保留和存档兼容。

const Profile := preload("res://scripts/data/animal_profile.gd")
const Brain := preload("res://scripts/animals/animal_state_machine.gd")
const Animal := preload("res://scripts/animals/farm_animal.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[animals] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_check_state_machine()
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame

	var coop: Node2D = main.get_node_or_null("Farm/World/ChickenCoop") as Node2D
	_check(coop != null, "chicken coop placed in world")
	if coop == null:
		_finish(main)
		return
	_check(coop.has_method(&"egg_count"), "coop exposes egg_count")
	_check((main.get_node_or_null("Farm/World/ChickenCoop/Nest") as Sprite2D) != null, "coop has a nest sprite")

	var chickens := get_nodes_in_group(&"chicken")
	_check(chickens.size() == 2, "two chickens in the yard")
	_check(get_nodes_in_group(&"farm_animal").size() == 2, "chickens use the shared animal host")
	await _check_animal_host(main, chickens[0])
	_check_chicken_steps(chickens[0])
	await _check_species_animations(main)
	await _capture_motion_reference(main)

	# 鸡会自己走动
	var first := chickens[0] as Node2D
	var start: Vector2 = first.global_position
	for i in 120:
		await physics_frame
	var moved: float = first.global_position.distance_to(start)
	_check(moved > 2.0, "chicken wanders around (moved %.1f px)" % moved)
	var sprite := first.get_node_or_null("Sprite") as Sprite2D
	_check(sprite != null and sprite.hframes == 4 and sprite.vframes == 2, "chicken sheet sliced 4x2")

	# 睡觉 → 每只鸡一颗蛋
	var time := get_first_node_in_group(&"time")
	_check(time != null, "time system present")
	time.call("sleep")
	await process_frame
	_check(int(coop.call("egg_count")) == 2, "each chicken lays an egg after sleeping")
	_check(get_nodes_in_group(&"egg").size() == 2, "eggs are in the world")

	# 蛋能在存档里往返
	var data: Dictionary = coop.call("to_dict")
	_check((data.get(&"eggs", []) as Array).size() == 2, "save data holds two eggs")
	coop.call("clear_eggs")
	await process_frame
	_check(int(coop.call("egg_count")) == 0, "clear_eggs empties the ground")
	coop.call("from_dict", data)
	await process_frame
	_check(int(coop.call("egg_count")) == 2, "eggs come back from save data")

	# 捡蛋
	var inventory := get_first_node_in_group(&"inventory")
	var player := main.get_node("Farm/World/Player") as Node2D
	var before: int = inventory.count_of(&"egg")
	var eggs := get_nodes_in_group(&"egg")
	var egg: Node2D = eggs[0] as Node2D
	player.global_position = egg.global_position + Vector2(0, 8)
	_check(bool(egg.call("player_in_range", player)), "standing on the egg is in range")
	player.global_position = egg.global_position + Vector2(0, 60)
	_check(not bool(egg.call("player_in_range", player)), "walking away leaves the egg range")
	player.global_position = egg.global_position + Vector2(0, 8)
	egg.call("interact", Vector2i.ZERO)
	await process_frame
	await process_frame
	_check(inventory.count_of(&"egg") == before + 1, "picking an egg adds it to the bag")
	_check(int(coop.call("egg_count")) == 1, "coop forgets the picked egg")

	# 满包时蛋留在地上：先把已有的蛋卖掉腾空，否则蛋会堆进同一种物品的格子
	inventory.remove_item(&"egg", inventory.count_of(&"egg"))
	for i in 40:
		inventory.add_item(&"wood", 99)
	await process_frame
	_check(inventory.add_item(&"wood", 1) > 0, "bag is really full")
	var leftovers: Array[Node2D] = []
	for node in get_nodes_in_group(&"egg"):
		if not (node as Node).is_queued_for_deletion():
			leftovers.append(node as Node2D)
	_check(leftovers.size() == 1, "exactly one egg left on the ground")
	if leftovers.size() == 1:
		var leftover: Node2D = leftovers[0]
		leftover.call("interact", Vector2i.ZERO)
		await process_frame
		_check(
			is_instance_valid(leftover) and not leftover.is_queued_for_deletion(),
			"a full bag leaves the egg on the ground"
		)

	# 蛋能卖
	var sell_price: int = 0
	for item: ItemData in inventory.definitions():
		if item.id == &"egg":
			sell_price = item.sell_price
	_check(sell_price > 0, "egg has a sell price")

	_finish(main)


func _finish(main: Node2D) -> void:
	main.queue_free()
	await process_frame
	print("[animals] shared state machine, chickens, eggs, save round trip; %d checks, %d failures" % [_checks, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_state_machine() -> void:
	var profile := Profile.new()
	profile.graze_chance = 0.0
	var brain := Brain.new()
	var home := Vector2(100, 100)
	brain.setup(profile, home, 1234)
	_check(brain.state == Brain.State.WANDER, "animal begins wandering")
	brain.tick(0.1, home, false)
	_check(brain.desired_velocity.length() > 0.0 and brain.desired_velocity.length() <= profile.move_speed + 0.001, "profile controls movement speed")
	brain.tick(100.0, home, false)
	_check(brain.desired_velocity.length() * 100.0 <= home.distance_to(brain.target) + 0.001, "a long frame cannot overshoot the target")

	# 连续多轮到点与等待，防止再次出现等完仍困在原目标、永久站住。
	for cycle: int in 20:
		var previous_target: Vector2 = brain.target
		var offset: Vector2 = previous_target - home
		var normalized := Vector2(offset.x / profile.home_radius, offset.y / (profile.home_radius * profile.vertical_range_scale))
		_check(normalized.length() <= 1.001, "wander target stays inside its home ellipse")
		brain.tick(0.1, previous_target, false)
		_check(brain.state == Brain.State.IDLE and brain.desired_velocity == Vector2.ZERO, "arrival enters idle")
		brain.tick(brain.duration + 0.01, previous_target, false)
		_check(brain.state == Brain.State.WANDER and brain.target != previous_target, "idle ends with a new destination")

	brain.notify_blocked()
	_check(brain.state == Brain.State.IDLE and is_equal_approx(brain.duration, profile.obstacle_wait), "collision enters a short idle")
	_check(brain.desired_velocity == Vector2.ZERO, "collision cancels movement intent")
	brain.tick(profile.obstacle_wait + 0.01, home, false)
	_check(brain.state == Brain.State.WANDER, "wandering resumes after obstacle cooldown")

	var grazer_profile := profile.duplicate() as Profile
	grazer_profile.species_id = &"cow_test"
	grazer_profile.move_speed = 9.0
	grazer_profile.graze_chance = 1.0
	var grazer := Brain.new()
	grazer.setup(grazer_profile, home, 4567)
	grazer.tick(0.1, home, false)
	_check(is_equal_approx(grazer.desired_velocity.length(), 9.0), "a second species reuses the brain with a different speed")
	grazer.tick(0.1, grazer.target, false)
	_check(grazer.state == Brain.State.GRAZE and grazer.desired_velocity == Vector2.ZERO, "graze configuration enters a stationary graze")
	grazer.tick(grazer.duration + 0.01, grazer.target, false)
	_check(grazer.state == Brain.State.IDLE, "grazing ends in idle")

	var changes: Array[int] = []
	brain.state_changed.connect(func(_before: int, after: int) -> void: changes.append(after))
	brain.tick(0.1, home, true)
	_check(brain.state == Brain.State.SLEEP and brain.desired_velocity == Vector2.ZERO, "night interrupts wandering")
	brain.tick(3.0, home, true)
	_check(changes.size() == 1, "sleep does not reenter or repeat its signal each tick")
	brain.tick(0.1, home, false)
	_check(brain.state == Brain.State.IDLE, "dawn wakes the animal into idle")
	brain.tick(brain.duration + 0.01, home, false)
	_check(brain.state == Brain.State.WANDER, "animal resumes its routine after waking")
	grazer.tick(0.1, home, true)
	_check(grazer.state == Brain.State.SLEEP, "night can also interrupt idle")
	grazer.tick(0.1, home, false)
	grazer.tick(grazer.duration + 0.01, home, false)
	grazer.tick(0.1, grazer.target, false)
	grazer.tick(0.1, grazer.target, true)
	_check(grazer.state == Brain.State.SLEEP, "night can interrupt grazing")

	var sibling := Brain.new()
	sibling.setup(profile, Vector2(200, 200), 8910)
	var sibling_target: Vector2 = sibling.target
	brain.tick(0.5, home, true)
	_check(sibling.state == Brain.State.WANDER and sibling.elapsed == 0.0 and sibling.target == sibling_target, "animals sharing a profile keep independent states and timers")
	_check(profile.move_speed == 16.0 and profile.graze_chance == 0.0, "states do not mutate their shared resource")

	_check(not profile.is_sleep_time(21 * 60 + 59), "awake before 22:00")
	_check(profile.is_sleep_time(22 * 60), "sleep at 22:00")
	_check(profile.is_sleep_time(24 * 60) and profile.is_sleep_time(26 * 60), "sleep across midnight and the game's 26:00 notation")
	_check(profile.is_sleep_time(6 * 60 - 1) and not profile.is_sleep_time(6 * 60), "wake exactly at 06:00")
	profile.sleeps_at_night = false
	_check(not profile.is_sleep_time(23 * 60), "night rest can be disabled for a species")
	profile.sleeps_at_night = true
	profile.sleep_minutes = 6 * 60
	profile.wake_minutes = 18 * 60
	_check(profile.is_sleep_time(12 * 60) and not profile.is_sleep_time(22 * 60), "profile supports a daytime rest schedule")
	profile.home_radius = 0.0
	var stationary := Brain.new()
	stationary.setup(profile, home, 11)
	stationary.tick(0.1, home, false)
	_check(stationary.desired_velocity.is_zero_approx() and stationary.state == Brain.State.IDLE, "zero-radius animals stop safely")


func _check_animal_host(main: Node2D, chicken: Animal) -> void:
	var time := main.get_node("Systems/Time")
	var player := main.get_node("Farm/World/Player")
	var sprite := chicken.get_node("Sprite") as Sprite2D
	var original_position: Vector2 = chicken.global_position
	var was_running: bool = bool(time.get("running"))
	time.set("running", false)
	chicken.global_position = Vector2(328, 264)
	chicken.brain.setup(chicken.profile, chicken.global_position, 1234)
	_check(chicken.is_in_group(&"world_actor"), "animals do not lock tillable tiles by their sprite bounds")

	var dialogue := main.get_node("UI/DialoguePanel")
	dialogue.call("open_with", "test", "test", [], null)
	var before: Vector2 = chicken.global_position
	var elapsed: float = chicken.brain.elapsed
	for tick: int in 6:
		await physics_frame
	_check(chicken.global_position == before and chicken.brain.elapsed == elapsed, "dialogue freezes motion and state timers")
	_check(sprite.frame < 2 and chicken.velocity == Vector2.ZERO, "dialogue displays the chicken's idle pose")
	dialogue.call("close")
	_check(not bool(player.get("input_locked")), "closing dialogue releases animal simulation")

	time.set("minutes", 22 * 60)
	await physics_frame
	await physics_frame
	_check(chicken.brain.state == Brain.State.SLEEP and chicken.global_position == before, "real clock puts chicken to sleep without moving")
	_check(sprite.frame < 2, "sleep uses a valid idle pose when no sleep frames exist")
	time.set("minutes", 6 * 60)
	await physics_frame
	await physics_frame
	_check(chicken.brain.state == Brain.State.IDLE, "real dawn wakes chicken")

	# 真碰撞：让鸡朝一块临时墙走，验证宿主会把碰撞回传给状态机。
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 32)
	collider.shape = shape
	wall.add_child(collider)
	main.get_node("Farm/World").add_child(wall)
	wall.global_position = Vector2(340, 264)
	chicken.brain.setup(chicken.profile, chicken.global_position, 111)
	chicken.brain.target = chicken.global_position + Vector2(40, 0)
	var observed_states: Array[int] = []
	var record_change := func(_old: int, current: int) -> void: observed_states.append(current)
	chicken.brain.state_changed.connect(record_change)
	var walk_frames: Dictionary = {}
	for tick: int in 60:
		await physics_frame
		walk_frames[sprite.frame] = true
	_check(observed_states.has(Brain.State.IDLE), "physical collision interrupts wandering")
	_check(observed_states.has(Brain.State.WANDER), "physical collision recovers into a new walk")
	_check(walk_frames.has(4) or walk_frames.has(6), "chicken renders its walk poses")
	chicken.brain.state_changed.disconnect(record_change)
	wall.queue_free()

	chicken.global_position = original_position
	chicken.brain.setup(chicken.profile, original_position, 1234)
	time.set("running", was_running)
	await _check_generic_animation(main)


func _check_generic_animation(main: Node2D) -> void:
	# 无小鸡专用脚本的新动物宿主，也能通过常规 AnimatedSprite2D 工作。
	var animal := Animal.new()
	animal.profile = Profile.new()
	animal.profile.species_id = &"sheep_test"
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for animation: StringName in [&"idle_right", &"walk_right"]:
		frames.add_animation(animation)
		frames.add_frame(animation, texture)
	sprite.sprite_frames = frames
	animal.add_child(sprite)
	animal.set_physics_process(false)
	main.add_child(animal)
	animal.facing = &"right"
	animal._update_visual(0.1, true)
	_check(sprite.animation == &"walk_right", "generic species selects its directional walk animation")
	animal.brain.tick(0.1, animal.global_position, true)
	animal._update_visual(0.1, false)
	_check(sprite.animation == &"idle_right", "missing sleep animation falls back to directional idle")
	animal.queue_free()
	await process_frame


func _check_chicken_steps(chicken: Animal) -> void:
	var sprite := chicken.get_node("Sprite") as Sprite2D
	var origin: Vector2 = chicken.global_position
	chicken.set_physics_process(false)
	# 使用真实宿主移动，位置远离农场障碍；不靠“节点存在”判断行走正确。
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2(1, 1).normalized(), Vector2(-1, -1).normalized()]:
		chicken.global_position = Vector2(1600, 1600)
		chicken.brain.setup(chicken.profile, chicken.global_position, 1234)
		chicken.brain.target = chicken.global_position + direction * 40
		chicken._update_facing(direction)
		chicken._update_visual(0.0, false)
		var mirrored: bool = direction.x < 0
		_check(sprite.frame == 0 and sprite.flip_h == mirrored, "chicken idle mirrors its single-facing texture toward the destination")
		var before: Vector2 = chicken.global_position
		chicken._physics_process(0.01)
		_check((chicken.global_position - before).dot(direction) > 0.0, "chicken actually moves toward its destination")
		_check(sprite.frame == 4 and sprite.flip_h == mirrored, "first footstep faces the actual movement instead of walking backwards")
		for frame: int in [5, 6, 7, 4]:
			chicken._update_visual(0.24, true)
			_check(sprite.frame == frame and sprite.flip_h == mirrored, "complete four-frame gait retains its direction and loops")
		for vertical: Vector2 in [Vector2.UP, Vector2.DOWN]:
			chicken._update_facing(vertical)
			chicken._update_visual(0.0, true)
			_check(sprite.frame == 4 and sprite.flip_h == mirrored, "vertical motion retains the last horizontal walk direction")
		chicken._update_visual(0.0, false)
		_check(sprite.frame == 0 and sprite.flip_h == mirrored, "stopping returns to matching idle, never blink/empty cells as a direction")
	chicken.global_position = origin
	chicken.brain.setup(chicken.profile, origin, 1234)
	chicken.set_physics_process(true)


func _check_species_animations(main: Node2D) -> void:
	var animal := Animal.new()
	animal.profile = Profile.new()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	animal.add_child(sprite)
	main.add_child(animal)
	animal.set_physics_process(false)
	var species: int = 0
	for file: String in ResourceLoader.list_directory("res://assets/packs/content_v1/animations/animals/"):
		if not file.ends_with(".tres"): continue
		species += 1
		sprite.sprite_frames = load("res://assets/packs/content_v1/animations/animals/" + file) as SpriteFrames
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			animal._update_facing(direction)
			animal._update_visual(0.1, true)
			_check(String(sprite.animation).begins_with("walk") and sprite.sprite_frames.get_frame_count(sprite.animation) > 1, file + " walks in every direction instead of sliding in idle")
			_check(sprite.flip_h == (direction.x > 0), file + " mirrors left-only walk for right travel and resets mirror on left travel")
			animal._update_visual(0.1, false)
			_check(sprite.animation == StringName("idle_" + String(animal.facing)) and not sprite.flip_h, file + " restores the native idle direction without a stale mirror")
	_check(species > 0, "all available species animation resources were exercised")
	print("[animals] checked %d animal animation resources" % species)
	# 原生四向步行优先于镜像；只有侧向帧的图集，纵向走动沿用最近侧向。
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(&"walk_left", 0)
	for direction: String in ["left", "right", "up", "down"]:
		var name := StringName("walk_" + direction)
		frames.add_animation(name)
		frames.add_frame(name, texture)
	sprite.sprite_frames = frames
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		animal._update_facing(direction)
		animal._update_visual(0.1, true)
		_check(sprite.animation == StringName("walk_" + String(animal.facing)) and not sprite.flip_h, "native four-direction walk always wins without mirroring")
	animal.queue_free()
	await process_frame


func _capture_motion_reference(main: Node2D) -> void:
	if "--preview" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	var layer := CanvasLayer.new()
	layer.layer = 100
	main.add_child(layer)
	var background := ColorRect.new()
	background.size = Vector2(640, 360)
	background.color = Color("60724b")
	layer.add_child(background)
	var title := Label.new()
	title.text = "Chicken: RIGHT steps / mirrored LEFT steps"
	title.position = Vector2(24, 12)
	layer.add_child(title)
	for index: int in 4:
		var chicken: Animal = load("res://scenes/world/chicken.tscn").instantiate() as Animal
		layer.add_child(chicken)
		chicken.set_physics_process(false)
		chicken.position = Vector2(96 + index * 144, 125)
		chicken.scale = Vector2(4, 4)
		chicken._update_facing(Vector2.RIGHT if index < 2 else Vector2.LEFT)
		chicken._update_visual(0.24 if index % 2 else 0.0, true)
	var subtitle := Label.new()
	subtitle.text = "Other animals: mirrored RIGHT / native LEFT"
	subtitle.position = Vector2(24, 170)
	layer.add_child(subtitle)
	for index: int in 4:
		var animal := Animal.new()
		var sprite := AnimatedSprite2D.new()
		sprite.name = "AnimatedSprite2D"
		var species: String = "white_cow" if index < 2 else "woolly_sheep"
		sprite.sprite_frames = load("res://assets/packs/content_v1/animations/animals/" + species + ".tres")
		animal.add_child(sprite)
		layer.add_child(animal)
		animal.set_physics_process(false)
		animal.position = Vector2(96 + index * 144, 275)
		animal.scale = Vector2(3, 3)
		animal._update_facing(Vector2.RIGHT if index % 2 == 0 else Vector2.LEFT)
		animal._update_visual(0.0, true)
	for frame: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://animal_motion_reference.png"
	_check(root.get_texture().get_image().save_png(path) == OK, "animal movement reference rendered")
	print("[animals] preview: " + ProjectSettings.globalize_path(path))
	layer.queue_free()
	await process_frame
