extends Node2D
## 面前格交互。可用性、预览和命中共用同一套判定；动画起手后锁定目标。

const SoilAutotile := preload("res://scripts/world/soil_autotile.gd")
const ToolEffect := preload("res://scripts/world/tool_effect.gd")
const TILE_SIZE: int = 16
## 种植区允许独立开新田；建筑、水体、树干等障碍不允许开垦。
const TILLABLE := Rect2i(16, 5, 14, 10)
const INITIAL_PLOTS: Array[Rect2i] = [
	Rect2i(18, 6, 4, 3), Rect2i(23, 6, 4, 3),
	Rect2i(18, 10, 4, 3), Rect2i(23, 10, 4, 3),
]

@onready var _soil: TileMapLayer = get_parent().get_node("Soil") as TileMapLayer
@onready var _watered: TileMapLayer = get_parent().get_node("Watered") as TileMapLayer
@onready var _fringe: TileMapLayer = get_parent().get_node("SoilFringe") as TileMapLayer
@onready var _detail: TileMapLayer = get_parent().get_node("Detail") as TileMapLayer
@onready var _cursor: Node2D = $Cursor
@onready var _cursor_border: Line2D = $Cursor/Border
@onready var _cursor_fill: Polygon2D = $Cursor/Fill

var _player: CharacterBody2D
## 格坐标 -> 是否已浇水
var _soil_state: Dictionary = {}
var _locked_cell: Vector2i
var _locked_tree: Sprite2D
var _query_shape: RectangleShape2D
var _show_area: bool = false


func _ready() -> void:
	_soil.tile_set = SoilAutotile.make_tileset()
	_watered.tile_set = _soil.tile_set
	_fringe.clear()
	_query_shape = RectangleShape2D.new()
	_query_shape.size = Vector2(14, 14)
	for plot in INITIAL_PLOTS:
		for y in range(plot.position.y, plot.end.y):
			for x in range(plot.position.x, plot.end.x):
				_soil_state[Vector2i(x, y)] = false
	for cell: Vector2i in _soil_state:
		_refresh_cell(cell)
	_player = get_tree().get_first_node_in_group(&"player") as CharacterBody2D
	if _player != null:
		_player.interaction = self
		_player.action_started.connect(_on_action_started)
		_player.use_requested.connect(_on_use_requested)


func _physics_process(_delta: float) -> void:
	if _player == null:
		_cursor.hide()
		return
	var tool: StringName = _player.current_tool
	if _show_area != (tool == &"hoe"):
		_show_area = tool == &"hoe"
		queue_redraw()
	var cell: Vector2i = _locked_cell if _player.is_acting else target_cell()
	_cursor.visible = tool != &"seeds"
	_cursor.global_position = _soil.to_global(_soil.map_to_local(cell))
	var valid: bool = _player.is_acting or can_use(tool, cell)
	var color := Color("e8e5b5") if valid else Color("b98070")
	if tool == &"watering_can" and valid:
		color = Color("b8e1dc")
	_cursor_border.default_color = color
	_cursor_fill.color = Color(color, 0.10 if valid else 0.05)


func _draw() -> void:
	if not _show_area or _soil == null:
		return
	var start: Vector2 = _soil.map_to_local(TILLABLE.position) - Vector2(8, 8)
	var end: Vector2 = start + Vector2(TILLABLE.size * TILE_SIZE)
	var points: Array[Vector2] = [start, Vector2(end.x, start.y), end, Vector2(start.x, end.y)]
	for index in 4:
		draw_dashed_line(points[index], points[(index + 1) % 4], Color(0.94, 0.89, 0.64, 0.65), 1.0, 3.0)


