extends Node
## 交易用例只依赖库存、钱包与注入的购买规则；界面、任务均订阅成功事件。

signal item_bought(id: StringName, count: int)
signal item_sold(id: StringName, count: int)

var inventory: Inventory
var economy: Economy
var last_rejection: String = ""
var _purchase_rules: Array[Callable] = []
var _busy: bool = false


func _ready() -> void:
	add_to_group(&"trade")


func configure(bag: Inventory, wallet: Economy) -> void:
	inventory = bag
	economy = wallet


func add_purchase_rule(rule: Callable) -> void:
	_purchase_rules.append(rule)


func purchase_hint(id: StringName) -> String:
	var item: ItemData = inventory.definition(id)
	if item == null or item.buy_price <= 0:
		return "这件物品不出售"
	for rule: Callable in _purchase_rules:
		var reason: String = rule.call(item)
		if not reason.is_empty():
			return reason
	if item.category == &"tool" and inventory.count_of(id) > 0:
		return "已拥有%s，无需重复购买" % item.display_name
	return ""


func purchase(id: StringName, wanted: int) -> int:
	if _busy or wanted <= 0:
		return 0
	last_rejection = purchase_hint(id)
	if not last_rejection.is_empty():
		return 0
	var item: ItemData = inventory.definition(id)
	var amount: int = mini(mini(wanted, 99), economy.coins / item.buy_price)
	if item.category == &"tool":
		amount = mini(amount, 1)
	while amount > 0 and not inventory.has_space_for(id, amount):
		amount -= 1
	if amount <= 0:
		last_rejection = "金币不足或背包已满"
		return 0
	_busy = true
	# 所有条件先验证，再更新两个模型，最后发通知。观察者只看到完整交易后的状态。
	inventory.begin_update()
	inventory.add_item(id, amount, &"purchase")
	economy.spend(item.buy_price * amount)
	inventory.end_update()
	item_bought.emit(id, amount)
	_busy = false
	return amount


func sell(id: StringName, wanted: int) -> int:
	if _busy or wanted <= 0:
		return 0
	var item: ItemData = inventory.definition(id)
	if item == null or item.sell_price <= 0 or item.category == &"tool":
		return 0
	var amount: int = mini(wanted, inventory.count_of(id))
	if amount <= 0:
		return 0
	_busy = true
	inventory.begin_update()
	if not inventory.remove_item(id, amount):
		inventory.end_update()
		_busy = false
		return 0
	economy.earn(item.sell_price * amount)
	inventory.end_update()
	item_sold.emit(id, amount)
	_busy = false
	return amount
