extends Node
## 引擎适配：编排过场/床位/输入锁，日期、罚金和保存交给RestService。

signal started
signal completed(result: Dictionary)
signal save_failed

var service: RefCounted
var _player: Node2D
var _house: Node
var _fade: Node
var _recover_home: Callable
var _sleep_sound: Callable
var _run_id: int = 0
var _owns_lock: bool = false


func configure(use_case: RefCounted, player: Node2D, house: Node, fade: Node, recover_home: Callable, sleep_sound: Callable) -> void:
	service = use_case
	_player = player
	_house = house
	_fade = fade
	_recover_home = recover_home
	_sleep_sound = sleep_sound


func request_sleep() -> void:
	_run(false)


func pass_out() -> void:
	_run(true)


func _run(pass_out: bool) -> void:
	if service == null or not service.begin(pass_out): return
	_run_id += 1
	var ticket: int = _run_id
	var indoors: bool = _house.is_inside()
	var night: bool = service.is_evening()
	started.emit()
	_player.set_input_locked(true)
	_owns_lock = true
	if not pass_out and _sleep_sound.is_valid(): _sleep_sound.call()
	await _fade.fade_out(0.6 if pass_out else 0.45)
	if not _active(ticket): return
	if pass_out and not indoors and _recover_home.is_valid(): _recover_home.call()
	if indoors: _house.begin_sleep()
	_fade.show_caption("凌晨两点，你累倒了……" if pass_out else ("晚安 · 第 %d 天" % service.day() if night else "小睡一会儿"))
	var result: Dictionary = service.settle()
	if not pass_out:
		_fade.show_caption("第 %d 天 · 早上好" % service.day() if result.advanced else "醒来 · 第 %d 天 %s" % [service.day(), service.clock_text()])
	await get_tree().create_timer(1.0 if pass_out else 0.9).timeout
	if not _active(ticket): return
	_house.prepare_wake()
	if not service.persist(): save_failed.emit()
	_fade.hide_caption()
	if pass_out and int(result.lost) > 0:
		_fade.show_caption("第 %d 天 · 早上好（被罚走 %d 金币）" % [service.day(), int(result.lost)])
	await _fade.fade_in(0.5)
	if not _active(ticket): return
	if pass_out and int(result.lost) > 0:
		await get_tree().create_timer(1.4).timeout
		if not _active(ticket): return
	_fade.hide_caption()
	_player.set_input_locked(false)
	_owns_lock = false
	result = service.result()
	service.finish()
	completed.emit(result)


func _active(ticket: int) -> bool:
	return is_inside_tree() and ticket == _run_id


func _exit_tree() -> void:
	_run_id += 1
	if _owns_lock and is_instance_valid(_player): _player.set_input_locked(false)
	if _owns_lock and is_instance_valid(_fade):
		_fade.hide_caption()
		_fade.fade_in(0.0)
	_owns_lock = false
	if service != null: service.clear()
	_recover_home = Callable()
	_sleep_sound = Callable()
