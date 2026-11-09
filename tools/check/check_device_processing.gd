extends SceneTree
## B3-05 设备加工：唯一库存整批交换、按设备类型限定、跨天领取与分区编解码。

const Service := preload("res://scripts/activities/device_processing_service.gd")
const Definition := preload("res://scripts/data/processing_definition.gd")
const DIR: String = "res://data/processing"
const JAR: StringName = &"preserves_jar"
const MACHINE: StringName = &"mayonnaise_machine"
const PICKLE: StringName = &"pickle_tomato"
const MAYO: StringName = &"make_mayonnaise"
const MIX: StringName = &"mix_probe"
const JAR_A: String = "device_000000000001"
const JAR_B: String = "device_000000000002"
const MACHINE_A: String = "device_000000000003"

var _checks: int = 0
var _failures: int = 0
var _stage: Node
var _bag: Inventory
var _service: RefCounted
var _day: int = 5
var _save_ok: bool = true
var _save_pending: bool = false
var _saved: Dictionary = {}


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[device_processing] FAIL: " + message)


func _run() -> void:
	_stage = Node.new()
	root.add_child(_stage)
	_bag = Inventory.new()
	_stage.add_child(_bag)
	await process_frame
	_service = Service.new()
	var authored: Array[ProcessingDefinition] = _load_authored()
	_check(authored.size() == 2, "both authored processing recipes load from data/processing")
	var catalog: Array[ProcessingDefinition] = []
	catalog.assign(authored)
	catalog.append(_mix_recipe())
	_check(_configure(catalog), "service configures from the authored catalog and one local probe")
	_check(_service._bag == _bag, "the service reads the only inventory instead of copying it")
	_check_definition_contract(authored, catalog)
	_check_types_and_unknown()
	_check_batch_ingredients()
	_check_day_boundary()
	_check_full_bag()
	_check_two_devices()
	_check_machine_type()
	_check_reentrancy()
	_check_persistence()
	_check_partition_rejection()
	await _check_release()
	print("[device_processing] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _load_authored() -> Array[ProcessingDefinition]:
	var result: Array[ProcessingDefinition] = []
	for file: String in ResourceLoader.list_directory(DIR):
		if not file.ends_with(".tres"): continue
		var recipe := load(DIR.path_join(file)) as ProcessingDefinition
		if recipe != null: result.append(recipe)
	return result


func _mix_recipe() -> ProcessingDefinition:
	var recipe := Definition.new()
	recipe.id = MIX
	recipe.device_types.assign([JAR])
	recipe.ingredients.assign({&"tomato": 2, &"fiber": 1})
	recipe.products.assign({&"pickled_tomato": 1})
	recipe.days = 1
	return recipe


func _current_day() -> int:
	return _day


func _configure(catalog: Array[ProcessingDefinition]) -> bool:
	return _service.configure(_bag, _current_day, catalog)


## 调用方保存端口：失败时保留待保存标记，重试写入当前快照而不是回放操作。
func _save() -> bool:
	_saved = _service.encode()
	_save_pending = not _save_ok
	return _save_ok


func _set_items(items: Dictionary) -> void:
	var slots: Array[Dictionary] = []
	for id: StringName in Inventory.TOOL_IDS: slots.append({"id": String(id), "count": 1})
	for id: StringName in items:
		var remaining: int = int(items[id])
		while remaining > 0:
			var count: int = mini(remaining, _bag.definition(id).max_stack)
			slots.append({"id": String(id), "count": count})
			remaining -= count
	_bag.from_dict({"slots": slots})


func _fill_bag() -> void:
	var slots: Array = _bag.to_dict().slots
	for index: int in slots.size():
		if slots[index].is_empty(): slots[index] = {"id": "stone", "count": 99}
	_bag.from_dict({"slots": slots})


func _find(catalog: Array[ProcessingDefinition], id: StringName) -> ProcessingDefinition:
	for recipe: ProcessingDefinition in catalog:
		if recipe.id == id: return recipe
	return null


func _check_definition_contract(authored: Array[ProcessingDefinition], catalog: Array[ProcessingDefinition]) -> void:
	var pickle: ProcessingDefinition = _find(authored, PICKLE)
	var mayo: ProcessingDefinition = _find(authored, MAYO)
	_check(pickle != null and pickle.is_valid(), "pickle recipe is valid")
	_check(mayo != null and mayo.is_valid(), "mayonnaise recipe is valid")
	if pickle == null or mayo == null: return
	_check(pickle.device_types == [JAR], "pickle recipe is limited to the preserves jar")
	_check(pickle.ingredients.size() == 1 and int(pickle.ingredients.get(&"tomato", 0)) == 3, "pickle recipe maps three tomatoes")
	_check(pickle.products.size() == 1 and int(pickle.products.get(&"pickled_tomato", 0)) == 1, "pickle recipe maps one pickled tomato")
	_check(pickle.days == 1, "pickle recipe finishes on the next day")
	_check(mayo.device_types == [MACHINE] and int(mayo.ingredients.get(&"egg", 0)) == 1 and int(mayo.products.get(&"mayonnaise", 0)) == 1, "mayonnaise recipe keeps its own device type and mapping")
	_check(mayo.days == 1, "mayonnaise recipe finishes on the next day")
	var broken := Definition.new()
	broken.id = &"broken"
	broken.device_types.assign([JAR])
	broken.ingredients.assign({&"tomato": 0})
	broken.products.assign({&"pickled_tomato": 1})
	var single: Array[ProcessingDefinition] = [broken]
	_check(not broken.is_valid(), "zero amount makes a definition invalid")
	_check(not _configure(single), "invalid recipe configuration is refused")
	var repeated: Array[ProcessingDefinition] = []
	repeated.assign(catalog)
	repeated.append(catalog[0])
	_check(not _configure(repeated), "duplicate recipe ids are refused")
	_check(_configure(catalog), "the valid catalog configures after refused attempts")


func _check_types_and_unknown() -> void:
	_day = 5
	_set_items({&"tomato": 9, &"egg": 2})
	var baseline: Dictionary = _bag.to_dict()
	_check(not _service.start(JAR_A, PICKLE) and _bag.to_dict() == baseline, "an unregistered device cannot start a batch")
	_check(_service.last_rejection.contains("设备类型"), "the unregistered device rejection is visible")
	_check(_service.bind_device(JAR_A, JAR) and _service.bind_device(JAR_A, JAR), "binding the same type twice is idempotent")
	_check(not _service.bind_device(JAR_A, MACHINE), "a device cannot be rebound to another type")
	_check(_service.bind_device(JAR_B, JAR) and _service.bind_device(MACHINE_A, MACHINE), "independent devices register their own types")
	_check(not _service.start(MACHINE_A, PICKLE) and _bag.to_dict() == baseline, "a recipe rejects any device type outside its list")
	_check(not _service.start(JAR_A, MAYO) and _bag.to_dict() == baseline, "the other recipe also rejects the jar")
	_check(not _service.start(JAR_A, &"missing_recipe") and _bag.to_dict() == baseline, "an unknown recipe is refused")
	var unknown: Dictionary = _service.status("device_000000000099")
	_check(unknown.phase == "idle" and unknown.recipe_id == &"" and unknown.ready_day == 0 and unknown.pending.is_empty(), "an unknown instance reports an idle empty status")
	_check(not _service.collect("device_000000000099").ok and _service.lock_reason("device_000000000099").is_empty(), "an unknown instance neither pays out nor locks placement")


func _check_batch_ingredients() -> void:
	_day = 5
	_set_items({&"tomato": 2})
	var baseline: Dictionary = _bag.to_dict()
	_check(not _service.start(JAR_A, MIX) and _bag.to_dict() == baseline, "a missing ingredient refuses the whole batch")
	_check(_service.last_rejection.contains("纤维") or _service.last_rejection.contains("材料"), "the missing material is explained")
	_check(_service.status(JAR_A).phase == "idle", "a refused batch leaves the device idle")
	_set_items({&"tomato": 2, &"fiber": 1})
	_check(_service.start(JAR_A, MIX), "all mapped ingredients commit together")
	_check(_bag.count_of(&"tomato") == 0 and _bag.count_of(&"fiber") == 0, "every mapped ingredient is consumed exactly once")
	var status: Dictionary = _service.status(JAR_A)
	_check(status.phase == "working" and status.recipe_id == MIX and status.ready_day == _day + 1, "status reports the running recipe and finish day")
	_check(int(status.pending.get(&"pickled_tomato", 0)) == 1, "pending products come from the recipe mapping")
	_check(not _service.start(JAR_A, PICKLE) and _service.last_rejection.contains("加工"), "a running instance refuses a second start")
	var invalid := Definition.new()
	invalid.id = &"bad_probe"
	var invalid_catalog: Array[ProcessingDefinition] = [invalid]
	var running: Dictionary = _service.encode()
	_check(not _configure(invalid_catalog) and _service.encode() == running, "a refused configuration preserves the running batch")


func _check_day_boundary() -> void:
	_day = 5
	_check(not _service.collect(JAR_A).ok and _service.status(JAR_A).phase == "working", "collection before the finish day fails")
	_check(_bag.count_of(&"pickled_tomato") == 0 and not _service.last_rejection.is_empty(), "an early collection grants nothing and explains why")
	_check(_service.lock_reason(JAR_A).contains("加工"), "a working device locks placement")
	_day = 6
	var payout: Dictionary = _service.collect(JAR_A)
	_check(payout.ok and int(payout.produced.get(&"pickled_tomato", 0)) == 1, "the finish day grants the mapped product")
	_check(_bag.count_of(&"pickled_tomato") == 1, "the product enters the single inventory")
	_check(_service.status(JAR_A).phase == "idle" and _service.lock_reason(JAR_A).is_empty(), "collection clears the instance for placement again")
	_check(not _service.collect(JAR_A).ok and _bag.count_of(&"pickled_tomato") == 1, "collecting twice in the same day adds nothing")
	_day = 7
	_check(not _service.collect(JAR_A).ok and _bag.count_of(&"pickled_tomato") == 1, "later days cannot repeat the same payout")


func _check_full_bag() -> void:
	_day = 7
	_set_items({&"tomato": 3})
	_check(_service.start(JAR_A, PICKLE), "the authored pickle recipe starts on a bound jar")
	_day = 8
	_check(_service.status(JAR_A).phase == "ready", "status reports the ready phase")
	_fill_bag()
	var baseline: Dictionary = _bag.to_dict()
	var blocked: Dictionary = _service.collect(JAR_A)
	_check(not blocked.ok and not String(blocked.reason).is_empty() and _bag.to_dict() == baseline, "a full bag keeps the product and explains why")
	_check(_service.status(JAR_A).phase == "ready" and _service.lock_reason(JAR_A).contains("领取"), "a ready instance keeps its pending payout")
	_bag.remove_item(&"stone", 99)
	_check(_service.collect(JAR_A).ok and _bag.count_of(&"pickled_tomato") == 1, "freeing one slot allows exactly one payout")
	_check(not _service.collect(JAR_A).ok and _bag.count_of(&"pickled_tomato") == 1, "repeated collection after success adds nothing")


func _check_two_devices() -> void:
	_day = 10
	_set_items({&"tomato": 6})
	_check(_service.start(JAR_A, PICKLE), "the first jar starts")
	_day = 11
	_check(_service.start(JAR_B, PICKLE), "the second jar starts on a later day")
	_check(_service.collect(JAR_A).ok and _service.status(JAR_B).phase == "working", "collecting one device leaves the other working")
	_check(not _service.collect(JAR_B).ok and _bag.count_of(&"pickled_tomato") == 1, "the other device keeps its own payout")
	_day = 12
	_check(_service.collect(JAR_B).ok and _bag.count_of(&"pickled_tomato") == 2, "each device settles its own batch once")
	_check(_service.status(JAR_A).phase == "idle" and _service.status(JAR_B).phase == "idle", "both instances return to idle independently")


func _check_machine_type() -> void:
	_day = 12
	_set_items({&"egg": 2})
	var baseline: Dictionary = _bag.to_dict()
	if _bag.definition(&"mayonnaise") == null:
		_check(not _service.start(MACHINE_A, MAYO) and _bag.to_dict() == baseline, "a product missing from the inventory never consumes ingredients")
		_check(_service.last_rejection.contains("成品"), "the unwired product is reported instead of locking materials")
	else:
		_check(_service.start(MACHINE_A, MAYO), "the mayonnaise recipe starts on its own device type")
		_check(_bag.count_of(&"egg") == 1, "the egg is consumed once")
		_day = 13
		var payout: Dictionary = _service.collect(MACHINE_A)
		_check(payout.ok and _bag.count_of(&"mayonnaise") == 1, "mayonnaise settles through the only inventory")


func _check_reentrancy() -> void:
	_day = 20
	_set_items({&"tomato": 3})
	var nested: Array[bool] = []
	var watcher := func(_id: String, _recipe: StringName) -> void:
		nested.append(_service.start(JAR_A, PICKLE))
		nested.append(_service.collect(JAR_B).ok)
	_service.started.connect(watcher)
	_check(_service.start(JAR_A, PICKLE), "a start commits and notifies once")
	_service.started.disconnect(watcher)
	_check(not nested.has(true) and _service.status(JAR_A).phase == "working", "signal observers cannot reenter start or collect")


func _check_persistence() -> void:
	_day = 21
	_service.collect(JAR_A)
	_set_items({&"tomato": 3})
	_check(_service.start(JAR_A, PICKLE), "a working record is prepared for the save round trip")
	var saved: Dictionary = _service.encode()
	_check(saved.schema == 1 and saved.instances.has(JAR_A), "encode keeps the instance under schema 1")
	var row: Dictionary = saved.instances[JAR_A]
	_check(row.size() == 2 and row.has("recipe_id") and row.has("ready_day"), "encode stores only the recipe id and finish day")
	_check(not row.has("products") and not row.has("ingredients"), "encode never stores item definitions")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved)) as Dictionary
	_check(_service.restore(parsed) and _service.status(JAR_A).phase == "working", "the JSON round trip restores the working record")
	_save_ok = false
	_check(not _save() and _save_pending, "a failed caller save is visible")
	_check(_service.status(JAR_A).phase == "working" and _bag.count_of(&"tomato") == 0, "a failed save never rolls back the committed batch")
	_save_ok = true
	_check(_save() and not _save_pending and _saved.instances.has(JAR_A), "the retry writes the same working fact")
	var before: Dictionary = _bag.to_dict()
	for attempt: int in 3:
		_check(_service.restore(parsed), "repeated restore accepts the same valid partition")
	_check(_bag.to_dict() == before and _service.status(JAR_A).phase == "working", "three restores neither consume nor produce")
	_day = 22
	var payout: Dictionary = _service.collect(JAR_A)
	_check(payout.ok and _bag.count_of(&"pickled_tomato") == 1, "the restored record can be collected exactly once")
	_check(not _service.encode().instances.has(JAR_A), "a successful collection removes the instance from the save")
	_save_ok = false
	_check(not _save() and _save_pending, "a failed save after collection is visible")
	_check(_bag.count_of(&"pickled_tomato") == 1 and not _service.encode().instances.has(JAR_A), "the collected fact is kept once after a failed save")
	_save_ok = true
	_check(_save() and not _save_pending and _saved.instances.is_empty(), "the retry saves the collected state without repeating the payout")


