extends SceneTree
## B3-04 洒水器计划纯逻辑检查：规则校验、朝向/占地换算、相邻覆盖、去重、跳过计数与只读幂等。

const Service := preload("res://scripts/progression/sprinkler_service.gd")
const Basic: Resource = preload("res://data/sprinklers/basic_sprinkler.tres")

var _checks: int = 0
var _failures: int = 0
var _service: RefCounted


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[sprinklers] FAIL: " + message)


func _cells(values: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(values)
	return result


func _same(actual: Variant, expected: Array) -> bool:
	return actual is Array and actual == _cells(expected)


func _instances(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(values)
	return result


func _rules(values: Array) -> Array[SprinklerRule]:
	var result: Array[SprinklerRule] = []
	result.assign(values)
	return result


func _rule(type_id: StringName, points: Array) -> SprinklerRule:
	var rule := SprinklerRule.new()
	rule.type_id = type_id
	rule.offset_cells.assign(points)
	return rule


func _device(type_id: Variant, cell: Variant, facing: int = 0, space: Variant = &"home", size: Variant = null) -> Dictionary:
	var record: Dictionary = {"type_id": type_id, "space_id": space, "cell": cell}
	if facing != 0: record["facing"] = facing
	if size != null: record["size"] = size
	return record


func _plan(values: Array, space: StringName = &"home") -> Dictionary:
	return _service.plan(_instances(values), space)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_service = Service.new()
	_check_contract_shape()
	_check_basic_resource()
	_check_configure()
	_check_neighbour_coverage()
	_check_dedup()
	_check_facing_and_footprint()
	_check_skips_and_empty()
	_check_purity()
	_check_release()
	_service.release()
	_check(_service.plan(_instances([_device(&"basic_sprinkler", Vector2i(1, 1))]), &"home").reason == Service.REASON_UNCONFIGURED, "released service no longer holds rules")
	_service = null
	print("[sprinklers] reached end; %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_contract_shape() -> void:
	_check(_service is RefCounted and _service.get_script().get_instance_base_type() == "RefCounted",
		"sprinkler service is a plain RefCounted, not a scene node")
	_check(_service.get_script().get_script_signal_list().is_empty(), "service declares no signals: it never notifies gameplay")
	var result: Dictionary = _plan([_device(&"basic_sprinkler", Vector2i(2, 2))])
	_check(result.keys().size() == 4 and result.has("cells") and result.has("devices") and result.has("skipped") and result.has("reason"),
		"plan returns exactly cells/devices/skipped/reason")
	_check(result is Dictionary and result.cells is Array and result.reason is String, "plan result fields keep their documented types")


func _check_basic_resource() -> void:
	_check(Basic != null and Basic.get_script() == preload("res://scripts/data/sprinkler_rule.gd"), "shipped basic sprinkler resource loads as SprinklerRule")
	_check(Basic.type_id == &"basic_sprinkler", "shipped rule uses the agreed device type id")
	_check(Basic.is_valid(), "shipped rule passes the same validation the service applies")
	var typed: Array[Vector2i] = []
	typed.assign(Basic.offset_cells)
	_check(typed.size() == 4, "basic sprinkler covers four cells")
	var expected: Array[Vector2i] = _cells([Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)])
	_check(typed == expected, "basic sprinkler covers exactly the four orthogonal neighbours")
	_check(Basic.offset_cells.count(Vector2i(0, 0)) == 0, "basic sprinkler never lists its own anchor cell")


func _check_configure() -> void:
	_check(not _service.configure(_rules([])), "empty rule catalog is refused")
	_check(not _service.configure(_rules([null])), "null rule is refused")
	_check(not _service.configure(_rules([_rule(&"", [Vector2i(1, 0)])])), "rule without type_id is refused")
	_check(not _service.configure(_rules([_rule(&"bad", [])])), "rule without offsets is refused")
	_check(not _service.configure(_rules([_rule(&"far", [Vector2i(9, 0)])])), "offset beyond eight cells is refused")
	_check(not _service.configure(_rules([_rule(&"far", [Vector2i(0, -9)])])), "negative oversized offset is refused too")
	_check(not _service.configure(_rules([_rule(&"dup", [Vector2i(1, 0), Vector2i(1, 0)])])), "repeated offset inside one rule is refused")
	_check(not _service.configure(_rules([_rule(&"same", [Vector2i(1, 0)]), _rule(&"same", [Vector2i(0, 1)])])), "duplicate type_id is refused instead of silently merged")
	var unconfigured: Dictionary = _plan([_device(&"basic_sprinkler", Vector2i(4, 4))])
	_check(unconfigured.reason == Service.REASON_UNCONFIGURED and unconfigured.skipped == 1 and unconfigured.devices == 0,
		"planning before configure reports the reason and skips every instance")
	var asym := _rule(&"asym", [Vector2i(1, 0), Vector2i(0, 1)])
	_check(_service.configure(_rules([Basic, asym])), "valid catalog configures")
	_check(not _service.configure(_rules([_rule(&"far", [Vector2i(8, 9)])])), "a later invalid reconfiguration is refused")
	_check(_same(_plan([_device(&"basic_sprinkler", Vector2i(4, 4))]).cells, [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4)]),
		"refused reconfiguration keeps the previously accepted rules")
	_check(_service.configure(_rules([Basic, asym])), "repeating the same valid catalog is idempotent")


func _check_neighbour_coverage() -> void:
	var result: Dictionary = _plan([_device(&"basic_sprinkler", Vector2i(4, 4))])
	_check(_same(result.cells, [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4)]), "one sprinkler covers its four orthogonal neighbours")
	_check(result.devices == 1 and result.skipped == 0 and String(result.reason).is_empty(), "one valid device is planned without a rejection reason")
	var array_cell: Dictionary = _plan([_device(&"basic_sprinkler", [4, 4])])
	_check(array_cell == result, "placement-style [x, y] cells plan exactly like Vector2i cells")
	var missing_space: Dictionary = _plan([{"type_id": &"basic_sprinkler", "cell": [4, 4]}])
	_check(missing_space == result, "an instance without space_id defaults to the home space")
	var missing_facing: Dictionary = _plan([{"type_id": &"basic_sprinkler", "space_id": "home", "cell": [4, 4]}])
	_check(missing_facing == result, "an instance without facing defaults to the unrotated footprint")
	_check(_same(Basic.offset_cells, [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]), "planning never rewrites the shipped rule resource")


