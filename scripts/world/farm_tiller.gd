extends Node2D
## 农场耕地系统（V0.4）：面前格高亮、工具动作表现、锄地、浇水、边界土屑过渡。
##
## 规则：
## 1. 每一格都是独立的完整方块瓦片（不拼九宫格，避免单格凸起变成"城垛"）；
## 2. 只能在**已有耕地的四邻**开垦，不能凭空在草地上挖；
## 3. 浇水只对已开垦且未浇水的格子有效；
## 4. 地块外沿会撒一圈半透明"土屑"，让耕地与草地的边界不那么生硬。
##
## 地块状态只存在内存里（`_soil_state`），V0.4 不做存档。
##
## 依赖场景结构（由 tools/build_farm_map.gd 生成）：
##   Farm/Soil        —— 耕地瓦片层
##   Farm/Watered     —— 已浇水覆盖层（同款瓦片 + 压暗 modulate）
##   Farm/SoilFringe  —— 边界土屑层（TileSet 在运行时生成）
##   Farm/Tiller      —— 本脚本，子节点 Cursor 为面前格高亮框

const TILE_SIZE := 16
const SOIL_SOURCE := 1
const FRINGE_SOURCE := 0
## 允许开垦的总范围（格坐标），覆盖初始 4 块苗圃并留出扩展余量
const TILLABLE := Rect2i(16, 5, 14, 10)
## 初始就已开垦的 4 块苗圃
const INITIAL_PLOTS: Array[Rect2i] = [
	Rect2i(18, 6, 4, 3),
	Rect2i(23, 6, 4, 3),
	Rect2i(18, 10, 4, 3),
	Rect2i(23, 10, 4, 3),
]

## 耕地铺地瓦片：纯色底 (1,1) 与带碎石细节的变体
const TILE_FILL := Vector2i(1, 1)
const FILL_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5),
	Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6),
]
const VARIANT_PERCENT := 50

## 土屑图集：x=0 底边密集，1 顶边密集，2 右边密集，3 左边密集
const FRINGE_BOTTOM := Vector2i(0, 0)
const FRINGE_TOP := Vector2i(1, 0)
const FRINGE_RIGHT := Vector2i(2, 0)
const FRINGE_LEFT := Vector2i(3, 0)
## 土屑格 -> 耕地邻居方向 -> 用哪块土屑（土屑靠向耕地那一侧更密）
const FRINGE_RULES: Array = [
	[Vector2i.UP, FRINGE_TOP],
	[Vector2i.DOWN, FRINGE_BOTTOM],
	[Vector2i.LEFT, FRINGE_LEFT],
	[Vector2i.RIGHT, FRINGE_RIGHT],
]
const NEIGHBOR_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
]

## 工具图标（与工具栏同一张图集）
const TOOLS_TEXTURE := "res://assets/game/characters/tools.png"
const TOOL_ICONS := {
	&"hoe": Rect2(0, 64, 16, 16),
	&"watering_can": Rect2(0, 0, 16, 16),
}

@onready var _soil: TileMapLayer = get_parent().get_node_or_null("Soil") as TileMapLayer
@onready var _watered: TileMapLayer = get_parent().get_node_or_null("Watered") as TileMapLayer
@onready var _fringe: TileMapLayer = get_parent().get_node_or_null("SoilFringe") as TileMapLayer
@onready var _cursor: Node2D = get_node_or_null("Cursor") as Node2D

var _player: Node2D
var _dust: CPUParticles2D
var _tools_texture: Texture2D
## 格坐标 -> 是否已浇水
var _soil_state: Dictionary = {}


func _ready() -> void:
	if _soil == null or _watered == null:
		push_error("[farm_tiller] 场景缺少 Soil / Watered 层，耕地系统已停用")
		set_physics_process(false)
		return
	if not _validate_tiles():
		set_physics_process(false)
		return

	_build_fringe_tileset()
	_setup_dust()

	for plot in INITIAL_PLOTS:
		for y in range(plot.position.y, plot.end.y):
			for x in range(plot.position.x, plot.end.x):
				_soil_state[Vector2i(x, y)] = false
	for cell: Vector2i in _soil_state.keys():
		_refresh_cell(cell)
	for cell: Vector2i in _soil_state.keys():
		_refresh_fringe_region(cell)

	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player == null:
		push_warning("[farm_tiller] 未找到 player 组节点，交互不会生效")
	else:
		if _player.has_signal(&"action_started"):
			_player.action_started.connect(_on_action_started)
		if _player.has_signal(&"use_requested"):
			_player.use_requested.connect(_on_use_requested)


func _physics_process(_delta: float) -> void:
	if _player == null or _cursor == null:
		return
	var cell := _target_cell()
	_cursor.visible = _can_use(cell)
	_cursor.position = Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5


func _target_cell() -> Vector2i:
	var base := Vector2i(
		floori(_player.global_position.x / TILE_SIZE),
		floori(_player.global_position.y / TILE_SIZE)
	)
	return base + _player.facing_vector()


func _current_tool() -> StringName:
	return _player.current_tool if _player != null else &""


func _can_use(cell: Vector2i) -> bool:
	match _current_tool():
		&"hoe":
			return _is_tillable(cell)
		&"watering_can":
			return _soil_state.has(cell) and not _soil_state[cell]
		_:
			return false


## 只能在已有耕地的四邻开垦：避免玩家在草地任意位置凭空挖地。
func _is_tillable(cell: Vector2i) -> bool:
	if not TILLABLE.has_point(cell):
		return false
	if _soil_state.has(cell):
		return false
	for direction in NEIGHBOR_DIRECTIONS:
		if _soil_state.has(cell + direction):
			return true
	return false


