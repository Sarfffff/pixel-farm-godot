class_name DeviceDefinition
extends Resource
## 可信设备目录；存档只保存type_id，不接受任意资源或脚本路径。

@export var id: StringName = &""
@export var placement_item_id: StringName = &""
@export var title: String = ""
@export var texture: Texture2D
@export var footprint: Vector2i = Vector2i.ONE
@export var storage_capacity: int = 0
@export var visual_scale: Vector2 = Vector2(0.5, 0.5)


func is_valid() -> bool:
	return id != &"" and placement_item_id != &"" and not title.is_empty() and texture != null and footprint.x > 0 and footprint.y > 0 and footprint.x <= 8 and footprint.y <= 8 and storage_capacity >= 0 and storage_capacity <= 48


func cells(anchor: Vector2i, facing: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var size: Vector2i = footprint if facing % 2 == 0 else Vector2i(footprint.y, footprint.x)
	for y: int in size.y:
		for x: int in size.x: result.append(anchor + Vector2i(x, y))
	return result
