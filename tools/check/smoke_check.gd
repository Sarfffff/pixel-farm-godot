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
	&"use_tool", &"mouse_use", &"tool_prev", &"tool_next", &"tool_1", &"tool_2", &"tool_3", &"tool_4", &"tool_5",
	&"toggle_inventory", &"interact", &"next_day",
]

const ITEM_DIR := "res://data/items"

## 必须有碰撞体的道具（蘑菇是纯装饰，不在此列）
const SOLID_PROPS: Array[String] = [
	"cottage", "tree_big", "tree_small", "tree_fruit", "bush", "rock", "log",
]

var _failures: int = 0


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_check_crop_resources()
	_check_input_map()
	_check_player_frames()
	_check_player_scene()
	_check_farm_scene()
	_check_prop_collisions()
	_check_main_scene()
	_check_inventory()

	if _failures == 0:
		print("[smoke_check] PASS")
	else:
		printerr("[smoke_check] FAIL，共 %d 项" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _fail(message: String) -> void:
	_failures += 1
	printerr("[smoke_check] 失败：%s" % message)


## 资源头必须直接以 [ 开头；UTF-8 BOM 会让 Godot 报 Expected '['。
func _check_crop_resources() -> void:
	var directory: DirAccess = DirAccess.open("res://data/crops")
	if directory == null:
		_fail("缺少作物资源目录")
		return
	for filename: String in directory.get_files():
		if not filename.ends_with(".tres"):
			continue
		var path: String = "res://data/crops/" + filename
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.is_empty() or bytes[0] != 91:
			_fail("作物资源须为无 BOM 的 UTF-8，并以 [gd_resource 开头：" + path)
			continue
		var crop: CropData = load(path) as CropData
		if crop == null or crop.stages.is_empty():
			_fail("作物定义无法加载或缺少生长阶段：" + path)
			continue
		for stage: Texture2D in crop.stages:
			if stage == null:
				_fail("作物阶段贴图无法加载：" + path)
	print("[smoke_check] 作物编码、资源加载与阶段贴图检查完成")


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
	# 不锁死总数：工具变多时动画会跟着加，逐项检查已经足够严格。
	if frames.get_animation_names().is_empty():
		_fail("%s 里没有任何动画" % PLAYER_FRAMES)
	for direction in ["down", "up", "left", "right"]:
		for prefix in ["idle", "walk"]:
			var animation: StringName = StringName("%s_%s" % [prefix, direction])
			if not frames.has_animation(animation):
				_fail("缺少动画 %s" % animation)
			elif frames.get_frame_count(animation) != (1 if prefix == "idle" else 4):
				_fail("%s 帧数异常：%d" % [animation, frames.get_frame_count(animation)])
	print("[smoke_check] 玩家动画检查完成")
	for tool: String in ["hoe", "watering_can", "axe", "stone_pickaxe"]:
		for direction in ["down", "up", "left", "right"]:
			var action := StringName("%s_%s" % [tool, direction])
			if not frames.has_animation(action):
				_fail("缺少工具动画 %s" % action)
			elif frames.get_frame_count(action) != (6 if tool == "stone_pickaxe" else 4) or frames.get_animation_loop(action):
				_fail("工具动画帧数或循环设置错误：%s" % action)


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


func _check_inventory() -> void:
	var directory := DirAccess.open(ITEM_DIR)
	if directory == null:
		_fail("缺少物品目录 %s" % ITEM_DIR)
		return
	var item_count: int = 0
	var buyable: int = 0
	var sellable: int = 0
	for file: String in directory.get_files():
		if not file.ends_with(".tres"):
			continue
		var item := load(ITEM_DIR.path_join(file)) as ItemData
		if item == null:
			_fail("物品文件无法加载为 ItemData：%s" % file)
			continue
		if item.id == &"" or item.display_name.is_empty() or item.icon == null:
			_fail("物品定义不完整（id/名称/图标）：%s" % file)
		if item.buy_price > 0:
			buyable += 1
		if item.sell_price > 0:
			sellable += 1
		item_count += 1
	if item_count < 4:
		_fail("物品表只有 %d 项，背包无法体现堆叠与分类" % item_count)
	if buyable == 0:
		_fail("物品表里没有 buy_price > 0 的商品，商店买不到东西")
	if sellable == 0:
		_fail("物品表里没有 sell_price > 0 的商品，商店卖不出东西")

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("无法加载 %s" % MAIN_SCENE)
		return
	var main := packed.instantiate() as Node2D
	var inventory := main.get_node_or_null("Systems/Inventory")
	if inventory == null:
		_fail("main 场景缺少 Systems/Inventory（背包系统）")
	elif not inventory.is_in_group(&"inventory"):
		_fail("Inventory 未加入 inventory 组，砍树掉落找不到它")
	elif not inventory.has_method(&"add_item"):
		_fail("Inventory 未挂载 inventory.gd")
	if main.get_node_or_null("UI/InventoryPanel") == null:
		_fail("main 场景缺少 UI/InventoryPanel 背包面板")
	if main.get_node_or_null("UI/Toast") == null:
		_fail("main 场景缺少 UI/Toast 入包提示")
	if main.get_node_or_null("Systems/Economy") == null:
		_fail("main 场景缺少 Systems/Economy 金币系统")
	if main.get_node_or_null("UI/HUD") == null:
		_fail("main 场景缺少 UI/HUD 金币条")
	if main.get_node_or_null("UI/ShopPanel") == null:
		_fail("main 场景缺少 UI/ShopPanel 商店面板")
	# 店主已搬进店内（P0-4），农场侧只保留店门
	if main.get_node_or_null("Farm/World/ShopDoor") == null:
		_fail("main 场景缺少 Farm/World/ShopDoor 店门")
	if main.get_node_or_null("UI/DialoguePanel") == null:
		_fail("main 场景缺少 UI/DialoguePanel 对话框")
	if main.get_node_or_null("Systems/Time") == null:
		_fail("main 场景缺少 Systems/Time 时间系统")
	elif not main.get_node("Systems/Time").has_signal(&"day_started"):
		_fail("时间系统缺少 day_started 信号，作物无法按天结算")
	if main.get_node_or_null("Systems/Save") == null:
		_fail("main 场景缺少 Systems/Save 存档系统")
	if main.get_node_or_null("UI/DaySummary") == null:
		_fail("main 场景缺少 UI/DaySummary 睡前结算面板")
	if main.get_node_or_null("Farm/World/CottageDoor") == null:
		_fail("main 场景缺少 Farm/World/CottageDoor 进屋交互点")
	if main.get_node_or_null("Systems/HouseManager") == null:
		_fail("main 场景缺少 Systems/HouseManager")
	if main.get_node_or_null("DayNightTint") == null:
		_fail("main 场景缺少 DayNightTint 昼夜色调")
	if main.get_node_or_null("UI/PauseMenu") == null:
		_fail("main 场景缺少 UI/PauseMenu 暂停菜单")
	main.free()

	# 标题界面：主场景应指向它，且三个按钮齐全
	# 编辑器可能把主场景存成 uid:// 引用，这里只要求目标文件名对得上
	if not String(ProjectSettings.get_setting("application/run/main_scene", "")).contains("main_menu"):
		_fail("项目主场景应为标题界面 main_menu.tscn")
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as Control
	if menu == null:
		_fail("无法加载标题界面场景")
	else:
		for node_name: String in ["ContinueButton", "NewButton", "QuitButton"]:
			if menu.get_node_or_null("MainFrame/VBox/%s" % node_name) == null:
				_fail("标题界面缺少按钮 %s" % node_name)
		if not menu.get_node_or_null("%SlotList") is Container:
			_fail("标题界面缺少存档槽位列表")
		menu.free()

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody2D
	if not player.has_method(&"set_input_locked"):
		_fail("玩家缺少 set_input_locked，打开背包时锁不住移动与工具输入")
	player.free()
	print("[smoke_check] 背包检查完成（%d 种物品）" % item_count)
