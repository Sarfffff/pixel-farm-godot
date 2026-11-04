extends SceneTree
## 将已生成图集整理成 Resource 配置、原生 TileSet 和六张可运行预览场景。

const Catalog = preload("res://tools/lib/world_region_catalog.gd")
const RegionData = preload("res://scripts/data/world_region_data.gd")
const ResourceData = preload("res://scripts/data/ground_resource_data.gd")
const Preview = preload("res://scripts/world/maps/region_preview.gd")
const ART: String = "res://assets/packs/world_regions_v1/"
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for folder: String in ["res://data/ground_resources", "res://data/maps", "res://scenes/maps"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(16, 16)
	var base := TileSetAtlasSource.new()
	base.texture = load(ART + "terrain_atlas.png")
	base.texture_region_size = Vector2i(16, 16)
	for y: int in 4:
		for x: int in 4: base.create_tile(Vector2i(x, y))
	tileset.add_source(base, 0)
	var transitions := TileSetAtlasSource.new()
	transitions.texture = load(ART + "transition_atlas.png")
	transitions.texture_region_size = Vector2i(16, 16)
	for y: int in 64:
		for x: int in 64: transitions.create_tile(Vector2i(x, y))
	tileset.add_source(transitions, 1)
	_save(tileset, "res://assets/tilesets/world_regions_v1.tres")
	for index: int in Catalog.RESOURCES.size():
		var row: Array = Catalog.RESOURCES[index]
		var definition: Resource = ResourceData.new()
		definition.id = StringName(row[0])
		definition.display_name = row[1]
		definition.texture = load(ART + "resources/" + String(row[0]) + ".png")
		definition.blocks_movement = row[2]
		definition.tool_hint = row[3]
		definition.planned_drop = StringName(row[4])
		definition.footprint = row[5]
		definition.visual_scale = 0.75 if index >= 24 else 1.0
		for region: Dictionary in Catalog.PROFILES:
			if region.weights.has(String(row[0])): definition.region_tags.append(StringName(region.id))
		_save(definition, "res://data/ground_resources/" + String(row[0]) + ".tres")
	# 先保存全部配置，运行时的区域选择器才能互相加载。
	for index: int in Catalog.PROFILES.size():
		var row: Dictionary = Catalog.PROFILES[index]
		var profile: Resource = RegionData.new()
		profile.id = StringName(row.id)
		profile.display_name = row.name
		profile.purpose = row.purpose
		profile.layout = StringName(row.id)
		profile.seed_value = 20261104 + index * 101
		profile.resource_count = row.count
		profile.resource_weights = row.weights
		_save(profile, "res://data/maps/" + String(row.id) + ".tres")
	for row: Dictionary in Catalog.PROFILES:
		var scene: Node2D = Preview.new()
		scene.name = String(row.id).capitalize().replace(" ", "") + "Preview"
		scene.profile = load("res://data/maps/" + String(row.id) + ".tres")
		scene.build_map()
		_own(scene, scene)
		var packed := PackedScene.new()
		if packed.pack(scene) != OK: _failures += 1
		_save(packed, "res://scenes/maps/" + String(row.id) + "_preview.tscn")
		print("[regions] %s: %d ground cells, %d resources" % [row.id, scene.get_node("Ground").get_used_cells().size(), scene.get_meta(&"resource_count")])
		scene.free()
	print("[regions] 6 profiles, 28 definitions, 6 native scenes; %d errors" % _failures)
	quit(0 if _failures == 0 else 1)


func _own(parent: Node, scene: Node) -> void:
	for child: Node in parent.get_children():
		child.owner = scene
		_own(child, scene)


func _save(resource: Resource, path: String) -> void:
	if ResourceSaver.save(resource, path) != OK:
		_failures += 1
		push_error("[regions] failed to save " + path)
