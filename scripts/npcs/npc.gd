class_name VillageNpc
extends Sprite2D
## 会走路的村民：按日程在格坐标之间寻路，走到玩家身边按 E 多句对话。
##
## 贴图是 4 帧四向表（0 下 / 1 上 / 2 左 / 3 右），与玩家图集同一套朝向约定。
## 移动不走物理：沿 A* 路径逐点靠拢，避免静态碰撞体被"拖着走"造成推挤。
## NPC 不挡玩家（没有碰撞体），这是刻意的：小体量农场里被 NPC 堵路比穿过去更烦。
##
## 依赖 Farm/Nav（scripts/world/nav_grid.gd）提供的网格寻路。

const INTERACT_RADIUS: float = 26.0
## 方向行：0 下 / 1 上 / 2 左 / 3 右
const FRAME_DOWN: int = 0
const FRAME_UP: int = 1
const FRAME_LEFT: int = 2
const FRAME_RIGHT: int = 3
const DIRECTION_ROWS: int = 4
## 每行 3 帧：0 待机 / 1 迈步 / 2 另一只脚（见 tools/art/build_npc_walk_frames.gd）
const STEPS_PER_DIRECTION: int = 3
const STEP_IDLE: int = 0
## 摆动间隔（秒）：24px/s 的移动速度下大约每 3.6px 一步
const STEP_INTERVAL: float = 0.15
## 距离路点小于这个值就认为到了
const ARRIVE_EPSILON: float = 2.0

@export var display_name: String = "村民"
## 好感度用的唯一 id（留空则不参与好感系统）
@export var npc_id: StringName = &""
## 这位村民喜欢的物品：送礼时额外加成
@export var liked_items: Array[StringName] = []
@export var dialogue: DialogueData
## 巡逻路线（格坐标），按顺序循环；留空则在 home_cell 附近随机踱步
@export var routine: Array[Vector2i] = []
@export var home_cell: Vector2i = Vector2i(20, 14)
@export var wander_radius: int = 3
@export var move_speed: float = 24.0
@export var wait_seconds: float = 3.0
## true = 站着不动只说话（店主这类固定摊位）
@export var stationary: bool = false

var _nav: FarmNav
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _wait_left: float = 0.0
var _route_index: int = -1
var _rng := RandomNumberGenerator.new()
## 当前朝向（行）与走路帧（列）
var _facing: int = FRAME_DOWN
var _step: int = STEP_IDLE
var _step_time: float = 0.0


func _ready() -> void:
	add_to_group(&"interactable")
	_apply_frame(STEP_IDLE)
	_rng.seed = hash(display_name) if not display_name.is_empty() else 1
	# 导航节点在 Farm 上，用 call_deferred 避免 _ready 顺序问题。
	_bind_nav.call_deferred()


func _bind_nav() -> void:
	_nav = get_tree().get_first_node_in_group(&"nav") as FarmNav
	if _nav == null and not stationary:
		push_warning("[npc] %s 找不到 FarmNav，将原地待命" % display_name)


func _physics_process(delta: float) -> void:
	if stationary or _nav == null:
		return
	if _is_interrupted():
		_set_step(STEP_IDLE)
		return
	if _wait_left > 0.0:
		_wait_left -= delta
		_set_step(STEP_IDLE)
		return
	if _path.is_empty():
		_set_step(STEP_IDLE)
		_plan_next_target()
		return
	_follow_path(delta)
	_advance_step(delta)


## 对话/面板打开或暂停时 NPC 站住，避免玩家在读字时被推来推去。
func _is_interrupted() -> bool:
	if get_tree().paused:
		return true
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and "input_locked" in player and bool(player.input_locked):
		return true
	return false


func _plan_next_target() -> void:
	if routine.is_empty():
		var wander := _nav.random_walkable_near(home_cell, wander_radius, _rng)
		if wander.x < 0:
			_wait_left = wait_seconds
			return
		_repath_to(wander)
		return
	_route_index = (_route_index + 1) % routine.size()
	_repath_to(routine[_route_index])


func _repath_to(cell: Vector2i) -> void:
	var target_cell: Vector2i = _nav.nearest_walkable(cell)
	if target_cell.x < 0:
		_wait_left = wait_seconds
		return
	var cells := _nav.find_path_cells(global_position, _nav.cell_to_world(target_cell))
	if cells.is_empty():
		# 走不过去（被道具围住）：罚站一会儿再重试，不会每帧反复寻路。
		_wait_left = wait_seconds
		return
	_path.clear()
	# 跳过起点格，避免原地抖动。
	for index in range(1, cells.size()):
		_path.append(_nav.cell_to_world(cells[index]))
	_path_index = 0


