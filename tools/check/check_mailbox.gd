extends SceneTree
## B2-05：真实背包/钱包、整批附件、观察者重入、保存失败、模态与MVP生命周期。

const State := preload("res://scripts/progression/mailbox_state.gd")
const Presenter := preload("res://scripts/ui/presenters/mailbox_presenter.gd")
var _failures: int = 0
var _checks: int = 0
var _main: Node2D
var _mail: RefCounted
var _bag: Inventory
var _wallet: Economy
var _save: Node

class ReplacementView extends Control:
	signal opened
	signal selected(id: StringName)
	signal claim_requested(id: StringName)
	signal retry_save_requested
	var data: Dictionary = {}
	func render(snapshot: Dictionary) -> void: data = snapshot
	func set_open(value: bool) -> void:
		visible = value
		if value: opened.emit()


func _init() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("[mailbox] FAIL: " + message)


func _letter(id: StringName, items: Array = [], coins: int = 0) -> MailData:
	var letter := MailData.new()
	letter.id = id
	letter.sender = "园艺师"
	letter.title = "来自农场的信 · " + String(id)
	letter.body = "谢谢你照料农场。\n附件可以一次领取，背包装不下时会一直替你保管。"
	letter.coins = coins
	for pair: Array in items:
		var attachment := MailAttachment.new()
		attachment.item_id = pair[0]
		attachment.count = pair[1]
		letter.attachments.append(attachment)
	return letter


func _set_free_slots(count: int) -> void:
	var slots: Array = []
	for id: StringName in Inventory.TOOL_IDS: slots.append({"id": String(id), "count": 1})
	while slots.size() < _bag.slot_count() - count:
		slots.append({"id": "carrot", "count": _bag.definition(&"carrot").max_stack})
	_bag.from_dict({"slots": slots, "today_collected": 0})


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_check_state()
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	_main.get_node("Systems/Save").remove_from_group(&"save")
	_main.get_node("Systems/Time").running = false
	await process_frame
	await process_frame
	_mail = _main.mail
	_bag = _main.get_node("Systems/Inventory") as Inventory
	_wallet = _main.get_node("Systems/Economy") as Economy
	_save = _main.get_node("Systems/Save")
	_mail.configure(_bag, _wallet, func() -> int: return 7, func() -> bool: return true)
	_check(_mail.definition(&"farm_welcome") != null, "authored mail Resource discovers through ResourceLoader")
	_check(_mail.unread_count() == 0, "mail definition alone does not trigger plot delivery")
	_check_transactions()
	_check_capacity()
	await _check_view_and_save()
	await _check_presenter_lifecycle()
	await _check_disk_and_legacy()
	if OS.get_cmdline_user_args().has("--preview"):
		await _capture()
	_main.queue_free()
	await process_frame
	print("[mailbox] %d checks; %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_state() -> void:
	var state := State.new()
	_check(state.deliver(&"stable", 3), "model delivers a stable ID once")
	_check(not state.deliver(&"stable", 9) and state.status(&"stable").day == 3, "duplicate delivery never changes its first day")
	_check(state.unread_count() == 1, "delivery increments unread count")
	var copy: Dictionary = state.status(&"stable")
	copy.claimed = true
	_check(not state.status(&"stable").claimed, "queries cannot mutate facts")
	_check(state.mark_read(&"stable") and not state.mark_read(&"stable"), "reading is idempotent")
	_check(state.unread_count() == 0, "reading decrements unread count")
	_check(state.mark_claimed(&"stable") and not state.mark_claimed(&"stable"), "claim marker is permanent")
	state.deliver(&"plain", 4, true)
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(state.encode()))
	state.restore(encoded)
	_check(state.status(&"stable").claimed and not state.status(&"plain").read and state.status(&"plain").day == 4 and state.unread_count() == 1, "coin-free letter remains unread across JSON restoration")
	_check(not state.deliver(&"stable", 8), "restoration retains the delivery tombstone")
	state.restore({"letters": {"missing_definition": {"day": 2, "read": false, "claimed": true}, "bad": {"day": "no"}, "flag": {"day": 1, "claimed": "yes"}}})
	_check(state.delivered(&"missing_definition") and not state.delivered(&"bad"), "unknown ID tombstones persist and malformed date is rejected")
	_check(state.status(&"flag").claimed, "invalid claim flag cannot create a repeatable reward")
	state.restore({})
	_check(state.encode().letters.is_empty(), "missing optional section initializes empty")


