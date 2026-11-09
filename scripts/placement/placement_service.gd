extends RefCounted
## 摆放/移动/拆除和独立仓储事务。整个通知与保存期间均持有重入锁。

signal changed
signal placed(id: String)
signal moved(id: String)
signal removed(id: String)
signal save_failed
signal restore_failed(reason: String)

const Registry := preload("res://scripts/placement/device_registry.gd")
const Snapshot := preload("res://scripts/placement/device_snapshot.gd")
const Transfer := preload("res://scripts/inventory/storage_transfer_service.gd")
const Definition := preload("res://scripts/data/device_definition.gd")
var busy: bool = false
var save_pending: bool = false
var last_rejection: String = ""
var _bag: Inventory
var _definitions: Dictionary[StringName, Resource] = {}
var _ports: Dictionary = {}
var _state := Registry.new()
var _lock_provider: Callable = Callable()


func configure(bag: Inventory, catalog: Array, ports: Dictionary) -> void:
	if busy: return
	_bag = bag
	_ports = ports.duplicate()
	_definitions.clear()
	for definition: Resource in catalog:
		if definition is Definition and definition.is_valid() and not _definitions.has(definition.id):
			_definitions[definition.id] = definition


## 外部状态锁端口：由组合根接线，device_id -> 非空原因表示禁止移动/拆除。
func set_lock_provider(provider: Callable) -> void:
	_lock_provider = provider


func definitions() -> Array[Resource]:
	var result: Array[Resource] = []
	result.assign(_definitions.values())
	return result


func definition(type_id: StringName) -> Resource:
	return _definitions.get(type_id)


func type_for_item(item_id: StringName) -> StringName:
	for data: Resource in _definitions.values():
		if data.placement_item_id == item_id: return data.id
	return &""


func instance(id: String) -> Dictionary:
	return _state.instance(id)


func instances() -> Array[Dictionary]:
	return _state.instances()


func occupied_cells(space_id: StringName, ignore_id: String = "") -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for record: Dictionary in instances():
		if record.id != ignore_id and StringName(record.space_id) == space_id:
			result.append_array(definition(StringName(record.type_id)).cells(Vector2i(record.cell[0], record.cell[1]), record.facing))
	return result


func preview(type_id: StringName, space_id: StringName, cell: Vector2i, facing: int, ignore_id: String = "") -> Dictionary:
	if busy: return _preview(type_id, space_id, cell, facing, ignore_id, false)
	busy = true
	var result: Dictionary = _preview(type_id, space_id, cell, facing, ignore_id, true)
	busy = false
	return result


func _preview(type_id: StringName, space_id: StringName, cell: Vector2i, facing: int, ignore_id: String, internal: bool) -> Dictionary:
	var data: Resource = definition(type_id)
	var cells: Array[Vector2i] = []
	if data != null: cells.assign(data.cells(cell, facing))
	var result: Dictionary = {"ok": false, "reason": "", "cells": cells, "type_id": type_id, "space_id": space_id, "cell": cell, "facing": facing, "ignore_id": ignore_id}
	if busy and not internal: result.reason = "正在处理设备，请稍候"
	elif data == null or _bag == null: result.reason = "设备配置不可用"
	elif space_id != &"home": result.reason = "目前只能在主农场摆放"
	elif facing < 0 or facing > 3 or absi(cell.x) > 4096 or absi(cell.y) > 4096: result.reason = "坐标或朝向无效"
	elif not ignore_id.is_empty() and instance(ignore_id).is_empty(): result.reason = "设备已不存在"
	elif ignore_id.is_empty() and (not _port("allowed").is_valid() or not bool(_port("allowed").call(data.placement_item_id))): result.reason = "尚未解锁此设备"
	else:
		result.reason = _space_reason(space_id, cells, ignore_id, false)
		if result.reason.is_empty() and ignore_id.is_empty():
			var exchange: Dictionary = _bag.preview_exchange_batch({data.placement_item_id: 1}, {})
			if not exchange.ok: result.reason = exchange.reason
		elif result.reason.is_empty(): result.reason = _locked_reason(instance(ignore_id))
	result.ok = String(result.reason).is_empty()
	return result


