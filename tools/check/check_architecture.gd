extends SceneTree
## 契约与集成：扩展接口、事务观察一致性、跨日雨水、备份故障恢复、世界恢复和模态锁。

const State := preload("res://scripts/animals/states/animal_state.gd")
const Brain := preload("res://scripts/animals/animal_state_machine.gd")
const Profile := preload("res://scripts/data/animal_profile.gd")
const Registry := preload("res://scripts/persistence/snapshot_registry.gd")
const JsonStore := preload("res://scripts/persistence/json_save_store.gd")
const Migrations := preload("res://scripts/persistence/save_migrations.gd")

class CustomState extends "res://scripts/animals/states/animal_state.gd":
	var enters: int = 0
	var exits: int = 0
	func enter(_context: RefCounted) -> void:
		enters += 1
	func tick(context: RefCounted, _delta: float, _position: Vector2) -> void:
		context.desired_velocity = Vector2(3, 0)
	func exit(_context: RefCounted) -> void:
		exits += 1

class FailedInstallStore extends "res://scripts/persistence/json_save_store.gd":
	var fail_publish: bool = false
	func _install(temp: String, destination: String) -> Error:
		if fail_publish and destination.ends_with(".json"):
			return ERR_CANT_CREATE
		return super._install(temp, destination)

class NewPanel extends "res://scripts/ui/common/modal_panel.gd":
	func set_open(value: bool) -> void:
		_set_modal_open(value)

var _failures: int = 0
var _checks: int = 0
var _main: Node2D
var _reached_end: bool = false


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[architecture] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_check_extension_contracts()
	_check_storage()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_main.get_node("Systems/Time").running = false
	_check_transactions()
	_check_rain_dates()
	await _check_modals()
	await _check_world_roundtrip()
	await _check_navigation()
	_reached_end = true
	_check(_reached_end, "all critical probes reached their end")
	_main.queue_free()
	root.get_node("AudioManager").stop_music(0.0)
	await process_frame
	await create_timer(0.1).timeout
	print("[architecture] %d checks, %d failures; reached end=%s" % [_checks, _failures, _reached_end])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_extension_contracts() -> void:
	var brain := Brain.new()
	brain.setup(Profile.new(), Vector2.ZERO, 123)
	var custom := CustomState.new()
	brain.register_state(100, custom)
	_check(brain.transition_to(100) and custom.enters == 1, "new animal state registers without editing state machine")
	brain.tick(0.1, Vector2.ZERO, false)
	_check(brain.desired_velocity == Vector2(3, 0), "custom state satisfies the normal tick contract")
	brain.transition_to(Brain.State.IDLE)
	_check(custom.exits == 1, "replacement state receives one exit")
	var before: int = brain.state
	_check(not brain.transition_to(999) and brain.state == before, "unregistered state cannot corrupt active behaviour")
	var registry := Registry.new()
	var visits: Array[String] = []
	registry.register_section(&"plugin", func() -> Dictionary: return {"value": 7},
		func(data: Dictionary) -> void: visits.append(str(int(data.value))))
	registry.restore(JSON.parse_string(JSON.stringify(registry.collect())))
	_check(visits == ["7"], "new save participant works through narrow callbacks")
	_check(Migrations.migrate({"version": 99}).is_empty(), "future save version rejected")
	_check(Migrations.migrate({"version": 1, "coins": 42}).version == 2, "v1 migrates explicitly without losing fields")
	var cleaned: Dictionary = Migrations.migrate({"version": 2, "inventory": {"slots": [null, {}]}, "farm": {"tilled": [null, [1, 2]], "crops": [1, {}]}, "weather": []})
	_check(cleaned.inventory.slots[0] == {} and cleaned.farm.tilled == [[1, 2]] and not cleaned.has("weather"), "malformed section containers are sanitized")


func _check_storage() -> void:
	var store := FailedInstallStore.new()
	var path: String = "user://atomic-contract.json"
	_check(store.write(path, {"version": 1, "value": 1}), "first atomic write succeeds")
	_check(store.write(path, {"version": 2, "value": 2}), "second atomic write succeeds")
	_check(int(store.read(path + ".bak").value) == 1, "backup retains the previous complete document")
	store.fail_publish = true
	_check(not store.write(path, {"version": 2, "value": 3}), "injected replacement failure is reported")
	_check(int(store.read(path).value) == 2, "failed write preserves the original primary")
	store.fail_publish = false
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ bad json")
	file.close()
	_check(store.read(path).is_empty() and not store.read(path + ".bak").is_empty(), "corrupt primary still has a readable complete backup")


func _check_transactions() -> void:
	var trade: Node = _main.get_node("Systems/Trade")
	var bag: Inventory = _main.get_node("Systems/Inventory")
	var wallet: Economy = _main.get_node("Systems/Economy")
	var gold: int = wallet.coins
	var seeds: int = bag.count_of(&"carrot_seeds")
	var observed: Array[Vector2i] = []
	var observer := func() -> void: observed.append(Vector2i(wallet.coins, bag.count_of(&"carrot_seeds")))
	bag.changed.connect(observer)
	var collected: int = bag.today_collected
	_check(trade.purchase(&"carrot_seeds", 3) == 3, "purchase works without opening a shop UI")
	_check(observed == [Vector2i(gold - 24, seeds + 3)], "inventory observer sees one complete transaction with final money")
	_check(bag.today_collected == collected, "purchases do not count as harvested goods")
	bag.changed.disconnect(observer)
	_check(trade.purchase(&"wood", 1) == 0, "items without purchase offers cannot be bought through the service")
	var coins: int = wallet.coins
	_check(trade.purchase(&"carrot_seeds", -1) == 0 and wallet.coins == coins, "invalid quantities never mutate models")
	trade.add_purchase_rule(func(item: ItemData) -> String: return "test locked" if item.id == &"carrot_seeds" else "")
	_check(trade.purchase(&"carrot_seeds", 1) == 0 and wallet.coins == coins, "additional purchase policy extends service without changing transaction code")


