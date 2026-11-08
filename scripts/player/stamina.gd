extends Node
## 体力：干活要花体力，睡一觉回满。
##
## 挂在 `Main/Systems/Stamina`（组 `stamina`）；干活的地方用 `spend()` 扣，
## 扣不动就返回 false，调用方据此拦住这次操作。

signal changed(value: int)
## 体力不足时被拦住，调用方可以给提示。
signal rejected

const MAX_VALUE: int = 100

var value: int = MAX_VALUE
var _update_depth: int = 0
var _pending_changed: bool = false


func _ready() -> void:
	add_to_group(&"stamina")
	# 睡醒回满：与其他系统一样用组查找 + 信号，不依赖类名。
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(func(_day: int) -> void: refill())


func can_spend(amount: int) -> bool:
	return value >= amount


## 扣体力；不够时不改数，返回 false。
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if value < amount:
		rejected.emit()
		return false
	value -= amount
	_notify_changed()
	return true


## 与库存相同的嵌套批量边界：数值立即提交，最外层结束时同步通知最终值。
func begin_update() -> void:
	_update_depth += 1


func end_update() -> void:
	if _update_depth == 0: return
	_update_depth -= 1
	if _update_depth > 0 or not _pending_changed: return
	_pending_changed = false
	changed.emit(value)


func _notify_changed() -> void:
	if _update_depth > 0:
		_pending_changed = true
	else:
		changed.emit(value)


func refill() -> void:
	if value == MAX_VALUE:
		return
	value = MAX_VALUE
	_notify_changed()


## 累倒醒来（星露谷规则）：当天只恢复一半体力。
## 必须在 day_started 的回满之后调用。
func wake_weary() -> void:
	value = maxi(1, MAX_VALUE / 2)
	_notify_changed()


func ratio() -> float:
	return float(value) / float(MAX_VALUE)


func to_dict() -> Dictionary:
	return {&"value": value}


func from_dict(data: Dictionary) -> void:
	value = clampi(int(data.get(&"value", MAX_VALUE)), 0, MAX_VALUE)
	_notify_changed()
