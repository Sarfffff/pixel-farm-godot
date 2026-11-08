class_name StoryCondition
extends Resource
## 外部事实只经 query(kind, key) 注入；事件不保存任务、关系或日期的副本。

@export_enum("location", "day", "minute", "weather", "relationship", "quest") var kind: String = "location"
@export var key: StringName = &""
## 类别条件：地点/天气/任务状态的任意一个匹配。
@export var allowed: Array[StringName] = []
## 数值条件：闭区间；minute 的 minimum > maximum 表示跨午夜。
@export var minimum: int = 0
@export var maximum: int = 2147483647


func is_valid() -> bool:
	if kind in ["location", "weather", "quest"]:
		return not allowed.is_empty() and (kind != "quest" or key != &"")
	if kind == "minute":
		return minimum >= 0 and maximum >= 0 and minimum < 1440 and maximum < 1440
	return kind in ["day", "relationship"] and minimum >= 0 and maximum >= minimum and (kind != "relationship" or key != &"")


func matches(value: Variant) -> bool:
	if not is_valid(): return false
	if kind in ["location", "weather", "quest"]:
		return (value is String or value is StringName) and allowed.has(StringName(value))
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT: return false
	var number: float = float(value)
	if not is_finite(number) or number != floor(number): return false
	if kind == "minute" and minimum > maximum:
		return number >= 0 and number < 1440 and (number >= minimum or number <= maximum)
	return number >= minimum and number <= maximum
