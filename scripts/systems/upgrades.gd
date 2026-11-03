extends Node
## 升级只在材料与金币全部满足时扣款，存档恢复不重复付费。

signal changed

const WATERING := preload("res://data/upgrades/watering_can.tres")
var watering_level: int = 0


func _ready() -> void:
	add_to_group(&"upgrades")


func can_purchase() -> bool:
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var economy := get_tree().get_first_node_in_group(&"economy") as Economy
	return watering_level == 0 and inventory != null and economy != null \
		and economy.can_afford(WATERING.coin_cost) \
		and inventory.count_of(&"wood") >= WATERING.wood_cost \
		and inventory.count_of(&"stone") >= WATERING.stone_cost


func purchase() -> bool:
	if not can_purchase():
		return false
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var economy := get_tree().get_first_node_in_group(&"economy") as Economy
	inventory.remove_item(&"wood", WATERING.wood_cost)
	inventory.remove_item(&"stone", WATERING.stone_cost)
	economy.spend(WATERING.coin_cost)
	watering_level = 1
	changed.emit()
	var save := get_tree().get_first_node_in_group(&"save")
	if save != null:
		save.save_game()
	return true


func to_dict() -> Dictionary:
	return {&"watering_level": watering_level}


func from_dict(data: Dictionary) -> void:
	watering_level = clampi(int(data.get("watering_level", 0)), 0, 1)
	changed.emit()
