extends RefCounted
## 纯数据农田编解码：不访问场景、私有字段、物理或作物节点。


static func encode(soil: Dictionary, crops: Array[Dictionary]) -> Dictionary:
	var tilled: Array = []
	var watered: Array = []
	for cell: Vector2i in soil:
		tilled.append([cell.x, cell.y])
		if soil[cell]:
			watered.append([cell.x, cell.y])
	return {&"tilled": tilled, &"watered": watered, &"crops": crops}


static func decode(data: Dictionary, allowed: Rect2i, definitions: Dictionary) -> Dictionary:
	var soil: Dictionary = {}
	for cell: Vector2i in _cells(data.get("tilled", [])):
		if allowed.has_point(cell):
			soil[cell] = false
	for cell: Vector2i in _cells(data.get("watered", [])):
		if soil.has(cell):
			soil[cell] = true
	var crops: Array[Dictionary] = []
	var records: Variant = data.get("crops", [])
	if records is Array:
		for record: Variant in records:
			if not record is Dictionary or not _number(record.get("x")) or not _number(record.get("y")):
				continue
			var id: Variant = record.get("id", "")
			if not id is String and not id is StringName:
				continue
			var cell := Vector2i(int(record.x), int(record.y))
			if soil.has(cell) and definitions.has(StringName(id)):
				crops.append(record)
	return {&"soil": soil, &"crops": crops}


static func _cells(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if value is Array:
		for pair: Variant in value:
			if pair is Array and pair.size() >= 2 and _number(pair[0]) and _number(pair[1]):
				result.append(Vector2i(int(pair[0]), int(pair[1])))
	return result


static func _number(value: Variant) -> bool:
	return value is int or value is float
