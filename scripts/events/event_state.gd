extends RefCounted
## 只持有一次性事件的完成日。播放进度、选择、外部任务和奖励不写入此模型。

var _completed: Dictionary[StringName, int] = {}


func has_completed(id: StringName) -> bool:
	return _completed.has(id)


func complete(id: StringName, day: int) -> void:
	_completed[id] = maxi(1, day)


func forget(id: StringName) -> void:
	_completed.erase(id)


func encode() -> Dictionary:
	var records: Dictionary = {}
	for id: StringName in _completed: records[String(id)] = _completed[id]
	return {"version": 1, "completed": records}


func restore(data: Dictionary) -> bool:
	# 保留未知事件 ID，避免暂时移除内容后重新上线又结算。
	var version: Variant = data.get("version", 1)
	if (typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT) or version != 1: return false
	var records: Variant = data.get("completed", {})
	if not records is Dictionary: return false
	_completed.clear()
	for key: Variant in records:
		if not (key is String or key is StringName) or String(key).is_empty(): continue
		var day: Variant = records[key]
		if typeof(day) != TYPE_INT and typeof(day) != TYPE_FLOAT: continue
		var number: float = float(day)
		if not is_finite(number) or number < 1 or number > 2147483647 or number != floor(number): continue
		_completed[StringName(key)] = int(number)
	return true


func clear() -> void:
	_completed.clear()
