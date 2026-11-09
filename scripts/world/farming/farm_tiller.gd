extends Node2D
## 面前格交互。可用性、预览和命中共用同一套判定；动画起手后锁定目标。

signal action_completed(tool: StringName, cell: Vector2i)

const FarmSnapshotCodec := preload("res://scripts/persistence/farm_snapshot_codec.gd")
const SoilAutotile := preload("res://scripts/world/farming/soil_autotile.gd")
const ToolEffect := preload("res://scripts/presentation/tool_effect.gd")
const MiningInteraction: Script = preload("res://scripts/world/resources/mining_interaction.gd")
const CropScene := preload("res://scenes/world/crop.tscn")
const CROP_DIR: String = "res://data/crops"
const TILE_SIZE: int = 16
## 每种操作的体力开销；收获单独算一档。
const STAMINA_COST := {
	&"hoe": 4,
	&"watering_can": 2,
	&"seeds": 2,
	&"axe": 8,
	&"stone_pickaxe": 6,
	&"harvest": 2,
}
## 工具 -> 操作音效（音效由 `tools/build/build_sfx.gd` 离线合成）。
const SFX_FOR_TOOL := {
	&"hoe": &"hoe",
	&"watering_can": &"water",
	&"seeds": &"plant",
	&"axe": &"chop",
	&"stone_pickaxe": &"mine",
	&"harvest": &"harvest",
}
## 种植区允许独立开新田；建筑、水体、树干等障碍不允许开垦。
const TILLABLE := Rect2i(16, 5, 14, 10)
## 道具贴图判定内缩量，避免贴图边缘刚好压在格线上时把相邻格也算成遮挡。
const PROP_INSET: float = 2.0
## 格内判定框：比整格收 1px，避免相邻格的分界处来回摆动。
const CELL_INSET: float = 1.0
const INITIAL_PLOTS: Array[Rect2i] = [
	Rect2i(18, 6, 4, 3), Rect2i(23, 6, 4, 3),
	Rect2i(18, 10, 4, 3), Rect2i(23, 10, 4, 3),
]

@onready var _soil: TileMapLayer = get_parent().get_node("Soil") as TileMapLayer
@onready var _watered: TileMapLayer = get_parent().get_node("Watered") as TileMapLayer
@onready var _fringe: TileMapLayer = get_parent().get_node("SoilFringe") as TileMapLayer
@onready var _detail: TileMapLayer = get_parent().get_node("Detail") as TileMapLayer
## 既有场地：路/桥/坡地/水面已经铺过的格子不再用来开垦。
@onready var _paths: TileMapLayer = get_parent().get_node("Paths") as TileMapLayer
@onready var _bridges: TileMapLayer = get_parent().get_node("Bridges") as TileMapLayer
@onready var _hills: TileMapLayer = get_parent().get_node("Hills") as TileMapLayer
@onready var _water_layer: TileMapLayer = get_parent().get_node("Water") as TileMapLayer
## 道具容器（y 排序）：树的树冠、建筑屋檐都画在这里。
@onready var _world: Node2D = get_parent().get_node("World") as Node2D
@onready var _cursor: Node2D = $Cursor
@onready var _cursor_border: Line2D = $Cursor/Border
@onready var _cursor_fill: Polygon2D = $Cursor/Fill

var _player: CharacterBody2D
## 格坐标 -> 是否已浇水
var _soil_state: Dictionary = {}
## 格坐标 -> 该格上的作物
var _crops: Dictionary[Vector2i, Crop] = {}
## 作物 id -> 配置，运行期扫描 res://data/crops
var _crop_definitions: Dictionary[StringName, CropData] = {}
var _locked_cell: Vector2i
var _locked_tree: Sprite2D
## 玩家用 Q/E 手选的种子；空表示跟着背包顺序走。
var _selected_seed: StringName = &""
var _query_shape: RectangleShape2D
var _show_area: bool = false
var _water_previews: Array[Line2D] = []
## 收获提交和所有同步通知共享一把锁，不能在观察者中换格再次收获。
var _harvest_busy: bool = false
var _harvest_cell: Vector2i
## action_completed 的兼容查询回执，不是作物状态，也不编码到快照。
var _harvest_result: Dictionary = {}
## 技能端口（可选）：只读能力查询与成功劳动凭据；未注入时保持原价、不记经验。
var _labor: Node


## 由组合根注入；本节点不查找技能系统，也不自行发放经验。
func configure_labor(port: Node) -> void:
	_labor = port


