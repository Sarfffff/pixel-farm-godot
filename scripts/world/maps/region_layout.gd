extends RefCounted
## 所有预览共用确定性地形和资源布局；画面、占地与检查同源。

const TILE: int = 16
const TERRAIN_IDS: Array[String] = ["spring_grass", "grass_variant", "meadow_grass", "forest_floor", "bare_dirt", "fertile_dirt", "earth_path", "cobblestone", "sand", "sand_variant", "quarry_gravel", "slate_gravel", "shallow_water", "deep_water", "marsh_ground", "moist_earth"]
const REGION_IDS: Array[String] = ["farm", "village", "forest", "wetland", "quarry", "beach"]
const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const RESOURCE_ROOT: String = "res://data/ground_resources/"


static func create(profile: Resource) -> Dictionary:
	var ground: Dictionary = {}
	var occupied: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value
	for y: int in profile.map_size.y:
		for x: int in profile.map_size.x:
			ground[Vector2i(x, y)] = surface(profile.layout, Vector2i(x, y), profile.map_size, rng)
	var resources: Array[Dictionary] = []
	var definitions: Dictionary = {}
	for id: String in profile.resource_weights:
		definitions[id] = load(RESOURCE_ROOT + id + ".tres")
	# 每种规划资源至少出现一次，其后按区域权重抽取；失败不强行挤入通道。
	for id: String in definitions:
		_place(id, profile, ground, occupied, resources, definitions, rng)
	var attempts: int = 0
	while resources.size() < profile.resource_count and attempts < profile.resource_count * 30:
		attempts += 1
		var id: String = _weighted(profile.resource_weights, rng)
		_place(id, profile, ground, occupied, resources, definitions, rng)
	return {"ground": ground, "resources": resources, "occupied": occupied, "spawn": Vector2i(4, _road_y(profile.layout, 4, profile.map_size))}


static func is_route(cell: Vector2i, size: Vector2i, kind: StringName = &"farm") -> bool:
	var horizontal: bool = absi(cell.y - _road_y(kind, cell.x, size)) <= 1
	if kind == &"beach" and cell.x > 31: horizontal = false
	var vertical_x: int = size.x / 2
	if kind == &"forest": vertical_x += roundi(sin(float(cell.y) * 0.22) * 3.0)
	if kind == &"wetland": vertical_x = 20 + roundi(sin(float(cell.y) * 0.24) * 2.0)
	return horizontal or absi(cell.x - vertical_x) <= 1


static func _road_y(kind: StringName, x: int, size: Vector2i) -> int:
	if kind == &"forest": return size.y / 2 + roundi(sin(float(x) * 0.18) * 2.0)
	if kind == &"wetland": return size.y / 2 + roundi(sin(float(x) * 0.15))
	if kind == &"quarry": return size.y / 2 + (2 if x > 28 else 0)
	return size.y / 2


static func is_water(terrain: int) -> bool:
	return terrain in [12, 13]


static func surface(kind: StringName, cell: Vector2i, size: Vector2i, rng: RandomNumberGenerator) -> int:
	var x: int = cell.x
	var y: int = cell.y
	var tile: int = 0 if rng.randf() < 0.8 else 1
	match kind:
		&"farm":
			if pow(float(x - 24) / 18.0, 2) + pow(float(y - 16) / 12.0, 2) < 1.0:
				tile = 4
		&"village":
			tile = 2
			if Rect2i(15, 9, 18, 15).has_point(cell): tile = 7
			if (x in range(6, 13) or x in range(35, 42)) and (y in range(5, 12) or y in range(21, 28)): tile = 6
		&"forest":
			tile = 0 if sin(float(x) * 0.18) + cos(float(y) * 0.27) > 1.3 else 3
		&"wetland":
			tile = 2 if x < 15 and sin(float(x) * 0.24) + cos(float(y) * 0.27) > 1.35 else 14
			var river: float = 34.0 + sin(float(y) * 0.28) * 3.0
			if absf(float(x) - river) < 4.0: tile = 12 if absf(float(x) - river) > 2.0 else 13
		&"quarry":
			tile = 10
			if (x - 12) * (x - 12) + (y - 10) * (y - 10) < 52 or (x - 37) * (x - 37) + (y - 25) * (y - 25) < 62: tile = 11
		&"beach":
			tile = 8 if rng.randf() < 0.82 else 9
			var coast: float = 36.0 + sin(float(y) * 0.23) * 2.5
			if float(x) > coast: tile = 12 if float(x) < coast + 3.0 else 13
	# 两条3格宽通路及渡口始终保留，可供玩家行走和后续连接区域。
	if is_route(cell, size, kind):
		if kind == &"village": return 7
		if kind == &"beach": return 6
		if is_water(tile): return 7
		return 6
	return tile


