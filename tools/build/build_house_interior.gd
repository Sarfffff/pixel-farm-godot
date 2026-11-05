extends SceneTree
## 生成农舍室内场景：一间 27×14 格的木屋内部（含顶部墙面刚好一屏）。
##
## 室内不切换场景，而是作为 Main 的子节点放在远处（HouseManager 负责显隐），
## 这样时间、背包、存档等 Systems 不会因为进出屋被重建。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_house_interior.gd

const OUT_SCENE := "res://scenes/world/house_interior.tscn"
const TILESET := "res://assets/tilesets/house_terrain.tres"
const ART := "res://assets/packs/content_v1/"
const PRESENTATION_ART := "res://assets/packs/presentation_v3/"

## 房屋尺寸（格）。27×15 + 1 排补墙 = 432×256：
## 相机最小缩放 = 640/432 ≈ 1.48，可视区域 432×243，整间屋连同顶部墙面一屏装完。
## 墙面留 4 排（64px）才看得出是"墙"——只留 1 排时整屏都是地板，像仓库。
const ROOM_W: int = 27
const ROOM_H: int = 15
## 可走的地板范围（含端点）
const FLOOR_MIN := Vector2i(1, 4)
const FLOOR_MAX := Vector2i(25, 13)
## 门开在底部墙的这列：门贴图 16×16 正好一格
const DOOR_COLUMNS: Array[int] = [13]
## 底部墙再往下补几排：让相机能滚过墙底，
## 站在门口时门不会被底部工具栏盖住（多出来的部分是实心墙，不是空地）。
const EXTRA_WALL_ROWS: int = 1
## 顶部墙面用掉的行数：0 横梁、1–2 壁纸、3 踢脚线，地板从第 4 行开始
const WALL_ROWS: int = 4

const SRC_FLOOR := 0
const SRC_WALLPAPER := 1
const SRC_WOOD := 2
const SRC_TRIM := 3
## 墙面三件套：竖纹壁纸 / 竖木板 / 错缝砖。
## 原先整面墙都用"上浅下深"的 wood_wall 平铺，每格重复同一条横带，看着像平铺的条纹。
const SRC_PAPER := 4
const SRC_PLANKS := 5
const SRC_BRICK := 6
const TILE := Vector2i(0, 0)

## 家具缩放：素材 32×32、可见内容约 28px，玩家只有 16×20。
## 1:1 摆放时椅子比人还高，0.75 后约 21px，比例才正常。
const FURNITURE_SCALE: float = 0.75

## 家具：[贴图路径, 脚底中心, 碰撞尺寸]；碰撞尺寸为 Vector2.ZERO 表示不挡路。
## 五段式平面：卧室（左）→ 起居（中左）→ 餐厅（中右）→ 厨房（右）→ 储物（下方）。
## 大件一律贴墙背朝外，中间留一条从门口直通床边的走道；
## 家具之间保持 8px 以上间隔，避免碰撞块重叠。
const FURNITURE: Array = [
	# —— 北墙一排（背靠墙，脚底离地约 2 格）——
	["objects/furniture/wardrobe.png", Vector2(44, 96), Vector2(28, 20)],
	["objects/furniture/brick_fireplace.png", Vector2(136, 96), Vector2(30, 22)],
	["objects/furniture/bookcase.png", Vector2(176, 96), Vector2(28, 20)],
	["objects/furniture/floor_lamp.png", Vector2(208, 88), Vector2(10, 6)],
	["objects/furniture/cupboard.png", Vector2(352, 96), Vector2(28, 20)],
	["objects/furniture/refrigerator.png", Vector2(392, 96), Vector2(28, 22)],
	# —— 卧室（左侧，床与床头柜一组）——
	["objects/furniture/single_bed.png", Vector2(52, 140), Vector2(30, 28)],
	["objects/furniture/bedside_table.png", Vector2(84, 140), Vector2(26, 16)],
	["objects/furniture/potted_fern.png", Vector2(28, 168), Vector2(14, 10)],
	# —— 起居（中左，茶几 + 摇椅 + 扶手椅围成小圈）——
	["objects/furniture/coffee_table.png", Vector2(152, 156), Vector2(26, 16)],
	["objects/furniture/rocking_chair.png", Vector2(120, 168), Vector2(24, 16)],
	["objects/furniture/armchair.png", Vector2(184, 168), Vector2(28, 16)],
	["objects/furniture/wood_stool.png", Vector2(152, 190), Vector2(18, 10)],
	["objects/furniture/potted_fern.png", Vector2(216, 120), Vector2(14, 10)],
	# —— 餐厅（中右，两把椅子夹一张餐桌）——
	["objects/furniture/dining_table.png", Vector2(280, 156), Vector2(26, 16)],
	["objects/furniture/oak_chair.png", Vector2(256, 160), Vector2(16, 10)],
	["objects/furniture/oak_chair.png", Vector2(304, 160), Vector2(16, 10)],
	# —— 厨房（右侧，灶台区靠东墙）——
	["objects/furniture/kitchen_table.png", Vector2(368, 176), Vector2(26, 16)],
	["objects/furniture/basket.png", Vector2(336, 192), Vector2(18, 10)],
	["objects/furniture/tall_potted_tree.png", Vector2(398, 192), Vector2(20, 12)],
	# —— 储物与边角 ——
	["objects/craftables/wood_chest.png", Vector2(96, 200), Vector2(28, 20)],
	["objects/furniture/tall_potted_tree.png", Vector2(32, 208), Vector2(20, 12)],
]