func _follow_path(delta: float) -> void:
	if _path_index >= _path.size():
		_path.clear()
		_wait_left = wait_seconds
		return
	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - global_position
	if to_target.length() <= ARRIVE_EPSILON:
		_path_index += 1
		return
	_update_facing(to_target)
	global_position += to_target.normalized() * minf(move_speed * delta, to_target.length())


func _update_facing(direction: Vector2) -> void:
	var facing: int = FRAME_DOWN
	if absf(direction.x) >= absf(direction.y):
		facing = FRAME_RIGHT if direction.x > 0.0 else FRAME_LEFT
	else:
		facing = FRAME_DOWN if direction.y > 0.0 else FRAME_UP
	if facing == _facing:
		return
	_facing = facing
	_apply_frame(_step)


## 走路动画：迈步 1 → 迈步 2 交替，停下由 _set_step(STEP_IDLE) 复位。
func _advance_step(delta: float) -> void:
	_step_time += delta
	if _step_time < STEP_INTERVAL:
		return
	_step_time -= STEP_INTERVAL
	_set_step(2 if _step == 1 else 1)


func _set_step(step: int) -> void:
	if step == _step:
		return
	_step = step
	_step_time = 0.0
	_apply_frame(step)


## 图集是「4 方向 × 3 帧」：帧序号 = 朝向 * 3 + 步态。
func _apply_frame(step: int) -> void:
	if hframes * vframes < DIRECTION_ROWS * STEPS_PER_DIRECTION:
		return
	frame = _facing * STEPS_PER_DIRECTION + step


## 当前是否在沿路径移动（自检与调试用）。
func is_walking() -> bool:
	return not _path.is_empty() and _path_index < _path.size()


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "按 E 和%s聊聊" % display_name


func interact(_cell: Vector2i) -> void:
	var panel := get_tree().current_scene.get_node_or_null("UI/DialoguePanel")
	if panel == null:
		return
	_record_talk()
	var options: Array = []
	if dialogue != null:
		options = dialogue.options.duplicate(true)
	var gift_id: StringName = _giftable_item()
	if gift_id != &"":
		options.append({&"id": &"gift", &"text": "送点东西（%s）" % _item_name(gift_id)})
	if not options.is_empty():
		options.append({&"id": &"leave", &"text": "再见"})

	if dialogue != null and not dialogue.lines.is_empty():
		panel.call(&"open_lines", display_name, dialogue.lines, self, options)
		return
	panel.call(&"open_with", display_name, "今天天气不错。", options, self)


## 选项回调：默认只结束对话；需要开店/给任务的 NPC 重写它。
func on_dialogue_option(id: StringName) -> String:
	if id == &"gift":
		return _give_gift()
	return ""


## 今天第一次聊天加好感（每人每天一次，跨天由 Friendship 清空）。
func _record_talk() -> void:
	if npc_id == &"":
		return
	var friendship := get_tree().get_first_node_in_group(&"friendship")
	if friendship != null and friendship.has_method(&"talked"):
		friendship.call(&"talked", npc_id)


## 手上拿着的东西：工具与空手不算礼物。
func _giftable_item() -> StringName:
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null or not inventory.has_method(&"active_item"):
		return &""
	var item_id: StringName = StringName(inventory.call(&"active_item"))
	if item_id == &"" or Inventory.TOOL_IDS.has(item_id):
		return &""
	return item_id


func _item_name(item_id: StringName) -> String:
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory != null and inventory.has_method(&"item_name"):
		return String(inventory.call(&"item_name", item_id))
	return String(item_id)


## 送礼：扣 1 个手持物品，按喜好加好感，返回一句反应。
func _give_gift() -> String:
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	var item_id: StringName = _giftable_item()
	if inventory == null or item_id == &"":
		return "你手上没拿东西呀。"
	if not bool(inventory.call(&"remove_item", item_id, 1)):
		return "……东西没送出去。"
	var liked: bool = liked_items.has(item_id)
	var friendship := get_tree().get_first_node_in_group(&"friendship")
	if friendship != null and friendship.has_method(&"gift"):
		friendship.call(&"gift", npc_id, liked)
	if liked:
		return "「%s」？这是我最喜欢的，太谢谢你了！" % _item_name(item_id)
	return "「%s」啊，我收下啦。" % _item_name(item_id)
