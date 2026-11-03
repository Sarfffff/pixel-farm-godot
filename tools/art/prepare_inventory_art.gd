extends SceneTree

const SOURCE: String = "res://assets/generated/sources/inventory_ui_v1.png"
const OUTPUT: String = "res://assets/generated/ui/inventory/"
const PALETTE: Array[Color] = [
	Color("302421"), Color("392b2a"), Color("45352f"), Color("564034"),
	Color("654638"), Color("79553f"), Color("936644"), Color("a7744f"),
	Color("bc8757"), Color("cf9d61"), Color("dcb272"), Color("eacb86"),
	Color("b79b6c"), Color("ceba88"), Color("e5d3a0"), Color("f0e1b6"),
]


func _init() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null:
		push_error("[inventory_art] Missing source atlas")
		quit(1)
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if error != OK:
		push_error("[inventory_art] Cannot create output directory: %s" % error)
		quit(1)
		return
	var panel: Image = _cell(source, Vector2i(0, 0), 32)
	var idle: Image = _cell(source, Vector2i(1, 0), 20)
	var selected: Image = _cell(source, Vector2i(0, 1), 20)
	var details: Image = _cell(source, Vector2i(1, 1), 16)
	var hover: Image = idle.duplicate() as Image
	for y: int in hover.get_height():
		for x: int in hover.get_width():
			var color: Color = hover.get_pixel(x, y)
			if x <= 1 or y <= 1 or x >= 18 or y >= 18:
				color = Color("b79b6c") if color.r > 0.35 else Color("654638")
			else:
				color = Color("564034") if color.r < 0.35 else Color("654638")
			hover.set_pixel(x, y, color)
	var images: Dictionary[String, Image] = {
		"panel": panel, "slot_idle": idle, "slot_selected": selected,
		"slot_hover": hover, "details": details,
	}
	for name: String in images:
		if images[name].save_png(OUTPUT + name + ".png") != OK:
			push_error("[inventory_art] Cannot save " + name)
			quit(1)
			return
	print("[inventory_art] Saved 5 pixel textures; 16-color palette; nearest sampling")
	quit(0)


func _cell(source: Image, coordinate: Vector2i, size: int) -> Image:
	var cell_size: Vector2i = source.get_size() / 2
	var image: Image = source.get_region(Rect2i(coordinate * cell_size, cell_size))
	image.resize(size, size, Image.INTERPOLATE_NEAREST)
	image.convert(Image.FORMAT_RGBA8)
	for y: int in size:
		for x: int in size:
			image.set_pixel(x, y, _nearest_color(image.get_pixel(x, y)))
	return image


func _nearest_color(color: Color) -> Color:
	var nearest: Color = PALETTE[0]
	var distance: float = INF
	for candidate: Color in PALETTE:
		var difference: Vector3 = Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
		var candidate_distance: float = difference.length_squared()
		if candidate_distance < distance:
			distance = candidate_distance
			nearest = candidate
	return nearest
