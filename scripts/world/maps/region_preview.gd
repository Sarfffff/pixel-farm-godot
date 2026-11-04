extends Node2D
## 六类区域的原生场景预览。资源只有美术、稳定ID和碰撞，不发放计划掉落物。

const Layout = preload("res://scripts/world/maps/region_layout.gd")
const PlayerScript = preload("res://scripts/world/maps/region_preview_player.gd")
const TILESET_PATH: String = "res://assets/tilesets/world_regions_v1.tres"
@export var profile: Resource
var _inspector: Label
var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	if not has_node("Ground"): build_map()
	for child: Node in $World.get_children():
		if child is Sprite2D and child.has_meta(&"resource_definition"): _sprites.append(child as Sprite2D)
	_build_ui()
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null: audio.call(&"play_music", &"farm_day")


func build_map() -> void:
	var data: Dictionary = Layout.create(profile)
	set_meta(&"region_id", String(profile.id))
	set_meta(&"resource_count", data.resources.size())
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = load(TILESET_PATH)
	add_child(ground)
	for cell: Vector2i in data.ground:
		var tile: int = int(data.ground[cell])
		var edge: Vector2i = Layout.transition(data.ground, cell)
		ground.set_cell(cell, 0 if edge.x < 0 else 1, Vector2i(tile % 4, tile / 4) if edge.x < 0 else Vector2i(edge.x % 64, edge.x / 64))
	var water := StaticBody2D.new()
	water.name = "WaterAndBounds"
	add_child(water)
	for y: int in profile.map_size.y:
		var start: int = -1
		for x: int in profile.map_size.x + 1:
			var wet: bool = x < profile.map_size.x and Layout.is_water(int(data.ground[Vector2i(x, y)]))
			if wet and start < 0: start = x
			elif not wet and start >= 0:
				_add_rect(water, Rect2(start * 16, y * 16, (x - start) * 16, 16))
				start = -1
	var extent: Vector2 = Vector2(profile.map_size * 16)
	for rect: Rect2 in [Rect2(-8, -8, extent.x + 16, 8), Rect2(-8, extent.y, extent.x + 16, 8), Rect2(-8, 0, 8, extent.y), Rect2(extent.x, 0, 8, extent.y)]: _add_rect(water, rect)
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.z_index = 2
	add_child(world)
	for entry: Dictionary in data.resources:
		var definition: Resource = entry.definition
		var sprite := Sprite2D.new()
		sprite.name = entry.id
		sprite.texture = definition.texture
		sprite.scale = Vector2.ONE * definition.visual_scale
		sprite.position = Vector2(entry.cell * 16) + Vector2(definition.footprint.x * 8, definition.footprint.y * 16)
		sprite.offset = Vector2(0, -definition.texture.get_height() / 2)
		sprite.set_meta(&"resource_definition", definition)
		sprite.set_meta(&"stable_id", entry.id)
		sprite.set_meta(&"cell", entry.cell)
		world.add_child(sprite)
		if definition.blocks_movement:
			var body := StaticBody2D.new()
			body.name = "FootCollision"
			sprite.add_child(body)
			_add_rect(body, Rect2(-definition.footprint.x * 7, -8, definition.footprint.x * 14, 7))
	var player := CharacterBody2D.new()
	player.name = "PreviewPlayer"
	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	player.set_script(PlayerScript)
	player.position = Vector2(data.spawn * 16) + Vector2(8, 8)
	world.add_child(player)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = load("res://scenes/player/player_frames.tres")
	sprite.position = Vector2(0, -8)
	sprite.animation = &"idle_down"
	player.add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	shape.position = Vector2(0, -4)
	player.add_child(shape)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2.ONE * 0.55
	camera.position = extent / 2.0 - Vector2(72, 7) / 0.55
	add_child(camera)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _add_rect(body: StaticBody2D, rect: Rect2) -> void:
	var node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	node.shape = shape
	node.position = rect.get_center()
	body.add_child(node)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewUI"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(5, 5)
	panel.size = Vector2(146, 350)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f0dfb5")
	style.border_color = Color("806858")
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_color_override("font_color", Color("514c40"))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_label(box, "地图与资源预览", 10)
	_label(box, "%s\n%s" % [profile.display_name, profile.purpose], 7)
	for index: int in Layout.REGION_IDS.size():
		var other: Resource = load("res://data/maps/" + Layout.REGION_IDS[index] + ".tres")
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, other.display_name]
		button.custom_minimum_size.y = 19
		button.add_theme_font_size_override("font_size", 7)
		button.disabled = other.id == profile.id
		button.pressed.connect(_switch.bind(index))
		box.add_child(button)
	_label(box, "WASD / 方向键走动\n1–6 切换区域\n鼠标悬停查看资源", 7)
	_inspector = _label(box, "树木和岩石有脚底碰撞\n采集与掉落尚未接入\n本预览不读取玩家存档", 7)
	_label(box, "48×32格 · 16px地表\n固定种子 · 主路保留", 6)
	var heading := Label.new()
	heading.text = "%s  ·  地表与资源分布样板" % profile.display_name
	heading.position = Vector2(174, 12)
	heading.add_theme_font_size_override("font_size", 10)
	heading.add_theme_color_override("font_color", Color("eadbb6"))
	layer.add_child(heading)


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 132
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("514c40"))
	parent.add_child(label)
	return label


func _process(_delta: float) -> void:
	if _inspector == null: return
	var mouse: Vector2 = get_global_mouse_position()
	for sprite: Sprite2D in _sprites:
		if sprite.get_rect().has_point(sprite.to_local(mouse)):
			var definition: Resource = sprite.get_meta(&"resource_definition")
			_inspector.text = "%s\n规划交互：%s\n%s" % [definition.display_name, definition.tool_hint, definition.integration_status]
			return


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_6:
		_switch(event.keycode - KEY_1)


func _switch(index: int) -> void:
	get_tree().change_scene_to_file("res://scenes/maps/" + Layout.REGION_IDS[index] + "_preview.tscn")
