extends Node
## 区域引擎适配：保留Main和核心系统，只搬迁同一个玩家；采集和保存由独立端口提供。

signal region_changed(id: StringName)
const Factory = preload("res://scripts/regions/region_factory.gd")
const Ledger = preload("res://scripts/regions/resource_ledger.gd")
const Harvest = preload("res://scripts/regions/harvest_service.gd")
const Interaction = preload("res://scripts/regions/region_interaction.gd")
const Portal = preload("res://scripts/regions/region_portal.gd")
const Layout = preload("res://scripts/world/maps/region_layout.gd")
const RULES: Resource = preload("res://data/maps/resource_rules.tres")
const ROUTES: Resource = preload("res://data/maps/region_routes.tres")
var active_region: StringName = &"home"
var ledger := Ledger.new()
var harvest := Harvest.new()
var stamina: Node
var player: CharacterBody2D
var _host: Node2D
var _farm: Node2D
var _field: Node
var _house: Node
var _camera: Camera2D
var _clock: Node
var _inventory: Inventory
var _interaction: Node
var _roots: Dictionary = {}
var _profiles: Dictionary = {}
var _sprites: Dictionary = {}
var _loot_nodes: Dictionary = {}
var _home_return: Vector2 = Vector2(580, 176)
var _busy: bool = false
var _name_label: Label


func _ready() -> void:
	add_to_group(&"world_regions")


func configure(host: Node2D, actor: CharacterBody2D, farm: Node2D, field: Node, house: Node, camera: Camera2D, clock: Node, bag: Inventory, energy: Node) -> void:
	_host = host
	player = actor
	_farm = farm
	_field = field
	_house = house
	_camera = camera
	_clock = clock
	_inventory = bag
	stamina = energy
	ledger.rules = RULES.rules
	ledger.last_day = int(clock.day)
	harvest.ledger = ledger
	harvest.inventory = bag
	harvest.spend_stamina = energy.spend
	harvest.current_day = func() -> int: return int(_clock.day)
	harvest.rejected.connect(_message)
	harvest.acted.connect(_harvest_feedback)
	_interaction = Interaction.new()
	_interaction.name = "RegionInteraction"
	_interaction.manager = self
	_interaction.player = actor
	add_child(_interaction)
	# 原农场继续使用原工具实现，但跨区后的信号必须只交给当前区域。
	player.action_started.disconnect(field._on_action_started)
	player.use_requested.disconnect(field._on_use_requested)
	player.action_started.connect(_action_started)
	player.use_requested.connect(_use_requested)
	_roots["home"] = farm
	for index: int in Layout.REGION_IDS.size():
		var id: String = Layout.REGION_IDS[index]
		var root: Node2D = Factory.instantiate_region(StringName(id))
		root.name = "Region_" + id
		root.position = Vector2(3000 + index * 1000, 0)
		root.visible = false
		root.process_mode = Node.PROCESS_MODE_DISABLED
		_host.add_child(root)
		_roots[id] = root
		_profiles[id] = load("res://data/maps/" + id + ".tres")
		ledger.seed_region(StringName(id), Factory.entries(root))
		_sprites[id] = {}
		for node: Node in root.get_node("World").get_children():
			if node.has_meta(&"stable_id"): _sprites[id][String(node.get_meta(&"stable_id"))] = node
		var loot := Node2D.new()
		loot.name = "GroundDrops"
		loot.y_sort_enabled = true
		root.get_node("World").add_child(loot)
		_loot_nodes[id] = loot
	ledger.changed.connect(_refresh_region)
	for region: String in ROUTES.connections:
		for route: Array in ROUTES.connections[region]:
			var sign := Portal.new()
			sign.name = "Route_" + String(route[1])
			sign.target = StringName(route[1])
			sign.arrival = StringName(route[2])
			sign.destination_name = region_name(StringName(route[1]))
			sign.position = Vector2(600, 176) if region == "home" else _gate_position(region, StringName(route[0]))
			sign.requested.connect(request_travel)
			_roots[region].get_node("World").add_child(sign)
	_name_label = Label.new()
	_name_label.name = "RegionName"
	_name_label.position = Vector2(175, 5)
	_name_label.add_theme_font_size_override("font_size", 8)
	_name_label.add_theme_color_override("font_color", Color("f0dfb5"))
	_name_label.add_theme_color_override("font_outline_color", Color("514c40"))
	_name_label.add_theme_constant_override("outline_size", 2)
	_host.get_node("UI").add_child(_name_label)
	_update_name()


func region_name(id: StringName) -> String:
	if id == &"home": return "农舍农场"
	if id == &"farm": return "农场荒地"
	var profile: Resource = _profiles.get(String(id))
	return profile.display_name if profile != null else String(id)


func region_origin() -> Vector2:
	return (_roots[String(active_region)] as Node2D).global_position


