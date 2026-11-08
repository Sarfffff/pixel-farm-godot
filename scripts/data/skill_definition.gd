class_name SkillDefinition
extends Resource
## 技能曲线、每笔成功劳动经验和五级收益的唯一配置。

const LEVEL_LIMIT: int = 5
const MAX_EXPERIENCE: int = 10000

@export var id: StringName = &""
@export var display_name: String = ""
@export var order: int = 0
@export_multiline var labor_hint: String = ""
@export var cumulative_xp: PackedInt32Array = PackedInt32Array()
@export var experience_for: Dictionary[StringName, int] = {}
@export var levels: Array[SkillLevelReward] = []


func is_valid() -> bool:
	if id == &"" or display_name.strip_edges().is_empty() or labor_hint.strip_edges().is_empty(): return false
	if cumulative_xp.size() != LEVEL_LIMIT or levels.size() != LEVEL_LIMIT or experience_for.is_empty(): return false
	var previous: int = 0
	for threshold: int in cumulative_xp:
		if threshold <= previous or threshold > MAX_EXPERIENCE: return false
		previous = threshold
	for action: StringName in experience_for:
		if action not in [&"harvest", &"chop_tree", &"clear_stump", &"forage", &"catch_fish"]: return false
		if experience_for[action] <= 0 or experience_for[action] > MAX_EXPERIENCE: return false
	for reward: SkillLevelReward in levels:
		if reward == null or not reward.is_valid(): return false
		if id != &"fishing" and (reward.fishing_wait_scale < 1.0 or reward.fishing_bite_window_bonus > 0.0): return false
	return true


func max_xp() -> int:
	return cumulative_xp[-1] if not cumulative_xp.is_empty() else 0


func level_for(xp: int) -> int:
	var level: int = 0
	for threshold: int in cumulative_xp:
		if xp < threshold: break
		level += 1
	return level


func effects_for(level: int) -> Dictionary:
	var reductions: Dictionary[StringName, int] = {}
	var wait_scale: float = 1.0
	var bite_bonus: float = 0.0
	for index in range(clampi(level, 0, levels.size())):
		var reward: SkillLevelReward = levels[index]
		for action: StringName in reward.stamina_reductions:
			reductions[action] = int(reductions.get(action, 0)) + reward.stamina_reductions[action]
		wait_scale *= reward.fishing_wait_scale
		bite_bonus += reward.fishing_bite_window_bonus
	return {"stamina_reductions": reductions, "fishing_wait_scale": wait_scale, "fishing_bite_window_bonus": bite_bonus}
