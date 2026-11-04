extends RefCounted
## 单次钓鱼的状态与时间。无场景、输入、库存或音画依赖，可独立复用与验证。

var state: StringName = &"idle"
var casts_today: int = 0
var pending_fish: StringName = &""
var bite_elapsed: float = 0.0
var _candidate: StringName = &""
var _elapsed: float = 0.0
var _wait: float = 0.0


func start(candidate: StringName, wait_seconds: float) -> bool:
	if state in [&"waiting", &"bite"] or pending_fish != &"" or candidate == &"":
		return false
	casts_today += 1
	_candidate = candidate
	_elapsed = 0.0
	bite_elapsed = 0.0
	_wait = maxf(wait_seconds, 0.01)
	state = &"waiting"
	return true


## 返回 true 表示错过咬钩窗口。
func tick(delta: float, bite_window: float) -> bool:
	if state == &"waiting":
		_elapsed += maxf(delta, 0.0)
		if _elapsed >= _wait:
			state = &"bite"
			bite_elapsed = 0.0
	elif state == &"bite":
		bite_elapsed += maxf(delta, 0.0)
		if bite_elapsed > maxf(bite_window, 0.01):
			cancel()
			return true
	return false


func reel() -> bool:
	if state != &"bite":
		return false
	pending_fish = _candidate
	_candidate = &""
	state = &"ready"
	return true


func claim() -> StringName:
	var fish: StringName = pending_fish
	pending_fish = &""
	state = &"idle"
	return fish


func cancel() -> void:
	_candidate = &""
	state = &"ready" if pending_fish != &"" else &"idle"


func progress(bite_window: float) -> float:
	if state == &"waiting":
		return clampf(_elapsed / _wait, 0.0, 1.0)
	if state == &"bite":
		return 1.0 - clampf(bite_elapsed / maxf(bite_window, 0.01), 0.0, 1.0)
	return 0.0
