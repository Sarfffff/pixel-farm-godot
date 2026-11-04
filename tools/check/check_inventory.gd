extends SceneTree
## 背包回归：初始物品、堆叠、溢出、取出、满包与面板开关（含输入锁）。
## --headless --path . --script res://tools/check/check_inventory.gd

const MAIN_SCENE := "res://scenes/main.tscn"

var _main: Node2D
var _inventory: Inventory
var _player: CharacterBody2D
var _panel: Control
var _toolbar: Control
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[inventory] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load(MAIN_SCENE).instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	# 关掉自动读档：测试固定从干净的开局状态出发，不受真实存档影响
	_main.get_node("Systems/Save").autoload_enabled = false
	await process_frame
	_inventory = _main.get_node("Systems/Inventory") as Inventory
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	_panel = _main.get_node("UI/InventoryPanel") as Control
	_toolbar = _main.get_node("UI/Toolbar") as Control

	_check(_inventory != null, "inventory node exists")
	_check(_inventory.slot_count() == 30, "30 slots including permanent tools")
	_check(_inventory.count_of(&"carrot_seeds") == 5, "starting carrot seeds")
	_check(_inventory.item_at(0)[&"id"] == &"carrot_seeds", "starting item sits in first slot")

	# 同 id 追加到已有堆叠
	_check(_inventory.add_item(&"wood", 3) == 0, "wood accepted")
	_check(_inventory.count_of(&"wood") == 3, "wood stacked")
	_check(_inventory.total_items() == 12, "total items count includes four tools")

	# 未定义的 id 全部退回，不写入背包
	_check(_inventory.add_item(&"no_such_item", 2) == 2, "unknown id rejected")
	_check(_inventory.total_items() == 12, "unknown id leaves inventory untouched")

	# 丢弃：面板 Delete 键丢 1 个，工具拒绝丢弃
	var wood_slot: int = _inventory.find_item(&"wood")
	var wood_before: int = _inventory.count_of(&"wood")
	_panel.call("_discard", wood_slot)
	_check(_inventory.count_of(&"wood") == wood_before - 1, "discard removes exactly one item")
	var tool_slot: int = _inventory.find_item(&"hoe")
	_panel.call("_discard", tool_slot)
	_check(_inventory.count_of(&"hoe") == 1, "permanent tools cannot be discarded")
	# 还原数量，后面的容量测试仍然按原来的期望值跑
	_inventory.add_item(&"wood", 1)
	_check(_inventory.count_of(&"wood") == wood_before, "discard test restores the stack")

	# 超过单格上限时自动开新格：3 + 200 = 203 -> 99 + 99 + 5
	_check(_inventory.add_item(&"wood", 200) == 0, "wood over one stack accepted")
	_check(_inventory.count_of(&"wood") == 203, "wood total after overflow into new slots")

	# 取出：数量不足时失败且不改动
	_check(not _inventory.remove_item(&"wood", 300), "remove more than held fails")
	_check(_inventory.count_of(&"wood") == 203, "failed remove leaves count unchanged")
	_check(_inventory.remove_item(&"wood", 203), "remove all wood")
	_check(_inventory.count_of(&"wood") == 0, "wood cleared")

	# 满包：先清空初始种子，24 格 × 99 后再放入应返回溢出数量
	_inventory.remove_item(&"carrot_seeds", _inventory.count_of(&"carrot_seeds"))
	_check(_inventory.total_items() == 4, "only permanent tools remain before fill test")
	_check(_inventory.add_item(&"wood", 99 * (_inventory.slot_count() - Inventory.TOOL_IDS.size())) == 0, "fill all cargo slots")
	_check(_inventory.add_item(&"stone", 1) == 1, "full bag reports overflow")
	_check(_inventory.count_of(&"stone") == 0, "overflow item not stored")

	# 面板开关：锁玩家输入并隐藏工具栏
	_panel.set_open(true)
	_check(_panel.visible, "panel opens")
	_check(_player.input_locked, "player input locked while panel open")
	_check(not _toolbar.visible, "toolbar hidden while panel open")
	await process_frame
	await process_frame
	_check_inventory_art()
	if "--capture" in OS.get_cmdline_user_args():
		_inventory.remove_item(&"wood", _inventory.count_of(&"wood"))
		var preview_items: Array[StringName] = [
			&"carrot_seeds", &"wood", &"stone", &"fiber",
			&"fertilizer", &"tomato_seeds", &"carrot", &"tomato",
		]
		for index: int in preview_items.size():
			_inventory.add_item(preview_items[index], 99 if index == 1 else 5 + index)
		_panel.set_open(true)
		await process_frame
		await RenderingServer.frame_post_draw
		var preview: Image = root.get_texture().get_image()
		preview.resize(640, 360, Image.INTERPOLATE_NEAREST)
		_check(preview.save_png("res://inventory_art_preview.png") == OK, "preview captured")
	_panel.set_open(false)
	_check(not _panel.visible, "panel closes")
	_check(not _player.input_locked, "player input restored")
	_check(_toolbar.visible, "toolbar restored")

	# 点击面板外的遮罩也能关闭（并恢复输入锁与工具栏）
	_panel.set_open(true)
	var overlay := _panel.get_node("Overlay") as ColorRect
	_check(overlay != null, "overlay exists")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	overlay.gui_input.emit(click)
	_check(not _panel.visible, "clicking outside closes the bag")
	_check(not _player.input_locked, "input unlocked after outside click")
	_check(_toolbar.visible, "toolbar restored after outside click")

	print("[inventory] %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_main.queue_free()
	await process_frame
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_inventory_art() -> void:
	var grid: GridContainer = _panel.get_node("%Grid") as GridContainer
	var frame: PanelContainer = _panel.get_node("Frame") as PanelContainer
	_check(grid.get_child_count() == 30, "30 visual slots")
	_check(grid.columns == 6, "6 visual columns")
	_check(frame.get_theme_stylebox("panel") is StyleBoxFlat, "shared paper and wood palette")
	_check(frame.size.y <= frame.get_viewport_rect().size.y, "panel fits native viewport height")
	_check(frame.get_viewport_rect().encloses(frame.get_global_rect()), "panel stays inside viewport")
	_check(frame.global_position.is_equal_approx(frame.global_position.round()), "panel aligned to whole pixels")
	_check(_panel.get_node_or_null("Overlay") is ColorRect, "full-screen overlay for click-to-close")
	var first: Panel = grid.get_child(0) as Panel
	var second: Panel = grid.get_child(1) as Panel
	var idle: StyleBox = _panel.get_theme_stylebox("idle", "InventorySlot")
	var selected: StyleBox = _panel.get_theme_stylebox("selected", "InventorySlot")
	var hover: StyleBox = _panel.get_theme_stylebox("hover", "InventorySlot")
	_check(first.get_theme_stylebox("panel") == selected, "first slot selected")
	second.mouse_entered.emit()
	_check(second.get_theme_stylebox("panel") == hover, "hover texture applied")
	first.mouse_entered.emit()
	_check(first.get_theme_stylebox("panel") == selected, "selection takes priority over hover")
	second.mouse_exited.emit()
	first.mouse_exited.emit()
	_check(second.get_theme_stylebox("panel") == idle, "hover texture clears")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	_panel._input(key)
	_check(second.get_theme_stylebox("panel") == selected, "keyboard changes highlighted slot")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	first._gui_input(click)
	_check(first.get_theme_stylebox("panel") == selected, "click changes highlighted slot")
	second.mouse_entered.emit()
	_panel.set_open(false)
	_panel.set_open(true)
	_check(second.get_theme_stylebox("panel") == idle, "reopening clears stale hover")
	for child: Node in grid.get_children():
		var slot: Panel = child as Panel
		var icon: TextureRect = slot.get_node("Icon") as TextureRect
		var count: Label = slot.get_node("Count") as Label
		_check(slot.size == Vector2(22, 22), "22px slot shared with hotbar")
		_check(icon.size == Vector2(16, 16), "16px icon preserved")
		_check(count.text == ("99" if slot.item_id == &"wood" else ""), "cargo counts shown, permanent tools have no count")
		_check(Rect2(Vector2.ZERO, slot.size).encloses(count.get_rect()), "count stays inside slot: %s" % count.get_rect())
		_check(icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "icon does not block clicks")
		_check(count.mouse_filter == Control.MOUSE_FILTER_IGNORE, "count does not block clicks")
