extends SceneTree
## B2-03 专属隔离检查：真实服务/库存/磁盘、双 View、模态、替换解绑与窗口布局。

const Presenter := preload("res://scripts/ui/presenters/quest_journal_presenter.gd")
const Service := preload("res://scripts/progression/quest_service.gd")
const JournalScene := preload("res://scenes/ui/quest_journal.tscn")
const Tracker := preload("res://scenes/ui/quest_tracker.tscn")
const Modals := preload("res://scripts/ui/common/modal_coordinator.gd")
const FIRST: StringName = &"ch1_01_gate"
const SECOND: StringName = &"ch1_02_basket"

class PanelDouble extends Control:
	signal selection_requested(id: StringName)
	signal accept_requested(id: StringName)
	signal deliver_requested(id: StringName)
	signal track_requested(id: StringName)
	signal untrack_requested
	signal refresh_requested
	var data: Dictionary = {}
	var renders: int = 0
	func render(snapshot: Dictionary) -> void:
		data = snapshot
		renders += 1
	func set_open(value: bool) -> void: visible = value

class HudDouble extends Control:
	signal journal_requested
	var data: Dictionary = {}
	func render(snapshot: Dictionary) -> void: data = snapshot

class FailingInstallStore extends "res://scripts/persistence/json_save_store.gd":
	func _install(_temp: String, _destination: String) -> Error:
		return ERR_CANT_CREATE

var _checks: int = 0
var _failures: int = 0
var _stage: Control
var _bag: Inventory
var _wallet: Economy
var _save: SaveSystem
var _service: RefCounted
var _presenter: Node
var _panel: Control
var _hud: Control
var _journal: Control
var _modals: Node


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[quest_journal] FAIL: " + message)


