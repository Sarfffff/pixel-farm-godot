extends SceneTree
## 项目冒烟检查：不启动游戏窗口，验证输入映射、玩家场景、地图结构与道具碰撞。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/check/smoke_check.gd
##
## 退出码 0 表示全部通过，1 表示存在失败项（可直接用于提交前自检）。

const MAIN_SCENE := "res://scenes/main.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PLAYER_FRAMES := "res://scenes/player/player_frames.tres"
const FARM_SCENE := "res://scenes/world/farm.tscn"

const EXPECTED_BINDINGS := {
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
}

## 只检查存在性（按键可自定义，不锁死具体键位）
const REQUIRED_ACTIONS: Array[StringName] = [
	&"use_tool", &"mouse_use", &"tool_prev", &"tool_next", &"tool_1", &"tool_2", &"tool_3",
]

## 必须有碰撞体的道具（蘑菇是纯装饰，不在此列）
const SOLID_PROPS: Array[String] = [
	"cottage", "tree_big", "tree_small", "tree_fruit", "bush", "rock", "log",
]

var _failures: int = 0


func _init() -> void:
	_check_input_map()
	_check_player_frames()
	_check_player_scene()
	_check_farm_scene()
	_check_prop_collisions()
	_check_main_scene()

	if _failures == 0:
		print("[smoke_check] PASS")
	else:
		printerr("[smoke_check] FAIL，共 %d 项" % _failures)
	quit(0 if _failures == 0 else 1)


func _fail(message: String) -> void:
	_failures += 1
	printerr("[smoke_check] 失败：%s" % message)


func _check_input_map() -> void:
	for action: StringName in EXPECTED_BINDINGS:
		if not InputMap.has_action(action):
			_fail("缺少输入动作 %s" % action)
			continue
		var bound: Array[int] = []
		for event in InputMap.action_get_events(action):
			var key_event := event as InputEventKey
			if key_event != null:
				bound.append(key_event.physical_keycode)
		for expected: int in EXPECTED_BINDINGS[action]:
			if not bound.has(expected):
				_fail("%s 缺少按键 %d（当前 %s）" % [action, expected, bound])

	for action: StringName in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			_fail("缺少输入动作 %s" % action)
		elif InputMap.action_get_events(action).is_empty():
			_fail("输入动作 %s 没有绑定任何按键" % action)
	print("[smoke_check] 输入映射检查完成")


func _check_player_frames() -> void:
	var frames := load(PLAYER_FRAMES) as SpriteFrames
	if frames == null:
		_fail("无法加载 %s" % PLAYER_FRAMES)
		return
	var names := frames.get_animation_names()
	if names.size() != 8:
		_fail("动画数量应为 8，实际 %d（%s）" % [names.size(), names])
	for direction in ["down", "up", "left", "right"]:
		for prefix in ["idle", "walk"]:
			var animation: StringName = StringName("%s_%s" % [prefix, direction])
			if not frames.has_animation(animation):
				_fail("缺少动画 %s" % animation)
			elif frames.get_frame_count(animation) != (1 if prefix == "idle" else 4):
				_fail("%s 帧数异常：%d" % [animation, frames.get_frame_count(animation)])
	print("[smoke_check] 玩家动画检查完成")


func _check_player_scene() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		_fail("无法加载 %s" % PLAYER_SCENE)
		return
	var player := packed.instantiate() as CharacterBody2D
	if player == null:
		_fail("玩家场景根节点类型不是 CharacterBody2D")
		return
	if player.get_node_or_null("Sprite") == null:
		_fail("玩家场景缺少 Sprite 节点")
	if player.get_node_or_null("Collision") == null:
		_fail("玩家场景缺少 Collision 节点")
	if player.motion_mode != CharacterBody2D.MOTION_MODE_FLOATING:
		_fail("玩家 motion_mode 应为 FLOATING（俯视角）")
	if not player.is_in_group(&"player"):
		_fail("玩家必须加入 player 组（工具栏与耕地系统靠它查找）")
	for signal_name in [&"tool_changed", &"use_requested"]:
		if not player.has_signal(signal_name):
			_fail("玩家缺少信号 %s" % signal_name)
	player.free()
	print("[smoke_check] 玩家场景检查完成")


func _check_farm_scene() -> void:
	var packed := load(FARM_SCENE) as PackedScene
	if packed == null:
		_fail("无法加载 %s" % FARM_SCENE)
		return
	var farm := packed.instantiate() as Node2D
	for layer_name in [
		"Ground", "Water", "Overlay", "Detail", "SoilFringe", "Soil", "Watered", "WaterCollision",
	]:
		if farm.get_node_or_null(layer_name) == null:
			_fail("农场缺少图层 %s" % layer_name)

	var tiller := farm.get_node_or_null("Tiller")
	if tiller == null:
		_fail("农场缺少 Tiller 节点（耕地系统）")
	else:
		if tiller.get_script() == null:
			_fail("Tiller 未挂载 farm_tiller.gd")
		if tiller.get_node_or_null("Cursor") == null:
			_fail("Tiller 缺少 Cursor 高亮框")
	var world := farm.get_node_or_null("World") as Node2D
	if world == null:
		_fail("农场缺少 World 容器")
	else:
		if not world.y_sort_enabled:
			_fail("World 未开启 y_sort_enabled，遮挡排序会失效")
		if world.get_script() == null:
			_fail("World 未挂载遮挡淡出脚本（角色会被建筑/树完全挡住）")
	if farm.get_node_or_null("Bounds") == null:
		_fail("农场缺少 Bounds 边界墙")
	farm.free()
	print("[smoke_check] 农场场景检查完成")


func _check_prop_collisions() -> void:
	for prop_name in SOLID_PROPS:
		var path := "res://scenes/world/props/%s.tscn" % prop_name
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("无法加载道具场景 %s" % path)
			continue
		var prop := packed.instantiate() as Node2D
		if prop.get_node_or_null("Body") == null:
			_fail("道具 %s 缺少 Body 静态碰撞体" % prop_name)
		prop.free()
	print("[smoke_check] 道具碰撞检查完成")


func _check_main_scene() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("无法加载 %s" % MAIN_SCENE)
		return
	var main := packed.instantiate() as Node2D
	if main.get_node_or_null("Farm") == null:
		_fail("main 场景缺少 Farm")
	if main.get_node_or_null("Farm/World/Player") == null:
		_fail("Player 必须位于 Farm/World 下，否则无法与道具互相遮挡")
	var camera := main.get_node_or_null("Camera") as Camera2D
	if camera == null:
		_fail("main 场景缺少 Camera")
	else:
		if camera.world_bounds != Rect2(0, 0, 640, 480):
			_fail("相机 world_bounds 配置错误：%s" % camera.world_bounds)
		if camera.target_path != NodePath("../Farm/World/Player"):
			_fail("相机 target_path 配置错误：%s" % camera.target_path)
	main.free()
	print("[smoke_check] 主场景检查完成")
