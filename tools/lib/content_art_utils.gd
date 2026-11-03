extends RefCounted
## 独立生成素材的技术整理：Alpha、邻格碎片、最近邻、统一像素色板。

const PALETTE: Array[Color] = [
	Color("514c40"), Color("70634f"), Color("8b775e"), Color("a98b68"),
	Color("bb9269"), Color("d0ad7e"), Color("dec79a"), Color("eee3c2"),
	Color("f5eed7"), Color("5e725a"), Color("70876b"), Color("8d9d71"),
	Color("9aad78"), Color("b1c389"), Color("cad698"), Color("dce3b5"),
	Color("526e6b"), Color("638b83"), Color("78aaa3"), Color("9ec5b5"),
	Color("b8d8cb"), Color("586976"), Color("7c8e98"), Color("a2b0b5"),
	Color("c4d3d4"), Color("687d97"), Color("91a9be"), Color("b9ceda"),
	Color("9b6e61"), Color("b78573"), Color("ce9d8b"), Color("e2bbaa"),
	Color("ac7856"), Color("c18c65"), Color("d8a67a"), Color("e7c494"),
	Color("796779"), Color("99869b"), Color("b5a2b1"), Color("d0bec8"),
	Color("c6a765"), Color("dfc37e"), Color("eedba5"), Color("3f5159"),
	Color("343f47"), Color("26333d"), Color("544b5f"), Color("f7f0dc"),
]
static var _color_cache: Dictionary[Color, Color] = {}


static func canvas(size: Vector2i) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


static func grid_regions(image: Image, columns: int, rows: int, mode: String) -> Array[Rect2i]:
	var x_counts: PackedInt32Array = PackedInt32Array()
	var y_counts: PackedInt32Array = PackedInt32Array()
	x_counts.resize(image.get_width())
	y_counts.resize(image.get_height())
	if mode not in ["tile", "background", "light"]:
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x, y).a >= 0.5:
					x_counts[x] += 1
					y_counts[y] += 1
	var x_edges: PackedInt32Array = _axis_edges(x_counts, maxi(2, image.get_height() / 200), columns)
	var y_edges: PackedInt32Array = _axis_edges(y_counts, maxi(2, image.get_width() / 200), rows)
	var regions: Array[Rect2i] = []
	for row: int in rows:
		for column: int in columns:
			regions.append(Rect2i(x_edges[column], y_edges[row], x_edges[column + 1] - x_edges[column], y_edges[row + 1] - y_edges[row]))
	return regions


static func _axis_edges(counts: PackedInt32Array, threshold: int, expected: int) -> PackedInt32Array:
	var runs: Array[Vector2i] = []
	var start: int = -1
	for index: int in counts.size() + 1:
		var occupied: bool = index < counts.size() and counts[index] >= threshold
		if occupied and start < 0:
			start = index
		elif not occupied and start >= 0:
			runs.append(Vector2i(start, index))
			start = -1
	var edges: PackedInt32Array = PackedInt32Array()
	if runs.size() == expected and expected > 1:
		# 某些生成图把整组居中留白，实际列距并非画布宽度/列数。
		# 在透明沟槽中取边界，完整保留每个主体，而非硬切到邻格。
		edges.append(maxi(0, runs[0].x - (runs[1].x - runs[0].y) / 2))
		for index: int in range(1, runs.size()):
			edges.append((runs[index - 1].y + runs[index].x) / 2)
		edges.append(mini(counts.size(), runs[-1].y + (runs[-1].x - runs[-2].y) / 2))
	else:
		for index: int in expected + 1:
			edges.append(roundi(float(index * counts.size()) / expected))
	return edges


