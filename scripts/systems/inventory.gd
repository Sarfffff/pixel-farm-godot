class_name Inventory
extends Node
## 背包：固定槽位 + 同 id 自动堆叠，物品定义在运行期从 res://data/items 扫描。
##
## 只负责数据，不碰界面：UI 订阅 changed 刷新，其他系统用 add_item / remove_item。
## 加入 inventory 组，任何节点都能 get_first_node_in_group(&"inventory") 找到它。

signal changed
## 成功放入物品时发出，供飘字提示使用（溢出时也只报实际放入的数量）。
signal item_added(id: StringName, count: int)

const ITEM_DIR: String = "res://data/items"
const SLOT_COUNT: int = 24
## 开局随身携带的物品，[id, 数量]；播种玩法接入后改为从商店购买。
const STARTING_ITEMS: Array = [[&"carrot_seeds", 5]]

var _definitions: Dictionary[StringName, ItemData] = {}
## 每格 { &"id": StringName, &"count": int }，空格为 {}。
var _slots: Array[Dictionary] = []
## 今天收进背包的件数（睡觉后清零），日报用。
var today_collected: int = 0


func _ready() -> void:
	add_to_group(&"inventory")
	_load_definitions()
	_slots.resize(SLOT_COUNT)
	for index in SLOT_COUNT:
		_slots[index] = {}
	for entry: Array in STARTING_ITEMS:
		add_item(entry[0] as StringName, int(entry[1]))
	# 开局赠品不算今日收获
	today_collected = 0
	_connect_time.call_deferred()
	changed.emit()


func _connect_time() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(func(_day: int) -> void: today_collected = 0)


## 放入物品，返回没放下的数量（背包满时 > 0，调用方可据此提示）。
func add_item(id: StringName, count: int) -> int:
	if count <= 0 or not _definitions.has(id):
		if count > 0:
			push_warning("[inventory] 未定义的物品 id：%s" % id)
		return count
	var definition: ItemData = _definitions[id]
	var remaining: int = count

	# 先补已有堆叠，再占新格子，避免同种物品散落在多个格子。
	for index in SLOT_COUNT:
		if remaining <= 0:
			break
		var slot: Dictionary = _slots[index]
		if slot.is_empty() or slot[&"id"] != id:
			continue
		var space: int = definition.max_stack - int(slot[&"count"])
		if space <= 0:
			continue
		var moved: int = mini(space, remaining)
		slot[&"count"] = int(slot[&"count"]) + moved
		remaining -= moved

	while remaining > 0:
		var index: int = _first_empty()
		if index < 0:
			break
		var moved: int = mini(definition.max_stack, remaining)
		_slots[index] = {&"id": id, &"count": moved}
		remaining -= moved

	var stored: int = count - remaining
	if stored > 0:
		today_collected += stored
		item_added.emit(id, stored)
		changed.emit()
	return remaining


## 取出指定数量；数量不足时不做任何改动并返回 false。
func remove_item(id: StringName, count: int) -> bool:
	if count <= 0:
		return true
	if count_of(id) < count:
		return false
	var remaining: int = count
	for index in SLOT_COUNT:
		if remaining <= 0:
			break
		var slot: Dictionary = _slots[index]
		if slot.is_empty() or slot[&"id"] != id:
			continue
		var taken: int = mini(int(slot[&"count"]), remaining)
		slot[&"count"] = int(slot[&"count"]) - taken
		remaining -= taken
		if int(slot[&"count"]) <= 0:
			_slots[index] = {}
	if remaining != count:
		changed.emit()
	return true


func has_space_for(id: StringName, count: int) -> bool:
	if count <= 0:
		return true
	var item: ItemData = _definitions.get(id)
	if item == null:
		return false
	var capacity: int = 0
	for slot: Dictionary in _slots:
		if slot.is_empty():
			capacity += item.max_stack
		elif slot[&"id"] == id:
			capacity += maxi(0, item.max_stack - int(slot[&"count"]))
		if capacity >= count:
			return true
	return false


func count_of(id: StringName) -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty() and slot[&"id"] == id:
			total += int(slot[&"count"])
	return total


## 当前放入的物品总数（按数量累计），用于判断背包是否为空。
func total_items() -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty():
			total += int(slot[&"count"])
	return total


func slot_count() -> int:
	return _slots.size()


## 返回格子内容的副本，空格返回 {}。
func item_at(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {}
	return _slots[index].duplicate()


func definition(id: StringName) -> ItemData:
	return _definitions.get(id)


## 物品表里的全部定义，供商店等外部系统展示商品（按 id 排序，界面顺序稳定）。
func definitions() -> Array[ItemData]:
	var ids: Array[StringName] = []
	for id: StringName in _definitions:
		ids.append(id)
	ids.sort()
	var result: Array[ItemData] = []
	for id: StringName in ids:
		result.append(_definitions[id])
	return result


## 存盘用：逐格导出（空格写空字典），顺序即槽位顺序。
func to_dict() -> Dictionary:
	var slots: Array = []
	for slot: Dictionary in _slots:
		if slot.is_empty():
			slots.append({})
		else:
			slots.append({&"id": String(slot[&"id"]), &"count": int(slot[&"count"])})
	return {&"slots": slots}


## 读档：未知物品、越界槽位、数量异常都跳过，保证坏档也能进游戏。
func from_dict(data: Dictionary) -> void:
	_slots.resize(SLOT_COUNT)
	for index in SLOT_COUNT:
		_slots[index] = {}
	var slots: Array = data.get("slots", [])
	for index in mini(slots.size(), SLOT_COUNT):
		var record: Dictionary = slots[index]
		if record.is_empty():
			continue
		var id := StringName(record.get("id", ""))
		var count: int = int(record.get("count", 0))
		if count <= 0 or not _definitions.has(id):
			continue
		_slots[index] = {&"id": id, &"count": mini(count, _definitions[id].max_stack)}
	changed.emit()


func _first_empty() -> int:
	for index in _slots.size():
		if _slots[index].is_empty():
			return index
	return -1


func _load_definitions() -> void:
	var directory := DirAccess.open(ITEM_DIR)
	if directory == null:
		push_error("[inventory] 无法打开物品目录 %s" % ITEM_DIR)
		return
	for file: String in directory.get_files():
		if not file.ends_with(".tres"):
			continue
		var item := load(ITEM_DIR.path_join(file)) as ItemData
		if item == null or item.id == &"":
			push_warning("[inventory] 跳过无效物品文件 %s" % file)
			continue
		_definitions[item.id] = item
	if _definitions.is_empty():
		push_error("[inventory] 没有任何物品定义，背包将无法使用")