func _check_dedup() -> void:
	var stacked: Dictionary = _plan([
		_device(&"basic_sprinkler", Vector2i(4, 4)),
		_device(&"basic_sprinkler", Vector2i(4, 4)),
	])
	_check(_same(stacked.cells, [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4)]), "two overlapping sprinklers emit each cell once")
	_check(stacked.devices == 2 and stacked.skipped == 0, "both overlapping devices still count as planned")
	var shared: Dictionary = _plan([
		_device(&"basic_sprinkler", Vector2i(4, 4)),
		_device(&"basic_sprinkler", Vector2i(6, 4)),
	])
	_check(_same(shared.cells, [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4), Vector2i(6, 3), Vector2i(7, 4), Vector2i(6, 5)]),
		"partially overlapping devices keep first-seen order and drop the shared cell")
	var counted: Dictionary = {}
	for cell: Vector2i in shared.cells: counted[cell] = int(counted.get(cell, 0)) + 1
	_check(counted.size() == shared.cells.size(), "no duplicated coordinate survives the plan")


func _check_facing_and_footprint() -> void:
	var asym := _rule(&"asym", [Vector2i(1, 0), Vector2i(0, 1)])
	_check(_service.configure(_rules([Basic, asym])), "asymmetric rule configures for rotation checks")
	_check(_same(_plan([_device(&"asym", Vector2i(4, 4))]).cells, [Vector2i(5, 4), Vector2i(4, 5)]), "1x1 facing 0 keeps local offsets")
	_check(_same(_plan([_device(&"asym", Vector2i(4, 4), 1)]).cells, [Vector2i(4, 5), Vector2i(3, 4)]), "1x1 facing 1 rotates offsets 90 degrees")
	_check(_same(_plan([_device(&"asym", Vector2i(4, 4), 2)]).cells, [Vector2i(3, 4), Vector2i(4, 3)]), "1x1 facing 2 rotates offsets 180 degrees")
	_check(_same(_plan([_device(&"asym", Vector2i(4, 4), 3)]).cells, [Vector2i(4, 3), Vector2i(5, 4)]), "1x1 facing 3 rotates offsets 270 degrees")
	var flat: Dictionary = _plan([_device(&"asym", Vector2i(4, 4), 0, &"home", Vector2i(2, 1))])
	_check(_same(flat.cells, [Vector2i(4, 5)]), "2x1 facing 0 extends +x and hides the offset that lands on its own body")
	_check(flat.devices == 1 and flat.skipped == 0, "a 2x1 device with one visible cell is still planned")
	var turned: Dictionary = _plan([_device(&"asym", Vector2i(4, 4), 1, &"home", Vector2i(2, 1))])
	_check(_same(turned.cells, [Vector2i(3, 4)]), "2x1 facing 1 swaps the footprint to +y and drops the covered body cell")
	var flipped: Dictionary = _plan([_device(&"asym", Vector2i(4, 4), 2, &"home", Vector2i(2, 1))])
	_check(_same(flipped.cells, [Vector2i(3, 4), Vector2i(4, 3)]), "2x1 facing 2 keeps both rotated offsets outside its +x body")
	var reversed: Dictionary = _plan([_device(&"asym", Vector2i(4, 4), 3, &"home", Vector2i(2, 1))])
	_check(_same(reversed.cells, [Vector2i(4, 3), Vector2i(5, 4)]), "2x1 facing 3 rotates back to the -y slot and the +x neighbour")
	var array_size: Dictionary = _plan([_device(&"asym", Vector2i(4, 4), 0, &"home", [2, 1])])
	_check(array_size == flat, "footprint accepts [w, h] exactly like Vector2i")
	var hidden := _rule(&"hidden", [Vector2i(1, 0)])
	_check(_service.configure(_rules([Basic, asym, hidden])), "rule whose only offset sits on the body configures")
	var buried: Dictionary = _plan([_device(&"hidden", Vector2i(4, 4), 0, &"home", Vector2i(2, 1))])
	_check(buried.cells.is_empty() and buried.devices == 1 and buried.skipped == 0, "a valid device whose whole coverage is its own body is planned, not skipped")


