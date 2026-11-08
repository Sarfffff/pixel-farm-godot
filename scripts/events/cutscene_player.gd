extends Node
## 可取消的逐帧执行器；不用等待动画/Timer 的悬挂协程。
## lock_acquire(owner) -> bool / lock_release(owner) 必须是按 owner 计数的独占租约。

signal playback_started(id: StringName)
signal playback_finished(id: StringName, reason: StringName)
signal choice_selected(id: StringName, cue_index: int, option: int)

const Dialogue := preload("res://scripts/events/cutscene_dialogue.gd")

var _service: RefCounted
var _acquire: Callable
var _unlock: Callable
var _resolve: Callable
var _face: Callable
var _base_camera: WeakRef
var _shot_camera: Camera2D
var _dialogue: Node
var _owned_dialogue: bool = false
var _curtain_layer: CanvasLayer
var _curtain: ColorRect
var _cues: Array[StoryCue] = []
var _id: StringName = &""
var _index: int = -1
var _elapsed: float = 0.0
var _from: Vector2
var _fade_from: float = 0.0
var _moving: WeakRef
var _actor_modes: Dictionary = {}
var _lock_owner: StringName
var _owns_lock: bool = false
var _starting: bool = false
var _released: bool = false
var _previous_focus: WeakRef
var _run_id: int = 0
var _cleaning: bool = false


func configure(service: RefCounted, acquire: Callable, unlock: Callable, resolve_actor: Callable, face_actor: Callable = Callable(), camera: Camera2D = null, dialogue: Node = null) -> void:
	if is_playing() or _released: return
	_unbind_dialogue()
	if _owned_dialogue and is_instance_valid(_dialogue):
		_dialogue.close()
		_dialogue.queue_free()
	_service = service
	_acquire = acquire
	_unlock = unlock
	_resolve = resolve_actor
	_face = face_actor
	_base_camera = weakref(camera) if is_instance_valid(camera) else null
	_dialogue = dialogue
	_owned_dialogue = false
	_lock_owner = StringName("story_cutscene_%d" % get_instance_id())
	_bind_dialogue()


func play(id: StringName) -> bool:
	if _released or _cleaning or not is_inside_tree() or is_playing() or _service == null: return false
	var event: StoryEvent = _service.definition(id)
	if event == null or not _preflight(event) or not _acquire.is_valid() or not _unlock.is_valid(): return false
	_starting = true
	_run_id += 1
	var ticket: int = _run_id
	var release_lock: Callable = _unlock
	if not bool(_acquire.call(_lock_owner)):
		_starting = false
		return false
	if _run_id != ticket or _released or not is_inside_tree():
		release_lock.call(_lock_owner)
		return false
	_owns_lock = true
	_id = id
	_cues = event.cues
	var focus: Control = get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus != null else null
	_ensure_visuals()
	if not _service.trigger(id):
		_starting = false
		_cleanup()
		return false
	_starting = false
	# 同步用例通知期间允许取消/离树；不得在恢复后继续旧播放。
	if _released or not is_inside_tree() or _run_id != ticket: return true
	if not _take_camera():
		_finish(&"cancelled")
		return true
	playback_started.emit(id)
	if is_playing() and _run_id == ticket: _advance()
	return true


func is_playing() -> bool:
	return _starting or _id != &""


func current_status() -> Dictionary:
	return {"playing": is_playing(), "event": String(_id), "cue": _index, "kind": _cues[_index].kind if _index >= 0 and _index < _cues.size() else ""}


func advance_line() -> void:
	if not _starting and _current_kind() == "line": _advance()


func choose(index: int) -> bool:
	if _starting or _current_kind() != "choice" or index < 0 or index >= _cues[_index].options.size(): return false
	var event_id: StringName = _id
	var cue_index: int = _index
	var ticket: int = _run_id
	choice_selected.emit(event_id, cue_index, index)
	if _run_id == ticket and _id == event_id and _index == cue_index: _advance()
	return true


