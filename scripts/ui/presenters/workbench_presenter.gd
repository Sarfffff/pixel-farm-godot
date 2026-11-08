extends Node
## 制作MVP：显示服务的只读预演，不计算资格、材料倍率或容量。

var _service: RefCounted
var _bag: Inventory
var _view: Control
var _message: String = ""
var _selected: StringName = &"carrot_seed_pack"
var _batches: int = 1
var _refreshing: bool = false


func configure(service: RefCounted, bag: Inventory, view: Control) -> void:
	dispose()
	_service = service
	_bag = bag
	_view = view
	bag.changed.connect(refresh)
	service.changed.connect(refresh)
	service.save_failed.connect(_save_failed)
	view.craft_requested.connect(_craft)
	view.batch_craft_requested.connect(_craft_batch)
	view.recipe_selected.connect(_select)
	view.quantity_changed.connect(_quantity)
	view.max_requested.connect(_maximum)
	view.retry_save_requested.connect(_retry_save)
	view.tree_exiting.connect(dispose)
	refresh()


func open() -> void:
	if not is_instance_valid(_view): return
	_message = ""
	refresh()
	_view.set_open(true)


func refresh() -> void:
	# 事务期间库存端口仍持有交换锁，统一等待服务末尾的changed再渲染最终预演。
	if _refreshing or not is_instance_valid(_view) or _service == null or _service.busy: return
	_refreshing = true
	var rows: Array[Dictionary] = _service.catalog()
	if not rows.any(func(row: Dictionary) -> bool: return row.id == _selected):
		_selected = rows[0].id if not rows.is_empty() else &""
	var detail: Dictionary = _service.preview(_selected, _batches)
	var limits: Dictionary = _service.limits(_selected)
	var materials: PackedStringArray = []
	var products: PackedStringArray = []
	for row: Dictionary in detail.ingredients:
		materials.append("%s：需要%d / 持有%d%s" % [row.name, row.required, row.have, " / 缺%d" % row.missing if int(row.missing) > 0 else ""])
	for row: Dictionary in detail.products: products.append("%s ×%d" % [row.name, row.count])
	var message: String = "制作已结算，但保存失败。可重试保存，成品不会重复发放。" if _service.save_pending else _message
	_view.render({"recipes": rows, "selected": _selected, "batches": _batches, "batch_limit": limits.batch_limit, "max_material": limits.max_material, "max_craftable": limits.max_craftable, "detail": detail, "materials_text": "\n".join(materials), "products_text": "、".join(products), "message": message if not message.is_empty() else "选择已知配方，确认批数、材料缺口和成品。", "save_pending": _service.save_pending})
	_refreshing = false


func _craft(id: StringName) -> void:
	_craft_batch(id, 1)


func _craft_batch(id: StringName, batches: int) -> void:
	if _service == null: return
	_selected = id
	_batches = batches
	_message = "制作完成，成品已放入背包。" if _service.craft(id, batches) else _service.last_rejection
	refresh()


func _select(id: StringName) -> void:
	_selected = id
	_batches = 1
	_message = ""
	refresh()


func _quantity(batches: int) -> void:
	_batches = batches
	_message = ""
	refresh()


func _maximum() -> void:
	if _service == null: return
	var limit: Dictionary = _service.limits(_selected)
	if int(limit.max_craftable) > 0: _batches = int(limit.max_craftable)
	refresh()


func _retry_save() -> void:
	if _service == null: return
	# 失败提示只由save_pending推导，避免稍后手动保存成功还残留旧失败文字。
	_message = "保存成功。" if _service.retry_save() else ""
	refresh()


func _save_failed() -> void:
	refresh()


func _exit_tree() -> void:
	dispose()


func dispose() -> void:
	if is_instance_valid(_bag) and _bag.changed.is_connected(refresh): _bag.changed.disconnect(refresh)
	if is_instance_valid(_service):
		if _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)
		if _service.save_failed.is_connected(_save_failed): _service.save_failed.disconnect(_save_failed)
	if is_instance_valid(_view):
		for binding: Array in [[&"craft_requested", _craft], [&"batch_craft_requested", _craft_batch], [&"recipe_selected", _select], [&"quantity_changed", _quantity], [&"max_requested", _maximum], [&"retry_save_requested", _retry_save], [&"tree_exiting", dispose]]:
			if _view.is_connected(binding[0], binding[1]): _view.disconnect(binding[0], binding[1])
	_service = null
	_bag = null
	_view = null
