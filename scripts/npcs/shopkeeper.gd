extends Sprite2D
## 杂货铺老板：玩家靠近按 E 对话，对话里选「看看今天的货」才打开商店。
##
## 加入 interactable 组，和睡觉点共用玩家的「最近可交互对象」逻辑；
## 脚底有一块小碰撞体，玩家不能从他身上穿过去。
## 老板固定朝下站着（第 0 帧），不根据玩家位置转向。

## 店主站在柜台后面，柜台有一格厚，半径放宽到 34 才够得着
const INTERACT_RADIUS: float = 34.0
const IDLE_LINE: String = "想买点什么？今天的种子刚到货。"
const CHAT_LINE: String = "还行，托你的福。多浇点水，收成不会差。"
const SPEAKER: String = "杂货铺老板"
## 营业时间：09:00–17:00；打烊后只聊天不卖货。
const OPEN_MINUTES: int = 9 * 60
const CLOSE_MINUTES: int = 17 * 60
const CLOSED_LINE: String = "今天打烊了，明天 9 点再来吧。"


func _ready() -> void:
	add_to_group(&"interactable")
	frame = 0


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	if not is_open():
		return "杂货铺打烊了（09:00–17:00）"
	return "按 E 和杂货铺老板聊聊"


## 营业中？没有时间系统时按营业处理，避免读档异常时商店彻底打不开。
func is_open() -> bool:
	var time := get_tree().get_first_node_in_group(&"time")
	if time == null:
		return true
	var minutes: int = int(time.get("minutes"))
	return minutes >= OPEN_MINUTES and minutes < CLOSE_MINUTES


func interact(_cell: Vector2i) -> void:
	var panel := get_tree().current_scene.get_node_or_null("UI/DialoguePanel")
	if panel == null or not panel.has_method(&"open_with"):
		return
	if not is_open():
		panel.open_with(SPEAKER, CLOSED_LINE, [
			{&"id": &"leave", &"text": "知道了"},
		], self)
		return
	panel.open_with(SPEAKER, IDLE_LINE, [
		{&"id": &"shop", &"text": "看看今天的货"},
		{&"id": &"chat", &"text": "最近生意怎么样？"},
		{&"id": &"leave", &"text": "先不买了"},
	], self)


## 对话面板回调：返回非空字符串表示"换一句台词继续聊"，返回空串表示结束对话。
func on_dialogue_option(id: StringName) -> String:
	match id:
		&"shop":
			if not is_open():
				return CLOSED_LINE
			_open_shop()
			return ""
		&"chat":
			return CHAT_LINE
		_:
			return ""


## 关掉对话、收起工具栏，再打开商店面板。
func _open_shop() -> void:
	var scene := get_tree().current_scene
	var dialogue := scene.get_node_or_null("UI/DialoguePanel")
	if dialogue != null and dialogue.has_method(&"close"):
		dialogue.close()
	var shop := scene.get_node_or_null("UI/ShopPanel")
	if shop != null and shop.has_method(&"set_open"):
		shop.set_open(true)
