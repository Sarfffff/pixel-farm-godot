extends RefCounted
## 唯一的动态实例与每箱仓储事实，不保存Node或回调。

const Store := preload("res://scripts/inventory/stack_store.gd")
var next_id: int = 1
var _records: Dictionary[String, Dictionary] = {}
var _stores: Dictionary[String, RefCounted] = {}


func instance(id: String) -> Dictionary:
	if not _records.has(id): return {}
	var record: Dictionary = _records[id].duplicate(true)
	record.slots = _stores[id].slots.duplicate(true) if _stores.has(id) else []
	return record


func instances() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _records.keys()
	ids.sort()
	for id: String in ids: result.append(instance(id))
	return result


func store(id: String) -> RefCounted:
	return _stores.get(id)


func put(record: Dictionary, definition: Resource, bag: Inventory) -> void:
	var id: String = record.id
	_records[id] = record.duplicate(true)
	if definition.storage_capacity > 0 and not _stores.has(id):
		var storage := Store.new(definition.storage_capacity)
		storage.restore(record.slots, bag)
		_stores[id] = storage


func erase(id: String) -> void:
	_records.erase(id)
	_stores.erase(id)


func replace(records: Array, next: int, definitions: Dictionary, bag: Inventory) -> void:
	_records.clear()
	_stores.clear()
	next_id = next
	for record: Dictionary in records: put(record, definitions[StringName(record.type_id)], bag)


func encode() -> Dictionary:
	return {"schema": 1, "next_id": next_id, "instances": instances()}
