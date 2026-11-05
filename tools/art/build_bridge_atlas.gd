extends SceneTree
## 木桥图集生成器（重画 river_bridge_atlas.png）
##
## 布局必须与 `farm_landscape._paint_bridges` 的取址保持一致：80×48，5 列 × 3 行。
##   列 0 / 1 / 2 = 横向桥的左端 / 中段 / 右端
##   列 3 / 4     = 纵向桥的左半 / 右半
##   行 0 = 上沿（栏杆横杆）  行 1 = 桥面中段  行 2 = 下沿（栏杆横杆）
##
## 旧图集的问题：纵向桥的中间段被画成一格一格的细竖条，铺出来像镂空护栏，
## 桥面本身没有连续的木板，远看就是一团条纹。
##
## 运行：
##   godot --headless --path . --script res://tools/art/build_bridge_atlas.gd

const OUT_PATH: String = "res://assets/textures/terrain/river_bridge_atlas.png"
const TILE: int = 16
const COLS: int = 5
const ROWS: int = 3

const DECK: Color = Color("a0744e")
const DECK_DARK: Color = Color("8b6242")
const DECK_LIGHT: Color = Color("b8905f")
const RAIL: Color = Color("6b4a30")
const RAIL_LIGHT: Color = Color("8a6544")
const STONE: Color = Color("8a8580")
const STONE_DARK: Color = Color("6f6a66")
const SHADOW: Color = Color("5c4a3a")


func _init() -> void:
	var atlas := Image.create(TILE * COLS, TILE * ROWS, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for row: int in ROWS:
		for col: int in COLS:
			var tile := _tile(col, row)
			atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(col * TILE, row * TILE))
	if atlas.save_png(OUT_PATH) == OK:
		print("[bridge] %s  %dx%d" % [OUT_PATH, atlas.get_width(), atlas.get_height()])
		quit(0)
	else:
		printerr("[bridge] 写入失败：%s" % OUT_PATH)
		quit(1)


## col/row 决定这一块是桥的哪一段。
func _tile(col: int, row: int) -> Image:
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var horizontal: bool = col <= 2
	# 横向桥：0 左端、1 中段、2 右端；纵向桥：3 左半、4 右半
	var is_start: bool = col == 0 or col == 3
	var is_end: bool = col == 2 or col == 4
	for y: int in TILE:
		for x: int in TILE:
			image.set_pixel(x, y, _pixel(x, y, row, horizontal, is_start, is_end))
	return image


func _pixel(x: int, y: int, row: int, horizontal: bool, is_start: bool, is_end: bool) -> Color:
	# —— 桥面本身：横向木板，每 4px 一条缝，缝上一行高光 ——
	var color: Color = DECK
	if y % 4 == 3:
		color = DECK_DARK
	elif y % 4 == 0:
		color = DECK_LIGHT

	# —— 栏杆：行 0 压在上沿，行 2 压在下沿；每 4px 一根立柱，别只留一条深色边 ——
	if row == 0:
		if y <= 1:
			color = RAIL
		elif y == 2:
			color = RAIL_LIGHT
		elif y <= 5 and x % 4 == 0:
			color = RAIL_LIGHT
	if row == 2:
		if y >= TILE - 1:
			color = RAIL
		elif y == TILE - 2:
			color = RAIL_LIGHT
		elif y >= TILE - 5 and x % 4 == 0:
			color = RAIL_LIGHT

	# —— 两端桥台：横向桥左右各一段石基，纵向桥上下各一截 ——
	if horizontal:
		if is_start and x <= 1:
			color = STONE if x == 0 else STONE_DARK
		if is_end and x >= TILE - 2:
			color = STONE if x == TILE - 1 else STONE_DARK
		# 桥沿外的一像素阴影，让桥面和岸土分开
		if row == 1 and y == TILE - 1:
			color = SHADOW
	else:
		# 纵向桥：外侧那一列是扶手，每 4px 一根横向立柱
		if is_start and x <= 1:
			color = RAIL if x == 0 else RAIL_LIGHT
			if y % 4 == 0 and x == 1:
				color = RAIL
		if is_end and x >= TILE - 2:
			color = RAIL if x == TILE - 1 else RAIL_LIGHT
			if y % 4 == 0 and x == TILE - 2:
				color = RAIL
		if not is_start and not is_end and (x <= 0 or x >= TILE - 1):
			color = DECK_DARK
	return color
