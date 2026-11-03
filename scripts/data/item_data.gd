class_name ItemData
extends Resource
## 单件物品的定义：图标、堆叠上限、售价与分类。
##
## 数据文件统一放在 res://data/items/*.tres，背包在运行期扫描该目录，
## 新增物品只需加一个 .tres，不需要改任何脚本。

## 背包里使用的唯一 id，与文件名保持一致（wood.tres -> wood）。
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var upgraded_icon: Texture2D
## 单格上限；数量超过后自动占用下一格。
@export var max_stack: int = 99
## 卖给商店的单价。
@export var sell_price: int = 0
## 商店买价；0 表示商店不出售这件物品。
@export var buy_price: int = 0
## material=材料 / seed=种子 / crop=收获物 / tool=工具
@export var category: StringName = &"material"
## 商店上架需要的社区中心阶段：0 = 一开始就能买，1/2 = 修好对应阶段后解锁。
@export var unlock_stage: int = 0
