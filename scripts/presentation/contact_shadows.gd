extends Node2D
## 地面接触影用整数像素绘制，角色与道具仍按原来的 Y 排序。

var world: Node2D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null: return
	for child: Node in world.get_children():
		if not child is Node2D or child == self or not (child as Node2D).is_visible_in_tree(): continue
		var width: float = 9.0
		if child.name in [&"Cottage0", &"GeneralStore1", &"CommunityBuilding"]: width = 45.0
		elif child.name == &"ChickenCoop": width = 30.0
		elif child is Sprite2D and (child as Sprite2D).texture != null:
			width = minf(22.0, (child as Sprite2D).get_rect().size.x * 0.55)
		elif not child is CharacterBody2D and not child.is_in_group(&"berry_bush"): continue
		var p: Vector2 = (child as Node2D).position.floor()
		draw_rect(Rect2(p + Vector2(-width / 2, -1), Vector2(width, 3)), Color(0.24, 0.30, 0.21, 0.12))
