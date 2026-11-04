class_name FarmNav
extends Node2D
## 农场网格寻路：把水面、道具碰撞与地图边界转成 AStarGrid2D 的不可走格。
##
## 为什么用格子 A* 而不是 NavigationRegion2D：
## 本项目所有坐标都以 16px 格子为基准，道具碰撞是固定的小矩形/圆；
## 直接按格标记既不需要烘焙导航网格，也能在无窗口自检里跑通。
##
## 用法：
##   var nav := get_tree().get_first_node_in_group(&"nav") as FarmNav
##   var path: Array[Vector2i] = nav.find_path_cells(from_world, to_world)

const CELL: int = 16
## 与 tools/build/build_farm_map.gd 的 MAP_W / MAP_H 保持一致
const MAP_W: int = 40
const MAP_H: int = 30
## 道具碰撞格的外扩：让 NPC 不贴着墙根走，避免视觉上卡进树冠/墙里
const CLEARANCE: float = 2.0

var _astar := AStarGrid2D.new()
var _rebuild_pending: bool = false


func _ready() -> void:
	add_to_group(&"nav")
	# 等所有道具 _ready 完再扫碰撞，否则 Body 还没建好。
	request_rebuild()
	get_tree().node_added.connect(_on_obstacle_node_changed)
	get_tree().node_removed.connect(_on_obstacle_node_changed)


func _on_obstacle_node_changed(node: Node) -> void:
	if node is StaticBody2D or node is CollisionShape2D:
		request_rebuild()


func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	build.call_deferred()


func build() -> void:
	_rebuild_pending = false
	# 相同 region 的 update 不会清空旧 solid 标记；用新网格重建当前世界，避免幽灵障碍。
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, MAP_W, MAP_H)
	_astar.cell_size = Vector2(CELL, CELL)
	# 节点落在格中心：cell(x,y) -> world(x*16+8, y*16+8)
	_astar.offset = Vector2(CELL, CELL) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()

	_mark_border()
	_mark_water()
	_mark_props()


func find_path_cells(from_world: Vector2, to_world: Vector2) -> Array[Vector2i]:
	var from_cell := world_to_cell(from_world)
	var to_cell := world_to_cell(to_world)
	if not is_walkable(from_cell) or not is_walkable(to_cell):
		return []
	var raw := _astar.get_id_path(from_cell, to_cell)
	var path: Array[Vector2i] = []
	for cell: Vector2i in raw:
		path.append(cell)
	return path


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for cell: Vector2i in find_path_cells(from_world, to_world):
		points.append(cell_to_world(cell))
	return points


func world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL, CELL) * 0.5


func is_walkable(cell: Vector2i) -> bool:
	if not _astar.is_in_boundsv(cell):
		return false
	return not _astar.is_point_solid(cell)


## 目标格不可走时，向外螺旋找最近的可走格（用于"走到某人身边"这种柔性目标）。
func nearest_walkable(cell: Vector2i, max_radius: int = 6) -> Vector2i:
	if is_walkable(cell):
		return cell
	for radius in range(1, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := cell + Vector2i(dx, dy)
				if is_walkable(candidate):
					return candidate
	return Vector2i(-1, -1)


## 在指定格周围随机挑一个可走格，给 NPC 的闲逛日程用。
func random_walkable_near(center: Vector2i, radius: int, rng: RandomNumberGenerator) -> Vector2i:
	for _attempt in 24:
		var offset := Vector2i(
			rng.randi_range(-radius, radius),
			rng.randi_range(-radius, radius)
		)
		var candidate := center + offset
		if is_walkable(candidate):
			return candidate
	return nearest_walkable(center)


func blocked_count() -> int:
	var total := 0
	for y in MAP_H:
		for x in MAP_W:
			if _astar.is_point_solid(Vector2i(x, y)):
				total += 1
	return total


func _mark_border() -> void:
	for x in MAP_W:
		_astar.set_point_solid(Vector2i(x, 0), true)
		_astar.set_point_solid(Vector2i(x, MAP_H - 1), true)
	for y in MAP_H:
		_astar.set_point_solid(Vector2i(0, y), true)
		_astar.set_point_solid(Vector2i(MAP_W - 1, y), true)


func _mark_water() -> void:
	var farm := get_parent()
	var water := farm.get_node_or_null("WaterCollision") as TileMapLayer
	if water == null:
		push_warning("[farm_nav] 缺少 WaterCollision，水面不会被当作障碍")
		return
	for cell: Vector2i in water.get_used_cells():
		if _astar.is_in_boundsv(cell):
			_astar.set_point_solid(cell, true)


## 扫 World 下所有静态碰撞体（道具、建筑、树干）占用的格子。
func _mark_props() -> void:
	var farm := get_parent()
	var world := farm.get_node_or_null("World")
	if world == null:
		return
	for child: Node in world.find_children("*", "StaticBody2D", true, false):
		var body := child as StaticBody2D
		if body.is_queued_for_deletion() or body.collision_layer == 0:
			continue
		for shape_node in body.get_children():
			var shape := shape_node as CollisionShape2D
			if shape == null or shape.disabled or shape.shape == null:
				continue
			_mark_rect(shape_rect(shape))


func _mark_rect(rect: Rect2) -> void:
	var padded := rect.grow(CLEARANCE)
	var min_cell := world_to_cell(padded.position)
	var max_cell := world_to_cell(padded.end)
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			if not _astar.is_in_boundsv(cell):
				continue
			if padded.has_point(cell_to_world(cell)):
				_astar.set_point_solid(cell, true)


## 把碰撞形状换成世界坐标矩形；只处理矩形与圆，其他形状按包围盒兜底。
static func shape_rect(shape: CollisionShape2D) -> Rect2:
	var resource := shape.shape
	if resource is RectangleShape2D:
		var size: Vector2 = (resource as RectangleShape2D).size
		return Rect2(shape.global_position - size * 0.5, size)
	if resource is CircleShape2D:
		var radius: float = (resource as CircleShape2D).radius
		return Rect2(shape.global_position - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	return Rect2(shape.global_position - Vector2(8, 8), Vector2(16, 16))
