extends SceneTree
## 验收真实成品、来源约束、尺寸、透明度、图集区域及完整清单覆盖。
## -- --allow-partial 可用于生成过程中的分批检查；默认必须全量到齐。

const ROOT: String = "res://assets/packs/content_v1/"
var _failures: int = 0


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "generation_plan.json"))
	if catalog.is_empty() or plan.is_empty():
		_check(false, "catalog or generation plan missing")
		preload("res://tools/lib/check_lifecycle.gd").finish(self, 1)
		return
	var expected: int = 0
	for job: Dictionary in plan["jobs"]:
		expected += job["cells"].size()
		if str(job["category"]) == "crops" and FileAccess.file_exists(str(job["source"])):
			var source: Image = Image.load_from_file(ProjectSettings.globalize_path(str(job["source"])))
			# 白底/棋盘底有时被画进 Alpha；正式透明作物图应在画布四角留空。
			for corner: Vector2i in [Vector2i.ZERO, Vector2i(source.get_width() - 1, 0), Vector2i(0, source.get_height() - 1), source.get_size() - Vector2i.ONE]:
				_check(source.get_pixelv(corner).a < 0.5, "crop source background truly transparent: " + str(job["id"]))
	if "--allow-partial" not in OS.get_cmdline_user_args():
		_check(catalog["missing_sources"].is_empty(), "all generated sources present")
		_check(int(catalog["item_count"]) == expected, "all planned sprites prepared")
	var ids: Dictionary[String, bool] = {}
	var atlas_cache: Dictionary[String, Image] = {}
	for item: Dictionary in catalog["items"]:
		var id: String = str(item["id"])
		_check(not ids.has(id), "unique ID: " + id)
		ids[id] = true
		var path: String = str(item["path"])
		_check(path.begins_with(ROOT) and ".." not in path, "output inside categorized library")
		_check(str(item["source"]).begins_with("res://art/sources/content_v1/"), "independent generated source")
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null:
			_check(false, "image readable: " + id)
			continue
		_check(image.get_size() == Vector2i(int(item["size"][0]), int(item["size"][1])), "native size: " + id)
		_check(image.get_used_rect().size != Vector2i.ZERO, "nonempty: " + id)
		var mode: String = str(item["mode"])
		if mode != "light":
			for y: int in image.get_height():
				for x: int in image.get_width():
					var alpha: float = image.get_pixel(x, y).a
					if alpha != 0.0 and alpha != 1.0:
						_check(false, "hard-edge alpha: " + id)
						break
		var atlas_path: String = str(item["atlas"])
		if not atlas_cache.has(atlas_path):
			atlas_cache[atlas_path] = Image.load_from_file(ProjectSettings.globalize_path(atlas_path))
		var atlas: Image = atlas_cache[atlas_path]
		if atlas == null:
			_check(false, "atlas readable: " + atlas_path)
			continue
		var region: Array = item["atlas_region"]
		var rect: Rect2i = Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3]))
		_check(Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(rect), "atlas region: " + id)
		_check(atlas.get_region(rect).get_data() == image.get_data(), "atlas pixels match standalone: " + id)
	_verify_resources()
	print("[check_content_art] %s: %d sprites / %d planned, %d errors" % ["PASS" if _failures == 0 else "FAIL", ids.size(), expected, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _verify_resources() -> void:
	var theme: Theme = load(ROOT + "ui/fonts/font_roles.tres") as Theme
	_check(theme != null and theme.default_font != null, "runtime font theme loads")
	if not DirAccess.dir_exists_absolute(ROOT + "animations"):
		return
	var pending: Array[String] = [ROOT + "animations"]
	var resources: int = 0
	while not pending.is_empty():
		var directory: String = pending.pop_back()
		for child: String in DirAccess.get_directories_at(directory):
			pending.append(directory.path_join(child))
		for file: String in DirAccess.get_files_at(directory):
			if not file.ends_with(".tres"):
				continue
			var frames: SpriteFrames = load(directory.path_join(file)) as SpriteFrames
			_check(frames != null, "SpriteFrames loads: " + file)
			if frames == null:
				continue
			resources += 1
			for animation: StringName in frames.get_animation_names():
				_check(frames.get_frame_count(animation) > 0, "animation is not empty: " + file)
				for index: int in frames.get_frame_count(animation):
					_check(frames.get_frame_texture(animation, index) != null, "animation texture loads: " + file)
	print("[check_content_art] loaded %d SpriteFrames resources" % resources)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[check_content_art] FAIL: " + message)
