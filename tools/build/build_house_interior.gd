extends SceneTree
## 生成农舍室内场景：一间 15×11 格的木屋内部。
##
## 室内不切换场景，而是作为 Main 的子节点放在远处（HouseManager 负责显隐），
## 这样时间、背包、存档等 Systems 不会因为进出屋被重建。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_house_interior.gd

const OUT_SCENE := "res://scenes/world/house_interior.tscn"
const TILESET := "res://assets/tilesets/house_terrain.tres"
const ART := "res://assets/generated/content_v1/"

## 房屋尺寸（格）。27×19 = 432×304：
## 宽度刚好卡住相机的最小缩放（zoom≈1.5），高度比画面高一点，
## 于是相机能上下轻微滚动——站在门口时门不会被底部工具栏挡住。
const ROOM_W: int = 27
const ROOM_H: int = 19
## 可走的地板范围（含端点）
const FLOOR_MIN := Vector2i(1, 3)
const FLOOR_MAX := Vector2i(25, 17)
## 门开在底部墙的这两列
const DOOR_COLUMNS: Array[int] = [12, 13]
## 底部墙再往下补几排：让相机能滚过墙底，
## 站在门口时门不会被底部工具栏盖住（多出来的部分是实心墙，不是空地）。
const EXTRA_WALL_ROWS: int = 3

const SRC_FLOOR := 0
const SRC_WALLPAPER := 1
const SRC_WOOD := 2
const SRC_TRIM := 3
const TILE := Vector2i(0, 0)

## 家具：[贴图路径, 脚底中心, 碰撞尺寸]；碰撞尺寸为 Vector2.ZERO 表示能踩过去（地毯、椅子）。
## 床靠左墙、壁炉靠上墙、衣柜靠右墙，中间留出从门口到床边的走道。
const FURNITURE: Array = [
	# —— 卧室（左上）——
	["objects/furniture/square_rug.png", Vector2(96, 200), Vector2.ZERO],
	["objects/furniture/single_bed.png", Vector2(56, 96), Vector2(30, 28)],
	["objects/furniture/bedside_table.png", Vector2(88, 96), Vector2(26, 16)],
	["objects/furniture/wardrobe.png", Vector2(392, 96), Vector2(28, 20)],
	["objects/furniture/potted_fern.png", Vector2(40, 176), Vector2.ZERO],
	["objects/furniture/armchair.png", Vector2(112, 232), Vector2(28, 16)],
	["objects/furniture/oval_rug.png", Vector2(112, 248), Vector2.ZERO],
	# —— 起居（中上）：壁炉 + 书柜 + 摇椅 ——
	["objects/furniture/brick_fireplace.png", Vector2(256, 72), Vector2(30, 22)],
	["objects/furniture/bookcase.png", Vector2(352, 72), Vector2(28, 20)],
	["objects/furniture/floor_lamp.png", Vector2(312, 84), Vector2.ZERO],
	["objects/furniture/rocking_chair.png", Vector2(150, 150), Vector2(24, 16)],
	["objects/furniture/wood_stool.png", Vector2(108, 150), Vector2.ZERO],
	["objects/furniture/coffee_table.png", Vector2(192, 168), Vector2(26, 16)],
	["objects/furniture/wall_clock.png", Vector2(330, 56), Vector2.ZERO],
	# —— 餐厅（中）——
	["objects/furniture/square_rug.png", Vector2(240, 206), Vector2.ZERO],
	["objects/furniture/dining_table.png", Vector2(240, 214), Vector2(26, 16)],
	["objects/furniture/oak_chair.png", Vector2(212, 212), Vector2.ZERO],
	["objects/furniture/oak_chair.png", Vector2(268, 212), Vector2.ZERO],
	# —— 厨房（右下）——
	["objects/furniture/refrigerator.png", Vector2(384, 236), Vector2(28, 22)],
	["objects/furniture/cupboard.png", Vector2(344, 214), Vector2(28, 20)],
	["objects/furniture/kitchen_table.png", Vector2(312, 252), Vector2(26, 16)],
	["objects/furniture/basket.png", Vector2(392, 268), Vector2.ZERO],
	# —— 门口 ——
	["objects/furniture/door_mat.png", Vector2(208, 272), Vector2.ZERO],
	# —— 储物（Chest 交互点见 _add_chest）——
	["objects/craftables/wood_chest.png", Vector2(152, 262), Vector2(28, 20)],
]


func _init() -> void:
	var root := _build()
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_SCENE)
	print("[build_house_interior] saved=%s err=%d" % [OUT_SCENE, err])
	root.free()
	quit(0 if err == OK else 1)