func _ready() -> void:
	add_to_group(&"farm_tiller")
	_soil.tile_set = SoilAutotile.make_tileset()
	_watered.tile_set = _soil.tile_set
	_fringe.clear()
	_query_shape = RectangleShape2D.new()
	_query_shape.size = Vector2(14, 14)
	for plot in INITIAL_PLOTS:
		for y in range(plot.position.y, plot.end.y):
			for x in range(plot.position.x, plot.end.x):
				_soil_state[Vector2i(x, y)] = false
	for cell: Vector2i in _soil_state:
		_refresh_cell(cell)
	_load_crop_definitions()
	for index in 2:
		var border := Line2D.new()
		border.points = PackedVector2Array([Vector2(-7, -7), Vector2(7, -7), Vector2(7, 7), Vector2(-7, 7), Vector2(-7, -7)])
		border.width = 1.0
		border.default_color = Color("b8e1dc")
		border.hide()
		add_child(border)
		_water_previews.append(border)
	_player = _world.get_node_or_null("Player") as CharacterBody2D
	if _player != null:
		_player.interaction = self


func _physics_process(_delta: float) -> void:
	if _player == null:
		_cursor.hide()
		return
	var tool: StringName = _player.current_tool
	var show_area: bool = tool == &"hoe" and not _player.input_locked
	if _show_area != show_area:
		_show_area = show_area
		queue_redraw()
	var cell: Vector2i = _locked_cell if _player.is_acting else resolve_target(tool)
	_cursor.visible = not _player.input_locked
	_cursor.global_position = _soil.to_global(_soil.map_to_local(cell))
	var valid: bool = _player.is_acting or can_use(tool, cell)
	var color := Color("e8e5b5") if valid else Color("b98070")
	if tool == &"watering_can" and valid:
		color = Color("b8e1dc")
	_cursor_border.default_color = color
	_cursor_fill.color = Color(color, 0.10 if valid else 0.05)
	var cells: Array[Vector2i] = []
	if tool == &"watering_can":
		cells = watering_cells(cell)
	for index in _water_previews.size():
		var border: Line2D = _water_previews[index]
		border.visible = not _player.input_locked and cells.size() == 3
		if border.visible:
			border.global_position = _soil.to_global(_soil.map_to_local(cells[index + 1]))


func _draw() -> void:
	if not _show_area or _soil == null:
		return
	var start: Vector2 = _soil.map_to_local(TILLABLE.position) - Vector2(8, 8)
	var end: Vector2 = start + Vector2(TILLABLE.size * TILE_SIZE)
	var points: Array[Vector2] = [start, Vector2(end.x, start.y), end, Vector2(start.x, end.y)]
	for index in 4:
		draw_dashed_line(points[index], points[(index + 1) % 4], Color(0.94, 0.89, 0.64, 0.22), 1.0, 3.0)


func interaction_hint(tool: StringName) -> String:
	if _player == null:
		return ""
	if _player.is_acting:
		match tool:
			&"hoe": return "正在开垦…"
			&"watering_can": return "正在浇水…"
			&"axe": return "正在砍伐…"
			&"stone_pickaxe": return "正在挥镐碎石…"
	var faced_crop: Crop = _crops.get(target_cell()) as Crop
	if faced_crop != null and faced_crop.withered:
		return "%s 已枯萎 · 按 F 免费清理" % faced_crop.data.display_name
	if not _has_stamina(tool):
		return "体力不够 · 按 F 回屋睡觉"
	var cell: Vector2i = resolve_target(tool)
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if tool == &"watering_can" and upgrades != null and upgrades.watering_level > 0 and can_use(tool, cell):
		return "铜水壶 · 一次浇三格 · 空格 / 左键 · 体力 3"
	if tool == &"stone_pickaxe":
		return MiningInteraction.hint(get_tree(), _soil.to_global(_soil.map_to_local(cell)))
	# 作物状态以面前一格为准：身边还有别的可开垦格时，不该把脚下这株的提示抢走。
	var crop: Crop = _crops.get(target_cell()) as Crop
	if crop == null:
		crop = _crops.get(cell) as Crop
	if crop != null:
		var crop_name: String = crop.data.display_name if crop.data != null else "作物"
		if crop.withered:
			return "%s 已枯萎 · 按 F 免费清理" % crop_name
		if crop.is_mature():
			return "%s 已成熟 · 按 F 收获" % crop_name
		if crop.data.regrow_days > 0 or not crop.data.stage_days.is_empty():
			return "%s · %s还需 %d 晚 · %s" % [crop_name, "复收" if crop.regrowing else "成熟", crop.watered_nights_remaining(), "今天已浇水" if crop.watered else "切换水壶浇水"]
		if tool == &"watering_can":
			if crop.watered:
				return "今天已经浇过水 · 明天再浇"
			return "给%s浇水 · 空格 / 左键" % crop_name
		return "%s 正在生长 · 切换水壶浇水" % crop_name
	return _tool_hint(tool, cell)


