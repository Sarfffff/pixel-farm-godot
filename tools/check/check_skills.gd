extends SceneTree
## B3-01 独立组件检查；真实劳动最终接线仍由主线程的整合套件验证。

const Service := preload("res://scripts/progression/skill_service.gd")
const Presenter := preload("res://scripts/ui/presenters/skill_presenter.gd")
const SkillScene := preload("res://scenes/ui/skill_panel.tscn")
const FishingSession := preload("res://scripts/activities/fishing_session.gd")
const Modals := preload("res://scripts/ui/common/modal_coordinator.gd")

class Clock extends Node:
	var day: int = 5
	func today() -> int: return day
	func to_dict() -> Dictionary: return {"day": day, "minutes": 1200}
	func from_dict(data: Dictionary) -> void: day = int(data.get("day", 1))

class ViewDouble extends Control:
	signal selection_requested(id: StringName)
	signal refresh_requested
	var renders: int = 0
	var data: Dictionary = {}
	func render(snapshot: Dictionary) -> void:
		data = snapshot
		renders += 1
	func set_open(value: bool) -> void: visible = value

class FailingInstallStore extends "res://scripts/persistence/json_save_store.gd":
	func _install(_temp: String, _destination: String) -> Error: return ERR_CANT_CREATE

var _checks: int = 0
var _failures: int = 0
var _stage: Control
var _clock: Clock
var _bag: Inventory
var _energy: Node
var _save: SaveSystem
var _service: RefCounted
var _producer_busy: bool = false
var _harvested: Dictionary = {}
var _completed_groups: Array[StringName] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[skills] FAIL: " + message)


func _settle() -> void:
	for frame in 4: await process_frame