func _check_partition_rejection() -> void:
	_day = 30
	_set_items({&"tomato": 6})
	_check(_service.start(JAR_A, PICKLE), "a fresh record guards the rejection cases")
	var baseline: Dictionary = _service.encode()
	var rows: Array[Dictionary] = [
		{"schema": 2, "instances": {}},
		{"schema": "1", "instances": {}},
		{"schema": true, "instances": {}},
		{"schema": 1.5, "instances": {}},
		{"instances": {}},
		{"schema": 1, "instances": []},
		{"schema": 1, "instances": {JAR_A: {"recipe_id": &"missing_recipe", "ready_day": 31}}},
		{"schema": 1, "instances": {JAR_A: {"recipe_id": String(PICKLE), "ready_day": 0}}},
		{"schema": 1, "instances": {JAR_A: {"recipe_id": String(PICKLE), "ready_day": 1.5}}},
		{"schema": 1, "instances": {JAR_A: {"recipe_id": String(PICKLE), "ready_day": "31"}}},
		{"schema": 1, "instances": {JAR_A: {"recipe_id": String(PICKLE), "ready_day": 1000001}}},
		{"schema": 1, "instances": {JAR_A: "text"}},
		{"schema": 1, "instances": {1: {"recipe_id": String(PICKLE), "ready_day": 31}}},
		{"schema": 1, "instances": {"": {"recipe_id": String(PICKLE), "ready_day": 31}}},
		{"schema": 1, "instances": {"x".repeat(65): {"recipe_id": String(PICKLE), "ready_day": 31}}},
		{"schema": 1, "instances": {MACHINE_A: {"recipe_id": String(PICKLE), "ready_day": 31}}},
	]
	for candidate: Dictionary in rows:
		_check(not _service.restore(candidate) and _service.encode() == baseline, "malformed partition is rejected as a whole: " + str(candidate.get("schema")))
	var oversized: Dictionary = {"schema": 1, "instances": {}}
	for index: int in Service.MAX_DEVICES + 1:
		oversized.instances["device_%012d" % (index + 1)] = {"recipe_id": String(PICKLE), "ready_day": 31}
	_check(not _service.restore(oversized) and _service.encode() == baseline, "an oversized instance table is rejected without truncating it")
	_check(_service.restore({"schema": 1, "instances": {}}) and _service.encode().instances.is_empty(), "an empty but versioned partition is accepted")
	_check(_service.restore({}) and _service.encode().instances.is_empty(), "a legacy save without the section clears the partition")


func _check_release() -> void:
	_service.release()
	_check(_service._bag == null and _service.status(JAR_A).phase == "idle" and _service.lock_reason(JAR_A).is_empty(), "release drops the inventory reference and all instance facts")
	_check(not _service.start(JAR_A, PICKLE) and not _service.collect(JAR_A).ok, "the released service refuses both operations")
	_check(not _service.restore({"schema": 1, "instances": {}}), "the released service refuses restore")
	_check(_service.encode().instances.is_empty(), "the released snapshot stays empty")
	_stage.queue_free()
	await process_frame
