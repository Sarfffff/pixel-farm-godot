extends SceneTree
## B3-02：真实库存净容量/非单调批数、冻结Resource、资格、原子通知和MVP解绑。

const Service := preload("res://scripts/progression/crafting_service.gd")
const Presenter := preload("res://scripts/ui/presenters/workbench_presenter.gd")
const WorkbenchView := preload("res://scripts/ui/panels/workbench_panel.gd")
const SEEDS: StringName = &"carrot_seed_pack"

class ExchangeFailure extends Inventory:
	func exchange_batch(_consumed: Dictionary, _produced: Dictionary, _source: StringName = &"crafting") -> bool:
		return false

class ViewDouble extends Control:
	signal craft_requested(id: StringName)
	signal batch_craft_requested(id: StringName, batches: int)
	signal recipe_selected(id: StringName)
	signal quantity_changed(batches: int)
	signal max_requested
	signal retry_save_requested
	var snapshot: Dictionary = {}
	var renders: int = 0
	func render(data: Dictionary) -> void:
		snapshot = data
		renders += 1
	func set_open(value: bool) -> void: visible = value

var _checks: int = 0
var _failures: int = 0
var _main: Node
var _bag: Inventory
var _save: Node
var _service: RefCounted
var _chapter: bool = true
var _usable: bool = false
var _save_ok: bool = true
var _writes: int = 0
var _access: Dictionary = {}
var _probe_busy: bool = false
var _end: bool = false


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[crafting] FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_main.get_node("Systems/Time").running = false
	_bag = _main.get_node("Systems/Inventory")
	_save = _main.get_node("Systems/Save")
	_save.use_slot(3)
	_check(_bag.has_method(&"preview_exchange_batch") and _bag.has_method(&"exchange_batch"), "real Inventory exposes the frozen public net-exchange ports")
	_service = Service.new()
	_configure()
	_check_definitions_and_access()
	_check_quantities_and_capacity()
	_check_atomic_observers()
	_check_save_failures()
	_check_exchange_failure()
	await _check_presenter_and_view()
	_service.release()
	_main.queue_free()
	await process_frame
	_end = true
	_check(_end, "all definitions, transaction, persistence and View lifecycle probes reached end")
	print("[crafting] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _configure() -> void:
	_service.configure(_bag, func() -> bool: return _chapter, _persist, _recipe_access, func(_item: StringName) -> bool: return _usable)


func _persist() -> bool:
	_writes += 1
	return _save_ok and _save.save_game()


func _recipe_access(id: StringName) -> Dictionary:
	return _access.get(id, {"known": true, "available": true, "reason": ""})


func _set_items(items: Dictionary, full: bool = false, spare: int = 0) -> void:
	var slots: Array[Dictionary] = []
	for id: StringName in Inventory.TOOL_IDS: slots.append({"id": String(id), "count": 1})
	for id: StringName in items:
		var remaining: int = int(items[id])
		while remaining > 0:
			var count: int = mini(remaining, _bag.definition(id).max_stack)
			slots.append({"id": String(id), "count": count})
			remaining -= count
	if full:
		while slots.size() < _bag.slot_count() - spare: slots.append({"id": "stone", "count": 99})
	_bag.from_dict({"slots": slots})
	_bag.today_collected = 0


func _recipe(id: StringName, ingredients: Dictionary, products: Dictionary) -> CraftingRecipeData:
	var recipe := CraftingRecipeData.new()
	recipe.id = id
	recipe.title = String(id)
	recipe.purpose = "测试已存在物品的可用转换"
	recipe.ingredients.assign(ingredients)
	recipe.products.assign(products)
	return recipe


func _check_definitions_and_access() -> void:
	_check(_service.recipes().size() == 3, "only the seed pack and two useful placeable recipes are authored")
	var seed: CraftingRecipeData = _service.recipes().filter(func(value: CraftingRecipeData) -> bool: return value.id == SEEDS)[0]
	_check(not seed.purpose.is_empty() and seed.requires_chapter, "legacy seed pack retains purpose and mandatory chapter rule")
	seed.ingredients[&"carrot"] = 999
	_check(_service.recipes().filter(func(value: CraftingRecipeData) -> bool: return value.id == SEEDS)[0].ingredients[&"carrot"] == 1, "queries cannot mutate registered Resource ingredients")
	var resource := _recipe(&"frozen", {&"wood": 1}, {&"fiber": 1})
	_check(_service.register_recipe(resource) and not _service.register_recipe(resource), "duplicate recipe ID rejected")
	resource.products[&"fiber"] = 999
	_set_items({&"wood": 3, &"carrot": 3, &"fiber": 6})
	_check(int(_service.preview(&"frozen").produced[&"fiber"]) == 1, "registration freezes external Resource mutations")
	var invalid := _recipe(&"invalid", {&"wood": 0}, {&"fiber": 1})
	_check(not _service.register_recipe(invalid), "zero ingredients rejected at registration")
	invalid.ingredients[&"wood"] = 1
	invalid.duration_seconds = NAN
	_check(not _service.register_recipe(invalid), "nonfinite recipe duration rejected")
	_chapter = false
	_check(not _service.preview(SEEDS).ok and not _service.craft(SEEDS), "injected skill permission cannot bypass the original chapter condition")
	_chapter = true
	_access[SEEDS] = {"known": false, "available": false, "reason": "尚未学会"}
	_check(not _service.catalog().any(func(row: Dictionary) -> bool: return row.id == SEEDS), "unknown recipes excluded from the player catalog")
	_check(_service.catalog(true).any(func(row: Dictionary) -> bool: return row.id == SEEDS and not row.known), "explicit diagnostics can query unknown status")
	_access[SEEDS] = {"known": true, "available": false, "reason": "需要农业等级"}
	_check(_service.preview(SEEDS).known and not _service.preview(SEEDS).available and _service.hint(SEEDS) == "需要农业等级", "known but unavailable recipe explains external qualification")
	_access.clear()
	_check(not _service.preview(&"wood_fence").ok and not _service.preview(&"storage_crate").available, "usable placement capability required even when a recipe is known")
	_usable = true
	_check(_service.preview(&"wood_fence").available and _service.preview(&"storage_crate").available, "placeable eligibility reads the injected capability port")
	_usable = false
	var legacy := Service.new()
	legacy.configure(_bag, func() -> bool: return true, _persist)
	_check(legacy.preview(SEEDS).ok and not legacy.preview(&"wood_fence").available, "three-argument legacy configure keeps seed crafting and closes ungated new devices")
	legacy.release()
	_configure()


func _check_quantities_and_capacity() -> void:
	_set_items({&"carrot": 3, &"fiber": 6})
	var baseline: Dictionary = _bag.to_dict()
	var before_writes: int = _writes
	for batches: Variant in [0, -1, true, 1.5, "2", 1000, 9223372036854775807]:
		_check(not _service.preview(SEEDS, batches).ok and not _service.craft(SEEDS, batches), "invalid batch quantity rejected: " + str(batches))
		_check(_bag.to_dict() == baseline and _writes == before_writes, "invalid quantity does not mutate or write")
	var missing: Dictionary = _service.preview(SEEDS, 4)
	_check(not missing.ok and missing.ingredients[0].missing == 1 and missing.ingredients[1].missing == 2, "preview reports total requirements and all material deficits for the selected batches")
	_check(_service.limits(SEEDS).max_material == 3 and _service.limits(SEEDS).max_craftable == 3, "material and actual craft limits use recipe batches")
	var overflow := _recipe(&"overflow", {&"wood": 1}, {&"fiber": 2147483647})
	_service.register_recipe(overflow)
	_set_items({&"wood": 2})
	_check(not _service.preview(overflow.id, 2).ok and _service.hint(overflow.id, 2).contains("数量过大"), "multiplication bounded before material/product maps are constructed")
	_check(_service.limits(overflow.id).max_material == 2 and _service.limits(overflow.id).max_craftable == 0, "material bound remains distinct from output-capacity/overflow bound")
	var protected := _recipe(&"protected", {&"hoe": 1}, {&"fiber": 1})
	_service.register_recipe(protected)
	_check(not _service.preview(protected.id).available, "permanent tools cannot be consumed")
	var nonmonotonic := _recipe(&"nonmonotonic", {&"wood": 1}, {&"fiber": 1})
	_service.register_recipe(nonmonotonic)
	_set_items({&"wood": 2}, true)
	baseline = _bag.to_dict()
	_check(not _service.preview(nonmonotonic.id, 1).ok and _service.preview(nonmonotonic.id, 2).ok, "full bag: one batch cannot free the material stack but two batches can")
	_check(_service.limits(nonmonotonic.id).max_craftable == 2 and _bag.to_dict() == baseline, "nonmonotonic maximum is exact and preview remains read-only")
	_check(not _service.craft(nonmonotonic.id, 1) and _bag.to_dict() == baseline, "full-bag failed craft retains every item")
	_check(_service.craft(nonmonotonic.id, 2) and _bag.count_of(&"wood") == 0 and _bag.count_of(&"fiber") == 2, "net-capacity batch atomically consumes and fills its freed slot")
	var multi := _recipe(&"multi", {&"wood": 1}, {&"fiber": 1, &"carrot_seeds": 1})
	_service.register_recipe(multi)
	_set_items({&"wood": 10}, true, 1)
	baseline = _bag.to_dict()
	_check(not _service.preview(multi.id).ok and not _service.craft(multi.id) and _bag.to_dict() == baseline, "multiple products cannot share one empty slot")
	_check(_service.limits(multi.id).max_craftable == 10 and _service.preview(multi.id, 10).ok, "larger batch correctly frees a second slot for multiple products")
	var same := _recipe(&"same_item", {&"wood": 1}, {&"wood": 2})
	_service.register_recipe(same)
	_set_items({&"wood": 1}, true)
	_check(_service.craft(same.id) and _bag.count_of(&"wood") == 2 and _bag.today_collected == 0, "same input/output net exchange succeeds and does not count as labor collection")
	_set_items({&"wood": 999})
	_check(_service.limits(nonmonotonic.id).max_craftable == 999 and _service.preview(nonmonotonic.id, 999).ok and not _service.preview(nonmonotonic.id, 1000).ok, "global batch cap is accepted exactly and rejects its successor")
	_check(_service.craft(nonmonotonic.id, 999) and _bag.count_of(&"wood") == 0 and _bag.count_of(&"fiber") == 999, "largest permitted batch settles exactly once")
	_set_items({&"carrot": 3, &"fiber": 6})
	var access_reentry: Array[bool] = []
	_service.configure(_bag, func() -> bool: return true, _persist, func(_id: StringName) -> Dictionary:
		access_reentry.append(_service.craft(SEEDS))
		return {"known": true, "available": true, "reason": ""})
	_service.preview(SEEDS)
	_check(not access_reentry.is_empty() and not access_reentry.has(true), "read-only qualification query also blocks synchronous mutation reentry")
	_configure()


func _observe(source: String, context: Dictionary) -> void:
	context.counts[source] = int(context.counts.get(source, 0)) + 1
	if _probe_busy:
		_check(false, "unexpected recursive notification: " + source)
		return
	_probe_busy = true
	_check(_bag.count_of(&"carrot") == 1 and _bag.count_of(&"fiber") == 2 and _bag.count_of(&"carrot_seeds") == 8, source + ": observers see the whole two-batch result")
	_check(not _service.craft(SEEDS) and not _service.retry_save(), source + ": duplicate craft/save reentry rejected even with another batch of materials")
	_check(not _service.refresh_access(), source + ": synchronous access refresh does not recursively publish")
	context.snapshots.append(JSON.parse_string(JSON.stringify(_save.collect())))
	_probe_busy = false


func _check_atomic_observers() -> void:
	_set_items({&"carrot": 3, &"fiber": 6})
	var context: Dictionary = {"counts": {}, "snapshots": []}
	var inventory_changed := _observe.bind("inventory.changed", context)
	var item_added := func(_id: StringName, _count: int) -> void: _observe("item_added", context)
	var crafted := func(_id: StringName) -> void: _observe("crafted", context)
	var batch := func(_id: StringName, count: int) -> void:
		_check(count == 2, "batch completion reports the committed recipe quantity")
		_observe("batch_crafted", context)
	var changed := _observe.bind("service.changed", context)
	_bag.changed.connect(inventory_changed)
	_bag.item_added.connect(item_added)
	_service.crafted.connect(crafted)
	_service.batch_crafted.connect(batch)
	_service.changed.connect(changed)
	var before_writes: int = _writes
	_check(_service.craft(SEEDS, 2), "real Inventory completes two recipe batches")
	_bag.changed.disconnect(inventory_changed)
	_bag.item_added.disconnect(item_added)
	_service.crafted.disconnect(crafted)
	_service.batch_crafted.disconnect(batch)
	_service.changed.disconnect(changed)
	for source: String in ["inventory.changed", "item_added", "crafted", "batch_crafted", "service.changed"]:
		_check(context.counts.get(source, 0) == 1, "one committed operation emits one " + source)
	_check(_writes == before_writes + 1 and _bag.today_collected == 0 and not _service.busy, "one save, no labor-stat inflation, transaction released")
	for snapshot: Dictionary in context.snapshots:
		for index: int in 3:
			_save.apply(snapshot)
			_check(_bag.count_of(&"carrot") == 1 and _bag.count_of(&"fiber") == 2 and _bag.count_of(&"carrot_seeds") == 8, "repeated JSON restore does not replay crafting")
	_check(_save.load_game(3) and _bag.count_of(&"carrot_seeds") == 8, "disk reload retains exactly the committed products")


func _check_save_failures() -> void:
	_set_items({&"carrot": 2, &"fiber": 4})
	_save_ok = false
	var failures: Array[int] = [0]
	var failed := func() -> void:
		failures[0] += 1
		_check(not _service.craft(SEEDS) and not _service.retry_save(), "save-failed callbacks cannot reenter crafting or retry")
	_service.save_failed.connect(failed)
	_check(_service.craft(SEEDS) and _service.save_pending and not _service.busy, "legacy single-batch craft retains committed products after save failure")
	var baseline: Dictionary = _bag.to_dict()
	_check(not _service.retry_save() and _service.save_pending and _bag.to_dict() == baseline, "failed retry preserves products and materials")
	_save_ok = true
	_check(_service.retry_save() and not _service.save_pending and _bag.to_dict() == baseline, "successful retry saves existing result without crafting again")
	var before: int = _writes
	_check(_service.retry_save() and _writes == before and failures[0] == 2, "duplicate successful retry performs no extra write or settlement")
	_service.save_failed.disconnect(failed)


func _check_exchange_failure() -> void:
	var bag := ExchangeFailure.new()
	root.add_child(bag)
	bag.add_item(&"carrot", 1, &"transfer")
	bag.add_item(&"fiber", 2, &"transfer")
	var service := Service.new()
	service.configure(bag, func() -> bool: return true, _persist)
	var before: Dictionary = bag.to_dict()
	_check(service.preview(SEEDS).ok and not service.craft(SEEDS) and bag.to_dict() == before and not service.busy, "commit-port rejection after successful preview preserves inventory and releases transaction")
	service.release()
	bag.queue_free()


func _check_presenter_and_view() -> void:
	_set_items({&"carrot": 3, &"fiber": 6})
	var view := ViewDouble.new()
	_main.get_node("UI").add_child(view)
	var presenter := Presenter.new()
	_main.get_node("Systems").add_child(presenter)
	presenter.configure(_service, _bag, view)
	_check(view.snapshot.selected == SEEDS and view.snapshot.max_craftable == 3, "Presenter reads service limits and chooses legacy seed recipe")
	view.quantity_changed.emit(2)
	_check(view.snapshot.batches == 2 and view.snapshot.products_text.contains("8"), "quantity intent renders service-calculated total products")
	view.max_requested.emit()
	_check(view.snapshot.batches == 3, "maximum intent selects actual service result")
	_access[SEEDS] = {"known": true, "available": false, "reason": "技能暂未达到"}
	_service.refresh_access()
	_check(not view.snapshot.detail.ok and view.snapshot.detail.reason == "技能暂未达到", "explicit access refresh updates an open View")
	_access.clear()
	_service.refresh_access()
	view.quantity_changed.emit(2)
	_save_ok = false
	view.batch_craft_requested.emit(SEEDS, 2)
	_check(view.snapshot.save_pending and view.snapshot.message.contains("保存失败") and _bag.count_of(&"carrot_seeds") == 8, "batch intent surfaces persistent save-failure text")
	view.retry_save_requested.emit()
	_check(view.snapshot.save_pending and view.snapshot.message.contains("保存失败"), "failed retry retains service-derived visible warning")
	var manual_saved := func(_slot: int) -> void: _service.confirm_saved()
	_save.saved.connect(manual_saved)
	_save_ok = true
	_check(_save.save_game() and not view.snapshot.save_pending and not view.snapshot.message.contains("保存失败") and not view.snapshot.message.contains("仍失败"), "later successful manual save clears all old failure text")
	_save.saved.disconnect(manual_saved)
	_save_ok = false
	_service.configure(_bag, func() -> bool: return true, _persist, _recipe_access)
	view.craft_requested.emit(SEEDS)
	_check(view.snapshot.save_pending and _bag.count_of(&"carrot_seeds") == 12, "legacy single-batch View intent uses the same service")
	_save_ok = true
	view.retry_save_requested.emit()
	_check(not view.snapshot.save_pending and _bag.count_of(&"carrot_seeds") == 12, "retry intent only persists the already committed batch")
	var old_renders: int = view.renders
	presenter.get_parent().remove_child(presenter)
	for event: StringName in [&"craft_requested", &"batch_craft_requested", &"recipe_selected", &"quantity_changed", &"max_requested", &"retry_save_requested", &"tree_exiting"]:
		_check(view.get_signal_connection_list(event).is_empty(), "detached Presenter disconnects old View " + event)
	_check(not _bag.changed.is_connected(presenter.refresh) and not _service.changed.is_connected(presenter.refresh) and not _service.save_failed.is_connected(presenter._save_failed), "detached Presenter releases all model/service subscriptions")
	_set_items({&"carrot": 1, &"fiber": 2})
	var baseline: Dictionary = _bag.to_dict()
	view.batch_craft_requested.emit(SEEDS, 1)
	_service.refresh_access()
	_check(_bag.to_dict() == baseline and view.renders == old_renders, "old detached View cannot craft or receive refresh")
	presenter.free()
	view.queue_free()
	await process_frame
	var native: Control = WorkbenchView.new()
	_main.get_node("UI").add_child(native)
	presenter = Presenter.new()
	_main.get_node("Systems").add_child(presenter)
	presenter.configure(_service, _bag, native)
	presenter.open()
	_set_items({&"carrot": 5, &"fiber": 10})
	var spin: SpinBox = native.find_child("BatchQuantity", true, false)
	spin.value = 2
	var button: Button = native.find_child("Craft", true, false)
	button.grab_focus()
	var focus: Control = root.gui_get_focus_owner()
	_service.refresh_access()
	_check(spin.value == 2 and root.gui_get_focus_owner() == focus, "native render preserves quantity and focused control")
	_check(button.text == "制作 · 胡萝卜种子包" and not button.disabled, "legacy craft button text remains discoverable by integration checks")
	if "--preview" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("user://crafting_workbench.png") == OK, "native batch crafting preview saves")
		print("[crafting] preview: " + ProjectSettings.globalize_path("user://crafting_workbench.png"))
	button.pressed.emit()
	_check(_bag.count_of(&"carrot_seeds") == 8 and _bag.count_of(&"carrot") == 3, "native craft button emits exactly one batch request")
	_check(button.has_focus() and not button.disabled and spin.value == 2, "completed crafting keeps keyboard focus and selected batches when another batch fits")
	native.queue_free()
	await process_frame
	_check(not _service.changed.is_connected(presenter.refresh), "destroying the replacement native View unbinds its Presenter")
	presenter.queue_free()
	await process_frame
