extends Node
## 只整理农业显示信息；购买资格仍由交易服务校验。

const Rules := preload("res://scripts/world/farming/crop_season_rules.gd")
var _view: Control
var _clock: Node
var _save: Node
var _definitions: Dictionary = {}


func configure(view: Control, definitions: Array[CropData], clock: Node, save: Node = null) -> void:
	_unbind()
	_view = view
	_clock = clock
	_save = save
	for data: CropData in definitions: _definitions[data.seed_item] = data
	view.seed_information = describe
	clock.day_started.connect(_refresh)
	if save != null: save.restored.connect(_refresh)


func describe(seed: StringName) -> String:
	var data: CropData = _definitions.get(seed)
	if data == null: return ""
	var info: Dictionary = Rules.information(data, int(_clock.day))
	var production: String = "复收%d晚" % info.regrow_nights if info.regrow_nights > 0 else "单次收获"
	var status: String = "今种可首收" if info.fits_first_harvest else "季末来不及首收 · 可留种"
	if not info.in_season: status = "当前季节不可播种"
	return "%s · 首收%d晚\n%s · 余季%d天\n%s" % [data.seasons_text(), info.grow_nights, production, info.days_left, status]


func _refresh(_day: int = 0) -> void:
	if is_instance_valid(_view): _view.refresh_offers()


func _exit_tree() -> void:
	_unbind()


func _unbind() -> void:
	if is_instance_valid(_clock) and _clock.day_started.is_connected(_refresh):
		_clock.day_started.disconnect(_refresh)
	if is_instance_valid(_save) and _save.restored.is_connected(_refresh):
		_save.restored.disconnect(_refresh)
	if is_instance_valid(_view) and _view.seed_information == Callable(self, "describe"):
		_view.seed_information = Callable()
	_view = null
	_clock = null
	_save = null
	_definitions.clear()
