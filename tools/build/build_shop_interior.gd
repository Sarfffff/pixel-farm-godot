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
const DOOR_COLUMNS: Array[int] = [8, 9]
## 底部墙再多画几排，让相机能滚过墙底（同农舍）
const EXTRA_WALL_ROWS: int = 3

const SRC_FLOOR := 0
const SRC_WALLPAPER := 1
const SRC_WOOD := 2
const SRC_TRIM := 3
const TILE := Vector2i(0, 0)

## 家具：[贴图, 脚底中心, 碰撞尺寸]
const FURNITURE: Array = [
	# 柜台：三格 wood_counter 拼成一条连续柜台
	["terrain/interiors/wood_counter.png", Vector2(112, 128), Vector2(48, 14)],
	["terrain/interiors/wood_counter.png", Vector2(128, 128), Vector2.ZERO],
	["terrain/interiors/wood_counter.png", Vector2(144, 128), Vector2.ZERO],
	# 货架：贴着上墙摆一排
	["terrain/interiors/shop_shelf.png", Vector2(64, 64), Vector2(16, 10)],
	["terrain/interiors/shop_shelf.png", Vector2(80, 64), Vector2.ZERO],
	["terrain/interiors/shop_shelf.png", Vector2(208, 64), Vector2(16, 10)],
	["terrain/interiors/shop_shelf.png", Vector2(224, 64), Vector2.ZERO],
	# 店内陈设
	["objects/furniture/display_cabinet.png", Vector2(248, 104), Vector2(28, 20)],
	["objects/furniture/bookcase.png", Vector2(32, 100), Vector2(28, 20)],
	["objects/furniture/potted_fern.png", Vector2(32, 152), Vector2.ZERO],
	["objects/furniture/basket.png", Vector2(248, 160), Vector2.ZERO],
	["objects/furniture/wood_stool.png", Vector2(96, 168), Vector2.ZERO],
	["objects/furniture/door_mat.png", Vector2(144, 160), Vector2.ZERO],
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
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	props.z_index = 5

	room.add_child(floor_layer)
	room.add_child(wall_layer)
	room.add_child(props)
	for child: Node in [floor_layer, wall_layer, props]:
		child.owner = room

	_paint_floor(floor_layer)
	_paint_walls(wall_layer)
	_add_wall_body(room)
	_add_furniture(props, room)
	_add_keeper(room)
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
	for x in ROOM_W:
		if x in DOOR_COLUMNS:
			continue
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
		# 贴图可能是 16×16 也可能是 32×32，脚底统一贴 position
		sprite.offset = Vector2(0, -sprite.texture.get_height() * 0.5)
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


## 店主站在柜台后面（柜台在 y=128，他站在 y=112 一侧）。
func _add_keeper(room: Node2D) -> void:
	var keeper := load("res://scenes/npcs/shopkeeper.tscn").instantiate() as Node2D
	keeper.name = "Shopkeeper"
	keeper.position = Vector2(120, 112)
	room.add_child(keeper)
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
	art.offset = Vector2(0, -8)
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
