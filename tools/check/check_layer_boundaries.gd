extends SceneTree
## 实际替换/移除View、重复日结和模型通知事务，验证分层契约而非文件名。

const Rest = preload("res://scripts/time/rest_service.gd")
const Transfer = preload("res://scripts/inventory/storage_transfer_service.gd")
const Store = preload("res://scripts/inventory/stack_store.gd")
const Processing = preload("res://scripts/activities/processing_session.gd")
const Presenter = preload("res://scripts/ui/presenters/farm_activities_presenter.gd")
const Recipe = preload("res://data/recipes/pickled_tomato.tres")

class Clock extends Node:
	var day: int = 1
	var minutes: int = 360
	func is_evening() -> bool: return minutes >= 1080
	func clock_text() -> String: return "06:00"
	func sleep() -> void:
		day += 1
		minutes = 360
	func rest() -> bool:
		if is_evening():
			sleep()
			return true
		minutes = 1200
		return false

class View extends Control:
	signal opened(mode: StringName)
	signal closed(mode: StringName)
	signal refresh_requested
	signal deposit_requested(id: StringName, all: bool)
	signal withdraw_requested(id: StringName, all: bool)
	signal fish_requested
	var mode: StringName = &"storage"
	var data: Dictionary = {}
	func open(next: StringName) -> void:
		mode = next
		show()
		opened.emit(mode)
	func close() -> void:
		hide()
		closed.emit(mode)
	func render(state: Dictionary) -> void: data = state

var _checks: int = 0
var _failures: int = 0
var _main: Node2D


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[layer_boundaries] FAIL: " + message)


