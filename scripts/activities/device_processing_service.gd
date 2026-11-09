extends RefCounted
## 设备加工用例：按设备实例保存配方与到期日，产物在领取时进入唯一库存。
## 不创建节点或界面，不复制背包；投入和产出都走 Inventory 的整批交换。

signal started(device_id: String, recipe_id: StringName)
signal collected(device_id: String, produced: Dictionary)
signal changed

const MAX_DEVICES: int = 1024
const MAX_DAY: int = 1000000

var busy: bool = false
var last_rejection: String = ""
var _bag: Inventory
var _day: Callable
var _recipes: Dictionary[StringName, ProcessingDefinition] = {}
## 设备实例ID → 设备类型ID；由组合根在设备创建/恢复时登记。
var _types: Dictionary[String, StringName] = {}
## 设备实例ID → {recipe_id, ready_day}；产物始终按当前配方推导，不另存一份物品。
var _records: Dictionary[String, Dictionary] = {}
var _publishing: bool = false
var _released: bool = false


## 重配是新会话初始化：替换配方目录并清空加工记录，保留设备类型登记。
func configure(bag: Inventory, current_day: Callable, recipes: Array[ProcessingDefinition]) -> bool:
	if busy or _mutation_blocked(): return false
	if not is_instance_valid(bag) or not current_day.is_valid(): return false
	var accepted: Dictionary[StringName, ProcessingDefinition] = {}
	for recipe: ProcessingDefinition in recipes:
		if recipe == null or not recipe.is_valid() or accepted.has(recipe.id): return false
		accepted[recipe.id] = recipe.duplicate(true) as ProcessingDefinition
	if accepted.is_empty(): return false
	_bag = bag
	_day = current_day
	_recipes = accepted
	_records.clear()
	last_rejection = ""
	return true


## 组合根在设备放置/恢复后登记实例类型；未登记的实例一律拒绝加工。
func bind_device(device_id: String, type_id: StringName) -> bool:
	if busy or _mutation_blocked(): return false
	if device_id.is_empty() or device_id.length() > 64 or type_id == &"": return false
	var existing: StringName = _types.get(device_id, &"")
	if existing != &"": return existing == type_id
	if _types.size() >= MAX_DEVICES: return false
	_types[device_id] = type_id
	return true


## 设备拆除后清理登记与其加工记录；忙碌中的设备应由 lock_reason 先行阻止拆除。
func unbind_device(device_id: String) -> bool:
	if busy or _mutation_blocked(): return false
	var known: bool = _types.erase(device_id)
	_records.erase(device_id)
	return known


## 整批预检全部原料后才提交；同一实例加工中拒绝，设备类型不受配方支持时拒绝。
func start(device_id: String, recipe_id: StringName) -> bool:
	last_rejection = ""
	if _released: return _reject("设备加工服务已释放")
	if busy or _publishing: return _reject("正在处理设备，请稍候")
	var recipe: ProcessingDefinition = _recipes.get(recipe_id)
	if recipe == null: return _reject("加工配方不可用")
	var type_id: StringName = _types.get(device_id, &"")
	if type_id == &"": return _reject("设备类型尚未接入")
	if not recipe.device_types.has(type_id): return _reject("这台设备不能使用该配方")
	var record: Dictionary = _records.get(device_id, {})
	if not record.is_empty(): return _reject("请先领取设备产物" if _is_ready(record) else "该设备正在加工，请稍候")
	if not is_instance_valid(_bag): return _reject("背包暂不可用")
	# 成品未接入时先拒绝，避免收了原料却永远无法领取。
	for item: StringName in recipe.products:
		if Inventory.TOOL_IDS.has(item) or _bag.definition(item) == null: return _reject("成品尚未接入唯一背包")
	var today: int = _today()
	if today <= 0: return _reject("当前日期不可用")
	if today + int(recipe.days) > MAX_DAY: return _reject("加工周期超出范围")
	var consumed: Dictionary[StringName, int] = _items(recipe.ingredients)
	var preview: Dictionary = _bag.preview_exchange_batch(consumed, {})
	if not bool(preview.get("ok", false)): return _reject(String(preview.get("reason", "材料不足或背包状态已变化")))
	busy = true
	_bag.begin_update()
	var exchanged: bool = _bag.exchange_batch(consumed, {}, &"transfer")
	if not exchanged:
		_bag.end_update()
		busy = false
		return _reject("材料或背包状态已变化，请重新确认")
	_records[device_id] = {"recipe_id": recipe_id, "ready_day": today + int(recipe.days)}
	_bag.end_update()
	busy = false
	last_rejection = ""
	_publish_started(device_id, recipe_id)
	return true


## 未到期或背包放不下时返回false并保留待领取产物；成功领取后记录立即清除。
func collect(device_id: String) -> Dictionary:
	last_rejection = ""
	var result: Dictionary = {"ok": false, "produced": {}, "reason": ""}
	if _released: return _reject_result(result, "设备加工服务已释放")
	if busy or _publishing: return _reject_result(result, "正在处理设备，请稍候")
	var record: Dictionary = _records.get(device_id, {})
	if record.is_empty(): return _reject_result(result, "该设备没有待领取的产物")
	var recipe: ProcessingDefinition = _recipes.get(StringName(record.recipe_id))
	if recipe == null: return _reject_result(result, "加工配方已不可用")
	var today: int = _today()
	if today <= 0: return _reject_result(result, "当前日期不可用")
	if today < int(record.ready_day): return _reject_result(result, "尚未加工完成，请在第%d天后再来" % int(record.ready_day))
	if not is_instance_valid(_bag): return _reject_result(result, "背包暂不可用")
	var produced: Dictionary[StringName, int] = _items(recipe.products)
	var preview: Dictionary = _bag.preview_exchange_batch({}, produced)
	if not bool(preview.get("ok", false)): return _reject_result(result, String(preview.get("reason", "背包放不下全部成品，请先整理背包")))
	busy = true
	_bag.begin_update()
	var exchanged: bool = _bag.exchange_batch({}, produced, &"transfer")
	if not exchanged:
		_bag.end_update()
		busy = false
		return _reject_result(result, "背包空间已变化，请重试")
	_records.erase(device_id)
	_bag.end_update()
	busy = false
	last_rejection = ""
	result.ok = true
	result.produced = produced
	_publish_collected(device_id, produced)
	return result


