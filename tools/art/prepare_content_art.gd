extends SceneTree
## 独立全品类图集整理。只读取 generated/sources/content_v1，不读取外部资源包。
## 支持增量处理；-- --require-all 验收完整批次；-- --resources-only 生成 SpriteFrames。

const Utils := preload("res://tools/lib/content_art_utils.gd")
const ROOT: String = "res://assets/generated/content_v1/"
const SOURCE_ROOT: String = "res://assets/generated/sources/content_v1/"
const PLAN: String = ROOT + "generation_plan.json"
var _errors: int = 0
var _items: Array[Dictionary] = []
var _sheets: Array[Dictionary] = []
var _missing: Array[String] = []
var _pipeline_hash: String = ""


func _init() -> void:
	_pipeline_hash = FileAccess.get_md5("res://tools/lib/content_art_utils.gd") + FileAccess.get_md5("res://tools/art/prepare_content_art.gd")
	if "--resources-only" in OS.get_cmdline_user_args():
		_build_resources()
		quit(0 if _errors == 0 else 1)
		return
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	if plan.is_empty():
		_fail("Missing generation plan")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ROOT + "metadata")
	for job: Dictionary in plan["jobs"]:
		var path: String = str(job["source"])
		if not path.begins_with(SOURCE_ROOT) or ".." in path:
			_fail("Source outside independent generated sources")
			continue
		if not FileAccess.file_exists(path):
			_missing.append(str(job["id"]))
			continue
		_prepare(job)
	_write_json(ROOT + "catalog.json", {
		"version": 1, "source_document": plan["source_document"], "policy": plan["policy"],
		"generator": "built-in image_gen; tools/art/prepare_content_art.gd",
		"palette": "48 shared muted colors", "filter": "nearest", "tile_size": [16, 16],
		"alpha": "binary except translucent lighting masks", "planned_sheet_count": plan["jobs"].size(),
		"completed_sheet_count": _sheets.size(), "missing_sources": _missing,
		"item_count": _items.size(), "sheets": _sheets, "items": _items,
	})
	_write_coverage()
	if "--require-all" in OS.get_cmdline_user_args() and not _missing.is_empty():
		_fail("Missing generated sheets: " + ", ".join(_missing))
	print("[content_art] %d sheets, %d sprites, %d pending, %d errors" % [_sheets.size(), _items.size(), _missing.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _fail(message: String) -> void:
	_errors += 1
	push_error("[content_art] " + message)


func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write: " + path)
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")


func _write_coverage() -> void:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "coverage_plan.json"))
	var counts: Dictionary[String, int] = {}
	for sheet: Dictionary in _sheets:
		counts[str(sheet["id"])] = int(sheet["count"])
	var sections: Array[Dictionary] = []
	for definition: Dictionary in plan.get("sections", []):
		var entry: Dictionary = definition.duplicate(true)
		var missing: Array[String] = []
		var sprites: int = 0
		for id: String in definition["job_ids"]:
			if not counts.has(id):
				missing.append(id)
			else:
				sprites += counts[id]
		for path: String in definition.get("runtime_files", []):
			if not FileAccess.file_exists(ROOT + path):
				missing.append(path)
		entry["prepared_sprite_count"] = sprites
		entry["pending"] = missing
		entry["status"] = "prepared" if missing.is_empty() else "in_progress"
		sections.append(entry)
	_write_json(ROOT + "coverage.json", {"scope": plan["scope"], "source_document": plan["source_document"], "sections": sections})


