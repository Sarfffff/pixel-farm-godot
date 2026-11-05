extends SceneTree
## 技术拼接岸线图集。运行后用 Godot --headless --editor --import 导入，再重建地图。


const TerrainTiles := preload("res://tools/lib/terrain_tiles.gd")


func _init() -> void:
	var atlas: Image = TerrainTiles.make_shore_image()
	var path: String = TerrainTiles.SHORE_PATH
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = atlas.save_png(path)
	# 当前桥与土路由 prepare_path_bridge_art.gd 从原创原图整理；不以旧拼接桥覆写。
	print("[prepare_terrain_art] shore atlas saved: %s (%d)" % [path, error])
	quit(0 if error == OK else 1)
