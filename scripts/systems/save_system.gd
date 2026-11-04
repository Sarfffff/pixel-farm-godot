class_name SaveSystem
extends Node
## 存档：三个槽位，写 user://save_<n>.json，顶层带 version 与 saved_at。
##
## 读档缺字段一律走默认值；文件损坏时改名隔离并当作空槽，保证坏档不会让游戏起不来。
## 加入 save 组，方便其它系统手动触发。

signal saved(slot: int)
signal load_failed(reason: String)

const SLOT_COUNT: int = 3
const SAVE_PATH_FORMAT: String = "user://save_%d.json"
const VERSION: int = 1
## 主菜单选好槽位后写进 Engine meta，进游戏时 SaveSystem 读它决定当前槽位。
const PENDING_SLOT_META: StringName = &"pending_save_slot"
## 新游戏起名后同样用 Engine meta 传给游戏内，用一次就清掉。
const PENDING_NAME_META: StringName = &"pending_save_name"
const DEFAULT_NAME: String = "我的农场"
## 用 preload 取默认时间，避免依赖 TimeSystem 的全局类名。
const TimeScript := preload("res://scripts/systems/time_system.gd")

## 测试脚本与标题界面会置 false，避免在进入农场前就读档。
@export var autoload_enabled: bool = true

## 当前正在使用的槽位（1 起）。
var current_slot: int = 1
## 当前存档的农场名，标题界面的槽位列表用它区分三个档。
var save_name: String = DEFAULT_NAME


func _ready() -> void:
	add_to_group(&"save")
	current_slot = clampi(int(Engine.get_meta(PENDING_SLOT_META, 1)), 1, SLOT_COUNT)
	var pending_name := String(Engine.get_meta(PENDING_NAME_META, "")).strip_edges()
	if not pending_name.is_empty():
		save_name = pending_name
		Engine.set_meta(PENDING_NAME_META, "")
	# 等所有系统 _ready 完再读档，否则耕地/背包还没建好。
	_restore_on_start.call_deferred()
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	# 关窗口时先存一次再退出，避免玩家白玩一天。
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()


## 指定槽位的文件路径；不传则用当前槽位。
func save_path(slot: int = -1) -> String:
	var target: int = current_slot if slot < 0 else slot
	return SAVE_PATH_FORMAT % clampi(target, 1, SLOT_COUNT)


func has_save(slot: int = -1) -> bool:
	return FileAccess.file_exists(save_path(slot))


func any_save() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_save(slot):
			return true
	return false


## 主菜单用：槽位是否存在、第几天、多少金币、保存时间（unix 秒）。
func slot_summary(slot: int) -> Dictionary:
	if not has_save(slot):
		return {&"slot": slot, &"exists": false}
	var parsed := _read(slot)
	if parsed.is_empty():
		return {&"slot": slot, &"exists": false}
	var clock: Dictionary = parsed.get("time", {})
	var farm_name := String(parsed.get("name", "")).strip_edges()
	return {
		&"slot": slot,
		&"exists": true,
		&"name": farm_name if not farm_name.is_empty() else DEFAULT_NAME,
		&"day": maxi(1, int(clock.get("day", 1))),
		&"coins": maxi(0, int(parsed.get("coins", 0))),
		&"saved_at": int(parsed.get("saved_at", 0)),
	}


## 切到某个槽位（主菜单选档后调用），之后的保存都写这里。
func use_slot(slot: int) -> void:
	current_slot = clampi(slot, 1, SLOT_COUNT)
	Engine.set_meta(PENDING_SLOT_META, current_slot)


func _restore_on_start() -> void:
	if not autoload_enabled:
		return
	if has_save():
		load_game()
		return
	# 新开局先落一次档：标题界面的槽位列表立刻能看到农场名与天数。
	save_game()


func save_game() -> bool:
	var file := FileAccess.open(save_path(), FileAccess.WRITE)
	if file == null:
		push_warning("[save] 无法写入存档 %s" % save_path())
		return false
	file.store_string(JSON.stringify(collect(), "\t"))
	file.close()
	saved.emit(current_slot)
	return true


func load_game(slot: int = -1) -> bool:
	var target: int = current_slot if slot < 0 else slot
	if not has_save(target):
		load_failed.emit("这个槽位还没有存档")
		return false
	var data := _read(target)
	if data.is_empty():
		_quarantine(target)
		load_failed.emit("存档损坏")
		return false
	if int(data.get("version", 0)) > VERSION:
		load_failed.emit("存档来自更高版本")
		return false
	use_slot(target)
	apply(data)
	return true


