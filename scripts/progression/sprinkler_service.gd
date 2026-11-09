extends RefCounted
## B3-04 洒水器覆盖计划：纯只读逻辑，不读场景/库存/存档，不发信号，不改传入实例。
##
## 实例字典与放置记录一致，可附带占地：
##   {"type_id": String|StringName, "space_id": String|StringName（缺省 home）,
##    "cell": Vector2i|[x, y], "facing": 0..3, "size": Vector2i|[w, h]（缺省 1x1）}
## 规则偏移相对锚点格，按 facing 旋转；落在设备自身占地上的格子不输出，重复格只保留首次。
## 是否真的浇灌、是否雨天由主线程决定，本服务只给出设备覆盖到的格子。

const Rule := preload("res://scripts/data/sprinkler_rule.gd")
## 与放置/存档相同的坐标上限，异常数据不能把格子铺到地图外。
const MAX_CELL: int = 4096
## 与 DeviceDefinition.footprint 相同的占地上限。
const MAX_FOOTPRINT: int = 8
const REASON_UNCONFIGURED: String = "洒水器规则未配置"
const REASON_SPACE: String = "空间无效"

var _rules: Dictionary[StringName, SprinklerRule] = {}


## 全量校验通过后才替换配置；任一规则非法（空id/偏移超8格/偏移或type_id重复）返回false并保留原规则。
func configure(rules: Array[SprinklerRule]) -> bool:
	if rules.is_empty(): return false
	var accepted: Dictionary[StringName, SprinklerRule] = {}
	for rule: SprinklerRule in rules:
		if rule == null or not rule.is_valid(): return false
		if accepted.has(rule.type_id): return false
		var copy := rule.duplicate(true) as SprinklerRule
		if copy == null: return false
		accepted[rule.type_id] = copy
	_rules = accepted
	return true


## 返回 {cells, devices, skipped, reason}；reason 只在整次计划不可用时非空，单台设备问题计入 skipped。
func plan(instances: Array[Dictionary], space_id: StringName = &"home") -> Dictionary:
	var cells: Array[Vector2i] = []
	if space_id == &"":
		return {"cells": cells, "devices": 0, "skipped": instances.size(), "reason": REASON_SPACE}
	if _rules.is_empty():
		return {"cells": cells, "devices": 0, "skipped": instances.size(), "reason": REASON_UNCONFIGURED}
	var seen: Dictionary[Vector2i, bool] = {}
	var devices: int = 0
	for instance: Dictionary in instances:
		var covered: Dictionary = _covered_cells(instance, space_id)
		if covered.is_empty(): continue
		devices += 1
		var covered_cells: Array[Vector2i] = covered.cells
		for cell: Vector2i in covered_cells:
			if seen.has(cell): continue
			seen[cell] = true
			cells.append(cell)
	return {"cells": cells, "devices": devices, "skipped": instances.size() - devices, "reason": ""}


func release() -> void:
	_rules.clear()


## 合法实例返回 {"cells": Array[Vector2i]}（可能为空：偏移全部落在自身上）；任何非法输入返回 {}。
func _covered_cells(instance: Dictionary, space_id: StringName) -> Dictionary:
	var raw_type: Variant = instance.get("type_id", null)
	if not (raw_type is String or raw_type is StringName): return {}
	var rule: SprinklerRule = _rules.get(StringName(raw_type))
	if rule == null: return {}
	var raw_space: Variant = instance.get("space_id", &"home")
	if not (raw_space is String or raw_space is StringName): return {}
	if StringName(raw_space) != space_id: return {}
	var raw_cell: Variant = _as_cell(instance.get("cell", null))
	if raw_cell == null: return {}
	var anchor: Vector2i = raw_cell
	if absi(anchor.x) > MAX_CELL or absi(anchor.y) > MAX_CELL: return {}
	var raw_facing: Variant = _as_integer(instance.get("facing", 0))
	if raw_facing == null: return {}
	var turn: int = int(raw_facing)
	if turn < 0 or turn > 3: return {}
	var raw_size: Variant = instance.get("size", instance.get("footprint", Vector2i.ONE))
	var parsed_size: Variant = _as_cell(raw_size)
	if parsed_size == null: return {}
	var size: Vector2i = parsed_size
	if size.x < 1 or size.y < 1 or size.x > MAX_FOOTPRINT or size.y > MAX_FOOTPRINT: return {}
	# 占地朝向与 DeviceDefinition.cells 一致：奇数朝向交换长宽，始终沿 +x/+y 展开。
	var body: Dictionary[Vector2i, bool] = {}
	var span: Vector2i = size if turn % 2 == 0 else Vector2i(size.y, size.x)
	for y: int in span.y:
		for x: int in span.x:
			body[anchor + Vector2i(x, y)] = true
	var result: Array[Vector2i] = []
	for offset: Vector2i in rule.offset_cells:
		var cell: Vector2i = anchor + rotate(offset, turn)
		if body.has(cell): continue
		if absi(cell.x) > MAX_CELL or absi(cell.y) > MAX_CELL: return {}
		result.append(cell)
	return {"cells": result}


## 偏移随朝向做 90° 旋转，方向与占地交换长宽保持一致（facing 1 时 +x 变 +y）。
static func rotate(offset: Vector2i, facing: int) -> Vector2i:
	match facing:
		1: return Vector2i(-offset.y, offset.x)
		2: return Vector2i(-offset.x, -offset.y)
		3: return Vector2i(offset.y, -offset.x)
	return offset


## 接受 Vector2i 或 [x, y]，其他结构一律拒绝。
static func _as_cell(value: Variant) -> Variant:
	if value is Vector2i: return value
	if value is Array:
		var pair: Array = value
		if pair.size() != 2: return null
		var x: Variant = _as_integer(pair[0])
		var y: Variant = _as_integer(pair[1])
		if x == null or y == null: return null
		return Vector2i(int(x), int(y))
	return null


## 只接受整数或整值浮点；bool、字符串、NaN 与超范围数值都不能伪装成坐标。
static func _as_integer(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT: return value
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		if is_finite(number) and number == floor(number) and absf(number) <= 1000000.0: return int(number)
	return null
