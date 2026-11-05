extends Node
## 进出房屋：不切场景，只做「农场隐藏 / 室内显示 + 玩家搬家 + 相机换边界」。
##
## 为什么不 `change_scene_to_file`：Main 下挂着时间、背包、经济、存档等 Systems，
## 换场景会把它们全部重建，时间与背包状态都会丢。这里让室内成为 Main 的兄弟节点，
## 放在远处的 `INTERIOR_ORIGIN`，两套世界互不干扰。
##
## 玩家会 reparent 到当前世界的节点下，这样 Y 排序与可见性都跟着世界走。

const INTERIOR_ORIGIN: Vector2 = Vector2(0, 2000)

@export var player_path: NodePath
@export var farm_path: NodePath
@export var camera_path: NodePath
## 室内相机范围（相对室内场景原点）：27×19 格房间 + 底部 3 排墙体余量，
## 这样站在门口时相机能继续往下滚，门不会被底部工具栏挡住。
@export var interior_bounds: Rect2 = Rect2(0, 0, 432, 352)
## 农场可走范围
@export var farm_bounds: Rect2 = Rect2(0, 0, 640, 480)
## 出门时站在门口往下的偏移
@export var exit_offset: Vector2 = Vector2(0, 12)

var _player: Node2D
var _farm: Node2D
var _farm_world: Node2D
var _camera: Camera2D
## 当前所在的室内
var _interior: Node2D
## 已实例化的室内，按场景路径缓存：农舍和商店是两套不同的房间
var _interiors: Dictionary = {}
var _inside: bool = false
var _saved_position: Vector2


func _ready() -> void:
	add_to_group(&"house")
	_player = get_node_or_null(player_path) as Node2D
	_farm = get_node_or_null(farm_path) as Node2D
	_camera = get_node_or_null(camera_path) as Camera2D
	if _farm != null:
		_farm_world = _farm.get_node_or_null("World") as Node2D
	if _player == null or _farm == null or _camera == null:
		push_warning("[house] 玩家 / 农场 / 相机路径未配好，进出屋会失效")


func is_inside() -> bool:
	return _inside


## 存档用：人在屋里时应该记下门外的坐标，否则读档会落在室内偏移坐标上。
func save_position() -> Vector2:
	if _inside:
		return _saved_position
	return _player.global_position if _player != null else Vector2.ZERO


func enter_house(scene: PackedScene) -> void:
	if _inside or scene == null or _player == null:
		return
	var target := _ensure_interior(scene)
	if target == null:
		return
	# 换房子时把上一间藏起来：农舍和商店互不干扰
	if _interior != null and _interior != target:
		_interior.visible = false
	_interior = target
	_saved_position = _player.global_position
	_inside = true

	_farm.visible = false
	_interior.visible = true

	# 玩家搬进室内的 Y 排序容器：家具 z_index 更高，
	# 玩家若留在室内根节点会被地毯、椅子整片盖住。
	var spawn := _interior.get_node_or_null("Spawn") as Node2D
	var local: Vector2 = spawn.position if spawn != null else interior_bounds.size * 0.5
	var layer := _y_sort_layer(_interior)
	if _player.get_parent() != null:
		_player.reparent(layer, false)
	_player.position = local
	_player.visible = true

	_set_indoor_tint(true)
	_camera.global_position = _interior.global_position + local
	# 每间屋子自带相机边界（住宅 432×352、店铺 288×240），没有则用默认值。
	var bounds: Rect2 = interior_bounds
	var declared: Variant = _interior.get("camera_bounds")
	if declared is Rect2:
		bounds = declared
	if _camera.has_method(&"set_world_bounds"):
		_camera.call(&"set_world_bounds", Rect2(_interior.global_position, bounds.size))
		camera_follow_reset()
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO


func exit_house() -> void:
	if not _inside or _player == null:
		return
	_inside = false
	if _interior != null:
		_interior.visible = false
	_farm.visible = true

	if _player.get_parent() != null:
		_player.reparent(_farm_world if _farm_world != null else _farm, false)
	_player.global_position = _saved_position + exit_offset
	_player.visible = true

	_set_indoor_tint(false)
	_camera.global_position = _player.global_position
	if _camera.has_method(&"set_world_bounds"):
		_camera.call(&"set_world_bounds", farm_bounds)
		camera_follow_reset()
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO


## 睡觉开始：角色躺到床上并藏起来，黑屏期间看不到"人还站着"。
func begin_sleep() -> void:
	if not _inside or _player == null:
		return
	var bed := _interior.get_node_or_null("BedSpot") as Node2D
	if bed != null:
		_player.position = bed.position
	_player.visible = false
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO


## 睡醒：角色出现在床边、显形，再淡入并交还操作权。
func prepare_wake() -> void:
	if _inside and _player != null:
		var wake := _interior.get_node_or_null("WakeSpot") as Node2D
		var bed := _interior.get_node_or_null("BedSpot") as Node2D
		var target: Vector2 = _player.position
		if wake != null:
			target = wake.position
		elif bed != null:
			target = bed.position
		_player.position = target
		if _player.get_parent() != null:
			_camera.global_position = (_player.get_parent() as Node2D).global_position + target
	if _player != null:
		_player.visible = true


## 旧入口保留；新休息控制器分开安排落点、保存和淡入。
func finish_sleep() -> void:
	prepare_wake()
	var fade := get_tree().get_first_node_in_group(&"screen_fade")
	if fade != null:
		fade.call(&"hide_caption")
		await fade.call(&"fade_in", 0.5)
	if _player != null and _player.has_method(&"set_input_locked"):
		_player.call(&"set_input_locked", false)


## 室内常亮：夜里进屋不该跟室外一样黑（CanvasModulate 是全局的，只能切换色调）。
func _set_indoor_tint(indoor: bool) -> void:
	var tint := get_tree().get_first_node_in_group(&"day_night_tint")
	if tint != null and tint.has_method(&"set_indoor"):
		tint.call(&"set_indoor", indoor)


## 相机瞬移后不要从旧位置平滑滑过来。
func camera_follow_reset() -> void:
	if _camera != null and _camera.has_method(&"reset_smoothing"):
		_camera.call(&"reset_smoothing")


## 室内的可排序层：优先 Props（家具容器，y_sort 开启），找不到再退回室内根节点。
func _y_sort_layer(interior: Node2D) -> Node2D:
	var props := interior.get_node_or_null("Props") as Node2D
	return props if props != null and props.y_sort_enabled else interior


func _ensure_interior(scene: PackedScene) -> Node2D:
	# 同一栋建筑复用实例；不同建筑（农舍 / 商店）各有一套
	var key := scene.resource_path
	if key.is_empty():
		key = str(scene)
	if _interiors.has(key):
		return _interiors[key] as Node2D
	var inst := scene.instantiate() as Node2D
	if inst == null:
		push_warning("[house] 室内场景根节点不是 Node2D")
		return null
	_interiors[key] = inst
	inst.visible = false
	inst.position = INTERIOR_ORIGIN
	# 挂在场景根（Main）下，而不是 Systems 下，方便按名字定位与调试。
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	host.add_child(inst)
	return inst