func _tool_hint(tool: StringName, cell: Vector2i) -> String:
	match tool:
		&"hoe":
			if not TILLABLE.has_point(cell):
				return "种植区外 · 请在虚线范围内开垦"
			if _soil_state.has(cell):
				return "已经开垦 · 切种子袋播种"
			match _block_reason(cell):
				&"ground":
					return "地面已铺小路或桥面 · 换一格开垦"
				&"prop":
					return "上方有树冠或杂物遮挡 · 换一格开垦"
				&"body":
					return "地面有障碍 · 避开建筑、石头与树桩"
			return "可以开垦 · 空格 / 左键"
		&"watering_can":
			if not _soil_state.has(cell):
				return "这里还未开垦 · 先使用锄头"
			return "这片地还没有作物 · 先播种再浇水"
		&"seeds":
			if not _soil_state.has(cell):
				return "先用锄头开垦这一格"
			if _seed_id() == &"":
				return "背包里没有种子 · 按 B 打开背包"
			var seed_crop := _seed_crop()
			if seed_crop != null and not seed_crop.grows_in(_current_season()):
				return "%s 只在 %s 种，现在是%s季" % [
					seed_crop.display_name, seed_crop.seasons_text(), _season_name(),
				]
			return "播种 %s · 空格 / 左键" % _seed_label()
		&"axe":
			var tree: Sprite2D = _axe_target(cell)
			if tree != null and not tree.blocked_reason().is_empty():
				return tree.blocked_reason()
			if _tree_at(cell) != null:
				return "可以砍树 · 空格 / 左键"
			if _stump_at(cell) != null:
				return "可以清除树桩 · 空格 / 左键"
			return "面向树干或树桩使用"
	return ""


func target_cell() -> Vector2i:
	return base_cell() + _player.facing_vector()


## 脚底所在格（向上 1px，避免站在格线时朝上和朝下出现相差一格的错觉）。
func base_cell() -> Vector2i:
	return _soil.local_to_map(_soil.to_local(_player.global_position - Vector2(0, 1)))


## 工具真正作用的格子：面前一格可用就用它，否则在身边一圈里挑最顺手的一格。
##
## 只对锄地和水壶生效——播种必须站在目标格前，避免把种子撒错格。
func resolve_target(tool: StringName) -> Vector2i:
	var front: Vector2i = target_cell()
	if not _area_tool(tool) or _can_use_for(tool, front):
		return front
	var base: Vector2i = base_cell()
	for offset: Vector2i in _neighbor_order():
		var candidate: Vector2i = base + offset
		if _can_use_for(tool, candidate):
			return candidate
	return front


func _area_tool(tool: StringName) -> bool:
	return tool == &"hoe" or tool == &"watering_can" or tool == &"interact"


## 身边（面前优先，其次一圈）有没有成熟作物可收：玩家用 E 时先问这个。
func has_harvest_target() -> bool:
	if _player == null:
		return false
	return _can_use_for(&"interact", resolve_target(&"interact"))


## 选目标用的可用性判定：interact（收获）不是工具栏动作，需要单独看成熟作物。
func _can_use_for(tool: StringName, cell: Vector2i) -> bool:
	if tool == &"interact":
		return can_interact(cell)
	return can_use(tool, cell)


## 面前 → 斜前 → 左右 → 斜后 → 身后：越顺手的越先选。
func _neighbor_order() -> Array[Vector2i]:
	var facing: Vector2i = _player.facing_vector()
	var side_a := Vector2i(facing.y, -facing.x)
	var side_b := Vector2i(-facing.y, facing.x)
	return [
		facing,
		facing + side_a,
		facing + side_b,
		side_a,
		side_b,
		facing - side_a,
		facing - side_b,
		-facing,
	]


func can_use(tool: StringName, cell: Vector2i) -> bool:
	if not _has_stamina(tool):
		return false
	match tool:
		&"hoe":
			return _is_tillable(cell)
		&"watering_can":
			for target: Vector2i in watering_cells(cell):
				var crop: Crop = _crops.get(target) as Crop
				if crop != null and not crop.withered and not crop.watered and not crop.is_mature():
					return true
			return false
		&"seeds":
			return _can_plant(cell)
		&"axe":
			var tree: Sprite2D = _axe_target(cell)
			return tree != null and tree.can_chop()
		&"stone_pickaxe":
			var rock: Sprite2D = MiningInteraction.rock_at(get_tree(), _soil.to_global(_soil.map_to_local(cell)))
			return rock != null and rock.can_mine()
		_:
			return false


