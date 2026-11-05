extends SceneTree
## 农场地图生成器：固定布局、连续水系、可通行木桥与原素材草坡。
##
## 用途：从零构建 40×30 的农场场景并保存为 scenes/world/farm.tscn，
## 包含地形分层、河流与池塘、圆角岸线、双桥、小路、草坡及水体/护栏碰撞。
## 固定随机种子，保证每次生成结果一致，便于对比与回滚。
##
## 运行方式（编辑器打开本项目时也可执行）：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_farm_map.gd
##
## 约定：瓦片 16×16；source 0=草地，1=耕地，2=水面，3=岸线，4=小路，5=坡地，6=桥。
## 场景结构（生成结果）：
##   Farm
##    ├─ Ground            草地底纹（z 0）
##    ├─ Water             四帧水面动画（z 1，不参与碰撞）
##    ├─ Overlay / Hills   岸线圆角与草坡（z 3）
##    ├─ Paths / Bridges   木板小路（z 4）与加宽桥面（z 7）
##    ├─ Detail            地面小装饰（z 4）
##    ├─ WaterCollision    水体碰撞（z -1，藏在草地下，只提供碰撞）
##    ├─ World (y_sort)    所有会遮挡的物件与角色都放这里（z 10）
##    ├─ Bounds            地图外圈静态墙
##    └─ BridgeRails / CliffCollision  桥护栏与坡地碰撞

const FARM_SCENE := "res://scenes/world/farm.tscn"
const TERRAIN_PATH := "res://assets/tilesets/farm_terrain.tres"
const Landscape := preload("res://tools/lib/farm_landscape.gd")
const TerrainTiles := preload("res://tools/lib/terrain_tiles.gd")
## World 容器挂载的遮挡淡出脚本
const OCCLUSION_SCRIPT := "res://scripts/presentation/occlusion_fader.gd"
## 耕地系统脚本与面前格高亮场景
const TILLER_SCRIPT := "res://scripts/world/farming/farm_tiller.gd"
## NPC 网格寻路脚本
const NAV_SCRIPT := "res://scripts/world/navigation/nav_grid.gd"
const CURSOR_SCENE := "res://scenes/world/tile_cursor.tscn"
## 耕地与湿土的压暗色调（素材本身偏亮，压一点更融进草地）
const SOIL_TINT := Color(0.88, 0.82, 0.72)
const WET_TINT := Color(0.70, 0.62, 0.54)

const MAP_W := 40
const MAP_H := 30
const RNG_SEED := 20261102

const SRC_GRASS := 0
const SRC_WATER := 2

## 草地铺地格（3×3 圆角地块的中心格）
const GRASS_FILL := Vector2i(1, 1)
## 草地地面细节变体（第 5、6 行前六列，均为整格不透明）
const GRASS_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
	Vector2i(4, 5), Vector2i(5, 5), Vector2i(0, 6), Vector2i(1, 6),
	Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6),
]
## 草地零星装饰（小花、草簇、碎石）
const GRASS_DECOR: Array[Vector2i] = [
	Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
	Vector2i(6, 6), Vector2i(7, 6),
]
## 3×3 圆角地块的九宫格坐标：行=纵向边，列=横向边
const BLOB_TOP_EDGE := Vector2i(1, 0)
const BLOB_BOTTOM_EDGE := Vector2i(1, 2)
const BLOB_LEFT_EDGE := Vector2i(0, 1)
const BLOB_RIGHT_EDGE := Vector2i(2, 1)
const BLOB_TOP_LEFT := Vector2i(0, 0)
const BLOB_TOP_RIGHT := Vector2i(2, 0)
const BLOB_BOTTOM_LEFT := Vector2i(0, 2)
const BLOB_BOTTOM_RIGHT := Vector2i(2, 2)

## 苗圃：4 块 4×3 的耕地，块与块之间留 1 格草地通道。
## 瓦片由 farm_tiller.gd 运行时绘制，这里只用于排除地面装饰。
const PLOTS: Array[Rect2i] = [
	Rect2i(18, 6, 4, 3),
	Rect2i(23, 6, 4, 3),
	Rect2i(18, 10, 4, 3),
	Rect2i(23, 10, 4, 3),
]

## 地面细节密度与装饰密度（按格概率）
const VARIANT_CHANCE := 0.22
const DECOR_CHANCE := 0.035

## 地形分层：名称、z_index、是否参与碰撞
## Soil / Watered 由 scripts/world/farming/farm_tiller.gd 在运行时填瓦片（V0.4）
const LAYER_SPECS: Array = [
	["Ground", 0, false],
	["Water", 1, false],
	["Overlay", 3, false],
	["Paths", 4, false],
	["Hills", 3, false],
	["Bridges", 7, false],
	["Detail", 4, false],
	["SoilFringe", 5, false],
	["Soil", 5, false],
	["Watered", 6, false],
	["WaterCollision", -1, true],
]

