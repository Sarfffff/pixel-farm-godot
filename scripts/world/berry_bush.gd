extends Node2D
## 野浆果丛：结果时按 E 采一把，采完要等两天才重新结果。
##
## 视觉用 `_draw` 直接画，不依赖贴图：有果时灌木上缀几颗彩色果子，
## 采完只剩绿叶，玩家一眼能看出还能不能采。

const YIELD: int = 2
const STAMINA_COST: int = 1
## 采完隔两天重新结果（第 N 天采，第 N+2 天恢复）。
const REGROW_DAYS: int = 2

## 产物物品 id，由管理器按落点分配。
var kind: StringName = &"wild_blackberry"
## 果子颜色，与产物对应。
var berry_color: Color = Color("3b2a45")
var slot: int = 0
var manager: Node
## 0 = 有果；>0 = 到这一天（含）之后重新结果。
var regrow_day: int = 0

var _display_name: String = "野果"


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"berry_bush")
	_display_name = _lookup_name()
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(_on_day_started)


func has_berries() -> bool:
	return regrow_day == 0


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= 20.0


func hint() -> String:
	if has_berries():
		return "[E] 采%s ×%d · 体力 %d" % [_display_name, YIELD, STAMINA_COST]
	return "%s 还没长好 · 再过 %d 天" % [_display_name, days_until_ripe()]


func interact(_cell: Vector2i) -> void:
	if not has_berries():
		_message("%s 还没长好，过两天再来" % _display_name)
		return
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null:
		return
	if not inventory.has_space_for(kind, YIELD):
		_message("背包已满 · 腾出空间再来采")
		return
	var stamina := get_tree().get_first_node_in_group(&"stamina")
	if stamina != null and not stamina.spend(STAMINA_COST):
		_message("体力不够 · 回屋睡一觉")
		return
	inventory.add_item(kind, YIELD)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method(&"play_sfx"):
		audio.call(&"play_sfx", &"harvest", randf_range(0.98, 1.06))
	_message("采到 %s ×%d" % [_display_name, YIELD])
	_harvest()
	if manager != null and manager.has_method(&"on_bush_changed"):
		manager.call(&"on_bush_changed")


## 采完进入"没果"状态，记下重新结果的日子。
func _harvest() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	var day: int = int(time.day) if time != null else 1
	regrow_day = day + REGROW_DAYS
	queue_redraw()


func days_until_ripe() -> int:
	if regrow_day <= 0:
		return 0
	var time := get_tree().get_first_node_in_group(&"time")
	var day: int = int(time.day) if time != null else 1
	return maxi(regrow_day - day, 1)


func _on_day_started(day: int) -> void:
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
	return {&"slot": slot, &"kind": String(kind), &"regrow": regrow_day}


func from_dict(data: Dictionary) -> void:
	regrow_day = maxi(0, int(data.get(&"regrow", 0)))
	queue_redraw()


# --------------------------------------------------------------------------
# 画一丛灌木：三团绿叶 + 落地阴影，结果时缀上浆果
# --------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(-8, -1, 16, 3), Color(0.16, 0.2, 0.1, 0.28))
	var dark := Color("3f6b35")
	var mid := Color("4f8440")
	var light := Color("69a24f")
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