func _settle() -> void:
	for frame in 4: await process_frame


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_stage = Control.new()
	root.add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bag = Inventory.new()
	_wallet = Economy.new()
	_save = SaveSystem.new()
	_save.autoload_enabled = false
	for node: Node in [_bag, _wallet, _save]: _stage.add_child(node)
	_service = Service.new()
	_service.start()
	_service.configure(_bag, _wallet, Callable(), _save.save_game)
	_save.snapshots.register_section(&"inventory", _bag.to_dict, _bag.from_dict)
	_save.snapshots.register_section(&"coins", _coins, _restore_coins, TYPE_INT)
	_save.snapshots.register_section(&"quests", _service.encode, _service.restore, TYPE_DICTIONARY, true)
	_journal = load("res://scenes/ui/hud.tscn").instantiate()
	_stage.add_child(_journal)
	_panel = JournalScene.instantiate()
	_hud = Tracker.instantiate()
	_stage.add_child(_hud)
	_stage.add_child(_panel)
	_presenter = Presenter.new()
	_stage.add_child(_presenter)
	_presenter.configure(_service, _bag, _panel, _hud, _save, _location)
	_save.snapshots.register_section(&"quest_tracking", _presenter.encode_tracking, _presenter.restore_tracking, TYPE_DICTIONARY, true)
	_modals = Modals.new()
	_stage.add_child(_modals)
	_modals.register_panel(_panel)
	await _settle()

	await _check_actions_and_refresh()
	await _check_round_trip()
	await _check_capacity_and_save_failure()
	await _check_input_and_layout()
	await _check_lifecycle()

	# 最后执行标记前断言依赖和场景已释放，不能让中途脚本错误伪装成通过。
	_save.snapshots.clear()
	_service.clear()
	_service = null
	_stage.queue_free()
	await _settle()
	_check(not is_instance_valid(_stage) and not paused, "final cleanup releases views and modal pause")
	print("[quest_journal] PASS path reached; %d checks, %d failures" % [_checks, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_actions_and_refresh() -> void:
	_panel.open()
	await _settle()
	var detail: Node = _panel._detail
	_check(detail._heading.text == "修好摊位的门板", "first quest is selected")
	_check(detail._body.text.contains("杂货铺老板") and detail._body.text.contains("杂货店内柜台"), "giver and injected location appear")
	_check(detail._body.text.contains("120 金币") and detail._body.text.contains("胡萝卜种子"), "rewards use authored values and item names")
	_check(detail._body.text.contains("0/6") and detail._body.text.contains("接取委托"), "initial progress and next step appear")
	_check(_panel._list.item_count == 6, "all chapter quests are listed including locks")
	_panel.selection_requested.emit(SECOND)
	_check(detail._accept.disabled and detail._body.text.contains("先完成：修好摊位的门板"), "locked quest explains prerequisite without enabling accept")
	_panel.selection_requested.emit(FIRST)
	detail._accept.pressed.emit()
	await _settle()
	_check(_service.status_of(FIRST) == 2 and _presenter.tracked_id() == FIRST, "accept intention uses service and chooses a single target")
	_check(_hud._body.text.contains("0/6") and _hud._body.text.contains("准备材料"), "HUD shows active goal and next step")
	_panel.accept_requested.emit(FIRST)
	_check(_service.status_of(FIRST) == 2, "duplicate accept keeps the same active quest")
	_bag.add_item(&"fiber", 4)
	_check(detail._body.text.contains("4/6") and _hud._body.text.contains("4/6"), "inventory additions refresh both views synchronously")
	_bag.remove_item(&"fiber", 1)
	_check(detail._body.text.contains("3/6") and _hud._body.text.contains("3/6"), "inventory consumption reduces the live progress")
	_bag.add_item(&"fiber", 3)
	_check(not detail._deliver.disabled and _hud._title.text == "可交付", "service readiness enables delivery")
	var coins: int = _wallet.coins
	detail._deliver.pressed.emit()
	_panel.deliver_requested.emit(FIRST)
	await _settle()
	_check(_service.status_of(FIRST) == 3 and _wallet.coins == coins + 120, "button delivery settles once despite duplicate intention")
	_check(_presenter.tracked_id() == &"" and _hud._body.text.contains("尚未追踪"), "completed target clears without silently tracking a new task")
	_check(detail._body.text.contains("已完成") and detail._accept.disabled and detail._deliver.disabled, "completed detail cannot grant rewards again")
	_panel.selection_requested.emit(SECOND)
	_check(not detail._accept.disabled, "completion unlock refreshes the next quest")
	_panel.close()
	_service.accept(SECOND)
	await _settle()
	_check(detail._track.disabled == false, "accepting outside the view refreshes even while panel is closed")
	_panel.track_requested.emit(SECOND)
	_check(_presenter.tracked_id() == SECOND, "manual track uses stable quest ID")
	_panel.track_requested.emit(FIRST)
	_check(_presenter.tracked_id() == SECOND, "completed ID cannot replace current tracking")
	_panel.untrack_requested.emit()
	_check(_presenter.tracked_id() == &"", "untrack clears the only HUD target")
	_panel.track_requested.emit(SECOND)


func _check_round_trip() -> void:
	_bag.add_item(&"carrot", 2)
	_check(_save.save_game(), "isolated save writes quest facts and tracking")
	var coins: int = _wallet.coins
	_service.restore({})
	_presenter.restore_tracking({})
	_bag.remove_item(&"carrot", 2)
	for attempt in 3:
		_check(_save.load_game(), "disk load succeeds, attempt %d" % attempt)
		await _settle()
		_check(_presenter.tracked_id() == SECOND and _hud._body.text.contains("2/5"), "load restores selected target and current inventory progress")
		_check(_wallet.coins == coins and _bag.count_of(&"carrot") == 2, "load never replays quest rewards")
	var document: Dictionary = _save.collect()
	document.erase("quest_tracking")
	_save.apply(document)
	_check(_presenter.tracked_id() == &"", "old save without tracking clears a previous slot's target")
	for broken: Dictionary in [
		{"tracked_id": 14}, {"tracked_id": []}, {"tracked_id": "missing"},
		{"tracked_id": String(FIRST)}, {"version": 2, "tracked_id": String(SECOND)},
		{"version": "bad", "tracked_id": String(SECOND)},
	]:
		_presenter.restore_tracking(broken)
		_check(_presenter.tracked_id() == &"", "malformed/unknown/completed target is discarded")
	# 两个 active 的恢复事实用于验证切换目标，UI 不创建第二套任务状态。
	_service.restore({"accepted": {String(FIRST): 1, String(SECOND): 1}})
	_presenter.track(FIRST)
	_presenter.track(SECOND)
	_check(_presenter.encode_tracking().tracked_id == String(SECOND) and not _hud._body.text.contains("修好摊位的门板"), "switching two active quests leaves exactly one HUD target")
	_check(_wallet.coins == coins, "tracking restore and switching never changes money")
	_service.restore({"completed": {String(FIRST): 1}, "accepted": {String(SECOND): 1}})
	_presenter.track(SECOND)
	await _settle()


func _check_capacity_and_save_failure() -> void:
	_bag.add_item(&"carrot", 3)
	var guard: int = 0
	while _bag.has_space_for(&"stone", 1) and guard < 80:
		_bag.add_item(&"stone", 99, &"purchase")
		guard += 1
	var coins: int = _wallet.coins
	_panel.deliver_requested.emit(SECOND)
	_check(_wallet.coins == coins and _service.status_of(SECOND) == 2 and _bag.count_of(&"carrot") == 5, "full reward capacity is refused by the service without partial delivery")
	_check(not _panel._message.text.is_empty(), "service rejection is visible")
	_bag.remove_item(&"stone", _bag.count_of(&"stone"))
	var original_store := _save.storage
	_save.storage = FailingInstallStore.new()
	print("[quest_journal] expected fault: isolated JSON store refuses installation")
	_panel.deliver_requested.emit(SECOND)
	await _settle()
	_check(_service.status_of(SECOND) == 3 and _wallet.coins == coins + 150, "failed save preserves exactly one settled delivery")
	_check(_panel._message.text.contains("存档失败") and _hud._body.text.contains("存档失败"), "failed save is visible in panel and HUD")
	_check(_save.storage.last_error == ERR_CANT_CREATE, "delivery uses the real SaveSystem and reports the storage installation failure")
	_check(not _service.busy, "failed save returns control to the player")
	_save.storage = original_store
	_check(_save.save_game(), "manual retry writes the settled delivery to the isolated save")
	_check(_panel._message.text.is_empty() and not _hud._body.text.contains("存档失败"), "successful manual save clears the failure in panel and HUD")
	var written: Dictionary = _save.storage.read(_save.save_path())
	_check(int(written.get("coins", -1)) == coins + 150 and _wallet.coins == coins + 150, "manual retry persists the reward without granting it again")
	_save.storage = FailingInstallStore.new()
	_check(_service.accept(&"ch1_03_timber"), "another accepted quest settles despite the expected save fault")
	_check(_panel._message.text.contains("存档失败"), "a later failed write shows the failure again")
	_save.storage = original_store
	_check(_save.load_game(), "the prior successful save can be loaded after a later failure")
	await _settle()
	_check(_panel._message.text.is_empty() and not _hud._body.text.contains("存档失败"), "disk restore clears stale save-failure feedback in both views")
	_panel.deliver_requested.emit(SECOND)
	var rejection: String = _panel._message.text
	_check(not rejection.is_empty() and not rejection.contains("存档失败"), "a completed quest still reports a separate operation rejection")
	_check(_save.save_game(), "saving after an unrelated rejection succeeds")
	_check(_panel._message.text == rejection and _hud._body.text.contains(rejection), "successful saving does not erase unrelated operation feedback")
	_service.restore({"accepted": {String(FIRST): 1}})
	_presenter.track(FIRST)
	await _settle()


func _check_input_and_layout() -> void:
	_panel.selection_requested.emit(FIRST)
	_panel.toggle_action = &"check_quest_log"
	InputMap.add_action(&"check_quest_log")
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_Q
	toggle.physical_keycode = KEY_Q
	InputMap.action_add_event(&"check_quest_log", toggle)
	_panel.close()
	_press(KEY_Q)
	await _settle()
	_check(_panel.visible and paused, "Q opens registered journal and pauses through coordinator")
	_press(KEY_ESCAPE)
	await _settle()
	_check(not _panel.visible and not paused, "Escape closes modal and releases pause")
	var collapsed: bool = _journal._journal_collapsed
	_press(KEY_J)
	await _settle()
	_check(_journal._journal_collapsed != collapsed and not _panel.visible, "existing J farm journal remains independent")
	_press(KEY_J)
	var other := preload("res://scripts/ui/common/modal_panel.gd").new()
	other.hide()
	_stage.add_child(other)
	_modals.register_panel(other)
	other.set_open(true)
	_press(KEY_Q)
	await _settle()
	_check(not _panel.visible and other.visible, "Q does not steal another modal's input")
	other.set_open(false)
	_hud.journal_requested.emit()
	_check(_panel.visible and not other.visible, "HUD intent opens through modal API")
	other.set_open(true)
	_check(not _panel.visible and not paused, "modal replacement closes the pausing quest journal")
	other.queue_free()
	await _settle()
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(800, 600)]:
		root.size = resolution
		await _settle()
		_check(_hud.get_viewport_rect().grow(1).encloses(_hud.get_global_rect()), "tracker fits at %s" % resolution)
		_check(not _hud.get_global_rect().intersects(_journal.get_node("Journal").get_global_rect()), "tracker does not overlap existing journal at %s" % resolution)
		_check(not _hud.get_global_rect().intersects(_journal.get_node("StaminaPanel").get_global_rect()), "tracker avoids existing status cards")
		_panel.open()
		await _settle()
		_check(_panel.get_viewport_rect().grow(1).encloses(_panel._frame.get_global_rect()), "modal frame fits at %s" % resolution)
		_check(_panel._frame.get_global_rect().encloses(_panel._list.get_global_rect()), "list stays within modal frame")
		_check(_panel._detail.size.x <= _panel._detail.get_parent().size.x, "detail wraps inside scroll width")
		_panel.close()
	if "--preview" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280, 720)
		await _settle()
		await RenderingServer.frame_post_draw
		_capture("quest_tracker")
		_panel.open()
		await _settle()
		await RenderingServer.frame_post_draw
		_capture("quest_journal")
		_panel.close()
	InputMap.erase_action(&"check_quest_log")
	_panel.toggle_action = &"toggle_quest_log"


