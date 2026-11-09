extends Node
## 劳动端口：把技能服务的只读能力查询与成功凭据转给既有玩法节点。
## 不保存经验或等级，唯一事实仍在 SkillService；劳动节点只提交已完整结算的凭据。

var _service: RefCounted
var _day: Callable


func _ready() -> void:
	add_to_group(&"labor")


func configure(service: RefCounted, current_day: Callable) -> void:
	_service = service
	_day = current_day


## 工具升级后的基准价再叠加技能减免；未接入技能时返回原价。
func stamina_cost(action: StringName, base_cost: int) -> int:
	if _service == null or base_cost <= 0:
		return base_cost
	return int(_service.stamina_cost(action, base_cost))


func fishing_parameters(wait_min: float, wait_max: float, bite_window: float) -> Dictionary:
	if _service == null:
		return {"wait_min": wait_min, "wait_max": wait_max, "bite_window": bite_window}
	return _service.fishing_parameters(wait_min, wait_max, bite_window)


func today() -> int:
	return int(_day.call()) if _day.is_valid() else 0


## 只在物品、体力与目标状态全部提交后调用；返回 false 只表示重复或满级。
func record(action: StringName, receipt_id: String) -> bool:
	if _service == null or not _day.is_valid() or receipt_id.strip_edges().is_empty():
		return false
	return bool(_service.record_labor(action, {"id": receipt_id, "day": today()}))


func today_text() -> String:
	return "第 %d 天" % today()


func clear() -> void:
	_service = null
	_day = Callable()
