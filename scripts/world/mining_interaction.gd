extends RefCounted

const RockScript: Script = preload("res://scripts/world/breakable_rock.gd")


static func rock_at(tree: SceneTree, center: Vector2) -> Sprite2D:
	var nearest: Sprite2D
	var nearest_distance: float = INF
	for candidate: Node in tree.get_nodes_in_group(&"breakable_rock"):
		var rock: Sprite2D = candidate as Sprite2D
		if rock == null or rock.is_queued_for_deletion() or rock.is_broken:
			continue
		var base: Vector2 = rock.global_position - Vector2(0, 4)
		var difference: Vector2 = (base - center).abs()
		var distance: float = base.distance_squared_to(center)
		if difference.x <= 19.0 and difference.y <= 11.0 and distance < nearest_distance:
			nearest = rock
			nearest_distance = distance
	return nearest


static func hint(tree: SceneTree, center: Vector2) -> String:
	var rock: Sprite2D = rock_at(tree, center)
	if rock == null:
		return "面向石头 · 空格 / 左键碎石"
	if not rock.can_mine():
		return "背包空间不足 · 按 B 整理后再碎石"
	return "还需 %d 击 · 空格 / 左键" % rock.hits_remaining


static func restore(world: Node2D, saved: Dictionary) -> void:
	world.set_meta(&"rock_states", saved.duplicate())
	for child: Node in world.get_children():
		if child.get_script() == RockScript and saved.has(String(child.name)):
			child.restore_state(int(saved[String(child.name)]))
