extends SceneTree
## 真实 NPC 按钮、任务事务通知、延迟室内绑定、失败与重复读档。

const Presenter := preload("res://scripts/ui/presenters/quest_dialogue_presenter.gd")
const FIRST: StringName = &"ch1_01_gate"
const SECOND: StringName = &"ch1_02_basket"

var _checks: int = 0
var _failures: int = 0
var _main: Node
var _quests: RefCounted
var _bag: Inventory
var _wallet: Economy
var _save: Node
var _dialogue: Control
var _initial: Dictionary


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[quest_integration] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_quests = _main.quests
	_bag = _main.get_node("Systems/Inventory")
	_wallet = _main.get_node("Systems/Economy")
	_save = _main.get_node("Systems/Save")
	_dialogue = _main.get_node("UI/DialoguePanel")
	_main.get_node("Systems/Time").running = false
	_initial = _save.collect().duplicate(true)
	_check_accept_and_notifications()
	_check_batch_and_duplicate_requirements()
	await _check_npc_chapter()
	await _check_chapter_integration()
	await _check_lifecycle()
	_main.queue_free()
	await process_frame
	_check(not is_instance_valid(_main), "the integrated scene exits completely")
	print("[quest_integration] %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _reset() -> void:
	_dialogue.close()
	_quests.configure(_bag, _wallet, func() -> int: return 1, _save.save_game)
	_save.apply(_initial.duplicate(true))


func _check_accept_and_notifications() -> void:
	_reset()
	_check(not _quests.accept_for(&"gardener", FIRST), "another NPC cannot accept the shopkeeper's quest")
	var writes: Array[int] = [0]
	var saved := func(_slot: int) -> void: writes[0] += 1
	_save.saved.connect(saved)
	_check(_quests.accept_for(&"shopkeeper", FIRST), "the giver accepts the opening quest")
	_check(writes[0] == 1, "accepting immediately persists the quest")
	_check(_save.load_game() and _quests.status_of(FIRST) == 2, "disk reload preserves acceptance before delivery")
	_check(not _quests.accept(FIRST) and writes[0] == 1, "repeated acceptance neither changes state nor writes")
	_save.saved.disconnect(saved)
	_bag.add_item(&"fiber", 6)
	_check(not _quests.deliver_for(&"gardener", FIRST), "another NPC cannot consume the goods")
	var observed: Array[bool] = []
	var coin_observer := func(_amount: int) -> void:
		observed.append(_quests.status_of(FIRST) == 3 and _bag.count_of(&"carrot_seeds") == 8 and _bag.count_of(&"fiber") == 0)
		_check(not _quests.accept(SECOND), "wallet observer cannot accept a second quest during settlement")
		_quests.restore({})
		_check(_quests.status_of(FIRST) == 3, "observer restore cannot erase a live transaction")
	var completed_observer := func(_id: StringName) -> void:
		_check(not _quests.accept(SECOND), "completion observer cannot start a nested transaction")
		_check(not _quests.deliver(FIRST), "completion observer cannot repeat the reward")
	_wallet.coins_gained.connect(coin_observer)
	_quests.completed.connect(completed_observer)
	_check(_quests.deliver_for(&"shopkeeper", FIRST), "delivery commits through the NPC port")
	_wallet.coins_gained.disconnect(coin_observer)
	_quests.completed.disconnect(completed_observer)
	_check(observed == [true], "the earliest wallet notification sees all committed rewards and goods")
	_check(not _quests.busy and _wallet.coins == 620, "successful settlement releases the guard and pays once")
	var settled: Dictionary = _save.collect().duplicate(true)
	for repeat: int in 3:
		_save.apply(settled)
	_check(_wallet.coins == 620 and _bag.count_of(&"carrot_seeds") == 8, "three restores produce no extra rewards")


func _check_batch_and_duplicate_requirements() -> void:
	_reset()
	var quest: QuestData = _quests.definition(FIRST)
	var original_steps: Array[QuestStep] = quest.steps.duplicate()
	var original_rewards: Array[QuestReward] = quest.reward_items.duplicate()
	var first := QuestStep.new()
	first.item_id = &"fiber"
	first.count = 3
	var second := QuestStep.new()
	second.item_id = &"fiber"
	second.count = 4
	quest.steps.assign([first, second])
	_quests.accept(FIRST)
	_bag.add_item(&"fiber", 4)
	_check(not _quests.can_deliver(FIRST) and not _quests.deliver(FIRST), "repeated requirements are summed before deducting anything")
	var rows: Array = _quests.progress(FIRST)
	_check(rows.size() == 1 and rows[0].need == 7 and rows[0].have == 4, "progress presents the same aggregated requirement used by settlement")
	_check(_bag.count_of(&"fiber") == 4 and _wallet.coins == 500, "failed repeated requirements leave all models intact")
	quest.steps.assign(original_steps)
	_bag.add_item(&"fiber", 2)
	# 两份奖励单独都能放入同一个空格，合在一起则需要两格。
	_bag.remove_item(&"carrot_seeds", 5)
	while _bag.has_space_for(&"stone", 99):
		_bag.add_item(&"stone", 99, &"transfer")
	_bag.remove_item(&"stone", 99)
	_check(_bag.has_space_for(&"turnip_seeds", 1) and _bag.has_space_for(&"blueberry_seeds", 1), "both rewards individually fit in the one empty slot")
	_check(not _bag.has_space_for_batch({&"turnip_seeds": 1, &"blueberry_seeds": 1}), "batch capacity counts shared empty slots once")
	var reward_a := QuestReward.new()
	reward_a.item_id = &"turnip_seeds"
	reward_a.count = 1
	var reward_b := QuestReward.new()
	reward_b.item_id = &"blueberry_seeds"
	reward_b.count = 1
	quest.reward_items.assign([reward_a, reward_b])
	_check(not _quests.deliver(FIRST), "a combined reward overflow refuses the whole delivery")
	_check(_bag.count_of(&"fiber") == 6 and _wallet.coins == 500 and _quests.status_of(FIRST) == 2, "batch refusal preserves goods, coins and quest")
	_check(_quests.delivery_hint(FIRST).contains("整批奖励"), "the failed operation exposes a useful capacity reason")
	_bag.remove_item(&"stone", 99)
	_check(_quests.deliver(FIRST), "freeing a second slot permits both rewards")
	_check(_bag.count_of(&"turnip_seeds") == 1 and _bag.count_of(&"blueberry_seeds") == 1, "both configured rewards are actually granted")
	quest.reward_items.assign(original_rewards)
	_reset()
	# 钱包缺失时不能消耗材料而静默漏发金币。
	_quests.configure(_bag, null)
	_quests.accept(FIRST)
	_bag.add_item(&"fiber", 6)
	_check(not _quests.deliver(FIRST) and _bag.count_of(&"fiber") == 6, "missing reward dependency refuses before consuming goods")
	_reset()
	var failed_writes: Array[int] = [0]
	var failure := func() -> void: failed_writes[0] += 1
	_quests.save_failed.connect(failure)
	_quests.configure(_bag, _wallet, Callable(), func() -> bool: return false)
	_check(_quests.accept(FIRST) and failed_writes[0] == 1 and not _quests.busy, "failed acceptance save is visible, retains state and releases input use")
	_quests.save_failed.disconnect(failure)
	_reset()


func _actor(giver: StringName) -> Node:
	for actor: Node in get_nodes_in_group(&"interactable"):
		if actor.has_method(&"configure_quest_dialogue") and actor.get(&"npc_id") == giver:
			return actor
	return null


func _button(text: String) -> Button:
	for child: Node in _dialogue.get_node("%Options").get_children():
		if child is Button and not child.is_queued_for_deletion() and child.text == text:
			return child
	return null


func _press(text: String) -> void:
	var button: Button = _button(text)
	_check(button != null, "dialogue offers button: " + text)
	if button != null:
		button.pressed.emit()
	await process_frame


func _finish_lines() -> void:
	for step: int in 12:
		if _button("继续") == null:
			return
		await _press("继续")
	_check(false, "dialogue must terminate within the authored line bound")


func _check_npc_chapter() -> void:
	_reset()
	var house: Node = _main.get_node("Systems/HouseManager")
	house.enter_house(load("res://scenes/world/shop_interior.tscn"))
	await process_frame
	await process_frame
	var boss: Node = _actor(&"shopkeeper")
	_check(boss != null and boss.quest_options.is_valid(), "the lazily-created indoor shopkeeper receives injected quest ports")
	if boss == null:
		return
	_main.get_node("Systems/Time").minutes = 600
	boss.interact(Vector2i.ZERO)
	_check(_button("看看今天的货") != null and _button("委托：修好摊位的门板") != null, "shopping and quest entry coexist")
	await _press("看看今天的货")
	_check(_main.get_node("UI/ShopPanel").visible and not _dialogue.visible, "legacy shop option still transfers modal ownership")
	_main.get_node("UI/ShopPanel").set_open(false)
	_main.get_node("Systems/Time").minutes = 1320
	boss.interact(Vector2i.ZERO)
	_check(_button("看看今天的货") == null and _button("委托：修好摊位的门板") != null, "after hours denies shopping but retains quest conversations")
	_dialogue.close()
	_main.get_node("Systems/Time").minutes = 600
	var coins_before: int = _wallet.coins
	for quest: QuestData in _quests.definitions():
		var actor: Node = _actor(quest.giver)
		_check(actor != null and actor.quest_options.is_valid(), "chapter giver is wired: " + String(quest.giver))
		if actor == null:
			continue
		if quest.giver != &"shopkeeper" and house.is_inside():
			house.exit_house()
		elif quest.giver == &"shopkeeper" and not house.is_inside():
			house.enter_house(load("res://scenes/world/shop_interior.tscn"))
		actor.interact(Vector2i.ZERO)
		await _finish_lines()
		await _press("委托：" + quest.title)
		await _finish_lines()
		_check(_quests.status_of(quest.id) == 1, "viewing the offer does not implicitly accept it")
		await _press("接下这份委托")
		_check(_quests.status_of(quest.id) == 2, "actual accept button commits the quest")
		_dialogue.close()
		for step: QuestStep in quest.deliver_steps():
			_bag.add_item(step.item_id, step.count, &"transfer")
		actor.interact(Vector2i.ZERO)
		await _finish_lines()
		await _press("交付：" + quest.title)
		await _finish_lines()
		if quest.id == FIRST:
			if "--preview" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var path: String = "user://quest-delivery.png"
				_check(root.get_texture().get_image().save_png(path) == OK, "quest delivery screenshot is saved")
				print("[quest_integration] screenshot=" + ProjectSettings.globalize_path(path))
		await _press("交付物品并领取奖励")
		await _finish_lines()
		_check(_quests.status_of(quest.id) == 3, "actual delivery button completes: " + String(quest.id))
		_dialogue.close()
	_check(_wallet.coins == coins_before + 1290, "all six NPC deliveries pay the authored total exactly once")
	_check(_quests.log.completed_count() == 6, "the whole authored chain is reachable through NPC buttons")
	_check(_save.save_game() and _save.load_game(), "the completed chain survives an actual disk round trip")
	_check(_quests.log.completed_count() == 6 and _wallet.coins == coins_before + 1290, "loading does not replay any chapter payment")
	_check(not _main.regions.player.input_locked, "closing the dialogue returns player control")
	house.exit_house()


func _check_lifecycle() -> void:
	_reset()
	var actor: Node = _actor(&"gardener")
	var presenter: Node = _main.get_node("Systems/QuestDialoguePresenter")
	presenter.unbind()
	_check(not actor.quest_options.is_valid() and not actor.quest_response.is_valid(), "unbind clears both actor-to-presenter ports")
	var replacement := Presenter.new()
	replacement.configure(_quests, _bag)
	_main.get_node("Systems").add_child(replacement)
	replacement.bind_actor(actor)
	_check(actor.quest_options.is_valid(), "a replacement presenter can bind the same actor")
	replacement.queue_free()
	await process_frame
	_check(not actor.quest_options.is_valid() and not actor.quest_response.is_valid(), "presenter destruction removes its callbacks")
	actor.interact(Vector2i.ZERO)
	_check(_dialogue.visible, "ordinary NPC dialogue works after removing quest presentation")
	_dialogue.close()
	# 对话持有的 NPC 已销毁时，点击旧按钮也能正常退出。
	var transient: Node = load("res://scenes/npcs/shopkeeper.tscn").instantiate()
	_main.add_child(transient)
	transient.interact(Vector2i.ZERO)
	transient.queue_free()
	await process_frame
	await _press("先走了")
	_check(not _dialogue.visible, "destroyed dialogue owner is handled without script errors")


func _check_chapter_integration() -> void:
	var crafts: RefCounted = _main.crafts
	var cutscene: Node = _main.get_node("Systems/ChapterCutscene")
	var chapter: Node = _main.get_node("Systems/ChapterFlow")
	var player: Node = _main.regions.player
	var journal: Control = _main.get_node("UI/QuestJournal")
	var house: Node = _main.get_node("Systems/HouseManager")
	_check(crafts.unlocked(), "completing the final quest unlocks an actual crafting service")
	_check(_main.get_node("Systems/FarmActivities/CommunityVisuals").chapter_stage == 3, "chapter completion changes the existing market presentation without rewriting community state")
	house.enter_house(load("res://scenes/world/house_interior.tscn"))
	await process_frame
	var table: Node
	for actor: Node in get_nodes_in_group(&"interactable"):
		if actor.name == &"SeedWorkbench": table = actor
	_check(table != null, "the cached farm house creates a reachable workbench interaction on its wooden table")
	_bag.add_item(&"carrot", 2, &"transfer")
	_bag.add_item(&"fiber", 4, &"transfer")
	var carrots: int = _bag.count_of(&"carrot")
	var fiber: int = _bag.count_of(&"fiber")
	var seeds: int = _bag.count_of(&"carrot_seeds")
	var collected: int = _bag.today_collected
	var nested: Array[bool] = []
	var on_crafted := func(_id: StringName) -> void: nested.append(crafts.craft(&"carrot_seed_pack"))
	crafts.crafted.connect(on_crafted)
	if table != null:
		player.global_position = table.global_position + Vector2(0, 20)
		var interact := InputEventKey.new()
		interact.keycode = KEY_F
		interact.physical_keycode = KEY_F
		interact.pressed = true
		Input.parse_input_event(interact)
		await process_frame
		interact.pressed = false
		Input.parse_input_event(interact)
	var view: Control = _main.get_node("UI/WorkbenchPanel")
	_check(view.visible and paused, "interacting with the workbench opens the shared modal")
	var buttons: Array[Node] = view.find_children("*", "Button", true, false)
	var make_button: Button
	for button: Button in buttons:
		if button.text == "制作 · 胡萝卜种子包": make_button = button
	_check(make_button != null and not make_button.disabled, "the usable chapter recipe has an enabled craft button")
	if make_button != null: make_button.pressed.emit()
	crafts.crafted.disconnect(on_crafted)
	_check(nested == [false], "craft observers cannot reenter even with ingredients for another batch")
	_check(_bag.count_of(&"carrot") == carrots - 1 and _bag.count_of(&"fiber") == fiber - 2 and _bag.count_of(&"carrot_seeds") == seeds + 4, "the workbench consumes ingredients and produces plantable seed items")
	_check(_bag.today_collected == collected, "crafting does not inflate harvest statistics")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var path: String = "user://chapter-workbench.png"
		_check(root.get_texture().get_image().save_png(path) == OK, "workbench screenshot is saved")
		print("[quest_integration] workbench=" + ProjectSettings.globalize_path(path))
	view.set_open(false)
	house.exit_house()
	if "--preview" in OS.get_cmdline_user_args():
		var clock: Node = _main.get_node("Systems/Time")
		var previous_time: Dictionary = clock.to_dict()
		var previous_position: Vector2 = player.global_position
		clock.from_dict({"day": 1, "minutes": 1200})
		clock.time_changed.emit(clock.day, clock.minutes)
		player.global_position = Vector2(96, 392)
		_main.get_node("Camera").global_position = player.global_position
		_main.get_node("Camera").reset_smoothing()
		await process_frame
		await RenderingServer.frame_post_draw
		var market_path: String = "user://chapter-market.png"
		_check(root.get_texture().get_image().save_png(market_path) == OK, "completed market screenshot is saved")
		print("[quest_integration] market=" + ProjectSettings.globalize_path(market_path))
		clock.from_dict(previous_time)
		clock.time_changed.emit(clock.day, clock.minutes)
		player.global_position = previous_position
		_main.get_node("Camera").global_position = player.global_position
		_main.get_node("Camera").reset_smoothing()
	# 正常键盘入口使用K，Q/E和J保持原用途。
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.physical_keycode = KEY_K
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	_check(journal.visible and paused, "K opens the integrated quest journal")
	journal.close()
	key.pressed = false
	Input.parse_input_event(key)
	var before_event: Dictionary = _save.collect().duplicate(true)
	chapter.enabled = true
	chapter.request_followup()
	await process_frame
	await process_frame
	_check(cutscene.is_playing() and player.has_input_leases(), "the chapter follow-up obtains an owned input lease")
	_check(_main.events.has_completed(&"ch1_market_memory"), "story facts commit before presentation ends")
	_check(_main.mail.status(&"chapter_one_complete").get("claimed", false), "the chapter letter is delivered without generating a second reward")
	journal.set_open(true)
	_check(not journal.visible and not paused, "other modals cannot pause a running cutscene")
	player.set_input_locked(true)
	_check(cutscene.skip(), "the integrated cutscene can be skipped")
	_check(player.input_locked and not player.has_input_leases(), "skipping releases only the story lease and preserves another input owner")
	player.set_input_locked(false)
	_check(not player.input_locked, "normal input returns when all owners release")
	var skipped: Dictionary = _save.collect().duplicate(true)
	_save.apply(before_event)
	await process_frame
	_check(not cutscene.is_playing() and not _main.events.has_completed(&"ch1_market_memory"), "restoring a pre-event save does not auto-trigger or replay the event")
	chapter.request_followup()
	await process_frame
	await process_frame
	cutscene.advance_line()
	_check(cutscene.choose(0), "the actual chapter choice is reachable")
	cutscene.advance_line()
	_check(not cutscene.is_playing() and not player.input_locked, "fully watching restores player control")
	_check(_main.events.encode() == skipped.events and _main.mail.encode() == skipped.mail, "full viewing and skipping produce identical persistent story and mail facts")
	_save.apply(before_event)
	chapter.request_followup()
	await process_frame
	await process_frame
	_save.apply(skipped)
	_check(not cutscene.is_playing() and not player.has_input_leases(), "loading cancels the old cutscene before restoring the new world")
	chapter.enabled = false
	_check(_save.save_game() and _save.load_game(), "chapter, craft output and tracking partitions persist together")
	_check(crafts.unlocked() and _bag.count_of(&"carrot_seeds") == seeds + 4, "reload retains both the usable entitlement and crafted seeds without duplication")
	_reset()
	_bag.add_item(&"carrot", 1, &"transfer")
	_bag.add_item(&"fiber", 2, &"transfer")
	_check(not crafts.craft(&"carrot_seed_pack") and _bag.count_of(&"carrot") == 1 and _bag.count_of(&"fiber") == 2, "a locked workbench preserves all ingredients")
	crafts.configure(_bag, func() -> bool: return true, func() -> bool: return false)
	_check(crafts.craft(&"carrot_seed_pack") and crafts.save_pending and not crafts.busy, "craft save failure keeps the committed result and releases the transaction")
	_check(_save.save_game() and not crafts.save_pending, "a later successful manual save clears the pending-save condition")
	crafts.configure(_bag, func() -> bool: return _quests.status_of(&"ch1_06_lamps") == 3, _save.save_game)
	var presenter: Node = _main.get_node("Systems/WorkbenchPresenter")
	view.queue_free()
	await process_frame
	_check(not _bag.changed.is_connected(presenter.refresh) and not crafts.changed.is_connected(presenter.refresh), "removing the workbench View disconnects Presenter model subscriptions")
	var replacement: Control = load("res://scripts/ui/panels/workbench_panel.gd").new()
	replacement.name = "WorkbenchPanel"
	_main.get_node("UI").add_child(replacement)
	_main.get_node("Systems/Modals").register_panel(replacement)
	presenter.configure(crafts, _bag, replacement)
	_check(_bag.changed.is_connected(presenter.refresh) and replacement.craft_requested.get_connections().size() == 1, "a replacement workbench View reconnects exactly one intent binding")
