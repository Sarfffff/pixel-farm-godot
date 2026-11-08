extends Node2D
## 场景组合根：依赖只在这里装配。领域模块不查找界面、不彼此创建服务。

const DailyCycle := preload("res://scripts/core/daily_cycle.gd")
const TradeService := preload("res://scripts/economy/trade_service.gd")
const WorldObjects := preload("res://scripts/persistence/world_objects.gd")
const ModalPanel := preload("res://scripts/ui/common/modal_panel.gd")
const ModalCoordinator := preload("res://scripts/ui/common/modal_coordinator.gd")
const CoinFeedback := preload("res://scripts/ui/hud/coin_feedback.gd")
const WorldRegions := preload("res://scripts/regions/world_regions.gd")
const RestService := preload("res://scripts/time/rest_service.gd")
const RestController := preload("res://scripts/time/rest_controller.gd")
const DaySummaryPresenter := preload("res://scripts/ui/presenters/day_summary_presenter.gd")
const ActivityPanel := preload("res://scripts/ui/panels/farm_activities_panel.gd")
const ActivitiesPresenter := preload("res://scripts/ui/presenters/farm_activities_presenter.gd")
const CommunityVisuals := preload("res://scripts/presentation/community_visuals.gd")
const DevelopmentControls := preload("res://scripts/platform/development_controls.gd")
const SeedInformationPresenter := preload("res://scripts/ui/presenters/seed_information_presenter.gd")
const QuestService := preload("res://scripts/progression/quest_service.gd")
const MailService := preload("res://scripts/progression/mail_service.gd")
const MailboxPanel := preload("res://scripts/ui/panels/mailbox_panel.gd")
const MailboxPresenter := preload("res://scripts/ui/presenters/mailbox_presenter.gd")
const Mailbox := preload("res://scripts/world/interactions/mailbox.gd")
const QuestDialoguePresenter := preload("res://scripts/ui/presenters/quest_dialogue_presenter.gd")
const QuestJournal := preload("res://scenes/ui/quest_journal.tscn")
const QuestTracker := preload("res://scenes/ui/quest_tracker.tscn")
const QuestJournalPresenter := preload("res://scripts/ui/presenters/quest_journal_presenter.gd")
const EventService := preload("res://scripts/events/event_service.gd")
const CutscenePlayer := preload("res://scripts/events/cutscene_player.gd")
const ChapterFlow := preload("res://scripts/progression/chapter_flow.gd")
const CraftingService := preload("res://scripts/progression/crafting_service.gd")
const WorkbenchPanel := preload("res://scripts/ui/panels/workbench_panel.gd")
const WorkbenchPresenter := preload("res://scripts/ui/presenters/workbench_presenter.gd")
const Workbench := preload("res://scripts/world/interactions/workbench.gd")

var daily_cycle: RefCounted
var world_objects := WorldObjects.new()
var regions: Node
var quests: RefCounted
## B2-05公开投递/阅读/附件服务；剧情条件由后续整合层接线。
var mail: RefCounted
var _summary_presenter: RefCounted
var _quest_dialogue: Node
var _quest_journal: Node
var events: RefCounted
var crafts: RefCounted
var _cutscene: Node
var _chapter: Node
var _workbench: Node
var _community_visuals: Node