func _check_skips_and_empty() -> void:
	var empty: Dictionary = _plan([])
	_check(empty.cells.is_empty() and empty.devices == 0 and empty.skipped == 0 and String(empty.reason).is_empty(), "empty instance list returns empty cells and an empty reason")
	var other_space: Dictionary = _plan([_device(&"basic_sprinkler", Vector2i(4, 4), 0, &"forest")])
	_check(other_space.cells.is_empty() and other_space.devices == 0 and other_space.skipped == 1, "instances from another space are skipped")
	var unknown: Dictionary = _plan([_device(&"gold_sprinkler", Vector2i(4, 4))])
	_check(unknown.cells.is_empty() and unknown.skipped == 1 and String(unknown.reason).is_empty(), "unknown type_id is skipped without failing the whole plan")
	for bad: Dictionary in [
		{"cell": [4, 4]},
		{"type_id": 7, "cell": [4, 4]},
		{"type_id": &"basic_sprinkler", "cell": "4,4"},
		{"type_id": &"basic_sprinkler", "cell": [4.5, 4]},
		{"type_id": &"basic_sprinkler", "cell": [true, 4]},
		{"type_id": &"basic_sprinkler", "cell": [4097, 4]},
		{"type_id": &"basic_sprinkler", "cell": [-4097, 4]},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "facing": 4},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "facing": -1},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "facing": 1.5},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "facing": true},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "size": [0, 1]},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "size": [9, 1]},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "size": "big"},
		{"type_id": &"basic_sprinkler", "cell": [4, 4], "space_id": 5},
	]:
		var skipped: Dictionary = _plan([bad])
		_check(skipped.cells.is_empty() and skipped.devices == 0 and skipped.skipped == 1,
			"malformed instance %s is skipped and counted" % [bad])
	var mixed: Dictionary = _plan([
		_device(&"basic_sprinkler", Vector2i(4, 4)),
		_device(&"gold_sprinkler", Vector2i(9, 9)),
		_device(&"basic_sprinkler", "far"),
		_device(&"basic_sprinkler", Vector2i(4, 4), 0, &"forest"),
	])
	_check(mixed.devices == 1 and mixed.skipped == 3 and mixed.cells.size() == 4, "one valid instance among three invalid ones keeps exact counts")
	var bad_space: Dictionary = _plan([_device(&"basic_sprinkler", Vector2i(4, 4))], &"")
	_check(bad_space.cells.is_empty() and bad_space.skipped == 1 and bad_space.reason == Service.REASON_SPACE, "an empty target space fails the whole plan with a reason")


func _check_purity() -> void:
	var records: Array = [
		_device(&"basic_sprinkler", Vector2i(4, 4)),
		_device(&"basic_sprinkler", Vector2i(6, 4), 1, &"home"),
		_device(&"gold_sprinkler", [1, 1]),
	]
	var before: Array = records.duplicate(true)
	var first: Dictionary = _plan(records)
	var second: Dictionary = _plan(records)
	_check(records == before, "planning never mutates the caller's instances")
	_check(first == second, "two consecutive plans return identical results")
	first.cells.append(Vector2i(99, 99))
	first["devices"] = 99
	_check(second.cells.size() == 7 and second.devices == 2, "each plan returns fresh arrays and dictionaries")
	var third: Dictionary = _plan(records)
	_check(third == second and not third.cells.has(Vector2i(99, 99)), "mutating one result cannot leak into the next plan")
	var asym := _rule(&"asym", [Vector2i(1, 0)])
	_check(_service.configure(_rules([Basic, asym])), "rule catalog reconfigures for the copy check")
	asym.offset_cells.clear()
	_check(_same(_plan([_device(&"asym", Vector2i(4, 4))]).cells, [Vector2i(5, 4)]), "the service keeps a private copy of accepted rules")
	var rotated := _same(_plan([_device(&"basic_sprinkler", Vector2i(4, 4), 1)]).cells, [Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4), Vector2i(4, 3)])
	_check(rotated, "symmetric neighbours still cover the same four cells after a 90-degree turn")
	_check(String(_plan([]).reason).is_empty(), "an empty plan after reconfiguration reports no failure")


func _check_release() -> void:
	_service.release()
	var released: Dictionary = _plan([_device(&"basic_sprinkler", Vector2i(4, 4))])
	_check(released.reason == Service.REASON_UNCONFIGURED and released.skipped == 1, "release drops the rule catalog")
	_service.release()
	_check(_service.configure(_rules([Basic])), "a released service can be configured again by the composition root")
	_check(_same(_plan([_device(&"basic_sprinkler", Vector2i(4, 4))]).cells, [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4)]), "reconfiguration after release restores coverage")