## 收集当前局面；某个系统缺失时跳过对应字段，读档会走默认值。
func collect() -> Dictionary:
	var data: Dictionary = {
		&"version": VERSION,
		&"saved_at": int(Time.get_unix_time_from_system()),
		&"name": save_name,
	}
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		data[&"time"] = {&"day": time.day, &"minutes": time.minutes}
	var economy := get_tree().get_first_node_in_group(&"economy") as Economy
	if economy != null:
		data[&"coins"] = economy.coins
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	if inventory != null:
		data[&"inventory"] = inventory.to_dict()
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	if tiller != null and tiller.has_method(&"to_dict"):
		data[&"farm"] = tiller.to_dict()
	var player := get_tree().get_first_node_in_group(&"player") as CharacterBody2D
	if player != null:
		# 人在屋里时记门外坐标，否则读档会落在室内那套偏移坐标上。
		var spot: Vector2 = player.global_position
		var house := get_tree().get_first_node_in_group(&"house")
		if house != null and house.has_method(&"save_position"):
			spot = house.save_position()
		data[&"player"] = {&"x": spot.x, &"y": spot.y}
	# 鸡窝只存地上的蛋；鸡自己在附近随机游走，回来重新出生即可。
	var coop := get_tree().get_first_node_in_group(&"chicken_coop")
	if coop != null and coop.has_method(&"to_dict"):
		data[&"coop"] = coop.to_dict()
	var community := get_tree().get_first_node_in_group(&"community")
	if community != null and community.has_method(&"to_dict"):
		data[&"community"] = community.to_dict()
	var orders := get_tree().get_first_node_in_group(&"orders")
	if orders != null and orders.has_method(&"to_dict"):
		data[&"orders"] = orders.to_dict()
	var weather := get_tree().get_first_node_in_group(&"weather")
	if weather != null and weather.has_method(&"to_dict"):
		data[&"weather"] = weather.to_dict()
	var stamina := get_tree().get_first_node_in_group(&"stamina")
	if stamina != null and stamina.has_method(&"to_dict"):
		data[&"stamina"] = stamina.to_dict()
	for group: StringName in [&"upgrades", &"tutorial", &"forage", &"farm_activities", &"friendship", &"berry_grove"]:
		var system := get_tree().get_first_node_in_group(group)
		if system != null:
			data[group] = system.to_dict()
	return data


## 把存档内容套回运行时；字段缺失或类型不对都退回默认值。
func apply(data: Dictionary) -> void:
	var loaded_name := String(data.get("name", "")).strip_edges()
	if not loaded_name.is_empty():
		save_name = loaded_name
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		var clock: Dictionary = data.get("time", {})
		time.day = maxi(1, int(clock.get("day", 1)))
		time.minutes = clampi(
			int(clock.get("minutes", TimeScript.START_MINUTES)), 0, TimeScript.CLOSE_MINUTES
		)
		time.reset_clock()
		time.time_changed.emit(time.day, time.minutes)

	var economy := get_tree().get_first_node_in_group(&"economy") as Economy
	if economy != null:
		economy.coins = maxi(0, int(data.get("coins", Economy.STARTING_COINS)))
		economy.changed.emit(economy.coins)

	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var inventory_data: Dictionary = data.get("inventory", {})
	if inventory != null and not inventory_data.is_empty():
		inventory.from_dict(inventory_data)

	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	var farm: Dictionary = data.get("farm", {})
	if tiller != null and tiller.has_method(&"from_dict") and not farm.is_empty():
		tiller.from_dict(farm)

	var player := get_tree().get_first_node_in_group(&"player") as CharacterBody2D
	var position_data: Dictionary = data.get("player", {})
	if player != null and not position_data.is_empty():
		player.global_position = Vector2(
			float(position_data.get("x", player.global_position.x)),
			float(position_data.get("y", player.global_position.y))
		)

	var coop := get_tree().get_first_node_in_group(&"chicken_coop")
	var coop_data: Dictionary = data.get("coop", {})
	if coop != null and coop.has_method(&"from_dict") and not coop_data.is_empty():
		coop.from_dict(coop_data)

	# 社区阶段要在订单之前恢复：订单池按解锁阶段筛。
	var community := get_tree().get_first_node_in_group(&"community")
	var community_data: Dictionary = data.get("community", {})
	if community != null and community.has_method(&"from_dict") and not community_data.is_empty():
		community.from_dict(community_data)

	var orders := get_tree().get_first_node_in_group(&"orders")
	var orders_data: Dictionary = data.get("orders", {})
	if orders != null and orders.has_method(&"from_dict") and not orders_data.is_empty():
		orders.from_dict(orders_data)

	# 天气要在时间之后恢复：它用当天日期记"已经掷过骰子"。
	var weather := get_tree().get_first_node_in_group(&"weather")
	var weather_data: Dictionary = data.get("weather", {})
	if weather != null and weather.has_method(&"from_dict") and not weather_data.is_empty():
		weather.from_dict(weather_data)

	var stamina := get_tree().get_first_node_in_group(&"stamina")
	var stamina_data: Dictionary = data.get("stamina", {})
	if stamina != null and stamina.has_method(&"from_dict") and not stamina_data.is_empty():
		stamina.from_dict(stamina_data)

	var berries := get_tree().get_first_node_in_group(&"berry_grove")
	var berry_data: Dictionary = data.get("berries", {})
	if berries != null and berries.has_method(&"from_dict") and not berry_data.is_empty():
		berries.from_dict(berry_data)
	for group: StringName in [&"upgrades", &"tutorial", &"forage", &"farm_activities", &"friendship", &"berry_grove"]:
		var system := get_tree().get_first_node_in_group(group)
		if system != null:
			system.from_dict(data.get(String(group), {}))


## 只改存档里的农场名，其余字段原样保留；槽位为空时返回 false。
func rename_save(slot: int, new_name: String) -> bool:
	var data := _read(slot)
	if data.is_empty():
		return false
	var trimmed := new_name.strip_edges().left(16)
	data[&"name"] = trimmed if not trimmed.is_empty() else DEFAULT_NAME
	var file := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if slot == current_slot:
		save_name = String(data[&"name"])
	return true


func delete_save(slot: int = -1) -> void:
	var path := save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func delete_all() -> void:
	for slot in range(1, SLOT_COUNT + 1):
		delete_save(slot)


## 读 + 解析；损坏时返回空字典，由调用方决定是否隔离。
func _read(slot: int) -> Dictionary:
	var file := FileAccess.open(save_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## 坏档改名留档，下次启动就当空槽，不会反复报错。
func _quarantine(slot: int) -> void:
	var path := save_path(slot)
	var broken_path: String = path + ".broken"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(broken_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
