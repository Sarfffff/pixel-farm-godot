extends Node
## 社区中心：按阶段上缴物资，每修好一个阶段解锁新的种子。
##
## 阶段表写在这里（不依赖素材），商店读 `unlocked_stage()` 决定哪些种子能卖。

signal stage_completed(stage: int)
signal changed

const STAGES := [
	{
		&"title": "修补围栏",
		&"desc": "把农场四周的栅栏补齐，镇上的商队才愿意常来。",
		&"needs": {&"wood": 15, &"fiber": 10},
		&"reward": 300,
		&"unlock": "萝卜种子上架",
	},
	{
		&"title": "翻新集市",
		&"desc": "把集市摊位重新刷一遍漆，多出来的位置留给新货。",
		&"needs": {&"carrot": 10, &"egg": 5},
		&"reward": 500,
		&"unlock": "小麦种子上架",
	},
	{
		&"title": "装点农场",
		&"desc": "给中心广场铺一条石板路，再把仓库填满。",
		&"needs": {&"wheat": 8, &"stone": 10},
		&"reward": 800,
		&"unlock": "农场招牌挂上了",
	},
]

var stage: int = 0


func _ready() -> void:
	add_to_group(&"community")


func stage_count() -> int:
	return STAGES.size()


func is_finished() -> bool:
	return stage >= STAGES.size()


## 当前阶段的原始数据；全部修完后返回空字典。
func current() -> Dictionary:
	return {} if is_finished() else STAGES[stage]


## 商店用它过滤 `ItemData.unlock_stage`。
func unlocked_stage() -> int:
	return stage


## 当前阶段每一项的需求与背包持有量，给面板直接用。
func progress() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var current_stage := current()
	if current_stage.is_empty():
		return rows
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	var needs: Dictionary = current_stage[&"needs"]
	for id: StringName in needs:
		var need: int = int(needs[id])
		var have: int = inventory.count_of(id) if inventory != null else 0
		var display_name := String(id)
		var icon: Texture2D = null
		if inventory != null:
			for item: ItemData in inventory.definitions():
				if item.id == id:
					display_name = item.display_name
					icon = item.icon
					break
		rows.append({
			&"id": id,
			&"need": need,
			&"have": have,
			&"name": display_name,
			&"icon": icon,
		})
	return rows


func can_donate() -> bool:
	if is_finished():
		return false
	for row: Dictionary in progress():
		if int(row[&"have"]) < int(row[&"need"]):
			return false
	return true


## 上缴当前阶段：扣物品、发奖金、阶段 +1；材料不够时不做任何改动。
func donate() -> bool:
	if not can_donate():
		return false
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null:
		return false
	var needs: Dictionary = current()[&"needs"]
	for id: StringName in needs:
		if not inventory.remove_item(id, int(needs[id])):
			return false
	var reward: int = int(current()[&"reward"])
	var economy := get_tree().get_first_node_in_group(&"economy")
	if economy != null and economy.has_method(&"earn"):
		economy.earn(reward)
	stage += 1
	stage_completed.emit(stage)
	changed.emit()
	var save := get_tree().get_first_node_in_group(&"save")
	if save != null and save.has_method(&"save_game"):
		save.save_game()
	return true


func to_dict() -> Dictionary:
	return {&"stage": stage}


func from_dict(data: Dictionary) -> void:
	stage = clampi(int(data.get(&"stage", 0)), 0, STAGES.size())
	changed.emit()
