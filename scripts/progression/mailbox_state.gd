extends RefCounted
## 唯一的邮件事实；不认识库存、金币、文件和界面。

var _letters: Dictionary[StringName, Dictionary] = {}


func delivered(id: StringName) -> bool:
	return _letters.has(id)


func status(id: StringName) -> Dictionary:
	return _letters.get(id, {}).duplicate(true)


func deliver(id: StringName, day: int, claimed: bool = false) -> bool:
	if id == &"" or delivered(id):
		return false
	_letters[id] = {&"day": maxi(1, day), &"read": false, &"claimed": claimed}
	return true


func mark_read(id: StringName) -> bool:
	if not delivered(id) or _letters[id].read:
		return false
	_letters[id].read = true
	return true


func mark_claimed(id: StringName) -> bool:
	if not delivered(id) or _letters[id].claimed:
		return false
	_letters[id].claimed = true
	_letters[id].read = true
	return true


func unread_count() -> int:
	var total: int = 0
	for row: Dictionary in _letters.values():
		if not row.read:
			total += 1
	return total


func encode() -> Dictionary:
	var rows: Dictionary = {}
	for id: StringName in _letters:
		rows[String(id)] = _letters[id].duplicate(true)
	return {&"version": 1, &"letters": rows}


func restore(data: Dictionary) -> void:
	_letters.clear()
	var rows: Variant = data.get("letters", {})
	if not rows is Dictionary:
		return
	for key: Variant in rows:
		if not key is String and not key is StringName:
			continue
		var id := StringName(key)
		var row: Variant = rows[key]
		if id == &"" or not row is Dictionary:
			continue
		var day: Variant = row.get("day", 1)
		if not (day is int or day is float) or not is_finite(float(day)):
			continue
		# 坏的领取标记按已领处理，不能因字符串/空值降级而重新发附件。
		var claimed: bool = row.get("claimed", false) if row.get("claimed", false) is bool else true
		var read: bool = row.get("read", false) if row.get("read", false) is bool else false
		_letters[id] = {&"day": maxi(1, int(day)), &"read": read, &"claimed": claimed}
	# 暂时缺少定义的稳定ID仍保留投递/领取墓碑，内容恢复后不能重发。
