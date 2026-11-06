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
	log.load_definitions()


func configure(inventory: Inventory, economy: Economy, day: Callable = Callable(), save: Callable = Callable()) -> void:
	_inventory = inventory
	_economy = economy
	_day = day
	_save = save


func definitions() -> Array[QuestData]:
	return log.definitions()


func status_of(id: StringName) -> int:
	return log.status_of(id)


func accept(id: StringName) -> bool:
	if not log.accept(id, _today()):
		return false
	accepted.emit(id)
	changed.emit()
	return true


## 每一步的「要多少 / 有多少」与这一行是否够数；只读，供日志或对话直接渲染。
func progress(id: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var quest: QuestData = log.define(id)
	if quest == null:
		return rows
	for step: QuestStep in quest.deliver_steps():
		var need: int = step.count
		var have: int = mini(_count_of(step.item_id), need)
		rows.append({
			&"item": step.item_id,
			&"need": need,
			&"have": have,
			&"done": have >= need,
			&"text": _step_text(step),
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
	if busy or _inventory == null:
		return false
	var quest: QuestData = log.define(id)
	if quest == null or not log.is_active(id):
		return false
	if not _steps_met(quest) or not _rewards_fit(quest):
		return false

	busy = true
	_inventory.begin_update()
	for step: QuestStep in quest.deliver_steps():
		if not _inventory.remove_item(step.item_id, step.count):
			# 预检查已经保证够数，走到这里说明背包被外部改动；整笔放弃。
			_inventory.end_update()
			busy = false
			return false
	# 模型先提交，观察者在 end_update 里看到的一定是完成后的样子。
	log.complete(id, _today())
	if _economy != null and quest.reward_coins > 0:
		_economy.earn(quest.reward_coins)
	for reward: QuestReward in quest.reward_items:
		if reward == null or reward.item_id == &"" or reward.count <= 0:
			continue
		var leftover: int = _inventory.add_item(reward.item_id, reward.count, &"quest")
		if leftover > 0:
			push_warning("[quests] 奖励放不下，剩余 %d 个 %s" % [leftover, reward.item_id])
	_inventory.end_update()
	busy = false

	completed.emit(id)
	changed.emit()
	_persist()
	return true


func encode() -> Dictionary:
	return log.encode()


## 恢复只还原事实，不发奖、不改背包。
func restore(data: Dictionary) -> void:
	log.restore(data)
	changed.emit()


func clear() -> void:
	if busy:
		return
	log.clear()
	changed.emit()
	_inventory = null
	_economy = null
	_day = Callable()
	_save = Callable()


func _steps_met(quest: QuestData) -> bool:
	var steps: Array[QuestStep] = quest.deliver_steps()
	if steps.is_empty():
		return false
	for step: QuestStep in steps:
		if _count_of(step.item_id) < step.count:
			return false
	return true


## 奖励必须现在就能装下：交付物与奖励物在数据层被禁止相同，扣货只会让容量更宽裕。
func _rewards_fit(quest: QuestData) -> bool:
	for reward: QuestReward in quest.reward_items:
		if reward == null or reward.item_id == &"" or reward.count <= 0:
			continue
		if _inventory.definition(reward.item_id) == null:
			push_warning("[quests] 奖励物品未定义：%s" % reward.item_id)
			return false
		if not _inventory.has_space_for(reward.item_id, reward.count):
			return false
	return true


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
