extends Node
## 任务事实只读自 QuestService；此处仅持有列表选择、提示和唯一追踪 ID。
## 由组合根显式持有/挂树，地点文案由组合根注入，不查 NPC 或 SceneTree。

const Status := preload("res://scripts/progression/quest_log.gd").Status

signal tracking_changed(id: StringName)

var _service: RefCounted
var _inventory: Inventory
var _panel: Control
var _hud: Control
var _save: Node
var _location_text: Callable
var _selected_id: StringName = &""
var _tracked_id: StringName = &""
var _message: String = ""
var _refresh_pending: bool = false


## Views 须已 ready；save 可选，提供 restored 信号。location_text(giver_id) -> String。
func configure(service: RefCounted, inventory: Inventory, panel: Control, hud: Control = null, save: Node = null, location_text: Callable = Callable()) -> void:
	_unbind()
	_service = service
	_inventory = inventory
	_panel = panel
	_hud = hud
	_save = save
	_location_text = location_text
	_service.changed.connect(_on_changed)
	_service.save_failed.connect(_on_save_failed)
	_inventory.changed.connect(_on_changed)
	if is_instance_valid(_save): _save.restored.connect(_on_restored)
	if is_instance_valid(_panel):
		_panel.selection_requested.connect(_select)
		_panel.accept_requested.connect(_accept)
		_panel.deliver_requested.connect(_deliver)
		_panel.track_requested.connect(track)
		_panel.untrack_requested.connect(_untrack)
		_panel.refresh_requested.connect(refresh)
		_panel.tree_exiting.connect(_on_panel_exiting)
	if is_instance_valid(_hud):
		_hud.journal_requested.connect(_open_journal)
		_hud.tree_exiting.connect(_on_hud_exiting)
	_selected_id = &""
	_tracked_id = &""
	_message = ""
	refresh()


func refresh() -> void:
	if _service == null: return
	if _tracked_id != &"" and _service.status_of(_tracked_id) != Status.ACTIVE:
		_tracked_id = &""
		tracking_changed.emit(_tracked_id)
	var rows: Array[Dictionary] = []
	var selected: Dictionary = {}
	var tracked: Dictionary = {}
	for quest: QuestData in _service.definitions():
		var row: Dictionary = _describe(quest)
		rows.append({"id": quest.id, "text": "%s · %s" % [row.status_text, quest.title]})
		if _selected_id == &"" and row.status != Status.LOCKED: _selected_id = quest.id
		if quest.id == _selected_id: selected = row
		if quest.id == _tracked_id: tracked = row
	if selected.is_empty() and not rows.is_empty():
		_selected_id = rows[0].id
		selected = _describe(_find_definition(_selected_id))
	if is_instance_valid(_panel):
		_panel.render({"rows": rows, "selected_id": _selected_id, "detail": selected, "message": _message})
	if is_instance_valid(_hud):
		_hud.render({"target": tracked, "message": _message})


func tracked_id() -> StringName:
	return _tracked_id


## 只允许追踪一个已接任务；清空使用空 ID。无自动切到另一任务的隐含状态。
func track(id: StringName) -> void:
	if _service == null: return
	if id != &"" and _service.status_of(id) != Status.ACTIVE: return
	if id == _tracked_id: return
	_tracked_id = id
	tracking_changed.emit(id)
	refresh()


## 新可选分区 quest_tracking；不包含任务进度/奖励事实，不改变正式保存版本。
func encode_tracking() -> Dictionary:
	return {"version": 1, "tracked_id": String(_tracked_id)}


## 在 quests 恢复后调用；缺失/坏值/未知 ID/非进行中 ID 均清空，不接取、不交付。
func restore_tracking(data: Dictionary) -> void:
	var id: StringName = &""
	var raw: Variant = data.get("tracked_id", "")
	var version: Variant = data.get("version", 1)
	if (typeof(version) == TYPE_INT or typeof(version) == TYPE_FLOAT) and version == 1:
		if typeof(raw) == TYPE_STRING or typeof(raw) == TYPE_STRING_NAME:
			id = StringName(raw)
	if _service == null or _service.status_of(id) != Status.ACTIVE: id = &""
	_tracked_id = id
	_message = ""
	tracking_changed.emit(id)
	refresh()


