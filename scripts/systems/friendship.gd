extends Node
## 村民好感度（`friendship` 组）：聊天与送礼累积，分 5 档。
##
## 只记点数，不存"今天聊过谁"——后者是当天状态，跨天自动清空即可。
## 数值刻意做得小：一次聊天 +2、一次送礼 +10（喜欢 +20），
## 一档到下一档大约要 10 次互动，慢一点但不至于卡死。

const LEVELS: Array[String] = ["陌生", "熟人", "朋友", "好友", "挚友"]
## 进入各档所需的累计点数
const THRESHOLDS: Array[int] = [0, 20, 80, 160, 240]
const TALK_POINTS: int = 2
const GIFT_POINTS: int = 10
const LIKED_BONUS: int = 10
const MAX_POINTS: int = 999

## npc_id -> 点数
var points: Dictionary = {}
## 当天已经聊过的 npc_id（跨天清空，防刷）
var _talked_today: Dictionary = {}


func _ready() -> void:
	add_to_group(&"friendship")
	_connect_clock.call_deferred()


func _connect_clock() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(func(_day: int) -> void: _talked_today.clear())


func points_of(npc_id: StringName) -> int:
	return int(points.get(npc_id, 0))


func level_index(npc_id: StringName) -> int:
	var value: int = points_of(npc_id)
	var index: int = 0
	for i in THRESHOLDS.size():
		if value >= THRESHOLDS[i]:
			index = i
	return index


func level_name(npc_id: StringName) -> String:
	return LEVELS[clampi(level_index(npc_id), 0, LEVELS.size() - 1)]


## 到下一档还差多少点；已满级返回 0。
func points_to_next(npc_id: StringName) -> int:
	var index: int = level_index(npc_id)
	if index >= THRESHOLDS.size() - 1:
		return 0
	return maxi(0, THRESHOLDS[index + 1] - points_of(npc_id))


## 聊天：每天每人只记一次，返回本次获得的点数。
func talked(npc_id: StringName) -> int:
	if npc_id == &"" or _talked_today.has(npc_id):
		return 0
	_talked_today[npc_id] = true
	return add_points(npc_id, TALK_POINTS)


## 送礼：喜欢的物品额外加成。
func gift(npc_id: StringName, liked: bool) -> int:
	return add_points(npc_id, GIFT_POINTS + (LIKED_BONUS if liked else 0))


func add_points(npc_id: StringName, amount: int) -> int:
	if npc_id == &"" or amount <= 0:
		return 0
	var before_level: int = level_index(npc_id)
	var value: int = mini(points_of(npc_id) + amount, MAX_POINTS)
	points[npc_id] = value
	if level_index(npc_id) != before_level:
		_announce_level_up(npc_id)
	return amount


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in points.keys():
		out[String(key)] = int(points[key])
	return {"points": out}


func from_dict(data: Dictionary) -> void:
	points.clear()
	_talked_today.clear()
	var stored: Dictionary = data.get("points", {})
	for key: Variant in stored.keys():
		points[StringName(key)] = maxi(0, int(stored[key]))


func _announce_level_up(npc_id: StringName) -> void:
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast") if get_tree().current_scene != null else null
	if toast != null and toast.has_method(&"show_message"):
		toast.call(&"show_message", "和 %s 的关系变成「%s」了" % [String(npc_id), level_name(npc_id)])
