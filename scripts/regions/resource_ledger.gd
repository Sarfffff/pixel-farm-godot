extends RefCounted
## 纯状态：资源损伤、再生日期、掉落物。恢复快照绝不调用采集或发奖。

signal changed(region: StringName)
var rules: Dictionary = {}
var regions: Dictionary = {}
var _templates: Dictionary = {}
var last_day: int = 1


func seed_region(id: StringName, entries: Array[Dictionary]) -> void:
	var objects: Dictionary = {}
	for entry: Dictionary in entries:
		var rule: Dictionary = rules.get(String(entry.kind), {})
		if rule.is_empty(): continue
		var drop_cell: Vector2i = entry.get("drop_cell", entry.cell)
		objects[String(entry.id)] = {"kind": String(entry.kind), "cell": [entry.cell.x, entry.cell.y], "drop_cell": [drop_cell.x, drop_cell.y], "hits": int(rule.hits), "due_day": 0, "generation": 0}
	_templates[String(id)] = {"objects": objects, "drops": {}}
	regions[String(id)] = _templates[String(id)].duplicate(true)


func object(region: StringName, id: String) -> Dictionary:
	return regions.get(String(region), {}).get("objects", {}).get(id, {})


func damage(region: StringName, id: String, day: int) -> Dictionary:
	var state: Dictionary = object(region, id)
	if state.is_empty() or int(state.hits) <= 0: return {}
	state.hits = int(state.hits) - 1
	var result: Dictionary = {"finished": false, "hits": state.hits}
	if int(state.hits) == 0:
		var rule: Dictionary = rules[state.kind]
		state.due_day = day + int(rule.days)
		var drops: Dictionary = regions[String(region)].drops
		var drop_id: String
		while true:
			state.generation = int(state.generation) + 1
			drop_id = id + "/drop/" + str(state.generation)
			if not drops.has(drop_id): break
		drops[drop_id] = {"item": String(rule.item), "count": int(rule.count), "cell": state.drop_cell.duplicate()}
		result.finished = true
		result.drop_id = drop_id
	changed.emit(region)
	return result


func begin_day(day: int, can_regrow: Callable) -> void:
	if day <= last_day: return
	last_day = day
	for region: String in regions:
		var any: bool = false
		for id: String in regions[region].objects:
			var state: Dictionary = regions[region].objects[id]
			if int(state.hits) > 0 or int(state.due_day) <= 0 or int(state.due_day) > day: continue
			if can_regrow.is_valid() and not bool(can_regrow.call(StringName(region), id)): continue
			state.hits = int(rules[state.kind].hits)
			state.due_day = 0
			any = true
		if any: changed.emit(StringName(region))


func take_drop(region: StringName, id: String) -> void:
	regions[String(region)].drops.erase(id)
	changed.emit(region)


func to_dict() -> Dictionary:
	return {"last_day": last_day, "areas": regions.duplicate(true)}


func from_dict(data: Dictionary, day: int) -> void:
	regions = _templates.duplicate(true)
	last_day = day
	var areas: Variant = data.get("areas", {})
	if not areas is Dictionary: return
	var allowed_items: Dictionary = {}
	for rule: Dictionary in rules.values(): allowed_items[String(rule.item)] = true
	for region: String in regions:
		var saved: Variant = areas.get(region, {})
		if not saved is Dictionary: continue
		var objects: Variant = saved.get("objects", {})
		if objects is Dictionary:
			for id: String in regions[region].objects:
				var record: Variant = objects.get(id)
				if not record is Dictionary: continue
				var state: Dictionary = regions[region].objects[id]
				state.hits = _number(record.get("hits"), int(rules[state.kind].hits), 0, int(rules[state.kind].hits))
				state.due_day = _number(record.get("due_day"), day + 1, 1, 1000000) if state.hits == 0 else 0
				state.generation = _number(record.get("generation"), 0, 0, 1000000)
		var drops: Variant = saved.get("drops", {})
		if not drops is Dictionary: continue
		for id: Variant in drops:
			var drop: Variant = drops[id]
			if not id is String or id.length() > 180 or not drop is Dictionary: continue
			var item: Variant = drop.get("item")
			var cell: Variant = drop.get("cell")
			if not item is String or not allowed_items.has(item) or not _cell_valid(cell): continue
			var count: int = _number(drop.get("count"), 0, 0, 99)
			if count == 0: continue
			regions[region].drops[id] = {"item": item, "count": count, "cell": [int(cell[0]), int(cell[1])]}


static func _number(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if not value is int and not value is float: return fallback
	if not is_finite(float(value)): return fallback
	return clampi(int(value), minimum, maximum)


static func _cell_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1])) and float(value[0]) >= 0 and float(value[0]) < 48 and float(value[1]) >= 0 and float(value[1]) < 32
