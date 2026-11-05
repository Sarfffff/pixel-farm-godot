extends SceneTree
## 生成杂货店室内：24×13 格的小店，柜台 + 货架 + 店主。
##
## 与农舍室内同一套做法（不切场景、放在远处由 HouseManager 显隐），
## 只是尺寸更小、家具不同。相机边界由根节点的 interior_room.gd 声明。
## 24 格宽是为了把相机最小缩放压到 1.67——18 格宽时缩放 2.2 倍，
## 一屏只看得见货架的一部分，店里像被裁掉了。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_shop_interior.gd

const OUT_SCENE := "res://scenes/world/shop_interior.tscn"
const TILESET := "res://assets/tilesets/house_terrain.tres"
const ART := "res://assets/packs/content_v1/"

const ROOM_W: int = 24
const ROOM_H: int = 13
const FLOOR_MIN := Vector2i(1, 4)
const FLOOR_MAX := Vector2i(22, 11)
## 门开在底部墙正中，正对柜台
const DOOR_COLUMNS: Array[int] = [11]
## 底部墙再多画几排，让相机能滚过墙底（同农舍）
const EXTRA_WALL_ROWS: int = 1
## 顶部墙面用掉的行数：0 横梁、1–2 壁纸、3 踢脚线，地板从第 4 行开始
const WALL_ROWS: int = 4

const SRC_FLOOR := 0
const SRC_WALLPAPER := 1
const SRC_WOOD := 2
const SRC_TRIM := 3
## 墙面三件套，与农舍室内共用（竖纹壁纸 / 竖木板 / 错缝砖）。
const SRC_PAPER := 4
const SRC_PLANKS := 5
const SRC_BRICK := 6
const TILE := Vector2i(0, 0)

## 家具缩放：素材 32×32、可见约 28px，玩家只有 16×20，1:1 会显得家具比人高。
const FURNITURE_SCALE: float = 0.75

## 家具：[贴图, 脚底中心, 碰撞尺寸]。
## 只用 objects/furniture 的 32×32 素材：terrain/interiors 是 16×16 的贴图零件，
## 混进来会变成"小木箱"，和玩家、NPC 的比例对不上。
##
## 店铺陈设规范（其他店铺照此办）：
##   1. 货架必须贴墙：脚底压在第一行地板的底边（y = FLOOR_MIN.y + 1 行），
##      不要放在店中央，否则像露天摆摊；
##   2. 柜台正对店门，店主站柜台北侧，顾客从南侧结账；
##   3. 柜台与门之间留出 ≥3 格空走道，不要摆家具；
##   4. 凳子、篮子、盆栽这类零散物件只放墙角，总数不超过 3 件；
##   5. 除酒馆外不摆餐桌/待客区，商店不需要座位。
const FURNITURE: Array = [
	# —— 柜台：正对店门的三段展示柜拼成一条长柜台 ——
	# 碰撞只挂在中间那段（96 宽覆盖整排），避免三个碰撞块互相重叠
	["objects/furniture/display_cabinet.png", Vector2(160, 120), Vector2.ZERO],
	["objects/furniture/display_cabinet.png", Vector2(184, 120), Vector2(96, 16)],
	["objects/furniture/display_cabinet.png", Vector2(208, 120), Vector2.ZERO],
	# —— 后墙货架：三段连成一排贴着后墙站，左右各一排，中间留给柜台 ——
	["objects/furniture/bookcase.png", Vector2(56, 80), Vector2(28, 18)],
	["objects/furniture/cupboard.png", Vector2(80, 80), Vector2(28, 18)],
	["objects/furniture/bookcase.png", Vector2(104, 80), Vector2(28, 18)],
	["objects/furniture/cupboard.png", Vector2(264, 80), Vector2(28, 18)],
	["objects/furniture/bookcase.png", Vector2(288, 80), Vector2(28, 18)],
	["objects/furniture/cupboard.png", Vector2(312, 80), Vector2(28, 18)],
	# —— 左右侧墙：各一个展示柜，贴墙摆放 ——
	["objects/furniture/cupboard.png", Vector2(32, 144), Vector2(28, 18)],
	["objects/furniture/display_cabinet.png", Vector2(352, 144), Vector2(30, 16)],
	# —— 柜台旁的待售货篮（唯一的地面杂项之一）——
	["objects/furniture/basket.png", Vector2(240, 136), Vector2(18, 10)],
	# —— 门口两角植物 ——
	["objects/furniture/potted_fern.png", Vector2(32, 184), Vector2(14, 10)],
	["objects/furniture/tall_potted_tree.png", Vector2(352, 184), Vector2(20, 12)],
]

## 平铺在地上的东西：单独一层、压在角色脚下，不参与 Y 排序。
## 商店只在门口放一块门垫，不铺地毯（地毯会让货道看起来像客厅）。
const FLOOR_PROPS: Array = [
	["objects/furniture/door_mat.png", Vector2(184, 176)],
]

