extends Node2D
## 野浆果丛的管理器：开局在地图上随机撒一批，之后每天补长几丛，也负责玩家种植。
##
## 「随机」只发生在生成位置：撒点前会查地形——水面、已开垦的地、已有道具/建筑、
## 离得太近的其他浆果丛，都会被跳过。生成结果进存档，读档后位置固定，不会每开一次变一批。

const Bush := preload("res://scripts/world/resources/berry_bush.gd")
const GroundRules := preload("res://scripts/world/farming/farm_ground_rules.gd")
const SpriteBounds := preload("res://scripts/presentation/visible_sprite_bounds.gd")
## 按成株可见叶丛预留空间，额外留2像素河岸/路沿间隔。
const EDGE_CLEARANCE: float = 2.0

## 开局撒多少丛、地图上最多同时存在多少丛野生浆果。
const WILD_START: int = 10
const WILD_MAX: int = 14
## 每天最多补长几丛，避免一夜之间长满。
const DAILY_GROW: int = 1

const KINDS: Array[StringName] = [&"wild_blackberry", &"wild_raspberry", &"wild_gooseberry"]
const COLORS := {
	&"wild_blackberry": Color("3b2a45"),
	&"wild_raspberry": Color("b5324a"),
	&"wild_gooseberry": Color("d8e05c"),
}
## 种子 -> 种出来的浆果。
const SEED_TO_KIND := {
	&"wild_blackberry_seeds": &"wild_blackberry",
	&"wild_raspberry_seeds": &"wild_raspberry",
	&"wild_gooseberry_seeds": &"wild_gooseberry",
}

## 允许生成的矩形（世界坐标）：避开地图边缘与出生点。
const BOUNDS := Rect2(24, 40, 592, 416)
## 农场可开垦区（格）：这是玩家的地，野果不长进来，也不许种进来。
const FARM_PLOT := Rect2i(16, 5, 14, 10)
## 两丛之间至少隔这么远，免得挤成一坨。
const MIN_SPACING: float = 44.0
## 与现有道具/建筑保持的距离。
const PROP_CLEARANCE: float = 18.0

var bushes: Array[Node] = []
## 极端拥挤旧档暂时没有落点时保留记录，不丢失玩家种下的灌木。
var _waiting: Array[Dictionary] = []

var _ready_done: bool = false
var _rng := RandomNumberGenerator.new()
var _water: TileMapLayer
var _tiller: Node
var _last_day: int = 1


func _ready() -> void:
	add_to_group(&"berry_grove")
	_rng.seed = 20261105
	_initialize.call_deferred()


func _initialize() -> void:
	_ensure_ready()
	if bushes.is_empty() and _waiting.is_empty():
		_scatter(WILD_START)


## 读档可能早于 _initialize，所以依赖都在这里统一补齐。
func _ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	var farm := get_parent().get_parent()
	_water = farm.get_node_or_null("Water") as TileMapLayer
	_tiller = get_tree().get_first_node_in_group(&"farm_tiller")
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		_last_day = int(time.day)
		if time.has_signal(&"day_started"):
			time.day_started.connect(_on_day_started)


# --------------------------------------------------------------------------
# 生成
# --------------------------------------------------------------------------

func _scatter(count: int) -> void:
	var placed: int = 0
	var attempts: int = 0
	var kind_offset: int = _rng.randi_range(0, KINDS.size() - 1)
	while placed < count and attempts < count * 60:
		attempts += 1
		var point := Vector2(
			_rng.randf_range(BOUNDS.position.x, BOUNDS.end.x),
			_rng.randf_range(BOUNDS.position.y, BOUNDS.end.y)
		)
		if not can_place_at(point):
			continue
		if not _spawn_wild_with_reserve(point, KINDS[(kind_offset + placed) % KINDS.size()]):
			break
		placed += 1
	# 随机尝试耗尽后搜索合法种植格；数量受安全空间限制，品种轮换不受拥挤影响。
	while placed < count:
		var point: Vector2 = _nearest_clear_point(BOUNDS.get_center(), true)
		if point == Vector2.ZERO:
			break
		if not _spawn_wild_with_reserve(point, KINDS[(kind_offset + placed) % KINDS.size()]):
			break
		placed += 1


func _spawn_wild_with_reserve(point: Vector2, kind: StringName) -> bool:
	var bush: Node = _spawn(point, kind, true)
	# 野果种子需要仍有地方可种，野生补长不能占掉最后一处安全种植格。
	if _nearest_clear_point(BOUNDS.get_center(), true) == Vector2.ZERO:
		bushes.erase(bush)
		bush.queue_free()
		return false
	return true


func _spawn(point: Vector2, kind: StringName, wild: bool) -> Node:
	var bush := Bush.new()
	bush.kind = kind
	bush.berry_color = COLORS.get(kind, Color("3b2a45"))
	bush.manager = self
	bush.wild = wild
	bush.stage = 1 if wild else 0
	# 与角色、其他道具共用 Y 排序容器。
	get_parent().add_child(bush)
	bush.global_position = point
	bushes.append(bush)
	return bush


