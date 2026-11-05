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
## 每个品种按幼苗、采后、结果排列；沿用地图灌木的柔和鼠尾草绿。
const ART: Dictionary = {
	&"wild_blackberry": [preload("res://assets/packs/farm_style_v2/berries/blackberry/sprout.png"), preload("res://assets/packs/farm_style_v2/berries/blackberry/bare.png"), preload("res://assets/packs/farm_style_v2/berries/blackberry/ripe.png")],
	&"wild_raspberry": [preload("res://assets/packs/farm_style_v2/berries/raspberry/sprout.png"), preload("res://assets/packs/farm_style_v2/berries/raspberry/bare.png"), preload("res://assets/packs/farm_style_v2/berries/raspberry/ripe.png")],
	&"wild_gooseberry": [preload("res://assets/packs/farm_style_v2/berries/gooseberry/sprout.png"), preload("res://assets/packs/farm_style_v2/berries/gooseberry/bare.png"), preload("res://assets/packs/farm_style_v2/berries/gooseberry/ripe.png")],
}

var kind: StringName = &"wild_blackberry"
## 兼容管理器的旧种植接口；实际显示颜色由 ART 中的贴图决定。
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		var text := "[F] 采%s ×%d · 体力 %d" % [_display_name, YIELD, STAMINA_COST]
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
# 显示使用原创像素贴图，沿用现有日期状态与 queue_redraw 刷新路径。
# --------------------------------------------------------------------------

func visual_texture() -> Texture2D:
	var frames: Array = ART.get(kind, ART[&"wild_blackberry"])
	return frames[0 if not is_mature() else 2 if has_berries() else 1] as Texture2D


func _draw() -> void:
	draw_texture(visual_texture(), Vector2(-16, -32))
