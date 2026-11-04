extends SceneTree
## 检查素材成品、确定性分布、地形/资源占地、主路可达性与真实运行碰撞。

const Layout = preload("res://scripts/world/maps/region_layout.gd")
const Catalog = preload("res://tools/lib/world_region_catalog.gd")
const ART: String = "res://assets/packs/world_regions_v1/"
var _failures: int = 0
var _finished: bool = false


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		printerr("[world_regions] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	await _verify()
	_check(_finished, "all region checks reached the end")
	print("[world_regions] %s; %d failures" % ["PASS" if _failures == 0 else "FAIL", _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _verify() -> void:
	for id: String in Layout.TERRAIN_IDS:
		_image(ART + "terrain/" + id + ".png", Vector2i(16, 16), false)
	for index: int in Catalog.RESOURCES.size():
		_image(ART + "resources/" + String(Catalog.RESOURCES[index][0]) + ".png", Vector2i.ONE * (32 if index < 24 else 64), true)
	var seen: Dictionary = {}
	for id: String in Layout.REGION_IDS:
		var profile: Resource = load("res://data/maps/" + id + ".tres")
		var first: Dictionary = Layout.create(profile)
		var second: Dictionary = Layout.create(profile)
		_check(first.ground == second.ground, id + " ground generation is deterministic")
		_check(first.resources.size() == profile.resource_count, id + " reaches configured resource count")
		var positions: Dictionary = {}
		var cells: Dictionary = {}
		var blocked: Dictionary = {}
		for entry: Dictionary in first.resources:
			seen[entry.kind] = true
			positions[entry.id] = entry.cell
			var definition: Resource = entry.definition
			_check(definition.region_tags.has(profile.id), id + " uses region-appropriate resource")
			for y: int in range(entry.cell.y, entry.cell.y + definition.footprint.y):
				for x: int in range(entry.cell.x, entry.cell.x + definition.footprint.x):
					var cell := Vector2i(x, y)
					_check(not cells.has(cell), id + " resource footprints never overlap")
					_check(not Layout.is_water(int(first.ground[cell])), id + " resource never sits on water")
					_check(not Layout.is_route(cell, profile.map_size, profile.layout), id + " resource never blocks main route")
					cells[cell] = true
					if definition.blocks_movement: blocked[cell] = true
		for entry: Dictionary in second.resources:
			_check(positions.has(entry.id) and positions[entry.id] == entry.cell, id + " stable resource identity")
		var reached: Dictionary = _reachable(first.ground, blocked, first.spawn)
		for cell: Vector2i in first.ground:
			if Layout.is_route(cell, profile.map_size, profile.layout): _check(reached.has(cell), id + " all main route cells connect to spawn")
		# 每个资源至少有一处相邻可达格，不能只验证主路而忽略采集入口。
		for entry: Dictionary in first.resources:
			var accessible: bool = false
			var footprint: Vector2i = entry.definition.footprint
			for y: int in range(entry.cell.y - 1, entry.cell.y + footprint.y + 1):
				for x: int in range(entry.cell.x - 1, entry.cell.x + footprint.x + 1):
					if reached.has(Vector2i(x, y)): accessible = true
			_check(accessible, id + " resource has a reachable approach")
		var scene: Node2D = load("res://scenes/maps/" + id + "_preview.tscn").instantiate() as Node2D
		root.add_child(scene)
		current_scene = scene
		await physics_frame
		await physics_frame
		_check(scene.get_node("Ground").get_used_cells().size() == profile.map_size.x * profile.map_size.y, id + " native scene has complete ground")
		_check(int(scene.get_meta(&"resource_count")) == profile.resource_count, id + " native scene matches profile")
		if id in ["wetland", "beach"]:
			var checked_water: bool = false
			for cell: Vector2i in first.ground:
				if not Layout.is_water(int(first.ground[cell])): continue
				var query := PhysicsPointQueryParameters2D.new()
				query.position = Vector2(cell * 16) + Vector2(8, 8)
				query.collision_mask = 1
				_check(not scene.get_world_2d().direct_space_state.intersect_point(query).is_empty(), id + " water collider matches visible water")
				checked_water = true
				break
			_check(checked_water, id + " includes a real water region")
		var player := scene.get_node("World/PreviewPlayer") as CharacterBody2D
		var origin: Vector2 = player.position
		Input.action_press(&"move_right")
		for frame: int in 12: await physics_frame
		Input.action_release(&"move_right")
		_check(player.position.x > origin.x + 8, id + " preview player can move on starting route")
		var checked_body: bool = false
		for child: Node in scene.get_node("World").get_children():
			if not child.has_node("FootCollision"): continue
			var body := child.get_node("FootCollision") as StaticBody2D
			var shape := body.get_child(0) as CollisionShape2D
			var query := PhysicsPointQueryParameters2D.new()
			query.position = shape.global_position
			query.collision_mask = 1
			var hits: Array[Dictionary] = scene.get_world_2d().direct_space_state.intersect_point(query)
			_check(not hits.is_empty(), id + " resource foot collider is active in physics world")
			checked_body = true
			break
		_check(checked_body, id + " contains a solid resource")
		scene.queue_free()
		await process_frame
		await process_frame
	_check(seen.size() == 28, "all 28 resource classes are represented across six maps")
	_finished = true


func _reachable(ground: Dictionary, blocked: Dictionary, start: Vector2i) -> Dictionary:
	var result: Dictionary = {start: true}
	var pending: Array[Vector2i] = [start]
	var index: int = 0
	while index < pending.size():
		var cell: Vector2i = pending[index]
		index += 1
		for direction: Vector2i in Layout.NEIGHBORS:
			var neighbor: Vector2i = cell + direction
			if result.has(neighbor) or not ground.has(neighbor) or blocked.has(neighbor) or Layout.is_water(int(ground[neighbor])): continue
			result[neighbor] = true
			pending.append(neighbor)
	return result


func _image(path: String, size: Vector2i, transparent: bool) -> void:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	_check(image != null, "asset exists: " + path)
	if image == null: return
	_check(image.get_size() == size, "native asset size: " + path)
	_check(image.get_used_rect().size != Vector2i.ZERO, "asset not empty: " + path)
	if transparent: _check(image.get_pixel(0, 0).a == 0, "sprite corner transparent: " + path)
	for y: int in size.y:
		for x: int in size.x:
			var alpha: float = image.get_pixel(x, y).a
			if alpha != 0.0 and alpha != 1.0:
				_check(false, "binary alpha: " + path)
				return
