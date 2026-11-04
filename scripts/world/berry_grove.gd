extends Node2D
## 野浆果丛的管理器：固定落点、按位置轮换种类、记下每丛什么时候重新结果。
##
## 落点是脚本扫地图挑的：不压水、不压道具、离出生点和彼此都有距离。
## 三种浆果按 slot 轮换，玩家逛一圈能分辨出"这边是黑莓、那边是醋栗"。

const Bush := preload("res://scripts/world/berry_bush.gd")

const SPOTS: Array[Vector2] = [
	Vector2(88, 94),
	Vector2(248, 126),
	Vector2(344, 158),
	Vector2(88, 190),
	Vector2(456, 222),
	Vector2(264, 254),
	Vector2(120, 286),
	Vector2(360, 318),
]
const KINDS: Array[StringName] = [&"wild_blackberry", &"wild_raspberry", &"wild_gooseberry"]
const COLORS := {
	&"wild_blackberry": Color("3b2a45"),
	&"wild_raspberry": Color("b5324a"),
	&"wild_gooseberry": Color("d8e05c"),
}

var bushes: Dictionary = {}
var _spawned: bool = false


func _ready() -> void:
	add_to_group(&"berry_grove")
	_initialize.call_deferred()


func _initialize() -> void:
	if _spawned:
		return
	_spawned = true
	for slot in SPOTS.size():
		if not bushes.has(slot):
			_spawn(slot)


func _spawn(slot: int) -> void:
	var bush := Bush.new()
	bush.slot = slot
	bush.kind = KINDS[slot % KINDS.size()]
	bush.berry_color = COLORS.get(bush.kind, Color("3b2a45"))
	bush.manager = self
	# 和角色、其他道具共用同一个 Y 排序容器。
	get_parent().add_child(bush)
	bush.global_position = SPOTS[slot]
	bushes[slot] = bush


## 采集后由浆果丛回调，目前只留作以后接成就/提示用。
func on_bush_changed() -> void:
	pass


func ripe_count() -> int:
	var count: int = 0
	for slot: int in bushes.keys():
		if (bushes[slot] as Node).call(&"has_berries"):
			count += 1
	return count


func to_dict() -> Dictionary:
	var rows: Array = []
	for slot: int in bushes.keys():
		rows.append((bushes[slot] as Node).call(&"to_dict"))
	return {&"bushes": rows}


func from_dict(data: Dictionary) -> void:
	_spawned = true
	for slot: int in bushes.keys():
		(bushes[slot] as Node).queue_free()
	bushes.clear()
	for slot in SPOTS.size():
		_spawn(slot)
	for row in data.get(&"bushes", []):
		var entry: Dictionary = row
		var slot: int = int(entry.get(&"slot", -1))
		if bushes.has(slot):
			(bushes[slot] as Node).call(&"from_dict", entry)
