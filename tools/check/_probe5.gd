extends SceneTree
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var room = load("res://scenes/world/house_interior.tscn").instantiate()
	root.add_child(room)
	await physics_frame
	await physics_frame
	var space = room.get_world_2d().direct_space_state
	var names = ["OakChair", "OakChair2", "WoodStool", "DiningTable", "PottedFern", "Basket"]
	for n in names:
		var node = room.get_node_or_null("Props/" + n)
		if node == null:
			print(n, " -> node missing")
			continue
		var body = node.get_node_or_null("Body")
		if body == null:
			print(n, " -> no body")
			continue
		var shape = body.get_child(0) as CollisionShape2D
		var center = node.global_position + shape.position * node.scale
		var hits = space.intersect_point(center, 8)
		var solid := false
		for h in hits:
			if h.collider is StaticBody2D:
				solid = true
		print(n, " center=", center, " solid=", solid)
	quit(0)
