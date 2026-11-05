extends Node2D
## 野浆果丛的管理器：开局在地图上随机撒一批，之后每天补长几丛，也负责玩家种植。
##
## 「随机」只发生在生成位置：撒点前会查地形——水面、已开垦的地、已有道具/建筑、
## 离得太近的其他浆果丛，都会被跳过。生成结果进存档，读档后位置固定，不会每开一次变一批。

const Bush := preload("res://scripts/world/resources/berry_bush.gd")

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
const BOUNDS := Rect2(40, 56, 560, 360)
## 农场可开垦区（格）：这是玩家的地，野果不长进来，也不许种进来。
const FARM_PLOT := Rect2i(16, 5, 14, 10)
## 两丛之间至少隔这么远，免得挤成一坨。
const MIN_SPACING: float = 56.0
## 与现有道具/建筑保持的距离。
const PROP_CLEARANCE: float = 18.0

var bushes: Array[Node] = []

var _ready_done: bool = false
var _rng := RandomNumberGenerator.new()
var _water: TileMapLayer
## 桥、木板路、坡地也是"铺好的地面"，灌木长上去会压住贴图。
var _bridges: TileMapLayer
var _paths: TileMapLayer
var _hills: TileMapLayer
var _tiller: Node
var _last_day: int = 1


func _ready() -> void:
	add_to_group(&"berry_grove")
	_rng.randomize()
	_initialize.call_deferred()


func _initialize() -> void:
	_ensure_ready()
	if bushes.is_empty():
		_scatter(WILD_START)


## 读档可能早于 _initialize，所以依赖都在这里统一补齐。
func _ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	var farm := get_parent().get_parent()
	_water = farm.get_node_or_null("Water") as TileMapLayer
	_bridges = farm.get_node_or_null("Bridges") as TileMapLayer
	_paths = farm.get_node_or_null("Paths") as TileMapLayer
	_hills = farm.get_node_or_null("Hills") as TileMapLayer
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
	while placed < count and attempts < count * 60:
		attempts += 1
		var point := Vector2(
			_rng.randf_range(BOUNDS.position.x, BOUNDS.end.x),
			_rng.randf_range(BOUNDS.position.y, BOUNDS.end.y)
		)
		if not can_place_at(point):
			continue
		_spawn(point, KINDS[_rng.randi() % KINDS.size()], true)
		placed += 1


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
func can_place_at(point: Vector2) -> bool:
	if not BOUNDS.has_point(point):
		return false
	var cell := Vector2i((point / 16.0).floor())
	# 整片种植区都留给庄稼，野果和玩家种的浆果都不进这块。
	if FARM_PLOT.has_point(cell):
		return false
	# 水面、桥面、木板小路、坡地上都不长野果：这几层都有贴图，
	# 32px 的灌木压上去就是一块绿糊在桥上（玩家报过"穿模"）。
	for layer: TileMapLayer in [_water, _bridges, _paths, _hills]:
		if layer != null and layer.get_cell_source_id(cell) != -1:
			return false
	if _tiller != null and _tiller.get(&"_soil_state").has(cell):
		return false
	if _tiller != null and _tiller.get(&"_crops").has(cell):
		return false
	for child in get_parent().get_children():
		if child == self or bushes.has(child):
			continue
		if child is Node2D and (child as Node2D).global_position.distance_to(point) < PROP_CLEARANCE:
			return false
	for bush: Node in bushes:
		if (bush as Node2D).global_position.distance_to(point) < MIN_SPACING:
			return false
	return true


func _on_day_started(day: int) -> void:
	if day <= _last_day:
		return
	_last_day = day
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
	return {&"bushes": rows}


func from_dict(data: Dictionary) -> void:
	_ensure_ready()
	for bush: Node in bushes:
		if is_instance_valid(bush):
			bush.queue_free()
	bushes.clear()
	for row in data.get(&"bushes", []):
		var entry: Dictionary = row
		var kind := StringName(String(entry.get(&"kind", "wild_blackberry")))
		var point := Vector2(float(entry.get(&"x", 0.0)), float(entry.get(&"y", 0.0)))
		if point == Vector2.ZERO:
			continue
		var bush := _spawn(point, kind, bool(entry.get(&"wild", true)))
		bush.call(&"from_dict", entry)