func _describe(quest: QuestData) -> Dictionary:
	var status: int = _service.status_of(quest.id)
	var progress: Array[Dictionary] = _service.progress(quest.id)
	var ready: bool = _service.can_deliver(quest.id)
	var status_text: String = ["未解锁", "可接取", "进行中", "已完成"][status]
	if ready: status_text = "可交付"
	var giver: String = quest.giver_name if not quest.giver_name.is_empty() else String(quest.giver)
	if giver.is_empty(): giver = "农场委托"
	var location: String = String(_location_text.call(quest.giver)) if _location_text.is_valid() else ""
	if location.is_empty(): location = "寻找%s（地点线索待补充）" % giver
	var lines: Array[String] = []
	for row: Dictionary in progress:
		lines.append("%s · 已交付" % row.text if status == Status.COMPLETED else "%s · %d/%d" % [row.text, row.have, row.need])
	var rewards: Array[String] = []
	if quest.reward_coins > 0: rewards.append("%d 金币" % quest.reward_coins)
	for reward: QuestReward in quest.reward_items:
		if reward != null: rewards.append("%s ×%d" % [_inventory.item_name(reward.item_id), reward.count])
	var hint: String = ""
	if status == Status.ACTIVE and not _service.busy and _service.has_method(&"delivery_hint"):
		hint = String(_service.delivery_hint(quest.id))
	var next: String = ""
	match status:
		Status.LOCKED:
			var names: Array[String] = []
			for required: StringName in quest.requires:
				if _service.status_of(required) != Status.COMPLETED:
					var prerequisite: QuestData = _find_definition(required)
					names.append(prerequisite.title if prerequisite != null else String(required))
			next = "先完成：" + "、".join(names)
		Status.AVAILABLE: next = "接取委托：%s" % giver
		Status.ACTIVE:
			if ready:
				next = "前往%s，向%s交付" % [location, giver]
				if not hint.is_empty(): next = hint
			else:
				for row: Dictionary in progress:
					if not row.done:
						next = "准备材料：%s · %d/%d" % [row.text, row.have, row.need]
						break
		Status.COMPLETED: next = "委托已完成；在日志中查看下一项委托"
	return {
		"id": quest.id, "title": quest.title, "summary": quest.summary,
		"category": "主线 · 第%d章" % quest.chapter, "giver": giver, "location": location,
		"status": status, "status_text": status_text, "progress_text": "\n".join(lines),
		"progress_heading": "材料记录（已交付）" if status == Status.COMPLETED else "材料进度（当前背包）",
		"reward_text": "、".join(rewards), "next": next, "delivery_hint": hint,
		"can_accept": status == Status.AVAILABLE and not _service.busy,
		"can_deliver": ready and hint.is_empty() and not _service.busy,
		"can_track": status == Status.ACTIVE, "tracked": quest.id == _tracked_id,
	}


func _select(id: StringName) -> void:
	_selected_id = id
	_message = ""
	refresh()


func _accept(id: StringName) -> void:
	_message = ""
	if _service.accept(id):
		if _tracked_id == &"": track(id)
	else: _message = "暂时无法接取，任务状态可能已变化"
	refresh()


func _deliver(id: StringName) -> void:
	_message = ""
	if not _service.deliver(id):
		_message = String(_service.delivery_hint(id)) if _service.has_method(&"delivery_hint") else "暂时无法交付，请确认材料与奖励空间"
	refresh()


func _find_definition(id: StringName) -> QuestData:
	for quest: QuestData in _service.definitions():
		if quest.id == id: return quest
	return null


func _untrack() -> void:
	track(&"")


func _on_changed() -> void:
	refresh()
	# 用例通知发生在事务 busy 期间；事务结束后重新查询服务，避免按钮一直禁用。
	if _service != null and _service.busy and not _refresh_pending:
		_refresh_pending = true
		_refresh_settled.call_deferred()


func _refresh_settled() -> void:
	_refresh_pending = false
	refresh()


func _on_restored() -> void:
	_message = ""
	_on_changed()


func _on_save_failed() -> void:
	_message = "任务已结算，但存档失败 · 请手动重试保存"
	refresh()


func _open_journal() -> void:
	if is_instance_valid(_panel): _panel.set_open(true)


func _on_panel_exiting() -> void:
	_unbind_panel()
	if not is_instance_valid(_hud): _unbind()


func _on_hud_exiting() -> void:
	_unbind_hud()
	if not is_instance_valid(_panel): _unbind()


func _unbind_panel() -> void:
	if is_instance_valid(_panel):
		for binding: Array in [
			[_panel.selection_requested, _select], [_panel.accept_requested, _accept],
			[_panel.deliver_requested, _deliver], [_panel.track_requested, track],
			[_panel.untrack_requested, _untrack], [_panel.refresh_requested, refresh],
			[_panel.tree_exiting, _on_panel_exiting],
		]:
			if binding[0].is_connected(binding[1]): binding[0].disconnect(binding[1])
	_panel = null


func _unbind_hud() -> void:
	if is_instance_valid(_hud):
		if _hud.journal_requested.is_connected(_open_journal): _hud.journal_requested.disconnect(_open_journal)
		if _hud.tree_exiting.is_connected(_on_hud_exiting): _hud.tree_exiting.disconnect(_on_hud_exiting)
	_hud = null


func dispose() -> void:
	_unbind()


func _exit_tree() -> void:
	_unbind()


func _unbind() -> void:
	_unbind_panel()
	_unbind_hud()
	if is_instance_valid(_service):
		if _service.changed.is_connected(_on_changed): _service.changed.disconnect(_on_changed)
		if _service.save_failed.is_connected(_on_save_failed): _service.save_failed.disconnect(_on_save_failed)
	if is_instance_valid(_inventory) and _inventory.changed.is_connected(_on_changed): _inventory.changed.disconnect(_on_changed)
	if is_instance_valid(_save) and _save.restored.is_connected(_on_restored): _save.restored.disconnect(_on_restored)
	_service = null
	_inventory = null
	_save = null
	_location_text = Callable()