## 道具摆放：场景路径 + 脚底坐标；可持久化道具的第三列是不可随位置/名字变化的固定 ID。
const PROP_TABLE: Array = [
	["res://scenes/world/props/cottage.tscn", Vector2(472, 144)],
	["res://scenes/world/props/general_store.tscn", Vector2(488, 256)],
	["res://scenes/world/props/bush.tscn", Vector2(520, 192)],
	["res://scenes/world/props/mushroom.tscn", Vector2(536, 152)],
	["res://scenes/world/props/tree_fruit.tscn", Vector2(552, 216), &"farm/tree/552/216"],
	["res://scenes/world/props/log.tscn", Vector2(264, 208)],
	["res://scenes/world/props/rock.tscn", Vector2(264, 152), &"farm/rock/264/152"],
	["res://scenes/world/props/tree_big.tscn", Vector2(40, 72), &"farm/tree/40/72"],
	["res://scenes/world/props/tree_big.tscn", Vector2(104, 56), &"farm/tree/104/56"],
	["res://scenes/world/props/tree_small.tscn", Vector2(88, 64), &"farm/tree/88/64"],
	["res://scenes/world/props/tree_fruit.tscn", Vector2(232, 56), &"farm/tree/232/56"],
	["res://scenes/world/props/tree_big.tscn", Vector2(296, 72), &"farm/tree/296/72"],
	["res://scenes/world/props/tree_small.tscn", Vector2(360, 56), &"farm/tree/360/56"],
	["res://scenes/world/props/tree_big.tscn", Vector2(424, 72), &"farm/tree/424/72"],
	["res://scenes/world/props/tree_big.tscn", Vector2(520, 64), &"farm/tree/520/64"],
	["res://scenes/world/props/tree_small.tscn", Vector2(584, 72), &"farm/tree/584/72"],
	["res://scenes/world/props/tree_big.tscn", Vector2(632, 48), &"farm/tree/632/48"],
	["res://scenes/world/props/tree_small.tscn", Vector2(24, 168), &"farm/tree/24/168"],
	["res://scenes/world/props/bush.tscn", Vector2(56, 232)],
	["res://scenes/world/props/tree_big.tscn", Vector2(32, 312), &"farm/tree/32/312"],
	["res://scenes/world/props/mushroom.tscn", Vector2(64, 360)],
	["res://scenes/world/props/tree_small.tscn", Vector2(24, 424), &"farm/tree/24/424"],
	["res://scenes/world/props/rock.tscn", Vector2(72, 464), &"farm/rock/72/464"],
	["res://scenes/world/props/tree_big.tscn", Vector2(616, 176), &"farm/tree/616/176"],
	["res://scenes/world/props/bush.tscn", Vector2(592, 240)],
	["res://scenes/world/props/tree_big.tscn", Vector2(632, 336), &"farm/tree/632/336"],
	["res://scenes/world/props/rock.tscn", Vector2(600, 440), &"farm/rock/600/440"],
	["res://scenes/world/props/tree_small.tscn", Vector2(624, 456), &"farm/tree/624/456"],
	["res://scenes/world/props/tree_big.tscn", Vector2(136, 448), &"farm/tree/136/448"],
	["res://scenes/world/props/bush.tscn", Vector2(216, 432)],
	["res://scenes/world/props/tree_small.tscn", Vector2(304, 464), &"farm/tree/304/464"],
	["res://scenes/world/props/log.tscn", Vector2(488, 456)],
	["res://scenes/world/props/rock.tscn", Vector2(376, 288), &"farm/rock/376/288"],
	["res://scenes/world/props/mushroom.tscn", Vector2(264, 456)],
	["res://scenes/world/props/bush.tscn", Vector2(592, 312)],
	["res://scenes/world/props/mushroom.tscn", Vector2(312, 296)],
	["res://scenes/world/props/bush.tscn", Vector2(104, 320)],
	["res://scenes/world/props/tree_small.tscn", Vector2(64, 120), &"farm/tree/64/120"],
]