func _ready() -> void:
	world_objects.object_restored.connect(_bind_obstacle)
	_configure_activities()
	var modals := ModalCoordinator.new()
	modals.name = "Modals"
	get_node("Systems").add_child(modals)
	modals.configure(get_node("Farm/World/Player").set_modal_input_locked, get_node("UI/Toolbar").set_ui_visible)
	modals.opening_allowed = _can_open_game_modal
	for panel: Node in get_node("UI").get_children():
		if panel is ModalPanel:
			panel.pauses_world = panel.pauses_world or panel.name in [&"PauseMenu", &"HelpPanel", &"SettingsPanel"]
			modals.register_panel(panel)
	for object: Node in get_node("Farm/World").get_children():
		if object.has_method(&"persistence_id"):
			world_objects.register_object(object)
			_bind_obstacle(object)
	var save: Node = get_node("Systems/Save")
	var registry: RefCounted = save.snapshots
	var clock: Node = get_node("Systems/Time")
	var economy: Economy = get_node("Systems/Economy")
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		var feedback := CoinFeedback.new()
		feedback.name = "CoinFeedback"
		feedback.configure(economy, audio.play_sfx)
		get_node("UI").add_child(feedback)
	registry.register_section(&"time", clock.to_dict, clock.from_dict)
	registry.register_section(&"coins", func() -> int: return economy.coins,
		func(coins: int) -> void:
			economy.coins = maxi(0, coins)
			economy.changed.emit(economy.coins), TYPE_INT)
	registry.register_section(&"inventory", get_node("Systems/Inventory").to_dict, get_node("Systems/Inventory").from_dict)
	_configure_mail(economy, clock, save, modals)
	registry.register_section(&"mail", mail.encode, mail.restore, TYPE_DICTIONARY, true)
	_configure_quests(economy, clock, save)
	registry.register_section(&"world_objects", world_objects.to_dict, world_objects.from_dict, TYPE_DICTIONARY, true)
	var field: Node = get_node("Farm/Tiller")
	registry.register_section(&"farm", func() -> Dictionary:
		var state: Dictionary = field.to_dict()
		state.erase("rocks")
		return state, field.from_dict)
	var player: Node2D = get_node("Farm/World/Player")
	var house: Node = get_node("Systems/HouseManager")
	regions = WorldRegions.new()
	regions.name = "Regions"
	get_node("Systems").add_child(regions)
	regions.configure(self, player, get_node("Farm"), field, house, get_node("Camera"), clock, get_node("Systems/Inventory"), get_node("Systems/Stamina"))
	player.action_started.connect(regions.begin_tool_action)
	player.use_requested.connect(regions.commit_tool_action)
	daily_cycle.on_begin_day(regions.begin_day)
	_configure_rest()
	_configure_development_controls()
	var seed_presenter := SeedInformationPresenter.new()
	seed_presenter.name = "SeedInformationPresenter"
	seed_presenter.configure(get_node("UI/ShopPanel"), field.crop_definitions(), clock, save)
	get_node("Systems").add_child(seed_presenter)
	registry.register_section(&"player", func() -> Dictionary:
		var point: Vector2 = regions.home_save_position()
		return {&"x": point.x, &"y": point.y},
		func(data: Dictionary) -> void: player.global_position = Vector2(float(data.get("x", player.global_position.x)), float(data.get("y", player.global_position.y))))
	for entry: Array in [
		[&"coop", "Farm/World/ChickenCoop", false],
		[&"community", "Systems/CommunityCenter", false],
		[&"weather", "Systems/Weather", false],
		[&"stamina", "Systems/Stamina", false],
		[&"upgrades", "Systems/Upgrades", true],
		[&"forage", "Farm/World/Forage", true],
		[&"berries", "Farm/World/BerryGrove", false],
		[&"farm_activities", "Systems/FarmActivities", true],
		[&"friendship", "Systems/Friendship", true],
		[&"orders", "Systems/Orders", false],
		[&"tutorial", "Systems/Tutorial", true],
	]:
		var participant: Node = get_node(entry[1])
		registry.register_section(entry[0], participant.to_dict, participant.from_dict, TYPE_DICTIONARY, entry[2])
	registry.register_section(&"regions", regions.to_dict, regions.from_dict, TYPE_DICTIONARY, true)
	# 任务依赖世界与基础模型，最后恢复；恢复期间不开放接取和交付。
	registry.register_section(&"quests", quests.encode, quests.restore, TYPE_DICTIONARY, true)
	_configure_quest_journal(modals, save)
	registry.register_section(&"quest_tracking", _quest_journal.encode_tracking, _quest_journal.restore_tracking, TYPE_DICTIONARY, true)
	_configure_chapter(modals, clock, save)
	registry.register_section(&"events", events.encode, _restore_story_events, TYPE_DICTIONARY, true)
	save.restored.connect(func() -> void:
		clock.time_changed.emit(clock.day, clock.minutes)
		get_node("Farm/Nav").request_rebuild())
	get_node("Systems/Presentation").configure(get_node("Farm"), clock, get_node("Systems/Weather"), house)


func _exit_tree() -> void:
	if quests != null and is_instance_valid(_community_visuals) and quests.changed.is_connected(_community_visuals.refresh):
		quests.changed.disconnect(_community_visuals.refresh)
	if quests != null and quests.changed.is_connected(get_node("Farm/Nav").request_rebuild):
		quests.changed.disconnect(get_node("Farm/Nav").request_rebuild)
	if is_instance_valid(_cutscene): _cutscene.release()
	if events != null: events.release()
	if crafts != null: crafts.release()
	if get_tree().node_added.is_connected(_bind_quest_actor):
		get_tree().node_added.disconnect(_bind_quest_actor)
	if is_instance_valid(_quest_dialogue):
		_quest_dialogue.unbind()
	if is_instance_valid(_quest_journal):
		_quest_journal.dispose()
	# 解除持久化与每日回调，防止 Callable 在场景退出后保留会话对象。
	get_node("Systems/Time").advance_day = Callable()
	get_node("Systems/Save").snapshots.clear()
	world_objects.clear()
	daily_cycle.clear()
	daily_cycle = null
	_summary_presenter = null
	if quests != null:
		quests.clear()
	quests = null
	if mail != null:
		mail.clear()
	mail = null