func _check_transactions() -> void:
	_set_free_slots(26)
	var letter: MailData = _letter(&"parcel", [[&"wood", 2], [&"wood", 3], [&"stone", 4]], 25)
	_check(_mail.register_definition(letter) and not _mail.register_definition(letter), "duplicate definitions cannot replace a stable identity")
	_check(not _mail.deliver(&"unknown") and _mail.deliver(&"parcel") and not _mail.deliver(&"parcel"), "only known IDs deliver and duplicate delivery does not repeat")
	_check(_mail.mark_read(&"parcel") and not _mail.mark_read(&"parcel"), "public reading endpoint persists only a first read")
	var coins: int = _wallet.coins
	var collected: int = _bag.today_collected
	var observations: Array[bool] = []
	var observer := func(_value: int = 0) -> void:
		observations.append(_mail.status(&"parcel").claimed and _bag.count_of(&"wood") == 5 and _bag.count_of(&"stone") == 4 and _wallet.coins == coins + 25)
		_check(not _mail.claim(&"parcel") and not _mail.deliver(&"farm_welcome"), "observer reentry cannot claim or deliver during a transaction")
		_mail.restore({})
		_check(_mail.status(&"parcel").claimed, "observer cannot restore over a live transaction")
	_wallet.changed.connect(observer)
	_bag.changed.connect(observer)
	_check(_mail.claim(&"parcel"), "claim commits merged items and coins")
	_wallet.changed.disconnect(observer)
	_bag.changed.disconnect(observer)
	_check(observations.size() >= 2 and not observations.has(false), "both model notifications observe the complete transaction")
	_check(not _mail.claim(&"parcel") and _wallet.coins == coins + 25 and _bag.count_of(&"wood") == 5, "continuous clicks never repeat rewards")
	_check(_bag.today_collected == collected, "mail items are not counted as harvested produce")
	var snapshot: Dictionary = _mail.encode()
	for index: int in 3: _mail.restore(snapshot)
	_check(_wallet.coins == coins + 25 and _bag.count_of(&"wood") == 5 and _mail.status(&"parcel").claimed, "repeated restore grants no items or coins")


func _check_capacity() -> void:
	_set_free_slots(1)
	_mail.register_definition(_letter(&"full", [[&"wood", 1], [&"stone", 1]], 40))
	_mail.deliver(&"full")
	var coins: int = _wallet.coins
	var bag: Dictionary = _bag.to_dict()
	_check(_bag.has_space_for(&"wood", 1) and _bag.has_space_for(&"stone", 1), "two individual capacity probes share the same last slot")
	_check(not _mail.claim(&"full") and not _mail.status(&"full").claimed, "whole-batch capacity keeps every attachment pending")
	_check(_bag.to_dict() == bag and _wallet.coins == coins, "failed claim changes neither bag nor wallet")
	_set_free_slots(2)
	_check(_mail.claim(&"full") and _bag.count_of(&"wood") == 1 and _bag.count_of(&"stone") == 1, "freeing enough space permits the same pending parcel")
	_set_free_slots(0)
	_mail.register_definition(_letter(&"coins", [], 17))
	_mail.deliver(&"coins")
	_check(_mail.claim(&"coins"), "coin-only letter can be claimed with a full bag")
	_set_free_slots(1)
	_mail.register_definition(_letter(&"stack", [[&"wood", _bag.definition(&"wood").max_stack], [&"wood", 1]]))
	_mail.deliver(&"stack")
	_check(not _mail.claim(&"stack"), "duplicate attachment lines combine before capacity validation")