func skip() -> bool:
	if _starting or not is_playing(): return false
	var ticket: int = _run_id
	var remaining: Array[StoryCue] = _cues.duplicate()
	# 跳过仍落实剩余走位和朝向；镜头与黑幕在结束时恢复。
	for index: int in range(maxi(0, _index), remaining.size()):
		var cue: StoryCue = remaining[index]
		if cue.kind == "move":
			var actor: Node2D = _actor(cue.actor)
			if is_instance_valid(actor): actor.global_position = cue.target
		elif cue.kind == "face" and _face.is_valid():
			_face.call(cue.actor, StringName(cue.facing))
		if _run_id != ticket: return true
	_finish(&"skipped")
	return true


func cancel() -> bool:
	if not is_playing(): return false
	_finish(&"cancelled")
	return true


## 载入任何快照前先 cancel，再恢复基础模型和事件分区；不恢复播放游标。
func release() -> void:
	_released = true
	_cleanup()
	_unbind_dialogue()
	_service = null
	_acquire = Callable()
	_unlock = Callable()
	_resolve = Callable()
	_face = Callable()
	_base_camera = null
	if is_instance_valid(_curtain_layer):
		_curtain_layer.queue_free()
	_curtain_layer = null
	_curtain = null
	if _owned_dialogue and is_instance_valid(_dialogue): _dialogue.queue_free()
	_dialogue = null


func _exit_tree() -> void:
	release()


func _input(event: InputEvent) -> void:
	if is_playing() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		skip()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _starting or not is_playing() or _index < 0 or _index >= _cues.size(): return
	var cue: StoryCue = _cues[_index]
	if cue.kind in ["line", "choice"]: return
	_elapsed += delta
	var ratio: float = 1.0 if cue.duration <= 0.0 else minf(1.0, _elapsed / cue.duration)
	match cue.kind:
		"move":
			var actor: Node2D = _moving.get_ref() as Node2D if _moving != null else null
			if not is_instance_valid(actor) or not actor.is_inside_tree():
				cancel()
				return
			actor.global_position = _from.lerp(cue.target, ratio)
		"camera":
			if is_instance_valid(_shot_camera): _shot_camera.global_position = _from.lerp(cue.target, ratio)
		"fade_out", "fade_in":
			_curtain.color.a = lerpf(_fade_from, 1.0 if cue.kind == "fade_out" else 0.0, ratio)
	if ratio >= 1.0: _advance()


func _advance() -> void:
	if not is_playing(): return
	_dialogue.close()
	_moving = null
	_index += 1
	_elapsed = 0.0
	if _index >= _cues.size():
		_finish(&"watched")
		return
	var cue: StoryCue = _cues[_index]
	match cue.kind:
		"line": _dialogue.show_line(cue.speaker, cue.text)
		"choice": _dialogue.show_choices(cue.text, cue.options, cue.default_option)
		"move":
			var actor: Node2D = _actor(cue.actor)
			if not is_instance_valid(actor):
				cancel()
				return
			_hold_actor(actor)
			_moving = weakref(actor)
			_from = actor.global_position
		"face":
			var actor: Node2D = _actor(cue.actor)
			if not is_instance_valid(actor) or not _face.is_valid():
				cancel()
				return
			_hold_actor(actor)
			_face.call(cue.actor, StringName(cue.facing))
		"camera":
			if not is_instance_valid(_shot_camera):
				cancel()
				return
			_from = _shot_camera.global_position
		"fade_out", "fade_in": _fade_from = _curtain.color.a


func _preflight(event: StoryEvent) -> bool:
	if is_instance_valid(_dialogue) and (not _dialogue_contract() or not _dialogue.is_inside_tree()): return false
	for cue: StoryCue in event.cues:
		if cue.kind in ["move", "face"] and not is_instance_valid(_actor(cue.actor)): return false
		if cue.kind == "face" and not _face.is_valid(): return false
		if cue.kind == "camera" and (_base_camera == null or not is_instance_valid(_base_camera.get_ref())): return false
	if _base_camera != null:
		var camera: Camera2D = _base_camera.get_ref() as Camera2D
		if not is_instance_valid(camera) or camera.get_viewport() != get_viewport() or get_viewport().get_camera_2d() != camera: return false
	return true


func _actor(id: StringName) -> Node2D:
	if not _resolve.is_valid(): return null
	var value: Variant = _resolve.call(id)
	if not is_instance_valid(value) or not value is Node2D or not value.is_inside_tree(): return null
	return value as Node2D


