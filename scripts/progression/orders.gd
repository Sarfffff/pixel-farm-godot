extends Node
## 多日订单：未完成的订单保留五天；完成后次日发新单。
##
## 订单池 = 已解锁（`unlock_stage <= 社区阶段`）且有卖价的农产品，
## 首单改用田边可采到的纤维；其他订单奖金按卖价上浮。

signal order_changed

const MIN_COUNT: int = 3
const MAX_COUNT: int = 6
## 奖金 = 卖价 × 数量 × 这个系数
const REWARD_RATE: float = 1.7
const DURATION_DAYS: int = 5

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
	if not has_order() or day > int(order.get(&"due_day", day)):
		refresh(day)
	else:
		order_changed.emit()


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
			if item.category == &"crop" and item.sell_price > 0 and item.unlock_stage <= unlocked and _obtainable_for_order(item.id):
				candidates.append(item)
	if candidates.is_empty():
		order_changed.emit()
		return
	var pick: ItemData = candidates[randi() % candidates.size()]
	var count: int = randi_range(MIN_COUNT, MAX_COUNT)
	# 首单让新人当天能完成，顺路认识社区需要的纤维来源。
	if day == 1:
		pick = inventory.definition(&"fiber")
		count = 4
	order = {
		&"item": pick.id,
		&"name": pick.display_name,
		&"icon": pick.icon,
		&"count": count,
		&"reward": int(round(float(pick.sell_price) * float(count) * REWARD_RATE)),
		&"done": false,
		&"day": day,
		&"due_day": day + DURATION_DAYS - 1,
	}
	order_changed.emit()


## 新种植必须在订单期限和本季内成熟；足量库存也可以交付。
func _obtainable_for_order(id: StringName) -> bool:
	if id == &"egg":
		return true
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	if inventory != null and inventory.count_of(id) >= MAX_COUNT:
		return true
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	var time := get_tree().get_first_node_in_group(&"time")
	if tiller == null or time == null:
		return false
	for crop: CropData in tiller.crop_definitions():
		if crop.harvest_item != id or not crop.grows_in(time.season()):
			continue
		var nights: int = 0
		for stage: int in crop.last_stage():
			nights += crop.days_at_stage(stage)
		var available: int = mini(DURATION_DAYS - 1, time.DAYS_PER_SEASON - time.day_of_season())
		return nights <= available
	return false


func has_order() -> bool:
	return not order.is_empty() and not bool(order.get(&"done", false))


func item_id() -> StringName:
	return StringName(order.get(&"item", &""))


func required() -> int:
	return int(order.get(&"count", 0))


func reward() -> int:
	return int(order.get(&"reward", 0))


func days_left() -> int:
	var time := get_tree().get_first_node_in_group(&"time")
	var day: int = int(time.day) if time != null else 1
	return maxi(0, int(order.get(&"due_day", day)) - day + 1)


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
		&"due_day": int(order.get(&"due_day", 1)),
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
		&"due_day": maxi(1, int(data.get(&"due_day", int(data.get(&"day", 1)) + DURATION_DAYS - 1))),
	}
	order_changed.emit()
