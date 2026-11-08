extends RefCounted
## 即时配方用例。唯一库存负责净容量和原子交换；资格由组合根注入。

signal changed
signal crafted(id: StringName)
signal batch_crafted(id: StringName, batches: int)
signal save_failed

const MAX_BATCHES: int = 999
const MAX_ITEM_AMOUNT: int = CraftingRecipeData.MAX_ITEM_AMOUNT

var busy: bool = false
var save_pending: bool = false
var last_rejection: String = ""
var _bag: Inventory
var _chapter_unlocked: Callable
var _save: Callable
var _access: Callable
var _product_available: Callable
var _recipes: Dictionary[StringName, CraftingRecipeData] = {}
var _querying: bool = false
var _publishing: bool = false
var _released: bool = false


## 后两个端口可省略以兼容第一章；设备配方缺资格/放置端口时关闭。
func configure(bag: Inventory, chapter_unlocked: Callable, save: Callable, recipe_access: Callable = Callable(), product_available: Callable = Callable()) -> void:
	if _mutation_blocked(): return
	_bag = bag
	_chapter_unlocked = chapter_unlocked
	_save = save
	_access = recipe_access
	_product_available = product_available
	_recipes.clear()
	for file: String in ResourceLoader.list_directory("res://data/recipes"):
		if not file.ends_with(".tres"): continue
		var recipe := load("res://data/recipes/" + file) as CraftingRecipeData
		if recipe != null: _register(recipe)
	_publish_changed()


func register_recipe(recipe: CraftingRecipeData) -> bool:
	if _mutation_blocked() or not _register(recipe): return false
	_publish_changed()
	return true


func _register(recipe: CraftingRecipeData) -> bool:
	if recipe == null or not recipe.is_valid() or _recipes.has(recipe.id): return false
	_recipes[recipe.id] = recipe.duplicate(true) as CraftingRecipeData
	return true


func recipes() -> Array[CraftingRecipeData]:
	var result: Array[CraftingRecipeData] = []
	var ids: Array = _recipes.keys()
	ids.sort()
	for id: StringName in ids: result.append(_recipes[id].duplicate(true) as CraftingRecipeData)
	return result


## 兼容固定工作台交互提示；不是对全部通用配方的资格结论。
func unlocked() -> bool:
	if _released or _querying: return false
	_querying = true
	var value: bool = _chapter_ready()
	_querying = false
	return value


## 主线程连接技能/能力变化；不接管或复制技能服务的状态和信号。
func refresh_access() -> bool:
	if _mutation_blocked(): return false
	_publish_changed()
	return true


func catalog(include_unknown: bool = false) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _released or _querying: return rows
	_querying = true
	var ids: Array = _recipes.keys()
	ids.sort()
	for id: StringName in ids:
		var recipe: CraftingRecipeData = _recipes[id]
		var access: Dictionary = _eligibility(recipe)
		if not include_unknown and not access.known: continue
		rows.append({"id": id, "title": recipe.title, "purpose": recipe.purpose, "unlock_source": recipe.unlock_source, "known": access.known, "available": access.available, "reason": access.reason})
	_querying = false
	return rows


func preview(id: StringName, batches: Variant = 1) -> Dictionary:
	if _released or _querying: return _empty_preview(id, batches, "制作服务暂不可用")
	_querying = true
	var result: Dictionary = _preview(id, batches)
	_querying = false
	return result


func hint(id: StringName, batches: Variant = 1) -> String:
	if busy or _publishing: return "正在制作，请稍候"
	return String(preview(id, batches).reason)


func limits(id: StringName) -> Dictionary:
	var result: Dictionary = {"max_material": 0, "max_craftable": 0, "batch_limit": MAX_BATCHES}
	if _released or _querying: return result
	_querying = true
	var recipe: CraftingRecipeData = _recipes.get(id)
	if recipe != null and is_instance_valid(_bag):
		var upper: int = MAX_BATCHES
		for item: StringName in recipe.ingredients:
			upper = mini(upper, int(_bag.count_of(item) / recipe.ingredients[item]))
		result.max_material = upper
		for amounts: Dictionary in [recipe.ingredients, recipe.products]:
			for item: StringName in amounts: upper = mini(upper, int(MAX_ITEM_AMOUNT / int(amounts[item])))
		if _eligibility(recipe).available and _ports_ready():
			# 消耗整堆材料可腾格，1批失败而2批成功；不可按前缀可制作性二分。
			for batches: int in range(upper, 0, -1):
				if _exchange_preview(_scaled(recipe.ingredients, batches), _scaled(recipe.products, batches)).ok:
					result.max_craftable = batches
					break
	_querying = false
	return result


## Variant 入口严格拒绝 bool/小数/字符串，避免隐式转换后制造数量。
func craft(id: StringName, batches: Variant = 1) -> bool:
	if _mutation_blocked(): return false
	busy = true
	_querying = true
	var plan: Dictionary = _preview(id, batches)
	_querying = false
	last_rejection = plan.reason
	if not plan.ok:
		busy = false
		return false
	_bag.begin_update()
	var exchanged: bool = bool(_bag.call(&"exchange_batch", plan.consumed, plan.produced, &"crafting"))
	if not exchanged:
		_bag.end_update()
		last_rejection = "材料或背包状态已变化，请重新确认"
		busy = false
		return false
	# Inventory.exchange_batch已完成全部提交；外层合并边界只负责同步通知。
	_bag.end_update()
	crafted.emit(id)
	batch_crafted.emit(id, int(batches))
	_persist()
	busy = false
	_publish_changed()
	return true


