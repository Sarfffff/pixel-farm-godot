extends SceneTree
## 只更新地形贴图引用和Paths格子，不重建道具、稳定ID或覆盖其他场景开发。

const Landscape := preload("res://tools/lib/farm_landscape.gd")
const Terrain := preload("res://tools/lib/terrain_tiles.gd")
const FARM: String = "res://scenes/world/farm.tscn"
const TILESET: String = "res://assets/tilesets/farm_terrain.tres"


func _init() -> void:
	if not FileAccess.file_exists(Terrain.PATH_PATH) or not FileAccess.file_exists(Terrain.BRIDGE_PATH):
		push_error("Run prepare_path_bridge_art.gd and import textures first")
		quit(1)
		return
	var scene: String = FileAccess.get_file_as_string(FARM)
	var paths := TileMapLayer.new()
	paths.tile_set = load(TILESET) as TileSet
	Landscape.paint_paths(paths, Landscape.water_cells())
	var data: PackedByteArray = paths.get("tile_map_data")
	var marker: String = "[node name=\"Paths\""
	var start: int = scene.find(marker)
	var end: int = scene.find("\n[node", start + 1)
	if start < 0 or end < 0:
		paths.free()
		push_error("Paths section is missing; no files changed")
		quit(1)
		return
	var block: String = scene.substr(start, end - start)
	var updated: String = block
	for line: String in block.split("\n"):
		if line.begins_with("tile_map_data = "):
			updated = block.replace(line, "tile_map_data = PackedByteArray(\"%s\")" % Marshalls.raw_to_base64(data))
	if updated == block:
		print("[refresh_farm_paths] path cells already current")
	scene = scene.substr(0, start) + updated + scene.substr(end)
	var tileset: String = FileAccess.get_file_as_string(TILESET)
	var error: Error = _write_if_changed(FARM, _texture_paths(scene))
	if error == OK:
		error = _write_if_changed(TILESET, _texture_paths(tileset))
	print("[refresh_farm_paths] %d road cells; error=%d" % [paths.get_used_cells().size(), error])
	paths.free()
	quit(0 if error == OK else 1)


func _texture_paths(text: String) -> String:
	var uid := RegEx.new()
	uid.compile(" uid=\"uid://[^\"]+\"")
	var lines: PackedStringArray = text.split("\n")
	var replacements: Dictionary[String, String] = {
		"res://assets/textures/base/objects/paths.png": Terrain.PATH_PATH,
		"res://assets/textures/terrain/river_bridge_atlas.png": Terrain.BRIDGE_PATH,
	}
	for index: int in lines.size():
		if not lines[index].begins_with("[ext_resource"):
			continue
		for old: String in replacements:
			if lines[index].contains('path="' + old + '"'):
				lines[index] = uid.sub(lines[index], "").replace(old, replacements[old])
	return "\n".join(lines)


func _write_if_changed(path: String, text: String) -> Error:
	if FileAccess.get_file_as_string(path) == text:
		return OK
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return file.get_error()
