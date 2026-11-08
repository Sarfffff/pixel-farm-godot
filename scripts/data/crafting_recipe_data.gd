class_name CraftingRecipeData
extends Resource
## 工作台即时制作配置；不与按天加工配方混用。

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var purpose: String = ""
## 说明配方来源，动态资格只由注入端口查询，不保存解锁账本。
@export var unlock_source: String = "第一章奖励"
@export var requires_chapter: bool = true
@export var requires_placement: bool = false
## 当前工作台只提交即时配方；非零耗时须接设备生产用例后才开放。
@export var duration_seconds: float = 0.0
@export var ingredients: Dictionary[StringName, int] = {}
@export var products: Dictionary[StringName, int] = {}

const MAX_ITEM_AMOUNT: int = 2147483647


func is_valid() -> bool:
	if id == &"" or title.strip_edges().is_empty() or ingredients.is_empty() or products.is_empty() or not is_finite(duration_seconds) or duration_seconds < 0.0:
		return false
	for amounts: Dictionary in [ingredients, products]:
		for item: StringName in amounts:
			if item == &"" or int(amounts[item]) <= 0 or int(amounts[item]) > MAX_ITEM_AMOUNT:
				return false
	return true