## 这个位置能不能长浆果：不压水、不压耕地、不贴道具、不挨着别的浆果丛。
func can_place_at(point: Vector2, check_actors: bool = true) -> bool:
	_ensure_ready()
	var area: Rect2 = placement_rect(point)
	if not BOUNDS.encloses(area):
		return false
	# 整片种植区都留给庄稼，野果和玩家种的浆果都不进这块。
	var farm: Node2D = get_parent().get_parent() as Node2D
	var plot: Rect2 = Rect2(Vector2(FARM_PLOT.position * 16), Vector2(FARM_PLOT.size * 16))
	if (farm.global_transform * plot).intersects(area):
		return false
	if not GroundRules.is_clear(farm, area):
		return false
	var cell: Vector2i = _water.local_to_map(_water.to_local(point))
	if _tiller != null and _tiller.get(&"_soil_state").has(cell):
		return false
	if _tiller != null and _tiller.get(&"_crops").has(cell):
		return false
	for child in get_parent().get_children():
		if child == self or child.is_queued_for_deletion() or bushes.has(child):
			continue
		if child.is_in_group(&"world_actor") or child is CharacterBody2D:
			if check_actors and child is Node2D and (child as Node2D).global_position.distance_to(point) < 24.0:
				return false
			continue
		if _overlaps_prop(child, area):
			return false
		if child is Node2D and (child as Node2D).global_position.distance_to(point) < PROP_CLEARANCE:
			return false
	for bush: Node in bushes:
		if (bush as Node2D).global_position.distance_to(point) < MIN_SPACING:
			return false
	return true


func _overlaps_prop(node: Node, area: Rect2) -> bool:
	if node.is_queued_for_deletion() or (node is CanvasItem and not (node as CanvasItem).visible):
		return false
	if node is Sprite2D:
		var sprite: Sprite2D = node as Sprite2D
		if (sprite.global_transform * SpriteBounds.local_rect(sprite)).grow(EDGE_CLEARANCE).intersects(area):
			return true
	# 鸡舍等容器把贴图放在内部，不能只检查World第一层的脚底坐标。
	for child: Node in node.get_children():
		if _overlaps_prop(child, area):
			return true
	return false


static func placement_rect(point: Vector2) -> Rect2:
	var footprint: Rect2 = Bush.growth_rect()
	return Rect2(point + footprint.position, footprint.size).grow(EDGE_CLEARANCE)


func _on_day_started(day: int) -> void:
	if day <= _last_day:
		return
	_last_day = day
	if not _waiting.is_empty():
		var pending: Array[Dictionary] = _waiting.duplicate(true)
		_waiting.clear()
		_restore_rows(pending)
	var wild_count: int = 0
	for bush: Node in bushes:
		if bool(bush.get(&"wild")):
			wild_count += 1
	if wild_count >= WILD_MAX:
		return
	_scatter(mini(DAILY_GROW, WILD_MAX - wild_count))


# --------------------------------------------------------------------------
# 玩家种植
# --------------------------------------------------------------------------

## 这个种子是哪种浆果；不是浆果种子返回空。
func kind_for_seed(seed_id: StringName) -> StringName:
	return SEED_TO_KIND.get(seed_id, &"")


## 能不能在这一格种下：必须是空草地，别的条件与随机生成一致。
func can_plant_at(cell: Vector2i) -> bool:
	var center := Vector2(cell) * 16.0 + Vector2(8, 14)
	return can_place_at(center)


func plant_at(cell: Vector2i, kind: StringName) -> void:
	var center := Vector2(cell) * 16.0 + Vector2(8, 14)
	if not KINDS.has(kind) or not can_place_at(center):
		return
	var bush := _spawn(center, kind, false)
	bush.call(&"plant", kind, COLORS.get(kind, Color("3b2a45")))


# --------------------------------------------------------------------------
# 查询与存档
# --------------------------------------------------------------------------

func ripe_count() -> int:
	var count: int = 0
	for bush: Node in bushes:
		if bool(bush.call(&"has_berries")):
			count += 1
	return count


## 采集后由浆果丛回调，目前只留作以后接成就/提示用。
func on_bush_changed() -> void:
	pass


func to_dict() -> Dictionary:
	var rows: Array = []
	for bush: Node in bushes:
		if is_instance_valid(bush):
			rows.append(bush.call(&"to_dict"))
	rows.append_array(_waiting.duplicate(true))
	return {&"bushes": rows}


func from_dict(data: Dictionary) -> void:
	_ensure_ready()
	for bush: Node in bushes:
		if is_instance_valid(bush):
			bush.queue_free()
	bushes.clear()
	_waiting.clear()
	var safe: Array = []
	var misplaced: Array = []
	for row: Dictionary in data.get(&"bushes", []):
		var point: Vector2 = Vector2(float(row.get(&"x", 0.0)), float(row.get(&"y", 0.0)))
		(safe if can_place_at(point, false) else misplaced).append(row)
	# 先占住全部合法旧位置，避免较早出现的坏坐标挤走后面的正常灌木。
	_restore_rows(safe, true)
	_restore_rows(misplaced, true)


func _restore_rows(rows: Array, restoring: bool = false) -> void:
	for row in rows:
		var entry: Dictionary = row
		var kind := StringName(String(entry.get(&"kind", "wild_blackberry")))
		var point := Vector2(float(entry.get(&"x", 0.0)), float(entry.get(&"y", 0.0)))
		if point == Vector2.ZERO:
			continue
		if not can_place_at(point, not restoring):
			point = _nearest_clear_point(point, not restoring)
		if point == Vector2.ZERO:
			_waiting.append(entry.duplicate(true))
			continue
		var bush := _spawn(point, kind, bool(entry.get(&"wild", true)))
		bush.call(&"from_dict", entry)


## 旧档只移动不安全的灌木；最近草地搜索固定顺序，不重新抽品种或生长日期。
func _nearest_clear_point(origin: Vector2, check_actors: bool = true) -> Vector2:
	var closest: Vector2 = Vector2.ZERO
	var distance: float = INF
	for y: int in range(4, 28):
		for x: int in range(2, 38):
			var point: Vector2 = Vector2(x * 16 + 8, y * 16 + 14)
			var candidate_distance: float = point.distance_squared_to(origin)
			if candidate_distance < distance and can_place_at(point, check_actors):
				closest = point
				distance = candidate_distance
	return closest
