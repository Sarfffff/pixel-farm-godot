extends Node2D
## 遮挡淡出：角色走到树木、建筑背后（被前方道具挡住）时，把遮挡物调成半透明。
##
## 判断条件（两者同时满足才淡出）：
## 1. 道具脚底 y 大于角色脚底 y —— 道具被排在角色前面，可能盖住角色；
## 2. 角色的**脚底点**落在道具的遮挡框内（左右各内缩 EDGE_INSET 像素）。
##
## 为什么用脚底点而不是包围盒相交：包围盒相交会把"站在房子侧面、身体轻微蹭到墙"
## 也判成被遮挡；而脚底点 + 水平内缩只在角色确实站进道具脚下/身后时才命中。
##
## 挂在 World（y 排序容器）上，自动收集其下的 Sprite2D 子节点作为候选遮挡物。
## 玩家节点固定名为 Player，脚底点即其 global_position。

const FADE_ALPHA: float = 0.55
const FADE_DURATION: float = 0.12
const PLAYER_NAME := "Player"
## 遮挡框左右内缩量：避免站在道具边缘蹭到一点就淡出
const EDGE_INSET: float = 4.0

var _player: Node2D
## 候选遮挡物及其全局包围盒（道具不会移动，初始化时缓存一次）
var _occluder_bounds: Dictionary = {}
var _target_alpha: Dictionary = {}
var _tweens: Dictionary = {}


func _ready() -> void:
	_player = get_node_or_null(PLAYER_NAME) as Node2D
	if _player == null:
		push_warning("[occlusion_fader] 未找到 Player 节点，遮挡淡出已停用")
		return

	for child in get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite == _player:
			continue
		_occluder_bounds[sprite] = _global_bounds(sprite)
		_target_alpha[sprite] = 1.0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return

	var feet: Vector2 = _player.global_position

	for sprite: Sprite2D in _occluder_bounds.keys():
		if sprite.get_meta(&"felled", false):
			_apply_alpha(sprite, 1.0)
			continue
		var occluding: bool = sprite.global_position.y > feet.y
		var covered: bool = _occlusion_rect(sprite).has_point(feet)
		_apply_alpha(sprite, FADE_ALPHA if (occluding and covered) else 1.0)


## 道具的遮挡框：贴图包围盒左右内缩 EDGE_INSET，上下各留 0.5px 容差。
func _occlusion_rect(sprite: Sprite2D) -> Rect2:
	var bounds: Rect2 = _occluder_bounds[sprite]
	return bounds.grow_individual(-EDGE_INSET, -0.5, -EDGE_INSET, -0.5)


## 只在目标值变化时启动补间，避免每帧重建 Tween。
func _apply_alpha(sprite: Sprite2D, wanted: float) -> void:
	if is_equal_approx(_target_alpha.get(sprite, 1.0), wanted):
		return
	_target_alpha[sprite] = wanted

	if _tweens.has(sprite):
		var previous := _tweens[sprite] as Tween
		if previous != null and previous.is_valid():
			previous.kill()

	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", wanted, FADE_DURATION)
	_tweens[sprite] = tween


## 道具贴图的全局包围盒（考虑 offset、region 与缩放）。
func _global_bounds(sprite: Sprite2D) -> Rect2:
	var local_rect := sprite.get_rect()
	var top_left := sprite.to_global(local_rect.position)
	var bottom_right := sprite.to_global(local_rect.end)
	return Rect2(top_left, bottom_right - top_left).abs()