func _prepare(job: Dictionary) -> void:
	var id: String = str(job["id"])
	var metadata_path: String = ROOT + "metadata/" + id + ".json"
	var source_hash: String = FileAccess.get_md5(str(job["source"]))
	if FileAccess.file_exists(metadata_path) and "--force" not in OS.get_cmdline_user_args():
		var cached: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if cached.get("source_hash", "") == source_hash and cached.get("plan_hash", "") == JSON.stringify(job).sha256_text() and cached.get("pipeline_hash", "") == _pipeline_hash:
			var all_exist: bool = cached["items"].size() == job["cells"].size()
			for item: Dictionary in cached["items"]:
				all_exist = all_exist and FileAccess.file_exists(str(item["path"]))
			if all_exist:
				_items.append_array(cached["items"])
				_sheets.append(cached["sheet"])
				return
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(str(job["source"])))
	if source == null:
		_fail("Unreadable generated source: " + id)
		return
	var columns: int = int(job["columns"])
	var rows: int = int(job["rows"])
	var mode: String = str(job["mode"])
	var cells: Array = job["cells"]
	var frames: Array[Image] = []
	var frame_modes: Array[String] = []
	var regions: Array[Rect2i] = Utils.grid_regions(source, columns, rows, mode)
	var factors: Dictionary[String, float] = {}
	var atlas_cell_size: Vector2i = Vector2i.ZERO
	for index: int in cells.size():
		var definition: Dictionary = cells[index]
		var frame_mode: String = _cell_mode(mode, str(definition["category"]), str(definition["id"]))
		frame_modes.append(frame_mode)
		var frame: Image = Utils.extract(source, index % columns, index / columns, columns, rows, frame_mode, regions[index])
		frames.append(frame)
		var size: Vector2i = Vector2i(int(definition["size"][0]), int(definition["size"][1]))
		atlas_cell_size.x = maxi(atlas_cell_size.x, size.x)
		atlas_cell_size.y = maxi(atlas_cell_size.y, size.y)
		if definition.has("animation_group") and not frame.get_used_rect().size == Vector2i.ZERO:
			var group: String = str(definition["animation_group"])
			var bounds: Vector2i = frame.get_used_rect().size
			var factor: float = minf(float(size.x - 4) / bounds.x, float(size.y - 4) / bounds.y)
			factors[group] = minf(factors.get(group, factor), factor)
	var atlas: Image = Utils.canvas(atlas_cell_size * Vector2i(columns, rows))
	var entries: Array[Dictionary] = []
	for index: int in cells.size():
		var definition: Dictionary = cells[index]
		var item_id: String = str(definition["id"])
		var category: String = str(definition["category"])
		if ".." in item_id or ".." in category or item_id.begins_with("/"):
			_fail("Unsafe output ID: " + item_id)
			continue
		var size: Vector2i = Vector2i(int(definition["size"][0]), int(definition["size"][1]))
		var grounded: bool = str(definition.get("anchor", job.get("anchor", ""))) == "bottom_center" or category.begins_with("animals") or category.begins_with("characters") or category.begins_with("terrain/trees") or category.begins_with("terrain/orchard")
		var factor: float = factors.get(str(definition.get("animation_group", "")), -1.0)
		var extent: int = -1
		if category == "crops":
			var stage_index: int = index % columns
			extent = [18, 9, 15, 22, 28, 22][stage_index]
			factor = -1.0
			grounded = true
		var sprite: Image = Utils.fit(frames[index], size, frame_modes[index], grounded, factor, extent)
		if sprite.get_used_rect().size == Vector2i.ZERO:
			_fail("Empty generated cell: %s/%s" % [id, item_id])
			continue
		var path: String = ROOT + category + "/" + item_id + ".png"
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if sprite.save_png(path) != OK:
			_fail("Cannot save sprite: " + path)
		var cell: Vector2i = Vector2i(index % columns, index / columns)
		var tile_position: Vector2i = cell * atlas_cell_size + Vector2i((atlas_cell_size.x - size.x) / 2, atlas_cell_size.y - size.y)
		atlas.blit_rect(sprite, Rect2i(Vector2i.ZERO, size), tile_position)
		var entry: Dictionary = {
			"id": category + "/" + item_id, "name": definition["label"], "category": category,
			"path": path, "size": [size.x, size.y], "source": job["source"], "source_sheet": id,
			"source_grid_cell": [cell.x, cell.y], "atlas": ROOT + "atlases/" + id + ".png",
			"source_region": _rect_array(regions[index]),
			"atlas_region": [tile_position.x, tile_position.y, size.x, size.y],
			"anchor": [size.x / 2, size.y - 1] if grounded else [size.x / 2, size.y / 2],
			"opaque_bounds": _rect_array(sprite.get_used_rect()), "mode": frame_modes[index],
		}
		for field: String in ["animation_group", "frame"]:
			if definition.has(field):
				entry[field] = definition[field]
		var icon_size: int = 16
		if category.begins_with("buildings"):
			icon_size = 32
		if category.begins_with("items/") or category.begins_with("objects/") or category.begins_with("buildings/") or (category == "crops" and str(definition.get("frame", "")) in ["seed_packet", "harvest"]):
			var icon_path: String = ROOT + "icons/" + category + "/" + item_id + ".png"
			DirAccess.make_dir_recursive_absolute(icon_path.get_base_dir())
			var icon: Image = Utils.fit(sprite.duplicate() as Image, Vector2i(icon_size, icon_size), "sprite", false)
			if icon.save_png(icon_path) != OK:
				_fail("Cannot save inventory icon: " + icon_path)
			entry["icon"] = icon_path
			entry["icon_size"] = [icon_size, icon_size]
		if mode == "panel":
			entry["nine_patch_margin"] = [8, 8, 8, 8]
		if mode == "light":
			entry["blend_mode_hint"] = "multiply" if "shadow" in item_id else "add"
		entries.append(entry)
	DirAccess.make_dir_recursive_absolute(ROOT + "atlases")
	var atlas_path: String = ROOT + "atlases/" + id + ".png"
	if atlas.save_png(atlas_path) != OK:
		_fail("Cannot save atlas: " + id)
	var sheet: Dictionary = {"id": id, "category": job["category"], "path": atlas_path, "source": job["source"],
		"columns": columns, "rows": rows, "cell_size": [atlas_cell_size.x, atlas_cell_size.y], "count": entries.size(), "mode": mode}
	_write_json(metadata_path, {"source_hash": source_hash, "plan_hash": JSON.stringify(job).sha256_text(), "pipeline_hash": _pipeline_hash, "sheet": sheet, "items": entries})
	_items.append_array(entries)
	_sheets.append(sheet)
	print("[content_art] prepared " + id + ": " + str(entries.size()))


