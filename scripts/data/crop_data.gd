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
## 各个非成熟阶段需要浇水过夜的次数；留空兼容旧作物的一天一阶。
@export var stage_days: Array[int] = []
## 0 为一次性作物；大于 0 时收获后保留植株，重新浇水这么多天后结果。
@export var regrow_days: int = 0
## 独立素材的画布大小不同，按地块调节显示比例，脚底锚点保持不变。
@export_range(0.25, 2.0, 0.05) var visual_scale: float = 1.0


func days_at_stage(index: int) -> int:
	return maxi(1, stage_days[index]) if index >= 0 and index < stage_days.size() else 1


## 成熟所需的阶段下标（最后一张贴图）。
func last_stage() -> int:
	return maxi(stages.size() - 1, 0)
