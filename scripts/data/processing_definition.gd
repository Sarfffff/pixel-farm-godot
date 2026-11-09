class_name ProcessingDefinition
extends Resource
## 设备加工配方：只声明可用设备类型与整批物料，不保存解锁账本或运行状态。

@export var id: StringName = &""
## 允许使用此配方的设备类型ID；一台设备可对应多个配方。
@export var device_types: Array[StringName] = []
@export var ingredients: Dictionary[StringName, int] = {}
@export var products: Dictionary[StringName, int] = {}
## 加工天数，从开始当日算起至少要到下一日才可领取。
@export var days: int = 1

const MAX_DAYS: int = 1000000
const MAX_AMOUNT: int = 1000000
const MAX_DEVICE_TYPES: int = 8
const MAX_ITEM_KINDS: int = 8


func is_valid() -> bool:
	if id == &"" or device_types.is_empty() or device_types.size() > MAX_DEVICE_TYPES: return false
	if ingredients.is_empty() or products.is_empty(): return false
	if days < 1 or days > MAX_DAYS: return false
	var seen: Dictionary[StringName, bool] = {}
	for type_id: StringName in device_types:
		if type_id == &"" or seen.has(type_id): return false
		seen[type_id] = true
	for amounts: Dictionary in [ingredients, products]:
		if amounts.size() > MAX_ITEM_KINDS: return false
		for item: StringName in amounts:
			if item == &"" or int(amounts[item]) <= 0 or int(amounts[item]) > MAX_AMOUNT: return false
	return true
