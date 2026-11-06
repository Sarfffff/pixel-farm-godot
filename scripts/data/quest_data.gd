class_name QuestData
extends Resource
## 一个任务的定义。数据文件放在 res://data/quests/*.tres，运行期扫描该目录。
##
## 任务之间只通过 `requires` 串成章节：新增一章只加 .tres，不改 QuestService。
## `order` 决定同日可接任务在列表里的先后，不参与任何计算。

@export var id: StringName = &""
## 章节号；当前只有第一章（1）。
@export var chapter: int = 1
@export var order: int = 0
@export var title: String = ""
@export_multiline var summary: String = ""
## 委托人：NPC 的 npc_id（B2-06 接对话时用）；留空表示由系统直接发放。
@export var giver: StringName = &""
@export var giver_name: String = ""
## 前置任务：全部完成后本任务才会从锁定变成可接。
@export var requires: Array[StringName] = []
@export var steps: Array[QuestStep] = []
@export var reward_coins: int = 0
@export var reward_items: Array[QuestReward] = []
## 接任务 / 进行中 / 交付后的台词，供对话与日志直接取用，避免台词写死在脚本里。
@export var offer_lines: Array[String] = []
@export var progress_lines: Array[String] = []
@export var done_lines: Array[String] = []


## 至少要有一步且奖励不能为负；空定义在加载时会被跳过。
func is_valid() -> bool:
	return id != &"" and not title.strip_edges().is_empty() and not steps.is_empty() and reward_coins >= 0


## 交付步骤里需要的物品，进度与事务都用它。
func deliver_steps() -> Array[QuestStep]:
	var result: Array[QuestStep] = []
	for step: QuestStep in steps:
		if step != null and step.kind == &"deliver" and step.item_id != &"" and step.count > 0:
			result.append(step)
	return result
