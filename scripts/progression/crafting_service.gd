extends RefCounted
## 第一章工作台的最小即时制作用例；配方、资格和结算均独立于界面。

signal changed
signal crafted(id: StringName)
signal save_failed

var busy: bool = false
var save_pending: bool = false
var _bag: Inventory
var _unlocked: Callable
var _save: Callable
var _recipes: Array[CraftingRecipeData] = []


func configure(bag: Inventory, unlocked: Callable, save: Callable) -> void:
	if busy: return
	_bag = bag
	_unlocked = unlocked
	_save = save
	_recipes.clear()
	for file: String in ResourceLoader.list_directory("res://data/recipes"):
		if not file.ends_with(".tres"): continue
		var recipe := load("res://data/recipes/" + file) as CraftingRecipeData
		if recipe != null and recipe.is_valid():
			_recipes.append(recipe)
	_recipes.sort_custom(func(a: CraftingRecipeData, b: CraftingRecipeData) -> bool: return String(a.id) < String(b.id))


func unlocked() -> bool:
	return _unlocked.is_valid() and bool(_unlocked.call())


func recipes() -> Array[CraftingRecipeData]:
	return _recipes.duplicate()


func hint(id: StringName) -> String:
	if busy: return "正在制作，请稍候"
	if not unlocked(): return "完成第一章「把灯点起来」后开放种子工作台"
	var recipe: CraftingRecipeData = _find(id)
	if recipe == null or _bag == null: return "配方暂不可用"
	for item: StringName in recipe.ingredients:
		if Inventory.TOOL_IDS.has(item) or _bag.definition(item) == null or _bag.count_of(item) < recipe.ingredients[item]:
			return "材料不足：%s ×%d" % [_bag.item_name(item), recipe.ingredients[item]]
	if not _bag.has_space_for_batch(recipe.products): return "背包放不下成品，请先整理背包"
	return ""


func craft(id: StringName) -> bool:
	if not hint(id).is_empty(): return false
	busy = true
	var recipe: CraftingRecipeData = _find(id)
	_bag.begin_update()
	for item: StringName in recipe.ingredients:
		_bag.remove_item(item, recipe.ingredients[item])
	for item: StringName in recipe.products:
		_bag.add_item(item, recipe.products[item], &"crafting")
	_bag.end_update()
	crafted.emit(id)
	changed.emit()
	save_pending = _save.is_valid() and not bool(_save.call())
	if save_pending: save_failed.emit()
	busy = false
	return true


func _find(id: StringName) -> CraftingRecipeData:
	for recipe: CraftingRecipeData in _recipes:
		if recipe.id == id: return recipe
	return null


func confirm_saved() -> void:
	if save_pending:
		save_pending = false
		changed.emit()


func release() -> void:
	if busy: return
	_bag = null
	_unlocked = Callable()
	_save = Callable()
	_recipes.clear()
