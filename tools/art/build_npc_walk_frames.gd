extends SceneTree
## 给 NPC 合成走路帧：源图只有四方向待机姿势，没有走路循环。
##
## 帧结构（3 帧 × 4 方向，行 = 方向）：
##   帧 0 待机（原图）
##   帧 1 / 帧 2 迈步：**身体完全不上下移动**，只动脚，否则看起来像在跳
##
## 正面（下）/ 背面（上）：两条腿以身体中线为界做剪刀式开合，
##   帧 1 两脚分开、帧 2 两脚并拢，读起来是"迈步"。
## 侧面（左/右）：只有一条腿可见，整块脚掌前后摆 1px，像跨步。
##
## 输出 96×128（3 列 × 4 行），与 Sprite2D 的 hframes=3 / vframes=4 对齐。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/art/build_npc_walk_frames.gd

const INPUT_DIR := "res://assets/textures/characters/npcs_v1/"
const IDS: Array[String] = ["shopkeeper", "gardener", "carpenter", "fisherman"]
## 脚掌起点行：贴图脚底在 y=24，y >= 22 才是分开的两只脚
const FEET_TOP: int = 22
const FRAME: int = 32
const COLUMNS: int = 3
const ROWS: int = 4
## 方向行：与 npc.gd 的 FRAME_DOWN / UP / LEFT / RIGHT 一致
const DOWN: int = 0
const UP: int = 1
const SIDE_VIEWS: Array[int] = [2, 3]

var _errors: int = 0


func _init() -> void:
	for id: String in IDS:
		_build_one(id)
	print("[npc_walk] %d characters, %d errors" % [IDS.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _build_one(id: String) -> void:
	var path: String = INPUT_DIR + id + "_directions.png"
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if source == null:
		_errors += 1
		push_error("[npc_walk] 缺少 %s" % path)
		return
	if source.get_size() != Vector2i(FRAME * ROWS, FRAME):
		_errors += 1
		push_error("[npc_walk] %s 尺寸异常：%s" % [path, source.get_size()])
		return

	var sheet := Image.create(FRAME * COLUMNS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for direction: int in ROWS:
		var idle: Image = source.get_region(Rect2i(direction * FRAME, 0, FRAME, FRAME))
		idle.convert(Image.FORMAT_RGBA8)
		_blit(sheet, idle, Vector2i(0, direction * FRAME))
		_blit(sheet, _make_step(idle, direction, 1), Vector2i(FRAME, direction * FRAME))
		_blit(sheet, _make_step(idle, direction, -1), Vector2i(FRAME * 2, direction * FRAME))

	var out_path: String = INPUT_DIR + id + "_walk.png"
	if sheet.save_png(ProjectSettings.globalize_path(out_path)) != OK:
		_errors += 1
		push_error("[npc_walk] 无法写入 %s" % out_path)
	else:
		print("[npc_walk] %s -> %s" % [id, out_path])


## 生成一帧迈步：phase = 1 迈出一侧，-1 迈回另一侧；只改脚的位置，身体不动。
func _make_step(base: Image, direction: int, phase: int) -> Image:
	var out := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	out.fill(Color.TRANSPARENT)
	var center_x: int = _center_x(base)
	for y: int in FRAME:
		for x: int in FRAME:
			var color: Color = base.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var offset_x: int = 0
			if y >= FEET_TOP:
				if direction in SIDE_VIEWS:
					# 侧视只有一条腿：整体前后摆
					offset_x = phase
				else:
					# 正视/背视：两腿以中线为界相对开合
					offset_x = -phase if x < center_x else phase
			var target := Vector2i(x + offset_x, y)
			if target.x < 0 or target.x >= FRAME:
				continue
			out.set_pixel(target.x, target.y, color)
	return out


## 角色在 32×32 画格里的水平中心，用来把两条腿分到左右两侧。
func _center_x(image: Image) -> int:
	var used: Rect2i = image.get_used_rect()
	return used.position.x + used.size.x / 2


func _blit(sheet: Image, frame: Image, at: Vector2i) -> void:
	sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(FRAME, FRAME)), at)
