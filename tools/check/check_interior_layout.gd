extends SceneTree
## 室内家具体检：农舍与商店里的每一件家具都按同一套规则校验。
##
## 规则：
##  1. 家具贴图必须是 32×32（`terrain/interiors` 里的 16×16 零件混进来会像小木箱）
##  2. 脚底落点必须在可走地板范围内
##  3. 碰撞块不能互相重叠，也不能伸进墙体
##  4. 地毯 / 地垫必须在 FloorProps 层：不参与 Y 排序、层级低于家具
##  5. 门口通道（门往内 2.5 格）不能被家具碰撞堵住
##
## --headless --path . --script res://tools/check/check_interior_layout.gd

const SCENES: Array[String] = [
	"res://scenes/world/house_interior.tscn",
	"res://scenes/world/shop_interior.tscn",
]
const TILE: int = 16
## 家具贴图的标准边长
const FURNITURE_SIZE: int = 32
## 家具可见高度上限（玩家可见高度约 20px，家具不该再高出一截）
const MAX_FURNITURE_HEIGHT: float = 22.0

var _failures: int = 0


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	for path: String in SCENES:
		_audit(path)
	if _failures == 0:
		print("[interior] PASS")
	else:
		printerr("[interior] FAIL，共 %d 项" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[interior] FAIL: " + message)


## 这些家具必须挡路：能坐的、能站的、以及有实体的绿植与桶篮。
func _needs_blocker(node_name: String) -> bool:
	for keyword: String in ["Chair", "Stool", "Armchair", "Bench", "Fern", "Basket", "Table", "Bed"]:
		if node_name.contains(keyword):
			return true
	return false


func _audit(path: String) -> void:
	var scene := load(path) as PackedScene
	_check(scene != null, "%s loads" % path)
	if scene == null:
		return
	var room := scene.instantiate() as Node2D
	var tag: String = path.get_file().get_basename()

	var floor_layer := room.get_node_or_null("Floor") as TileMapLayer
	var props := room.get_node_or_null("Props") as Node2D
	var flat := room.get_node_or_null("FloorProps") as Node2D
	var door := room.get_node_or_null("ExitDoor") as Node2D
	_check(floor_layer != null and props != null and flat != null, "%s has floor / props / floor props" % tag)
	if floor_layer == null or props == null or flat == null:
		room.free()
		return

	var used: Rect2i = floor_layer.get_used_rect()
	var floor_rect := Rect2(
		Vector2(used.position * TILE), Vector2(used.size * TILE)
	)

	# —— 家具层：贴图规格、落点、碰撞 ——
	var blockers: Array[Rect2] = []
	var blocker_names: Array[String] = []
	for child: Node in props.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		# 多帧贴图是 NPC（3×4 走路图集），不是家具
		if sprite.hframes > 1 or sprite.vframes > 1:
			continue
		var size: Vector2 = sprite.texture.get_size()
		_check(
			size == Vector2(FURNITURE_SIZE, FURNITURE_SIZE),
			"%s/%s uses 32x32 art (got %s)" % [tag, sprite.name, size]
		)
		_check(
			sprite.position.y >= floor_rect.position.y and sprite.position.y <= floor_rect.end.y,
			"%s/%s stands on the floor (y=%.0f)" % [tag, sprite.name, sprite.position.y]
		)
		_check(
			sprite.position.x >= floor_rect.position.x and sprite.position.x <= floor_rect.end.x,
			"%s/%s is inside the room (x=%.0f)" % [tag, sprite.name, sprite.position.x]
		)
		# 家具不能画得比玩家还高大（玩家可见高度约 20px）
		var art_height: int = sprite.texture.get_image().get_used_rect().size.y
		_check(
			float(art_height) * sprite.scale.y <= MAX_FURNITURE_HEIGHT,
			"%s/%s is not taller than the player (%.1fpx)" % [
				tag, sprite.name, float(art_height) * sprite.scale.y
			]
		)

		var body := sprite.get_node_or_null("Body") as StaticBody2D
		# 座椅类必须有碰撞，玩家不能直接穿过去
		if _needs_blocker(String(sprite.name)):
			_check(body != null, "%s/%s cannot be walked through" % [tag, sprite.name])
		if body == null:
			continue
		var shape := body.get_child(0) as CollisionShape2D
		if shape == null or shape.shape == null:
			continue
		var box := shape.shape as RectangleShape2D
		if box == null:
			continue
		# 碰撞块是家具的子节点，会跟着家具一起缩放
		var rect := Rect2(
			sprite.position + shape.position * sprite.scale,
			box.size * sprite.scale
		)
		_check(
			floor_rect.encloses(rect),
			"%s/%s blocker stays inside the floor" % [tag, sprite.name]
		)
		for index: int in blockers.size():
			_check(
				not blockers[index].intersects(rect),
				"%s/%s blocker overlaps %s" % [tag, sprite.name, blocker_names[index]]
			)
		blockers.append(rect)
		blocker_names.append(String(sprite.name))

	# —— 平铺层：地毯不参与排序、层级压在家具下 ——
	_check(not flat.y_sort_enabled, "%s floor props do not y-sort" % tag)
	_check(
		flat.z_index < props.z_index,
		"%s floor props sit below furniture (%d < %d)" % [tag, flat.z_index, props.z_index]
	)
	for child: Node in flat.get_children():
		var rug := child as Sprite2D
		if rug == null or rug.texture == null:
			continue
		_check(
			rug.texture.get_size() == Vector2(FURNITURE_SIZE, FURNITURE_SIZE),
			"%s/%s floor prop uses 32x32 art" % [tag, rug.name]
		)

	# —— 门口通道不能被堵 ——
	if door != null:
		var corridor := Rect2(door.position + Vector2(-12, -44), Vector2(24, 44))
		for index: int in blockers.size():
			_check(
				not blockers[index].intersects(corridor),
				"%s/%s blocks the doorway corridor" % [tag, blocker_names[index]]
			)

	room.free()
