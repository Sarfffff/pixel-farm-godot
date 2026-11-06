extends SceneTree
## B2-02 章节任务：模型状态机、交付事务、重入与容量、存档往返、坏档字段。
## 模型部分不依赖场景树；事务部分走组合根装配的真实背包、钱包与存档。

const MAIN_SCENE: String = "res://scenes/main.tscn"
const QuestLogScript := preload("res://scripts/progression/quest_log.gd")
const CH1: Array[StringName] = [
	&"ch1_01_gate", &"ch1_02_basket", &"ch1_03_timber",
	&"ch1_04_river", &"ch1_05_flowerbed", &"ch1_06_lamps",
]
const KNOWN_GIVERS: Array[StringName] = [&"shopkeeper", &"carpenter", &"fisherman", &"gardener"]

var _failures: int = 0
var _main: Node2D
var _quests: RefCounted
var _inventory: Inventory
var _economy: Economy
var _save: Node
var _clock: Node


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[quests] FAIL: " + message)


## 独立的任务簿：不建场景也能验证定义、解锁与编解码。
func _new_log() -> RefCounted:
	var log: RefCounted = QuestLogScript.new()
	log.load_definitions()
	return log


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_check_model_definition()
	_check_model_state_machine()
	_check_model_encoding()

	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	_main.get_node("Systems/Save").set(&"autoload_enabled", false)
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_quests = _main.get(&"quests")
	_inventory = get_first_node_in_group(&"inventory") as Inventory
	_economy = get_first_node_in_group(&"economy") as Economy
	_save = _main.get_node("Systems/Save")
	_clock = _main.get_node("Systems/Time")
	_clock.set(&"running", false)
	if _quests == null or _inventory == null or _economy == null:
		_check(false, "the composition root exposes the quest service, bag and wallet")
		_finish()
		return

	_check_data_contract()
	await _check_transaction()
	await _check_capacity_guard()
	await _check_reentrancy()
	await _check_save_failure()
	await _check_save_round_trip()
	await _check_legacy_and_malformed()

	_finish()


## —— 1. 数据契约：数据文件就是规则 ——
func _check_model_definition() -> void:
	var log := _new_log()
	var list: Array = log.definitions()
	_check(list.size() == CH1.size(), "the chapter ships %d quest definitions (found %d)" % [CH1.size(), list.size()])
	var ids: Array[StringName] = []
	var previous_order: int = -2147483648
	var sorted: bool = true
	for quest: QuestData in list:
		ids.append(quest.id)
		if quest.order < previous_order:
			sorted = false
		previous_order = quest.order
		_check(quest.is_valid(), "%s has a title, steps and a sane coin reward" % quest.id)
		_check(KNOWN_GIVERS.has(quest.giver), "%s names one of the existing villagers as giver" % quest.id)
		_check(not quest.offer_lines.is_empty() and not quest.done_lines.is_empty(), "%s carries dialogue lines" % quest.id)
	_check(ids == CH1, "quest ids and their authored order match the chapter script")
	_check(sorted, "definitions come back sorted by chapter order")
	for quest: QuestData in list:
		for required: StringName in quest.requires:
			_check(log.define(required) != null, "%s only requires known quests (%s)" % [quest.id, required])
			_check(required != quest.id, "%s does not require itself" % quest.id)
	_check((log.define(CH1[0]) as QuestData).requires.is_empty(), "the chapter opens with a quest that has no prerequisite")


