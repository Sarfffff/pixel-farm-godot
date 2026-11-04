extends RefCounted
## 独立仓储数据，不加入玩家 inventory 组，也不发放开局物品。

var slots: Array[Dictionary] = []


func _init(capacity: int = 24) -> void:
	slots.resize(maxi(1, capacity))
	for index: int in slots.size():
		slots[index] = {}


func capacity_for(id: StringName, maximum: int) -> int:
	var space: int = 0
	for slot: Dictionary in slots:
		if slot.is_empty():
			space += maximum
		elif StringName(slot["id"]) == id:
			space += maxi(0, maximum - int(slot["count"]))
	return space


func add(id: StringName, count: int, maximum: int) -> int:
	var remaining: int = maxi(0, count)
	for slot: Dictionary in slots:
		if remaining == 0:
			break
		if not slot.is_empty() and StringName(slot["id"]) == id:
			var moved: int = mini(remaining, maxi(0, maximum - int(slot["count"])))
			slot["count"] = int(slot["count"]) + moved
			remaining -= moved
	for index: int in slots.size():
		if remaining == 0:
			break
		if slots[index].is_empty():
			var moved: int = mini(remaining, maximum)
			slots[index] = {"id": String(id), "count": moved}
			remaining -= moved
	return remaining


func count_of(id: StringName) -> int:
	var total: int = 0
	for slot: Dictionary in slots:
		if not slot.is_empty() and StringName(slot["id"]) == id:
			total += int(slot["count"])
	return total


func remove(id: StringName, count: int) -> bool:
	if count < 0 or count_of(id) < count:
		return false
	var remaining: int = count
	for index: int in slots.size():
		var slot: Dictionary = slots[index]
		if not slot.is_empty() and StringName(slot["id"]) == id:
			var taken: int = mini(remaining, int(slot["count"]))
			slot["count"] = int(slot["count"]) - taken
			remaining -= taken
			if int(slot["count"]) == 0:
				slots[index] = {}
		if remaining == 0:
			break
	return true


func restore(records: Array, inventory: Inventory) -> void:
	for index: int in slots.size():
		slots[index] = {}
	for index: int in mini(records.size(), slots.size()):
		if not records[index] is Dictionary:
			continue
		var record: Dictionary = records[index]
		var id: StringName = StringName(record.get("id", ""))
		var item: ItemData = inventory.definition(id)
		if item != null and int(record.get("count", 0)) > 0:
			slots[index] = {"id": String(id), "count": mini(int(record["count"]), item.max_stack)}