func request_travel(target: StringName, arrival: StringName) -> void:
	if _busy or player.input_locked or player.is_acting or _house.is_inside() or not _roots.has(String(target)): return
	_busy = true
	player.set_input_locked(true)
	var fade: Node = _host.get_node_or_null("ScreenFade")
	if fade != null: await fade.fade_out(0.18)
	travel_to(target, arrival)
	if fade != null: await fade.fade_in(0.22)
	player.set_input_locked(false)
	_busy = false


func travel_to(target: StringName, arrival: StringName = &"west") -> bool:
	if not _roots.has(String(target)) or _house.is_inside(): return false
	if active_region == &"home" and target != &"home": _home_return = player.global_position
	var point: Vector2 = _home_return if target == &"home" else _gate_position(String(target), arrival) + _inward(arrival) * 24.0
	_switch_to(target, point)
	return true


func recover_home() -> void:
	if active_region == &"home": return
	var door := _host.get_node("Farm/World/CottageDoor") as Node2D
	_switch_to(&"home", door.global_position + Vector2(0, 16))


func _switch_to(target: StringName, local_position: Vector2) -> void:
	player.cancel_action()
	_interaction.clear_lock()
	for id: String in _roots:
		_roots[id].visible = id == String(target)
		_roots[id].process_mode = Node.PROCESS_MODE_INHERIT if id == String(target) else Node.PROCESS_MODE_DISABLED
	active_region = target
	var root := _roots[String(target)] as Node2D
	player.reparent(root.get_node("World"), false)
	player.global_position = local_position if target == &"home" else root.global_position + local_position
	player.visible = true
	player.interaction = _field if target == &"home" else _interaction
	_camera.global_position = player.global_position
	_camera.set_world_bounds(Rect2(Vector2.ZERO, Vector2(640, 480)) if target == &"home" else Rect2(root.global_position, Vector2(_profiles[String(target)].map_size * 16)))
	_camera.reset_smoothing()
	_update_name()
	region_changed.emit(target)


func home_save_position() -> Vector2:
	return _house.save_position() if active_region == &"home" else _home_return


func begin_day(day: int) -> void:
	ledger.begin_day(day, _can_regrow)


func _can_regrow(region: StringName, id: String) -> bool:
	if region != active_region: return true
	var node: Sprite2D = _sprites[String(region)].get(id)
	return node != null and player.global_position.distance_to(node.global_position) > 36.0


func resource_at(cell: Vector2i) -> String:
	if active_region == &"home": return ""
	for id: String in _sprites[String(active_region)]:
		var state: Dictionary = ledger.object(active_region, id)
		if state.is_empty() or int(state.hits) <= 0: continue
		var node: Sprite2D = _sprites[String(active_region)][id]
		var definition: Resource = node.get_meta(&"resource_definition")
		var start := Vector2i(int(state.cell[0]), int(state.cell[1]))
		if Rect2i(start, definition.footprint).has_point(cell) and player.global_position.distance_to(node.global_position) <= 48.0: return id
	return ""


func nearby_drop() -> String:
	if active_region == &"home": return ""
	var closest: String = ""
	var distance: float = 27.0
	for id: String in ledger.regions[String(active_region)].drops:
		var drop: Dictionary = ledger.regions[String(active_region)].drops[id]
		var point: Vector2 = region_origin() + Vector2(int(drop.cell[0]) * 16 + 8, int(drop.cell[1]) * 16 + 14)
		var delta: float = player.global_position.distance_to(point)
		if delta < distance:
			distance = delta
			closest = id
	return closest


func _refresh_region(region: StringName) -> void:
	var key: String = String(region)
	if not _sprites.has(key): return
	for id: String in _sprites[key]:
		var node := _sprites[key][id] as Sprite2D
		var alive: bool = int(ledger.object(region, id).hits) > 0
		node.visible = alive
		var body: Node = node.get_node_or_null("FootCollision")
		if body != null:
			for shape: Node in body.get_children(): shape.set_deferred("disabled", not alive)
	var layer: Node2D = _loot_nodes[key]
	for child: Node in layer.get_children():
		layer.remove_child(child)
		child.queue_free()
	for id: String in ledger.regions[key].drops:
		var drop: Dictionary = ledger.regions[key].drops[id]
		var definition: ItemData = _inventory.definition(StringName(drop.item))
		if definition == null: continue
		var sprite := Sprite2D.new()
		sprite.name = "Drop"
		sprite.texture = definition.icon
		sprite.scale = Vector2.ONE * (16.0 / maxf(definition.icon.get_width(), definition.icon.get_height()))
		sprite.position = Vector2(int(drop.cell[0]) * 16 + 8, int(drop.cell[1]) * 16 + 14)
		sprite.offset = Vector2(0, -definition.icon.get_height() / 2.0)
		sprite.set_meta(&"drop_id", id)
		layer.add_child(sprite)


func _action_started(tool: StringName, cell: Vector2i) -> void:
	if active_region == &"home": _field._on_action_started(tool, cell)
	else: _interaction.lock_target(tool, cell)


func _use_requested(tool: StringName, cell: Vector2i) -> void:
	if active_region == &"home": _field._on_use_requested(tool, cell)
	else: _interaction.commit(tool, cell)


