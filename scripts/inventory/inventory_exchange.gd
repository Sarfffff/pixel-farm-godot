extends RefCounted
## 背包内部的纯交换预演；只处理临时槽位副本，不维护第二套库存。

const MAX_AMOUNT: int = 2147483647


static func plan(slots: Array[Dictionary], definitions: Dictionary[StringName, ItemData], protected: Array[StringName], consumed: Dictionary, produced: Dictionary) -> Dictionary:
	if consumed.is_empty() and produced.is_empty():
		return _failure("没有需要交换的物品")
	var take: Dictionary = _normalize(consumed, definitions, protected)
	if not take.ok: return take
	var give: Dictionary = _normalize(produced, definitions, protected)
	if not give.ok: return give
	var next: Array[Dictionary] = slots.duplicate(true)
	for id: StringName in take.items:
		var remaining: int = take.items[id]
		for index: int in next.size():
			var slot: Dictionary = next[index]
			if slot.is_empty() or slot[&"id"] != id: continue
			var removed: int = mini(remaining, int(slot[&"count"]))
			slot[&"count"] = int(slot[&"count"]) - removed
			remaining -= removed
			if int(slot[&"count"]) == 0: next[index] = {}
			if remaining == 0: break
		if remaining > 0: return _failure("材料不足：" + definitions[id].display_name)
	var additions: Array[Dictionary] = []
	for id: StringName in give.items:
		var remaining: int = give.items[id]
		var limit: int = definitions[id].max_stack
		# 与现有入包约定一致：先补已有堆叠，再占空格；循环受槽位数限制。
		for slot: Dictionary in next:
			if slot.is_empty() or slot[&"id"] != id: continue
			var moved: int = mini(remaining, maxi(0, limit - int(slot[&"count"])))
			slot[&"count"] = int(slot[&"count"]) + moved
			remaining -= moved
			if remaining == 0: break
		for index: int in next.size():
			if remaining == 0: break
			if not next[index].is_empty(): continue
			var moved: int = mini(remaining, limit)
			next[index] = {&"id": id, &"count": moved}
			remaining -= moved
		if remaining > 0: return _failure("背包放不下全部成品，请先整理背包")
		additions.append({&"id": id, &"count": int(give.items[id])})
	return {&"ok": true, &"reason": "", &"slots": next, &"additions": additions}


static func _normalize(items: Dictionary, definitions: Dictionary[StringName, ItemData], protected: Array[StringName]) -> Dictionary:
	var normalized: Dictionary[StringName, int] = {}
	for raw_id: Variant in items:
		if not (raw_id is String or raw_id is StringName): return _failure("无效物品编号")
		var id := StringName(raw_id)
		var amount: Variant = items[raw_id]
		var item: ItemData = definitions.get(id)
		if id == &"" or item == null or item.max_stack <= 0: return _failure("物品暂不可用")
		if protected.has(id): return _failure("基础工具不能作为交换材料或成品")
		if not amount is int or amount <= 0 or amount > MAX_AMOUNT: return _failure("物品数量必须为有效正整数")
		var previous: int = normalized.get(id, 0)
		if previous > MAX_AMOUNT - int(amount): return _failure("物品数量超过上限")
		normalized[id] = previous + int(amount)
	return {&"ok": true, &"reason": "", &"items": normalized}


static func _failure(reason: String) -> Dictionary:
	return {&"ok": false, &"reason": reason}
