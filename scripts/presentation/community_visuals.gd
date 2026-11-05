extends Node
## 社区等级由同一份存档状态驱动，初始化/读档均刷新，不重复发奖励。

const FENCE: Texture2D = preload("res://assets/packs/content_v1/terrain/town/spring/wood_fence.png")
const TABLE: Texture2D = preload("res://assets/packs/content_v1/objects/furniture/kitchen_table.png")
const SIGN: Texture2D = preload("res://assets/packs/content_v1/objects/craftables/sign_board.png")
var world: Node2D
var fences: Array[Sprite2D] = []
var stalls: Array[Sprite2D] = []
var sign: Sprite2D
var applied_stage: int = -1


func _ready() -> void:
	for index: int in 4:
		# 栅栏是实体：一截一格宽，脚底一小条碰撞，玩家得绕过去，不能直接穿过。
		var fence: Sprite2D = _sprite(FENCE, Vector2([536, 552, 584, 600][index], 110), 0.5, Vector2(16, 6))
		fences.append(fence)
	for position: Vector2 in [Vector2(80, 368), Vector2(112, 368)]:
		var table: Sprite2D = _sprite(TABLE, position, 1.0)
		stalls.append(table)
		var goods: Sprite2D = Sprite2D.new()
		goods.texture = preload("res://assets/packs/content_v1/items/food_forage/bread.png")
		goods.position = Vector2(0, -15)
		table.add_child(goods)
	# 招牌也是实体，玩家不能从牌子里穿过去
	sign = _sprite(SIGN, Vector2(616, 88), 1.0, Vector2(12, 6))
	var community: Node = get_tree().get_first_node_in_group(&"community")
	if community != null:
		community.changed.connect(refresh)
	refresh()


## footprint 非零时给贴图挂一条脚底碰撞（宽 × 高），用来挡住玩家。
func _sprite(texture: Texture2D, position: Vector2, factor: float, footprint := Vector2.ZERO) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = position
	sprite.offset = Vector2(0, -12)
	sprite.scale = Vector2.ONE * factor
	if footprint != Vector2.ZERO:
		sprite.add_child(_foot_body(footprint))
	world.add_child(sprite)
	return sprite


## 脚底碰撞体：与区域资源的 FootCollision 同名同结构，方便统一开关。
func _foot_body(footprint: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "FootCollision"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = footprint
	shape.shape = rect
	# 贴图以脚底为原点，碰撞条压在脚下而不是中间。
	shape.position = Vector2(0, -footprint.y / 2.0 + 1.0)
	body.add_child(shape)
	return body


func refresh() -> void:
	var community: Node = get_tree().get_first_node_in_group(&"community")
	applied_stage = int(community.stage) if community != null else 0
	for index: int in fences.size():
		var fence: Sprite2D = fences[index]
		fence.visible = applied_stage >= 1 or index == 0 or index == 3
		# 还没修好的栅栏是隐藏的，不能留下隐形墙
		_set_collider_enabled(fence, fence.visible)
	for stall: Sprite2D in stalls:
		stall.visible = applied_stage >= 2
	sign.visible = applied_stage >= 3
	_set_collider_enabled(sign, sign.visible)


## 隐藏的装饰不该继续挡路。
func _set_collider_enabled(node: Node, enabled: bool) -> void:
	var body: Node = node.get_node_or_null("FootCollision")
	if body == null:
		return
	for shape: Node in body.get_children():
		if shape is CollisionShape2D:
			(shape as CollisionShape2D).set_deferred("disabled", not enabled)
