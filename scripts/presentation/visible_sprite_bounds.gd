extends RefCounted
## 新建筑为共用脚底保留透明画布，遮挡与占地检查只考虑可见部分。

static var _used: Dictionary[int, Rect2i] = {}


static func local_rect(sprite: Sprite2D) -> Rect2:
	var rect: Rect2 = sprite.get_rect()
	if sprite.texture != null and not sprite.region_enabled and sprite.texture.resource_path.contains("/presentation_v3/structures/"):
		var id: int = sprite.texture.get_instance_id()
		if not _used.has(id): _used[id] = sprite.texture.get_image().get_used_rect()
		var bounds: Rect2i = _used[id]
		rect = Rect2(rect.position + Vector2(bounds.position), Vector2(bounds.size))
	return rect
