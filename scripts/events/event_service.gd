extends RefCounted
## 同步一次性用例。先记录完成，再调用原子结果端口；播放结束不参与结算。
## commit(id, outcome) -> bool：失败不得修改外部事实；成功通知前外部事务须完整。

signal committed(id: StringName)
signal changed
signal save_failed(id: StringName)

const State := preload("res://scripts/events/event_state.gd")

var busy: bool = false
var last_rejection: StringName = &""
var _state := State.new()
var _definitions: Dictionary[StringName, StoryEvent] = {}
var _query: Callable
var _commit: Callable
var _save: Callable
var _released: bool = false


func configure(query: Callable, commit: Callable = Callable(), save: Callable = Callable()) -> void:
	if busy or _released: return
	_query = query
	_commit = commit
	_save = save


func register_event(event: StoryEvent) -> bool:
	if busy or _released or event == null or not event.is_valid() or _definitions.has(event.id): return false
	# 配置在注册后冻结为自己的副本，调用者修改 Resource 不会改动正在执行的规则。
	_definitions[event.id] = event.duplicate(true) as StoryEvent
	return true


func load_directory(path: String) -> int:
	var count: int = 0
	for file: String in ResourceLoader.list_directory(path):
		if file.ends_with(".tres") and register_event(load(path.path_join(file)) as StoryEvent): count += 1
	return count


func definition(id: StringName) -> StoryEvent:
	var event: StoryEvent = _definitions.get(id)
	return event.duplicate(true) as StoryEvent if event != null else null


func has_completed(id: StringName) -> bool:
	return _state.has_completed(id)


func status_of(id: StringName) -> StringName:
	if _released: return &"released"
	if has_completed(id): return &"completed"
	if not _definitions.has(id): return &"unknown"
	return &"available" if can_trigger(id) else &"blocked"


func can_trigger(id: StringName) -> bool:
	if busy or _released or has_completed(id) or not _definitions.has(id): return false
	# 条件查询同样位于重入保护内，端口必须是只读同步查询。
	busy = true
	var allowed: bool = _conditions_met(_definitions[id])
	busy = false
	return allowed


func trigger(id: StringName) -> bool:
	last_rejection = &"unavailable"
	if busy or _released or has_completed(id) or not _definitions.has(id): return false
	busy = true
	var event: StoryEvent = _definitions[id]
	if not _conditions_met(event) or (event.outcome != &"" and not _commit.is_valid()):
		busy = false
		return false
	var day: int = 1
	if _query.is_valid():
		var raw: Variant = _query.call(&"day", &"")
		if (typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT) and is_finite(float(raw)) and float(raw) >= 1 and float(raw) <= 2147483647: day = int(raw)
	_state.complete(id, day)
	if event.outcome != &"" and not bool(_commit.call(id, event.outcome)):
		_state.forget(id)
		last_rejection = &"commit_failed"
		busy = false
		return false
	# 编码允许事务中的保存读取完整事实，恢复/释放在 busy 期间拒绝。
	committed.emit(id)
	changed.emit()
	if _save.is_valid() and not bool(_save.call()): save_failed.emit(id)
	last_rejection = &""
	busy = false
	return true


func encode() -> Dictionary:
	return _state.encode()


func restore(data: Dictionary) -> bool:
	if busy or _released: return false
	busy = true
	if not _state.restore(data):
		busy = false
		return false
	changed.emit()
	busy = false
	return true


func release() -> bool:
	if busy: return false
	_released = true
	_query = Callable()
	_commit = Callable()
	_save = Callable()
	_definitions.clear()
	_state.clear()
	return true


func _conditions_met(event: StoryEvent) -> bool:
	for condition: StoryCondition in event.conditions:
		if not _query.is_valid() or not condition.matches(_query.call(StringName(condition.kind), condition.key)): return false
	return true
