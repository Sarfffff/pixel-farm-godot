class_name QuestStep
extends Resource
## 任务的一步：把指定数量的物品交给委托人。
##
## 目前只有交付（deliver）一种：进度按背包当前持有量推导，不单独累计，
## 所以读档、反复打开面板、重复交付都不会把进度算两遍。

## deliver = 交付物品
@export var kind: StringName = &"deliver"
@export var item_id: StringName = &""
@export var count: int = 1
## 日志与对话里这一行怎么念，留空时按物品名自动拼。
@export var text: String = ""
