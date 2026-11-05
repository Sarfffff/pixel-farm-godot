extends CharacterBody2D
## 工具动作由角色动画驱动；目标在起手时确定，命中帧只提交一次。

signal tool_changed(tool: StringName)
signal action_started(tool: StringName, cell: Vector2i)
signal use_requested(tool: StringName, cell: Vector2i)
## 交互键（E）：收获等不走工具动画的即时操作。
signal interact_requested(cell: Vector2i)

const WALK_SPEED: float = 72.0
const ACCELERATION: float = 900.0
const FRICTION: float = 1100.0
const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe", &"stone_pickaxe"]
## 工具 -> 动作动画前缀。素材里还没有单独的播种帧，先复用锄地的弯腰动作。
const ACTION_ANIMATION: Dictionary[StringName, StringName] = {&"seeds": &"hoe"}
## 走上多少像素踩一步：72px/s 下约每 0.25 秒一声，接近走路节奏。
const STEP_DISTANCE: float = 18.0
## 低于这个速度就不算在走，避免刹车尾巴和静止抖动出脚步声。
const STEP_MIN_SPEED: float = 12.0

@onready var _sprite: AnimatedSprite2D = %Sprite

var current_tool: StringName = TOOLS[0]
var is_acting: bool = false
## 打开背包等面板时置为 true：停止移动并忽略工具输入，避免面板背后的角色乱动。
var input_locked: bool = false
var _manual_input_locked: bool = false
var _modal_input_locked: bool = false
var interaction: Node
var _facing: StringName = &"down"
var _action_tool: StringName
var _action_cell: Vector2i
var _impact_sent: bool = false
var _inventory: Inventory
## 距离上一声脚步已经走过的像素
var _step_travel: float = 0.0


func _ready() -> void:
	_sprite.frame_changed.connect(_on_sprite_frame_changed)
	_sprite.animation_finished.connect(_on_sprite_animation_finished)
	_update_animation(false)
	_bind_inventory.call_deferred()


func _bind_inventory() -> void:
	_inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	if _inventory != null:
		_inventory.active_item_changed.connect(_sync_active_item)
		_sync_active_item()


func _sync_active_item(_id: StringName = &"") -> void:
	if _inventory == null or is_acting:
		return
	var item: ItemData = _inventory.definition(_inventory.active_item())
	var next_tool: StringName = &"none"
	if item != null:
		if item.category == &"tool" and TOOLS.has(item.id):
			next_tool = item.id
		elif item.category == &"seed":
			next_tool = &"seeds"
	if next_tool != current_tool:
		current_tool = next_tool
		_update_animation(velocity.length_squared() > 0.01 and not input_locked)
		tool_changed.emit(current_tool)


