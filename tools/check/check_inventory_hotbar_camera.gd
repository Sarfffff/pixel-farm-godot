extends SceneTree
## 验证分类映射、快捷位引用、拖放、种子耗尽、旧档迁移和独立镜头缩放。

var _main: Node2D
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[hotbar_camera] FAIL: " + message)


func _settle() -> void:
	for frame in 4:
		await process_frame


func _mouse(position: Vector2, pressed: int = -1) -> void:
	var event: InputEventMouse
	if pressed >= 0:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
	else:
		event = InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		event.relative = Vector2(20, 20)
	event.position = position
	event.global_position = position
	root.push_input(event, true)
	await _settle()


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	_main.get_node("Systems/Time").running = false
	await _settle()
	var inventory := _main.get_node("Systems/Inventory") as Inventory
	var bag := _main.get_node("UI/InventoryPanel")
	var toolbar := _main.get_node("UI/Toolbar")
	var player := _main.get_node("Farm/World/Player")
	var tiller := _main.get_node("Farm/Tiller")
	var camera := _main.get_node("Camera")
	var original: Dictionary = inventory.to_dict()
	_check(inventory.slot_count() == 30 and inventory.hotbar.size() == 8, "thirty inventory slots and eight shortcut references")
	for id: StringName in Inventory.TOOL_IDS:
		_check(inventory.count_of(id) == 1, "permanent tool is actually in inventory: " + String(id))
		_check(not inventory.remove_item(id, 1), "permanent tools cannot be consumed")
	_check(_main.get_node("UI/ShopPanel")._sell(&"axe", 8, 1) == 0, "tool cannot be sold through shop API")
	# 满的旧版 24 格仍全部保留，另补四件工具。
	var legacy: Array = []
	for index in 24:
		legacy.append({&"id": "wood", &"count": 99})
	inventory.from_dict({&"slots": legacy})
	_check(inventory.count_of(&"wood") == 2376, "migration preserves every item in full legacy backpack")
	for id: StringName in Inventory.TOOL_IDS:
		_check(inventory.count_of(id) == 1, "migration restores missing tool: " + String(id))
	_check(inventory.hotbar == Inventory.DEFAULT_HOTBAR, "legacy save receives default shortcuts")
	inventory.from_dict(original)
	inventory.add_item(&"tomato_seeds", 7)
	inventory.add_item(&"wood", 3)
	bag.set_open(true)
	bag.set_category(&"tool")
	var tool_count: int = 0
	for slot: Panel in bag._slots:
		if slot.item_id != &"":
			tool_count += 1
			_check(inventory.definition(slot.item_id).category == &"tool", "tool filter uses actual item metadata")
	_check(tool_count == 4, "all four owned tools appear in tools category")
	bag.set_category(&"seed")
	bag._select(0)
	var seed: StringName = bag._selected_item()
	var before_bind: int = inventory.count_of(seed)
	_check(bag.bind_selected(5), "selected seed can be bound from category view")
	_check(inventory.count_of(seed) == before_bind and inventory.hotbar[5] == seed, "binding moves only the shortcut reference")
	inventory.select_hotbar(5)
	_check(player.current_tool == &"seeds" and tiller._seed_id() == seed, "held seed follows bound inventory item")
	tiller._plant(Vector2i(19, 7))
	_check(inventory.count_of(seed) == before_bind - 1, "planting consumes actual backpack stock")
	_check(toolbar._slot(5).get_node("Count").text == str(before_bind - 1), "hotbar count updates immediately after planting")
	_check(bag._hotbar_slots[5].get_node("Count").text == str(before_bind - 1), "embedded hotbar shares the same count")
	inventory.remove_item(seed, inventory.count_of(seed))
	_check(tiller._seed_id() == &"", "depleted bound seeds do not silently switch to a different seed")
	_check(toolbar._slot(5).get_node("Count").text == "0", "depleted seed shortcut displays zero")
	# 在种子分类页通过数字键真实绑定，不把过滤后的序号当实际存储序号。
	bag.set_category(&"seed")
	bag._select(0)
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.physical_keycode = KEY_3
	key.pressed = true
	bag._input(key)
	_check(inventory.hotbar[2] == &"tomato_seeds", "number key binds the filtered selection")
	var cargo_before: Array = inventory.to_dict()[&"slots"]
	var payload := {&"inventory": inventory, &"id": &"tomato_seeds", &"slot": inventory.find_item(&"tomato_seeds"), &"hotbar": -1}
	_check(toolbar._slot(7)._can_drop_data(Vector2.ZERO, payload), "hotbar accepts real backpack drag payload")
	toolbar._slot(7)._drop_data(Vector2.ZERO, payload)
	_check(inventory.hotbar[7] == &"tomato_seeds" and inventory.hotbar[2] == &"", "dragging an existing binding moves it without duplicates")
	_check(inventory.to_dict()[&"slots"] == cargo_before, "hotbar dragging never copies or removes cargo")
	payload[&"hotbar"] = 7
	toolbar._slot(0)._drop_data(Vector2.ZERO, payload)
	_check(inventory.hotbar[0] == &"tomato_seeds" and inventory.hotbar[7] == &"hoe", "dragging shortcuts swaps both ends")
	var tomato_position: int = inventory.find_item(&"tomato_seeds")
	var wood_position: int = inventory.find_item(&"wood")
	_check(inventory.swap_slots(tomato_position, wood_position), "cargo positions can be rearranged")
	_check(inventory.hotbar[0] == &"tomato_seeds" and inventory.count_of(&"tomato_seeds") == 7, "cargo movement does not break shortcuts")
	for index in Inventory.HOTBAR_SIZE:
		var slot: Panel = toolbar._slot(index)
		var label: Label = slot.get_node("Key")
		_check(label.get_parent() == slot, "number belongs to slot rather than icon")
		_check(label.position.x >= slot.size.x - 10 and label.position.y <= 1, "number is positioned at top-right")
		_check(Rect2(Vector2.ZERO, slot.size).encloses(label.get_rect()), "number stays inside slot")
		_check(label.text == str(index + 1), "all eight shortcut numbers are displayed")
	# 双击装备真实工具，并关闭背包；工具信息与快捷栏图标完全相同。
	bag.set_category(&"tool")
	for index in bag._slots.size():
		if bag._slots[index].item_id == &"axe":
			bag._equip(index)
			break
	_check(not bag.visible and player.current_tool == &"axe", "equipping from filtered bag selects correct tool and closes UI")
	var upgrades := _main.get_node("Systems/Upgrades")
	upgrades.from_dict({&"watering_level": 1})
	_check(inventory.item_name(&"watering_can") == "铜水壶", "upgraded tool name is shared")
	_check(inventory.item_icon(&"watering_can") == inventory.definition(&"watering_can").upgraded_icon, "upgraded tool icon is shared")
	var snapshot: Dictionary = inventory.to_dict()
	inventory.from_dict(original)
	inventory.from_dict(snapshot)
	_check(inventory.to_dict() == snapshot, "cargo, bindings and active shortcut roundtrip together")
	# 所有已有产物类型都能归到收获页，避免新增内容在分类中消失。
	for item: ItemData in inventory.definitions():
		if item.category in [&"crop", &"fish", &"forage", &"artisan"]:
			_check(inventory.matches_category(item.id, &"crop"), "harvest filter includes " + String(item.category))
	# 缩放只影响世界，快捷栏和状态牌大小保持不变。
	var ui_size: Vector2 = toolbar.size
	camera.set_view_zoom(1.25, true, false)
	_check(camera.get_viewport_rect().size / camera.zoom == Vector2(512, 288), "default camera shows thirty-two by eighteen tiles")
	camera.set_view_zoom(2.0, true, false)
	_check(toolbar.size == ui_size and camera.zoom == Vector2(2, 2), "zooming changes world but not HUD")
	camera.set_view_zoom(0.1, true, false)
	_check(camera.zoom.x >= camera.minimum_view_zoom(), "zoom cannot reveal outside map bounds")
	camera.set_view_zoom(99.0, true, false)
	_check(camera.zoom.x <= camera.max_zoom, "maximum zoom is clamped")
	bag.set_open(true)
	var before: float = camera._desired_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	camera._unhandled_input(wheel)
	_check(camera._desired_zoom == before, "scrolling inside backpack never changes camera")
	bag.set_open(false)
	camera.set_view_zoom(1.25, true, false)
	for edge: Vector2 in [Vector2(8, 8), Vector2(632, 472)]:
		player.global_position = edge
		camera._physics_process(1.0)
		camera.reset_smoothing()
		camera.force_update_scroll()
		var center: Vector2 = camera.get_screen_center_position()
		var extent: Vector2 = camera.get_viewport_rect().size / camera.zoom
		_check(camera.world_bounds.grow(1).encloses(Rect2(center - extent * 0.5, extent)), "camera remains within world at both corners")
	# 走 Godot 真正的 GUI 按下、移动和松开流程，不只调用 drop 回调。
	root.min_size = Vector2i.ZERO
	root.size = Vector2i(640, 360)
	bag.set_open(true)
	bag.set_category(&"seed")
	await _settle()
	var source: Control = bag._slots[0]
	var target: Control = bag._hotbar_slots[4]
	var start: Vector2 = source.get_global_rect().get_center()
	var end: Vector2 = target.get_global_rect().get_center()
	await _mouse(start, 1)
	await _mouse(start + Vector2(18, 12))
	await _mouse(end)
	await _mouse(end, 0)
	_check(inventory.hotbar[4] == &"tomato_seeds" and inventory.count_of(&"tomato_seeds") == 7, "real GUI drag binds seed without altering stock")
	bag.set_open(false)
	_main.queue_free()
	await _settle()
	print("[hotbar_camera] shared items, categories, drag/drop, migration, camera; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
