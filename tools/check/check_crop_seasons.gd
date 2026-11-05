extends SceneTree
## B1-06：换季枯萎、跨季/复收、清理、旧档与显示端口独立性。

const Rules := preload("res://scripts/world/farming/crop_season_rules.gd")
const Presenter := preload("res://scripts/ui/presenters/seed_information_presenter.gd")
const CARROT: CropData = preload("res://data/crops/carrot.tres")
const WHEAT: CropData = preload("res://data/crops/wheat.tres")
const BLUEBERRY: CropData = preload("res://data/crops/blueberry.tres")
const CELL := Vector2i(18, 7)
class Clock extends Node:
	signal day_started(day: int)
	var day: int = 28
class View extends Control:
	var seed_information: Callable
	var refreshes: int = 0
	func refresh_offers() -> void: refreshes += 1

var _main: Node
var _checks: int = 0
var _failures: int = 0


func _init() -> void: _run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("[crop_seasons] FAIL: " + message)


func _fixture(day: int, data: CropData, stage: int = 0, watered: bool = true, regrowing: bool = false) -> Crop:
	_main.get_node("Systems/Time").from_dict({"day": day, "minutes": 360})
	_main.get_node("Farm/Tiller").from_dict({"tilled": [[CELL.x, CELL.y]], "crops": [{"x": CELL.x, "y": CELL.y, "id": String(data.id), "stage": stage, "watered": watered, "regrowing": regrowing}]})
	return _main.get_node("Farm/Tiller")._crops[CELL]


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_check(not Rules.information(CARROT, 28).fits_first_harvest, "last spring day cannot yield a new carrot before summer")
	_check(Rules.information(CARROT, 25).fits_first_harvest, "three watered nights can finish before spring ends")
	_check(not Rules.information(CARROT, 26).fits_first_harvest, "harvest would mature on invalid new-season dawn")
	_check(Rules.information(WHEAT, 56).fits_first_harvest, "summer-autumn crop can use next season's days")
	_check(Rules.information(BLUEBERRY, 29).grow_nights == 5 and Rules.information(BLUEBERRY, 29).regrow_nights == 2, "information uses configured stage and regrowth durations")
	_check(not Rules.should_wither(CARROT, &"winter", true), "protected growing-area policy exempts seasonal failure")
	await _check_presenter()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	var clock: Node = _main.get_node("Systems/Time")
	clock.running = false
	_main.get_node("Systems/Weather").lock(&"sunny")
	var field: Node = _main.get_node("Farm/Tiller")
	var save: Node = _main.get_node("Systems/Save")
	var bag: Inventory = _main.get_node("Systems/Inventory")
	var energy: Node = _main.get_node("Systems/Stamina")
	var crop: Crop = _fixture(28, CARROT)
	clock.sleep()
	_check(clock.day == 29 and crop.withered and not crop.is_mature(), "outgoing day's growth is followed by new-season withering")
	_check(not crop.water() and not crop.grow_if_watered(), "withered crops cannot consume water or resume growth")
	var stamina_before: int = energy.value
	field.commit_tool_action(&"watering_can", CELL)
	_check(energy.value == stamina_before, "watering a dead crop never consumes stamina through actual tool port")
	var dead: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	var inventory_before: Dictionary = bag.to_dict()
	for repeat: int in 3:
		save.apply(dead)
		await process_frame
		_check(field._crops[CELL].withered and bag.to_dict() == inventory_before, "repeated JSON restore retains dead state without rewards")
	energy.value = 0
	field.interact(CELL)
	_check(not field._crops.has(CELL) and field.has_tilled_soil(CELL) and energy.value == 0, "F clears dead crop for free and keeps cultivated soil")
	_check(bag.to_dict() == inventory_before, "clearing dead crop awards neither produce nor progress items")
	energy.refill()
	crop = _fixture(56, WHEAT, 1)
	clock.sleep()
	_check(clock.day == 57 and not crop.withered and crop.stage == 2, "multi-season crop keeps real stage and grows across boundary")
	crop = _fixture(56, BLUEBERRY, BLUEBERRY.last_stage(), false)
	clock.sleep()
	_check(crop.withered and not crop.is_mature(), "unharvested mature summer crop also withers in autumn")
	crop = _fixture(56, BLUEBERRY, BLUEBERRY.last_stage() - 1, true, true)
	clock.sleep()
	_check(crop.withered and not crop.regrowing, "regrowth cannot bypass seasonal failure")
	crop = _fixture(85, CARROT, CARROT.last_stage(), false)
	_check(crop.withered, "old save without dead flag is sanitized for its current season")
	crop.apply_season(&"spring")
	_check(crop.withered, "dead crop never resurrects when suitable season returns")
	await _check_shop()
	_main.queue_free()
	await process_frame
	print("[crop_seasons] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_presenter() -> void:
	var clock := Clock.new()
	var view := View.new()
	var replacement := View.new()
	var presenter := Presenter.new()
	for node: Node in [clock, view, replacement, presenter]: root.add_child(node)
	presenter.configure(view, [CARROT], clock)
	_check(view.seed_information.call(CARROT.seed_item).contains("来不及首收"), "replacement view receives late-season risk without shop implementation")
	presenter.configure(replacement, [CARROT], clock)
	_check(not view.seed_information.is_valid(), "reconfiguration releases former view port")
	clock.day_started.emit(28)
	_check(view.refreshes == 0 and replacement.refreshes == 1, "only active view receives date refresh")
	root.remove_child(presenter)
	clock.day_started.emit(29)
	_check(not replacement.seed_information.is_valid() and replacement.refreshes == 1, "presenter exit removes all model and view bindings")
	presenter.free()
	for node: Node in [clock, view, replacement]: node.queue_free()
	await process_frame


func _check_shop() -> void:
	var clock: Node = _main.get_node("Systems/Time")
	var shop: Node = _main.get_node("UI/ShopPanel")
	var wallet: Economy = _main.get_node("Systems/Economy")
	var saved: Dictionary = _main.get_node("Systems/Save").collect()
	saved[&"time"] = {"day": 28, "minutes": 600}
	_main.get_node("Systems/Save").apply(saved)
	shop.set_open(true)
	await process_frame
	await process_frame
	var text: String = shop.seed_information.call(&"carrot_seeds")
	_check(text.contains("首收3晚") and text.contains("余季1天") and text.contains("来不及"), "real shop displays season, first harvest and last-day warning")
	for row: Node in shop._row_nodes:
		var details: Control = row.get_node_or_null("SeedInformation")
		if details != null:
			_check(details.get_global_rect().end.y <= (row as Control).get_global_rect().end.y, "seed information fits within its row")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var path: String = "user://seasonal_shop.png"
		_check(root.get_texture().get_image().save_png(path) == OK, "seasonal shop preview saved")
		print("[crop_seasons] screenshot=" + ProjectSettings.globalize_path(path))
	var before: int = wallet.coins
	_check(shop._buy(&"carrot_seeds", 8, 1) == 1 and wallet.coins == before - 8, "late but in-season seed purchase remains an explicit player choice")
	saved = _main.get_node("Systems/Save").collect()
	saved[&"time"] = {"day": 29, "minutes": 600}
	_main.get_node("Systems/Save").apply(saved)
	await process_frame
	await process_frame
	before = wallet.coins
	_check(shop._buy(&"carrot_seeds", 8, 1) == 0 and wallet.coins == before, "out-of-season purchase still rejects without charging")
	_check(shop.seed_information.call(&"carrot_seeds").contains("当前季节不可播种"), "information follows current date without stale snapshot")
	shop.set_open(false)
