class_name SkillLevelReward
extends Resource
## 一次升级新增的能力；不发物品或金币，实际能力由累计等级即时推导。

@export_multiline var description: String = ""
@export var stamina_reductions: Dictionary[StringName, int] = {}
@export_range(0.1, 1.0) var fishing_wait_scale: float = 1.0
@export_range(0.0, 5.0) var fishing_bite_window_bonus: float = 0.0


func is_valid() -> bool:
	if description.strip_edges().is_empty(): return false
	if not is_finite(fishing_wait_scale) or fishing_wait_scale < 0.1 or fishing_wait_scale > 1.0: return false
	if not is_finite(fishing_bite_window_bonus) or fishing_bite_window_bonus < 0.0 or fishing_bite_window_bonus > 5.0: return false
	var meaningful: bool = fishing_wait_scale < 1.0 or fishing_bite_window_bonus > 0.0
	for action: StringName in stamina_reductions:
		if action not in [&"hoe", &"watering_can", &"seeds", &"axe", &"harvest", &"forage", &"fishing"]: return false
		if stamina_reductions[action] <= 0 or stamina_reductions[action] > 8: return false
		meaningful = true
	return meaningful