static func extract(image: Image, column: int, row: int, columns: int, rows: int, mode: String, source_rect: Rect2i = Rect2i()) -> Image:
	var start: Vector2i = Vector2i(roundi(float(image.get_width() * column) / columns), roundi(float(image.get_height() * row) / rows))
	var end: Vector2i = Vector2i(roundi(float(image.get_width() * (column + 1)) / columns), roundi(float(image.get_height() * (row + 1)) / rows))
	var frame: Image = image.get_region(source_rect if source_rect.size != Vector2i.ZERO else Rect2i(start, end - start))
	frame.convert(Image.FORMAT_RGBA8)
	if mode == "tile":
		# 移除图集分格时生成的细分隔线，避免铺地后每格出现暗框。
		var trim: int = maxi(1, mini(frame.get_width(), frame.get_height()) / 64)
		frame = frame.get_region(Rect2i(Vector2i(trim, trim), frame.get_size() - Vector2i(trim, trim) * 2))
	if mode == "light":
		return frame
	for y: int in frame.get_height():
		for x: int in frame.get_width():
			var color: Color = frame.get_pixel(x, y)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			frame.set_pixel(x, y, color if color.a > 0 else Color.TRANSPARENT)
	if mode not in ["tile", "background"]:
		remove_fragments(frame)
	return frame


static func remove_fragments(frame: Image) -> void:
	var width: int = frame.get_width()
	var height: int = frame.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	var components: Array[Dictionary] = []
	var largest: int = -1
	var largest_area: int = 0
	for y: int in height:
		for x: int in width:
			var start: int = y * width + x
			if visited[start] != 0 or frame.get_pixel(x, y).a == 0:
				continue
			var pixels: PackedInt32Array = PackedInt32Array([start])
			visited[start] = 1
			var bounds: Rect2i = Rect2i(x, y, 1, 1)
			var index: int = 0
			while index < pixels.size():
				var pixel: int = pixels[index]
				index += 1
				var point: Vector2i = Vector2i(pixel % width, pixel / width)
				bounds = bounds.expand(point)
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var next: Vector2i = point + Vector2i(dx, dy)
						if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
							continue
						var next_index: int = next.y * width + next.x
						if visited[next_index] == 0 and frame.get_pixelv(next).a > 0:
							visited[next_index] = 1
							pixels.append(next_index)
			components.append({"pixels": pixels, "bounds": bounds})
			if pixels.size() > largest_area:
				largest_area = pixels.size()
				largest = components.size() - 1
	if largest < 0:
		return
	var keep_region: Rect2i = (components[largest]["bounds"] as Rect2i).grow(maxi(3, mini(width, height) / 40))
	for component: Dictionary in components:
		if keep_region.intersects(component["bounds"]):
			continue
		for pixel: int in component["pixels"]:
			frame.set_pixel(pixel % width, pixel / width, Color.TRANSPARENT)


static func fit(frame: Image, size: Vector2i, mode: String, grounded: bool, scale_factor: float = -1.0, extent: int = -1) -> Image:
	var result: Image = canvas(size)
	if mode in ["tile", "background"]:
		if mode == "tile" and frame.get_used_rect().size != Vector2i.ZERO:
			frame = frame.get_region(frame.get_used_rect())
		frame.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		result.blit_rect(frame, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	else:
		var bounds: Rect2i = frame.get_used_rect()
		if bounds.size == Vector2i.ZERO:
			return result
		var crop: Image = frame.get_region(bounds)
		var room: Vector2i = size - Vector2i(4, 4)
		if extent > 0:
			room = Vector2i(extent, extent)
		var factor: float = minf(float(room.x) / bounds.size.x, float(room.y) / bounds.size.y)
		if scale_factor > 0:
			factor = minf(factor, scale_factor)
		crop.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
		var position: Vector2i = (size - crop.get_size()) / 2
		if grounded:
			position.y = size.y - crop.get_height() - 2
		result.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), position)
	quantize(result, mode == "light")
	return result


static func quantize(image: Image, keep_alpha: bool) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if color.a <= 0.0:
				image.set_pixel(x, y, Color.TRANSPARENT)
				continue
			var opaque: Color = Color(color, 1.0)
			if not _color_cache.has(opaque):
				var nearest: Color = PALETTE[0]
				var distance: float = INF
				for candidate: Color in PALETTE:
					var difference: Vector3 = Vector3(opaque.r - candidate.r, opaque.g - candidate.g, opaque.b - candidate.b)
					var candidate_distance: float = difference.length_squared()
					if candidate_distance < distance:
						distance = candidate_distance
						nearest = candidate
				_color_cache[opaque] = nearest
			image.set_pixel(x, y, Color(_color_cache[opaque], color.a if keep_alpha else 1.0))
