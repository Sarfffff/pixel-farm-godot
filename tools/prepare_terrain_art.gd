extends SceneTree
## 技术拼接岸线图集。运行后用 Godot --headless --editor --import 导入，再重建地图。


func _init() -> void:
	var atlas: Image = preload("res://tools/terrain_tiles.gd").make_shore_image()
	var path: String = preload("res://tools/terrain_tiles.gd").SHORE_PATH
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = atlas.save_png(path)
	if error == OK:
		error = preload("res://tools/terrain_tiles.gd").make_bridge_image().save_png(preload("res://tools/terrain_tiles.gd").BRIDGE_PATH)
	print("[prepare_terrain_art] shore atlas saved: %s (%d)" % [path, error])
	quit(0 if error == OK else 1)
