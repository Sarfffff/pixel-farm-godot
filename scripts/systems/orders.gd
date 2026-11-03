extends Node
## 每日订单：每天一张，交指定数量的农产品换一笔奖金。
##
## 订单池 = 已解锁（`unlock_stage <= 社区阶段`）且有卖价的农产品，
## 奖金按卖价上浮，让"交订单"比"直接卖商店"更划算。

signal order_changed

const MIN_COUNT: int = 3
const MAX_COUNT: int = 6
## 奖金 = 卖价 × 数量 × 这个系数
const REWARD_RATE: float = 1.7

## { item, name, icon, count, reward, done, day }
var order: Dictionary = {}


func _ready() -> void:
	add_to_group(&"orders")
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(_on_day_started)
	if order.is_empty():
		refresh(int(time.day) if time != null else 1)


func _on_day_started(day: int) -> void:
	refresh(day)


## 换一张订单；同一天内重复调用会重掷，所以只在切天或初始化时用。
func refresh(day: int) -> void:
	order = {}
	var unlocked: int = 0
	var community := get_tree().get_first_node_in_group(&"community")
	if community != null and community.has_method(&"unlocked_stage"):
		unlocked = int(community.unlocked_stage())
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	var candidates: Array[ItemData] = []
	if inventory != null:
		for item: ItemData in inventory.definitions():
			if item.category == &"crop" and item.sell_price > 0 and item.unlock_stage <= unlocked:
				candidates.append(item)
	if candidates.is_empty():
		order_changed.emit()
		return
	var pick: ItemData = candidates[randi() % candidates.size()]
	var count: int = randi_range(MIN_COUNT, MAX_COUNT)
	order = {
		&"item": pick.id,
		&"name": pick.display_name,
		&"icon": pick.icon,
		&"count": count,
		&"reward": int(round(float(pick.sell_price) * float(count) * REWARD_RATE)),
		&"done": false,
		&"day": day,
	}
	order_changed.emit()


func has_order() -> bool:
	return not order.is_empty() and not bool(order.get(&"done", false))


func item_id() -> StringName:
	return StringName(order.get(&"item", &""))


func required() -> int:
	return int(order.get(&"count", 0))


func reward() -> int:
	return int(order.get(&"reward", 0))


## 背包里现有的数量，最多显示到需求量。
func owned() -> int:
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null or order.is_empty():
		return 0
	return mini(int(inventory.count_of(item_id())), required())


func can_deliver() -> bool:
	return has_order() and owned() >= required()


## 交付：扣货、发奖金、订单标记完成（当天不再刷新的那张）。
func deliver() -> bool:
	if not can_deliver():
		return false
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null or not inventory.remove_item(item_id(), required()):
		return false
	var economy := get_tree().get_first_node_in_group(&"economy")
	if economy != null and economy.has_method(&"earn"):
		economy.earn(reward())
	order[&"done"] = true
	order_changed.emit()
	var save := get_tree().get_first_node_in_group(&"save")
	if save != null and save.has_method(&"save_game"):
		save.save_game()
	return true


func to_dict() -> Dictionary:
	if order.is_empty():
		return {}
	return {
		&"item": String(item_id()),
		&"count": required(),
		&"reward": reward(),
		&"done": bool(order.get(&"done", false)),
		&"day": int(order.get(&"day", 1)),
	}


func from_dict(data: Dictionary) -> void:
	var id := StringName(String(data.get(&"item", "")))
	if id == &"":
		order = {}
		order_changed.emit()
		return
	var count: int = maxi(1, int(data.get(&"count", 1)))
	var display_name := String(id)
	var icon: Texture2D = null
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory != null:
		for item: ItemData in inventory.definitions():
			if item.id == id:
				display_name = item.display_name
				icon = item.icon
				break
	order = {
		&"item": id,
		&"name": display_name,
		&"icon": icon,
		&"count": count,
		&"reward": maxi(0, int(data.get(&"reward", 0))),
		&"done": bool(data.get(&"done", false)),
		&"day": maxi(1, int(data.get(&"day", 1))),
	}
	order_changed.emit()