func retry_save() -> bool:
	if _mutation_blocked(): return false
	if not save_pending: return true
	busy = true
	_persist()
	busy = false
	_publish_changed()
	return not save_pending


func confirm_saved() -> void:
	if not save_pending or _released: return
	save_pending = false
	if not busy and not _querying and not _publishing: _publish_changed()


func release() -> void:
	if _mutation_blocked(): return
	_released = true
	_bag = null
	_chapter_unlocked = Callable()
	_save = Callable()
	_access = Callable()
	_product_available = Callable()
	_recipes.clear()


func _preview(id: StringName, batches: Variant) -> Dictionary:
	var result: Dictionary = _empty_preview(id, batches, "配方暂不可用")
	var recipe: CraftingRecipeData = _recipes.get(id)
	if recipe == null: return result
	var access: Dictionary = _eligibility(recipe)
	result.known = access.known
	result.available = access.available
	result.title = recipe.title
	result.purpose = recipe.purpose
	result.unlock_source = recipe.unlock_source
	if typeof(batches) != TYPE_INT or batches < 1 or batches > MAX_BATCHES:
		result.reason = "制作批数必须为1至%d的整数" % MAX_BATCHES
		return result
	for amounts: Dictionary in [recipe.ingredients, recipe.products]:
		for item: StringName in amounts:
			if int(amounts[item]) > int(MAX_ITEM_AMOUNT / int(batches)):
				result.reason = "本次制作数量过大"
				return result
	result.consumed = _scaled(recipe.ingredients, int(batches))
	result.produced = _scaled(recipe.products, int(batches))
	if is_instance_valid(_bag):
		for item: StringName in result.consumed:
			var need: int = result.consumed[item]
			var have: int = _bag.count_of(item)
			result.ingredients.append({"id": item, "name": _bag.item_name(item), "required": need, "have": have, "missing": maxi(0, need - have)})
		for item: StringName in result.produced:
			result.products.append({"id": item, "name": _bag.item_name(item), "count": result.produced[item]})
	if not access.available:
		result.reason = access.reason
		return result
	if not _ports_ready():
		result.reason = "制作库存端口尚未接入"
		return result
	var check: Dictionary = _exchange_preview(result.consumed, result.produced)
	result.ok = check.ok
	result.reason = check.reason
	return result


func _eligibility(recipe: CraftingRecipeData) -> Dictionary:
	var result: Dictionary = {"known": recipe.requires_chapter, "available": false, "reason": "尚未学会此配方"}
	if _access.is_valid():
		var raw: Variant = _access.call(recipe.id)
		if raw is Dictionary and typeof(raw.get("known")) == TYPE_BOOL and typeof(raw.get("available")) == TYPE_BOOL:
			result.known = raw.known
			result.available = raw.known and raw.available
			result.reason = String(raw.get("reason", "资格尚未满足")) if raw.get("reason", "") is String else "资格尚未满足"
		else:
			result.known = false
	else:
		result.available = recipe.requires_chapter
	if recipe.requires_chapter and not _chapter_ready():
		result.available = false
		result.reason = "完成第一章「把灯点起来」后开放种子工作台"
	if not result.known:
		result.available = false
		if result.reason.is_empty(): result.reason = "尚未学会此配方"
	if not is_instance_valid(_bag):
		result.available = false
		result.reason = "背包暂不可用"
	if result.available:
		for item: StringName in recipe.ingredients:
			if Inventory.TOOL_IDS.has(item) or _bag.definition(item) == null:
				result.available = false
				result.reason = "配方材料暂不可用"
		for item: StringName in recipe.products:
			if Inventory.TOOL_IDS.has(item) or _bag.definition(item) == null:
				result.available = false
				result.reason = "配方成品尚未接入"
			elif recipe.requires_placement and (not _product_available.is_valid() or not bool(_product_available.call(item))):
				result.available = false
				result.reason = "该成品的放置与使用功能尚未开放"
	if recipe.duration_seconds > 0.0:
		result.available = false
		result.reason = "此配方需要尚未接入的生产设备"
	if result.available: result.reason = ""
	elif result.reason.is_empty(): result.reason = "配方资格尚未满足"
	return result


func _chapter_ready() -> bool:
	return _chapter_unlocked.is_valid() and bool(_chapter_unlocked.call())


func _ports_ready() -> bool:
	return is_instance_valid(_bag) and _bag.has_method(&"preview_exchange_batch") and _bag.has_method(&"exchange_batch")


func _exchange_preview(consumed: Dictionary, produced: Dictionary) -> Dictionary:
	var raw: Variant = _bag.call(&"preview_exchange_batch", consumed, produced)
	if not raw is Dictionary or typeof(raw.get("ok")) != TYPE_BOOL: return {"ok": false, "reason": "背包预演暂不可用"}
	return {"ok": raw.ok, "reason": "" if raw.ok else String(raw.get("reason", "材料不足或背包放不下成品"))}


func _scaled(items: Dictionary, batches: int) -> Dictionary:
	var result: Dictionary = {}
	for id: StringName in items: result[id] = int(items[id]) * batches
	return result


func _empty_preview(id: StringName, batches: Variant, reason: String) -> Dictionary:
	return {"id": id, "batches": batches, "known": false, "available": false, "ok": false, "reason": reason, "title": "", "purpose": "", "unlock_source": "", "consumed": {}, "produced": {}, "ingredients": [], "products": []}


func _persist() -> void:
	save_pending = not _save.is_valid() or not bool(_save.call())
	if save_pending: save_failed.emit()


func _mutation_blocked() -> bool:
	return busy or _querying or _publishing or _released


func _publish_changed() -> void:
	_publishing = true
	changed.emit()
	_publishing = false