func interaction_hint(tool: StringName) -> String:
	if _player == null:
		return ""
	if _player.is_acting:
		match tool:
			&"hoe": return "正在开垦…"
			&"watering_can": return "正在浇水…"
			&"axe": return "正在砍伐…"
	var cell: Vector2i = target_cell()
	match tool:
		&"hoe":
			if not TILLABLE.has_point(cell):
				return "种植区外 · 请在虚线范围内开垦"
			if _soil_state.has(cell):
				return "已经开垦 · 可切换水壶浇水"
			if _is_blocked(cell):
				return "地面有障碍 · 避开建筑、石头与树桩"
			return "可以开垦 · 空格 / 左键"
		&"watering_can":
			if not _soil_state.has(cell):
				return "这里还未开垦 · 先使用锄头"
			if _soil_state[cell]:
				return "已经浇水 · 请选择干燥耕地"
			return "可以浇水 · 空格 / 左键"
		&"seeds":
			return "播种功能尚未开放"
		&"axe":
			return "可以砍树 · 空格 / 左键" if _tree_at(cell) != null else "面向树干使用 · 树桩暂不可清除"
	return ""


func target_cell() -> Vector2i:
	# 脚底向上 1px，避免站在格线时朝上和朝下出现相差一格的错觉。
	var base: Vector2i = _soil.local_to_map(_soil.to_local(_player.global_position - Vector2(0, 1)))
	return base + _player.facing_vector()


func can_use(tool: StringName, cell: Vector2i) -> bool:
	match tool:
		&"hoe":
			return _is_tillable(cell)
		&"watering_can":
			return _soil_state.has(cell) and not _soil_state[cell]
		&"axe":
			return _tree_at(cell) != null
		_:
			return false


func _is_tillable(cell: Vector2i) -> bool:
	if not TILLABLE.has_point(cell) or _soil_state.has(cell):
		return false
	return not _is_blocked(cell)


func _is_blocked(cell: Vector2i) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = Transform2D(0.0, _soil.to_global(_soil.map_to_local(cell)))
	query.collision_mask = 1
	query.collide_with_areas = false
	if _player != null:
		query.exclude = [_player.get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _tree_at(cell: Vector2i) -> Sprite2D:
	# 树根落在格线时，接受接触该目标格的树干，避免一侧永远无法命中。
	var center: Vector2 = _soil.to_global(_soil.map_to_local(cell))
	var nearest: Sprite2D
	var nearest_distance: float = INF
	for candidate: Node in get_tree().get_nodes_in_group(&"choppable"):
		var tree := candidate as Sprite2D
		if tree == null or tree.is_felled:
			continue
		var trunk: Vector2 = tree.global_position - Vector2(0, 3)
		var difference: Vector2 = (trunk - center).abs()
		var distance: float = trunk.distance_squared_to(center)
		if difference.x <= 12 and difference.y <= 12 and distance < nearest_distance:
			nearest = tree
			nearest_distance = distance
	return nearest


func _on_action_started(tool: StringName, cell: Vector2i) -> void:
	_locked_cell = cell
	_locked_tree = _tree_at(cell) if tool == &"axe" else null


func _on_use_requested(tool: StringName, cell: Vector2i) -> void:
	match tool:
		&"hoe":
			if _is_tillable(cell):
				_soil_state[cell] = false
				_detail.erase_cell(cell)
				_refresh_region(cell)
				_spawn_effect(cell, tool)
		&"watering_can":
			if can_use(tool, cell):
				_soil_state[cell] = true
				_refresh_cell(cell)
				_spawn_effect(cell, tool)
		&"axe":
			if is_instance_valid(_locked_tree) and not _locked_tree.is_felled:
				_locked_tree.chop(_player.facing_vector())
				_spawn_effect(cell, tool)


func _refresh_region(cell: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_refresh_cell(cell + Vector2i(dx, dy))


func _refresh_cell(cell: Vector2i) -> void:
	if not _soil_state.has(cell):
		return
	var mask: int = SoilAutotile.mask_for(cell, _soil_state)
	var tile := Vector2i(mask % 16, mask / 16)
	_soil.set_cell(cell, 0, tile)
	if _soil_state[cell]:
		_watered.set_cell(cell, 0, tile)
	else:
		_watered.erase_cell(cell)


func _spawn_effect(cell: Vector2i, tool: StringName) -> void:
	var effect := ToolEffect.new()
	effect.kind = tool
	effect.direction = Vector2(_player.facing_vector())
	effect.position = _soil.to_global(_soil.map_to_local(cell))
	effect.z_index = 21
	get_tree().current_scene.add_child(effect)
