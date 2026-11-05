extends Node2D
## 房门：屋外按 F 进屋，屋内按 F 出门。
##
## 过渡按常见农场游戏的做法：一声开门 → 画面渐黑 → 换世界 → 渐亮。
## 过渡期间锁玩家输入，避免"黑屏里还能走动"。

const INTERACT_RADIUS: float = 24.0
## 渐黑 / 渐亮时长
const FADE_OUT: float = 0.22
const FADE_IN: float = 0.30
## 全黑后停留一小会儿，让换世界的那一帧不闪
const HOLD: float = 0.06

@export_enum("enter", "exit") var mode: String = "enter"
## 只有 mode = enter 时用到
@export var interior: PackedScene

var _busy: bool = false


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	if _busy:
		return false
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "按 F 出门" if mode == "exit" else "按 F 进屋"


func interact(_cell: Vector2i) -> void:
	if _busy:
		return
	var house := get_tree().get_first_node_in_group(&"house")
	if house == null:
		return
	_busy = true

	var player := get_tree().get_first_node_in_group(&"player")
	_set_player_locked(player, true)
	_play_door_sfx()

	var fade := get_tree().get_first_node_in_group(&"screen_fade")
	if fade != null:
		await fade.call(&"fade_out", FADE_OUT)

	if mode == "exit":
		house.call(&"exit_house")
	else:
		house.call(&"enter_house", interior)

	await get_tree().create_timer(HOLD).timeout
	if fade != null:
		await fade.call(&"fade_in", FADE_IN)

	_set_player_locked(player, false)
	_busy = false


func _set_player_locked(player: Node, locked: bool) -> void:
	if player != null and player.has_method(&"set_input_locked"):
		player.call(&"set_input_locked", locked)


func _play_door_sfx() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method(&"play_sfx"):
		audio.call(&"play_sfx", &"door", randf_range(0.95, 1.05))
