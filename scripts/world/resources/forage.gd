extends Node2D
## 固定落点便于辨认和存档，每天最多补三丛，不因读档重复刷新。

const Patch := preload("res://scripts/world/resources/forage_patch.gd")
const GroundRules := preload("res://scripts/world/farming/farm_ground_rules.gd")
const SPOTS: Array[Vector2] = [
	Vector2(296, 232), Vector2(328, 232), Vector2(360, 232), Vector2(392, 232), Vector2(424, 232),
	Vector2(296, 248), Vector2(328, 248), Vector2(360, 248), Vector2(392, 248), Vector2(424, 248),
]
var patches: Dictionary = {}
var _last_day: int = 1


func _ready() -> void:
	add_to_group(&"forage")
	_initialize.call_deferred()


func _initialize() -> void:
	for index in SPOTS.size():
		_spawn(index)
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		time.day_started.connect(_on_day_started)


func _spawn(index: int) -> void:
	var farm: Node2D = get_parent().get_parent() as Node2D
	if not GroundRules.is_clear(farm, Rect2(SPOTS[index] - Vector2(8, 10), Vector2(16, 13))):
		return
	var patch := Patch.new()
	patch.patch_id = index
	patch.manager = self
	# 与角色和道具共享 Y 排序。
	get_parent().add_child(patch)
	patch.global_position = SPOTS[index]
	patches[index] = patch


func remove_patch(index: int) -> void:
	if patches.has(index):
		var patch: Node = patches[index]
		patch.remove_from_group(&"interactable")
		patch.remove_from_group(&"forage_patch")
		patch.queue_free()
		patches.erase(index)


func _on_day_started(day: int) -> void:
	if day <= _last_day:
		return
	_last_day = day
	var added: int = 0
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	for index in SPOTS.size():
		if tiller != null and tiller.has_tilled_soil(Vector2i(SPOTS[index] / 16.0)):
			continue
		# 只在既有固定空地点补长；玩家占位延后到下一次日结，不在脚下刷新。
		if player != null and player.global_position.distance_to(SPOTS[index]) < 16.0:
			continue
		if not patches.has(index):
			_spawn(index)
			added += 1
			if added == 3:
				break


func to_dict() -> Dictionary:
	return {&"patches": patches.keys(), &"last_day": _last_day}


func from_dict(data: Dictionary) -> void:
	for index: int in patches.keys():
		remove_patch(index)
	_last_day = maxi(1, int(data.get("last_day", 1)))
	var active: Array = data.get("patches", range(SPOTS.size()))
	for value: Variant in active:
		var index: int = int(value)
		if index >= 0 and index < SPOTS.size() and not patches.has(index):
			_spawn(index)
