extends RefCounted
## 世界对象持久化集合：稳定 ID、初始模板和状态分开；恢复不会调用掉落或交易逻辑。

var _records: Dictionary = {}
signal object_restored(object: Node2D)


func clear() -> void:
	_records.clear()


func register_object(object: Node2D) -> void:
	var key: StringName = object.persistence_id()
	assert(not _records.has(key), "duplicate persistent world ID: " + String(key))
	var packed := PackedScene.new()
	assert(packed.pack(object) == OK, "cannot capture world template")
	_records[key] = {&"node": object, &"parent": object.get_parent(), &"template": packed, &"initial": object.to_dict()}


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in _records:
		var object: Node = _records[key].node if is_instance_valid(_records[key].node) else null
		result[key] = object.to_dict() if is_instance_valid(object) and not object.is_queued_for_deletion() else {&"cleared": true}
	return result


func from_dict(data: Dictionary) -> void:
	for key: StringName in _records:
		var record: Dictionary = _records[key]
		var saved: Variant = data.get(String(key), record.initial)
		var state: Dictionary = saved if saved is Dictionary else record.initial
		var object: Node2D = record.node if is_instance_valid(record.node) else null
		if object != null:
			# 按初始模板重建，避免从树桩恢复完整树时遗留形状、缩放或碰撞状态。
			object.get_parent().remove_child(object)
			object.queue_free()
			object = null
			record.node = null
		if bool(state.get("cleared", false)):
			continue
		if object == null:
			object = record.template.instantiate() as Node2D
			record.parent.add_child(object)
			record.node = object
		object.from_dict(state)
		object_restored.emit(object)
