extends RefCounted
## 可选devices分区的严格解码。先验证全部记录，再由用例原子替换。

const MAX_INSTANCES: int = 1024
const MAX_ID: int = 9007199254740000


static func decode(data: Dictionary, definitions: Dictionary, bag: Inventory) -> Dictionary:
	if data.is_empty(): return {"ok": true, "next_id": 1, "records": []}
	if data.get("schema") != 1 or not _integer(data.get("next_id"), 1, MAX_ID): return _bad("设备存档版本或编号无效")
	var rows: Variant = data.get("instances")
	if not rows is Array or rows.size() > MAX_INSTANCES: return _bad("设备实例列表无效")
	var records: Array[Dictionary] = []
	var ids: Dictionary = {}
	var used: Dictionary = {}
	var next_id: int = int(data.next_id)
	for raw: Variant in rows:
		if not raw is Dictionary: return _bad("设备记录无效")
		var id: Variant = raw.get("id")
		var type_id: Variant = raw.get("type_id")
		if not id is String or not id.begins_with("device_") or not id.trim_prefix("device_").is_valid_int() or ids.has(id): return _bad("设备实例ID无效或重复")
		var serial: int = id.trim_prefix("device_").to_int()
		if serial <= 0 or serial >= MAX_ID: return _bad("设备编号超出范围")
		if id != "device_%012d" % serial: return _bad("设备实例ID格式无效")
		if not (type_id is String or type_id is StringName) or not definitions.has(StringName(type_id)): return _bad("设备类型未知，未覆盖当前设备")
		var definition: Resource = definitions[StringName(type_id)]
		var cell: Variant = raw.get("cell")
		if raw.get("space_id") != "home" or not cell is Array or cell.size() != 2: return _bad("设备地图或坐标无效")
		if not _integer(cell[0], -4096, 4096) or not _integer(cell[1], -4096, 4096) or not _integer(raw.get("facing"), 0, 3): return _bad("设备坐标或朝向无效")
		var occupied: Array[Vector2i] = definition.cells(Vector2i(int(cell[0]), int(cell[1])), int(raw.facing))
		for point: Vector2i in occupied:
			if used.has(point): return _bad("存档中的设备占地重叠")
			used[point] = true
		var slots: Variant = raw.get("slots", [])
		if not slots is Array or slots.size() > definition.storage_capacity: return _bad("设备储物格无效")
		var clean_slots: Array[Dictionary] = []
		for slot: Variant in slots:
			if not slot is Dictionary: return _bad("储物记录无效")
			if slot.is_empty():
				clean_slots.append({})
				continue
			var item_id: Variant = slot.get("id")
			if not (item_id is String or item_id is StringName): return _bad("储物物品无效")
			var item: ItemData = bag.definition(StringName(item_id))
			if item == null or item.category == &"tool" or not _integer(slot.get("count"), 1, item.max_stack): return _bad("储物物品或数量无效")
			clean_slots.append({"id": String(item_id), "count": int(slot.count)})
		var operation: Variant = raw.get("operation", idle_operation())
		if not operation is Dictionary or not operation.get("phase") in ["idle", "processing", "ready"]: return _bad("设备工作状态无效")
		if not operation.get("recipe_id", "") is String or not _integer(operation.get("finish_day", 0), 0, 1000000): return _bad("设备工作记录无效")
		var inputs: Variant = operation.get("inputs", {})
		var outputs: Variant = operation.get("pending_outputs", {})
		if not _items_valid(inputs, bag) or not _items_valid(outputs, bag): return _bad("设备投入或待领取内容无效")
		records.append({"id": id, "type_id": String(type_id), "space_id": "home", "cell": [int(cell[0]), int(cell[1])], "facing": int(raw.facing), "slots": clean_slots, "operation": {"phase": String(operation.phase), "recipe_id": String(operation.get("recipe_id", "")), "finish_day": int(operation.get("finish_day", 0)), "inputs": inputs.duplicate(), "pending_outputs": outputs.duplicate()}})
		ids[id] = true
		next_id = maxi(next_id, serial + 1)
	return {"ok": true, "next_id": next_id, "records": records}


static func idle_operation() -> Dictionary:
	return {"phase": "idle", "recipe_id": "", "inputs": {}, "finish_day": 0, "pending_outputs": {}}


static func _items_valid(items: Variant, bag: Inventory) -> bool:
	if not items is Dictionary or items.size() > 128: return false
	for id: Variant in items:
		if not (id is String or id is StringName) or bag.definition(StringName(id)) == null or not _integer(items[id], 1, 1000000): return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and value >= minimum and value <= maximum


static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
