extends Node
## 第一章流程适配：只在正常玩法边界安排后续，不在恢复过程中产生剧情或投递。

const FINAL_QUEST: StringName = &"ch1_06_lamps"
const FINAL_EVENT: StringName = &"ch1_market_memory"

var enabled: bool = false
var _quests: RefCounted
var _mail: RefCounted
var _events: RefCounted
var _play: Callable
var _context: Callable
var _pending: bool = false


func configure(quests: RefCounted, mail: RefCounted, events: RefCounted, play: Callable, context: Callable) -> void:
	_quests = quests
	_mail = mail
	_events = events
	_play = play
	_context = context
	quests.completed.connect(_completed)


func start_new_game() -> void:
	if enabled: _mail.deliver(&"farm_welcome")


func request_followup() -> void:
	if enabled and _quests.status_of(FINAL_QUEST) == 3:
		_pending = true


func cancel_pending() -> void:
	_pending = false


func _completed(_id: StringName) -> void:
	request_followup()


func _process(_delta: float) -> void:
	if not enabled or not _pending or not _context.is_valid() or not bool(_context.call()): return
	_pending = false
	if _quests.status_of(FINAL_QUEST) != 3: return
	# 来信投递是独立的幂等用例，不在动画结束回调发放；写盘失败保留待保存事实。
	_mail.deliver(&"chapter_one_complete")
	if not _events.has_completed(FINAL_EVENT): _play.call(FINAL_EVENT)


func _exit_tree() -> void:
	if is_instance_valid(_quests) and _quests.completed.is_connected(_completed): _quests.completed.disconnect(_completed)
	_pending = false
	_quests = null
	_mail = null
	_events = null
	_play = Callable()
	_context = Callable()
