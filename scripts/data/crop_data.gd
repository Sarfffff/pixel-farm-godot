class_name CropData
extends Resource
## 一种作物的配置：地面阶段贴图、对应的种子与收获物。
##
## 数据文件放在 res://data/crops/*.tres；加新作物只需加一个 .tres + 阶段贴图，
## 不改任何脚本。

@export var id: StringName = &""
@export var display_name: String = ""
## 地面上的生长阶段贴图，从刚发芽到成熟，按顺序排列；最后一张即为成熟态。
@export var stages: Array[Texture2D] = []
## 播种消耗的物品 id（与 data/items 对应）。
@export var seed_item: StringName = &""
## 收获得到的物品 id 与数量。
@export var harvest_item: StringName = &""
@export var harvest_count: int = 1


## 成熟所需的阶段下标（最后一张贴图）。
func last_stage() -> int:
	return maxi(stages.size() - 1, 0)
