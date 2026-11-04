extends SceneTree
## 生成杂货店室内：18×12 格的小店，柜台 + 货架 + 店主。
##
## 与农舍室内同一套做法（不切场景、放在远处由 HouseManager 显隐），
## 只是尺寸更小、家具不同。相机边界由根节点的 interior_room.gd 声明。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_shop_interior.gd

const OUT_SCENE := "res://scenes/world/shop_interior.tscn"
const TILESET := "res://assets/tilesets/house_terrain.tres"
const ART := "res://assets/generated/content_v1/"

const ROOM_W: int = 18
const ROOM_H: int = 12
const FLOOR_MIN := Vector2i(1, 3)
const FLOOR_MAX := Vector2i(16, 10)
const DOOR_COLUMNS: Array[int] = [8]
## 底部墙再多画几排，让相机能滚过墙底（同农舍）
const EXTRA_WALL_ROWS: int = 3

const SRC_FLOOR := 0
const SRC_WALLPAPER := 1
const SRC_WOOD := 2
const SRC_TRIM := 3
const TILE := Vector2i(0, 0)

## 家具统一缩放：素材 32×32、可见内容约 28px，
## 玩家只有 16×20，1:1 摆会显得家具比人还高。
const FURNITURE_SCALE: float = 0.75

## 家具：[贴图, 脚底中心, 碰撞尺寸]。
## 只用 objects/furniture 的 32×32 素材：terrain/interiors 是 16×16 的贴图零件，
## 混进来会变成"小木箱"，和 32px 的玩家、NPC 比例对不上。
const FURNITURE: Array = [
	# 服务台：店主站在展示柜后面（柜台贴图 96..122，正好挡住他的脚）
	["objects/furniture/display_cabinet.png", Vector2(136, 122), Vector2(30, 16)],
	# 左右两侧靠墙货架
	["objects/furniture/bookcase.png", Vector2(40, 104), Vector2(28, 18)],
	["objects/furniture/cupboard.png", Vector2(232, 104), Vector2(28, 18)],
	# 东南角待客区：圆桌 + 椅子
	["objects/furniture/round_table.png", Vector2(200, 156), Vector2(28, 16)],
	["objects/furniture/oak_chair.png", Vector2(174, 158), Vector2(20, 12)],
	# 角落陈设
	["objects/furniture/potted_fern.png", Vector2(32, 168), Vector2(14, 10)],
	["objects/furniture/basket.png", Vector2(72, 168), Vector2(18, 10)],
	["objects/furniture/tall_potted_tree.png", Vector2(256, 160), Vector2(20, 12)],
	# 墙面挂件：贴在顶部墙面上，不占地面
	["objects/furniture/wall_clock.png", Vector2(136, 56), Vector2.ZERO],
	["objects/furniture/wall_shelf.png", Vector2(72, 56), Vector2.ZERO],
]

## 平铺在地上的东西：单独一层、固定压在角色脚下，不参与 Y 排序，
## 否则角色站在地毯北侧时会被地毯盖住。
const FLOOR_PROPS: Array = [
	["objects/furniture/door_mat.png", Vector2(136, 168)],
	# 待客区地毯：压在圆桌与椅子下面
	["objects/furniture/square_rug.png", Vector2(192, 168)],
]


func _init() -> void:
	var root := _build()
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_SCENE)
	print("[build_shop_interior] saved=%s err=%d" % [OUT_SCENE, err])
	root.free()
	quit(0 if err == OK else 1)


func _build() -> Node2D:
	var room := Node2D.new()
	room.name = "ShopInterior"
	room.set_script(load("res://scripts/world/interior_room.gd") as Script)
	room.set("camera_bounds", Rect2(0, 0, ROOM_W * 16, (ROOM_H + EXTRA_WALL_ROWS) * 16))

	var floor_layer := _make_layer("Floor", 0)
	var wall_layer := _make_layer("Walls", 1)
	# 地毯层：压在地砖之上、墙体与角色之下
	var floor_props := Node2D.new()
	floor_props.name = "FloorProps"
	floor_props.z_index = 2
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	props.z_index = 5

	room.add_child(floor_layer)
	room.add_child(wall_layer)
	room.add_child(floor_props)
	room.add_child(props)
	for child: Node in [floor_layer, wall_layer, floor_props, props]:
		child.owner = room

	_paint_floor(floor_layer)
	_paint_walls(wall_layer)
	_add_wall_body(room)
	_add_flat_props(floor_props, room)
	_add_furniture(props, room)
	_add_keeper(props, room)
	_add_door(room)
	_add_spawn(room)
	return room


func _make_layer(layer_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = load(TILESET) as TileSet
	layer.z_index = z
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return layer


func _paint_floor(layer: TileMapLayer) -> void:
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			layer.set_cell(Vector2i(x, y), SRC_FLOOR, TILE)


func _paint_walls(layer: TileMapLayer) -> void:
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, 0), SRC_WOOD, TILE)
		layer.set_cell(Vector2i(x, 1), SRC_WALLPAPER, TILE)
		layer.set_cell(Vector2i(x, 2), SRC_TRIM, TILE)
	for y in range(3, ROOM_H - 1):
		layer.set_cell(Vector2i(0, y), SRC_WOOD, TILE)
		layer.set_cell(Vector2i(ROOM_W - 1, y), SRC_WOOD, TILE)
	# 底墙整行铺满（含门柱列）：门是贴在墙上的贴图，
	# 留空洞会露出引擎黑底，显得门悬在黑洞里。
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, ROOM_H - 1), SRC_WOOD, TILE)
	for y in range(ROOM_H, ROOM_H + EXTRA_WALL_ROWS):
		for x in ROOM_W:
			layer.set_cell(Vector2i(x, y), SRC_WOOD, TILE)


