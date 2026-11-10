class_name FishingGearData
extends Resource
## 渔具成长配置：等级、抛竿体力系数与可选鱼种权重加成；不保存玩家已购买状态。

const MAX_LEVEL: int = 9
const MAX_SCALE: float = 4.0
const MAX_BONUS: float = 4.0
const MAX_BONUS_KINDS: int = 16

@export var item_id: StringName = &""
@export var level: int = 1
@export var cast_stamina_scale: float = 1.0
## 鱼种ID → 额外权重比例（0.5 表示 +50%），可为空。
@export var allowed_species_bonus: Dictionary[StringName, float] = {}


func is_valid() -> bool:
	if item_id == &"" or level < 1 or level > MAX_LEVEL: return false
	if not is_finite(cast_stamina_scale) or cast_stamina_scale <= 0.0 or cast_stamina_scale > MAX_SCALE: return false
	if allowed_species_bonus.size() > MAX_BONUS_KINDS: return false
	for fish: StringName in allowed_species_bonus:
		if fish == &"": return false
		var bonus: float = float(allowed_species_bonus[fish])
		if not is_finite(bonus) or bonus < 0.0 or bonus > MAX_BONUS: return false
	return true
