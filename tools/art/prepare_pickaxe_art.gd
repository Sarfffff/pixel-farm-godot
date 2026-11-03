extends SceneTree

const SOURCE: String = "res://assets/generated/sources/"
const OUTPUT: String = "res://assets/generated/characters/"
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const PALETTE: Array[Color] = [
	Color("47334f"), Color("6d526f"), Color("9b80a0"), Color("c9b5c4"),
	Color("fcebc0"), Color("e1cd9f"), Color("b99c83"), Color("936b49"),
	Color("644533"), Color("bb9259"), Color("454958"), Color("73798a"),
	Color("aab1ba"), Color("d8d8ce"), Color("d99488"), Color("faf2d6"),
]

var _errors: int = 0


func _init() -> void:
	var down: Image = _load("stone_pickaxe_actions_source_v1.png")
	var up: Image = _load("stone_pickaxe_up_source_v1.png")
	var side: Image = _load("stone_pickaxe_side_source_v1.png")
	var icon_source: Image = _load("stone_pickaxe_icon_source_v1.png")
	if _errors > 0:
		quit(1)
		return
	var atlas: Image = _canvas(Vector2i(192, 128))
	for row: int in 4:
		for phase: int in 6:
			var frame: Image
			if row == 0:
				frame = _cell(down, Vector2i(phase, 0), Vector2i(6, 4))
			elif row == 1:
				frame = _cell(up, Vector2i(phase, 0), Vector2i(6, 1))
			else:
				var source_cell: Vector2i = Vector2i([0, 1, 2, 3, 3, 4][phase], 1 if phase == 4 else 0)
				frame = _cell(side, source_cell, Vector2i(5, 2))
			frame = _align_character(frame)
			if row == 2:
				frame.flip_x()
			if frame.save_png(OUTPUT + "stone_pickaxe_%s_%d.png" % [DIRECTIONS[row], phase]) != OK:
				_fail("Cannot save action frame")
			atlas.blit_rect(frame, Rect2i(0, 0, 32, 32), Vector2i(phase, row) * 32)
	if atlas.save_png(OUTPUT + "stone_pickaxe_actions_v1.png") != OK:
		_fail("Cannot save action atlas")
	var icon: Image = _fit_icon(_clean(icon_source))
	if icon.save_png("res://assets/generated/items/stone_pickaxe.png") != OK:
		_fail("Cannot save icon")
	atlas.resize(1152, 768, Image.INTERPOLATE_NEAREST)
	if atlas.save_png(OUTPUT + "stone_pickaxe_preview.png") != OK:
		_fail("Cannot save preview")
	var catalog: FileAccess = FileAccess.open(OUTPUT + "stone_pickaxe_catalog.json", FileAccess.WRITE)
	if catalog == null:
		_fail("Cannot save catalog")
	else:
		catalog.store_string(JSON.stringify({
			"atlas": OUTPUT + "stone_pickaxe_actions_v1.png", "frame_size": [32, 32],
			"rows": DIRECTIONS, "columns": ["ready", "windup", "overhead", "impact", "follow_through", "recover"],
			"impact_frame": 3, "feet_y": 23, "alpha": [0, 255], "colors": 16,
			"icon": "res://assets/generated/items/stone_pickaxe.png", "icon_size": [16, 16],
			"sources": ["stone_pickaxe_actions_source_v1.png", "stone_pickaxe_up_source_v1.png", "stone_pickaxe_side_source_v1.png", "stone_pickaxe_icon_source_v1.png"],
			"preparation": "Independent AI-drawn pickaxe poses, curated side sequence; left mirrors the new right sequence. No hoe or axe frames used.",
		}, "\t") + "\n")
	print("[pickaxe_art] 24 independent action frames and 1 icon; %d errors" % _errors)
	quit(0 if _errors == 0 else 1)


func _fail(message: String) -> void:
	_errors += 1
	push_error("[pickaxe_art] " + message)