func status(device_id: String) -> Dictionary:
	var result: Dictionary = {"recipe_id": &"", "ready_day": 0, "phase": "idle", "pending": {}}
	if _released: return result
	var record: Dictionary = _records.get(device_id, {})
	if record.is_empty(): return result
	var recipe: ProcessingDefinition = _recipes.get(StringName(record.recipe_id))
	result.recipe_id = StringName(record.recipe_id)
	result.ready_day = int(record.ready_day)
	result.pending = _items(recipe.products) if recipe != null else {}
	result.phase = "ready" if _is_ready(record) else "working"
	return result


## 供放置锁使用：忙碌或待领取时返回原因，空串表示可以移动或拆除。
func lock_reason(device_id: String) -> String:
	if _released: return ""
	var record: Dictionary = _records.get(device_id, {})
	if record.is_empty(): return ""
	return "请先领取设备产物" if _is_ready(record) else "设备正在加工，暂不能移动或拆除"


## 按实例ID保存，只写配方ID与到期日；产物由配方推导，存档不接受外部物品清单。
func encode() -> Dictionary:
	var instances: Dictionary = {}
	var ids: Array = _records.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = _records[id]
		instances[id] = {"recipe_id": String(record.recipe_id), "ready_day": int(record.ready_day)}
	return {"schema": 1, "instances": instances}


## 版本不符、结构过量或配方未知时整分区拒绝，保留现有加工事实。
func restore(data: Dictionary) -> bool:
	if busy or _mutation_blocked(): return false
	var decoded: Dictionary = _decode(data)
	if not bool(decoded.ok):
		last_rejection = String(decoded.reason)
		return false
	var records: Dictionary[String, Dictionary] = {}
	records.assign(decoded.records)
	_records = records
	last_rejection = ""
	_publish_changed()
	return true


func release() -> void:
	if busy: return
	_released = true
	_bag = null
	_day = Callable()
	_recipes.clear()
	_types.clear()
	_records.clear()
	last_rejection = ""


func _decode(data: Dictionary) -> Dictionary:
	if data.is_empty(): return {"ok": true, "records": {}}
	if not _integer(data.get("schema"), 1, 1): return _bad("设备加工存档版本不受支持")
	var rows: Variant = data.get("instances")
	if not rows is Dictionary or rows.size() > MAX_DEVICES: return _bad("设备加工实例列表无效")
	var records: Dictionary[String, Dictionary] = {}
	for raw_id: Variant in rows:
		if not raw_id is String: return _bad("设备加工实例编号无效")
		var id: String = raw_id
		if id.is_empty() or id.length() > 64: return _bad("设备加工实例编号无效")
		var row: Variant = rows[raw_id]
		if not row is Dictionary: return _bad("设备加工记录无效")
		var raw_recipe: Variant = row.get("recipe_id")
		if not (raw_recipe is String or raw_recipe is StringName): return _bad("设备加工配方编号无效")
		var recipe: ProcessingDefinition = _recipes.get(StringName(raw_recipe))
		if recipe == null: return _bad("设备加工配方未知")
		if not _integer(row.get("ready_day"), 1, MAX_DAY): return _bad("设备加工到期日无效")
		var bound: StringName = _types.get(id, &"")
		if bound != &"" and not recipe.device_types.has(bound): return _bad("设备加工配方与设备类型不匹配")
		records[id] = {"recipe_id": StringName(raw_recipe), "ready_day": int(row.get("ready_day"))}
	return {"ok": true, "records": records}


func _is_ready(record: Dictionary) -> bool:
	var today: int = _today()
	return today > 0 and today >= int(record.get("ready_day", 0))


func _today() -> int:
	if not _day.is_valid(): return 0
	var value: Variant = _day.call()
	if not _integer(value, 1, MAX_DAY): return 0
	return int(value)


func _items(items: Dictionary[StringName, int]) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for item: StringName in items: result[item] = int(items[item])
	return result


func _reject(reason: String) -> bool:
	last_rejection = reason
	return false


func _reject_result(result: Dictionary, reason: String) -> Dictionary:
	last_rejection = reason
	result.reason = reason
	return result


func _bad(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and value >= minimum and value <= maximum


func _mutation_blocked() -> bool:
	return _released or _publishing


func _publish_started(device_id: String, recipe_id: StringName) -> void:
	_publishing = true
	started.emit(device_id, recipe_id)
	changed.emit()
	_publishing = false


func _publish_collected(device_id: String, produced: Dictionary) -> void:
	_publishing = true
	collected.emit(device_id, produced)
	changed.emit()
	_publishing = false


func _publish_changed() -> void:
	_publishing = true
	changed.emit()
	_publishing = false