func _check_rain_dates() -> void:
	var clock: Node = _main.get_node("Systems/Time")
	var weather: Node = _main.get_node("Systems/Weather")
	var field: Node = _main.get_node("Farm/Tiller")
	weather.lock(&"sunny")
	field._plant(Vector2i(20, 7))
	var crop: Crop = field._crops[Vector2i(20, 7)]
	# 固定 RNG 验证真实的天气切换，避免用直接调用农田结算掩盖连接顺序问题。
	weather.unlock()
	seed(0)
	clock.sleep()
	_check(weather.is_rainy() and crop.stage == 0 and crop.stage_age == 0, "tomorrow's rain cannot grow yesterday's dry crop")
	_check(crop.watered, "new rainy day waters the crop before publishing its events")
	for sample: int in 100:
		seed(sample)
		if weather._pick() == &"sunny":
			seed(sample)
			break
	clock.sleep()
	_check(crop.stage == 1, "rain on the day being settled advances its crop")
	_check(not weather.is_rainy() and not crop.watered, "new sunny day clears the crop's previous water state")
	_check(not bool(field._soil_state[Vector2i(18, 6)]), "empty plots also dry after a rainy day")


func _check_modals() -> void:
	var player: Node = _main.get_node("Farm/World/Player")
	var modals: Node = _main.get_node("Systems/Modals")
	var bag: Control = _main.get_node("UI/InventoryPanel")
	var shop: Control = _main.get_node("UI/ShopPanel")
	var pause: Control = _main.get_node("UI/PauseMenu")
	bag.set_open(true)
	shop.set_open(true)
	_check(not bag.visible and shop.visible and player.input_locked, "modal handoff retains its input lock")
	player.set_input_locked(true)
	shop.set_open(false)
	_check(player.input_locked, "closing a panel cannot release a cutscene lock")
	player.set_input_locked(false)
	_check(not player.input_locked, "manual lock releases after last owner closes")
	var custom := NewPanel.new()
	custom.hide()
	_main.get_node("UI").add_child(custom)
	modals.register_panel(custom)
	custom.set_open(true)
	_check(player.input_locked and not pause.can_pause(), "a new modal participates without adding a name to Player or Toolbar")
	custom.set_open(false)
	custom.queue_free()
	pause.open()
	_check(paused, "pause panel owns world pause")
	bag.set_open(true)
	_check(not paused and bag.visible and not pause.visible and player.input_locked, "switching from pause to ordinary modal restores world processing")
	bag.set_open(false)
	_check(not player.input_locked and not paused, "all modal ownership clears")
	var transient := NewPanel.new()
	transient.hide()
	_main.get_node("UI").add_child(transient)
	modals.register_panel(transient)
	transient.set_open(true)
	transient.queue_free()
	await process_frame
	await process_frame
	_check(not player.input_locked and not modals.has_open_panel(), "destroying an open modal releases its ownership")


func _find_world_object(id: StringName) -> Node2D:
	for object: Node in _main.get_node("Farm/World").get_children():
		if object.has_method(&"persistence_id") and object.persistence_id() == id:
			return object
	return null


func _check_world_roundtrip() -> void:
	var save: Node = _main.get_node("Systems/Save")
	var bag: Inventory = _main.get_node("Systems/Inventory")
	var baseline: Dictionary = save.collect()
	var tree: Node2D = get_first_node_in_group(&"choppable")
	var id: StringName = tree.persistence_id()
	for hit: int in tree.hits_required:
		tree.chop(Vector2i.DOWN)
	await create_timer(0.5).timeout
	_check(tree.is_felled, "real tree falls before snapshot")
	var felled: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	var wood: int = bag.count_of(&"wood")
	for repetition: int in 3:
		save.apply(felled)
		await process_frame
		_check(bag.count_of(&"wood") == wood and _find_world_object(id).is_felled, "reloading a stump does not repeat its wood reward")
	_find_world_object(id)._clear_stump()
	await process_frame
	var cleared: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	save.apply(baseline)
	await process_frame
	_check(_find_world_object(id) != null and not _find_world_object(id).is_felled, "initial template restores a complete tree after clearing")
	save.apply(cleared)
	await process_frame
	_check(_find_world_object(id) == null, "cleared tree stays absent after snapshot restore")
	_check(save.save_game() and save.load_game(), "world snapshots survive actual atomic disk write and read")


func _check_navigation() -> void:
	var nav: Node = _main.get_node("Farm/Nav")
	var world: Node2D = _main.get_node("Farm/World")
	nav.build()
	var cell: Vector2i = nav.nearest_walkable(Vector2i(20, 16))
	_check(cell.x >= 0 and nav.is_walkable(cell), "navigation fixture starts at a free cell")
	var prop := Node2D.new()
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	collision.shape = shape
	body.add_child(collision)
	prop.add_child(body)
	prop.position = nav.cell_to_world(cell)
	world.add_child(prop)
	await process_frame
	await process_frame
	_check(not nav.is_walkable(cell), "nested collider is added to navigation")
	prop.queue_free()
	await process_frame
	await process_frame
	_check(nav.is_walkable(cell), "navigation reopens after obstacle removal")
