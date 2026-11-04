extends Sprite2D
## 活动统一走现有 interactable / E 入口，贴图参与 World 的 Y 排序。

var manager: Node
var kind: StringName
var key: int = -1
var radius: float = 23.0


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return visible and player.global_position.distance_to(global_position) <= radius


func hint() -> String:
	return manager.activity_hint(kind, key)


func interact(_cell: Vector2i) -> void:
	manager.interact_activity(kind, key)


func add_body(size: Vector2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	shape.position = Vector2(0, -size.y / 2)
	body.add_child(shape)
	add_child(body)