func _init() -> void:
	var terrain := load(TERRAIN_PATH) as TileSet
	if terrain == null:
		push_error("[build_farm_map] 无法加载 %s" % TERRAIN_PATH)
		quit(1)
		return
	if not _validate_tileset(terrain):
		push_error("[build_farm_map] 瓦片校验失败，已中止生成")
		quit(1)
		return
	var terrain_uid: int = ResourceLoader.get_resource_uid(TERRAIN_PATH)
	terrain = TerrainTiles.make_tileset(terrain)
	var terrain_error: Error = ResourceSaver.save(terrain, TERRAIN_PATH)
	if terrain_error == OK and terrain_uid != ResourceUID.INVALID_ID:
		terrain_error = ResourceSaver.set_uid(TERRAIN_PATH, terrain_uid)
	if terrain_error != OK:
		push_error("[build_farm_map] 保存地形资源失败：%d" % terrain_error)
		quit(1)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED

	var farm := _build_farm(terrain)
	var ground := farm.get_node("Ground") as TileMapLayer
	var detail := farm.get_node("Detail") as TileMapLayer
	var world := farm.get_node("World") as Node2D

	_paint_ground(ground, rng)
	Landscape.paint(farm)
	_paint_detail(detail, rng, farm)

	var prop_count := _place_props(world, farm)

	var packed := PackedScene.new()
	var pack_err := packed.pack(farm)
	if pack_err != OK:
		push_error("[build_farm_map] 打包场景失败：%d" % pack_err)
		quit(1)
		return
	var save_err := ResourceSaver.save(packed, FARM_SCENE)
	print("[build_farm_map] saved=%s err=%d props=%d" % [FARM_SCENE, save_err, prop_count])
	farm.queue_free()
	quit(0 if save_err == OK else 1)


## 从零构建场景骨架：地形层 + y 排序容器 + 边界墙。
func _build_farm(terrain: TileSet) -> Node2D:
	var farm := Node2D.new()
	farm.name = "Farm"

	for spec in LAYER_SPECS:
		var layer := TileMapLayer.new()
		layer.name = spec[0]
		layer.tile_set = terrain
		layer.z_index = spec[1]
		layer.collision_enabled = spec[2]
		farm.add_child(layer)
		layer.owner = farm

	# 所有需要互相遮挡的物件与角色都挂在这个节点下（V0.3 遮挡排序）。
	# 挂 occlusion_fader 后，角色被前方道具挡住时道具会自动半透明。
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.z_index = 10
	var fader := load(OCCLUSION_SCRIPT) as Script
	if fader == null:
		push_warning("[build_farm_map] 缺少遮挡淡出脚本 %s" % OCCLUSION_SCRIPT)
	else:
		world.set_script(fader)
	farm.add_child(world)
	world.owner = farm

	_add_bounds(farm)
	_add_tiller(farm)
	_add_nav(farm)
	return farm


## 网格寻路节点：NPC 用，运行时扫描水面与道具碰撞建 A*。
func _add_nav(farm: Node2D) -> void:
	var nav := Node2D.new()
	nav.name = "Nav"
	var script := load(NAV_SCRIPT) as Script
	if script == null:
		push_warning("[build_farm_map] 缺少寻路脚本 %s" % NAV_SCRIPT)
	else:
		nav.set_script(script)
	farm.add_child(nav)
	nav.owner = farm


## 耕地系统：Tiller 节点 + 面前格高亮框；已浇水层用压暗色调表示湿土。
func _add_tiller(farm: Node2D) -> void:
	var soil := farm.get_node_or_null("Soil") as TileMapLayer
	if soil != null:
		soil.modulate = SOIL_TINT
	var watered := farm.get_node_or_null("Watered") as TileMapLayer
	if watered != null:
		watered.modulate = WET_TINT

	var tiller := Node2D.new()
	tiller.name = "Tiller"
	var tiller_script := load(TILLER_SCRIPT) as Script
	if tiller_script == null:
		push_warning("[build_farm_map] 缺少耕地脚本 %s" % TILLER_SCRIPT)
	else:
		tiller.set_script(tiller_script)
	farm.add_child(tiller)
	tiller.owner = farm

	var cursor_scene := load(CURSOR_SCENE) as PackedScene
	if cursor_scene == null:
		push_warning("[build_farm_map] 缺少高亮框场景 %s" % CURSOR_SCENE)
		return
	var cursor := cursor_scene.instantiate() as Node2D
	cursor.name = "Cursor"
	tiller.add_child(cursor)
	cursor.owner = farm


