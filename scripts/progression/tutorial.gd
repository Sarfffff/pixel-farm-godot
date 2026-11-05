extends Node
## 从首次收成到升级后再生产；只记录成功操作，随 tutorial 字段存档。

signal changed

const TITLES: Array[String] = ["第一次耕作", "种下希望", "给作物浇水", "结束第一天", "照料到成熟", "第一笔生意", "升级铜水壶", "再经营一轮", "基础循环完成"]
const HINTS: Array[String] = [
	"[1] 锄头 · 左侧田地空格开垦，也可直接在现有田地播种",
	"[3] 种子 · 面向空田按空格播种",
	"[2] 水壶 · 面向作物按空格浇水",
	"回家进屋，到床边 [F]；18:00 后睡觉进入明天",
	"每天浇水，成熟后 [F] 收获；等收成时可采集、交订单",
	"09:00–17:00 进杂货店，找柜台老板 [F] 卖出作物",
]
const REINVEST_PLOTS: int = 3
const COMPLETE_STEP: int = 8

var step: int = 0
var bought_again: bool = false
var planted_again: Array[Vector2i] = []
var watered_again: Array[Vector2i] = []
var harvests_again: Dictionary = {}
var sold_again: bool = false


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
	var shop := get_tree().get_first_node_in_group(&"trade")
	if shop != null:
		shop.item_sold.connect(_on_item_sold)
		shop.item_bought.connect(_on_item_bought)
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades != null:
		upgrades.changed.connect(_on_upgrade_changed)
	for group: StringName in [&"inventory", &"economy"]:
		var system := get_tree().get_first_node_in_group(group)
		if system != null:
			system.changed.connect(func(_value: Variant = null) -> void: changed.emit())
	_on_upgrade_changed()


func _on_action(tool: StringName, cell: Vector2i) -> void:
	if step == 7:
		if tool == &"seeds" and bought_again and not planted_again.has(cell) and planted_again.size() < REINVEST_PLOTS:
			planted_again.append(cell)
		elif tool == &"watering_can" and planted_again.has(cell) and not watered_again.has(cell):
			watered_again.append(cell)
		elif tool == &"harvest" and watered_again.has(cell):
			var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
			var harvest: Dictionary = tiller.harvest_info(cell) if tiller != null else {}
			if not harvest.is_empty():
				var id: String = harvest.id
				harvests_again[id] = int(harvests_again.get(id, 0)) + int(harvest.count)
		_finish_reinvestment()
		return
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
	elif step == 7:
		# 雨天由耕地系统先自动浇水，不能要求玩家再浇已湿或已成熟的作物。
		var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
		if tiller != null:
			for cell: Vector2i in planted_again:
				if tiller.has_watered_crop(cell) and not watered_again.has(cell):
					watered_again.append(cell)
		_finish_reinvestment()


func _on_item_sold(id: StringName, count: int) -> void:
	if count <= 0:
		return
	if step == 5 and _is_field_produce(id):
		_set_step(6)
		_on_upgrade_changed()
	elif step == 7 and int(harvests_again.get(String(id), 0)) > 0:
		sold_again = true
		_finish_reinvestment()


func _on_item_bought(id: StringName, count: int) -> void:
	if step != 7 or count <= 0:
		return
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	if tiller == null:
		return
	for crop: CropData in tiller.crop_definitions():
		if crop.seed_item == id:
			bought_again = true
			changed.emit()
			return


func _is_field_produce(id: StringName) -> bool:
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	if tiller != null:
		for crop: CropData in tiller.crop_definitions():
			if crop.harvest_item == id:
				return true
	return false


func _on_upgrade_changed() -> void:
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if step == 6 and upgrades != null and upgrades.watering_level > 0:
		_set_step(7)
	else:
		changed.emit()


func _finish_reinvestment() -> void:
	if bought_again and planted_again.size() >= REINVEST_PLOTS and watered_again.size() >= REINVEST_PLOTS and sold_again:
		_set_step(COMPLETE_STEP)
	else:
		changed.emit()


func _set_step(value: int) -> void:
	if value <= step:
		return
	step = clampi(value, 0, COMPLETE_STEP)
	changed.emit()


func title() -> String:
	return TITLES[step]


func hint() -> String:
	if step < HINTS.size():
		return HINTS[step]
	if step == 6:
		var upgrades := get_tree().get_first_node_in_group(&"upgrades")
		var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
		var economy := get_tree().get_first_node_in_group(&"economy") as Economy
		if upgrades == null or inventory == null or economy == null:
			return "卖收成、交订单，收集木石后去杂货店升级"
		var config: Resource = upgrades.WATERING
		return "目标：一次浇三格\n金币 %d/%d · 木 %d/%d · 石 %d/%d\n卖收成/交订单；[4]砍树 [5]碎石，杂货店购买升级" % [economy.coins, config.coin_cost, inventory.count_of(&"wood"), config.wood_cost, inventory.count_of(&"stone"), config.stone_cost]
	if step == 7:
		return "铜水壶一次浇三格\n再买当季种子 %s · 播种 %d/3\n浇水 %d/3 · 新收成出售 %s\n三株排成一行，面向中间那格浇水" % ["✓" if bought_again else "待完成", planted_again.size(), watered_again.size(), "✓" if sold_again else "待完成"]
	return "已完成收成→出售→升级→再生产\n继续交订单、修社区，扩大农场；睡前保存，明天继续"


func to_dict() -> Dictionary:
	return {"step": step, "bought_again": bought_again, "planted_again": _pack_cells(planted_again), "watered_again": _pack_cells(watered_again), "harvests_again": harvests_again.duplicate(), "sold_again": sold_again}


func from_dict(data: Dictionary) -> void:
	step = clampi(int(data.get("step", 0)), 0, COMPLETE_STEP)
	bought_again = bool(data.get("bought_again", false))
	planted_again = _unpack_cells(data.get("planted_again", []))
	watered_again = _unpack_cells(data.get("watered_again", []))
	harvests_again = data.get("harvests_again", {}).duplicate()
	sold_again = bool(data.get("sold_again", false))
	_on_upgrade_changed()


func _pack_cells(cells: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell: Vector2i in cells:
		result.append([cell.x, cell.y])
	return result


func _unpack_cells(entries: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entry: Variant in entries:
		if entry is Array and entry.size() == 2:
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			if not result.has(cell) and result.size() < REINVEST_PLOTS:
				result.append(cell)
	return result