## 平铺在地上：单独一层、压在角色脚下，不参与 Y 排序，
## 否则站在毯子北侧时会被毯子盖住脚。
## 地毯只摆在"家具下方"，别单独扔在空地中央，否则像一块绿色色块。
const FLOOR_PROPS: Array = [
	["objects/furniture/square_rug.png", Vector2(152, 156)],
	["objects/furniture/oval_rug.png", Vector2(280, 156)],
	["objects/furniture/square_rug.png", Vector2(52, 148)],
	["objects/furniture/door_mat.png", Vector2(216, 208)],
]

## 墙面装饰：挂在壁纸那一行（y=16..48），只做视觉、不参与碰撞。
## 不进 Props 有两个原因：Props 有"家具必须 32×32 且脚底落在地板内"的体检规则，
## 而墙件是 16×16 且本来就在地板之上。
## 每项：[贴图相对路径, 中心/脚底位置, 缩放]；32×32 挂件用 0.75 缩放并向上提 16px。
const WALL_DECOR: Array = [
	# 窗：第 2 排壁纸（y=32..48），左右各挂两扇，旁边配窗帘
	["res://assets/packs/content_v1/terrain/interiors/window.png", Vector2(88, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/window.png", Vector2(104, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/curtain.png", Vector2(72, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/curtain.png", Vector2(120, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/window.png", Vector2(312, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/window.png", Vector2(328, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/curtain.png", Vector2(296, 40), 1.0],
	["res://assets/packs/content_v1/terrain/interiors/curtain.png", Vector2(344, 40), 1.0],
	# 挂件：时钟与搁板挂在壁纸下沿（脚底贴 y=64 的地面线）
	["res://assets/packs/presentation_v3/furniture/wall_clock.png", Vector2(176, 64), FURNITURE_SCALE],
	["res://assets/packs/presentation_v3/furniture/wall_shelf.png", Vector2(240, 64), FURNITURE_SCALE],
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
	room.set_script(load("res://scripts/world/interiors/interior_room.gd") as Script)
	room.set("camera_bounds", Rect2(0, 0, ROOM_W * 16, (ROOM_H + EXTRA_WALL_ROWS) * 16))

	var floor_layer := _make_layer("Floor", 0)
	var wall_layer := _make_layer("Walls", 1)
	# 地毯层：压在地砖之上、墙体与角色之下
	var floor_props := Node2D.new()
	floor_props.name = "FloorProps"
	floor_props.z_index = 2
	# 墙件（窗、窗帘）压在地板之上、家具之下，站在墙根时不会盖住角色
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
	_add_door(room)
	_add_sleep_spot(room)
	_add_chest(room)
	_add_spawn(room)
	return room


## 储物箱交互点：与农场木箱共用同一条 24 格仓库（见 chest_access.gd）。
func _add_chest(room: Node2D) -> void:
	var chest := Node2D.new()
	chest.name = "Chest"
	chest.set_script(load("res://scripts/world/interiors/chest_access.gd") as Script)
	# 木箱贴图在 (96, 200)，交互点落在箱子上
	chest.position = Vector2(96, 192)
	room.add_child(chest)
	chest.owner = room


## 床边睡觉点：站在床脚按 E 才睡；醒来落在旁边的 WakeSpot。
func _add_sleep_spot(room: Node2D) -> void:
	var spot := Node2D.new()
	spot.name = "BedSpot"
	spot.set_script(load("res://scripts/world/interiors/sleep_spot.gd") as Script)
	# 床在 (52, 140)，脚底往下 10px 就是床脚站位（半径 24，离开床头就睡不了）
	spot.position = Vector2(52, 150)
	room.add_child(spot)
	spot.owner = room

	var wake := Marker2D.new()
	wake.name = "WakeSpot"
	wake.position = Vector2(76, 158)
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
	# 顶墙四段：砖横梁 → 竖纹壁纸 ×2 → 木护墙板。
	# 三种材质各管一段，横向不再整片重复同一条色带。
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, 0), SRC_BRICK, TILE)
		layer.set_cell(Vector2i(x, 1), SRC_PAPER, TILE)
		layer.set_cell(Vector2i(x, 2), SRC_PAPER, TILE)
		layer.set_cell(Vector2i(x, 3), SRC_PLANKS, TILE)
	# 左右墙用竖木板：纹理朝上走，和正墙的横带区分开。
	for y in range(WALL_ROWS, ROOM_H - 1):
		layer.set_cell(Vector2i(0, y), SRC_PLANKS, TILE)
		layer.set_cell(Vector2i(ROOM_W - 1, y), SRC_PLANKS, TILE)
	# 底墙整行铺满（含门柱列）：门是贴在墙上的贴图，
	# 留空洞会露出引擎黑底，显得门悬在黑洞里。
	for x in ROOM_W:
		layer.set_cell(Vector2i(x, ROOM_H - 1), SRC_PLANKS, TILE)
	# 门洞下方补实心墙（相机可以滚到这里，工具栏就不会挡住门）
	for y in range(ROOM_H, ROOM_H + EXTRA_WALL_ROWS):
		for x in ROOM_W:
			layer.set_cell(Vector2i(x, y), SRC_PLANKS, TILE)


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


## 地毯 / 地垫：固定 z 值，不参与 Y 排序，永远压在角色脚下。
func _art_path(original: String) -> String:
	if original == "objects/craftables/wood_chest.png":
		return PRESENTATION_ART + "objects/chest_closed.png"
	if original.begins_with("objects/furniture/"):
		var name: String = original.get_file()
		if name == "door_mat.png": name = "oval_rug.png"
		return PRESENTATION_ART + "furniture/" + name
	return ART + original


func _add_flat_props(layer: Node2D, room: Node2D) -> void:
	for entry: Array in FLOOR_PROPS:
		var sprite := Sprite2D.new()
		var path: String = _art_path(String(entry[0]))
		sprite.name = String(entry[0]).get_file().get_basename().to_pascal_case()
		sprite.texture = load(path) as Texture2D
		if sprite.texture == null:
			push_warning("[build_house_interior] 缺少贴图 %s" % path)
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 平铺物以中心对齐格子，不做脚底锚点
		sprite.offset = Vector2.ZERO
		sprite.scale = Vector2.ONE * FURNITURE_SCALE
		sprite.position = entry[1]
		layer.add_child(sprite)
		sprite.owner = room


## 墙件：窗和窗帘按 16×16 原尺寸贴到壁纸那一行（y=24 即第 2 行）。
## 不做缩放——墙件要跟 16px 地砖严格对齐，缩放会出现半像素缝。
## 32×32 的挂件（钟、搁板）仍按 0.75 缩放，脚底贴 (x, 48) 即地面线。
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
			push_warning("[build_house_interior] 缺少墙件贴图 %s" % path)
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var decor_scale: float = float(entry[2])
		sprite.scale = Vector2.ONE * decor_scale
		sprite.position = entry[1]
		# 32×32 的挂件以脚底为锚点，向上长
		if sprite.texture.get_height() > 16:
			sprite.offset = Vector2(0, -sprite.texture.get_height() * 0.5)
		layer.add_child(sprite)
		sprite.owner = room


func _add_furniture(props: Node2D, room: Node2D) -> void:
	for entry: Array in FURNITURE:
		var sprite := Sprite2D.new()
		var path: String = _art_path(String(entry[0]))
		sprite.name = String(entry[0]).get_file().get_basename().to_pascal_case()
		sprite.texture = load(path) as Texture2D
		if sprite.texture == null:
			push_warning("[build_house_interior] 缺少贴图 %s" % path)
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 32×32 的家具，脚底贴在 position 上；offset 跟着 scale 一起缩，锚点不变
		sprite.offset = Vector2(0, -16)
		sprite.scale = Vector2.ONE * FURNITURE_SCALE
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