func _build() -> Node2D:
	var room := Node2D.new()
	room.name = "HouseInterior"
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
	_add_door(room)
	_add_sleep_spot(room)
	_add_chest(room)
	_add_spawn(room)
	return room


## 储物箱交互点：与农场木箱共用同一条 24 格仓库（见 chest_access.gd）。
func _add_chest(room: Node2D) -> void:
	var chest := Node2D.new()
	chest.name = "Chest"
	chest.set_script(load("res://scripts/world/chest_access.gd") as Script)
	# 木箱贴图在 (152, 262)，交互点落在箱子上
	chest.position = Vector2(152, 254)
	room.add_child(chest)
	chest.owner = room


## 床边睡觉点：站在床脚按 E 才睡；醒来落在旁边的 WakeSpot。
func _add_sleep_spot(room: Node2D) -> void:
	var spot := Node2D.new()
	spot.name = "BedSpot"
	spot.set_script(load("res://scripts/world/sleep_spot.gd") as Script)
	# 床在 (56, 96)，脚底往下 10px 就是床脚站位（半径 24，离开床头就睡不了）
	spot.position = Vector2(56, 106)
	room.add_child(spot)
	spot.owner = room

	var wake := Marker2D.new()
	wake.name = "WakeSpot"
	wake.position = Vector2(80, 114)
	room.add_child(wake)
	wake.owner = room


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
	# 顶墙：最上一行深色木墙，第二行壁纸，第三行当踢脚线
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, 0), SRC_WOOD, TILE)
		layer.set_cell(Vector2i(x, 1), SRC_WALLPAPER, TILE)
		layer.set_cell(Vector2i(x, 2), SRC_TRIM, TILE)
	# 左右墙
	for y in range(3, ROOM_H - 1):
		layer.set_cell(Vector2i(0, y), SRC_WOOD, TILE)
		layer.set_cell(Vector2i(ROOM_W - 1, y), SRC_WOOD, TILE)
	# 底墙，中间留出门洞
	for x in ROOM_W:
		if x in DOOR_COLUMNS:
			continue
		layer.set_cell(Vector2i(x, ROOM_H - 1), SRC_WOOD, TILE)
	# 门洞下方补实心墙（相机可以滚到这里，工具栏就不会挡住门）
	for y in range(ROOM_H, ROOM_H + EXTRA_WALL_ROWS):
		for x in ROOM_W:
			layer.set_cell(Vector2i(x, y), SRC_WOOD, TILE)


## 四面墙的碰撞：房间必须是个封闭盒子，玩家不能走进虚空。
## 底墙连门洞一起挡（门是"按 E 出去"，不是"走出去"），
## 否则玩家会直接从门洞走到房间外那几排装饰墙上。
func _add_wall_body(room: Node2D) -> void:
	var left: float = float(FLOOR_MIN.x) * 16.0
	var right: float = float(FLOOR_MAX.x + 1) * 16.0
	var top: float = float(FLOOR_MIN.y) * 16.0
	var bottom: float = float(FLOOR_MAX.y + 1) * 16.0
	var full_width: float = float(ROOM_W) * 16.0
	var door_row: float = float(ROOM_H - 1) * 16.0

	var walls: Array[Rect2] = [
		Rect2(0.0, 0.0, full_width, top),                       # 顶墙
		Rect2(0.0, top, left, bottom - top),                    # 左墙
		Rect2(right, top, full_width - right, bottom - top),     # 右墙
		Rect2(0.0, door_row, full_width, 16.0),                 # 底墙（含门洞）
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
			push_warning("[build_house_interior] 缺少贴图 %s" % path)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 32×32 的家具，脚底贴在 position 上
		sprite.offset = Vector2(0, -16)
		sprite.position = entry[1]
		props.add_child(sprite)
		sprite.owner = room

		var footprint: Vector2 = entry[2]
		if footprint != Vector2.ZERO:
			_add_blocker(sprite, footprint, room)


## 家具碰撞：从脚底往上长，挡住玩家穿过床、桌子、柜子。
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


## 门洞里放一张门贴图，玩家走上去按 E 出去。
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
	# 先挂进场景树，再设 owner：owner 必须是自己的祖先
	room.add_child(door)
	door.owner = room
	art.owner = room


## 进门后的落点：门内侧两格。
func _add_spawn(room: Node2D) -> void:
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = Vector2(
		(float(DOOR_COLUMNS[0]) + float(DOOR_COLUMNS.size()) * 0.5) * 16.0,
		float(ROOM_H - 3) * 16.0 + 8.0
	)
	room.add_child(spawn)
	spawn.owner = room