func _check_view_and_save() -> void:
	_set_free_slots(26)
	var box: Node = _main.get_node("Farm/World/Mailbox")
	var view: Control = _main.get_node("UI/MailboxPanel")
	_check(box.player_in_range(_main.get_node("Farm/World/Player")) == false, "world interaction uses the player distance")
	box.interact(Vector2i.ZERO)
	_check(view.visible and paused and _main.get_node("Farm/World/Player").input_locked, "world mailbox enters the registered modal and pauses gameplay")
	view.set_open(false)
	_check(not paused and not _main.get_node("Farm/World/Player").input_locked, "closing mail restores modal ownership")
	_mail.configure(_bag, _wallet, func() -> int: return 8, func() -> bool: return false)
	_mail.register_definition(_letter(&"write_failure", [[&"wood", 2]], 10))
	_mail.deliver(&"write_failure")
	view.set_open(true)
	view.selected.emit(&"write_failure")
	var before: int = _wallet.coins
	view.claim_requested.emit(&"write_failure")
	_check(_mail.status(&"write_failure").claimed and _wallet.coins == before + 10, "failed write retains the committed attachment result")
	_check(_mail.save_pending and view.retry_button.visible and view.note.text.contains("尚未保存"), "failed save remains visible in the open panel with a retry action")
	_check((_main.get_node("UI/Toast") as Label).text.contains("保存失败"), "composition root also exposes save failure as a toast")
	view.claim_requested.emit(&"write_failure")
	_check(_wallet.coins == before + 10, "retrying a failed-save claim cannot grant twice")
	_mail.configure(_bag, _wallet, func() -> int: return 8, func() -> bool: return true)
	view.retry_save_requested.emit()
	_check(not _mail.save_pending and not view.retry_button.visible and _wallet.coins == before + 10, "retry only saves and does not re-award the parcel")
	var inventory_panel: Control = _main.get_node("UI/InventoryPanel")
	inventory_panel.set_open(true)
	_check(not view.visible, "modal coordinator replaces the mailbox when another panel opens")
	inventory_panel.set_open(false)
	await process_frame


func _check_presenter_lifecycle() -> void:
	_mail.register_definition(_letter(&"replacement_only", [[&"wood", 1]]))
	_mail.deliver(&"replacement_only")
	var connections: int = _mail.changed.get_connections().size()
	var presenter := Presenter.new()
	var first := ReplacementView.new()
	root.add_child(first)
	root.add_child(presenter)
	presenter.configure(_mail, _bag, first)
	first.set_open(true)
	first.selected.emit(&"replacement_only")
	_check(first.data.has("letters"), "presenter accepts an alternative intent/render view")
	var replacement := ReplacementView.new()
	root.add_child(replacement)
	presenter.configure(_mail, _bag, replacement)
	first.claim_requested.emit(&"replacement_only")
	_check(not _mail.status(&"replacement_only").claimed, "replaced view cannot claim an otherwise eligible attachment")
	first.queue_free()
	replacement.queue_free()
	await process_frame
	_mail.mark_read(&"stack")
	presenter.queue_free()
	await process_frame
	_check(_mail.changed.get_connections().size() == connections, "presenter and deleted view release their bindings")


func _check_disk_and_legacy() -> void:
	var bag: Dictionary = _bag.to_dict()
	var coins: int = _wallet.coins
	_check(_save.save_game(), "real isolated save writes the mail section")
	var snapshot: Dictionary = _mail.encode()
	_mail.restore({})
	_check(_save.load_game() and _mail.encode() == snapshot, "mail state round-trips through the real JSON slot")
	_check(_bag.to_dict() == bag and _wallet.coins == coins, "disk restoration grants no attachments")
	var legacy: Dictionary = _save.collect()
	legacy.erase("mail")
	_save.apply(legacy)
	_check(_mail.encode().letters.is_empty() and _mail.unread_count() == 0, "legacy save missing mail clears the previous session mailbox")
	await process_frame


func _capture() -> void:
	_set_free_slots(26)
	_mail.deliver(&"farm_welcome")
	_mail.register_definition(_letter(&"preview", [[&"wood", 3], [&"carrot_seeds", 2]], 25))
	_mail.deliver(&"preview")
	var view: Control = _main.get_node("UI/MailboxPanel")
	view.set_open(true)
	view.selected.emit(&"preview")
	await process_frame
	await RenderingServer.frame_post_draw
	var directory: String = OS.get_user_data_dir().path_join("mailbox_previews")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join("mailbox.png"))
	print("[mailbox_preview] " + directory.path_join("mailbox.png"))
	view.set_open(false)
