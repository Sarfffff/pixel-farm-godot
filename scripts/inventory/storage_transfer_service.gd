extends RefCounted
## 仓储事务只协调背包和仓库；通知发生时两边已经完成提交。

var bag: Inventory
var storage: RefCounted
var _busy: bool = false


func deposit(id: StringName, wanted: int) -> int:
	var item: ItemData = bag.definition(id)
	if _busy or item == null or wanted <= 0 or item.category == &"tool": return 0
	var amount: int = mini(mini(wanted, bag.count_of(id)), storage.capacity_for(id, item.max_stack))
	if amount <= 0: return 0
	_busy = true
	bag.begin_update()
	if bag.remove_item(id, amount): storage.add(id, amount, item.max_stack)
	else: amount = 0
	bag.end_update()
	_busy = false
	return amount


func withdraw(id: StringName, wanted: int) -> int:
	var item: ItemData = bag.definition(id)
	if _busy or item == null or wanted <= 0: return 0
	var amount: int = mini(wanted, storage.count_of(id))
	while amount > 0 and not bag.has_space_for(id, amount): amount -= 1
	if amount <= 0: return 0
	_busy = true
	bag.begin_update()
	if storage.remove(id, amount): bag.add_item(id, amount, &"transfer")
	else: amount = 0
	bag.end_update()
	_busy = false
	return amount
