extends RefCounted
## 休息用例：只接模型和保存端口，不查场景树、不操作界面或过场。

var busy: bool = false
var _clock: Node
var _wallet: Economy
var _stamina: Node
var _save: Callable
var _pass_out: bool = false
var _settled: bool = false
var _save_attempted: bool = false
var _result: Dictionary = {}


func configure(clock: Node, wallet: Economy, stamina: Node, save: Callable) -> void:
	_clock = clock
	_wallet = wallet
	_stamina = stamina
	_save = save


func begin(pass_out: bool = false) -> bool:
	if busy or not is_instance_valid(_clock): return false
	busy = true
	_pass_out = pass_out
	_settled = false
	_save_attempted = false
	_result = {"advanced": false, "lost": 0, "saved": false, "night": pass_out or _clock.is_evening()}
	return true


func settle() -> Dictionary:
	if not busy: return {}
	if _settled: return _result.duplicate()
	# 先封闭重入，再触发模型信号；重复提交不重复扣款或推进日期。
	_settled = true
	if _pass_out:
		_result.lost = _wallet.pass_out_fine()
		_clock.sleep()
		_stamina.wake_weary()
		_result.advanced = true
	else:
		_result.advanced = _clock.rest()
	return _result.duplicate()


## 由控制器在玩家最终落点准备好之后调用，失败不会冒充保存成功。
func persist() -> bool:
	if not busy or not _settled: return false
	if not bool(_result.advanced): return true
	if not _save_attempted:
		_save_attempted = true
		_result.saved = _save.is_valid() and bool(_save.call())
	return bool(_result.saved)


func result() -> Dictionary:
	return _result.duplicate()


func day() -> int:
	return int(_clock.day)


func clock_text() -> String:
	return _clock.clock_text()


func is_evening() -> bool:
	return _clock.is_evening()


func finish() -> void:
	busy = false


func clear() -> void:
	finish()
	_clock = null
	_wallet = null
	_stamina = null
	_save = Callable()
