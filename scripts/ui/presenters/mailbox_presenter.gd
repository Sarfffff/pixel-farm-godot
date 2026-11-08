extends Node
## 邮件显示快照与意图适配；业务规则归MailService，所有绑定均可解除。

var _service: RefCounted
var _bag: Inventory
var _view: Control
var _selected: StringName = &""
var _message: String = ""


func configure(service: RefCounted, bag: Inventory, view: Control) -> void:
	disconnect_bindings()
	_service = service
	_bag = bag
	_view = view
	_service.changed.connect(refresh)
	_bag.changed.connect(refresh)
	_view.opened.connect(_opened)
	_view.selected.connect(_select)
	_view.claim_requested.connect(_claim)
	_view.retry_save_requested.connect(_retry)
	refresh()


func open_mailbox() -> void:
	if is_instance_valid(_view): _view.set_open(true)


func snapshot() -> Dictionary:
	var data: Dictionary = {"letters": [], "unread": _service.unread_count(), "selected": _selected, "save_pending": _service.save_pending}
	for letter: MailData in _service.letters():
		var status: Dictionary = _service.status(letter.id)
		data.letters.append({"id": letter.id, "text": ("● " if not status.read else "") + letter.title + (" · 附件" if not status.claimed else "")})
	var chosen: MailData = _service.definition(_selected)
	if chosen != null and not _service.status(_selected).is_empty():
		var status: Dictionary = _service.status(_selected)
		data.title = chosen.title + "\n来自：" + chosen.sender
		data.body = chosen.body
		var attachment_names: PackedStringArray = []
		if chosen.coins > 0: attachment_names.append("金币 ×%d" % chosen.coins)
		for item: MailAttachment in chosen.attachments:
			attachment_names.append("%s ×%d" % [_bag.item_name(item.item_id), item.count])
		data.attachments = "附件：" + "、".join(attachment_names) if not attachment_names.is_empty() else "这封信没有附件"
		data.claim_hint = _service.claim_hint(_selected)
		data.can_claim = String(data.claim_hint).is_empty()
		data.claim_text = "附件已领取" if status.claimed and chosen.has_attachments() else "领取全部附件" if chosen.has_attachments() else "无附件"
	data.note = _message
	if _message.is_empty() and chosen != null and chosen.has_attachments() and not _service.status(_selected).claimed:
		data.note = data.get("claim_hint", "")
	if _service.save_pending:
		data.note = "本次进度尚未保存，请重试保存；已领取附件不会再次发放。"
	return data


func refresh() -> void:
	if _service == null or not is_instance_valid(_view): return
	if _service.status(_selected).is_empty():
		var letters: Array = _service.letters()
		_selected = letters[0].id if not letters.is_empty() else &""
	_view.render(snapshot())


func _opened() -> void:
	_message = ""
	refresh()
	_select(_selected)


func _select(id: StringName) -> void:
	if _service.definition(id) == null or _service.status(id).is_empty(): return
	_selected = id
	_message = ""
	_service.mark_read(id)
	refresh()


func _claim(id: StringName) -> void:
	if id != _selected: return
	_message = "附件已放入背包" if _service.claim(id) else _service.last_rejection
	refresh()


func _retry() -> void:
	# 未保存提示由服务快照统一提供，其他入口保存成功后不会残留旧错误。
	_message = "保存成功" if _service.retry_save() else ""
	refresh()


func disconnect_bindings() -> void:
	if _service != null and _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)
	if is_instance_valid(_bag) and _bag.changed.is_connected(refresh): _bag.changed.disconnect(refresh)
	if is_instance_valid(_view):
		for binding: Array in [[_view.opened, _opened], [_view.selected, _select], [_view.claim_requested, _claim], [_view.retry_save_requested, _retry]]:
			var event: Signal = binding[0]
			if event.is_connected(binding[1]): event.disconnect(binding[1])
	_service = null
	_bag = null
	_view = null


func _exit_tree() -> void:
	disconnect_bindings()