## —— 2. 状态机：锁定 → 可接 → 进行中 → 完成，只认事实 ——
func _check_model_state_machine() -> void:
	var log := _new_log()
	_check(log.status_of(CH1[0]) == 1, "the first quest starts available")
	for index in range(1, CH1.size()):
		_check(log.status_of(CH1[index]) == 0, "%s stays locked before its prerequisite" % CH1[index])
	_check(log.status_of(&"no_such_quest") == 0, "unknown ids read as locked instead of crashing")
	_check(not log.accept(CH1[1], 1), "a locked quest cannot be accepted")
	_check(log.accept(CH1[0], 3), "an available quest can be accepted")
	_check(log.status_of(CH1[0]) == 2 and log.accepted_day(CH1[0]) == 3, "accepting records the day and moves to active")
	_check(not log.accept(CH1[0], 3), "accepting twice is refused")
	_check(not log.complete(CH1[1], 4), "a quest that was never accepted cannot complete")
	_check(log.complete(CH1[0], 5), "an active quest can complete")
	_check(log.status_of(CH1[0]) == 3 and log.completed_day(CH1[0]) == 5, "completion records its day")
	_check(not log.is_active(CH1[0]) and log.is_completed(CH1[0]), "completed leaves the active set")
	_check(not log.complete(CH1[0], 6), "a completed quest cannot complete again")
	_check(log.status_of(CH1[1]) == 1, "finishing a quest unlocks the next one")
	_check(log.status_of(CH1[2]) == 0, "the quest after that stays locked")
	var completed_ids: Array[StringName] = log.completed_ids()
	_check(log.completed_count() == 1 and completed_ids.size() == 1 and completed_ids[0] == CH1[0], "the completion list matches the facts")


## —— 3. 编解码：只认已知 id 与正整数天数，恢复不中断 ——
func _check_model_encoding() -> void:
	var log := _new_log()
	log.accept(CH1[0], 2)
	log.complete(CH1[0], 4)
	var document: Dictionary = log.encode()
	_check(document.has(&"accepted") and document.has(&"completed"), "the section encodes both tables")
	var restored := _new_log()
	restored.restore(document)
	_check(restored.status_of(CH1[0]) == 3 and restored.completed_day(CH1[0]) == 4, "a written section restores the same facts")

	var broken := _new_log()
	broken.restore({&"accepted": {&"no_such_quest": 3, &"ch1_01_gate": "bad"}, &"completed": {&"ch1_02_basket": 4}})
	var rewritten: Dictionary = broken.encode()
	var accepted: Dictionary = rewritten.get(&"accepted", {})
	var completed: Dictionary = rewritten.get(&"completed", {})
	_check(not accepted.has("no_such_quest"), "unknown ids are dropped on load")
	_check(int(accepted.get("ch1_01_gate", 0)) == 1, "a non-numeric day falls back to day 1")
	_check(int(completed.get("ch1_02_basket", 0)) == 4, "a valid completion day is preserved")
	_check(broken.status_of(CH1[1]) == 3, "a completed entry without acceptance still reads as completed")
	_check(broken.status_of(CH1[0]) == 2, "a non-numeric accepted day still marks the quest active on day 1")
	broken.clear()
	_check(broken.completed_count() == 0 and broken.status_of(CH1[0]) == 1, "clearing the log reopens the chapter")


## —— 4. 组合根装配与物品契约 ——
func _check_data_contract() -> void:
	var log: RefCounted = _quests.get(&"log")
	var list: Array[QuestData] = log.definitions()
	for quest: QuestData in list:
		var delivered: Array[StringName] = []
		for step: QuestStep in quest.deliver_steps():
			delivered.append(step.item_id)
			_check(_inventory.definition(step.item_id) != null, "%s requires a defined item (%s)" % [quest.id, step.item_id])
		for reward: QuestReward in quest.reward_items:
			_check(_inventory.definition(reward.item_id) != null, "%s rewards a defined item (%s)" % [quest.id, reward.item_id])
			_check(not delivered.has(reward.item_id), "%s does not reward the item it just consumed (%s)" % [quest.id, reward.item_id])
	var section: Dictionary = _save.call(&"collect")
	_check(section.has(&"quests"), "the save document carries a quests section")


