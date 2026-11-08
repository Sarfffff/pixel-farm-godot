extends Control
## 窄接口：面板只报告开关意图，互斥、暂停和输入锁由协调器负责。

@export var pauses_world: bool = false
var modal_coordinator: Node


func set_open(open: bool) -> void:
	_set_modal_open(open)


func _set_modal_open(open: bool) -> void:
	if is_instance_valid(modal_coordinator):
		modal_coordinator.set_panel_open(self, open)
	else:
		visible = open


func _can_open_modal() -> bool:
	return not is_instance_valid(modal_coordinator) or modal_coordinator.can_open_panel()