func _hold_actor(actor: Node2D) -> void:
	var instance: int = actor.get_instance_id()
	if not _actor_modes.has(instance):
		_actor_modes[instance] = {"ref": weakref(actor), "mode": actor.process_mode}
	actor.process_mode = Node.PROCESS_MODE_DISABLED


func _take_camera() -> bool:
	if _base_camera == null: return true
	var camera: Camera2D = _base_camera.get_ref() as Camera2D
	if not is_instance_valid(camera) or not camera.is_inside_tree() or camera.get_viewport() != get_viewport() or get_viewport().get_camera_2d() != camera: return false
	_shot_camera = Camera2D.new()
	_shot_camera.zoom = camera.zoom
	_shot_camera.offset = camera.offset
	_shot_camera.rotation = camera.global_rotation
	_shot_camera.ignore_rotation = camera.ignore_rotation
	_shot_camera.limit_left = camera.limit_left
	_shot_camera.limit_top = camera.limit_top
	_shot_camera.limit_right = camera.limit_right
	_shot_camera.limit_bottom = camera.limit_bottom
	add_child(_shot_camera)
	_shot_camera.global_position = camera.get_screen_center_position()
	_shot_camera.global_rotation = camera.global_rotation
	_shot_camera.make_current()
	return true


func _finish(reason: StringName) -> void:
	var id: StringName = _id
	_cleanup()
	playback_finished.emit(id, reason)


func _cleanup() -> void:
	if _cleaning: return
	_cleaning = true
	_run_id += 1
	_id = &""
	_index = -1
	_cues.clear()
	_moving = null
	_starting = false
	if is_instance_valid(_dialogue): _dialogue.close()
	if _previous_focus != null:
		var focus: Control = _previous_focus.get_ref() as Control
		if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	_previous_focus = null
	if is_instance_valid(_curtain): _curtain.color.a = 0.0
	for entry: Dictionary in _actor_modes.values():
		var actor: Node = entry.ref.get_ref()
		if is_instance_valid(actor): actor.process_mode = entry.mode
	_actor_modes.clear()
	if is_instance_valid(_shot_camera):
		var owned_current: bool = is_inside_tree() and get_viewport().get_camera_2d() == _shot_camera
		_shot_camera.enabled = false
		_shot_camera.queue_free()
		_shot_camera = null
		if owned_current and _base_camera != null:
			var camera: Camera2D = _base_camera.get_ref() as Camera2D
			if is_instance_valid(camera) and camera.is_inside_tree(): camera.make_current()
	if _owns_lock:
		_owns_lock = false
		if _unlock.is_valid(): _unlock.call(_lock_owner)
	_cleaning = false


func _current_kind() -> String:
	return _cues[_index].kind if _index >= 0 and _index < _cues.size() else ""


func _ensure_visuals() -> void:
	if not is_instance_valid(_curtain_layer):
		_curtain_layer = CanvasLayer.new()
		_curtain_layer.layer = 129
		add_child(_curtain_layer)
		_curtain = ColorRect.new()
		_curtain.color = Color(0, 0, 0, 0)
		_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_curtain_layer.add_child(_curtain)
		_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not is_instance_valid(_dialogue):
		_dialogue = Dialogue.new()
		_owned_dialogue = true
		add_child(_dialogue)
		_bind_dialogue()


func _bind_dialogue() -> void:
	if not _dialogue_contract(): return
	_dialogue.advanced.connect(advance_line)
	_dialogue.selected.connect(choose)
	_dialogue.skip_requested.connect(skip)
	_dialogue.tree_exiting.connect(_on_dialogue_exiting)


func _unbind_dialogue() -> void:
	if not is_instance_valid(_dialogue): return
	for binding: Array in [[&"advanced", advance_line], [&"selected", choose], [&"skip_requested", skip], [&"tree_exiting", _on_dialogue_exiting]]:
		if _dialogue.is_connected(binding[0], binding[1]): _dialogue.disconnect(binding[0], binding[1])


func _on_dialogue_exiting() -> void:
	cancel()


func _dialogue_contract() -> bool:
	if not is_instance_valid(_dialogue): return false
	for method: StringName in [&"show_line", &"show_choices", &"close"]:
		if not _dialogue.has_method(method): return false
	for event: StringName in [&"advanced", &"selected", &"skip_requested"]:
		if not _dialogue.has_signal(event): return false
	return true
