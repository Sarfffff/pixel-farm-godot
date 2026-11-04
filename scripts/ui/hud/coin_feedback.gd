extends Node
## 收入音效属于表现层；钱包只发布事实，不查找音频服务。

var _play_sound: Callable


func configure(wallet: Economy, play_sound: Callable) -> void:
	_play_sound = play_sound
	wallet.coins_gained.connect(_on_income)


func _on_income(amount: int) -> void:
	var pitch: float = clampf(1.0 + float(mini(amount, 400)) / 1600.0, 1.0, 1.25)
	if _play_sound.is_valid():
		_play_sound.call(&"coin", pitch)