func _is_tillable(cell: Vector2i) -> bool:
	if not TILLABLE.has_point(cell) or _soil_state.has(cell) or _crops.has(cell):
		return false
	return not _is_blocked(cell)


func _is_blocked(cell: Vector2i) -> bool:
	return _block_reason(cell) != &""


## 不可开垦的三类原因，顺序即提示优先级：
## ground=该格已铺路面/桥面/水面，prop=道具贴图盖住了这一格，body=物理障碍。
func _block_reason(cell: Vector2i) -> StringName:
	for patch: Node2D in get_tree().get_nodes_in_group(&"forage_patch"):
		if _soil.local_to_map(_soil.to_local(patch.global_position)) == cell:
			return &"prop"
	if _has_ground_overlay(cell):
		return &"ground"
	if _has_prop_overlay(cell):
		return &"prop"
	if _has_body(cell):
		return &"body"
	return &""


## 路面、桥面、坡地与水面都是既有场地，不允许在上面翻地。
func _has_ground_overlay(cell: Vector2i) -> bool:
	for layer: TileMapLayer in [_paths, _bridges, _hills, _water_layer]:
		if layer != null and layer.get_cell_source_id(cell) != -1:
			return true
	return false


## 树冠、屋檐等画在上方的像素压住该格时也不允许开垦，
## 否则能在树底下凭空多出一块田，看起来像穿模。
func _has_prop_overlay(cell: Vector2i) -> bool:
	if _world == null:
		return false
	var cell_rect: Rect2 = Rect2(
		_soil.to_global(_soil.map_to_local(cell)) - Vector2(8.0 - CELL_INSET, 8.0 - CELL_INSET),
		Vector2(TILE_SIZE - CELL_INSET * 2.0, TILE_SIZE - CELL_INSET * 2.0)
	)
	for child: Node in _world.get_children():
		var sprite := child as Sprite2D
		# 作物生长在耕地上方，不属于阻挡开垦的道具。
		if sprite == null or sprite is Crop or sprite.get_meta(&"felled", false):
			continue
		# 会走动的角色（NPC），站过来一会儿就会走开，不该把这块地永久锁死。
		# 双重判断：组名 + 交互接口，任一命中就跳过，改脚本或改名都不会漏。
		if sprite.is_in_group(&"world_actor") or sprite.has_method(&"player_in_range"):
			continue
		if _sprite_rect(sprite).intersects(cell_rect):
			return true
	return false


## 道具贴图的全局矩形（考虑 offset、region 与变换），四周内缩避免贴边误判。
func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var rect: Rect2 = preload("res://scripts/presentation/visible_sprite_bounds.gd").local_rect(sprite)
	if rect.size.x > PROP_INSET * 2.0 and rect.size.y > PROP_INSET * 2.0:
		rect = rect.grow(-PROP_INSET)
	var top_left: Vector2 = sprite.to_global(rect.position)
	var bottom_right: Vector2 = sprite.to_global(rect.end)
	return Rect2(top_left, bottom_right - top_left).abs()


