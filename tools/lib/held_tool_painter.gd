extends RefCounted

const COLORS: Dictionary[String, Color] = {
	"o": Color("47334f"), "w": Color("936b49"), "h": Color("bc945e"),
	"s": Color("454958"), "m": Color("73798a"), "l": Color("aab1ba"),
	"g": Color("596b4b"), "G": Color("839568"), "c": Color("f3f2c0"),
}
const OUTLINE: Color = Color("5c4e92")
const FUR: Color = Color("f3f2c0")
const FUR_SHADE: Color = Color("ddd5de")
const SHORTS: Color = Color("766daa")
## StringName 键不算常量表达式，用 static var 保存同一份静态数据。
static var SHAPES: Dictionary[StringName, Array] = {
	&"hoe": [
		".ooooo.", ".omlllo", ".owomso", ".owo.so", ".owo...", ".owo...",
		".owo...", ".owo...", ".owo...", ".owo...", ".owo...", "..o....",
	],
	&"axe": [
		"..ooo...", ".owomlo.", ".owomllo", ".owommso", ".owomso.", ".owooo..",
		".owo....", ".owo....", ".owo....", ".owo....", ".owo....", "..o.....",
	],
	&"stone_pickaxe": [
		".oooo...", "osmllmso", "oowooo.o", ".ohoc..o", ".owo....", ".owo....",
		".owo....", ".owo....", ".owo....", ".owo....", ".owo....", "..o.....",
	],
	&"watering_can": [
		"..ooo....", ".o...o...", ".o...o...", ".ooooo..o", "oGGGGGoGo",
		"oGGgGGoGo", "oGgggGoo.", ".ooooo...",
	],
	&"seeds": [
		"..oho..", ".owwwo.", "oGwhwho", "owGwhwo", "owwgwho", "owhhwwo", ".ooooo.",
	],
}


static func frame(character: Image, tool: StringName, direction: int, phase: int) -> Image:
	var result: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var equipment: Image = _tool(tool, direction)
	var torso_y: int = _torso_y(character)
	var left: bool = direction == 2
	var long_tool: bool = tool in [&"hoe", &"axe", &"stone_pickaxe"]
	var sway: int = [0, 1, 0, 1][phase] if long_tool else 0
	var grip: Vector2i = Vector2i(23, torso_y + 2)
	var root: Vector2i = Vector2i(20, torso_y + 2)
	if direction in [2, 3]:
		grip.x = 22
		root.x = 18
	grip.x += sway
	if tool == &"stone_pickaxe":
		grip.x += 1
	var tool_grip: Vector2i = Vector2i(2, 8)
	if tool == &"watering_can":
		tool_grip = Vector2i(3, 2)
		grip.y = torso_y - 1
		root.y = torso_y + 1
	elif tool == &"seeds":
		tool_grip = Vector2i(1, 2)
		grip = Vector2i(21 if direction in [0, 1] else 19, torso_y + 1)
	if left:
		grip.x = 31 - grip.x
		root.x = 31 - root.x
		tool_grip.x = equipment.get_width() - 1 - tool_grip.x
	var position: Vector2i = grip - tool_grip
	var equipment_rect: Rect2i = Rect2i(Vector2i.ZERO, equipment.get_size())
	if direction == 1:
		result.blend_rect(equipment, equipment_rect, position)
		_arm(result, root, grip)
		result.blend_rect(character, Rect2i(0, 0, 16, 16), Vector2i(8, 8))
	else:
		result.blend_rect(character, Rect2i(0, 0, 16, 16), Vector2i(8, 8))
		_arm(result, root, grip)
		result.blend_rect(equipment, equipment_rect, position)
	_paw(result, grip)
	for y: int in character.get_height():
		if y >= torso_y - 8 and y < 14:
			continue
		for x: int in character.get_width():
			var color: Color = character.get_pixel(x, y)
			if color.a > 0.0:
				result.set_pixel(x + 8, y + 8, color)
	return result


static func _torso_y(character: Image) -> int:
	for y: int in character.get_height():
		for x: int in character.get_width():
			if character.get_pixel(x, y) == SHORTS:
				return 8 + y
	return 18


static func _tool(tool: StringName, direction: int) -> Image:
	var rows: Array[String] = []
	rows.assign(SHAPES[tool])
	var image: Image = Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in rows.size():
		for x: int in rows[y].length():
			var symbol: String = rows[y][x]
			if COLORS.has(symbol):
				image.set_pixel(x, y, COLORS[symbol])
	if tool == &"seeds" and direction == 1:
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x, y) in [COLORS["g"], COLORS["G"]]:
					image.set_pixel(x, y, COLORS["w"])
	if direction == 2:
		image.flip_x()
	return image


static func _arm(image: Image, start: Vector2i, end: Vector2i) -> void:
	var steps: int = maxi(absi(end.x - start.x), absi(end.y - start.y))
	for step: int in steps + 1:
		var point: Vector2i = Vector2i(Vector2(start).lerp(Vector2(end), float(step) / maxi(1, steps)).round())
		image.set_pixelv(point + Vector2i.UP, OUTLINE)
		image.set_pixelv(point + Vector2i.DOWN, OUTLINE)
		image.set_pixelv(point, FUR if step < steps else FUR_SHADE)


static func _paw(image: Image, point: Vector2i) -> void:
	image.set_pixelv(point + Vector2i.UP, OUTLINE)
	image.set_pixelv(point + Vector2i.DOWN, OUTLINE)
	image.set_pixelv(point, FUR)
	image.set_pixelv(point + Vector2i.RIGHT, FUR_SHADE)