func _physics_process(delta: float) -> void:
	if is_acting or input_locked:
		velocity = Vector2.ZERO
		_step_travel = 0.0
		if not is_acting:
			_update_animation(false)
		return
	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down"
	)
	if input_direction != Vector2.ZERO:
		_facing = _resolve_facing(input_direction)
		velocity = velocity.move_toward(input_direction * WALK_SPEED, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	move_and_slide()
	_update_animation(input_direction != Vector2.ZERO)
	_advance_footsteps(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or input_locked:
		return
	# F 交互，Q/E 切换工具；开发快捷键由独立组件处理。
	if event.is_action_pressed(&"interact") and _try_interact():
		return
	if event.is_action_pressed(&"tool_next"):
		if not _cycle_seed(1):
			_cycle_hotbar(1)
	elif event.is_action_pressed(&"tool_prev"):
		if not _cycle_seed(-1):
			_cycle_hotbar(-1)
	else:
		for index in Inventory.HOTBAR_SIZE:
			if event.is_action_pressed(StringName("tool_%d" % (index + 1))):
				_select_hotbar(index)
				return
		if event.is_action_pressed(&"use_tool") or event.is_action_pressed(&"mouse_use"):
			_start_action()


## 面板打开（背包、商店等）时调用：立刻刹车并忽略移动/工具输入。
func set_input_locked(locked: bool) -> void:
	_manual_input_locked = locked
	_refresh_modal_lock()
	_apply_input_lock()


func set_modal_input_locked(locked: bool) -> void:
	_modal_input_locked = locked
	_apply_input_lock()


func _apply_input_lock() -> void:
	input_locked = _manual_input_locked or _modal_input_locked
	if input_locked:
		velocity = Vector2.ZERO
		if not is_acting:
			_update_animation(false)


func _refresh_modal_lock() -> void:
	var modals := get_tree().get_first_node_in_group(&"modal_coordinator")
	if modals != null:
		_modal_input_locked = modals.has_open_panel()


func facing_vector() -> Vector2i:
	match _facing:
		&"up": return Vector2i.UP
		&"left": return Vector2i.LEFT
		&"right": return Vector2i.RIGHT
		_: return Vector2i.DOWN


## 拿着种子袋时，Q/E 在背包里的几种种子之间切换；其他工具照常切换工具。
func _cycle_seed(direction: int) -> bool:
	if current_tool != &"seeds":
		return false
	if interaction == null or not interaction.has_method(&"cycle_seed"):
		return false
	interaction.cycle_seed(direction)
	return true


func _select_tool(index: int) -> void:
	if is_acting:
		return
	var next_tool: StringName = TOOLS[posmod(index, TOOLS.size())]
	# 程序内仍可按工具类型选择；玩家输入则按快捷位选择。
	if _inventory != null:
		var id: StringName = &"carrot_seeds" if next_tool == &"seeds" else next_tool
		if next_tool == &"seeds":
			for entry: StringName in _inventory.hotbar:
				var item: ItemData = _inventory.definition(entry)
				if item != null and item.category == &"seed":
					id = entry
					break
		var slot: int = _inventory.hotbar.find(id)
		if slot < 0 and _inventory.assign_hotbar(_inventory.active_slot, id):
			slot = _inventory.active_slot
		if slot >= 0:
			_inventory.select_hotbar(slot)
			return
	if next_tool != current_tool:
		current_tool = next_tool
		_update_animation(velocity.length_squared() > 0.01 and not input_locked)
		tool_changed.emit(current_tool)


func _select_hotbar(index: int) -> void:
	if is_acting:
		return
	if _inventory != null:
		_inventory.select_hotbar(index)
	elif index < TOOLS.size():
		_select_tool(index)


func _cycle_hotbar(direction: int) -> void:
	if _inventory != null:
		_select_hotbar(_inventory.active_slot + direction)
	else:
		_select_tool(TOOLS.find(current_tool) + direction)


## 跨区或强制送回农舍时取消未命中的旧动作，不能让旧目标命中新的世界。
func cancel_action() -> void:
	is_acting = false
	_impact_sent = true
	velocity = Vector2.ZERO
	_sync_active_item()
	_update_animation(false)


func _start_action() -> void:
	if is_acting or input_locked or current_tool == &"none" or not is_instance_valid(interaction):
		return
	var cell: Vector2i = _resolve_target(current_tool)
	if not interaction.can_use(current_tool, cell):
		return
	# 目标落在侧后方时先转过去，动作方向与真正作用的格子一致。
	_face_cell(cell)
	_action_tool = current_tool
	_action_cell = cell
	_impact_sent = false
	is_acting = true
	velocity = Vector2.ZERO
	action_started.emit(_action_tool, _action_cell)
	_sprite.play(StringName("%s_%s" % [ACTION_ANIMATION.get(_action_tool, _action_tool), _facing]))


## 交互键：先收成熟作物（面前优先、否则身边一圈），没有作物时再看附近的商店等交互点。
## 返回 false 表示这一圈没有可交互对象，按键应回落给工具切换。
func _try_interact() -> bool:
	if is_acting:
		return false
	if is_instance_valid(interaction) and interaction.has_method(&"interact"):
		var cell: Vector2i = _resolve_target(&"interact")
		if not interaction.has_method(&"can_interact") or interaction.can_interact(cell):
			_face_cell(cell)
			interaction.interact(cell)
			interact_requested.emit(cell)
			return true
	var node := nearby_interactable()
	if node != null and node.has_method(&"interact"):
		node.interact(Vector2i.ZERO)
		return true
	return false


## 范围内最近的交互点（商店等），没有则返回 null。
func nearby_interactable() -> Node2D:
	var best: Node2D
	var best_distance: float = INF
	for candidate in get_tree().get_nodes_in_group(&"interactable"):
		var node := candidate as Node2D
		if node == null or node == interaction:
			continue
		if node.has_method(&"player_in_range") and not node.player_in_range(self):
			continue
		var distance: float = node.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


## 顶部提示用：附近交互点的提示优先于当前工具提示。
func nearby_hint() -> String:
	var node := nearby_interactable()
	if node != null and node.has_method(&"hint"):
		return String(node.hint())
	return ""


## 让交互对象挑作用格：支持"身边一圈"的系统会返回范围内的合适格子。
func _resolve_target(tool: StringName) -> Vector2i:
	if interaction.has_method(&"resolve_target"):
		return interaction.resolve_target(tool)
	return interaction.target_cell()


## 把角色转向目标格所在方向；目标就在面前时保持原朝向。
func _face_cell(cell: Vector2i) -> void:
	if not interaction.has_method(&"base_cell"):
		return
	var delta: Vector2i = cell - interaction.base_cell()
	if delta == Vector2i.ZERO:
		return
	_facing = _resolve_facing(Vector2(delta))


func _on_sprite_frame_changed() -> void:
	var impact_frame: int = 1 if _action_tool == &"watering_can" else 2
	if _action_tool == &"stone_pickaxe":
		impact_frame = 3
	if is_acting and _sprite.frame == impact_frame and not _impact_sent:
		_impact_sent = true
		use_requested.emit(_action_tool, _action_cell)


func _on_sprite_animation_finished() -> void:
	if is_acting:
		is_acting = false
		_sync_active_item()
		_update_animation(false)


## 按"走过的距离"而不是固定计时触发脚步：走快走慢节奏都对，
## 贴着墙推（速度被挡成 0）也不会一直响。
func _advance_footsteps(delta: float) -> void:
	var speed: float = velocity.length()
	if speed < STEP_MIN_SPEED:
		_step_travel = 0.0
		return
	_step_travel += speed * delta
	if _step_travel < STEP_DISTANCE:
		return
	_step_travel -= STEP_DISTANCE
	_play_step()


func _play_step() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method(&"play_sfx"):
		return
	audio.call(&"play_sfx", &"step", randf_range(0.92, 1.08))


func _resolve_facing(input_direction: Vector2) -> StringName:
	if absf(input_direction.x) >= absf(input_direction.y):
		return &"right" if input_direction.x > 0.0 else &"left"
	return &"down" if input_direction.y > 0.0 else &"up"


func _update_animation(is_moving: bool) -> void:
	var state: String = "walk" if is_moving else "idle"
	var next_animation: StringName = StringName("%s_%s" % [state, _facing])
	if _sprite.animation != next_animation:
		var keep_step: bool = is_moving and String(_sprite.animation).begins_with("walk_")
		var step: int = _sprite.frame
		var progress: float = _sprite.frame_progress
		_sprite.play(next_animation)
		if keep_step:
			_sprite.set_frame_and_progress(step, progress)