## 建筑、石头、树干与树桩靠真实碰撞体拦截。
func _has_body(cell: Vector2i) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = Transform2D(0.0, _soil.to_global(_soil.map_to_local(cell)))
	query.collision_mask = 1
	query.collide_with_areas = false
	if _player != null:
		query.exclude = [_player.get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## 目标格上的树干（还没倒下的树）。
func _tree_at(cell: Vector2i) -> Sprite2D:
	return _choppable_at(cell, false)


## 目标格上的树桩（已倒下、还没连根清掉）。
func _stump_at(cell: Vector2i) -> Sprite2D:
	return _choppable_at(cell, true)


## 斧头目标：优先砍树干，没有树干时退到清树桩。
func _axe_target(cell: Vector2i) -> Sprite2D:
	var trunk: Sprite2D = _choppable_at(cell, false)
	return trunk if trunk != null else _choppable_at(cell, true)


func _choppable_at(cell: Vector2i, want_stump: bool) -> Sprite2D:
	# 树根落在格线时，接受接触该目标格的树干，避免一侧永远无法命中。
	var center: Vector2 = _soil.to_global(_soil.map_to_local(cell))
	var nearest: Sprite2D
	var nearest_distance: float = INF
	for candidate: Node in get_tree().get_nodes_in_group(&"choppable"):
		var tree := candidate as Sprite2D
		if tree == null or tree.is_felled != want_stump or tree.get_meta(&"cleared", false):
			continue
		var trunk: Vector2 = tree.global_position - Vector2(0, 3)
		var difference: Vector2 = (trunk - center).abs()
		var distance: float = trunk.distance_squared_to(center)
		if difference.x <= 12 and difference.y <= 12 and distance < nearest_distance:
			nearest = tree
			nearest_distance = distance
	return nearest


func _on_action_started(tool: StringName, cell: Vector2i) -> void:
	begin_tool_action(tool, cell)


func begin_tool_action(tool: StringName, cell: Vector2i) -> void:
	_locked_cell = cell
	_locked_tree = _axe_target(cell) if tool == &"axe" else null
	if tool == &"stone_pickaxe":
		_locked_tree = MiningInteraction.rock_at(get_tree(), _soil.to_global(_soil.map_to_local(cell)))


func _on_use_requested(tool: StringName, cell: Vector2i) -> void:
	commit_tool_action(tool, cell)


func commit_tool_action(tool: StringName, cell: Vector2i) -> void:
	if _harvest_busy or not can_use(tool, cell):
		return
	# 命中前背包或目标可能变化，再校验锁定的实际目标，不为失败砍伐扣体力。
	if tool == &"axe" and (not is_instance_valid(_locked_tree) or not _locked_tree.can_chop()):
		return
	if not _spend_stamina(tool):
		return
	match tool:
		&"hoe":
			if _is_tillable(cell):
				_soil_state[cell] = false
				_detail.erase_cell(cell)
				_refresh_region(cell)
				_spawn_effect(cell, tool)
				action_completed.emit(tool, cell)
		&"watering_can":
			for target: Vector2i in watering_cells(cell):
				_water_crop(target)
		&"seeds":
			_plant(cell)
		&"axe":
			# 树干和树桩都走同一个命中入口：树桩由 chop() 内部转成清桩逻辑。
			if is_instance_valid(_locked_tree) and not _locked_tree.get_meta(&"cleared", false):
				var was_felled: bool = _locked_tree.is_felled
				var hits_before: int = int(_locked_tree.hits_remaining)
				var stump_before: int = int(_locked_tree.stump_hits_remaining)
				if _locked_tree.chop(_player.facing_vector()):
					_report_wood_labor(_locked_tree, was_felled, hits_before, stump_before)
					_spawn_effect(cell, tool)
		&"stone_pickaxe":
			if is_instance_valid(_locked_tree) and _locked_tree.mine(_player.facing_vector()):
				_spawn_effect(cell, tool)
	# 真动手了才出声，和命中帧同步；音高轻微抖动，连续操作不机械。
	_play_action_sfx(tool)


func _refresh_region(cell: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_refresh_cell(cell + Vector2i(dx, dy))


func _refresh_cell(cell: Vector2i) -> void:
	if not _soil_state.has(cell):
		return
	var mask: int = SoilAutotile.mask_for(cell, _soil_state)
	var tile := Vector2i(mask % 16, mask / 16)
	_soil.set_cell(cell, 0, tile)
	if _soil_state[cell]:
		_watered.set_cell(cell, 0, tile)
	else:
		_watered.erase_cell(cell)


func _spawn_effect(cell: Vector2i, tool: StringName) -> void:
	var effect := ToolEffect.new()
	effect.kind = tool
	effect.direction = Vector2(_player.facing_vector())
	effect.position = _soil.to_global(_soil.map_to_local(cell))
	effect.z_index = 21
	get_tree().current_scene.add_child(effect)


## 交互键能否接管这一格：只有成熟作物才算，其余情况让按键回落给工具切换。
func can_interact(cell: Vector2i) -> bool:
	var crop: Crop = _crops.get(cell) as Crop
	return crop != null and (crop.withered or (crop.is_mature() and _has_stamina(&"harvest")))


## 交互键（F）收获：核心状态同帧完整提交后才同步通知观察者。
func interact(cell: Vector2i) -> void:
	if _harvest_busy: return
	_harvest_busy = true
	_commit_crop_interaction(cell)
	_harvest_result.clear()
	_harvest_busy = false


func _commit_crop_interaction(cell: Vector2i) -> void:
	if not can_interact(cell):
		return
	var crop: Crop = _crops[cell] as Crop
	if crop.withered:
		_crops.erase(cell)
		crop.queue_free()
		_soil_state[cell] = false
		_refresh_cell(cell)
		_show_toast("已清理枯株 · 耕地保留，可播种当季种子")
		return
	var inventory := _inventory()
	var item_id: StringName = crop.harvest_item_id()
	var amount: int = crop.harvest_amount()
	if inventory == null or item_id == &"" or amount <= 0 or not inventory.has_space_for(item_id, amount):
		_show_toast("背包已满 · 腾出空间再收获")
		return
	var stamina: Node = _stamina()
	inventory.begin_update()
	if stamina != null: stamina.begin_update()
	if not _spend_stamina(&"harvest"):
		inventory.end_update()
		if stamina != null: stamina.end_update()
		return
	# 预检后没有 await 或外部通知；批量提交期间容量不会被观察者抢占。
	var remaining: int = inventory.add_item(item_id, amount)
	assert(remaining == 0, "harvest capacity must remain valid through synchronous commit")
	if not crop.regrow_after_harvest():
		_crops.erase(cell)
		crop.play_harvest()
		# 收完回到干燥的空耕地，可以直接补种。
		_soil_state[cell] = false
		_refresh_cell(cell)
		_spawn_effect(cell, &"seeds")
		_play_action_sfx(&"harvest")
	_harvest_cell = cell
	_harvest_result = {&"id": String(item_id), &"count": amount}
	inventory.end_update()
	if stamina != null: stamina.end_update()
	# 物品、体力与作物状态都已提交后才上报劳动；满包和枯株在上方已返回。
	if is_instance_valid(_labor):
		_labor.record(&"harvest", "harvest:%d:%d:%d" % [int(_labor.today()), cell.x, cell.y])
	action_completed.emit(&"harvest", cell)


## 新的一天：浇过水的作物统一长一阶，然后清掉浇水标记、土变干。
## 雨天等于替玩家把所有作物都浇了，地也保持湿润。
func begin_new_day() -> void:
	var rainy := _weather_rainy()
	finish_day(rainy)
	begin_day(rainy)


## 结算结束的那一天，只使用当天的雨水、洒水器覆盖与劳动记录。
## sprinkled 是设备当夜实际覆盖的格子；与手浇/雨水一样只作用于未成熟作物。
func finish_day(rainy: bool, sprinkled: Array[Vector2i] = []) -> void:
	var grown: int = 0
	var sprinkled_count: int = 0
	for cell: Vector2i in _crops:
		var crop: Crop = _crops[cell]
		if not crop.is_mature():
			if rainy:
				crop.water()
			elif sprinkled.has(cell) and crop.water():
				sprinkled_count += 1
		if crop.grow_if_watered():
			grown += 1
	_show_toast(_day_summary_text(rainy, grown, sprinkled_count))


## 新日天气只影响新一天的浇水状态，不能补长前一晚的作物。
func begin_day(rainy: bool) -> void:
	for crop: Crop in _crops.values():
		crop.begin_day()
		crop.apply_season(_current_season())
		if rainy:
			crop.water()
	for cell: Vector2i in _soil_state:
		_soil_state[cell] = rainy
		_refresh_cell(cell)


func seed_purchase_hint(id: StringName) -> String:
	for crop: CropData in _crop_definitions.values():
		if crop.seed_item == id and not crop.grows_in(_current_season()):
			return "%s适合%s播种；当前是%s，先购买当季种子" % [crop.display_name, crop.seasons_text(), _season_name()]
	return ""


## 对外提供事实查询，不让订单、引导和预告依赖内部字典或 Sprite 节点。
func crop_definitions() -> Array[CropData]:
	var result: Array[CropData] = []
	result.assign(_crop_definitions.values())
	return result


func harvest_info(cell: Vector2i) -> Dictionary:
	if _harvest_busy and cell == _harvest_cell and not _harvest_result.is_empty():
		return _harvest_result.duplicate()
	var crop: Crop = _crops.get(cell)
	return {&"id": String(crop.harvest_item_id()), &"count": crop.harvest_amount()} if crop != null else {}


func has_watered_crop(cell: Vector2i) -> bool:
	return _crops.has(cell) and bool(_soil_state.get(cell, false))


func has_tilled_soil(cell: Vector2i) -> bool:
	return _soil_state.has(cell)


func tomorrow_harvest_count() -> int:
	var ready: int = 0
	for crop: Crop in _crops.values():
		if crop.is_mature() or not crop.watered:
			continue
		var needed: int = crop.data.regrow_days if crop.regrowing else crop.data.days_at_stage(crop.stage)
		if (crop.regrowing or crop.stage == crop.data.last_stage() - 1) and crop.stage_age + 1 >= needed:
			ready += 1
	return ready


func _day_summary_text(rainy: bool, grown: int, sprinkled: int = 0) -> String:
	if rainy and grown > 0:
		return "下雨了 · %d 株作物喝饱水长大一阶" % grown
	if rainy:
		return "下雨了 · 今天不用浇水"
	if grown > 0 and sprinkled > 0:
		return "新的一天 · 洒水器浇了 %d 株，共 %d 株长大一阶" % [sprinkled, grown]
	if grown > 0:
		return "新的一天 · %d 株作物长大了一阶" % grown
	return "新的一天 · 记得给作物浇水"


func _weather_rainy() -> bool:
	var weather := get_tree().get_first_node_in_group(&"weather")
	return weather != null and weather.has_method(&"is_rainy") and bool(weather.is_rainy())


func _show_toast(text: String) -> void:
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.show_message(text)


## 工具 -> 音效名；收获单独传 &"harvest"。
func _play_action_sfx(tool: StringName) -> void:
	var sfx: StringName = SFX_FOR_TOOL.get(tool, &"")
	if sfx == &"":
		return
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method(&"play_sfx"):
		audio.call(&"play_sfx", sfx, randf_range(0.94, 1.06))


## 体力：每次实际动手都要花，扣不动就挡住这次操作。
func _stamina() -> Node:
	return get_tree().get_first_node_in_group(&"stamina")


func _has_stamina(tool: StringName) -> bool:
	var stamina := _stamina()
	if stamina == null:
		return true
	return bool(stamina.can_spend(tool_cost(tool)))


func _spend_stamina(tool: StringName) -> bool:
	var stamina := _stamina()
	if stamina == null:
		return true
	if stamina.spend(tool_cost(tool)):
		return true
	_show_toast("体力不够了 · 回屋睡一觉")
	return false


## 倒树/清桩是完整劳动：只在目标状态已提交后上报，凭据按目标唯一状态生成。
func _report_wood_labor(tree: Sprite2D, was_felled: bool, hits_before: int, stump_before: int) -> void:
	if not is_instance_valid(_labor) or not is_instance_valid(tree):
		return
	var identity: String = String(tree.persistence_id())
	if not was_felled and tree.is_felled:
		_labor.record(&"chop_tree", "chop:%s:%d" % [identity, hits_before])
	elif was_felled and stump_before > 0 and bool(tree.get_meta(&"cleared", false)):
		_labor.record(&"clear_stump", "stump:%s" % identity)


func _can_plant(cell: Vector2i) -> bool:
	if not _soil_state.has(cell) or _crops.has(cell):
		return false
	var crop_data := _seed_crop()
	if crop_data == null:
		return false
	# 错季不能种：作物数据里写明了生长季节，留空表示四季皆可
	return crop_data.grows_in(_current_season())


## 当前季节；没有时间系统时按春天处理，保证单独测试耕地也能跑。
func _current_season() -> StringName:
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_method(&"season"):
		return StringName(time.call(&"season"))
	return &"spring"


func _season_name() -> String:
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_method(&"season_name"):
		return String(time.call(&"season_name"))
	return "春"


func _plant(cell: Vector2i) -> void:
	if not _can_plant(cell):
		return
	var crop_data: CropData = _seed_crop()
	if crop_data == null:
		return
	var inventory := _inventory()
	if inventory == null or not inventory.remove_item(crop_data.seed_item, 1):
		return
	_spawn_crop(cell, crop_data, 0, false)
	_soil_state[cell] = false
	_refresh_cell(cell)
	_spawn_effect(cell, &"seeds")
	action_completed.emit(&"seeds", cell)


## 在指定格生成一株作物；播种与读档共用。
func _spawn_crop(cell: Vector2i, crop_data: CropData, stage: int, watered: bool) -> Crop:
	var crop := CropScene.instantiate() as Crop
	crop.setup(crop_data)
	crop.stage = clampi(stage, 0, crop_data.last_stage())
	crop.watered = watered
	crop.apply_stage()
	# 落在格子底边中心：作物贴图 32×32 向上展开，配合 World 的 y_sort 排序。
	crop.position = _soil.to_global(_soil.map_to_local(cell)) + Vector2(0, TILE_SIZE * 0.5)
	_world.add_child(crop)
	_crops[cell] = crop
	return crop


func _water_crop(cell: Vector2i) -> void:
	var crop: Crop = _crops.get(cell) as Crop
	if crop == null or not crop.water():
		return
	_soil_state[cell] = true
	_refresh_cell(cell)
	_spawn_effect(cell, &"watering_can")
	action_completed.emit(&"watering_can", cell)
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.show_message("浇过水 · 睡一觉就长一阶")


## 铜水壶围绕目标格，沿朝向的垂直方向覆盖三格，只消耗一次体力。
func watering_cells(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [cell]
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades != null and upgrades.watering_level > 0 and _player != null:
		var facing: Vector2i = _player.facing_vector()
		var side := Vector2i(facing.y, -facing.x)
		for distance in range(1, int(upgrades.WATERING.width) / 2 + 1):
			result.append(cell + side * distance)
			result.append(cell - side * distance)
	return result


## 预检、实扣与提示共用这一处价格：先取工具升级后的基准，再叠加技能减免。
func tool_cost(tool: StringName) -> int:
	var base: int = int(STAMINA_COST.get(tool, 0))
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if tool == &"watering_can" and upgrades != null and upgrades.watering_level > 0:
		base = int(upgrades.WATERING.stamina_cost)
	if is_instance_valid(_labor):
		return int(_labor.stamina_cost(tool, base))
	return base


## 种子袋槽位没有子选择，直接取背包里第一种种子（按格子顺序）。
## 背包里所有还有库存的种子，按背包顺序。
func _seed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var inventory := _inventory()
	if inventory == null:
		return ids
	for index in inventory.slot_count():
		var slot: Dictionary = inventory.item_at(index)
		if slot.is_empty():
			continue
		var definition: ItemData = inventory.definition(slot[&"id"])
		if definition != null and definition.category == &"seed":
			if not ids.has(definition.id):
				ids.append(definition.id)
	return ids


## 当前要播的种子：优先玩家手选的那种，卖光了就退回背包里的第一种。
func _seed_id() -> StringName:
	var inventory := _inventory()
	if inventory != null:
		var active: StringName = inventory.active_item()
		var item: ItemData = inventory.definition(active)
		if item != null and item.category == &"seed":
			return active if inventory.count_of(active) > 0 else &""
	var ids := _seed_ids()
	if ids.is_empty():
		return &""
	if _selected_seed != &"" and ids.has(_selected_seed):
		return _selected_seed
	return ids[0]


## 拿着种子袋时按 Q/E 调用：在几种种子之间轮换并提示。
func cycle_seed(direction: int) -> void:
	var ids := _seed_ids()
	if ids.is_empty():
		return
	if ids.size() > 1:
		var current := _seed_id()
		var index := ids.find(current)
		_selected_seed = ids[posmod((index if index >= 0 else 0) + direction, ids.size())]
	else:
		_selected_seed = ids[0]
	var inventory := _inventory()
	var active: ItemData = inventory.definition(inventory.active_item())
	if active != null and active.category == &"seed":
		inventory.assign_hotbar(inventory.active_slot, _selected_seed)
	var definition: ItemData = _inventory().definition(_selected_seed)
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message") and definition != null:
		toast.show_message("种子：%s" % definition.display_name)


func _seed_label() -> String:
	var inventory := _inventory()
	if inventory == null:
		return "种子"
	var definition: ItemData = inventory.definition(_seed_id())
	return definition.display_name if definition != null else "种子"


func _seed_crop() -> CropData:
	var seed_id: StringName = _seed_id()
	if seed_id == &"":
		return null
	for crop_data: CropData in _crop_definitions.values():
		if crop_data.seed_item == seed_id:
			return crop_data
	return null


func _inventory() -> Inventory:
	return get_tree().get_first_node_in_group(&"inventory") as Inventory


## 存盘用：已开垦的格、浇过水的格、每株作物的阶段。
func to_dict() -> Dictionary:
	var crops: Array[Dictionary] = []
	for cell: Vector2i in _crops:
		var record: Dictionary = _crops[cell].to_dict()
		record[&"x"] = cell.x
		record[&"y"] = cell.y
		crops.append(record)
	var snapshot: Dictionary = FarmSnapshotCodec.encode(_soil_state, crops)
	# 保留 v1 对外接口；正式 v2 存档由 world_objects 独立保存树石。
	snapshot[&"rocks"] = _world.get_meta(&"rock_states", {}).duplicate()
	return snapshot


func from_dict(data: Dictionary) -> void:
	if data.get("rocks") is Dictionary:
		MiningInteraction.restore(_world, data.rocks)
	var decoded: Dictionary = FarmSnapshotCodec.decode(data, TILLABLE, _crop_definitions)
	for crop: Crop in _crops.values():
		crop.queue_free()
	_crops.clear()
	_soil_state = decoded.soil
	_soil.clear()
	_watered.clear()
	_fringe.clear()
	for record: Dictionary in decoded.crops:
		var cell := Vector2i(int(record.x), int(record.y))
		var crop: Crop = _spawn_crop(cell, _crop_definitions[StringName(record.id)], 0, false)
		crop.restore_growth(record)
		crop.apply_season(_current_season())
	for cell: Vector2i in _soil_state:
		_refresh_cell(cell)


func _load_crop_definitions() -> void:
	# 通过资源层枚举，避免导出后只看到 .tres.remap 文件。
	for file: String in ResourceLoader.list_directory(CROP_DIR):
		if not file.ends_with(".tres"):
			continue
		var crop_data := load(CROP_DIR.path_join(file)) as CropData
		if crop_data == null or crop_data.id == &"" or crop_data.stages.is_empty():
			push_warning("[farm_tiller] 跳过无效作物文件 %s" % file)
			continue
		_crop_definitions[crop_data.id] = crop_data