## 动作起手：在目标格播一次工具挥动表现。
func _on_action_started(tool: StringName) -> void:
	if _player == null or not TOOL_ICONS.has(tool):
		return
	if not _can_use(_target_cell()):
		return
	_play_tool_swing(_target_cell(), tool)


func _on_use_requested() -> void:
	if _player == null:
		return
	var cell := _target_cell()
	match _current_tool():
		&"hoe":
			if _is_tillable(cell):
				_soil_state[cell] = false
				_refresh_cell(cell)
				_refresh_fringe_region(cell)
				_emit_dust(cell, Color(0.78, 0.66, 0.5))
		&"watering_can":
			if _soil_state.has(cell) and not _soil_state[cell]:
				_soil_state[cell] = true
				_refresh_cell(cell)
				_emit_dust(cell, Color(0.6, 0.85, 0.95))


func _refresh_cell(cell: Vector2i) -> void:
	if not _soil_state.has(cell):
		_soil.erase_cell(cell)
		_watered.erase_cell(cell)
		return

	var tile := _fill_tile(cell)
	_soil.set_cell(cell, SOIL_SOURCE, tile)
	if _soil_state[cell]:
		_watered.set_cell(cell, SOIL_SOURCE, tile)
	else:
		_watered.erase_cell(cell)


## 按坐标哈希稳定地挑一个碎石变体，避免大片纯色又不随机闪烁。
func _fill_tile(cell: Vector2i) -> Vector2i:
	var hash_value: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	if posmod(hash_value, 100) < VARIANT_PERCENT:
		return FILL_VARIANTS[posmod(hash_value, FILL_VARIANTS.size())]
	return TILE_FILL


func _refresh_fringe_region(cell: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_refresh_fringe_cell(cell + Vector2i(dx, dy))


## 空地格：若四邻有耕地，就朝那个方向撒土屑；否则清掉。
func _refresh_fringe_cell(cell: Vector2i) -> void:
	if _fringe == null:
		return
	if _soil_state.has(cell):
		_fringe.erase_cell(cell)
		return
	for rule in FRINGE_RULES:
		var direction: Vector2i = rule[0]
		if _soil_state.has(cell + direction):
			_fringe.set_cell(cell, FRINGE_SOURCE, rule[1])
			return
	_fringe.erase_cell(cell)


## 运行时生成边界过渡图集：四张 16×16 的渐隐色带（贴耕地一侧最实，向外淡出）。
## 用色带而不是散点：散点在 4 倍缩放下会像草刺，色带才是"土壤过渡"的观感。
func _build_fringe_tileset() -> void:
	if _fringe == null:
		return
	var image := Image.create(TILE_SIZE * 4, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var dirt := Color(0.72, 0.60, 0.45)

	for index in 4:
		for y in TILE_SIZE:
			for x in TILE_SIZE:
				var distance: int = 0
				match index:
					0:
						distance = TILE_SIZE - 1 - y
					1:
						distance = y
					2:
						distance = TILE_SIZE - 1 - x
					_:
						distance = x
				if distance > 6:
					continue
				var falloff: float = 1.0 - float(distance) / 7.0
				var color := dirt
				color.a = 0.45 * pow(falloff, 1.7) * rng.randf_range(0.75, 1.0)
				image.set_pixel(index * TILE_SIZE + x, y, color)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for index in 4:
		source.create_tile(Vector2i(index, 0))

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tileset.add_source(source, FRINGE_SOURCE)
	_fringe.tile_set = tileset


func _setup_dust() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_dust = CPUParticles2D.new()
	_dust.name = "Dust"
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 8
	_dust.lifetime = 0.45
	_dust.explosiveness = 0.9
	_dust.direction = Vector2(0, -1)
	_dust.spread = 55.0
	_dust.initial_velocity_min = 18.0
	_dust.initial_velocity_max = 46.0
	_dust.gravity = Vector2(0, 110)
	_dust.scale_amount_min = 1.0
	_dust.scale_amount_max = 2.0
	_dust.texture = ImageTexture.create_from_image(image)
	_dust.z_index = 22
	add_child(_dust)


func _emit_dust(cell: Vector2i, color: Color) -> void:
	if _dust == null:
		return
	_dust.position = Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	_dust.color = color
	_dust.restart()


## 工具图标在目标格上方挥一下：起手抬起 → 落下 → 淡出。
func _play_tool_swing(cell: Vector2i, tool: StringName) -> void:
	if _tools_texture == null:
		_tools_texture = load(TOOLS_TEXTURE) as Texture2D
	if _tools_texture == null:
		return

	var atlas := AtlasTexture.new()
	atlas.atlas = _tools_texture
	atlas.region = TOOL_ICONS[tool]

	var swing := Sprite2D.new()
	swing.texture = atlas
	swing.z_index = 21
	swing.rotation_degrees = -40.0
	var origin := Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5 + Vector2(0, -12)
	swing.position = origin
	add_child(swing)

	var tween := create_tween()
	var arc := tween.tween_property(swing, "rotation_degrees", 35.0, 0.16)
	arc.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(swing, "position:y", origin.y + 7.0, 0.16)
	tween.tween_property(swing, "modulate:a", 0.0, 0.12)
	tween.tween_callback(swing.queue_free)


func _validate_tiles() -> bool:
	var source := _soil.tile_set.get_source(SOIL_SOURCE) as TileSetAtlasSource
	if source == null:
		push_error("[farm_tiller] TileSet 缺少耕地 source %d" % SOIL_SOURCE)
		return false
	var required: Array[Vector2i] = [TILE_FILL]
	required.append_array(FILL_VARIANTS)
	for coord in required:
		if not source.has_tile(coord):
			push_error("[farm_tiller] 耕地图集缺少瓦片 %s" % coord)
			return false
	return true
