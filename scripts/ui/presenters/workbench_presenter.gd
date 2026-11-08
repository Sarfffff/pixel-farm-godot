extends Node
## 制作显示与意图适配；资格、数量、容量和交易在服务内。

var _service: RefCounted
var _bag: Inventory
var _view: Control
var _message: String = ""


func configure(service: RefCounted, bag: Inventory, view: Control) -> void:
	dispose()
	_service = service
	_bag = bag
	_view = view
	bag.changed.connect(refresh)
	view.craft_requested.connect(_craft)
	service.save_failed.connect(_save_failed)
	service.changed.connect(refresh)
	view.tree_exiting.connect(dispose)
	refresh()


func open() -> void:
	if not is_instance_valid(_view): return
	_message = ""
	refresh()
	_view.set_open(true)


func refresh() -> void:
	if not is_instance_valid(_view) or _service == null: return
	var rows: Array[Dictionary] = []
	for recipe: CraftingRecipeData in _service.recipes():
		var ingredients: PackedStringArray = []
		var products: PackedStringArray = []
		for item: StringName in recipe.ingredients:
			ingredients.append("%s %d/%d" % [_bag.item_name(item), _bag.count_of(item), recipe.ingredients[item]])
		for item: StringName in recipe.products:
			products.append("%s ×%d" % [_bag.item_name(item), recipe.products[item]])
		var reason: String = _service.hint(recipe.id)
		rows.append({"id": recipe.id, "title": recipe.title, "text": "、".join(ingredients) + " → " + "、".join(products), "hint": reason, "available": reason.is_empty()})
	var message: String = "制作已结算，但保存失败，请手动重试保存。" if _service.save_pending else _message
	_view.render({"recipes": rows, "message": message if not message.is_empty() else "收获留种，再投入下一轮种植。" if _service.unlocked() else "完成第一章「把灯点起来」后开放。"})


func _craft(id: StringName) -> void:
	_message = "制作完成，成品已放入背包。" if _service.craft(id) else _service.hint(id)
	refresh()


func _save_failed() -> void:
	refresh()


func _exit_tree() -> void:
	dispose()


func dispose() -> void:
	if is_instance_valid(_bag) and _bag.changed.is_connected(refresh): _bag.changed.disconnect(refresh)
	if is_instance_valid(_view) and _view.craft_requested.is_connected(_craft): _view.craft_requested.disconnect(_craft)
	if is_instance_valid(_view) and _view.tree_exiting.is_connected(dispose): _view.tree_exiting.disconnect(dispose)
	if is_instance_valid(_service) and _service.save_failed.is_connected(_save_failed): _service.save_failed.disconnect(_save_failed)
	if is_instance_valid(_service) and _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)
	_service = null
	_bag = null
	_view = null