func _bind_obstacle(object: Node2D) -> void:
	if object.has_signal(&"obstacle_changed"):
		var refresh: Callable = get_node("Farm/Nav").request_rebuild
		if not object.is_connected(&"obstacle_changed", refresh):
			object.connect(&"obstacle_changed", refresh)


func _enter_tree() -> void:
	var clock: Node = get_node("Systems/Time")
	var weather: Node = get_node("Systems/Weather")
	var field: Node = get_node("Farm/Tiller")
	daily_cycle = DailyCycle.new(clock)
	daily_cycle.on_finish_day(func(_day: int) -> void: field.finish_day(weather.is_rainy()))
	daily_cycle.on_begin_day(weather.begin_day)
	daily_cycle.on_begin_day(func(_day: int) -> void: field.begin_day(weather.is_rainy()))
	clock.advance_day = daily_cycle.advance
	var trade := TradeService.new()
	trade.name = "Trade"
	trade.configure(get_node("Systems/Inventory"), get_node("Systems/Economy"))
	trade.add_purchase_rule(_purchase_rule)
	get_node("Systems").add_child(trade)


## 章节任务：定义来自 data/quests，事实归 QuestLog，事务与重入由 QuestService 负责。
func _configure_quests(economy: Economy, clock: Node, save: Node) -> void:
	quests = QuestService.new()
	quests.start()
	quests.configure(get_node("Systems/Inventory"), economy, func() -> int: return int(clock.day), save.save_game)
	quests.save_failed.connect(get_node("UI/Toast").show_message.bind("任务进度已更新，但存档失败 · 请手动重试保存"))
	_quest_dialogue = QuestDialoguePresenter.new()
	_quest_dialogue.name = "QuestDialoguePresenter"
	_quest_dialogue.configure(quests, get_node("Systems/Inventory"))
	get_node("Systems").add_child(_quest_dialogue)
	for actor: Node in get_tree().get_nodes_in_group(&"interactable"):
		_bind_quest_actor(actor)
	# 店主随室内场景延迟创建；只在创建时绑定，不让 NPC 每次交互查找任务服务。
	get_tree().node_added.connect(_bind_quest_actor)


func _bind_quest_actor(actor: Node) -> void:
	if is_instance_valid(_quest_dialogue):
		_quest_dialogue.bind_actor(actor)
	if actor is Sprite2D and actor.name == &"CoffeeTable" and is_instance_valid(_workbench):
		var room: Node = actor.get_parent().get_parent()
		if room.scene_file_path == "res://scenes/world/house_interior.tscn" and not actor.has_node("SeedWorkbench"):
			var interaction := Workbench.new()
			interaction.name = "SeedWorkbench"
			interaction.open_workbench = _workbench.open
			interaction.is_unlocked = crafts.unlocked
			actor.add_child(interaction)


func _can_open_game_modal() -> bool:
	var player: Node = get_node("Farm/World/Player") if regions == null else regions.player
	var rest: Node = get_node_or_null("Systems/Rest")
	return player.can_open_gameplay_ui() and (rest == null or not rest.service.busy)


