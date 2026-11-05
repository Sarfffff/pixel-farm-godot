extends Node
## 活动面板的交互与展示适配；业务服务不创建View，View不直接修改模型。

var _activities: Node
var _bag: Inventory
var _view: Control
var _toast: Node


func configure(activities: Node, bag: Inventory, view: Control, toast: Node) -> void:
	_activities = activities
	_bag = bag
	_view = view
	_toast = toast
	activities.panel_requested.connect(view.open)
	activities.reset_requested.connect(view.close)
	activities.notified.connect(_notify)
	activities.changed.connect(refresh)
	bag.changed.connect(refresh)
	view.opened.connect(_opened)
	view.closed.connect(_closed)
	view.refresh_requested.connect(refresh)
	view.deposit_requested.connect(_deposit)
	view.withdraw_requested.connect(_withdraw)
	view.fish_requested.connect(activities.fishing_action)
	view.visibility_changed.connect(_visibility_changed)
	activities.attach_panel(view)


func refresh() -> void:
	if not is_instance_valid(_view) or not _view.visible: return
	var state: Dictionary = {"message": _activities.message, "bag": [], "chest": []}
	if _view.mode == &"storage":
		for item: ItemData in _bag.definitions():
			var owned: int = _bag.count_of(item.id)
			var stored: int = _activities.storage.count_of(item.id)
			if owned > 0 and item.category != &"tool": state.bag.append({"id": item.id, "text": "%s ×%d" % [item.display_name, owned], "icon": item.icon})
			if stored > 0: state.chest.append({"id": item.id, "text": "%s ×%d" % [item.display_name, stored], "icon": item.icon})
	else:
		state.fishing_note = "每日投竿 %d/%d · 消耗体力 %d · 可按 Esc 结束" % [_activities.casts_today, _activities.settings.fishing_limit, _activities.settings.fishing_cost]
		state.fishing_text = _activities.fishing_text()
		state.fishing_progress = _activities.fishing_progress() * 100.0
		state.fishing_button = "收杆！ [F / 空格]" if _activities.fishing_state == &"bite" else "等待咬钩…" if _activities.fishing_state == &"waiting" else "领取鱼获" if _activities.pending_fish != &"" else "投竿 [F / 空格]"
	_view.render(state)


func _opened(_mode: StringName) -> void:
	_activities.message = ""
	_toast.clear()
	refresh()


func _closed(mode: StringName) -> void:
	if mode == &"fishing": _activities.cancel_fishing()


func _visibility_changed() -> void:
	_activities.set_storage_open(_view.visible and _view.mode == &"storage")


func _deposit(id: StringName, all: bool) -> void:
	var amount: int = mini(_bag.definition(id).max_stack, _bag.count_of(id)) if all else 1
	_activities.deposit(id, amount)


func _withdraw(id: StringName, all: bool) -> void:
	var amount: int = mini(_bag.definition(id).max_stack, _activities.storage.count_of(id)) if all else 1
	_activities.withdraw(id, amount)


func _notify(text: String) -> void:
	if not is_instance_valid(_view) or not _view.visible: _toast.show_message(text)


func _exit_tree() -> void:
	# 模型由同一会话持有；销毁Presenter时解除全部回调，支持移除/替换界面。
	if is_instance_valid(_activities):
		if is_instance_valid(_view):
			if _activities.panel_requested.is_connected(_view.open): _activities.panel_requested.disconnect(_view.open)
			if _activities.reset_requested.is_connected(_view.close): _activities.reset_requested.disconnect(_view.close)
		if _activities.notified.is_connected(_notify): _activities.notified.disconnect(_notify)
		if _activities.changed.is_connected(refresh): _activities.changed.disconnect(refresh)
		_activities.set_storage_open(false)
	if is_instance_valid(_bag) and _bag.changed.is_connected(refresh): _bag.changed.disconnect(refresh)
	if is_instance_valid(_view):
		var bindings: Array[Array] = [
			[_view.opened, _opened], [_view.closed, _closed],
			[_view.refresh_requested, refresh], [_view.deposit_requested, _deposit],
			[_view.withdraw_requested, _withdraw], [_view.visibility_changed, _visibility_changed],
		]
		if is_instance_valid(_activities): bindings.append([_view.fish_requested, _activities.fishing_action])
		for binding: Array in bindings:
			var event: Signal = binding[0]
			if event.is_connected(binding[1]): event.disconnect(binding[1])
