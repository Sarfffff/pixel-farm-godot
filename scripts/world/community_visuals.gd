extends Node
## 社区等级由同一份存档状态驱动，初始化/读档均刷新，不重复发奖励。

const FENCE: Texture2D = preload("res://assets/generated/content_v1/terrain/town/spring/wood_fence.png")
const TABLE: Texture2D = preload("res://assets/generated/content_v1/objects/furniture/kitchen_table.png")
const SIGN: Texture2D = preload("res://assets/generated/content_v1/objects/craftables/sign_board.png")
var world: Node2D
var fences: Array[Sprite2D] = []
var stalls: Array[Sprite2D] = []
var sign: Sprite2D
var applied_stage: int = -1


func _ready() -> void:
	for index: int in 4:
		var fence: Sprite2D = _sprite(FENCE, Vector2(536 + index * 16, 110), 0.5)
		fences.append(fence)
	for position: Vector2 in [Vector2(80, 368), Vector2(112, 368)]:
		var table: Sprite2D = _sprite(TABLE, position, 1.0)
		stalls.append(table)
		var goods: Sprite2D = Sprite2D.new()
		goods.texture = preload("res://assets/generated/content_v1/items/food_forage/bread.png")
		goods.position = Vector2(0, -15)
		table.add_child(goods)
	sign = _sprite(SIGN, Vector2(480, 82), 1.0)
	var community: Node = get_tree().get_first_node_in_group(&"community")
	if community != null:
		community.changed.connect(refresh)
	refresh()


func _sprite(texture: Texture2D, position: Vector2, factor: float) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = position
	sprite.offset = Vector2(0, -12)
	sprite.scale = Vector2.ONE * factor
	world.add_child(sprite)
	return sprite


func refresh() -> void:
	var community: Node = get_tree().get_first_node_in_group(&"community")
	applied_stage = int(community.stage) if community != null else 0
	for index: int in fences.size():
		fences[index].visible = applied_stage >= 1 or index == 0 or index == 3
	for stall: Sprite2D in stalls:
		stall.visible = applied_stage >= 2
	sign.visible = applied_stage >= 3
