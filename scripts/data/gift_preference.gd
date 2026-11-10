class_name GiftPreference
extends Resource
## 单一位 NPC 的礼物偏好配置（运行时只读数据）。
## 好感点数仍唯一归 Friendship；这里只描述喜欢/中性/不喜欢与每周次数上限。

const MAX_WEEKLY_LIMIT: int = 7
const MAX_ENTRIES: int = 16

@export var npc_id: StringName = &""
@export var liked: Array[StringName] = []
@export var neutral: Array[StringName] = []
@export var disliked: Array[StringName] = []
@export var weekly_limit: int = 2


func is_valid() -> bool:
	if npc_id == &"" or weekly_limit <= 0 or weekly_limit > MAX_WEEKLY_LIMIT: return false
	var seen: Dictionary = {}
	if not _unique(liked, seen): return false
	if not _unique(neutral, seen): return false
	if not _unique(disliked, seen): return false
	return true


func _unique(values: Array[StringName], seen: Dictionary) -> bool:
	if values.size() > MAX_ENTRIES: return false
	for value: StringName in values:
		if value == &"" or seen.has(value): return false
		seen[value] = true
	return true
