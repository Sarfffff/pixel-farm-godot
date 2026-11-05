extends SceneTree
## 室内墙面素材生成器
##
## 原先室内只用一张"上浅下深"的 wood_wall 铺满左右墙，每格重复同一条横向色带，
## 远看就是一排横条纹（玩家反馈"围墙看着像平铺"）。这里补三张可无缝平铺的 16×16：
##   wall_paper   米色竖纹壁纸（正墙主体）
##   wall_planks  竖向木板（侧墙、底墙、护墙板）
##   wall_brick   错缝砖（顶部梁、踢脚线）
##
## 运行：
##   godot --headless --path . --script res://tools/art/build_interior_walls.gd

const OUT_DIR: String = "res://assets/packs/presentation_v3/tiles"
const SIZE: int = 16


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save("wall_paper", _paper())
	_save("wall_planks", _planks())
	_save("wall_brick", _brick())
	print("[walls] 完成")
	quit(0)


## 竖纹壁纸：底色 + 每 4px 一道淡竖纹，顶部压一条阴影、底部一条收边。
func _paper() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var base := Color("d9d3ba")
	var stripe := Color("cdc6a8")
	var shade := Color("b8b092")
	var skirt := Color("c3bca0")
	for y in SIZE:
		for x in SIZE:
			var color := base
			if x % 4 == 0:
				color = stripe
			if x % 8 == 4:
				color = base.lightened(0.03)
			if y == 0:
				color = shade
			elif y == SIZE - 1:
				color = skirt
			# 极轻的竖向明暗，避免整片死平
			if x % 4 == 1:
				color = color.lightened(0.02)
			img.set_pixel(x, y, color)
	return img


## 竖向木板：每 5px 一道深缝，缝右侧一道高光，偶发横向木纹点。
func _planks() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var base := Color("b98a5e")
	var seam := Color("86603f")
	var highlight := Color("cfa273")
	for y in SIZE:
		for x in SIZE:
			var color := base
			if x % 5 == 0:
				color = seam
			elif x % 5 == 1:
				color = highlight
			if y == 0:
				color = color.lightened(0.08)
			elif y == SIZE - 1:
				color = color.darkened(0.12)
			# 稀疏木纹：只在缝左侧的中段出现
			if y == 6 and x % 5 == 3:
				color = color.darkened(0.08)
			if y == 11 and x % 5 == 2:
				color = color.darkened(0.06)
			img.set_pixel(x, y, color)
	return img


## 错缝砖：每 4px 一行砖，奇数行错开半块，砖体带轻微明暗差。
func _brick() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var brick := Color("c47a5f")
	var mortar := Color("8a6350")
	for y in SIZE:
		var row := y / 4
		var offset := 0 if row % 2 == 0 else 4
		for x in SIZE:
			var color := brick
			if y % 4 == 3:
				color = mortar
			elif (x + offset) % 8 == 0:
				color = mortar
			else:
				var even_brick := ((x + offset) / 8 + row) % 2 == 0
				color = brick.lightened(0.05) if even_brick else brick.darkened(0.04)
			img.set_pixel(x, y, color)
	return img


func _save(name: String, image: Image) -> void:
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(path) == OK:
		print("[walls] %s" % path)
	else:
		printerr("[walls] 写入失败：%s" % path)
