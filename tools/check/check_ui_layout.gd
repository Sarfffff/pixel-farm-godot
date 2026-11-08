extends SceneTree
## 不同比例的 HUD/模态窗口布局检查。

var _failures: int = 0
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[ui_layout] FAIL: " + message)


func _settle() -> void:
	for frame in 4:
		await process_frame


func _fits(control: Control, message: String) -> void:
	var rect: Rect2 = control.get_global_rect()
	var view: Rect2 = control.get_viewport_rect().grow(0.5)
	_check(view.encloses(rect), "%s (%s in %s)" % [message, rect, view])


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	_main.get_node("Systems/Time").running = false
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(800, 600)]:
		root.size = resolution
		await _settle()
		var hud := _main.get_node("UI/HUD")
		var toolbar := _main.get_node("UI/Toolbar")
		var tutorial := _main.get_node("Systems/Tutorial")
		for goal_step: int in [6, 7, 8]:
			tutorial.from_dict({"step": goal_step})
			await _settle()
			_fits(hud.get_node("Journal"), "extended goal %d fits at %s" % [goal_step, resolution])
			_check(not hud.get_node("Journal").get_global_rect().intersects(hud.get_node("TimePanel").get_global_rect()), "extended goal does not overlap clock")
		tutorial.from_dict({})
		await _settle()
		for path: String in ["TimePanel", "StaminaPanel", "Journal"]:
			_fits(hud.get_node(path), "%s fits at %s" % [path, resolution])
		_check(not hud.get_node("Journal").get_global_rect().intersects(hud.get_node("TimePanel").get_global_rect()), "journal and status do not overlap")
		_fits(toolbar, "toolbar fits at %s" % resolution)
		var width: float = toolbar.get_viewport_rect().size.x
		_check(absf(toolbar.get_global_rect().get_center().x - width / 2.0) < 0.5, "toolbar stays horizontally centered")
		var tip_click_count: int = 0
		for slot_index: int in [2, 0, 7, 2]:
			tip_click_count += 1
			toolbar._on_slot_selected(slot_index)
			await _settle()
			_fits(toolbar._tip_panel, "item tip fits at %s" % resolution)
			_check(toolbar._tip_panel.size.y < 48.0, "item tip remains compact on first/repeated clicks")
			_check(toolbar._tip_panel.get_global_rect().end.y <= toolbar.get_global_rect().position.y, "item tip stays above toolbar")
			if tip_click_count == 1:
				print("[ui_layout] first-click tip at %s: %s" % [resolution, toolbar._tip_panel.get_global_rect()])
			if tip_click_count == 1 and resolution == Vector2i(1280, 720) and "--preview" in OS.get_cmdline_user_args():
				var capture: String = "user://ui_layout_previews/toolbar_tip.png"
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture.get_base_dir()))
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(capture) == OK, "toolbar tip preview saved")
				print("[ui_layout] capture: " + ProjectSettings.globalize_path(capture))
		toolbar.set_ui_visible(true)
		var full_height: float = hud.get_node("Journal").size.y
		hud._toggle_journal()
		await _settle()
		_check(hud.get_node("Journal").size.y < full_height, "collapsed journal actually shrinks")
		hud._toggle_journal()
		for panel_name: String in ["InventoryPanel", "ShopPanel", "HelpPanel", "OrderPanel", "CommunityPanel"]:
			var panel := _main.get_node("UI/" + panel_name)
			panel.set_open(true)
			await _settle()
			_fits(panel.get_node("Frame"), "%s fits at %s" % [panel_name, resolution])
			_check(not hud.get_node("Journal").visible, "journal hides behind modal panels")
			_check(not toolbar._hint_panel.visible, "context hint hides behind modal panels")
			panel.set_open(false)
			await _settle()
	_check(_main.get_node("UI/HUD/Journal").visible, "journal returns after closing panels")
	var shop := _main.get_node("UI/ShopPanel")
	var bag := _main.get_node("UI/InventoryPanel")
	shop.set_open(true)
	bag.set_open(true)
	await _settle()
	_check(not _main.get_node("UI/Toolbar").visible and not _main.get_node("UI/HUD/Journal").visible, "switching from shop to bag keeps HUD controls hidden")
	_check(_main.get_node("Farm/World/Player").input_locked, "modal transfer retains player lock")
	bag.set_open(false)
	_main.queue_free()
	await _settle()
	print("[ui_layout] HUD, journal, modal panels, three resolutions; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
