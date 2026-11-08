class_name StoryCue
extends Resource
## 仅表现，不含发奖/改任务步骤。选项是对话回应，不改变已提交的剧情结果。

@export_enum("line", "move", "face", "camera", "fade_out", "fade_in", "choice", "wait") var kind: String = "line"
@export var actor: StringName = &""
@export var speaker: String = ""
@export_multiline var text: String = ""
@export var target: Vector2 = Vector2.ZERO
@export_range(0.0, 120.0) var duration: float = 0.0
@export_enum("up", "down", "left", "right") var facing: String = "down"
@export var options: Array[String] = []
@export var default_option: int = 0


func is_valid() -> bool:
	if not is_finite(duration) or duration < 0.0 or duration > 120.0 or not target.is_finite(): return false
	match kind:
		"line": return not text.strip_edges().is_empty()
		"choice": return not text.strip_edges().is_empty() and not options.is_empty() and default_option >= 0 and default_option < options.size() and options.all(func(option: String) -> bool: return not option.strip_edges().is_empty())
		"move": return actor != &""
		"face": return actor != &"" and facing in ["up", "down", "left", "right"]
		"camera", "fade_out", "fade_in", "wait": return true
	return false
