extends Sprite2D
## 杂货铺老板：玩家靠近按 E 对话，对话里选「看看今天的货」才打开商店。
##
## 加入 interactable 组，和睡觉点共用玩家的「最近可交互对象」逻辑；
## 脚底有一块小碰撞体，玩家不能从他身上穿过去。
## 老板固定朝下站着（第 0 帧），不根据玩家位置转向。

const INTERACT_RADIUS: float = 26.0
const IDLE_LINE: String = "想买点什么？今天的种子刚到货。"
const CHAT_LINE: String = "还行，托你的福。多浇点水，收成不会差。"


func _ready() -> void:
	add_to_group(&"interactable")
	frame = 0


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "按 E 和杂货铺老板聊聊"


func interact(_cell: Vector2i) -> void:
	var panel := get_tree().current_scene.get_node_or_null("UI/DialoguePanel")
	if panel == null or not panel.has_method(&"open_with"):
		return
	panel.open_with("杂货铺老板", IDLE_LINE, [
		{&"id": &"shop", &"text": "看看今天的货"},
		{&"id": &"chat", &"text": "最近生意怎么样？"},
		{&"id": &"leave", &"text": "先不买了"},
	], self)


## 对话面板回调：返回非空字符串表示"换一句台词继续聊"，返回空串表示结束对话。
func on_dialogue_option(id: StringName) -> String:
	match id:
		&"shop":
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
