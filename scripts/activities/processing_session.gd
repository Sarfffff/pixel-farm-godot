extends RefCounted
## 一台加工设备的纯运行状态；不创建界面、场景或保存文件。

var ready_day: int = 0
var _busy: bool = false


func start(day: int, bag: Inventory, recipe: Resource) -> bool:
	if _busy or ready_day > 0 or bag.count_of(recipe.ingredient) < recipe.ingredient_count: return false
	_busy = true
	bag.begin_update()
	var accepted: bool = bag.remove_item(recipe.ingredient, recipe.ingredient_count)
	if accepted: ready_day = day + maxi(1, recipe.days)
	bag.end_update()
	_busy = false
	return accepted


func collect(day: int, bag: Inventory, recipe: Resource) -> bool:
	if _busy or ready_day <= 0 or ready_day > day or not bag.has_space_for(recipe.product, recipe.product_count): return false
	_busy = true
	bag.begin_update()
	var accepted: bool = bag.add_item(recipe.product, recipe.product_count) == 0
	if accepted: ready_day = 0
	bag.end_update()
	_busy = false
	return accepted
