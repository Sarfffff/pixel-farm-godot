extends Node
## 每实例储物箱MVP；复用服务中的StackStore与StorageTransferService。

signal manage_requested(id: String)
var _service: RefCounted
var _bag: Inventory
var _view: Control
var _id: String = ""
var _message: String = ""


func configure(service: RefCounted, bag: Inventory, view: Control) -> void:
	disconnect_bindings()
	_service = service
	_bag = bag
	_view = view
	_service.changed.connect(refresh)
	_bag.changed.connect(refresh)
	_view.deposit_requested.connect(_deposit)
	_view.withdraw_requested.connect(_withdraw)
	_view.retry_save_requested.connect(_retry)
	_view.manage_requested.connect(_manage)
	_view.closed.connect(_closed)


func open_storage(id: String) -> void:
	if _service == null or not is_instance_valid(_view): return
	var record: Dictionary = _service.instance(id)
	if record.is_empty() or _service.definition(StringName(record.type_id)).storage_capacity <= 0: return
	_id = id
	_message = ""
	_view.set_open(true)
	refresh()


func snapshot() -> Dictionary:
	var data: Dictionary = {"bag": [], "storage": [], "message": _message, "save_pending": _service.save_pending}
	for item: ItemData in _bag.definitions():
		var owned: int = _bag.count_of(item.id)
		var stored: int = _service.storage_count(_id, item.id)
		if owned > 0 and item.category != &"tool": data.bag.append({"id": item.id, "text": "%s ×%d" % [item.display_name, owned], "icon": item.icon})
		if stored > 0: data.storage.append({"id": item.id, "text": "%s ×%d" % [item.display_name, stored], "icon": item.icon})
	return data


func refresh() -> void:
	if _service == null or not is_instance_valid(_view): return
	if not _id.is_empty() and _service.instance(_id).is_empty():
		_view.set_open(false)
		_id = ""
	_view.render(snapshot())


func _deposit(item: StringName, all: bool) -> void:
	if not is_instance_valid(_view) or not _view.visible: return
	var data: ItemData = _bag.definition(item)
	if data == null: return
	var count: int = data.max_stack if all else 1
	_message = "已存入物品" if _service.deposit(_id, item, count) > 0 else "没有可存入的物品或箱子已满"
	refresh()


func _withdraw(item: StringName, all: bool) -> void:
	if not is_instance_valid(_view) or not _view.visible: return
	var data: ItemData = _bag.definition(item)
	if data == null: return
	var count: int = data.max_stack if all else 1
	_message = "已取出物品" if _service.withdraw(_id, item, count) > 0 else "背包已满或箱子没有该物品"
	refresh()


func _retry() -> void:
	_service.retry_save()
	refresh()


func _closed() -> void:
	_id = ""


func _manage() -> void:
	if not is_instance_valid(_view) or not _view.visible or _id.is_empty(): return
	var id: String = _id
	_view.set_open(false)
	manage_requested.emit(id)


func disconnect_bindings() -> void:
	if _service != null and _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)
	if is_instance_valid(_bag) and _bag.changed.is_connected(refresh): _bag.changed.disconnect(refresh)
	if is_instance_valid(_view):
		_view.set_open(false)
		for pair: Array in [[_view.deposit_requested, _deposit], [_view.withdraw_requested, _withdraw], [_view.retry_save_requested, _retry], [_view.manage_requested, _manage], [_view.closed, _closed]]:
			var event: Signal = pair[0]
			if event.is_connected(pair[1]): event.disconnect(pair[1])
	_service = null
	_bag = null
	_view = null
	_id = ""


func _exit_tree() -> void:
	disconnect_bindings()