func _rect_array(rect: Rect2i) -> Array[int]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _cell_mode(mode: String, category: String, id: String) -> String:
	var suffix: String = id.get_file()
	if category == "terrain/mines" and suffix in ["ore_node", "stalagmite", "quartz_cluster", "cave_plant"]:
		return "sprite"
	if category == "terrain/interiors" and suffix not in ["plaster_wall", "wood_wall", "stone_wall", "wallpaper", "wood_floor", "stone_floor", "tile_floor", "brick_floor", "hay_floor", "ceiling_trim", "wall_trim", "corner_trim"]:
		return "sprite"
	if category == "terrain/beach" and suffix in ["sand", "wet_sand", "shallow_sea", "deep_sea"]:
		return "tile"
	if category == "terrain/town" and (suffix.ends_with("_wall") or suffix.ends_with("_roof")):
		return "tile"
	return mode


func _build_resources() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var groups: Dictionary[String, Array] = {}
	for item: Dictionary in catalog.get("items", []):
		var category: String = str(item["category"])
		if not item.has("animation_group") or category.begins_with("portraits") or category.begins_with("terrain") or category == "crops":
			continue
		var key: String = category + "/" + str(item["animation_group"])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(item)
	for key: String in groups:
		var resource: SpriteFrames = SpriteFrames.new()
		resource.remove_animation(&"default")
		for item: Dictionary in groups[key]:
			var phase: String = str(item["frame"])
			var animation: String = phase
			if phase.ends_with("_a") or phase.ends_with("_b"):
				animation = phase.left(-2)
			elif phase.begins_with("f") and phase.substr(1).is_valid_int():
				animation = "play"
			var name: StringName = StringName(animation)
			if not resource.has_animation(name):
				resource.add_animation(name)
				resource.set_animation_speed(name, 5.0)
				var loops: bool = animation in ["move", "play"] or animation.begins_with("walk") or animation.begins_with("graze") or (str(item["category"]) == "characters/villagers" and animation in ["down", "up", "left", "right"])
				resource.set_animation_loop(name, loops)
			var texture: Texture2D = load(str(item["path"])) as Texture2D
			if texture == null:
				_fail("Texture not imported: " + str(item["path"]))
				continue
			resource.add_frame(name, texture)
		var destination: String = ROOT + "animations/" + key + ".tres"
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if ResourceSaver.save(resource, destination) != OK:
			_fail("Cannot save SpriteFrames: " + key)
	print("[content_art] SpriteFrames groups: " + str(groups.size()))
