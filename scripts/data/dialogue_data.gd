class_name DialogueData
extends Resource
## 一段多句台词：按顺序显示，走完后可选给一组选项。
##
## 选项 id 会回调给 NPC 的 `on_dialogue_option(id)`：
## 返回非空字符串 = 换一句继续聊，返回空 = 结束对话（NPC 也可以自己去做别的事）。
## 不配选项时，面板最后自动给一个"再见"。

@export var lines: Array[String] = []
@export var options: Array[Dictionary] = []
