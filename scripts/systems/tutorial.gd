extends Node
## 只由成功操作推进，允许在初始田地直接播种；进度持久化。

signal changed

const TITLES: Array[String] = ["第一次耕作", "种下希望", "给作物浇水", "结束第一天", "照料到成熟", "第一笔生意", "农场起步了"]
const HINTS: Array[String] = [
	"[1] 锄头 · 在左侧田边按空格开垦",
	"[3] 种子 · 面向空田按空格播种",
	"[2] 水壶 · 面向作物按空格浇水",
	"回木屋按 [E]，确认睡觉进入明天",
	"每天浇水；三次过夜后按 [E] 收获",
	"找屋旁老板 [E]，在商店卖出作物",
	"修复社区、交订单，攒钱升级铜水壶",
]
var step: int = 0


func _ready() -> void:
	add_to_group(&"tutorial")
	_connect_events.call_deferred()


func _connect_events() -> void:
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	if tiller != null:
		tiller.action_completed.connect(_on_action)
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		time.day_started.connect(_on_day_started)
	var shop := get_tree().current_scene.get_node_or_null("UI/ShopPanel")
	if shop != null:
		shop.item_sold.connect(_on_item_sold)


func _on_action(tool: StringName, _cell: Vector2i) -> void:
	var next: int = step
	if tool == &"hoe" and step == 0:
		next = 1
	elif tool == &"seeds" and step <= 1:
		next = 2
	elif tool == &"watering_can" and step == 2:
		next = 3
	elif tool == &"harvest" and step <= 4:
		next = 5
	_set_step(next)


func _on_day_started(_day: int) -> void:
	if step == 3:
		_set_step(4)


func _on_item_sold(id: StringName, _count: int) -> void:
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var item: ItemData = inventory.definition(id) if inventory != null else null
	if item != null and item.category == &"crop":
		_set_step(6)


func _set_step(value: int) -> void:
	if step == value:
		return
	step = clampi(value, 0, 6)
	changed.emit()


func title() -> String:
	return TITLES[step]


func hint() -> String:
	return HINTS[step]


func to_dict() -> Dictionary:
	return {&"step": step}


func from_dict(data: Dictionary) -> void:
	step = clampi(int(data.get("step", 0)), 0, 6)
	changed.emit()
