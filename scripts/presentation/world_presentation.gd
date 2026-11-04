extends Node
## 由 GameSession 装配；只消费日期、天气和房屋状态，不写入玩法与存档。

const Ground = preload("res://scripts/presentation/ground_decor.gd")
const WeatherParticles = preload("res://scripts/presentation/weather_particles.gd")
const Shadows = preload("res://scripts/presentation/contact_shadows.gd")
const GROUND_SHADER: Shader = preload("res://assets/shaders/season_ground.gdshader")
const LEAF_SHADER: Shader = preload("res://assets/shaders/season_foliage.gdshader")
const LAMP: Texture2D = preload("res://assets/packs/content_v1/terrain/town/spring/lamp_post.png")
const SEASONS: Array[Texture2D] = [
	preload("res://assets/packs/presentation_v3/tiles/spring.png"), preload("res://assets/packs/presentation_v3/tiles/summer.png"),
	preload("res://assets/packs/presentation_v3/tiles/autumn.png"), preload("res://assets/packs/presentation_v3/tiles/winter.png")]

var ground_material: ShaderMaterial
var foliage_material: ShaderMaterial
var grass_material: ShaderMaterial
var particles: Node2D
var lights: Array[PointLight2D] = []
var season_index: int = 0
var _clock: Node
var _farm: Node2D
var _house: Node
var _decor: Node2D
var _glow: GradientTexture2D


func configure(farm: Node2D, clock: Node, weather: Node, house: Node) -> void:
	_farm = farm
	_clock = clock
	_house = house
	ground_material = ShaderMaterial.new()
	ground_material.shader = GROUND_SHADER
	(farm.get_node("Ground") as TileMapLayer).material = ground_material
	foliage_material = ShaderMaterial.new()
	foliage_material.shader = LEAF_SHADER
	grass_material = ShaderMaterial.new()
	grass_material.shader = LEAF_SHADER
	grass_material.set_shader_parameter("use_vertex_color", true)
	for name: String in ["Overlay", "Detail", "SoilFringe", "Hills"]:
		var layer: CanvasItem = farm.get_node_or_null(name) as CanvasItem
		if layer != null: layer.material = foliage_material
	_decor = Ground.new()
	_decor.z_index = 2
	farm.add_child(_decor)
	_decor.configure(farm.get_node("Paths"))
	var shadows: Node2D = Shadows.new()
	shadows.world = farm.get_node("World")
	shadows.z_index = 9
	farm.add_child(shadows)
	particles = WeatherParticles.new()
	particles.z_index = 25
	particles.configure(clock, weather, farm.get_node("Water"))
	farm.add_child(particles)
	_make_glow()
	for p: Vector2 in [Vector2(454, 119), Vector2(490, 119), Vector2(465, 229), Vector2(511, 229), Vector2(545, 55), Vector2(589, 55)]:
		lights.append(_light(farm.get_node("World"), p, 0.5))
	for p: Vector2 in [Vector2(264, 280), Vector2(440, 298), Vector2(536, 112)]:
		var lamp: Sprite2D = Sprite2D.new()
		lamp.texture = LAMP
		lamp.position = p
		lamp.offset = Vector2(0, -16)
		farm.get_node("World").add_child(lamp)
		lights.append(_light(lamp, Vector2(0, -22), 0.7))
	_scan(farm)
	get_tree().node_added.connect(_added)
	clock.time_changed.connect(_time_changed)
	_time_changed(clock.day, clock.minutes)


func _make_glow() -> void:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1, 0.5)


func _light(parent: Node, position: Vector2, energy: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.position = position
	light.texture = _glow
	light.texture_scale = 0.7
	light.color = Color("efd3a0")
	light.energy = energy
	light.set_meta(&"base_energy", energy)
	parent.add_child(light)
	return light


func _scan(node: Node) -> void:
	_apply(node)
	for child: Node in node.get_children(): _scan(child)


func _added(node: Node) -> void:
	if node is CanvasItem:
		_apply_deferred.call_deferred(weakref(node))


func _apply_deferred(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if node != null and node.is_inside_tree() and is_instance_valid(_farm):
		_apply(node)


func _apply(node: Node) -> void:
	if not is_instance_valid(node) or not node is CanvasItem: return
	if node is Node2D and node.get_script() != null and node.get_script().resource_path.ends_with("/interior_room.gd") and not node.has_meta(&"contact_shadows"):
		var props: Node2D = node.get_node_or_null("Props") as Node2D
		if props != null:
			node.set_meta(&"contact_shadows", true)
			var shadows: Node2D = Shadows.new()
			shadows.world = props
			shadows.z_index = -1
			props.add_child(shadows)
	if node is Sprite2D and node.texture != null:
		var path: String = node.texture.resource_path
		if path.ends_with("/floor_lamp.png") or path.ends_with("/brick_fireplace.png"):
			if not node.has_meta(&"warm_light"):
				node.set_meta(&"warm_light", true)
				_light(node, Vector2(0, -18), 0.28)
		if _farm.is_ancestor_of(node) and (path.contains("/trees/") or path.contains("basic_grass_biom_things") or path.contains("/crops/")):
			node.material = foliage_material
	elif node.is_in_group(&"berry_bush") and _farm.is_ancestor_of(node):
		node.material = foliage_material
	elif node.is_in_group(&"forage_patch") and _farm.is_ancestor_of(node):
		node.material = grass_material


func _time_changed(_day: int, minutes: int) -> void:
	season_index = _clock.season_index()
	ground_material.set_shader_parameter("season_tile", SEASONS[season_index])
	ground_material.set_shader_parameter("season", season_index)
	foliage_material.set_shader_parameter("season", season_index)
	grass_material.set_shader_parameter("season", season_index)
	_decor.season = season_index
	_decor.queue_redraw()
	var brightness: float = clampf(float(minutes - 17 * 60) / (4 * 60), 0.0, 1.0)
	for light: PointLight2D in lights:
		light.energy = float(light.get_meta(&"base_energy")) * brightness
		light.visible = brightness > 0.01