func _configure_chapter(modals: Node, clock: Node, save: Node) -> void:
	crafts = CraftingService.new()
	crafts.configure(get_node("Systems/Inventory"), func() -> bool: return quests.status_of(&"ch1_06_lamps") == 3, save.save_game)
	crafts.save_failed.connect(get_node("UI/Toast").show_message.bind("制作已结算，但保存失败 · 请手动重试保存"))
	save.saved.connect(func(_slot: int) -> void: crafts.confirm_saved())
	var view := WorkbenchPanel.new()
	view.name = "WorkbenchPanel"
	get_node("UI").add_child(view)
	modals.register_panel(view)
	_workbench = WorkbenchPresenter.new()
	_workbench.name = "WorkbenchPresenter"
	get_node("Systems").add_child(_workbench)
	_workbench.configure(crafts, get_node("Systems/Inventory"), view)
	events = EventService.new()
	events.configure(_story_fact, Callable(), save.save_game)
	events.load_directory("res://data/events")
	events.save_failed.connect(func(_id: StringName) -> void: get_node("UI/Toast").show_message("剧情进度保存失败 · 请手动重试保存"))
	_cutscene = CutscenePlayer.new()
	_cutscene.name = "ChapterCutscene"
	_cutscene.configure(events, regions.player.acquire_input_lease, regions.player.release_input_lease, _story_actor, _face_story_actor, get_node("Camera"))
	get_node("Systems").add_child(_cutscene)
	_chapter = ChapterFlow.new()
	_chapter.name = "ChapterFlow"
	_chapter.configure(quests, mail, events, _cutscene.play, func() -> bool:
		return regions.active_region == &"home" and not get_node("Systems/HouseManager").is_inside() and not regions.player.input_locked and not regions.player.is_acting)
	_chapter.enabled = save.autoload_enabled
	get_node("Systems").add_child(_chapter)
	if save.autoload_enabled and not save.has_save(): _start_new_chapter.call_deferred()
	get_node("UI/DialoguePanel").visibility_changed.connect(func() -> void:
		if not get_node("UI/DialoguePanel").visible: _chapter.request_followup())
	regions.region_changed.connect(func(_id: StringName) -> void: _chapter.request_followup())
	get_node("Systems/HouseManager").location_changed.connect(_chapter.request_followup)
	clock.day_started.connect(func(_day: int) -> void: _chapter.request_followup())
	save.restoring.connect(_cancel_story)
	save.restored.connect(_chapter.cancel_pending)
	_community_visuals.configure_chapter(_chapter_stage)
	quests.changed.connect(_community_visuals.refresh)
	quests.changed.connect(get_node("Farm/Nav").request_rebuild)


func _chapter_stage() -> int:
	if quests.status_of(&"ch1_06_lamps") == 3: return 3
	if quests.status_of(&"ch1_05_flowerbed") == 3: return 2
	return 1 if quests.status_of(&"ch1_01_gate") == 3 else 0


func _start_new_chapter() -> void:
	# 测试/预览可在场景加入后、首个延迟帧前关闭自动恢复；新游戏投递同样尊重此开关。
	if not is_instance_valid(_chapter): return
	_chapter.enabled = get_node("Systems/Save").autoload_enabled
	if _chapter.enabled: _chapter.start_new_game()


func _story_fact(kind: StringName, key: StringName) -> Variant:
	match kind:
		&"day": return get_node("Systems/Time").day
		&"minute": return get_node("Systems/Time").minutes % 1440
		&"location": return &"interior" if get_node("Systems/HouseManager").is_inside() else regions.active_region
		&"weather": return get_node("Systems/Weather").current
		&"relationship": return get_node("Systems/Friendship").points_of(key)
		&"quest": return [&"locked", &"available", &"active", &"completed"][quests.status_of(key)]
	return null


func _story_actor(id: StringName) -> Node2D:
	if id == &"player": return regions.player
	for actor: Node in get_tree().get_nodes_in_group(&"interactable"):
		if actor.has_method(&"configure_quest_dialogue") and actor.get(&"npc_id") == id: return actor as Node2D
	return null


func _face_story_actor(id: StringName, direction: StringName) -> void:
	var actor: Node2D = _story_actor(id)
	if is_instance_valid(actor) and actor.has_method(&"face_direction"): actor.face_direction(direction)


func _cancel_story() -> void:
	_cutscene.cancel()
	_chapter.cancel_pending()


func _restore_story_events(data: Dictionary) -> void:
	events.restore(data)


func _configure_quest_journal(modals: Node, save: Node) -> void:
	var tracker: Control = QuestTracker.instantiate()
	var panel: Control = QuestJournal.instantiate()
	get_node("UI").add_child(tracker)
	get_node("UI").move_child(tracker, 0)
	get_node("UI").add_child(panel)
	modals.register_panel(panel)
	_quest_journal = QuestJournalPresenter.new()
	_quest_journal.name = "QuestJournalPresenter"
	get_node("Systems").add_child(_quest_journal)
	_quest_journal.configure(quests, get_node("Systems/Inventory"), panel, tracker, save, _quest_giver_location)


func _quest_giver_location(giver: StringName) -> String:
	match giver:
		&"shopkeeper": return "农场北侧杂货铺柜台（交易09:00–17:00）"
		&"carpenter": return "农场西侧，农舍南方附近"
		&"fisherman": return "农场东南池塘附近"
		&"gardener": return "农场中央田地附近"
	return "农场内寻找委托人"


