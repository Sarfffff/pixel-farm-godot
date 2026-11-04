extends SceneTree
## 临时脚本：把两间屋子的每件家具逐项打印出来，人工核对。

func _init() -> void:
	for path: String in ["res://scenes/world/house_interior.tscn", "res://scenes/world/shop_interior.tscn"]:
		_dump(path)
	quit(0)


func _dump(path: String) -> void:
	var room := (load(path) as PackedScene).instantiate() as Node2D
	print("=== ", path.get_file().get_basename(), " ===")
	print("  layer           name              art      visible  scale  blocker")
	for layer_name: String in ["FloorProps", "Props"]:
		var layer := room.get_node_or_null(layer_name) as Node2D
		if layer == null:
			continue
		for child: Node in layer.get_children():
			var sprite := child as Sprite2D
			if sprite == null or sprite.texture == null:
				continue
			if sprite.hframes > 1 or sprite.vframes > 1:
				print("  %-15s %-17s (npc %s)" % [layer_name, sprite.name, sprite.texture.get_size()])
				continue
			var art: Vector2i = sprite.texture.get_size()
			var used: Rect2i = sprite.texture.get_image().get_used_rect()
			var visible_h: float = float(used.size.y) * sprite.scale.y
			var body := sprite.get_node_or_null("Body") as StaticBody2D
			var blocker := "-"
			if body != null and body.get_child_count() > 0:
				var shape := body.get_child(0) as CollisionShape2D
				var box := shape.shape as RectangleShape2D
				if box != null:
					blocker = "%dx%d @y%.0f" % [
						int(box.size.x), int(box.size.y),
						sprite.position.y + shape.position.y * sprite.scale.y
					]
			print("  %-15s %-17s %dx%d    %5.1fpx  %.2f   %s" % [
				layer_name, sprite.name, art.x, art.y, visible_h, sprite.scale.x, blocker
			])
	room.free()
