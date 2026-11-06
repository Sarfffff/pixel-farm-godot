class_name QuestReward
extends Resource
## 任务奖励里的一件物品；金币单独写在 QuestData.reward_coins。
##
## 奖励物品不能是任务本身要求交付的同一种物品：交付前要能放得下奖励，
## 若两者相同，容量判断会因"先扣后发"而变得依赖内部顺序。

@export var item_id: StringName = &""
@export var count: int = 1
