extends SceneTree
## 真实渲染验收页；只操作内存局面，自动读档关闭，不写玩家存档。

var main: Node2D
var player: Node2D
var camera: Node
var clock: Node
var weather: Node

func _init() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame: int in 8:
		await process_frame

func shot(label: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/presentation-preview/" + label + ".png")
	print("[presentation-preview] " + label)

func focus(point: Vector2, zoom_value: float) -> void:
	player.global_position = point
	camera.set_view_zoom(zoom_value, true, false)
	camera._physics_process(1.0)
	camera.reset_smoothing()
	camera.force_update_scroll()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/presentation-preview"))
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	main = load("res://scenes/main.tscn").instantiate() as Node2D
	main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(main)
	current_scene = main
	main.get_node("Systems/Save").remove_from_group(&"save")
	player = main.get_node("Farm/World/Player")
	camera = main.get_node("Camera")
	clock = main.get_node("Systems/Time")
	weather = main.get_node("Systems/Weather")
	clock.running = false
	weather.lock(&"sunny")
	await settle()
	focus(Vector2(472, 174), 1.25)
	await shot("01-farm")
	focus(Vector2(320, 240), 1.0)
	await shot("02-overview")
	clock.minutes = 21 * 60
	clock.time_changed.emit(clock.day, clock.minutes)
	await shot("03-night")
	clock.minutes = 12 * 60
	clock.day = 29
	clock.time_changed.emit(clock.day, clock.minutes)
	await shot("04-summer")
	clock.day = 57
	clock.time_changed.emit(clock.day, clock.minutes)
	await shot("04-autumn")
	clock.day = 85
	clock.time_changed.emit(clock.day, clock.minutes)
	await shot("04-winter")
	weather.lock(&"rainy")
	await shot("04-winter-snow")
	clock.day = 1
	weather.lock(&"rainy")
	clock.time_changed.emit(clock.day, clock.minutes)
	await shot("05-rain")
	weather.lock(&"sunny")
	clock.time_changed.emit(clock.day, clock.minutes)
	var house: Node = main.get_node("Systems/HouseManager")
	house.enter_house(load("res://scenes/world/house_interior.tscn"))
	await shot("06-home")
	focus(house._interior.global_position + Vector2(216, 112), 1.5)
	await shot("06-home-upper")
	house.exit_house()
	house.enter_house(load("res://scenes/world/shop_interior.tscn"))
	await shot("07-shop")
	main.get_node("UI/ShopPanel").set_open(true)
	await shot("08-shop-ui")
	main.get_node("UI/ShopPanel").set_open(false)
	main.get_node("UI/SettingsPanel").set_open(true)
	await shot("12-settings")
	main.get_node("UI/SettingsPanel").set_open(false)
	house.exit_house()
	focus(Vector2(312, 248), 1.8)
	main.get_node("Farm/World/Gardener").interact(Vector2i.ZERO)
	await shot("09-dialogue")
	main.get_node("UI/DialoguePanel").close()
	main.get_node("UI/InventoryPanel").set_open(true)
	await shot("10-inventory")
	main.get_node("UI/InventoryPanel").set_open(false)
	main.get_node("Systems/FarmActivities").panel.open(&"storage")
	await shot("11-storage")
	main.get_node("Systems/FarmActivities").panel.close()
	var activities: Node = main.get_node("Systems/FarmActivities")
	focus(activities.settings.machine_position + Vector2(-24, 8), 2.0)
	activities.processing_ready_day = clock.day + 1
	activities._refresh_world()
	await shot("13-processing")
	activities.processing_ready_day = clock.day
	activities._refresh_world()
	await shot("14-product-ready")
	main.get_node("Systems/Inventory").add_item(&"bamboo_rod", 1)
	focus(activities.settings.fishing_position + Vector2(0, -5), 1.8)
	activities.interact_activity(&"fishing")
	activities.start_fishing()
	await create_timer(0.5).timeout
	activities.tick_fishing(5.0)
	await shot("15-fishing")
	activities.panel.close()
	main.queue_free()
	await process_frame
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate() as Control
	menu.get_node("Save").autoload_enabled = false
	root.add_child(menu)
	current_scene = menu
	await shot("16-main-menu")
	menu.queue_free()
	root.get_node("AudioManager").stop_music(0.0)
	for audio: Node in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer: audio.stream = null
	await create_timer(0.1).timeout
	quit()
