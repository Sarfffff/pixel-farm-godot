extends Node2D
## 野浆果丛 / 玩家种下的浆果灌木。
##
## 和耕地作物刻意分开：
##   - 长在草地上，不用锄地、不用浇水
##   - 种一次就留着，采完隔两天再结果（多年生灌木）
##   - 野外长的采完会掉一颗种子，玩家可以拿去自己种
##
## `wild` 只影响"采的时候掉不掉种子"，其余行为一样。

const YIELD: int = 2
const SEED_YIELD: int = 1
const STAMINA_COST: int = 1
## 采完隔两天重新结果。
const REGROW_DAYS: int = 2
## 种下到第一次结果。
const GROW_DAYS: int = 2

var kind: StringName = &"wild_blackberry"
var berry_color: Color = Color("3b2a45")
## 管理器里的编号；野外随机生成的用 -1，由位置识别。
var slot: int = -1
var manager: Node
## 0 = 幼苗（不能采），1 = 成株
var stage: int = 1
## true = 野外长的（采完掉种子）
var wild: bool = true
## 0 = 有果；>0 = 到这一天之后重新结果
var regrow_day: int = 0
## 幼苗成熟的日期；成株为 0
var grow_day: int = 0

var _display_name: String = "野果"


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"berry_bush")
	_display_name = _lookup_name()
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(_on_day_started)


func is_mature() -> bool:
	return stage >= 1


func has_berries() -> bool:
	return stage >= 1 and regrow_day == 0


func seed_id() -> StringName:
	return StringName("%s_seeds" % String(kind))


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= 20.0


func hint() -> String:
	if not is_mature():
		return "%s幼苗 · 再过 %d 天结果" % [_display_name, days_until_mature()]
	if has_berries():
		var text := "[E] 采%s ×%d · 体力 %d" % [_display_name, YIELD, STAMINA_COST]
		if wild:
			text += " · 顺带收种子"
		return text
	return "%s 还没长好 · 再过 %d 天" % [_display_name, days_until_ripe()]


func interact(_cell: Vector2i) -> void:
	if not is_mature():
		_message("%s 还是幼苗，过两天再来" % _display_name)
		return
	if not has_berries():
		_message("%s 还没长好，过两天再来" % _display_name)
		return
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null:
		return
	var seed: StringName = seed_id()
	var seeds: int = SEED_YIELD if wild else 0
	if not inventory.has_space_for(kind, YIELD) or (seeds > 0 and not inventory.has_space_for(seed, seeds)):
		_message("背包已满 · 腾出空间再来采")
		return
	var stamina := get_tree().get_first_node_in_group(&"stamina")
	if stamina != null and not stamina.spend(STAMINA_COST):
		_message("体力不够 · 回屋睡一觉")
		return
	inventory.add_item(kind, YIELD)
	if seeds > 0:
		inventory.add_item(seed, seeds)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method(&"play_sfx"):
		audio.call(&"play_sfx", &"harvest", randf_range(0.98, 1.06))
	if seeds > 0:
		_message("采到 %s ×%d，还收到 %d 颗种子" % [_display_name, YIELD, seeds])
	else:
		_message("采到 %s ×%d" % [_display_name, YIELD])
	_harvest()
	if manager != null and manager.has_method(&"on_bush_changed"):
		manager.call(&"on_bush_changed")


## 玩家用种子种下：进入幼苗期，过 GROW_DAYS 天结果。
func plant(kind_id: StringName, color: Color) -> void:
	kind = kind_id
	berry_color = color
	wild = false
	stage = 0
	regrow_day = 0
	_display_name = _lookup_name()
	var time := get_tree().get_first_node_in_group(&"time")
	var day: int = int(time.day) if time != null else 1
	grow_day = day + GROW_DAYS
	queue_redraw()


func _harvest() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	var day: int = int(time.day) if time != null else 1
	regrow_day = day + REGROW_DAYS
	queue_redraw()


func days_until_ripe() -> int:
	if regrow_day <= 0:
		return 0
	var day: int = _today()
	return maxi(regrow_day - day, 1)


func days_until_mature() -> int:
	if grow_day <= 0:
		return 0
	return maxi(grow_day - _today(), 1)


func _today() -> int:
	var time := get_tree().get_first_node_in_group(&"time")
	return int(time.day) if time != null else 1


func _on_day_started(day: int) -> void:
	if stage < 1 and grow_day > 0 and day >= grow_day:
		stage = 1
		grow_day = 0
		queue_redraw()
	if regrow_day > 0 and day >= regrow_day:
		regrow_day = 0
		queue_redraw()


func _lookup_name() -> String:
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null:
		return "野果"
	for item: ItemData in inventory.definitions():
		if item.id == kind:
			return item.display_name
	return "野果"


func _message(text: String) -> void:
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.show_message(text)


func to_dict() -> Dictionary:
	return {
		&"x": global_position.x,
		&"y": global_position.y,
		&"kind": String(kind),
		&"stage": stage,
		&"wild": wild,
		&"regrow": regrow_day,
		&"grow": grow_day,
	}


func from_dict(data: Dictionary) -> void:
	regrow_day = maxi(0, int(data.get(&"regrow", 0)))
	grow_day = maxi(0, int(data.get(&"grow", 0)))
	stage = clampi(int(data.get(&"stage", 1)), 0, 1)
	wild = bool(data.get(&"wild", true))
	queue_redraw()


# --------------------------------------------------------------------------
# 画法：幼苗只画一小团叶，成株画三团深浅叶 + 结果时缀浆果
# --------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(-8, -1, 16, 3), Color(0.16, 0.2, 0.1, 0.28))
	var dark := Color("3f6b35")
	var mid := Color("4f8440")
	var light := Color("69a24f")
	if not is_mature():
		# 幼苗：两片小叶子，一看就知道还没长成
		draw_circle(Vector2(-1, -3), 2.6, dark)
		draw_circle(Vector2(2, -4), 2.2, mid)
		draw_circle(Vector2(0, -6), 1.6, light)
		return
	draw_circle(Vector2(-4, -6), 5.0, dark)
	draw_circle(Vector2(4, -6), 5.0, dark)
	draw_circle(Vector2(0, -10), 6.0, dark)
	draw_circle(Vector2(-4, -7), 4.0, mid)
	draw_circle(Vector2(4, -7), 4.0, mid)
	draw_circle(Vector2(0, -11), 5.0, mid)
	draw_circle(Vector2(-2, -13), 2.4, light)
	if not has_berries():
		return
	var spots := [
		Vector2(-6, -6), Vector2(-2, -9), Vector2(3, -5), Vector2(6, -8), Vector2(1, -13), Vector2(-5, -11),
	]
	for point: Vector2 in spots:
		draw_circle(point, 1.8, berry_color)
		draw_circle(point + Vector2(-0.5, -0.6), 0.7, berry_color.lightened(0.5))
