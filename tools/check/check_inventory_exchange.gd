extends SceneTree
## B3公共库存端口：净容量、失败无改、批量通知和同步重入。

var _bag: Inventory
var _checks: int = 0
var _failures: int = 0
var _reached_end: bool = false


func _init() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	_checks += 1
	if value: return
	_failures += 1
	printerr("[inventory_exchange] FAIL: " + label)


func _full_bag() -> void:
	var slots: Array[Dictionary] = []
	for id: StringName in Inventory.TOOL_IDS: slots.append({"id": String(id), "count": 1})
	slots.append({"id": "fiber", "count": 2})
	while slots.size() < Inventory.SLOT_COUNT: slots.append({"id": "wood", "count": 99})
	_bag.from_dict({"slots": slots})
	_bag.today_collected = 0


func _reject(consumed: Dictionary, produced: Dictionary, label: String) -> void:
	var before: Dictionary = _bag.to_dict()
	var notified: Array[int] = [0]
	var observer := func() -> void: notified[0] += 1
	_bag.changed.connect(observer)
	var preview: Dictionary = _bag.preview_exchange_batch(consumed, produced)
	_check(not preview.ok and not String(preview.reason).is_empty(), label + ": explained preview rejection")
	_check(not _bag.exchange_batch(consumed, produced), label + ": commit also rejects")
	_check(_bag.to_dict() == before and notified[0] == 0, label + ": no data or notification changes")
	_bag.changed.disconnect(observer)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_bag = Inventory.new()
	root.add_child(_bag)
	await process_frame
	_full_bag()
	_reject({&"fiber": 1}, {&"carrot_seeds": 4}, "one batch does not release a slot")
	var before: Dictionary = _bag.to_dict()
	_check(_bag.preview_exchange_batch({&"fiber": 2}, {&"carrot_seeds": 4}).ok, "two batches release the input slot even though one batch cannot")
	_check(_bag.to_dict() == before, "successful preview is read-only")
	var notifications: Array[String] = []
	var owner_state: Dictionary = {"committed": false}
	var observer := func() -> void:
		notifications.append("changed")
		_check(owner_state.committed and _bag.count_of(&"fiber") == 0 and _bag.count_of(&"carrot_seeds") == 4, "observer sees the complete owner and inventory transaction")
		_check(not _bag.exchange_batch({&"wood": 1}, {&"wood": 1}), "changed observer cannot start a nested exchange")
	var added := func(id: StringName, amount: int) -> void:
		notifications.append("added")
		_check(id == &"carrot_seeds" and amount == 4 and _bag.count_of(&"fiber") == 0 and owner_state.committed, "item-added observer sees all final facts")
		_check(not _bag.exchange_batch({&"wood": 1}, {&"wood": 1}), "item-added observer cannot exchange another item")
	_bag.changed.connect(observer)
	_bag.item_added.connect(added)
	_bag.begin_update()
	_check(_bag.exchange_batch({&"fiber": 2}, {&"carrot_seeds": 4}), "valid exchange commits inside an outer transaction")
	_check(notifications.is_empty(), "outer transaction controls notification timing")
	_check(not _bag.exchange_batch({&"wood": 1}, {&"wood": 1}), "exchange remains guarded until outer notifications return")
	owner_state.committed = true
	_bag.end_update()
	_check(notifications == ["added", "changed"] and _bag.today_collected == 0, "crafting reports one batch without increasing labor statistics")
	_bag.changed.disconnect(observer)
	_bag.item_added.disconnect(added)
	_check(_bag.exchange_batch({&"wood": 1}, {&"wood": 1}), "guard releases for the next independent exchange")
	_full_bag()
	_reject({&"fiber": 2}, {&"carrot_seeds": 1, &"stone": 1}, "two products cannot share one released slot")
	_check(_bag.exchange_batch({&"fiber": 2, &"wood": 99}, {&"carrot_seeds": 1, &"stone": 1}), "two consumed slots accommodate both products atomically")
	_check(_bag.count_of(&"carrot_seeds") == 1 and _bag.count_of(&"stone") == 1 and _bag.count_of(&"fiber") == 0, "all products and materials commit together")
	for record: Array in [
		[{}, {}, "empty transaction"],
		[{&"fiber": 3}, {}, "missing ingredients"],
		[{&"hoe": 1}, {}, "consume permanent tool"],
		[{}, {&"hoe": 1}, "duplicate permanent tool"],
		[{}, {&"missing": 1}, "unknown item"],
		[{}, {7: 1}, "non-string item ID"],
		[{}, {&"wood": 0}, "zero quantity"],
		[{}, {&"wood": -1}, "negative quantity"],
		[{}, {&"wood": true}, "boolean quantity"],
		[{}, {&"wood": 1.5}, "fraction quantity"],
		[{}, {&"wood": NAN}, "non-finite quantity"],
		[{}, {&"wood": 2147483648}, "out-of-range quantity"],
		[{}, {&"wood": 2147483647}, "huge quantity fails capacity in bounded work"],
	]:
		_reject(record[0], record[1], record[2])
	_check(_bag.exchange_batch({&"stone": 1}, {}), "placement can consume without a product")
	_check(_bag.exchange_batch({}, {&"stone": 1}, &"transfer"), "dismantling can return items without consumption")
	_check(_bag.today_collected == 0, "placement and dismantling do not generate labor statistics")
	var restored: Variant = JSON.parse_string(JSON.stringify(_bag.to_dict()))
	var exact: Dictionary = _bag.to_dict()
	for repeat: int in 3: _bag.from_dict(restored)
	_check(_bag.to_dict() == exact, "JSON round-trip restores the exact exchanged inventory without rewards")
	_reached_end = true
	_bag.queue_free()
	await process_frame
	_check(_reached_end and not is_instance_valid(_bag), "all transaction checks reached end and released the model")
	print("[inventory_exchange] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
