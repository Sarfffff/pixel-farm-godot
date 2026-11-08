extends RefCounted
## 章节任务用例：接受、进度、交付事务。
##
## 接任务簿（QuestLog）与既有背包、金币、日期、保存端口；不查场景树、不碰界面。
## 交付是一次事务：先校验进度与奖励容量，再扣货、提交模型、发钱发物，最后通知观察者。
## 重入保护覆盖重复按钮、重复信号与观察者回调：busy 期间任何交付请求都被拒绝。

signal accepted(id: StringName)
signal completed(id: StringName)
signal changed
## 交付已结算但写档失败；由组合根接到可见提示，不静默吞掉。
signal save_failed

const QuestLogScript := preload("res://scripts/progression/quest_log.gd")

## true 表示一笔交付正在进行，期间拒绝新的交付请求。
var busy: bool = false
var last_rejection: String = ""
## 任务事实；编码/恢复与状态查询都走它。
var log: RefCounted

var _inventory: Inventory = null
var _economy: Economy = null
var _day: Callable = Callable()
var _save: Callable = Callable()


func _init() -> void:
	log = QuestLogScript.new()


## 组合根在注册快照分区之前调用，先把定义读进来。
func start() -> void:
	if busy:
		return
	log.load_definitions()


func configure(inventory: Inventory, economy: Economy, day: Callable = Callable(), save: Callable = Callable()) -> void:
	if busy:
		return
	_inventory = inventory
	_economy = economy
	_day = day
	_save = save


func definitions() -> Array[QuestData]:
	return log.definitions()


func status_of(id: StringName) -> int:
	return log.status_of(id)


func definition(id: StringName) -> QuestData:
	return log.define(id)


func accept(id: StringName) -> bool:
	if busy:
		return false
	busy = true
	if not log.accept(id, _today()):
		busy = false
		return false
	accepted.emit(id)
	changed.emit()
	_persist()
	busy = false
	last_rejection = ""
	return true


## NPC 交互端口：身份与资格在用例中验证，Presenter 不决定谁能交付。
func accept_for(giver: StringName, id: StringName) -> bool:
	var quest: QuestData = definition(id)
	if quest == null or giver == &"" or quest.giver != giver:
		return false
	return accept(id)


func deliver_for(giver: StringName, id: StringName) -> bool:
	var quest: QuestData = definition(id)
	if quest == null or giver == &"" or quest.giver != giver:
		return false
	return deliver(id)


func delivery_hint(id: StringName) -> String:
	if busy:
		return "任务正在结算，请稍候"
	var quest: QuestData = definition(id)
	if quest == null or not log.is_active(id):
		return "任务状态已变化，请重新交谈"
	if _inventory == null or (quest.reward_coins > 0 and _economy == null):
		return "任务服务暂不可用"
	if not _steps_met(quest):
		return "交付物品还没备齐"
	if not _rewards_fit(quest):
		return "背包放不下整批奖励，请先整理背包再来交付"
	return ""


## 每一步的「要多少 / 有多少」与这一行是否够数；只读，供日志或对话直接渲染。
func progress(id: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var quest: QuestData = log.define(id)
	if quest == null:
		return rows
	var totals: Dictionary = _requirements(quest)
	for item_id: StringName in totals:
		var need: int = int(totals[item_id])
		var have: int = mini(_count_of(item_id), need)
		var text: String = "交付 %d 份%s" % [need, _inventory.item_name(item_id) if _inventory != null else String(item_id)]
		for step: QuestStep in quest.deliver_steps():
			if step.item_id == item_id and step.count == need:
				text = _step_text(step)
				break
		rows.append({
			&"item": item_id,
			&"need": need,
			&"have": have,
			&"done": have >= need,
			&"text": text,
		})
	return rows


## 只看任务事实与背包，不看界面是否存在。
func can_deliver(id: StringName) -> bool:
	var quest: QuestData = log.define(id)
	if quest == null or not log.is_active(id) or _inventory == null:
		return false
	return _steps_met(quest)


## 交付：扣货 → 提交模型 → 发金币/物品 → 通知观察者 → 写档。
## 失败时不留任何改动；busy 期间的重复请求不会重复发奖。
func deliver(id: StringName) -> bool:
	last_rejection = delivery_hint(id)
	if not last_rejection.is_empty():
		return false
	var quest: QuestData = definition(id)

	busy = true
	_inventory.begin_update()
	var requirements: Dictionary = _requirements(quest)
	for item_id: StringName in requirements:
		_inventory.remove_item(item_id, int(requirements[item_id]))
	# 模型先提交，观察者在 end_update 里看到的一定是完成后的样子。
	log.complete(id, _today())
	for reward: QuestReward in quest.reward_items:
		if reward == null or reward.item_id == &"" or reward.count <= 0:
			continue
		var leftover: int = _inventory.add_item(reward.item_id, reward.count, &"quest")
		if leftover > 0:
			push_warning("[quests] 奖励放不下，剩余 %d 个 %s" % [leftover, reward.item_id])
	# 钱包立即通知观察者，因此先提交所有物品；任何模型通知均能看到整笔结果。
	if quest.reward_coins > 0:
		_economy.earn(quest.reward_coins)
	_inventory.end_update()

	completed.emit(id)
	changed.emit()
	_persist()
	busy = false
	last_rejection = ""
	return true


func encode() -> Dictionary:
	return log.encode()


## 恢复只还原事实，不发奖、不改背包。
func restore(data: Dictionary) -> void:
	if busy:
		return
	busy = true
	log.restore(data)
	changed.emit()
	busy = false


func clear() -> void:
	if busy:
		return
	busy = true
	log.clear()
	changed.emit()
	_inventory = null
	_economy = null
	_day = Callable()
	_save = Callable()
	busy = false


func _steps_met(quest: QuestData) -> bool:
	var requirements: Dictionary = _requirements(quest)
	if requirements.is_empty():
		return false
	for item_id: StringName in requirements:
		if Inventory.TOOL_IDS.has(item_id) or _count_of(item_id) < int(requirements[item_id]):
			return false
	return true


func _requirements(quest: QuestData) -> Dictionary:
	var totals: Dictionary = {}
	for step: QuestStep in quest.deliver_steps():
		totals[step.item_id] = int(totals.get(step.item_id, 0)) + step.count
	return totals


## 奖励必须现在就能装下：交付物与奖励物在数据层被禁止相同，扣货只会让容量更宽裕。
func _rewards_fit(quest: QuestData) -> bool:
	var totals: Dictionary = {}
	for reward: QuestReward in quest.reward_items:
		if reward == null or reward.item_id == &"" or reward.count <= 0:
			continue
		if _inventory.definition(reward.item_id) == null:
			push_warning("[quests] 奖励物品未定义：%s" % reward.item_id)
			return false
		totals[reward.item_id] = int(totals.get(reward.item_id, 0)) + reward.count
	return _inventory.has_space_for_batch(totals)


func _count_of(id: StringName) -> int:
	return _inventory.count_of(id) if _inventory != null else 0


func _step_text(step: QuestStep) -> String:
	if not step.text.strip_edges().is_empty():
		return step.text
	var item_name: String = String(step.item_id)
	if _inventory != null:
		item_name = _inventory.item_name(step.item_id)
	return "交付 %d 份%s" % [step.count, item_name]


func _today() -> int:
	if _day.is_valid():
		return maxi(1, int(_day.call()))
	return 1


func _persist() -> void:
	if not _save.is_valid():
		return
	if not bool(_save.call()):
		save_failed.emit()
