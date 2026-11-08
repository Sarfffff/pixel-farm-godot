class_name CraftingRecipeData
extends Resource
## 工作台即时制作配置；不与按天加工配方混用。

@export var id: StringName = &""
@export var title: String = ""
@export var ingredients: Dictionary[StringName, int] = {}
@export var products: Dictionary[StringName, int] = {}


func is_valid() -> bool:
	if id == &"" or title.is_empty() or ingredients.is_empty() or products.is_empty():
		return false
	for amounts: Dictionary in [ingredients, products]:
		for item: StringName in amounts:
			if item == &"" or int(amounts[item]) <= 0:
				return false
	return true
