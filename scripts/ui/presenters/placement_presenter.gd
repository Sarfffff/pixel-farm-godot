extends Node
## 只整理预览与转交意图；规则、库存和持久化均在应用服务。

signal preview_changed(snapshot: Dictionary)
var _service: RefCounted
var _view: Control
var _type: StringName = &""
var _cell: Vector2i
var _facing: int = 0
var _moving: String = ""
var _message: String = ""


func configure(service: RefCounted, view: Control) -> void:
	disconnect_bindings()
	_service = service
	_view = view
	_service.changed.connect(refresh)
	_view.type_selected.connect(_select)
	_view.rotate_requested.connect(_rotate)
	_view.commit_requested.connect(_commit)
	_view.dismantle_requested.connect(_dismantle)
	_view.retry_save_requested.connect(_retry)
	_view.closed.connect(_closed)


func open_place(type_id: StringName, cell: Vector2i) -> void:
	if not is_instance_valid(_view): return
	_type = type_id
	_cell = cell
	_facing = 0
	_moving = ""
	_message = ""
	_view.set_open(true)
	refresh()


func open_move(id: String) -> void:
	if _service == null or not is_instance_valid(_view): return
	var record: Dictionary = _service.instance(id)
	if record.is_empty(): return
	_type = StringName(record.type_id)
	_cell = Vector2i(record.cell[0], record.cell[1])
	_facing = record.facing
	_moving = id
	_message = ""
	_view.set_open(true)
	refresh()


func set_target(cell: Vector2i) -> void:
	_cell = cell
	_message = ""
	refresh()


func snapshot() -> Dictionary:
	var data: Dictionary = _service.preview(_type, &"home", _cell, _facing, _moving)
	data.catalog = []
	for definition: Resource in _service.definitions(): data.catalog.append({"id": definition.id, "title": definition.title})
	data.moving = not _moving.is_empty()
	data.save_pending = _service.save_pending
	if not _message.is_empty(): data.reason = _message
	return data


func refresh() -> void:
	if _service == null or not is_instance_valid(_view): return
	var data: Dictionary = snapshot()
	_view.render(data)
	preview_changed.emit(data if _view.visible else {})


func _select(type_id: StringName) -> void:
	_type = type_id
	_message = ""
	refresh()


func _rotate() -> void:
	_facing = (_facing + 1) % 4
	_message = ""
	refresh()


func _commit() -> void:
	if not is_instance_valid(_view) or not _view.visible: return
	var success: bool = _service.move(_moving, &"home", _cell, _facing) if not _moving.is_empty() else not _service.place(_type, &"home", _cell, _facing).is_empty()
	_message = "设备已移动" if success and not _moving.is_empty() else "设备已放置" if success else _service.last_rejection
	if success: _view.set_open(false)
	refresh()


func _dismantle() -> void:
	if not is_instance_valid(_view) or not _view.visible: return
	if _service.dismantle(_moving): _view.set_open(false)
	else: _message = _service.last_rejection
	refresh()


func _retry() -> void:
	_service.retry_save()
	refresh()


func _closed() -> void:
	preview_changed.emit({})


func disconnect_bindings() -> void:
	if _service != null and _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)
	if is_instance_valid(_view):
		_view.set_open(false)
		for pair: Array in [[_view.type_selected, _select], [_view.rotate_requested, _rotate], [_view.commit_requested, _commit], [_view.dismantle_requested, _dismantle], [_view.retry_save_requested, _retry], [_view.closed, _closed]]:
			var event: Signal = pair[0]
			if event.is_connected(pair[1]): event.disconnect(pair[1])
	preview_changed.emit({})
	_service = null
	_view = null


func _exit_tree() -> void:
	disconnect_bindings()