func _configure_mail(economy: Economy, clock: Node, save: Node, modals: Node) -> void:
	mail = MailService.new()
	mail.load_definitions()
	var bag: Inventory = get_node("Systems/Inventory")
	mail.configure(bag, economy, func() -> int: return int(clock.day), save.save_game)
	mail.save_failed.connect(get_node("UI/Toast").show_message.bind("信箱进度保存失败 · 已领取附件不会重发，请重试保存"))
	var view := MailboxPanel.new()
	view.name = "MailboxPanel"
	get_node("UI").add_child(view)
	modals.register_panel(view)
	var presenter := MailboxPresenter.new()
	presenter.name = "MailboxPresenter"
	get_node("Systems").add_child(presenter)
	presenter.configure(mail, bag, view)
	var mailbox := Mailbox.new()
	mailbox.name = "Mailbox"
	mailbox.position = Vector2(512, 168)
	get_node("Farm/World").add_child(mailbox)
	mailbox.configure(mail.unread_count)
	mail.changed.connect(mailbox.refresh)
	mailbox.open_requested.connect(presenter.open_mailbox)
	get_node("Farm/Nav").request_rebuild()


func _purchase_rule(item: ItemData) -> String:
	var community: Node = get_node("Systems/CommunityCenter")
	if item.unlock_stage > community.unlocked_stage():
		return "先完成社区修复，才能购买%s" % item.display_name
	return get_node("Farm/Tiller").seed_purchase_hint(item.id)


func _configure_rest() -> void:
	var clock: Node = get_node("Systems/Time")
	var summary: Node = get_node("UI/DaySummary")
	var service := RestService.new()
	service.configure(clock, get_node("Systems/Economy"), get_node("Systems/Stamina"), get_node("Systems/Save").save_game)
	# Callable不持有RefCounted目标；组合根显式拥有Presenter，避免显示查询失效。
	_summary_presenter = DaySummaryPresenter.new()
	_summary_presenter.clock = clock
	_summary_presenter.economy = get_node("Systems/Economy")
	_summary_presenter.inventory = get_node("Systems/Inventory")
	_summary_presenter.tomorrow = get_node("Systems/FarmActivities").tomorrow_text
	summary.summary_data = _summary_presenter.snapshot
	var controller := RestController.new()
	controller.name = "Rest"
	var audio: Node = get_node_or_null("/root/AudioManager")
	controller.configure(service, get_node("Farm/World/Player"), get_node("Systems/HouseManager"), get_node("ScreenFade"), _recover_pass_out, audio.play_sfx.bind(&"sleep") if audio != null else Callable())
	get_node("Systems").add_child(controller)
	summary.sleep_requested.connect(controller.request_sleep)
	controller.started.connect(summary.set_open.bind(false))
	controller.save_failed.connect(get_node("UI/Toast").show_message.bind("休息已结算，但存档失败 · 请手动重试保存"))
	clock.day_over.connect(controller.pass_out)


func _configure_development_controls() -> void:
	var player: Node = regions.player
	var rest: Node = get_node("Systems/Rest")
	var controls := DevelopmentControls.new()
	controls.name = "DevelopmentControls"
	var allow_tools: bool = DevelopmentControls.allowed(OS.has_feature("editor"), OS.has_feature("farm_release"), "--enable-dev-tools" in OS.get_cmdline_user_args())
	controls.configure(allow_tools, get_node("Systems/Time").sleep, func() -> bool:
		return not get_tree().paused and not player.input_locked and not player.is_acting and not rest.service.busy)
	get_node("Systems").add_child(controls)
	if allow_tools:
		get_node("UI/Toast").show_message("开发工具已启用 · N 推进一天（不自动保存）")


func _recover_pass_out() -> void:
	regions.recover_home()
	var player: Node2D = regions.player
	player.global_position = get_node("Farm/World/CottageDoor").global_position + Vector2(0, 16)
	get_node("Camera").global_position = player.global_position
	get_node("Camera").reset_smoothing()


func _configure_activities() -> void:
	var activities: Node = get_node("Systems/FarmActivities")
	var visuals := CommunityVisuals.new()
	visuals.name = "CommunityVisuals"
	_community_visuals = visuals
	visuals.world = get_node("Farm/World")
	activities.add_child(visuals)
	activities.configure(get_node("Systems/Inventory"), get_node("Farm/World/Player"), get_node("Systems/Time"), get_node("Systems/Stamina"), get_node("Systems/Save").save_game, get_node("Farm/Tiller").tomorrow_harvest_count, get_node("Farm/World"), visuals)
	var view := ActivityPanel.new()
	view.name = "FarmActivitiesPanel"
	get_node("UI").add_child(view)
	var presenter := ActivitiesPresenter.new()
	presenter.name = "ActivitiesPresenter"
	presenter.configure(activities, get_node("Systems/Inventory"), view, get_node("UI/Toast"))
	get_node("Systems").add_child(presenter)