func _harvest_feedback(region: StringName, id: String, finished: bool) -> void:
	var state: Dictionary = ledger.object(region, id)
	var tool: String = String(ledger.rules[state.kind].tool)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null: audio.play_sfx(&"chop" if tool == "axe" else (&"mine" if tool == "stone_pickaxe" else &"harvest"))
	if finished: _message("资源已掉落 · 靠近按 [E] 拾取")


func _message(text: String) -> void:
	_host.get_node("UI/Toast").show_message(text)


func _update_name() -> void:
	if _name_label != null: _name_label.text = region_name(active_region) + (" · 东侧路标通往荒地" if active_region == &"home" else " · 路标 [E] 通往相邻区域")


func _gate_position(id: String, side: StringName) -> Vector2:
	var profile: Resource = _profiles[id]
	var size: Vector2i = profile.map_size
	if side in [&"west", &"east"]:
		var x: int = 2 if side == &"west" else size.x - 3
		var y: int = Layout._road_y(profile.layout, x, size)
		return Vector2(x * 16 + 8, y * 16 + 8)
	var y: int = 2 if side == &"north" else size.y - 3
	var candidates: Array[int] = []
	for x: int in range(size.x / 2 - 7, size.x / 2 + 8):
		if Layout.is_route(Vector2i(x, y), size, profile.layout): candidates.append(x)
	var x: int = candidates[candidates.size() / 2] if not candidates.is_empty() else size.x / 2
	return Vector2(x * 16 + 8, y * 16 + 8)


func _inward(side: StringName) -> Vector2:
	match side:
		&"east": return Vector2.LEFT
		&"north": return Vector2.DOWN
		&"south": return Vector2.UP
	return Vector2.RIGHT


func to_dict() -> Dictionary:
	var point: Vector2 = _house.save_position() if active_region == &"home" else player.global_position - region_origin()
	return {"schema": 1, "current": String(active_region), "position": [point.x, point.y], "home_return": [_home_return.x, _home_return.y], "resources": ledger.to_dict()}


func from_dict(data: Dictionary) -> void:
	if data.has("schema") and ((not data.schema is int and not data.schema is float) or float(data.schema) != 1.0): data = {}
	var home: Vector2 = _point([player.global_position.x, player.global_position.y], _home_return, Vector2(640, 480))
	if _house.is_inside():
		_house.exit_house()
	ledger.from_dict(data.get("resources", {}) if data.get("resources", {}) is Dictionary else {}, int(_clock.day))
	for id: String in _sprites: _refresh_region(StringName(id))
	var target: StringName = &"home"
	if data.get("current") is String and _roots.has(data.current): target = StringName(data.current)
	_home_return = _point(data.get("home_return"), Vector2(580, 176), Vector2(640, 480))
	var point: Vector2 = _point(data.get("position"), home if target == &"home" else _gate_position(String(target), &"west") + Vector2(24, 0), Vector2(640, 480) if target == &"home" else Vector2(_profiles[String(target)].map_size * 16))
	if target != &"home":
		var cell := Vector2i((point / 16).floor())
		var ground: TileMapLayer = _roots[String(target)].get_node("Ground")
		# 蓝图中水体和资源的物理状态已恢复；非法位置退回保留的主路出生点。
		var base: int = ground.get_cell_atlas_coords(cell).y * 4 + ground.get_cell_atlas_coords(cell).x
		if ground.get_cell_source_id(cell) == 1: base = (ground.get_cell_atlas_coords(cell).y * 64 + ground.get_cell_atlas_coords(cell).x) / 256
		if Layout.is_water(base): point = _gate_position(String(target), &"west") + Vector2(24, 0)
		for id: String in _sprites[String(target)]:
			var node := _sprites[String(target)][id] as Sprite2D
			var definition: Resource = node.get_meta(&"resource_definition")
			if not definition.blocks_movement or int(ledger.object(target, id).hits) <= 0: continue
			var obstacle := Rect2(node.position - Vector2(definition.footprint.x * 7, 8), Vector2(definition.footprint.x * 14, 12))
			if obstacle.grow(4).has_point(point): point = _gate_position(String(target), &"west") + Vector2(24, 0)
	_switch_to(target, point)


func _point(value: Variant, fallback: Vector2, bounds: Vector2) -> Vector2:
	if not value is Array or value.size() != 2: return fallback
	if (not value[0] is int and not value[0] is float) or (not value[1] is int and not value[1] is float): return fallback
	if not is_finite(float(value[0])) or not is_finite(float(value[1])): return fallback
	var point := Vector2(float(value[0]), float(value[1]))
	if point.x < 0 or point.y < 0 or point.x > bounds.x or point.y > bounds.y: return fallback
	return point.clamp(Vector2(8, 8), bounds - Vector2(8, 8))


func _exit_tree() -> void:
	if ledger.changed.is_connected(_refresh_region): ledger.changed.disconnect(_refresh_region)
	harvest.clear()
	if is_instance_valid(_interaction): _interaction.manager = null
