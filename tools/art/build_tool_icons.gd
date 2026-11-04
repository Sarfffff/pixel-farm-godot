extends SceneTree
## 延续 held_tool_painter 的可编辑像素轮廓与调色板，统一 16px 道具图标。

const COLORS := {
	"o": Color("47334f"), "s": Color("454958"), "m": Color("73798a"),
	"l": Color("aab1ba"), "L": Color("d8d8ce"), "w": Color("936b49"),
	"h": Color("bc945e"), "H": Color("e1cd9f"), "g": Color("596b4b"),
	"G": Color("839568"), "c": Color("fcebc0"), "b": Color("644533"),
}
const SHAPES := {
	"hoe": [
		"................", ".....ooooooo....", "....omLLLLLlo...", "....osmlllmmo...",
		".....ooowomso...", ".......ohoso....", "......oHhooo....", ".....oHhwo......",
		"....oHhwo.......", "...oHhwo........", "..oHhwo.........", ".oHhwo..........",
		".ohwo...........", "..oo............", "................", "................",
	],
	"axe": [
		"................", "........oooo....", ".......omLLLo...", "......ohomLLLo..",
		".....oHhomlLLo..", ".....ohwosmLLo..", "....oHhwoosmo...", "...oHhwo.ooo....",
		"..oHhwo.........", ".oHhwo..........", ".ohwo...........", "..oo............",
		"................", "................", "................", "................",
	],
	"watering_can": [
		"................", "....ooooo.......", "...oLmmllo......", "...om...mo......",
		"...oo...oo......", "..ooGoooGoo..oo.", ".oLGGGGGGGGoGLo.", ".oGGGGGGGGoGmo..",
		".oGGGggGGGoGo...", ".oGGggggGGoGo...", "..oGggggGGoGo...", "..oGGggGGoGo....",
		"...ooooooo......", "................", "................", "................",
	],
}


func _init() -> void:
	var preview := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	preview.fill(Color.TRANSPARENT)
	var index: int = 0
	for id: String in SHAPES:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var rows: Array = SHAPES[id]
		for y in 16:
			for x in 16:
				var code: String = rows[y][x]
				if COLORS.has(code):
					image.set_pixel(x, y, COLORS[code])
		image.save_png("res://assets/textures/items/tool_%s.png" % id)
		preview.blit_rect(image, Rect2i(0, 0, 16, 16), Vector2i(index * 16, 0))
		if id == "watering_can":
			var copper: Image = image.duplicate()
			for y in 16:
				for x in 16:
					var color: Color = copper.get_pixel(x, y)
					if color == COLORS["g"]:
						copper.set_pixel(x, y, Color("936b49"))
					elif color == COLORS["G"]:
						copper.set_pixel(x, y, Color("d19a65"))
			copper.save_png("res://assets/textures/items/tool_copper_watering_can.png")
		index += 1
	var pickaxe := Image.load_from_file("res://assets/textures/items/stone_pickaxe.png")
	preview.blit_rect(pickaxe, Rect2i(0, 0, 16, 16), Vector2i(48, 0))
	preview.resize(768, 192, Image.INTERPOLATE_NEAREST)
	# 预览目录不入库，先确保存在
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
	preview.save_png("res://docs/screenshots/tool-icons-unified.png")
	print("[tool_icons] unified outlines, metal highlights and wooden handles")
	quit()
