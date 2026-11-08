extends RefCounted
## 可信设备工厂/引擎适配，由组合根注入，不读取存档中的场景路径。

signal interacted(id: String)
signal obstacle_changed
const Instance := preload("res://scripts/world/interactions/device_instance.gd")
var _parent: Node2D
var _position: Callable
var _nodes: Dictionary[String, Node2D] = {}
var _obstacle_pending: bool = false


func configure(parent: Node2D, cell_to_world: Callable) -> void:
	_parent = parent
	_position = cell_to_world


func node_for(id: String) -> Node2D:
	return _nodes.get(id)


func create(definition: Resource, record: Dictionary) -> bool:
	if _nodes.has(record.id): return false
	var node: Node2D = _prepare(definition, record)
	if node == null: return false
	_publish(node)
	return true


func update_instance(record: Dictionary) -> bool:
	var node: Node2D = _nodes.get(record.id)
	if not is_instance_valid(node) or not _position.is_valid(): return false
	var definition: Resource = node.get_meta(&"device_definition")
	node.configure(definition, record, _parent.to_local(_position.call(Vector2i(record.cell[0], record.cell[1]))))
	_obstacle_changed()
	return true


func remove_instance(id: String) -> void:
	var node: Node2D = _nodes.get(id)
	_nodes.erase(id)
	if is_instance_valid(node):
		if node.interacted.is_connected(_interact): node.interacted.disconnect(_interact)
		if node.get_parent() != null: node.get_parent().remove_child(node)
		node.queue_free()
		_obstacle_changed()


func restore_instances(definitions: Dictionary, records: Array) -> bool:
	var candidates: Array[Node2D] = []
	for record: Dictionary in records:
		var definition: Resource = definitions.get(StringName(record.type_id))
		var node: Node2D = _prepare(definition, record)
		if node == null:
			for candidate: Node2D in candidates: candidate.free()
			return false
		candidates.append(node)
	if not is_instance_valid(_parent): return false
	for id: String in _nodes.keys(): remove_instance(id)
	for candidate: Node2D in candidates: _publish(candidate)
	_obstacle_changed()
	return true


func release() -> void:
	for id: String in _nodes.keys(): remove_instance(id)
	_parent = null
	_position = Callable()


func _prepare(definition: Resource, record: Dictionary) -> Node2D:
	if not is_instance_valid(_parent) or not _position.is_valid() or definition == null or not definition.is_valid(): return null
	var node := Instance.new()
	node.name = record.id
	node.set_meta(&"device_definition", definition)
	node.configure(definition, record, _parent.to_local(_position.call(Vector2i(record.cell[0], record.cell[1]))))
	return node


func _publish(node: Node2D) -> void:
	_nodes[node.instance_id] = node
	_parent.add_child(node)
	node.interacted.connect(_interact)
	_obstacle_changed()


func _interact(id: String) -> void:
	interacted.emit(id)


func _obstacle_changed() -> void:
	if _obstacle_pending: return
	_obstacle_pending = true
	_emit_obstacle_changed.call_deferred()


func _emit_obstacle_changed() -> void:
	_obstacle_pending = false
	obstacle_changed.emit()
