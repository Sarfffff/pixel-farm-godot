extends SceneTree
## B4-02 修路/区域解锁链纯状态检查：阶段顺序、材料门槛、解锁区域、存档兼容与配置校验。

const Service := preload("res://scripts/progression/road_repair_service.gd")
const Quarry: Resource = preload("res://data/unlocks/quarry_road.tres")

var _checks: int = 0
var _failures: int = 0
var _service: RefCounted


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[road_repair] FAIL: " + message)


func _row(label: String, cost: Dictionary, region: StringName = &"") -> Dictionary:
	return {"label": label, "cost": cost, "unlock_region": region}


func _cost(pairs: Array) -> Dictionary:
	var result: Dictionary = {}
	for pair: Array in pairs: result[StringName(pair[0])] = int(pair[1])
	return result


func _have(pairs: Array) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for pair: Array in pairs: result[StringName(pair[0])] = int(pair[1])
	return result


func _data(id: StringName, rows: Array) -> RegionUnlockData:
	var data := RegionUnlockData.new()
	data.id = id
	data.stages.assign(rows)
	return data


func _road() -> RegionUnlockData:
	return _data(&"quarry_road", [
		_row("未修", _cost([[&"wood", 4], [&"stone", 2]])),
		_row("材料已交", _cost([[&"hardwood", 3]])),
		_row("通路", {}, &"quarry"),
	])


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_service = Service.new()
	_check_contract_and_unconfigured()
	_check_configure_validation()
	_check_requirements()
	_check_advance_and_unlocks()
	_check_persistence()
	_check_shipped_chain()
	_check_purity_and_release()
	_service.release()
	_check(_service.stage() == 0 and _service.encode() == {"schema": 1, "stage": 0}, "final release leaves no chain behind")
	_service = null
	print("[road_repair] reached end; %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_contract_and_unconfigured() -> void:
	_check(_service.get_script().get_instance_base_type() == "RefCounted",
		"chain service is a plain RefCounted and needs no scene node")
	_check(_service.get_script().get_script_signal_list().is_empty(), "service declares no signals: it never pushes gameplay events")
	_check(_service.stage() == 0, "an unconfigured service reports stage 0")
	_check(_service.requirement().is_empty(), "an unconfigured service has no material requirement")
	_check(not _service.requirements_met(_have([])), "an unconfigured service never reports the gate as satisfied")
	_check(_service.unlocked_regions().is_empty() and not _service.advance(), "an unconfigured service cannot advance or unlock")
	_check(_service.encode() == {"schema": 1, "stage": 0}, "encode always reports schema 1 with the current stage")
	_check(not _service.restore({}), "restore before configure is refused")
	_check(not _service.configure(null), "null definition is refused")


func _check_configure_validation() -> void:
	_check(_road().is_valid(), "the fixture chain passes the same validation the service applies")
	_check(not _service.configure(_data(&"", [_row("a", _cost([[&"wood", 1]])), _row("b", {}, &"quarry")])),
		"empty chain id is refused")
	_check(not _service.configure(_data(&"chain", [])), "chain without stages is refused")
	_check(not _service.configure(_data(&"chain", [_row("  ", _cost([[&"wood", 1]])), _row("b", {}, &"quarry")])),
		"blank stage label is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"wood", 0]])), _row("b", {}, &"quarry")])),
		"zero material cost is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"wood", -3]])), _row("b", {}, &"quarry")])),
		"negative material cost is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", {&"wood": 1.5}), _row("b", {}, &"quarry")])),
		"fractional material cost is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", {&"wood": "3"}), _row("b", {}, &"quarry")])),
		"string material cost is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"Wood", 1]])), _row("b", {}, &"quarry")])),
		"item id outside the lower-snake format is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"", 1]])), _row("b", {}, &"quarry")])),
		"empty item id is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"wo od", 1]])), _row("b", {}, &"quarry")])),
		"item id with a space is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"a-b", 1]])), _row("b", {}, &"quarry")])),
		"item id with a dash is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"x".repeat(65), 1]])), _row("b", {}, &"quarry")])),
		"over-long item id is refused")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"wood", 1]])), _row("b", _cost([[&"stone", 1]]), &"quarry")])),
		"a terminal stage must not demand materials")
	_check(not _service.configure(_data(&"chain", [_row("a", {}, "quarry road")])), "region id outside the id format is refused")
	_check(_service.configure(_data(&"chain", [_row("a", {}, &"quarry")])), "a single terminal stage without materials is a valid chain")


