class_name Crop
extends Sprite2D
## 一株作物：浇水推进一个阶段，最后一张贴图即可收获。
##
## 位置由耕地系统设成所在格的底部中心，配合 World 的 y_sort 参与遮挡排序。
## 阶段贴图是 32×32，脚底对齐后向上占两格，与树的做法一致。

const STAGE_OFFSET := Vector2(0, -16)
const SeasonRules := preload("res://scripts/world/farming/crop_season_rules.gd")

var data: CropData
var stage: int = 0
## 当天是否已经浇过水：浇过的作物在推进前不再响应水壶。
var watered: bool = false
var stage_age: int = 0
var regrowing: bool = false
var withered: bool = false


func setup(crop_data: CropData) -> void:
	data = crop_data
	stage = 0
	watered = false
	stage_age = 0
	regrowing = false
	withered = false
	offset = STAGE_OFFSET
	apply_stage()


func is_mature() -> bool:
	return data != null and not withered and stage >= data.last_stage()


func watered_nights_remaining() -> int:
	if data == null or withered or is_mature():
		return 0
	if regrowing:
		return maxi(0, data.regrow_days - stage_age)
	var nights: int = -stage_age
	for index: int in range(stage, data.last_stage()):
		nights += data.days_at_stage(index)
	return maxi(0, nights)


## 浇水：只打上"今天浇过"的标记，生长留到睡觉结算，返回是否真的标记成功。
func water() -> bool:
	if data == null or withered or watered or is_mature():
		return false
	watered = true
	return true


## 睡觉结算：今天浇过水的作物推进一阶，返回是否长了。
func grow_if_watered() -> bool:
	if data == null or withered or not watered or is_mature():
		return false
	stage_age += 1
	var required: int = maxi(1, data.regrow_days) if regrowing else data.days_at_stage(stage)
	if stage_age < required:
		return false
	stage_age = 0
	stage = data.last_stage() if regrowing else mini(stage + 1, data.last_stage())
	regrowing = false
	apply_stage()
	_play_grow_pop()
	return true


## 复收作物保留根系；一次性作物仍由耕地系统移除。
func regrow_after_harvest() -> bool:
	if data == null or withered or data.regrow_days <= 0:
		return false
	stage = maxi(0, data.last_stage() - 1)
	stage_age = 0
	regrowing = true
	watered = false
	apply_stage()
	_play_grow_pop()
	return true


## 新的一天：清掉浇水标记，作物停在当前阶段。
func begin_day() -> void:
	watered = false


func apply_season(season: StringName) -> void:
	if SeasonRules.should_wither(data, season):
		withered = true
		watered = false
		regrowing = false
	apply_stage()


func harvest_item_id() -> StringName:
	return data.harvest_item if data != null else &""


func harvest_amount() -> int:
	return data.harvest_count if data != null else 0


## 收获时缩小淡出，节点随后自行销毁。
func play_harvest() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * data.visual_scale * 1.25, 0.12)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


## 按当前 stage 换贴图；读档恢复阶段时也会用到，所以是公开方法。
func apply_stage() -> void:
	if data == null or data.stages.is_empty():
		return
	texture = data.stages[clampi(stage, 0, data.last_stage())]
	scale = Vector2.ONE * data.visual_scale
	modulate = Color("8b7654") if withered else Color.WHITE


## 生长时轻微弹一下，给"长了一阶"一个视觉反馈。
func _play_grow_pop() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 0.94) * data.visual_scale, 0.08)
	tween.tween_property(self, "scale", Vector2.ONE * data.visual_scale, 0.12)


## 作物只编码自身生长事实，不知道地图坐标或存档文件。
func to_dict() -> Dictionary:
	return {&"id": String(data.id) if data != null else "", &"stage": stage, &"watered": watered, &"stage_age": stage_age, &"regrowing": regrowing, &"withered": withered}


func restore_growth(record: Dictionary) -> void:
	if data == null:
		return
	stage = clampi(int(record.get("stage", 0)), 0, data.last_stage())
	withered = bool(record.get("withered", false))
	watered = bool(record.get("watered", false)) and not withered
	regrowing = bool(record.get("regrowing", false)) and not withered and data.regrow_days > 0 and not is_mature()
	var maximum: int = data.regrow_days if regrowing else data.days_at_stage(stage)
	stage_age = clampi(int(record.get("stage_age", 0)), 0, maxi(0, maximum - 1))
	apply_stage()
