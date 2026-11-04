extends SceneTree
## 表现层回归：季节、灯光、室内、头像、状态图不改变生产与存档协议。

const Safety = preload("res://tools/lib/check_safety.gd")
const Portraits = preload("res://scripts/presentation/portrait_library.gd")
const Bounds = preload("res://scripts/presentation/visible_sprite_bounds.gd")
var _failures: int = 0
var _checks: int = 0
var _main: Node2D


func _init() -> void:
	if not Safety.require_isolated(self): return
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[presentation] FAIL: " + message)


func _settle() -> void:
	for frame: int in 5: await process_frame


func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	var save: Node = _main.get_node("Systems/Save")
	save.remove_from_group(&"save")
	var clock: Node = _main.get_node("Systems/Time")
	clock.running = false
	await _settle()
	var presentation: Node = _main.get_node("Systems/Presentation")
	_check(_main.get_node("Farm/Hills").material == presentation.foliage_material, "cliff grass shares season treatment")
	for patch: Node in get_nodes_in_group(&"forage_patch"):
		_check(patch.material == presentation.grass_material, "drawn forage grass shares season treatment")
	var snapshot: Dictionary = save.collect()
	_check(not snapshot.has("presentation"), "decorative state needs no new save section")
	_check(presentation.lights.size() >= 9, "building windows and path lanterns have lights")
	for light: PointLight2D in presentation.lights:
		_check(not light.visible, "daytime lights are off")
	clock.minutes = 21 * 60
	clock.time_changed.emit(clock.day, clock.minutes)
	_check(presentation.lights[0].visible and presentation.lights[0].energy > 0, "lights turn on at night")
	for index: int in 4:
		clock.day = 1 + index * 28
		clock.time_changed.emit(clock.day, clock.minutes)
		_check(presentation.season_index == index, "season follows the existing calendar")
		_check(int(presentation.ground_material.get_shader_parameter("season")) == index, "ground changes independently of buildings")
		_check(int(presentation.foliage_material.get_shader_parameter("season")) == index, "foliage and terrain edges share season")
		_check(int(presentation.grass_material.get_shader_parameter("season")) == index, "forage grass follows season")
	clock.day = 1
	clock.minutes = 12 * 60
	clock.time_changed.emit(clock.day, clock.minutes)
	var cottage: Sprite2D = _main.get_node("Farm/World/Cottage0") as Sprite2D
	_check(cottage.texture.resource_path.contains("presentation_v3"), "farmhouse has its own new exterior")
	var visible_rect: Rect2 = Bounds.local_rect(cottage)
	_check(visible_rect.size.x < cottage.get_rect().size.x and visible_rect.size.y < cottage.get_rect().size.y, "transparent canvas does not expand occlusion or crop exclusion")
	var shop: Sprite2D = _main.get_node("Farm/World/GeneralStore1") as Sprite2D
	var coop_art: Sprite2D = _main.get_node("Farm/World/ChickenCoop/Nest") as Sprite2D
	var shop_rect: Rect2 = shop.global_transform * Bounds.local_rect(shop)
	var coop_rect: Rect2 = coop_art.global_transform * Bounds.local_rect(coop_art)
	_check(not shop_rect.intersects(coop_rect), "shop and coop silhouettes do not overlap")
	var player: Node2D = _main.get_node("Farm/World/Player") as Node2D
	player.global_position = Vector2(472, 174)
	var world: Node = _main.get_node("Farm/World")
	_check(not world._occlusion_rect(shop).has_point(player.global_position), "shop padding cannot hide a player standing outside its roof")
	var activities: Node = _main.get_node("Systems/FarmActivities")
	activities.interact_activity(&"storage")
	_check(activities._chest.texture == activities.CHEST_OPEN_ART, "opening storage raises chest lid")
	activities.panel.close()
	_check(activities._chest.texture == activities.CHEST_ART, "closing storage restores closed chest")
	var inventory: Inventory = _main.get_node("Systems/Inventory") as Inventory
	inventory.add_item(&"tomato", 3)
	_check(activities.use_processing(), "recipe can still start")
	_check(activities._machine.texture == activities.MACHINE_WORKING_ART, "working recipe shows working station")
	clock.sleep()
	_check(activities._machine.texture == activities.MACHINE_READY_ART, "new day changes finished station art")
	_check(activities.use_processing() and inventory.count_of(&"pickled_tomato") == 1, "visual readiness preserves actual one-product reward")
	_check(activities._machine.texture == activities.MACHINE_ART, "claiming output restores idle station")
	_check(not activities.use_processing(), "idle visual does not duplicate a completed product")
	var house: Node = _main.get_node("Systems/HouseManager")
	house.enter_house(load("res://scenes/world/house_interior.tscn"))
	await _settle()
	_check(not presentation.particles.is_visible_in_tree(), "outdoor rain and snow are hidden indoors")
	var floor: TileMapLayer = house._interior.get_node("Floor") as TileMapLayer
	var source: TileSetAtlasSource = floor.tile_set.get_source(0) as TileSetAtlasSource
	_check(source.texture.resource_path.contains("presentation_v3/tiles/wood_floor"), "interior uses calm seamless floor")
	var indoor_chest: Sprite2D = house._interior.get_node("Props/WoodChest") as Sprite2D
	activities.interact_activity(&"storage")
	_check(indoor_chest.texture == activities.CHEST_OPEN_ART, "indoor warehouse entry shares open-lid feedback")
	activities.panel.close()
	house.exit_house()
	house.enter_house(load("res://scenes/world/shop_interior.tscn"))
	await _settle()
	var owner: Node = house._interior.find_child("Shopkeeper", true, false)
	_check(owner != null, "actual store owner is present")
	var people: Array[Node] = [owner, _main.get_node("Farm/World/Gardener"), _main.get_node("Farm/World/Carpenter"), _main.get_node("Farm/World/Fisherman")]
	for person: Node in people:
		var textures: Array[Texture2D] = []
		for emotion: StringName in [&"neutral", &"happy", &"concerned"]:
			var texture: Texture2D = Portraits.for_owner(person, emotion)
			_check(texture != null and texture.get_size() == Vector2(48, 48), "matching villager has each expression at native pixel size")
			textures.append(texture)
		_check(textures[0] != textures[1] and textures[1] != textures[2], "expressions use distinct images")
	house.exit_house()
	var dialogue: Node = _main.get_node("UI/DialoguePanel")
	var gardener: Node = people[1]
	gardener.interact(Vector2i.ZERO)
	_check(dialogue._portrait.visible and dialogue._portrait.texture == Portraits.for_owner(gardener, &"neutral"), "dialogue shows actual speaker identity")
	dialogue._set_portrait(&"happy")
	_check(dialogue.portrait_emotion == &"happy", "dialogue expression can change without closing or rewarding")
	dialogue.close()
	for panel_name: String in ["HUD", "InventoryPanel", "ShopPanel", "DialoguePanel", "SettingsPanel", "PauseMenu", "HelpPanel"]:
		var panel: Control = _main.get_node("UI/" + panel_name) as Control
		_check(panel.theme.resource_path.ends_with("farm_hud.tres"), "shared theme: " + panel_name)
	var panel: Node = _main.get_node("UI/ShopPanel")
	_check(panel._idle_style is StyleBoxFlat and panel._active_style is StyleBoxFlat, "shop selection uses same pixel borders as inventory")
	save.apply(snapshot)
	await _settle()
	_check(presentation.season_index == 0 and activities.processing_ready_day == 0, "save restore recomputes decorative state without changing data")
	_check(save.collect().keys() == snapshot.keys(), "presentation adds no persistent gameplay fields")
	print("[presentation] %d checks, %d failures; reached end" % [_checks, _failures])
	_main.queue_free()
	root.get_node("AudioManager").stop_music(0.0)
	for audio: Node in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer: audio.stream = null
	await create_timer(0.1).timeout
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