func _check_requirements() -> void:
	var road := _road()
	_check(_service.configure(road), "a valid chain configures")
	_check(_service.stage() == 0 and _service.requirement() == _have([[&"wood", 4], [&"stone", 2]]),
		"configure starts at stage 0 with the authored materials")
	_check(_service.requirements_met(_have([[&"wood", 4], [&"stone", 2]])), "exact materials satisfy the gate")
	_check(_service.requirements_met(_have([[&"wood", 9], [&"stone", 2], [&"fiber", 1]])), "extra materials do not block the gate")
	_check(not _service.requirements_met(_have([[&"wood", 3], [&"stone", 2]])), "one missing unit fails the gate")
	_check(not _service.requirements_met(_have([[&"wood", 4]])), "a missing material kind fails the gate")
	_check(not _service.requirements_met(_have([[&"wood", 4], [&"stone", -2]])), "a negative amount for a required item never satisfies the gate")
	_check(not _service.requirements_met(_have([])), "an empty material table fails the gate while materials are needed")
	var bag: Dictionary[StringName, int] = _have([[&"hardwood", 9]])
	var snapshot: Dictionary[StringName, int] = bag.duplicate()
	_service.requirements_met(bag)
	_check(bag == snapshot, "the gate never mutates the caller's material table")
	var need: Dictionary[StringName, int] = _service.requirement()
	need[&"wood"] = 99
	_check(_service.requirement() == _have([[&"wood", 4], [&"stone", 2]]), "requirement returns a private copy")
	_check(_service.stage() == 0, "read-only queries never advance or unlock on their own")
	_service.advance()
	_check(_service.requirement() == _have([[&"hardwood", 3]]), "the next stage carries its own material requirement")
	_check(not _service.requirements_met(_have([[&"wood", 4], [&"stone", 2]])), "the previous stage materials no longer satisfy the new stage")
	_check(not _service.configure(_data(&"chain", [_row("a", _cost([[&"wood", 0]])), _row("b", {}, &"quarry")])),
		"a refused reconfiguration changes nothing")
	_check(_service.stage() == 1 and _service.requirement() == _have([[&"hardwood", 3]]),
		"refused reconfiguration keeps the previous progress and materials")
	_check(_service.configure(road) and _service.stage() == 0, "a successful reconfiguration starts a new session at stage 0")


func _check_advance_and_unlocks() -> void:
	_check(_service.advance() and _service.stage() == 1, "advance stops at the next stage instead of skipping it")
	_check(_service.unlocked_regions().is_empty(), "stage 1 has not unlocked the quarry yet")
	_check(_service.advance() and _service.stage() == 2, "the second paid stage reaches the end")
	_check(_service.requirement().is_empty(), "the terminal stage demands no materials")
	_check(not _service.requirements_met(_have([])), "the terminal stage never reports a satisfied gate")
	var unlocked: Array[StringName] = _service.unlocked_regions()
	_check(unlocked == [&"quarry"], "the terminal stage unlocks exactly the quarry")
	var encoded: Dictionary = _service.encode()
	for attempt in 3:
		_check(not _service.advance(), "repeated advance at the terminal stage is refused")
	_check(_service.stage() == 2 and _service.encode() == encoded, "terminal repeats leave stage and snapshot unchanged")
	unlocked.append(&"forest")
	_check(_service.unlocked_regions() == [&"quarry"], "unlocked_regions returns a private array")
	var chain := _data(&"chain", [
		_row("a", _cost([[&"wood", 1]])),
		_row("b", _cost([[&"wood", 1]]), &"forest"),
		_row("c", {}, &"quarry"),
	])
	_check(_service.configure(chain), "a multi-region chain configures")
	_check(_service.unlocked_regions().is_empty(), "stage 0 unlocks nothing")
	_check(_service.advance() and _service.unlocked_regions() == [&"forest"], "stage 1 unlocks forest")
	_check(_service.advance() and _service.unlocked_regions() == [&"forest", &"quarry"], "stage 2 keeps earlier unlocks and adds quarry")
	var duplicate := _data(&"duplicate", [_row("a", _cost([[&"wood", 1]])), _row("b", {}, &"quarry"), _row("c", {}, &"quarry")])
	_check(_service.configure(duplicate), "a chain repeating the same region configures")
	_service.advance()
	_service.advance()
	_check(_service.unlocked_regions() == [&"quarry"], "a region unlocked by two stages is reported once")