func place(type_id: StringName, space_id: StringName, cell: Vector2i, facing: int) -> String:
	if busy: return _reject_id("正在处理设备，请稍候")
	busy = true
	var check: Dictionary = _preview(type_id, space_id, cell, facing, "", true)
	last_rejection = check.reason
	if not check.ok:
		busy = false
		return ""
	if _state.next_id >= Snapshot.MAX_ID or instances().size() >= Snapshot.MAX_INSTANCES:
		busy = false
		return _reject_id("设备数量已达上限")
	if not _factory_ready():
		busy = false
		return _reject_id("设备表现尚未接入")
	var id: String = "device_%012d" % _state.next_id
	var data: Resource = definition(type_id)
	var record: Dictionary = {"id": id, "type_id": String(type_id), "space_id": String(space_id), "cell": [cell.x, cell.y], "facing": facing, "slots": [], "operation": Snapshot.idle_operation()}
	if not bool(_port("create").call(data, record.duplicate(true))):
		_port("remove").call(id)
		busy = false
		return _reject_id("设备创建失败，物品已保留")
	_bag.begin_update()
	if not _bag.exchange_batch({data.placement_item_id: 1}, {}, &"transfer"):
		_port("remove").call(id)
		_bag.end_update()
		busy = false
		return _reject_id("放置材料已变化，请重试")
	_state.put(record, data, _bag)
	_state.next_id += 1
	_bag.end_update()
	_finish()
	placed.emit(id)
	busy = false
	return id


func move(id: String, space_id: StringName, cell: Vector2i, facing: int) -> bool:
	var record: Dictionary = instance(id)
	if busy or record.is_empty(): return _reject("设备已不存在或正在操作")
	busy = true
	var check: Dictionary = _preview(StringName(record.type_id), space_id, cell, facing, id, true)
	last_rejection = check.reason
	if not check.ok or not _port("update").is_valid():
		busy = false
		return false
	record.cell = [cell.x, cell.y]
	record.space_id = String(space_id)
	record.facing = facing
	if not bool(_port("update").call(record.duplicate(true))):
		busy = false
		return _reject("移动失败，设备保留原位")
	_state.put(record, definition(StringName(record.type_id)), _bag)
	_finish()
	moved.emit(id)
	busy = false
	return true


func dismantle(id: String) -> bool:
	var record: Dictionary = instance(id)
	if busy or record.is_empty(): return _reject("设备已不存在或正在操作")
	last_rejection = _locked_reason(record)
	if not last_rejection.is_empty(): return false
	var data: Resource = definition(StringName(record.type_id))
	var exchange: Dictionary = _bag.preview_exchange_batch({}, {data.placement_item_id: 1})
	if not exchange.ok: return _reject("背包放不下拆回的设备，请先整理")
	if not _port("remove").is_valid(): return _reject("设备表现尚未接入")
	busy = true
	_bag.begin_update()
	if not _bag.exchange_batch({}, {data.placement_item_id: 1}, &"transfer"):
		_bag.end_update()
		busy = false
		return _reject("背包空间已变化，请重试")
	_state.erase(id)
	_port("remove").call(id)
	_bag.end_update()
	_finish()
	removed.emit(id)
	busy = false
	return true


func storage_count(id: String, item: StringName) -> int:
	var storage: RefCounted = _state.store(id)
	return storage.count_of(item) if storage != null else 0


func deposit(id: String, item: StringName, count: int) -> int:
	return _transfer(id, item, count, true)


func withdraw(id: String, item: StringName, count: int) -> int:
	return _transfer(id, item, count, false)