func _load(name: String) -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + name))
	if image == null:
		_fail("Missing source: " + name)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _canvas(size: Vector2i) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _cell(source: Image, coordinate: Vector2i, grid: Vector2i) -> Image:
	var start: Vector2i = Vector2i(roundi(float(source.get_width() * coordinate.x) / grid.x), roundi(float(source.get_height() * coordinate.y) / grid.y))
	var end: Vector2i = Vector2i(roundi(float(source.get_width() * (coordinate.x + 1)) / grid.x), roundi(float(source.get_height() * (coordinate.y + 1)) / grid.y))
	var inset: Vector2i = Vector2i(6, 6) if grid == Vector2i(5, 2) else Vector2i.ZERO
	return _clean(source.get_region(Rect2i(start + inset, end - start - inset * 2)))


func _clean(image: Image) -> Image:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			var background: bool = color.r > 0.7 and color.b > 0.65 and color.g < 0.4
			var fringe: bool = color.r > color.g + 0.23 and color.b > color.g + 0.23 and color.r + color.b > 1.2
			if color.a < 0.5 or background or fringe:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)
	_keep_subject(image)
	return image


func _keep_subject(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	var components: Array[PackedInt32Array] = []
	var largest: int = -1
	var largest_size: int = 0
	for y: int in height:
		for x: int in width:
			var start: int = y * width + x
			if visited[start] != 0 or image.get_pixel(x, y).a == 0.0:
				continue
			var pixels: PackedInt32Array = PackedInt32Array([start])
			visited[start] = 1
			var index: int = 0
			while index < pixels.size():
				var point: Vector2i = Vector2i(pixels[index] % width, pixels[index] / width)
				index += 1
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var next: Vector2i = point + Vector2i(dx, dy)
						if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
							continue
						var next_index: int = next.y * width + next.x
						if visited[next_index] == 0 and image.get_pixelv(next).a > 0.0:
							visited[next_index] = 1
							pixels.append(next_index)
			components.append(pixels)
			if pixels.size() > largest_size:
				largest = components.size() - 1
				largest_size = pixels.size()
	for index: int in components.size():
		if index == largest:
			continue
		for pixel: int in components[index]:
			image.set_pixel(pixel % width, pixel / width, Color.TRANSPARENT)


func _is_fur(color: Color) -> bool:
	return color.a > 0.0 and color.r > 0.77 and color.g > 0.70 and color.r > color.g + 0.015 and color.g > color.b + 0.08


func _align_character(frame: Image) -> Image:
	var body: Rect2i = Rect2i()
	for y: int in frame.get_height():
		for x: int in frame.get_width():
			if _is_fur(frame.get_pixel(x, y)):
				body = Rect2i(x, y, 1, 1) if body.size == Vector2i.ZERO else body.expand(Vector2i(x, y))
	var result: Image = _canvas(Vector2i(32, 32))
	if body.size.y == 0:
		_fail("Missing cat body")
		return result
	var factor: float = 14.0 / body.size.y
	var pivot: Vector2i = Vector2i(roundi(body.get_center().x * factor), roundi(body.end.y * factor))
	frame.resize(maxi(1, roundi(frame.get_width() * factor)), maxi(1, roundi(frame.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	result.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(16, 23) - pivot)
	_quantize(result)
	return result


func _fit_icon(frame: Image) -> Image:
	var result: Image = _canvas(Vector2i(16, 16))
	var bounds: Rect2i = frame.get_used_rect()
	if bounds.size == Vector2i.ZERO:
		_fail("Empty icon")
		return result
	var crop: Image = frame.get_region(bounds)
	var factor: float = 14.0 / maxi(crop.get_width(), crop.get_height())
	crop.resize(maxi(1, roundi(crop.get_width() * factor)), maxi(1, roundi(crop.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	result.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), (Vector2i(16, 16) - crop.get_size()) / 2)
	_quantize(result)
	return result


func _quantize(image: Image) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if color.a == 0.0:
				continue
			var nearest: Color = PALETTE[0]
			var distance: float = INF
			for candidate: Color in PALETTE:
				var difference: Vector3 = Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
				if difference.length_squared() < distance:
					distance = difference.length_squared()
					nearest = candidate
			image.set_pixel(x, y, nearest)