func _check_persistence() -> void:
	_check(_service.configure(_road()), "reset before the persistence checks")
	_service.advance()
	_service.advance()
	_check(_service.encode() == {"schema": 1, "stage": 2}, "encode reports schema 1 and the current stage")
	for attempt in 3:
		_check(_service.restore(_service.encode()), "repeated restore accepts the service's own snapshot")
		_check(_service.stage() == 2 and _service.unlocked_regions() == [&"quarry"], "repeated restore keeps stage and unlocks stable")
	_check(_service.restore({}) and _service.stage() == 0 and _service.unlocked_regions().is_empty(),
		"an old save without this section resets to stage 0")
	_check(_service.restore({"schema": 1, "stage": 1}) and _service.stage() == 1, "a valid middle snapshot restores")
	var before: Dictionary = _service.encode()
	for bad: Dictionary in [
		{"schema": 2, "stage": 1}, {"schema": "1", "stage": 1}, {"stage": 1},
		{"schema": 1}, {"schema": 1, "stage": -1}, {"schema": 1, "stage": 3},
		{"schema": 1, "stage": 1.5}, {"schema": 1, "stage": true}, {"schema": 1, "stage": "1"},
		{"schema": 1, "stage": 1, "extra": 1},
	]:
		_check(not _service.restore(bad) and _service.encode() == before, "refused snapshot keeps the current state")
	_check(_service.restore({"schema": 1, "stage": 0}) and _service.stage() == 0, "a zero-stage snapshot restores")
	_check(_service.advance() and _service.stage() == 1, "restored chain still advances one stage at a time")


func _check_shipped_chain() -> void:
	_check(Quarry != null and Quarry.get_script() == preload("res://scripts/data/region_unlock_data.gd"),
		"the shipped road chain loads as RegionUnlockData")
	_check(Quarry.id == &"quarry_road" and Quarry.stages.size() == 3 and Quarry.is_valid(), "the shipped chain has three valid stages")
	_check(String(Quarry.stages[0].get("label", "")) == "未修" and String(Quarry.stages[1].get("label", "")) == "材料已交" \
		and String(Quarry.stages[2].get("label", "")) == "通路", "shipped labels follow 未修 / 材料已交 / 通路")
	var last_cost: Dictionary = Quarry.stages[2].get("cost", {})
	_check(StringName(Quarry.stages[2].get("unlock_region", &"")) == &"quarry" and last_cost.is_empty(),
		"the final shipped stage unlocks the quarry without asking for more materials")
	var first_cost: Dictionary = Quarry.stages[0].get("cost", {})
	var second_cost: Dictionary = Quarry.stages[1].get("cost", {})
	_check(not first_cost.is_empty() and not second_cost.is_empty(), "both repair stages demand materials")
	_check(_service.configure(Quarry), "the shipped chain configures")
	var first: Dictionary[StringName, int] = _service.requirement()
	_check(int(first.get(&"wood", 0)) > 0 and int(first.get(&"stone", 0)) > 0, "stage 0 asks for wood and stone")
	_check(_service.requirements_met(first) and _service.advance() and _service.stage() == 1, "paying stage 0 materials advances once")
	_check(_service.requirements_met(_service.requirement()) and _service.advance(), "paying stage 1 materials finishes the road")
	_check(_service.unlocked_regions() == [&"quarry"], "the finished road unlocks the quarry")
	_check(_service.restore(_service.encode()) and _service.stage() == 2, "the shipped chain survives an encode/restore round trip")


func _check_purity_and_release() -> void:
	var road := _road()
	_check(_service.configure(road), "fresh chain configures for the copy check")
	road.stages.clear()
	_check(_service.requirement() == _have([[&"wood", 4], [&"stone", 2]]), "the service keeps a normalized copy of the definition")
	_service.advance()
	_service.advance()
	_check(_service.stage() == 2 and _service.unlocked_regions() == [&"quarry"], "the private copy still drives stages and unlocks")
	_service.release()
	_check(_service.stage() == 0 and _service.requirement().is_empty() and _service.unlocked_regions().is_empty() and not _service.advance(),
		"release clears the chain and its progress")
	_check(_service.encode() == {"schema": 1, "stage": 0}, "a released service encodes the empty stage")
	_check(not _service.restore({"schema": 1, "stage": 1}), "a released service refuses snapshots")
	_check(_service.configure(_road()), "the composition root can configure a released service again")