func _run() -> void:
	_check_rest_service()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_main.get_node("Systems/Time").running = false
	_check_atomic_models()
	await _check_replaceable_view()
	await _check_rest_without_view()
	await _check_controller_cleanup()
	_check(true, "all lifecycle and independent-view probes reached their end")
	_main.queue_free()
	await process_frame
	print("[layer_boundaries] %d checks, %d failures; reached end" % [_checks, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_rest_service() -> void:
	var clock := Clock.new()
	var wallet := Economy.new()
	var energy: Node = preload("res://scripts/player/stamina.gd").new()
	var service := Rest.new()
	var writes: Array[int] = [0]
	service.configure(clock, wallet, energy, func() -> bool:
		writes[0] += 1
		return false)
	_check(service.begin() and not service.begin(true), "one rest session owns all requests, including pass-out")
	_check(not service.settle().advanced and clock.day == 1 and clock.minutes == 1200, "nap changes time without advancing date")
	service.settle()
	_check(service.persist() and writes[0] == 0, "nap does not write a next-day save")
	service.finish()
	_check(service.begin(), "next rest can begin after completion")
	_check(service.settle().advanced and clock.day == 2, "evening rest advances the date")
	service.settle()
	_check(clock.day == 2, "repeated settlement cannot advance twice")
	_check(not service.persist() and not service.persist() and writes[0] == 1, "save failure is reported and a repeated commit does not write twice")
	service.finish()
	_check(service.begin(true), "pass-out can start without any interface")
	var result: Dictionary = service.settle()
	service.settle()
	_check(clock.day == 3 and wallet.coins == 450 and result.lost == 50 and energy.value == 50, "pass-out advances, fines and applies half stamina exactly once")
	service.clear()
	clock.free()
	wallet.free()
	energy.free()


func _check_atomic_models() -> void:
	var bag: Inventory = _main.get_node("Systems/Inventory")
	var transfer := Transfer.new()
	transfer.bag = bag
	transfer.storage = Store.new(2)
	bag.add_item(&"wood", 5)
	var observations: Array[bool] = []
	var observe := func() -> void:
		observations.append(bag.count_of(&"wood") + transfer.storage.count_of(&"wood") == 5)
		_check(transfer.deposit(&"wood", 1) == 0, "storage transaction blocks synchronous observer reentry")
	bag.changed.connect(observe)
	_check(transfer.deposit(&"wood", 3) == 3 and transfer.storage.count_of(&"wood") == 3, "deposit commits both models")
	_check(transfer.withdraw(&"wood", 2) == 2 and transfer.storage.count_of(&"wood") == 1, "withdraw preserves the item total")
	bag.changed.disconnect(observe)
	_check(observations.size() == 2 and not observations.has(false), "inventory observers never see a half-completed storage move")
	var processing := Processing.new()
	bag.add_item(&"tomato", 3)
	var ready_observations: Array[bool] = []
	var check_ready := func() -> void: ready_observations.append(processing.ready_day == 2 and bag.count_of(&"tomato") == 0)
	bag.changed.connect(check_ready)
	_check(processing.start(1, bag, Recipe) and not processing.start(1, bag, Recipe), "processing consumes ingredients once and preserves its unique state")
	bag.changed.disconnect(check_ready)
	_check(ready_observations.size() == 1 and ready_observations[0], "ingredient notification already includes the committed processing state")
	_check(not processing.collect(1, bag, Recipe), "processing cannot be collected before due day")
	var products: int = bag.count_of(Recipe.product)
	_check(processing.collect(2, bag, Recipe) and not processing.collect(2, bag, Recipe), "processing produces exactly one batch")
	_check(bag.count_of(Recipe.product) == products + Recipe.product_count, "standalone processing uses the original item inventory")


func _check_replaceable_view() -> void:
	var activities: Node = _main.get_node("Systems/FarmActivities")
	var bag: Inventory = _main.get_node("Systems/Inventory")
	var original: Control = activities.panel
	original.queue_free()
	await process_frame
	await process_frame
	var stored: int = activities.storage.count_of(&"wood")
	_check(activities.deposit(&"wood", 1) == 1 and activities.storage.count_of(&"wood") == stored + 1, "storage remains usable after removing its concrete view")
	_main.get_node("Systems/ActivitiesPresenter").queue_free()
	await process_frame
	var view := View.new()
	_main.get_node("UI").add_child(view)
	var presenter := Presenter.new()
	presenter.configure(activities, bag, view, _main.get_node("UI/Toast"))
	_main.get_node("Systems").add_child(presenter)
	view.open(&"storage")
	_check(not view.data.is_empty() and view.data.has("bag"), "presenter can render a replacement view with no native widgets")
	stored = activities.storage.count_of(&"wood")
	view.deposit_requested.emit(&"wood", false)
	_check(activities.storage.count_of(&"wood") == stored + 1, "replacement view intent reaches the same transaction service")
	# 拆除但尚未释放时，旧适配也不应继续接收操作或保留钓鱼绑定。
	presenter.get_parent().remove_child(presenter)
	stored = activities.storage.count_of(&"wood")
	view.deposit_requested.emit(&"wood", false)
	_check(activities.storage.count_of(&"wood") == stored, "detached presenter cannot keep forwarding old view intents")
	_check(view.fish_requested.get_connections().is_empty(), "detaching presenter removes its direct application-service signal binding")
	presenter.free()
	view.queue_free()
	await process_frame
	var snapshot: Dictionary = activities.to_dict()
	activities.from_dict(snapshot)
	_check(activities.to_dict() == snapshot, "activity state restores without a presenter or view")


func _check_rest_without_view() -> void:
	_main.get_node("UI/DaySummary").queue_free()
	await process_frame
	var clock: Node = _main.get_node("Systems/Time")
	var wallet: Economy = _main.get_node("Systems/Economy")
	var rest: Node = _main.get_node("Systems/Rest")
	var regions: Node = _main.get_node("Systems/Regions")
	var snapshots: Array[Dictionary] = []
	wallet.coins = 500
	rest.service.configure(clock, wallet, _main.get_node("Systems/Stamina"), func() -> bool:
		snapshots.append(_main.get_node("Systems/Save").collect())
		return false)
	regions.travel_to(&"forest")
	var day: int = clock.day
	clock.day_over.emit()
	clock.day_over.emit()
	clock.day_over.emit()
	await create_timer(4.1).timeout
	_check(clock.day == day + 1 and wallet.coins == 450, "removing DaySummary does not disable or duplicate real pass-out settlement")
	_check(regions.active_region == &"home" and not regions.player.input_locked and not rest.service.busy, "save failure still restores home, visibility and player control")
	_check(snapshots.size() == 1 and snapshots[0].regions.current == "home", "one final snapshot is requested after relocation")
	if not snapshots.is_empty():
		var point: Dictionary = snapshots[0].player
		_check(regions.player.global_position.distance_to(Vector2(point.x, point.y)) < 1.0, "saved player location is the final wake position")


func _check_controller_cleanup() -> void:
	var old: Node = _main.get_node("Systems/Rest")
	old.queue_free()
	await process_frame
	for cancel_after: float in [0.1, 0.7]:
		var clock: Node = _main.get_node("Systems/Time")
		clock.minutes = 360
		var service := Rest.new()
		service.configure(clock, _main.get_node("Systems/Economy"), _main.get_node("Systems/Stamina"), func() -> bool: return true)
		var controller: Node = preload("res://scripts/time/rest_controller.gd").new()
		var player: Node2D = _main.get_node("Systems/Regions").player
		controller.configure(service, player, _main.get_node("Systems/HouseManager"), _main.get_node("ScreenFade"), Callable(), Callable())
		_main.get_node("Systems").add_child(controller)
		controller.request_sleep()
		await create_timer(cancel_after).timeout
		controller.queue_free()
		await process_frame
		_check(not player.input_locked and not _main.get_node("ScreenFade").is_black(), "destroying a rest controller releases its input and curtain ownership")
		await create_timer(1.0).timeout
		_check(not service.busy and not player.input_locked, "cancelled fade/timer cannot resume an obsolete rest operation")