func _check_lifecycle() -> void:
	_panel.open()
	_panel.queue_free()
	await _settle()
	_check(not paused and not _modals.has_open_panel(), "destroying open panel releases its modal ownership")
	_bag.add_item(&"fiber", 1)
	_check(_hud._body.text.contains("1/6"), "surviving HUD updates after panel destruction")
	var replacement := PanelDouble.new()
	var replacement_hud := HudDouble.new()
	_stage.add_child(replacement)
	_stage.add_child(replacement_hud)
	for attempt in 2:
		_presenter.configure(_service, _bag, replacement, replacement_hud, _save)
	_check(_hud.journal_requested.get_connections().is_empty(), "reconfigure removes old HUD intent")
	_check(_count_bindings(_save.saved, _presenter._on_saved) == 1 and _count_bindings(_save.restored, _presenter._on_restored) == 1, "repeated configure keeps exactly one saved and restored subscription")
	_presenter.track(FIRST)
	_check(replacement.data.detail.location.contains("地点线索待补充"), "missing location uses honest exploration hint")
	var before_failure: int = replacement.renders
	var former_hud_text: String = _hud._body.text
	_service.save_failed.emit()
	_check(replacement.renders == before_failure + 1, "repeated configure handles a save failure once")
	var before_save: int = replacement.renders
	_check(_save.save_game(), "manual save succeeds with replacement views")
	_check(replacement.renders == before_save + 1 and String(replacement.data.message).is_empty() and String(replacement_hud.data.message).is_empty(), "saved notification refreshes replacement views once and clears the failure")
	_check(_hud._body.text == former_hud_text, "former HUD receives no save-failure or success rendering after replacement")
	var renders: int = replacement.renders
	_hud.journal_requested.emit()
	_check(replacement.renders == renders, "old HUD cannot call new panel")
	_save.snapshots.clear()
	_stage.remove_child(_presenter)
	_check(replacement.accept_requested.get_connections().is_empty() and replacement_hud.journal_requested.get_connections().is_empty(), "presenter exit disconnects every view intention")
	_check(not _service.changed.is_connected(_presenter._on_changed) and not _service.save_failed.is_connected(_presenter._on_save_failed), "presenter exit disconnects service bindings")
	_check(not _bag.changed.is_connected(_presenter._on_changed) and not _save.restored.is_connected(_presenter._on_restored), "presenter exit disconnects inventory and save bindings")
	_check(not _save.saved.is_connected(_presenter._on_saved), "presenter exit disconnects successful-save confirmation")
	_bag.add_item(&"fiber", 1)
	_save.restored.emit()
	_save.saved.emit(_save.current_slot)
	_service.changed.emit()
	replacement.accept_requested.emit(SECOND)
	_check(replacement.renders == renders and _service.status_of(SECOND) != 2, "detached presenter cannot render or submit operations")
	_presenter.free()
	_presenter = Presenter.new()
	_stage.add_child(_presenter)
	_presenter.configure(_service, _bag, replacement, replacement_hud, _save)
	_presenter.track(FIRST)
	replacement.queue_free()
	replacement_hud.queue_free()
	await _settle()
	_check(not _service.changed.is_connected(_presenter._on_changed) and not _bag.changed.is_connected(_presenter._on_changed), "destroying both views releases remaining source subscriptions")
	_check(not _save.saved.is_connected(_presenter._on_saved) and not _save.restored.is_connected(_presenter._on_restored), "destroying both views releases saved and restored bindings")
	var disposable := PanelDouble.new()
	var disposable_hud := HudDouble.new()
	_stage.add_child(disposable)
	_stage.add_child(disposable_hud)
	_presenter.configure(_service, _bag, disposable, disposable_hud, _save)
	_service.save_failed.emit()
	var before_dispose: int = disposable.renders
	_presenter.dispose()
	_presenter.dispose()
	_check(not _save.saved.is_connected(_presenter._on_saved) and not _save.restored.is_connected(_presenter._on_restored), "explicit disposal removes both save subscriptions and is idempotent")
	_save.saved.emit(_save.current_slot)
	_save.restored.emit()
	_service.save_failed.emit()
	_check(disposable.renders == before_dispose and disposable.accept_requested.get_connections().is_empty() and disposable_hud.journal_requested.get_connections().is_empty(), "disposed presenter neither renders save notifications nor retains view intentions")


func _count_bindings(event: Signal, callback: Callable) -> int:
	var count: int = 0
	for binding: Dictionary in event.get_connections():
		if binding.callable == callback: count += 1
	return count


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)


func _capture(name: String) -> void:
	var path: String = "user://%s.png" % name
	_check(root.get_texture().get_image().save_png(path) == OK, "preview image writes")
	print("[quest_journal] screenshot=" + ProjectSettings.globalize_path(path))


func _coins() -> int:
	return _wallet.coins


func _restore_coins(coins: int) -> void:
	_wallet.coins = coins


func _location(_giver: StringName) -> String:
	return "杂货店内柜台"
