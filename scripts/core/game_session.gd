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

var daily_cycle: RefCounted
var world_objects := WorldObjects.new()
var regions: Node
var _summary_presenter: RefCounted


func _ready() -> void:
	world_objects.object_restored.connect(_bind_obstacle)
	_configure_activities()
	var modals := ModalCoordinator.new()
	modals.name = "Modals"
	get_node("Systems").add_child(modals)
	modals.configure(get_node("Farm/World/Player").set_modal_input_locked, get_node("UI/Toolbar").set_ui_visible)
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
	save.restored.connect(func() -> void:
		clock.time_changed.emit(clock.day, clock.minutes)
		get_node("Farm/Nav").request_rebuild())
	get_node("Systems/Presentation").configure(get_node("Farm"), clock, get_node("Systems/Weather"), house)


func _exit_tree() -> void:
	# 解除持久化与每日回调，防止 Callable 在场景退出后保留会话对象。
	get_node("Systems/Time").advance_day = Callable()
	get_node("Systems/Save").snapshots.clear()
	world_objects.clear()
	daily_cycle.clear()
	daily_cycle = null
	_summary_presenter = null


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
