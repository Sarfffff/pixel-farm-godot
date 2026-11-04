extends SceneTree
## 玩家帧资源生成器
##
## 从 basic_charakter_spritesheet.png 切出 4 方向 × 4 帧的行走动画与单帧待机动画，
## 写出 res://scenes/player/player_frames.tres。
##
## 图集实测布局：帧尺寸 16×16，列/行间隔 48px，首个帧左上角在 (16,16)；
## 行顺序为 下 / 上 / 左 / 右（左与右互为镜像，见 docs/02 实际记录）。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build_player_frames.gd

const SHEET_PATH := "res://assets/game/characters/basic_charakter_spritesheet.png"
const OUT_PATH := "res://scenes/player/player_frames.tres"

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
