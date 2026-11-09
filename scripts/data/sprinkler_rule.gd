class_name SprinklerRule
extends Resource
## 洒水器覆盖规则：type_id 匹配设备类型，offset_cells 是相对设备锚点格的偏移（会随朝向旋转）。

## 单个轴向最大偏移；超出的规则视为配置错误，不允许把覆盖范围扩到整张地图。
const MAX_OFFSET: int = 8

@export var type_id: StringName = &""
@export var offset_cells: Array[Vector2i] = []


func is_valid() -> bool:
	if type_id == &"" or offset_cells.is_empty(): return false
	var seen: Dictionary[Vector2i, bool] = {}
	for offset: Vector2i in offset_cells:
		if absi(offset.x) > MAX_OFFSET or absi(offset.y) > MAX_OFFSET: return false
		if seen.has(offset): return false
		seen[offset] = true
	return true