func _add_wall_body(room: Node2D) -> void:
	var left: float = float(FLOOR_MIN.x) * 16.0
	var right: float = float(FLOOR_MAX.x + 1) * 16.0
	var top: float = float(FLOOR_MIN.y) * 16.0
	var bottom: float = float(FLOOR_MAX.y + 1) * 16.0
	var full_width: float = float(ROOM_W) * 16.0
	var door_row: float = float(ROOM_H - 1) * 16.0

	var walls: Array[Rect2] = [
		Rect2(0.0, 0.0, full_width, top),
		Rect2(0.0, top, left, bottom - top),
		Rect2(right, top, full_width - right, bottom - top),
		Rect2(0.0, door_row, full_width, 16.0),
	]

	var body := StaticBody2D.new()
	body.name = "WallBody"
	body.collision_layer = 1
	body.collision_mask = 0
	room.add_child(body)
	body.owner = room
	for index in walls.size():
		var rect: Rect2 = walls[index]
		var shape := CollisionShape2D.new()
		shape.name = "Wall%d" % index
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.position + rect.size * 0.5
		body.add_child(shape)
		shape.owner = room


## 地垫 / 地毯：固定 z 值，不参与 Y 排序，永远压在角色脚下。
func _add_flat_props(layer: Node2D, room: Node2D) -> void:
	for entry: Array in FLOOR_PROPS:
		var sprite := Sprite2D.new()
		var path: String = ART + String(entry[0])
		sprite.name = String(entry[0]).get_file().get_basename().to_pascal_case()
		sprite.texture = load(path) as Texture2D
		if sprite.texture == null:
			push_warning("[build_shop_interior] 缺少贴图 %s" % path)
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 平铺物以中心对齐格子，不做脚底锚点
		sprite.offset = Vector2.ZERO
		sprite.scale = Vector2.ONE * FURNITURE_SCALE
		sprite.position = entry[1]
		layer.add_child(sprite)
		sprite.owner = room


func _add_furniture(props: Node2D, room: Node2D) -> void:
	for entry: Array in FURNITURE:
		var sprite := Sprite2D.new()
		var path: String = ART + String(entry[0])
		sprite.name = String(entry[0]).get_file().get_basename().to_pascal_case()
		sprite.texture = load(path) as Texture2D
		if sprite.texture == null:
			push_warning("[build_shop_interior] 缺少贴图 %s" % path)
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 32×32 的家具，脚底统一贴 position；offset 跟着 scale 一起缩
		sprite.offset = Vector2(0, -sprite.texture.get_height() * 0.5)
		sprite.scale = Vector2.ONE * FURNITURE_SCALE
		sprite.position = entry[1]
		props.add_child(sprite)
		sprite.owner = room

		var footprint: Vector2 = entry[2]
		if footprint != Vector2.ZERO:
			_add_blocker(sprite, footprint, room)


func _add_blocker(sprite: Sprite2D, size: Vector2, room: Node2D) -> void:
	var body := StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = Vector2(0, -size.y * 0.5)
	body.add_child(shape)
	sprite.add_child(body)
	body.owner = room
	shape.owner = room


## 店主站在柜台后面（柜台在 y=128，他站在 y=110 一侧）。
## 放进 Props 而不是房间根节点，才能和柜台一起做 Y 排序（被柜台挡住下半身）。
func _add_keeper(props: Node2D, room: Node2D) -> void:
	var keeper := load("res://scenes/npcs/shopkeeper.tscn").instantiate() as Node2D
	keeper.name = "Shopkeeper"
	# 站在柜台北侧：柜台（90..122）刚好挡住他的脚，上半身完整露出来
	keeper.position = Vector2(136, 94)
	props.add_child(keeper)
	props.owner = room
	keeper.owner = room


func _add_door(room: Node2D) -> void:
	var door := Node2D.new()
	door.name = "ExitDoor"
	door.set_script(load("res://scripts/world/house_door.gd") as Script)
	door.set("mode", &"exit")
	door.position = Vector2(
		(float(DOOR_COLUMNS[0]) + float(DOOR_COLUMNS.size()) * 0.5) * 16.0,
		float(ROOM_H - 1) * 16.0 + 8.0
	)
	var art := Sprite2D.new()
	art.name = "Art"
	art.texture = load(ART + "terrain/interiors/door.png") as Texture2D
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 无偏移：门贴图正好盖住脚下那格墙砖，四周不露黑底；
	# z 要压过墙体层（z=1），否则整行铺满后门会被墙砖盖住
	art.offset = Vector2.ZERO
	art.z_index = 2
	door.add_child(art)
	room.add_child(door)
	door.owner = room
	art.owner = room


func _add_spawn(room: Node2D) -> void:
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = Vector2(
		(float(DOOR_COLUMNS[0]) + float(DOOR_COLUMNS.size()) * 0.5) * 16.0,
		float(ROOM_H - 3) * 16.0 + 8.0
	)
	room.add_child(spawn)
	spawn.owner = room
