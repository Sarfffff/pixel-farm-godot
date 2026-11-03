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
	changed.emit(value)
	return true


func refill() -> void:
	if value == MAX_VALUE:
		return
	value = MAX_VALUE
	changed.emit(value)


func ratio() -> float:
	return float(value) / float(MAX_VALUE)


func to_dict() -> Dictionary:
	return {&"value": value}


func from_dict(data: Dictionary) -> void:
	value = clampi(int(data.get(&"value", MAX_VALUE)), 0, MAX_VALUE)
	changed.emit(value)