## 墙面装饰：只挂柜台正后方，像价目牌/存货架，别整面墙铺满。
## 每项：[贴图路径, 位置, 缩放]；32×32 挂件用 0.75 缩放、脚底贴 y=64 的地面线。
const WALL_DECOR: Array = [
	# 两侧开窗：店内采光的窗户是店铺最容易读出来的特征
	["res://assets/packs/content_v1/terrain/interiors/window.png", Vector2(88, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/window.png", Vector2(280, 40), 1.0],
	# 柜台正后方：两块价目/存货板 + 挂钟
	["res://assets/packs/content_v1/terrain/interiors/shop_shelf.png", Vector2(152, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/shop_shelf.png", Vector2(216, 40), 1.0],
	["res://assets/packs/presentation_v3/furniture/wall_clock.png", Vector2(184, 56), FURNITURE_SCALE],
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
	room.set_script(load("res://scripts/world/interiors/interior_room.gd") as Script)
	room.set("camera_bounds", Rect2(0, 0, ROOM_W * 16, (ROOM_H + EXTRA_WALL_ROWS) * 16))

	var floor_layer := _make_layer("Floor", 0)
	var wall_layer := _make_layer("Walls", 1)
	# 地毯层：压在地砖之上、墙体与角色之下
	var floor_props := Node2D.new()
	floor_props.name = "FloorProps"
	floor_props.z_index = 2
	# 墙件（货架板、时钟）压在地板之上、家具之下
	var wall_decor := Node2D.new()
	wall_decor.name = "WallDecor"
	wall_decor.z_index = 3
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	props.z_index = 5

	room.add_child(floor_layer)
	room.add_child(wall_layer)
	room.add_child(floor_props)
	room.add_child(wall_decor)
	room.add_child(props)
	for child: Node in [floor_layer, wall_layer, floor_props, wall_decor, props]:
		child.owner = room

	_paint_floor(floor_layer)
	_paint_walls(wall_layer)
	_add_wall_body(room)
	_add_flat_props(floor_props, room)
	_add_wall_decor(wall_decor, room)
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
	# 与农舍同一套四段墙：砖梁 → 竖纹壁纸 ×2 → 木护墙板。
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, 0), SRC_BRICK, TILE)
		layer.set_cell(Vector2i(x, 1), SRC_PAPER, TILE)
		layer.set_cell(Vector2i(x, 2), SRC_PAPER, TILE)
		layer.set_cell(Vector2i(x, 3), SRC_PLANKS, TILE)
	for y in range(WALL_ROWS, ROOM_H - 1):
		layer.set_cell(Vector2i(0, y), SRC_PLANKS, TILE)
		layer.set_cell(Vector2i(ROOM_W - 1, y), SRC_PLANKS, TILE)
	# 底墙整行铺满（含门柱列）：门是贴在墙上的贴图，留空洞会露出黑底
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, ROOM_H - 1), SRC_PLANKS, TILE)
	for y in range(ROOM_H, ROOM_H + EXTRA_WALL_ROWS):
		for x in ROOM_W:
			layer.set_cell(Vector2i(x, y), SRC_PLANKS, TILE)


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


## 墙挂装饰：咖啡区货架板、时钟。只做视觉，不参与碰撞。
## 32×32 挂件按 0.75 缩放并向上提半张贴图，脚底贴 y=64 的地面线。
func _add_wall_decor(layer: Node2D, room: Node2D) -> void:
	for index: int in WALL_DECOR.size():
		var entry: Array = WALL_DECOR[index]
		var sprite := Sprite2D.new()
		var path: String = String(entry[0])
		sprite.name = "Decor%d%s" % [
			index, String(entry[0]).get_file().get_basename().to_pascal_case()
		]
		sprite.texture = load(path) as Texture2D
		if sprite.texture == null:
			push_warning("[build_shop_interior] 缺少墙件贴图 %s" % path)
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * float(entry[2])
		sprite.position = entry[1]
		if sprite.texture.get_height() > 16:
			sprite.offset = Vector2(0, -sprite.texture.get_height() * 0.5)
		layer.add_child(sprite)
		sprite.owner = room


## 店主站在柜台北侧（柜台贴图正好挡住他的脚，露出上半身）。
## 放进 Props 才能和柜台一起做 Y 排序。
func _add_keeper(props: Node2D, room: Node2D) -> void:
	var keeper := load("res://scenes/npcs/shopkeeper.tscn").instantiate() as Node2D
	keeper.name = "Shopkeeper"
	# 柜台脚底 y=120、柜台贴图占 98..120，店主站 96 正好只露上半身
	keeper.position = Vector2(184, 96)
	props.add_child(keeper)
	keeper.owner = room


func _add_door(room: Node2D) -> void:
	var door := Node2D.new()
	door.name = "ExitDoor"
	door.set_script(load("res://scripts/world/interiors/house_door.gd") as Script)
	door.set("mode", &"exit")
	door.position = Vector2(
		(float(DOOR_COLUMNS[0]) + float(DOOR_COLUMNS.size()) * 0.5) * 16.0,
		float(ROOM_H - 1) * 16.0 + 8.0
	)
	var art := Sprite2D.new()
	art.name = "Art"
	art.texture = load(ART + "terrain/interiors/door.png") as Texture2D
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 无偏移：门贴图正好盖住脚下那格墙砖；z 要压过墙体层（z=1）
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