## —— 5. 交付事务：材料不足不动、成功一次、重复交付不重复发奖 ——
func _check_transaction() -> void:
	var coins_before: int = _economy.coins
	var completions: Array[StringName] = []
	_quests.completed.connect(func(id: StringName) -> void: completions.append(id))

	_check(not _quests.can_deliver(CH1[0]), "an empty bag cannot meet the requirement")
	_check(not _quests.deliver(CH1[0]), "delivering before accepting is refused")
	_check(_quests.accept(CH1[0]), "the opening quest can be accepted through the service")
	_check(not _quests.deliver(CH1[0]), "delivering without the goods is refused")
	_check(_economy.coins == coins_before and _quests.status_of(CH1[0]) == 2, "a refused delivery changes nothing")

	_inventory.add_item(&"fiber", 6)
	var rows: Array = _quests.progress(CH1[0])
	_check(rows.size() == 1 and int(rows[0][&"have"]) == 6 and bool(rows[0][&"done"]), "progress follows the bag up to the requirement")
	_check(_quests.can_deliver(CH1[0]), "six fiber make the quest deliverable")

	_check(_quests.deliver(CH1[0]), "delivering with the goods succeeds")
	_check(_quests.status_of(CH1[0]) == 3, "a delivered quest becomes completed")
	_check(_inventory.count_of(&"fiber") == 0, "delivery consumes exactly the requirement")
	_check(_economy.coins == coins_before + 120, "delivery pays the authored coin reward")
	_check(_inventory.count_of(&"carrot_seeds") == 8, "delivery grants the authored item reward (5 start + 3)")
	_check(completions.size() == 1, "the completed signal fires once")
	await process_frame

	_check(not _quests.deliver(CH1[0]), "delivering again is refused")
	_check(_economy.coins == coins_before + 120 and _inventory.count_of(&"carrot_seeds") == 8, "a repeated delivery grants nothing")
	_check(completions.size() == 1, "the completed signal never repeats")
	_check(_quests.status_of(CH1[1]) == 1, "finishing a quest unlocks the next one")


## —— 6. 容量：装不下就不扣货、不发钱 ——
func _check_capacity_guard() -> void:
	_check(_quests.accept(CH1[1]), "the unlocked follow-up can be accepted")
	_inventory.add_item(&"carrot", 5)
	var guard: int = 0
	while _inventory.has_space_for(&"stone", 1) and guard < 80:
		_inventory.add_item(&"stone", 99, &"purchase")
		guard += 1
	_check(not _inventory.has_space_for(&"turnip_seeds", 2), "the bag is genuinely full for the reward item")
	var coins_before: int = _economy.coins
	_check(_quests.can_deliver(CH1[1]), "progress alone would allow delivery")
	_check(not _quests.deliver(CH1[1]), "a full bag blocks delivery before anything is removed")
	_check(_inventory.count_of(&"carrot") == 5, "the goods stay in the bag when the reward would not fit")
	_check(_economy.coins == coins_before, "the wallet is untouched when the reward would not fit")
	_check(_quests.status_of(CH1[1]) == 2, "the quest stays active after the blocked delivery")
	_inventory.remove_item(&"stone", 99)
	_check(_quests.deliver(CH1[1]), "the same delivery succeeds once space is freed")
	_check(_quests.status_of(CH1[1]) == 3 and _inventory.count_of(&"turnip_seeds") >= 2, "freed space lets the reward through")
	await process_frame


## —— 7. 重入：观察者在通知里再次提交不得重复发奖，且看到的是完成后的状态 ——
func _check_reentrancy() -> void:
	# 上一步把背包塞满了石头，先腾出空间，否则这里测的就不是重入而是容量。
	for filler: StringName in [&"stone", &"carrot", &"fiber", &"egg"]:
		_take_all(filler)
	_check(_quests.accept(CH1[2]), "the third quest can be accepted")
	_inventory.add_item(&"wood", 12)
	var coins_before: int = _economy.coins
	var reentered: Array[bool] = [false]
	var observed_completed: Array[bool] = [false]
	var observed_reward: Array[bool] = [false]
	var watcher := func() -> void:
		if _quests.status_of(CH1[2]) != 3:
			return
		observed_completed[0] = true
		observed_reward[0] = _inventory.count_of(&"hardwood") >= 2
		reentered[0] = bool(_quests.deliver(CH1[2]))
	_inventory.changed.connect(watcher)
	_check(_quests.deliver(CH1[2]), "the third quest delivers")
	_inventory.changed.disconnect(watcher)
	_check(observed_completed[0], "an observer notified by the bag already sees the committed quest state")
	_check(observed_reward[0], "the granted reward is part of the same notification")
	_check(not reentered[0], "a delivery request from inside the notification is refused")
	_check(_economy.coins == coins_before + 180 and _inventory.count_of(&"hardwood") == 2, "reentrancy cannot pay the reward twice")
	await process_frame


