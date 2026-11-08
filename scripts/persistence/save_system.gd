class_name SaveSystem
extends Node
## 存档：三个槽位，写 user://save_<n>.json，顶层带 version 与 saved_at。
##
## 读档缺字段一律走默认值；文件损坏时改名隔离并当作空槽，保证坏档不会让游戏起不来。
## 加入 save 组，方便其它系统手动触发。

signal saved(slot: int)
signal load_failed(reason: String)
signal restored
## 合法快照恢复前取消瞬时表现，避免旧过场继续操作新世界。
signal restoring

const SLOT_COUNT: int = 3
const SAVE_PATH_FORMAT: String = "user://save_%d.json"
const Migrations := preload("res://scripts/persistence/save_migrations.gd")
const Registry := preload("res://scripts/persistence/snapshot_registry.gd")
const JsonStore := preload("res://scripts/persistence/json_save_store.gd")
const StorePort := preload("res://scripts/persistence/save_store.gd")
const VERSION: int = Migrations.CURRENT_VERSION

var storage: StorePort = JsonStore.new()
var snapshots := Registry.new()
var _write_allowed: bool = true
## 主菜单选好槽位后写进 Engine meta，进游戏时 SaveSystem 读它决定当前槽位。
const PENDING_SLOT_META: StringName = &"pending_save_slot"
## 新游戏起名后同样用 Engine meta 传给游戏内，用一次就清掉。
const PENDING_NAME_META: StringName = &"pending_save_name"
const DEFAULT_NAME: String = "我的农场"

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
		preload("res://scripts/platform/app_lifecycle.gd").quit(get_tree())


## 指定槽位的文件路径；不传则用当前槽位。
func save_path(slot: int = -1) -> String:
	var target: int = current_slot if slot < 0 else slot
	return SAVE_PATH_FORMAT % clampi(target, 1, SLOT_COUNT)


func has_save(slot: int = -1) -> bool:
	return FileAccess.file_exists(save_path(slot)) or FileAccess.file_exists(save_path(slot) + ".bak")


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
	parsed = Migrations.migrate(parsed)
	if parsed.is_empty():
		return {&"slot": slot, &"exists": true, &"compatible": false, &"day": 1, &"coins": 0, &"name": "格式不兼容", &"saved_at": 0}
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
	# 元数据查询器没有运行中快照，不能在标题关闭时覆盖正式进度。
	if not _write_allowed or not snapshots.has_sections():
		return false
	if not storage.write(save_path(), collect()):
		push_warning("[save] 保存失败，原档保留：%s" % error_string(storage.last_error))
		return false
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
	var version: Variant = data.get("version", 1)
	if (version is int or version is float) and version > VERSION:
		if target == current_slot: _write_allowed = false
		load_failed.emit("存档来自更高版本")
		return false
	if Migrations.migrate(data).is_empty():
		if target == current_slot: _write_allowed = false
		load_failed.emit("存档格式不受支持")
		return false
	use_slot(target)
	apply(data)
	_write_allowed = true
	return true


## 收集当前局面；某个系统缺失时跳过对应字段，读档会走默认值。
func collect() -> Dictionary:
	var data: Dictionary = snapshots.collect()
	data[&"version"] = VERSION
	data[&"saved_at"] = int(Time.get_unix_time_from_system())
	data[&"name"] = save_name
	return data


## 运行时恢复和文件读写分离；全部参与者恢复之后才发布时间与导航刷新。
func apply(data: Dictionary) -> void:
	var migrated: Dictionary = Migrations.migrate(data)
	if migrated.is_empty():
		return
	restoring.emit()
	var loaded_name := String(migrated.get("name", "")).strip_edges()
	if not loaded_name.is_empty():
		save_name = loaded_name
	snapshots.restore(migrated)
	restored.emit()


## 只改存档里的农场名，其余字段原样保留；槽位为空时返回 false。
func rename_save(slot: int, new_name: String) -> bool:
	var data := _read(slot)
	if data.is_empty():
		return false
	var trimmed := new_name.strip_edges().left(16)
	data[&"name"] = trimmed if not trimmed.is_empty() else DEFAULT_NAME
	if not storage.write(save_path(slot), data):
		return false
	if slot == current_slot:
		save_name = String(data[&"name"])
	return true


func delete_save(slot: int = -1) -> void:
	var path := save_path(slot)
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

	if slot < 0 or slot == current_slot:
		_write_allowed = true


func delete_all() -> void:
	for slot in range(1, SLOT_COUNT + 1):
		delete_save(slot)


## 读 + 解析；损坏时返回空字典，由调用方决定是否隔离。
func _read(slot: int) -> Dictionary:
	var document: Dictionary = storage.read(save_path(slot))
	if document.is_empty():
		document = storage.read(save_path(slot) + ".bak")
	return document


## 坏档改名留档，下次启动就当空槽，不会反复报错。
func _quarantine(slot: int) -> void:
	var path := save_path(slot)
	for suffix: String in ["", ".bak"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		var source: String = ProjectSettings.globalize_path(path + suffix)
		if DirAccess.copy_absolute(source, source + ".broken") == OK:
			DirAccess.remove_absolute(source)
