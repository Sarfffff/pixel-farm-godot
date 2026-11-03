extends SceneTree

const Painter: Script = preload("res://tools/art/held_tool_painter.gd")
const CAT_SOURCE: String = "res://assets/game/characters/basic_charakter_spritesheet.png"
const OUTPUT: String = "res://assets/generated/characters/"
const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe", &"stone_pickaxe"]
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]

var _errors: int = 0


func _init() -> void:
	var cat: Image = Image.load_from_file(ProjectSettings.globalize_path(CAT_SOURCE))
	if cat == null:
		push_error("[held_tools_art] Missing cat source")
		quit(1)
		return
	cat.convert(Image.FORMAT_RGBA8)
	var atlas: Image = _canvas(Vector2i(128, 640))
	var preview: Image = _canvas(Vector2i(160, 128))
	var entries: Array[Dictionary] = []
	for tool_index: int in 5:
		var tool: StringName = TOOLS[tool_index]
		for direction_index: int in 4:
			var direction: StringName = DIRECTIONS[direction_index]
			for phase: int in 4:
				var character: Image = cat.get_region(Rect2i(16 + phase * 48, 16 + direction_index * 48, 16, 16))
				var frame: Image = Painter.frame(character, tool, direction_index, phase)
				atlas.blit_rect(frame, Rect2i(0, 0, 32, 32), Vector2i(phase * 32, (tool_index * 4 + direction_index) * 32))
				if phase == 0:
					preview.blit_rect(frame, Rect2i(0, 0, 32, 32), Vector2i(tool_index, direction_index) * 32)
			entries.append({"tool": tool, "direction": direction, "atlas_row": tool_index * 4 + direction_index})
	if atlas.save_png(OUTPUT + "held_tools_v1.png") != OK:
		_errors += 1
	preview.resize(960, 768, Image.INTERPOLATE_NEAREST)
	if preview.save_png(OUTPUT + "held_tools_preview.png") != OK:
		_errors += 1
	var file: FileAccess = FileAccess.open(OUTPUT + "held_tools_catalog.json", FileAccess.WRITE)
	if file == null:
		_errors += 1
	else:
		file.store_string(JSON.stringify({
			"version": 2, "atlas": OUTPUT + "held_tools_v1.png", "frame_size": [32, 32], "columns": 4,
			"tools": TOOLS, "directions": DIRECTIONS, "rows": entries,
			"preview": OUTPUT + "held_tools_preview.png", "alpha": [0, 255], "colors": 16,
			"preparation": "Native-resolution carry tools redrawn in held_tool_painter.gd. Upright long handles, outward-facing heads, short loads at waist. Connected arms follow the actual torso in each original walk frame, with at most one pixel lateral sway. Back view occludes tools behind body. Original face and feet retained. Action sprites unchanged.",
		}, "\t") + "\n")
	print("[held_tools_art] 20 directional grip poses, 80 frames, %d errors" % _errors)
	quit(0 if _errors == 0 else 1)


func _canvas(size: Vector2i) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image