## —— 8. 写档失败：结算保留、提示可见、不重复发奖 ——
func _check_save_failure() -> void:
	_check(_quests.accept(CH1[3]), "the fourth quest can be accepted")
	_inventory.add_item(&"common_carp", 2)
	var failures: Array[int] = [0]
	var record := func() -> void: failures[0] += 1
	_quests.save_failed.connect(record)
	_quests.configure(_inventory, _economy, func() -> int: return int(_clock.day), func() -> bool: return false)
	var coins_before: int = _economy.coins
	_check(_quests.deliver(CH1[3]), "the delivery still settles when the save fails")
	_check(failures[0] == 1, "the failed write is reported once")
	_check(_quests.status_of(CH1[3]) == 3 and _economy.coins == coins_before + 200, "a failed write keeps the settled result")
	_quests.save_failed.disconnect(record)
	_quests.configure(_inventory, _economy, func() -> int: return int(_clock.day), _save.save_game)
	await process_frame


## —— 9. 存读档：状态来自文件，恢复不发奖 ——
func _check_save_round_trip() -> void:
	var coins_after: int = _economy.coins
	var seeds: int = _inventory.count_of(&"fertilizer")
	_check(_save.call(&"save_game"), "the live session can write a save")
	_quests.restore({})
	_check(_quests.status_of(CH1[0]) == 1, "clearing the section reopens the chapter")
	var during_restore: Array[StringName] = []
	var record := func(id: StringName) -> void: during_restore.append(id)
	_quests.completed.connect(record)
	_check(_save.call(&"load_game"), "the written save loads back from disk")
	await process_frame
	_quests.completed.disconnect(record)
	_check(_quests.status_of(CH1[0]) == 3 and _quests.status_of(CH1[1]) == 3, "completed quests survive the disk round trip")
	_check(_quests.status_of(CH1[4]) == 1, "the quest after the last completion is available again after loading")
	_check(_economy.coins == coins_after, "restoring does not replay coin rewards")
	_check(_inventory.count_of(&"fertilizer") == seeds, "restoring does not replay item rewards")
	_check(during_restore.is_empty(), "restoring never fires completed")

	var document: Dictionary = _save.call(&"collect")
	_save.call(&"apply", document)
	_save.call(&"apply", document)
	await process_frame
	_check(_economy.coins == coins_after and _inventory.count_of(&"fertilizer") == seeds, "applying the same snapshot twice grants nothing extra")
	_check(_quests.status_of(CH1[0]) == 3, "repeated restores keep the state machine stable")


## —— 10. 旧档与坏档：没有该分区时整章回到可接，且不发钱 ——
func _check_legacy_and_malformed() -> void:
	var coins_before: int = _economy.coins
	_quests.restore({})
	_check(_quests.get(&"log").completed_count() == 0, "a legacy save without the section starts from scratch")
	_check(_quests.status_of(CH1[0]) == 1, "the opening quest is available again")
	_check(_economy.coins == coins_before, "loading a legacy save grants no coins")
	_quests.restore({&"accepted": {&"no_such_quest": 3}, &"completed": {&"ch1_03_timber": 0}})
	_check(_quests.status_of(CH1[2]) == 3, "a zero day is clamped to day 1 but keeps the completion")
	_check(_quests.status_of(CH1[0]) == 1, "unknown accepted ids do not unlock anything")
	await process_frame


func _take_all(id: StringName) -> void:
	var count: int = _inventory.count_of(id)
	if count > 0:
		_inventory.remove_item(id, count)


func _finish() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	print("[quests] model state machine, encoding, delivery transaction, capacity, reentrancy, save failure and round trip; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