static func transition(ground: Dictionary, cell: Vector2i) -> Vector2i:
	var base: int = ground[cell]
	var counts: Dictionary = {}
	for direction: Vector2i in NEIGHBORS:
		var other: int = int(ground.get(cell + direction, base))
		if _family(base) != _family(other): counts[other] = int(counts.get(other, 0)) + 1
	if counts.is_empty(): return Vector2i(-1, 0)
	var neighbor: int = int(counts.keys()[0])
	for key: int in counts:
		if int(counts[key]) > int(counts[neighbor]): neighbor = key
	var mask: int = 0
	for index: int in NEIGHBORS.size():
		if _family(int(ground.get(cell + NEIGHBORS[index], base))) == _family(neighbor): mask |= 1 << index
	return Vector2i((base * 16 + neighbor) * 16 + mask, mask)


static func _family(tile: int) -> int:
	if tile in [0, 1, 2]: return 0
	if tile in [4, 5, 15]: return 4
	if tile in [8, 9]: return 8
	if tile in [12, 13]: return 12
	return tile


static func _weighted(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: int = 0
	for value: Variant in weights.values(): total += int(value)
	var roll: int = rng.randi_range(1, maxi(1, total))
	for id: String in weights:
		roll -= int(weights[id])
		if roll <= 0: return id
	return String(weights.keys()[0])


static func _place(id: String, profile: Resource, ground: Dictionary, occupied: Dictionary, entries: Array[Dictionary], definitions: Dictionary, rng: RandomNumberGenerator) -> void:
	var definition: Resource = definitions[id]
	if definition == null: return
	for attempt: int in 80:
		var cell := Vector2i(rng.randi_range(2, profile.map_size.x - 4), rng.randi_range(2, profile.map_size.y - 4))
		if attempt < 60:
			var anchor := Vector2i(12 if rng.randf() < 0.5 else 36, 8 if rng.randf() < 0.5 else 25)
			cell = Vector2i(clampi(roundi(rng.randfn(anchor.x, 5.5)), 2, profile.map_size.x - 4), clampi(roundi(rng.randfn(anchor.y, 3.0)), 2, profile.map_size.y - 4))
		if profile.id == &"wetland" and id in ["reeds", "willow_tree", "river_pebbles"] and cell.x < 26: continue
		if profile.id == &"beach" and id in ["shell", "reeds"] and cell.x < 26: continue
		var footprint := Rect2i(cell, definition.footprint)
		var free: bool = true
		for y: int in range(cell.y - 1, footprint.end.y + 1):
			for x: int in range(cell.x - 1, footprint.end.x + 1):
				var test := Vector2i(x, y)
				if is_route(test, profile.map_size, profile.layout) or is_water(int(ground.get(test, 13))) or occupied.has(test): free = false
		if not free: continue
		for y: int in range(cell.y, footprint.end.y):
			for x: int in range(cell.x, footprint.end.x): occupied[Vector2i(x, y)] = true
		entries.append({"id": "%s_%s_%d_%d" % [profile.id, id, cell.x, cell.y], "kind": id, "cell": cell, "definition": definition})
		return
