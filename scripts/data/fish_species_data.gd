class_name FishSpeciesData
extends Resource
## 鱼种出现条件：区域、季节、天气、时段与最低渔具等级；weight 只参与抽取权重。

const MINUTE_LIMIT: int = 1560
## 时钟从 06:00 走到次日 02:00，非法时段按这个上限校验。
const MAX_WEIGHT: float = 1000.0
const MAX_MIN_ROD_LEVEL: int = 9
const MAX_ENTRIES: int = 8

@export var id: StringName = &""
@export var display_name: String = ""
@export var regions: Array[StringName] = []
@export var seasons: Array[StringName] = []
@export var weathers: Array[StringName] = []
@export var min_rod_level: int = 0
@export var weight: float = 1.0
@export var min_minute: int = 0
@export var max_minute: int = MINUTE_LIMIT


func is_valid() -> bool:
	if id == &"" or display_name.strip_edges().is_empty(): return false
	if not _names_valid(regions) or not _names_valid(seasons) or not _names_valid(weathers): return false
	if min_rod_level < 0 or min_rod_level > MAX_MIN_ROD_LEVEL: return false
	if not is_finite(weight) or weight <= 0.0 or weight > MAX_WEIGHT: return false
	if min_minute < 0 or max_minute > MINUTE_LIMIT or min_minute > max_minute: return false
	return true


func _names_valid(values: Array[StringName]) -> bool:
	if values.is_empty() or values.size() > MAX_ENTRIES: return false
	var seen: Dictionary[StringName, bool] = {}
	for value: StringName in values:
		if value == &"" or seen.has(value): return false
		seen[value] = true
	return true