func _new_service() -> RefCounted:
	var service := Service.new()
	_check(service.configure(_clock.today), "service configures from runtime Resource catalog")
	return service


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_stage = Control.new()
	root.add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clock = Clock.new()
	_bag = Inventory.new()
	_energy = preload("res://scripts/player/stamina.gd").new()
	_save = SaveSystem.new()
	_save.autoload_enabled = false
	for node: Node in [_clock, _bag, _energy, _save]: _stage.add_child(node)
	_service = _new_service()
	_save.snapshots.register_section(&"time", _clock.to_dict, _clock.from_dict)
	_save.snapshots.register_section(&"inventory", _bag.to_dict, _bag.from_dict)
	_save.snapshots.register_section(&"stamina", _energy.to_dict, _energy.from_dict)
	_save.snapshots.register_section(&"skills", _service.encode, _service.restore, TYPE_DICTIONARY, true)
	await _settle()
	_check_catalog_and_every_level()
	_check_receipts_and_configuration()
	_check_atomic_notifications()
	_check_summary_and_restore()
	await _check_producer_boundary_and_disk()
	await _check_mvp()
	_check(_completed_groups == [&"catalog", &"receipts", &"atomic", &"summary", &"producer", &"mvp"], "all six scenario groups reached their final assertions")
	_save.snapshots.clear()
	_service.release()
	_service = null
	_stage.queue_free()
	await _settle()
	_check(not is_instance_valid(_stage) and not paused, "final cleanup releases all fixtures and modal ownership")
	print("[skills] reached end; %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_catalog_and_every_level() -> void:
	var service: RefCounted = _new_service()
	var definitions: Array[SkillDefinition] = service.definitions()
	_check(definitions.size() == 3, "three configured skills ship")
	_check(definitions[0].id == &"agriculture" and definitions[1].id == &"foraging" and definitions[2].id == &"fishing", "catalog order and stable IDs are deterministic")
	var actions: Dictionary = {&"agriculture": &"harvest", &"foraging": &"chop_tree", &"fishing": &"catch_fish"}
	var sequence: int = 0
	for definition: SkillDefinition in definitions:
		_check(definition.is_valid() and definition.levels.size() == 5, "%s has five valid configured levels" % definition.id)
		_check(service.level_of(definition.id) == 0 and service.xp_of(definition.id) == 0, "%s starts at zero" % definition.id)
		for level in range(1, 6):
			var before: Dictionary = _actual_capabilities(service)
			var guard: int = 0
			while service.level_of(definition.id) < level and guard < 10001:
				sequence += 1
				_check(service.record_labor(actions[definition.id], {"id": "levels/%d" % sequence, "day": _clock.day}), "configured successful labor advances %s" % definition.id)
				guard += 1
			_check(service.level_of(definition.id) == level, "%s reaches level %d" % [definition.id, level])
			_check(_actual_capabilities(service) != before, "%s level %d changes a real integer cost or fishing parameter" % [definition.id, level])
		var capped: Dictionary = service.encode()
		_check(not service.record_labor(actions[definition.id], {"id": "cap/%s" % definition.id, "day": _clock.day}), "maxed %s rejects further XP" % definition.id)
		_check(service.xp_of(definition.id) == definition.max_xp() and service.encode() == capped, "max level neither overflows nor retains useless receipt history")
	_check(service.stamina_cost(&"harvest", 2) == 1 and service.stamina_cost(&"seeds", 2) == 1, "agriculture harvest and planting benefits apply")
	_check(service.stamina_cost(&"hoe", 4) == 2 and service.stamina_cost(&"watering_can", 3) == 2, "hoe and upgraded watering costs use cumulative rules")
	_check(service.stamina_cost(&"axe", 8) == 3 and service.stamina_cost(&"forage", 2) == 1, "foraging benefits apply to current tool costs")
	_check(service.stamina_cost(&"fishing", 4) == 1 and service.stamina_cost(&"stone_pickaxe", 6) == 6, "fishing reaches one stamina and mining remains outside the scope")
	_check(service.stamina_cost(&"axe", 1) == 1 and service.stamina_cost(&"harvest", 0) == 0, "discounts never create free positive-cost labor or charge a free action")
	var fishing: Dictionary = service.fishing_parameters(1.5, 3.0, 2.0)
	_check(is_equal_approx(fishing.wait_min, 1.2) and is_equal_approx(fishing.wait_max, 2.4) and is_equal_approx(fishing.bite_window, 2.5), "fishing levels change the actual wait and reel window")
	var invalid_parameters: Dictionary = service.fishing_parameters(NAN, -1.0, INF)
	_check(is_finite(invalid_parameters.wait_min) and invalid_parameters.wait_max >= invalid_parameters.wait_min and invalid_parameters.bite_window > 0.0, "invalid base fishing scalars do not escape into engine timing")
	var effects: Dictionary = service.effects_of(&"agriculture")
	effects.stamina_reductions[&"harvest"] = 99
	_check(service.stamina_cost(&"harvest", 2) == 1, "effect query results cannot mutate the model")
	service.release()
	_completed_groups.append(&"catalog")


func _actual_capabilities(service: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in [&"hoe", &"watering_can", &"seeds", &"axe", &"harvest", &"forage", &"fishing"]:
		var costs: Dictionary = {&"hoe": 4, &"watering_can": 2, &"seeds": 2, &"axe": 8, &"harvest": 2, &"forage": 2, &"fishing": 4}
		result[action] = service.stamina_cost(action, costs[action])
	result["timing"] = service.fishing_parameters(1.5, 3.0, 2.0)
	return result


func _check_receipts_and_configuration() -> void:
	var service: RefCounted = _new_service()
	_check(service.record_labor(&"harvest", {"id": "farm/crop/one/round/1", "day": _clock.day, "xp": 999999, "count": 1000}), "valid labor receipt is accepted")
	_check(service.xp_of(&"agriculture") == 8, "external XP/count cannot override the authored points")
	_check(not service.record_labor(&"harvest", {"id": "farm/crop/one/round/1", "day": _clock.day}), "duplicate receipt is rejected")
	_check(not service.record_labor(&"forage", {"id": "farm/crop/one/round/1", "day": _clock.day}), "receipt ID is deduplicated across action types")
	_clock.day += 1
	_check(not service.record_labor(&"harvest", {"id": "farm/crop/one/round/1", "day": _clock.day}), "changing the date cannot replay a credited stable ID")
	for action: StringName in [&"purchase", &"sell", &"transfer", &"crafting", &"quest", &"mail", &"restore", &"watering_can", &"hoe", &"seeds", &"mine"]:
		_check(not service.record_labor(action, {"id": "forbidden/%s" % action, "day": _clock.day}), "non-labor action %s cannot award experience" % action)
	var before: Dictionary = service.encode()
	for receipt: Dictionary in [
		{}, {"id": true, "day": _clock.day}, {"id": [], "day": _clock.day},
		{"id": " ", "day": _clock.day}, {"id": "bad\nid", "day": _clock.day},
		{"id": "x".repeat(181), "day": _clock.day}, {"id": "day/string", "day": "6"},
		{"id": "day/float", "day": 6.5}, {"id": "day/bool", "day": true},
		{"id": "day/past", "day": _clock.day - 1}, {"id": "day/future", "day": _clock.day + 1},
		{"id": "day/nan", "day": NAN}, {"id": "day/inf", "day": INF},
	]:
		_check(not service.record_labor(&"harvest", receipt), "invalid receipt ID/day is refused without mutation")
	_check(service.encode() == before, "all rejected receipts preserve the committed state")
	var definitions: Array[SkillDefinition] = service.definitions()
	definitions[0].experience_for[&"harvest"] = 9999
	_check(service.record_labor(&"harvest", {"id": "farm/crop/two/round/1", "day": float(_clock.day)}), "integral JSON-style day is accepted")
	_check(service.xp_of(&"agriculture") == 16, "definition queries return copies rather than live rule mutation")
	_check(service.record_labor(&"forage", {"id": "gather/one", "day": _clock.day}) and service.record_labor(&"clear_stump", {"id": "gather/stump/one", "day": _clock.day}) and service.xp_of(&"foraging") == 5, "forage and stump use their distinct configured per-labor rewards")
	var bad := definitions[0].duplicate(true) as SkillDefinition
	bad.cumulative_xp = PackedInt32Array([10, 10, 9, 8, 7])
	var snapshot: Dictionary = service.encode()
	var configured_definitions: Array[SkillDefinition] = [bad]
	_check(not service.configure(_clock.today, configured_definitions) and service.encode() == snapshot, "bad curve reconfiguration preserves the old service")
	var valid: SkillDefinition = service.definitions()[0]
	configured_definitions.assign([valid, valid])
	_check(not service.configure(_clock.today, configured_definitions), "duplicate skill ID is rejected")
	var duplicate_action := valid.duplicate(true) as SkillDefinition
	duplicate_action.id = &"other"
	configured_definitions.assign([valid, duplicate_action])
	_check(not service.configure(_clock.today, configured_definitions), "duplicate labor mapping is rejected")
	valid.levels[0].stamina_reductions.clear()
	configured_definitions.assign([valid])
	_check(not service.configure(_clock.today, configured_definitions), "a level with no capability change is invalid")
	service.release()
	_check(service.level_of(&"agriculture") == 0 and not service.record_labor(&"harvest", {"id": "after/release", "day": _clock.day}), "released service no longer exposes old state or accepts labor")
	_clock.day = 5
	_completed_groups.append(&"receipts")


func _check_atomic_notifications() -> void:
	var service: RefCounted = _new_service()
	for index in 2: service.record_labor(&"harvest", {"id": "atomic/before/%d" % index, "day": _clock.day})
	var observations: Array[bool] = []
	var nested: Array[bool] = []
	var levels: Array[Vector2i] = []
	var watcher := func() -> void:
		observations.append(service.xp_of(&"agriculture") == 24 and service.level_of(&"agriculture") == 1 and service.stamina_cost(&"harvest", 2) == 1 and service.pending_upgrades().size() == 1 and service.encode().receipts.has("atomic/commit"))
		nested.append(service.record_labor(&"harvest", {"id": "atomic/nested", "day": _clock.day}))
		nested.append(service.restore({}))
		nested.append(service.configure(_clock.today))
		nested.append(service.acknowledge_summary(_clock.day))
		service.release()
	var advanced := func(_id: StringName, old_level: int, new_level: int) -> void:
		levels.append(Vector2i(old_level, new_level))
		nested.append(service.record_labor(&"forage", {"id": "atomic/level_nested", "day": _clock.day}))
	service.changed.connect(watcher)
	service.level_advanced.connect(advanced)
	_check(service.record_labor(&"harvest", {"id": "atomic/commit", "day": _clock.day}), "outer labor transaction commits")
	service.changed.disconnect(watcher)
	service.level_advanced.disconnect(advanced)
	_check(observations == [true] and levels == [Vector2i(0, 1)], "all observers see complete XP, capability, receipt and summary in one committed notification")
	_check(not nested.has(true) and service.xp_of(&"agriculture") == 24 and not service.busy, "all mutation ports reject observer reentry and return control")
	service.release()
	_completed_groups.append(&"atomic")


func _check_summary_and_restore() -> void:
	var template: SkillDefinition = _service.definitions()[0]
	template.cumulative_xp = PackedInt32Array([1, 2, 3, 4, 5])
	var service := Service.new()
	_check(service.configure(_clock.today, [template]), "short curve fixture configures through the same Resource contract")
	var advanced: Array[int] = []
	var record := func(_id: StringName, _old: int, level: int) -> void: advanced.append(level)
	service.level_advanced.connect(record)
	_check(service.record_labor(&"harvest", {"id": "summary/all_levels", "day": _clock.day}), "one productive action can cross several levels")
	_check(advanced == [5] and service.pending_upgrades().size() == 5, "cross-level notice covers each authored benefit without five reward transactions")
	var state: Dictionary = service.encode()
	var capabilities: Dictionary = _actual_capabilities(service)
	var notice: Array[Dictionary] = service.pending_upgrades()
	notice[0].description = "tampered"
	_check(service.pending_upgrades()[0].description != "tampered", "summary query is a read-only copy")
	_check(service.pending_upgrades(_clock.day - 1).is_empty() and not service.acknowledge_summary(_clock.day + 1), "summary respects earned day and cannot acknowledge the future")
	_check(service.acknowledge_summary(_clock.day) and service.pending_upgrades().is_empty(), "nightly acknowledgment clears only notification state")
	_check(_actual_capabilities(service) == capabilities and not service.acknowledge_summary(_clock.day), "acknowledgment is idempotent and never removes earned abilities")
	advanced.clear()
	for attempt in 3:
		_check(service.restore(state), "repeated restore accepts the same valid skill section")
		_check(service.pending_upgrades().size() == 5 and service.level_of(&"agriculture") == 5 and _actual_capabilities(service) == capabilities, "restored summary and abilities remain stable")
	_check(advanced.is_empty(), "restoring never emits an earned-level event or grants rewards")
	_check(not service.record_labor(&"harvest", {"id": "summary/all_levels", "day": _clock.day}), "saved receipt remains deduplicated after restore")
	_check(not service.restore({"version": 2}) and service.encode() == state, "future section version is rejected without erasing current state")
	_check(not service.restore({"version": true}) and not service.restore({"version": "1"}), "bad section versions are not coerced")
	_check(service.restore({"xp": {"agriculture": INF}, "receipts": [], "pending_upgrades": "bad"}) and service.xp_of(&"agriculture") == 0, "bad inner scalar and collection types restore safely without XP")
	_check(service.restore({"xp": {"agriculture": 999999, "unknown": 9999}, "receipts": {"kept/id": 2, "bad/day": true}, "pending_upgrades": [
		{"skill": "agriculture", "level": 1, "day": 2}, {"skill": "agriculture", "level": 1, "day": 2},
		{"skill": "agriculture", "level": 6, "day": 2}, {"skill": "unknown", "level": 1, "day": 2},
	]}), "bounded malformed section is sanitized")
	_check(service.xp_of(&"agriculture") == 5 and service.pending_upgrades().size() == 1 and not service.encode().receipts.has("bad/day"), "XP clamps, unknown skills and invalid/repeated pending entries are ignored")
	_check(service.restore({"xp": {"agriculture": 0}, "receipts": {"a": 1, "b": 1, "c": 1, "d": 1, "e": 1, "f": 1}}), "lowered experience curve still preserves legitimate older receipt history")
	_check(not service.record_labor(&"harvest", {"id": "a", "day": _clock.day}), "a preserved historic receipt cannot earn XP after curve rebalancing")
	var bounded: Dictionary = service.encode()
	var excessive_receipts: Dictionary = {}
	for index in range(SkillDefinition.MAX_EXPERIENCE + 1): excessive_receipts["receipt/%d" % index] = 1
	_check(not service.restore({"receipts": excessive_receipts}) and service.encode() == bounded, "excessive receipt history is refused without truncating deduplication")
	_check(not service.restore({"pending_upgrades": [{}, {}, {}, {}, {}, {}]}) and service.encode() == bounded, "excessive upgrade rows are refused without partial restoration")
	_check(service.restore({}) and service.level_of(&"agriculture") == 0 and service.pending_upgrades().is_empty() and service.encode().receipts.is_empty(), "old save missing skills clears prior-slot XP, receipts and summary")
	service.level_advanced.disconnect(record)
	service.release()
	_completed_groups.append(&"summary")


## 测试组合根示范：使用真实库存/体力/鱼状态；正式 FarmTiller 等接线由整合者验证。
func _commit_harvest(id: String) -> bool:
	if _producer_busy or _harvested.has(id) or not _bag.has_space_for(&"carrot", 1): return false
	_producer_busy = true
	var cost: int = _service.stamina_cost(&"harvest", 2)
	if not _energy.can_spend(cost):
		_producer_busy = false
		return false
	_bag.begin_update()
	_energy.begin_update()
	_energy.spend(cost)
	_bag.add_item(&"carrot", 1)
	_harvested[id] = true
	_service.record_labor(&"harvest", {"id": id, "day": _clock.day})
	_bag.end_update()
	_energy.end_update()
	_producer_busy = false
	return true


func _check_producer_boundary_and_disk() -> void:
	var guard: int = 0
	while _bag.has_space_for(&"stone", 1) and guard < 80:
		_bag.add_item(&"stone", 99, &"purchase")
		guard += 1
	var before_energy: int = _energy.value
	_check(not _commit_harvest("world/crop/full") and _service.xp_of(&"agriculture") == 0 and _energy.value == before_energy, "full-bag harvest failure never reaches labor submission or costs stamina")
	_bag.remove_item(&"stone", _bag.count_of(&"stone"))
	_energy.value = 0
	_check(not _commit_harvest("world/crop/no_energy") and _service.xp_of(&"agriculture") == 0, "failed stamina precondition awards no experience")
	_energy.refill()
	var observed: Array[bool] = []
	var observer := func() -> void:
		observed.append(_harvested.has("world/crop/success") and _bag.count_of(&"carrot") == 1 and _service.xp_of(&"agriculture") == 8)
	_service.changed.connect(observer)
	_check(_commit_harvest("world/crop/success"), "successful producer commits actual goods and labor once")
	_service.changed.disconnect(observer)
	_check(observed == [true] and not _commit_harvest("world/crop/success"), "model notification sees committed source and goods; producer refuses a duplicate")
	for source: StringName in [&"purchase", &"transfer", &"crafting", &"quest", &"mail"]:
		_bag.add_item(&"wood", 1, source)
	_check(_service.xp_of(&"agriculture") == 8 and _service.xp_of(&"foraging") == 0, "real inventory additions from unrelated sources never grant skill XP")
	var session := FishingSession.new()
	_check(session.start(&"common_carp", 0.01), "real fishing session starts")
	session.tick(0.02, 2.0)
	_check(session.reel(), "real fishing session creates pending catch only on a valid bite")
	guard = 0
	while _bag.has_space_for(&"stone", 1) and guard < 80:
		_bag.add_item(&"stone", 99, &"purchase")
		guard += 1
	_check(not _claim_fish(session, "world/fish/cast/1") and session.pending_fish != &"" and _service.xp_of(&"fishing") == 0, "full-bag claim retains pending fish and awards no XP")
	_bag.remove_item(&"stone", _bag.count_of(&"stone"))
	_check(_claim_fish(session, "world/fish/cast/1") and _service.xp_of(&"fishing") == 10 and session.pending_fish == &"", "successful claim submits fish receipt after pending state and inventory commit")
	_check(not _claim_fish(session, "world/fish/cast/1") and _service.xp_of(&"fishing") == 10, "repeated claim cannot award fish experience again")
	var original_store := _save.storage
	_save.storage = FailingInstallStore.new()
	print("[skills] expected fault: isolated JSON installation refuses a write")
	_check(not _save.save_game() and _service.xp_of(&"agriculture") == 8, "failed file write leaves earned XP and player control intact")
	_save.storage = original_store
	_check(_save.save_game(), "manual retry writes the real skills section")
	var state: Dictionary = _service.encode()
	var carrots: int = _bag.count_of(&"carrot")
	for attempt in 3:
		_service.restore({})
		_check(_save.load_game(), "isolated skill save round trip succeeds")
		_check(_service.encode() == state and _bag.count_of(&"carrot") == carrots, "disk restore preserves XP/receipts and never generates extra goods")
	_check(not _service.record_labor(&"harvest", {"id": "world/crop/success", "day": _clock.day}), "disk-restored receipt cannot be farmed again")
	var legacy: Dictionary = _save.collect()
	legacy.erase("skills")
	_save.apply(legacy)
	_check(_service.xp_of(&"agriculture") == 0 and _service.xp_of(&"fishing") == 0, "old main save without skills clears a prior slot through restore_missing")
	await _settle()
	_completed_groups.append(&"producer")


func _claim_fish(session: RefCounted, id: String) -> bool:
	if session.pending_fish == &"" or not _bag.has_space_for(session.pending_fish, 1): return false
	_bag.begin_update()
	var fish: StringName = session.claim()
	_bag.add_item(fish, 1)
	_service.record_labor(&"catch_fish", {"id": id, "day": _clock.day})
	_bag.end_update()
	return true


func _check_mvp() -> void:
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var view: Control = SkillScene.instantiate()
	var presenter := Presenter.new()
	var modals := Modals.new()
	for node: Node in [view, presenter, modals]: _stage.add_child(node)
	modals.register_panel(view)
	presenter.configure(_service, view)
	_check(view._list.item_count == 3 and view._body.text.contains("总经验 0/320"), "real panel renders the three skills and current experience")
	presenter.open()
	_check(view.visible and paused, "skill view uses the existing modal pause boundary")
	for index in 3:
		_service.record_labor(&"harvest", {"id": "mvp/crop/%d" % index, "day": _clock.day})
	_check(view._heading.text.contains("1/5级") and view._body.text.contains("收获体力减少1"), "view follows real upgrade query without implementing rules")
	_check(presenter.upgrade_lines().size() == 1 and _service.pending_upgrades().size() == 1, "nightly presenter read does not consume the pending notification")
	view.selection_requested.emit(&"fishing")
	_check(view._heading.text.contains("钓鱼") and view._body.text.contains("咬钩"), "selection displays the authored skill capability roadmap")
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(800, 600)]:
		root.size = resolution
		await _settle()
		_check(view.get_viewport_rect().grow(1).encloses(view._frame.get_global_rect()), "skill panel fits viewport %s" % resolution)
		_check(view._body.size.x <= view._scroll.size.x, "skill text wraps within scroll width")
	if "--preview" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280, 720)
		await _settle()
		await RenderingServer.frame_post_draw
		var path: String = "user://skills.png"
		_check(root.get_texture().get_image().save_png(path) == OK, "native skill preview writes")
		print("[skills] screenshot=" + ProjectSettings.globalize_path(path))
	var escaped := InputEventKey.new()
	escaped.keycode = KEY_ESCAPE
	escaped.physical_keycode = KEY_ESCAPE
	escaped.pressed = true
	Input.parse_input_event(escaped)
	await _settle()
	_check(not view.visible and not paused, "Escape closes skill panel and releases modal ownership")
	var replacement := ViewDouble.new()
	_stage.add_child(replacement)
	for attempt in 2: presenter.configure(_service, replacement)
	_check(view.selection_requested.get_connections().is_empty() and view.refresh_requested.get_connections().is_empty(), "reconfiguration releases former view intentions")
	var renders: int = replacement.renders
	view.selection_requested.emit(&"foraging")
	_check(replacement.renders == renders, "old view cannot select the replacement's skill")
	_service.record_labor(&"forage", {"id": "mvp/forage/1", "day": _clock.day})
	_check(replacement.renders == renders + 1, "repeated configure retains only one model subscription")
	renders = replacement.renders
	_stage.remove_child(presenter)
	_service.record_labor(&"forage", {"id": "mvp/forage/2", "day": _clock.day})
	_check(replacement.renders == renders and replacement.selection_requested.get_connections().is_empty() and not _service.changed.is_connected(presenter.refresh), "presenter exit unbinds model and view")
	presenter.free()
	presenter = Presenter.new()
	_stage.add_child(presenter)
	presenter.configure(_service, replacement)
	replacement.queue_free()
	await _settle()
	_check(not _service.changed.is_connected(presenter.refresh), "destroying the view releases the live presenter source binding")
	var disposable := ViewDouble.new()
	_stage.add_child(disposable)
	presenter.configure(_service, disposable)
	presenter.dispose()
	presenter.dispose()
	_check(not _service.changed.is_connected(presenter.refresh) and disposable.refresh_requested.get_connections().is_empty(), "explicit repeated dispose unbinds safely")
	view.open()
	view.queue_free()
	await _settle()
	_check(not paused and not modals.has_open_panel(), "destroying an open skill view releases its pause")
	_completed_groups.append(&"mvp")