func _transfer(id: String, item: StringName, count: int, depositing: bool) -> int:
	if busy or _state.store(id) == null or count <= 0: return 0
	var record: Dictionary = instance(id)
	if record.operation.phase != "idle": return 0
	busy = true
	var transfer := Transfer.new()
	transfer.bag = _bag
	transfer.storage = _state.store(id)
	var amount: int = transfer.deposit(item, count) if depositing else transfer.withdraw(item, count)
	transfer.bag = null
	transfer.storage = null
	if amount > 0: _finish()
	busy = false
	return amount


func encode() -> Dictionary:
	return _state.encode()


func restore(data: Dictionary) -> bool:
	if busy or _bag == null: return false
	busy = true
	var decoded: Dictionary = Snapshot.decode(data, _definitions, _bag)
	var reason: String = decoded.get("reason", "")
	if decoded.ok:
		for record: Dictionary in decoded.records:
			var config: Resource = definition(StringName(record.type_id))
			reason = _space_reason(&"home", config.cells(Vector2i(record.cell[0], record.cell[1]), record.facing), "", true)
			if not reason.is_empty(): break
	if reason.is_empty() and (not _port("restore").is_valid() or not bool(_port("restore").call(_definitions.duplicate(), decoded.records.duplicate(true)))): reason = "设备世界重建失败"
	if not reason.is_empty():
		last_rejection = reason
		restore_failed.emit(reason)
		busy = false
		return false
	_state.replace(decoded.records, decoded.next_id, _definitions, _bag)
	save_pending = false
	last_rejection = ""
	changed.emit()
	busy = false
	return true


func retry_save() -> bool:
	if busy: return false
	busy = true
	_persist()
	changed.emit()
	busy = false
	return not save_pending


func confirm_saved() -> void:
	if save_pending:
		save_pending = false
		changed.emit()


func release() -> void:
	if busy: return
	_ports.clear()
	_lock_provider = Callable()
	_bag = null


func _space_reason(space: StringName, cells: Array[Vector2i], ignore_id: String, restoring: bool) -> String:
	if not restoring:
		var occupied: Array[Vector2i] = occupied_cells(space, ignore_id)
		for cell: Vector2i in cells:
			if occupied.has(cell): return "这里已有其他设备"
	if not _port("query").is_valid(): return "地图放置查询尚未接入"
	var result: Dictionary = _port("query").call(space, cells.duplicate(), ignore_id, restoring)
	if bool(result.get("ok", false)): return ""
	var reason: String = result.get("reason", "")
	return reason if not reason.is_empty() else "此处不能放置"


func _locked_reason(record: Dictionary) -> String:
	if record.operation.phase == "processing": return "设备正在加工，暂不能移动或拆除"
	if record.operation.phase == "ready" or not record.operation.pending_outputs.is_empty(): return "请先领取设备产物"
	if not record.operation.inputs.is_empty(): return "请先清空设备投入物"
	for slot: Dictionary in record.slots:
		if not slot.is_empty(): return "请先清空储物箱"
	return _external_lock_reason(String(record.get("id", "")))


## 隔离调用外部端口：任何非 String 结果（含运行时错误导致的空返回）收敛为固定原因，
## 保证 move/dismantle 的校验阶段始终正常返回，不半途退出事务或泄漏 busy。
func _external_lock_reason(device_id: String) -> String:
	if not _lock_provider.is_valid(): return ""
	var outcome: Variant = _lock_provider.call(device_id)
	if outcome is String: return outcome
	return "设备状态不可用"


func _factory_ready() -> bool:
	return _port("create").is_valid() and _port("remove").is_valid()


func _port(key: String) -> Callable:
	return _ports.get(key, Callable())


func _finish() -> void:
	last_rejection = ""
	_persist()
	changed.emit()


func _persist() -> void:
	save_pending = true
	if _port("save").is_valid(): save_pending = not bool(_port("save").call())
	if save_pending: save_failed.emit()


func _reject(reason: String) -> bool:
	last_rejection = reason
	return false


func _reject_id(reason: String) -> String:
	_reject(reason)
	return ""
