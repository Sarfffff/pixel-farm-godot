extends RefCounted
## 版本升级与外部数据边界校验；纯数据操作，不修改运行时、不发玩法事件。

const CURRENT_VERSION: int = 2
const SCALARS: Dictionary = {
	"time": {"day": TYPE_INT, "minutes": TYPE_INT},
	"inventory": {"active_slot": TYPE_INT},
	"player": {"x": TYPE_FLOAT, "y": TYPE_FLOAT},
	"community": {"stage": TYPE_INT},
	"orders": {"item": TYPE_STRING, "count": TYPE_INT, "reward": TYPE_INT, "day": TYPE_INT, "due_day": TYPE_INT, "done": TYPE_BOOL},
	"weather": {"kind": TYPE_STRING}, "stamina": {"value": TYPE_INT},
	"upgrades": {"watering_level": TYPE_INT},
	"tutorial": {"step": TYPE_INT, "bought_again": TYPE_BOOL, "sold_again": TYPE_BOOL},
	"forage": {"last_day": TYPE_INT},
	"farm_activities": {"last_day": TYPE_INT, "processing_ready_day": TYPE_INT, "casts_today": TYPE_INT, "pending_fish": TYPE_STRING},
}


static func migrate(document: Dictionary) -> Dictionary:
	var result: Dictionary = document.duplicate(true)
	var version: Variant = result.get("version", 1)
	if (not version is int and not version is float) or version < 1 or version > CURRENT_VERSION or float(version) != floor(float(version)):
		return {}
	version = int(version)
	if version == 1:
		# v2 新增 world_objects 分区；旧档缺少树状态时保留初始地图。
		result["version"] = 2
	_clean_fields(result, {"name": TYPE_STRING, "coins": TYPE_INT, "saved_at": TYPE_INT})
	for section: String in ["time", "inventory", "farm", "player", "coop", "community", "orders", "weather", "stamina", "upgrades", "tutorial", "forage", "farm_activities", "friendship", "world_objects", "animals", "berries"]:
		if result.has(section) and not result[section] is Dictionary:
			result.erase(section)
	for section: String in SCALARS:
		if result.has(section):
			_clean_fields(result[section], SCALARS[section])
	if result.has("inventory"):
		var bag: Dictionary = result.inventory
		_clean_slots(bag)
		if bag.has("hotbar") and not bag.hotbar is Array:
			bag.erase("hotbar")
	if result.has("farm"):
		for key: String in ["tilled", "watered"]:
			_clean_pairs(result.farm, key)
		_clean_records(result.farm, "crops")
		for record: Dictionary in result.farm.get("crops", []):
			_clean_fields(record, {"id": TYPE_STRING, "x": TYPE_INT, "y": TYPE_INT, "stage": TYPE_INT, "stage_age": TYPE_INT, "watered": TYPE_BOOL, "regrowing": TYPE_BOOL})
		_clean_number_map(result.farm, "rocks")
	if result.has("coop"):
		_clean_pairs(result.coop, "eggs")
	if result.has("tutorial"):
		_clean_pairs(result.tutorial, "planted_again")
		_clean_pairs(result.tutorial, "watered_again")
		_clean_number_map(result.tutorial, "harvests_again")
	if result.has("friendship"):
		_clean_number_map(result.friendship, "points")
	if result.has("forage"):
		_clean_number_list(result.forage, "patches")
	if result.has("farm_activities"):
		_clean_slots(result.farm_activities)
		_clean_number_list(result.farm_activities, "depleted")
	if result.has("world_objects"):
		for key: Variant in result.world_objects.keys():
			var state: Variant = result.world_objects[key]
			if not state is Dictionary:
				result.world_objects.erase(key)
			else:
				_clean_fields(state, {"hits": TYPE_INT, "stump_hits": TYPE_INT, "felled": TYPE_BOOL, "cleared": TYPE_BOOL})
	if result.has("berries"):
		_clean_records(result.berries, "bushes")
		for bush: Dictionary in result.berries.get("bushes", []):
			_clean_fields(bush, {"x": TYPE_FLOAT, "y": TYPE_FLOAT, "kind": TYPE_STRING, "stage": TYPE_INT, "wild": TYPE_BOOL, "regrow": TYPE_INT, "grow": TYPE_INT})
	return result


static func _clean_pairs(section: Dictionary, key: String) -> void:
	var value: Variant = section.get(key)
	if not value is Array:
		section.erase(key)
		return
	section[key] = value.filter(func(pair: Variant) -> bool:
		return pair is Array and pair.size() >= 2 and _number(pair[0]) and _number(pair[1]))


static func _clean_records(section: Dictionary, key: String) -> void:
	var value: Variant = section.get(key)
	if value is Array:
		section[key] = value.filter(func(record: Variant) -> bool: return record is Dictionary)
	else:
		section.erase(key)


static func _clean_fields(data: Dictionary, schema: Dictionary) -> void:
	for key: String in schema:
		if not data.has(key): continue
		var value: Variant = data[key]
		var valid: bool = typeof(value) == int(schema[key])
		if int(schema[key]) in [TYPE_INT, TYPE_FLOAT]: valid = _number(value)
		elif int(schema[key]) == TYPE_STRING: valid = value is String or value is StringName
		if not valid: data.erase(key)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _clean_slots(data: Dictionary) -> void:
	var slots: Variant = data.get("slots")
	if not slots is Array:
		data.erase("slots")
		return
	for index: int in slots.size():
		if not slots[index] is Dictionary: slots[index] = {}
		else: _clean_fields(slots[index], {"id": TYPE_STRING, "count": TYPE_INT})


static func _clean_number_map(data: Dictionary, key: String) -> void:
	var values: Variant = data.get(key)
	if not values is Dictionary:
		data.erase(key)
		return
	for id: Variant in values.keys():
		if not _number(values[id]): values.erase(id)


static func _clean_number_list(data: Dictionary, key: String) -> void:
	var values: Variant = data.get(key)
	if values is Array: data[key] = values.filter(_number)
	else: data.erase(key)
