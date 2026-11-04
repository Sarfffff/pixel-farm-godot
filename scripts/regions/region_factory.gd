extends RefCounted
## 消费已有原生地图蓝图，仅移除预览控制器；正式资源行为由组合根装配。

static func instantiate_region(id: StringName) -> Node2D:
	var packed: PackedScene = load("res://scenes/maps/" + String(id) + "_preview.tscn")
	var region: Node2D = packed.instantiate() as Node2D
	region.set_script(null)
	for path: String in ["World/PreviewPlayer", "Camera"]:
		var preview: Node = region.get_node_or_null(path)
		if preview != null:
			preview.get_parent().remove_child(preview)
			preview.free()
	region.set_meta(&"region_id", id)
	return region


static func entries(region: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Node in region.get_node("World").get_children():
		if not child.has_meta(&"resource_definition"): continue
		var definition: Resource = child.get_meta(&"resource_definition")
		var cell: Vector2i = child.get_meta(&"cell")
		var drop_cell: Vector2i = cell + Vector2i((definition.footprint.x - 1) / 2, definition.footprint.y - 1)
		result.append({"id": String(child.get_meta(&"stable_id")), "kind": String(definition.id), "cell": cell, "drop_cell": drop_cell})
	return result
