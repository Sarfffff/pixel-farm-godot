class_name StoryEvent
extends Resource
## 一次性稳定 ID；outcome 由组合根路由到已有同步用例，Resource 不持有外部状态。

@export var id: StringName = &""
@export var title: String = ""
@export var outcome: StringName = &""
@export var conditions: Array[StoryCondition] = []
@export var cues: Array[StoryCue] = []


func is_valid() -> bool:
	return id != &"" and not title.strip_edges().is_empty() and conditions.all(func(condition: StoryCondition) -> bool: return condition != null and condition.is_valid()) and cues.all(func(cue: StoryCue) -> bool: return cue != null and cue.is_valid())
