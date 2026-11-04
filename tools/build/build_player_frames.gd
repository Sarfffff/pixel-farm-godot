extends SceneTree
## 玩家帧资源生成器
##
## 从 basic_charakter_spritesheet.png 切出 4 方向 × 4 帧的行走动画与单帧待机动画，
## 保留 24 个原动画，追加五种工具四向待机/行走，共 64 个动画。
##
## 图集实测布局：帧尺寸 16×16，列/行间隔 48px，首个帧左上角在 (16,16)；
## 行顺序为 下 / 上 / 左 / 右（左与右互为镜像，见 docs/02 实际记录）。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_player_frames.gd

const SHEET_PATH := "res://assets/textures/base/characters/basic_charakter_spritesheet.png"
const OUT_PATH := "res://scenes/player/player_frames.tres"
const ACTION_SHEET := preload("res://assets/textures/base/characters/basic_charakter_actions.png")
const NEW_ACTIONS := preload("res://assets/textures/characters/farmer_actions_v3.png")
const PICKAXE_ACTIONS: Texture2D = preload("res://assets/textures/characters/stone_pickaxe_actions_v1.png")
const HELD_TOOLS: Texture2D = preload("res://assets/textures/characters/held_tools_v1.png")
const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe", &"stone_pickaxe"]

const ORIGIN := 16
const STEP := 48
const FRAME_SIZE := 16

const ROW_DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]
const WALK_FPS := 8.0
const IDLE_FPS := 1.0


func _init() -> void:
	var sheet := load(SHEET_PATH) as Texture2D
	if sheet == null:
		push_error("[build_player_frames] 无法加载 %s" % SHEET_PATH)
		quit(1)
		return

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for row in ROW_DIRECTIONS.size():
		var direction: StringName = ROW_DIRECTIONS[row]

		var idle_name: StringName = StringName("idle_%s" % direction)
		frames.add_animation(idle_name)
		frames.set_animation_speed(idle_name, IDLE_FPS)
		frames.set_animation_loop(idle_name, false)
		frames.add_frame(idle_name, _make_atlas(sheet, row, 0))

		var walk_name: StringName = StringName("walk_%s" % direction)
		frames.add_animation(walk_name)
		frames.set_animation_speed(walk_name, WALK_FPS)
		frames.set_animation_loop(walk_name, true)
		for col in 4:
			frames.add_frame(walk_name, _make_atlas(sheet, row, col))

	# 新图集 32×32 独立姿势，锄地向下挖、挥斧横向砍；水壶沿用原素材。
	for tool: String in ["hoe", "watering_can", "axe"]:
		var first_row: int = {"axe": 0, "hoe": 4, "watering_can": 8}[tool]
		for row in ROW_DIRECTIONS.size():
			var action := StringName("%s_%s" % [tool, ROW_DIRECTIONS[row]])
			frames.add_animation(action)
			frames.set_animation_loop(action, false)
			frames.set_animation_speed(action, 10.0)
			if tool != "watering_can":
				var action_row: int = row + (4 if tool == "axe" else 0)
				var durations: Array[float] = [0.8, 0.8, 1.2, 1.6]
				if tool == "axe":
					durations = [1.0, 0.9, 1.2, 1.5]
				for phase in 4:
					var atlas := AtlasTexture.new()
					atlas.atlas = NEW_ACTIONS
					atlas.region = Rect2(phase * 32, action_row * 32, 32, 32)
					frames.add_frame(action, atlas, durations[phase])
				continue
			var reversed: bool = tool == "watering_can" or (tool == "hoe" and row == 1)
			var poses: Array[int] = [0, 1]
			if reversed:
				poses = [1, 0]
			for phase in 3:
				var atlas := AtlasTexture.new()
				atlas.atlas = ACTION_SHEET
				atlas.region = Rect2(poses[mini(phase, 1)] * 48, (first_row + row) * 48, 48, 48)
				var duration: float = 1.6 if phase == 0 else 0.8
				if tool == "watering_can":
					duration = 1.2 if phase == 0 else 1.5
				frames.add_frame(action, atlas, duration)
			frames.add_frame(action, _make_atlas(sheet, row, 0), 1.2)

	var pickaxe_durations: Array[float] = [0.6, 0.9, 1.4, 0.7, 0.8, 1.2]
	for row: int in ROW_DIRECTIONS.size():
		var action: StringName = StringName("stone_pickaxe_%s" % ROW_DIRECTIONS[row])
		frames.add_animation(action)
		frames.set_animation_loop(action, false)
		frames.set_animation_speed(action, 10.0)
		for phase: int in 6:
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = PICKAXE_ACTIONS
			atlas.region = Rect2(phase * 32, row * 32, 32, 32)
			frames.add_frame(action, atlas, pickaxe_durations[phase])

	for tool_index: int in TOOLS.size():
		for row: int in ROW_DIRECTIONS.size():
			for state: String in ["idle", "walk"]:
				var animation: StringName = StringName("held_%s_%s_%s" % [TOOLS[tool_index], state, ROW_DIRECTIONS[row]])
				frames.add_animation(animation)
				frames.set_animation_speed(animation, WALK_FPS if state == "walk" else IDLE_FPS)
				frames.set_animation_loop(animation, state == "walk")
				for phase: int in (4 if state == "walk" else 1):
					var atlas: AtlasTexture = AtlasTexture.new()
					atlas.atlas = HELD_TOOLS
					atlas.region = Rect2(phase * 32, (tool_index * 4 + row) * 32, 32, 32)
					frames.add_frame(animation, atlas)

	var err := ResourceSaver.save(frames, OUT_PATH)
	print("[build_player_frames] saved=%s err=%d animations=%d" % [OUT_PATH, err, frames.get_animation_names().size()])
	quit(0 if err == OK else 1)


func _make_atlas(sheet: Texture2D, row: int, col: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(
		ORIGIN + col * STEP,
		ORIGIN + row * STEP,
		FRAME_SIZE,
		FRAME_SIZE
	)
	return atlas
