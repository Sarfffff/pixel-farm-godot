extends RefCounted
## 章节任务簿：任务的唯一事实来源（定义 + 已接/已完成）。
##
## 只做状态与规则推导：不认识背包、金币、界面或场景树。
## 奖励发放在 QuestService；编码/恢复由组合根注册进快照分区，恢复不发奖。

const QUEST_DIR: String = "res://data/quests"
const SAVE_VERSION: int = 1

enum Status { LOCKED = 0, AVAILABLE = 1, ACTIVE = 2, COMPLETED = 3 }

## {任务id: QuestData}
var _definitions: Dictionary[StringName, QuestData] = {}
## {任务id: 接取日}
var _accepted: Dictionary[StringName, int] = {}
## {任务id: 完成日}
var _completed: Dictionary[StringName, int] = {}


## 扫描数据目录；导出包里的 .tres.remap 由 ResourceLoader 透明处理。
func load_definitions() -> void:
	_definitions.clear()
	for file: String in ResourceLoader.list_directory(QUEST_DIR):
		if not file.ends_with(".tres"):
			continue
		var quest := load(QUEST_DIR.path_join(file)) as QuestData
		if quest == null or not quest.is_valid():
			push_warning("[quests] 跳过无效任务文件 %s" % file)
			continue
		if _definitions.has(quest.id):
			push_warning("[quests] 任务 id 重复，保留先读到的那份：%s" % quest.id)
			continue
		_definitions[quest.id] = quest


## 全部任务按章内顺序排列，结果与文件扫描顺序无关。
func definitions() -> Array[QuestData]:
	var list: Array[QuestData] = []
	for quest: QuestData in _definitions.values():
		list.append(quest)
	list.sort_custom(_before)
	return list


func define(id: StringName) -> QuestData:
	return _definitions.get(id)


func status_of(id: StringName) -> int:
	if _completed.has(id):
		return Status.COMPLETED
	if _accepted.has(id):
		return Status.ACTIVE
	var quest: QuestData = define(id)
	if quest == null:
		return Status.LOCKED
	return Status.AVAILABLE if prerequisites_met(id) else Status.LOCKED


## 前置是否齐全；未知前置按未完成处理，缺数据不会让任务提前解锁。
func prerequisites_met(id: StringName) -> bool:
	var quest: QuestData = define(id)
	if quest == null:
		return false
	for required: StringName in quest.requires:
		if not _completed.has(required):
			return false
	return true


func accept(id: StringName, day: int) -> bool:
	if status_of(id) != Status.AVAILABLE:
		return false
	_accepted[id] = maxi(1, day)
	return true


## 只改事实，不发奖；重复完成返回 false，供服务判重。
func complete(id: StringName, day: int) -> bool:
	if not _accepted.has(id):
		return false
	_accepted.erase(id)
	_completed[id] = maxi(1, day)
	return true


func is_active(id: StringName) -> bool:
	return _accepted.has(id)


func is_completed(id: StringName) -> bool:
	return _completed.has(id)


func completed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _completed.keys():
		ids.append(id)
	return ids


func completed_count() -> int:
	return _completed.size()


func accepted_day(id: StringName) -> int:
	return int(_accepted.get(id, 0))


func completed_day(id: StringName) -> int:
	return int(_completed.get(id, 0))


func encode() -> Dictionary:
	return {
		&"version": SAVE_VERSION,
		&"accepted": _days_of(_accepted),
		&"completed": _days_of(_completed),
	}


func restore(data: Dictionary) -> void:
	_accepted.clear()
	_completed.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	_read_days(data.get(&"accepted", {}), _accepted)
	_read_days(data.get(&"completed", {}), _completed)
	# 已完成的任务不能同时挂在进行中；坏档以完成表为准。
	for id: StringName in _completed.keys():
		_accepted.erase(id)


func clear() -> void:
	_accepted.clear()
	_completed.clear()


## 排序：先章内 order，再按 id 字典序。
func _before(first: QuestData, second: QuestData) -> bool:
	if first.order != second.order:
		return first.order < second.order
	return String(first.id) < String(second.id)


func _days_of(source: Dictionary[StringName, int]) -> Dictionary:
	var result: Dictionary = {}
	for id: StringName in source.keys():
		result[String(id)] = int(source[id])
	return result


## 只认已知任务 id 与正整数天数；未知字段和坏标量一律丢弃，读档不因此中断。
func _read_days(source: Variant, target: Dictionary[StringName, int]) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key: Variant in source:
		var id := StringName(str(key))
		if define(id) == null:
			continue
		var raw: Variant = source[key]
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			target[id] = 1
			continue
		target[id] = maxi(1, int(raw))
