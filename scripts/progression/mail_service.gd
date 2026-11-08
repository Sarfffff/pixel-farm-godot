extends RefCounted
## 邮件用例：所有写操作防重入；通知前提交整笔状态，恢复只还原事实。

signal changed
signal delivered(id: StringName)
signal read(id: StringName)
signal claimed(id: StringName)
signal save_failed

const State := preload("res://scripts/progression/mailbox_state.gd")
const MAIL_DIR: String = "res://data/mail"
var busy: bool = false
var save_pending: bool = false
var last_rejection: String = ""
var _state := State.new()
var _definitions: Dictionary[StringName, MailData] = {}
var _bag: Inventory
var _wallet: Economy
var _day: Callable
var _save: Callable


func configure(bag: Inventory, wallet: Economy, day: Callable, save: Callable) -> void:
	if busy: return
	_bag = bag
	_wallet = wallet
	_day = day
	_save = save


func load_definitions() -> void:
	if busy: return
	for file: String in ResourceLoader.list_directory(MAIL_DIR):
		if file.ends_with(".tres"):
			register_definition(load(MAIL_DIR.path_join(file)) as MailData)


func register_definition(letter: MailData) -> bool:
	if busy or letter == null or not letter.is_valid() or _definitions.has(letter.id):
		return false
	_definitions[letter.id] = letter
	return true


func definition(id: StringName) -> MailData:
	return _definitions.get(id)


func letters() -> Array[MailData]:
	var result: Array[MailData] = []
	for letter: MailData in _definitions.values():
		if _state.delivered(letter.id): result.append(letter)
	result.sort_custom(func(a: MailData, b: MailData) -> bool:
		var a_day: int = int(_state.status(a.id).day)
		var b_day: int = int(_state.status(b.id).day)
		if a_day != b_day: return a_day > b_day
		if a.order != b.order: return a.order < b.order
		return String(a.id) < String(b.id))
	return result


func status(id: StringName) -> Dictionary:
	return _state.status(id)


func unread_count() -> int:
	return _state.unread_count()


func deliver(id: StringName) -> bool:
	var letter: MailData = definition(id)
	if busy or letter == null or _state.delivered(id): return false
	busy = true
	_state.deliver(id, maxi(1, int(_day.call())) if _day.is_valid() else 1, not letter.has_attachments())
	_persist()
	delivered.emit(id)
	changed.emit()
	busy = false
	return true


func mark_read(id: StringName) -> bool:
	if busy or not _state.delivered(id) or _state.status(id).read: return false
	busy = true
	_state.mark_read(id)
	_persist()
	read.emit(id)
	changed.emit()
	busy = false
	return true


func claim_hint(id: StringName) -> String:
	var letter: MailData = definition(id)
	if letter == null or not _state.delivered(id): return "这封信尚未投递"
	if not letter.is_valid(): return "附件配置暂不可用"
	if _state.status(id).claimed or not letter.has_attachments(): return "这封信没有待领取附件"
	if _bag == null or (letter.coins > 0 and _wallet == null): return "附件服务暂不可用"
	for item: StringName in _items(letter):
		if _bag.definition(item) == null: return "附件配置暂不可用"
	if not _bag.has_space_for_batch(_items(letter)): return "背包放不下整批附件，请整理后再领取"
	return ""


func claim(id: StringName) -> bool:
	if busy: return false
	last_rejection = claim_hint(id)
	if not last_rejection.is_empty(): return false
	var letter: MailData = definition(id)
	busy = true
	_bag.begin_update()
	_state.mark_claimed(id)
	var items: Dictionary[StringName, int] = _items(letter)
	for item: StringName in items:
		_bag.add_item(item, items[item], &"mail")
	# 钱包通知和背包批量通知都只能看到全部附件与领取事实已提交的结果。
	if letter.coins > 0: _wallet.earn(letter.coins)
	_bag.end_update()
	_persist()
	claimed.emit(id)
	changed.emit()
	busy = false
	return true


func retry_save() -> bool:
	if busy: return false
	busy = true
	_persist()
	changed.emit()
	busy = false
	return not save_pending


## 由整合层在完整快照成功写入后调用；不重试业务或再次发放附件。
func confirm_saved() -> void:
	if not save_pending: return
	save_pending = false
	changed.emit()


func encode() -> Dictionary:
	return _state.encode()


func restore(data: Dictionary) -> void:
	if busy: return
	busy = true
	_state.restore(data)
	save_pending = false
	last_rejection = ""
	changed.emit()
	busy = false


func clear() -> void:
	if busy: return
	_state.restore({})
	_bag = null
	_wallet = null
	_day = Callable()
	_save = Callable()


func _items(letter: MailData) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for attachment: MailAttachment in letter.attachments:
		result[attachment.item_id] = int(result.get(attachment.item_id, 0)) + attachment.count
	return result


func _persist() -> void:
	save_pending = true
	if _save.is_valid(): save_pending = not bool(_save.call())
	if save_pending: save_failed.emit()