## 地图边界：地图外一圈静态碰撞墙，防止角色走出地图。
func _add_bounds(farm: Node2D) -> void:
	const THICKNESS := 32.0
	var body := StaticBody2D.new()
	body.name = "Bounds"
	farm.add_child(body)
	body.owner = farm

	var map_size := Vector2(MAP_W * 16, MAP_H * 16)
	var walls: Array[Rect2] = [
		Rect2(Vector2(-THICKNESS, -THICKNESS), Vector2(THICKNESS, map_size.y + THICKNESS * 2.0)),
		Rect2(Vector2(map_size.x, -THICKNESS), Vector2(THICKNESS, map_size.y + THICKNESS * 2.0)),
		Rect2(Vector2(0, -THICKNESS), Vector2(map_size.x, THICKNESS)),
		Rect2(Vector2(0, map_size.y), Vector2(map_size.x, THICKNESS)),
	]
	var names: Array[String] = ["WallLeft", "WallRight", "WallTop", "WallBottom"]

	for index in walls.size():
		var rect: Rect2 = walls[index]
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.name = names[index]
		collider.shape = shape
		collider.position = rect.position + rect.size * 0.5
		body.add_child(collider)
		collider.owner = farm


## 预检：确认脚本里用到的每个图集坐标都在 TileSet 中声明过。
## 缺瓦片时 set_cell 会静默跳过，导致地面露出下层（曾经踩过这个坑）。
func _validate_tileset(tile_set: TileSet) -> bool:
	var grass_tiles: Array[Vector2i] = [
		GRASS_FILL, BLOB_TOP_EDGE, BLOB_BOTTOM_EDGE, BLOB_LEFT_EDGE, BLOB_RIGHT_EDGE,
		BLOB_TOP_LEFT, BLOB_TOP_RIGHT, BLOB_BOTTOM_LEFT, BLOB_BOTTOM_RIGHT,
	]
	grass_tiles.append_array(GRASS_VARIANTS)
	grass_tiles.append_array(GRASS_DECOR)

	var ok := true
	ok = _check_source(tile_set, SRC_GRASS, grass_tiles) and ok
	ok = _check_source(tile_set, SRC_WATER, [Vector2i(0, 0)]) and ok
	# 耕地图集由 scripts/world/farming/farm_tiller.gd 自行校验（它才是使用方）
	return ok


func _check_source(tile_set: TileSet, source_id: int, coords: Array[Vector2i]) -> bool:
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		push_error("[build_farm_map] TileSet 缺少 source %d" % source_id)
		return false
	var ok := true
	for coord in coords:
		if not source.has_tile(coord):
			push_error("[build_farm_map] source %d 缺少瓦片 %s" % [source_id, coord])
			ok = false
	return ok


## 草地：整片铺底，再按概率撒细节变体，避免大片纯色。
func _paint_ground(layer: TileMapLayer, rng: RandomNumberGenerator) -> void:
	for y in MAP_H:
		for x in MAP_W:
			layer.set_cell(Vector2i(x, y), SRC_GRASS, GRASS_FILL)
	for y in MAP_H:
		for x in MAP_W:
			if rng.randf() < VARIANT_CHANCE:
				var variant: Vector2i = GRASS_VARIANTS[rng.randi_range(0, GRASS_VARIANTS.size() - 1)]
				layer.set_cell(Vector2i(x, y), SRC_GRASS, variant)


## 地面装饰：只在草地格上撒小花/碎石，避开池塘与农田。
func _paint_detail(layer: TileMapLayer, rng: RandomNumberGenerator, farm: Node2D) -> void:
	var water: TileMapLayer = farm.get_node("Water") as TileMapLayer
	var paths: TileMapLayer = farm.get_node("Paths") as TileMapLayer
	for y in MAP_H:
		for x in MAP_W:
			var cell := Vector2i(x, y)
			if water.get_cell_source_id(cell) != -1 or paths.get_cell_source_id(cell) != -1 or Landscape.BLUFF.has_point(cell) or Landscape.on_bridge(cell) or _in_plot(cell):
				continue
			if rng.randf() < DECOR_CHANCE:
				var tile: Vector2i = GRASS_DECOR[rng.randi_range(0, GRASS_DECOR.size() - 1)]
				layer.set_cell(cell, SRC_GRASS, tile)


## 判断格子是否落在任一块苗圃内。
func _in_plot(cell: Vector2i) -> bool:
	for plot in PLOTS:
		if plot.has_point(cell):
			return true
	return false





## 道具：按 PROP_TABLE 实例化到 y 排序容器，owner 设为场景根以便打包保存。
func _place_props(world: Node2D, farm: Node2D) -> int:
	var count := 0
	for entry in PROP_TABLE:
		var scene_path: String = entry[0]
		var foot: Vector2 = entry[1]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("[build_farm_map] 缺少道具场景 %s" % scene_path)
			continue
		var inst := packed.instantiate() as Node2D
		inst.position = foot
		if inst.has_method(&"persistence_id"):
			inst.persistent_id = entry[2]
		inst.name = "%s%d" % [scene_path.get_file().get_basename().to_pascal_case(), count]
		world.add_child(inst)
		inst.owner = farm
		count += 1
	return count
