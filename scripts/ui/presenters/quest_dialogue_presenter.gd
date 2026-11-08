extends Node
## NPC 任务对话适配。规则与结算归 QuestService；这里只整理台词和选项。

const PREFIX: String = "quest:"
const Status := preload("res://scripts/progression/quest_log.gd").Status

var _quests: RefCounted
var _bag: Inventory
var _bindings: Array[Dictionary] = []


func configure(quests: RefCounted, bag: Inventory) -> void:
	unbind()
	_quests = quests
	_bag = bag


func bind_actor(actor: Node) -> void:
	if not actor.has_method(&"configure_quest_dialogue"):
		return
	for entry: Dictionary in _bindings:
		if entry.actor.get_ref() == actor:
			return
	var giver: StringName = actor.get(&"npc_id")
	var options: Callable = options_for.bind(giver)
	var response: Callable = respond.bind(giver)
	actor.configure_quest_dialogue(options, response)
	_bindings.append({&"actor": weakref(actor), &"options": options, &"response": response})


func options_for(giver: StringName) -> Array:
	var options: Array = []
	if _quests == null:
		return options
	for quest: QuestData in _quests.definitions():
		if quest.giver != giver:
			continue
		var status: int = _quests.status_of(quest.id)
		if status not in [Status.AVAILABLE, Status.ACTIVE]:
			continue
		var prefix: String = "委托" if status == Status.AVAILABLE else "交付" if _quests.can_deliver(quest.id) else "进度"
		options.append({&"id": StringName(PREFIX + "view:" + String(quest.id)), &"text": "%s：%s" % [prefix, quest.title]})
	return options


## actor 将意图转入此处，返回纯显示快照，由通用对话 View 渲染。
func respond(action: StringName, giver: StringName) -> Dictionary:
	var parts: PackedStringArray = String(action).split(":")
	if parts.size() != 3 or parts[0] != "quest":
		return {}
	if _quests == null or _bag == null:
		return _message("任务服务暂不可用，请稍后再来。")
	var id := StringName(parts[2])
	var quest: QuestData = _quests.definition(id)
	if quest == null or quest.giver != giver:
		return _message("这份委托不在我这里，请找委托人确认。")
	match parts[1]:
		"accept":
			if not _quests.accept_for(giver, id):
				return _message("任务状态已变化，请重新交谈。")
			return _details(quest, "已接取：" + quest.title, false)
		"deliver":
			if not _quests.deliver_for(giver, id):
				return _message(_quests.delivery_hint(id))
			var lines: Array[String] = quest.done_lines.duplicate()
			lines.append("已完成：%s\n%s" % [quest.title, _reward_text(quest)])
			return {&"lines": lines, &"options": _back_options()}
		"view":
			return _details(quest)
	return _message("请重新选择委托。")


func _details(quest: QuestData, heading: String = "", include_dialogue: bool = true) -> Dictionary:
	var status: int = _quests.status_of(quest.id)
	if status not in [Status.AVAILABLE, Status.ACTIVE]:
		return _message("这份委托已完成，或尚未开放。")
	var lines: Array[String] = []
	if include_dialogue:
		lines.assign(quest.offer_lines if status == Status.AVAILABLE else quest.progress_lines)
	var summary: String = heading if not heading.is_empty() else quest.title
	for row: Dictionary in _quests.progress(quest.id):
		summary += "\n%s（%d/%d）" % [row.text, row.have, row.need]
	summary += "\n" + _reward_text(quest)
	lines.append(summary)
	var options: Array = []
	if status == Status.AVAILABLE:
		options.append({&"id": StringName(PREFIX + "accept:" + String(quest.id)), &"text": "接下这份委托"})
	elif _quests.can_deliver(quest.id):
		options.append({&"id": StringName(PREFIX + "deliver:" + String(quest.id)), &"text": "交付物品并领取奖励"})
	options.append_array(_back_options())
	return {&"lines": lines, &"options": options}


func _reward_text(quest: QuestData) -> String:
	var parts: PackedStringArray = []
	if quest.reward_coins > 0:
		parts.append("%d 金币" % quest.reward_coins)
	for reward: QuestReward in quest.reward_items:
		if reward != null:
			parts.append("%s ×%d" % [_bag.item_name(reward.item_id), reward.count])
	return "奖励：" + "、".join(parts)


func _message(text: String) -> Dictionary:
	return {&"lines": [text], &"options": _back_options()}


func _back_options() -> Array:
	return [{&"id": &"__close", &"text": "结束交谈"}]


func unbind() -> void:
	for entry: Dictionary in _bindings:
		var actor: Node = entry.actor.get_ref()
		if is_instance_valid(actor) and actor.get(&"quest_options") == entry.options:
			actor.configure_quest_dialogue(Callable(), Callable())
	_bindings.clear()
	_quests = null
	_bag = null


func _exit_tree() -> void:
	unbind()
