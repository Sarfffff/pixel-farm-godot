extends Node2D
## 鸡窝：每天早上按鸡的数量下蛋，地上最多留 3 颗；蛋的坐标进存档。
##
## 蛋生成到父节点（World）而不是自己下面，这样蛋、鸡、房子共用同一套 Y 排序。

const EGG_SCENE: PackedScene = preload("res://scenes/world/egg.tscn")
## 地上最多留几颗蛋：捡不完也不会堆满地图。
const MAX_EGGS: int = 3
## 窝周围的候选落点（相对自身）：左右各两个、正前方一个。
const EGG_SPOTS: Array[Vector2] = [
	Vector2(-14, 6), Vector2(0, 10), Vector2(14, 6), Vector2(-22, 0), Vector2(22, 0)
]
## 两个蛋之间至少空这么多像素，避免叠在一起分不清。
const MIN_EGG_GAP: float = 10.0

var _eggs: Array[Node2D] = []


func _ready() -> void:
	add_to_group(&"chicken_coop")
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(_on_day_started)


## 每天开头：每只鸡一颗，但地上不超过 MAX_EGGS。
func _on_day_started(_day: int) -> void:
	var room: int = MAX_EGGS - _eggs.size()
	var want: int = mini(_chicken_count(), maxi(room, 0))
	for i in want:
		var spot := _free_spot()
		if spot == Vector2.INF:
			break
		_spawn_egg(spot)


func _chicken_count() -> int:
	return get_tree().get_nodes_in_group(&"chicken").size()


## 找一个没被占用的落点；全都被占就返回 Vector2.INF。
func _free_spot() -> Vector2:
	var order: Array[Vector2] = EGG_SPOTS.duplicate()
	order.shuffle()
	for spot: Vector2 in order:
		var world: Vector2 = to_global(spot)
		var crowded: bool = false
		for egg in _eggs:
			if is_instance_valid(egg) and egg.global_position.distance_to(world) < MIN_EGG_GAP:
				crowded = true
				break
		if not crowded:
			return spot
	return Vector2.INF


func _spawn_egg(local_spot: Vector2) -> void:
	var egg := EGG_SCENE.instantiate() as Node2D
	get_parent().add_child(egg)
	egg.global_position = to_global(local_spot)
	egg.set(&"coop", self)
	_eggs.append(egg)


## 蛋被捡走时调用，把它从列表里去掉，存档就不会记着这颗蛋。
func forget_egg(egg: Node2D) -> void:
	_eggs.erase(egg)


func egg_count() -> int:
	_prune()
	return _eggs.size()


func to_dict() -> Dictionary:
	_prune()
	var coords: Array = []
	for egg in _eggs:
		coords.append([egg.global_position.x, egg.global_position.y])
	return {&"eggs": coords}


func from_dict(data: Dictionary) -> void:
	clear_eggs()
	for entry in data.get(&"eggs", []):
		var pair: Array = entry
		if pair.size() < 2:
			continue
		var egg := EGG_SCENE.instantiate() as Node2D
		get_parent().add_child(egg)
		egg.global_position = Vector2(float(pair[0]), float(pair[1]))
		egg.set(&"coop", self)
		_eggs.append(egg)


func clear_eggs() -> void:
	for egg in _eggs:
		if is_instance_valid(egg):
			egg.queue_free()
	_eggs.clear()


## 蛋可能被别的途径 free 掉（换场景、测试清理），出列表前先剔一遍。
func _prune() -> void:
	var alive: Array[Node2D] = []
	for egg in _eggs:
		if is_instance_valid(egg) and not egg.is_queued_for_deletion():
			alive.append(egg)
	_eggs = alive
