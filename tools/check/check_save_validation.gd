extends SceneTree
## 合法 JSON 内层类型损坏、元数据查询不覆盖槽位、不兼容版本写保护。

const Save := preload("res://scripts/persistence/save_system.gd")
const Migrations := preload("res://scripts/persistence/save_migrations.gd")
var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[save_validation] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var save: Node = main.get_node("Systems/Save")
	save.autoload_enabled = false
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var clock: Node = main.get_node("Systems/Time")
	clock.running = false
	var baseline: Dictionary = save.collect()
	for bad: Variant in [null, [], {}, "bad", true]:
		var document: Dictionary = baseline.duplicate(true)
		document["name"] = bad
		document["coins"] = bad
		for section: String in Migrations.SCALARS:
			if document.has(section):
				for key: String in Migrations.SCALARS[section]:
					# 字符串字段的 "bad" 本身是有效字符串，其他内层错误必须被过滤。
					document[section][key] = bad
		document["inventory"]["slots"] = [{"id": bad, "count": bad}]
		document["farm_activities"]["slots"] = [{"id": bad, "count": bad}]
		document["farm_activities"]["depleted"] = [bad]
		document["forage"]["patches"] = [bad]
		document["tutorial"]["harvests_again"] = {"carrot": bad}
		document["friendship"]["points"] = {"gardener": bad}
		for id: Variant in document.world_objects:
			document.world_objects[id] = {"hits": bad, "cleared": bad, "felled": bad, "stump_hits": bad}
		document["berries"]["bushes"] = [{"x": bad, "y": bad, "kind": bad, "stage": bad, "regrow": bad}]
		save.apply(document)
		await process_frame
		await process_frame
		_check(clock.day >= 1 and clock.minutes >= 0 and clock.minutes <= clock.CLOSE_MINUTES, "invalid clock scalars fall back without aborting restore")
		var cleaned: Dictionary = save.collect()
		_check(cleaned.coins >= 0 and cleaned.inventory.slots is Array, "malformed scalar document finishes a complete restore")
		save.apply(baseline)
		await process_frame
	_check(save.save_game(), "live game owns a writable snapshot")
	var path: String = save.save_path()
	var original: String = FileAccess.get_file_as_string(path)
	var query := Save.new()
	query.autoload_enabled = false
	root.add_child(query)
	query.use_slot(save.current_slot)
	_check(not query.save_game(), "title metadata query cannot overwrite a game slot")
	_check(FileAccess.get_file_as_string(path) == original, "metadata save rejection preserves file bytes")
	var broken := baseline.duplicate(true)
	broken.time.day = []
	broken.time.minutes = {}
	broken.coins = []
	broken.name = []
	_check(save.storage.write(path, broken), "malformed but syntactically valid fixture writes")
	var summary: Dictionary = query.slot_summary(save.current_slot)
	_check(summary.exists and summary.day >= 1 and summary.coins >= 0, "title slot summary handles corrupt scalar types")
	_check(save.load_game(), "sanitized document can be loaded from disk")
	save.use_slot(3)
	var future: Dictionary = {"version": 99, "name": "future", "coins": 123}
	_check(save.storage.write(save.save_path(), future), "future version fixture writes")
	var bytes: String = FileAccess.get_file_as_string(save.save_path())
	_check(not save.load_game() and not save.save_game(), "failed future-version load blocks later autosave")
	_check(FileAccess.get_file_as_string(save.save_path()) == bytes, "future-version slot survives attempted autosave")
	_check(not bool(query.slot_summary(3).get("compatible", true)), "incompatible slot is marked for title UI")
	save.delete_save(3)
	save.use_slot(1)
	save.apply(baseline)
	_check(save.save_game(), "explicit new slot after deletion restores write capability")
	query.queue_free()
	main.queue_free()
	print("[save_validation] %d checks, %d failures; reached end" % [_checks, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
