extends Resource
## 区域原型配置；正式世界整合前不改变主农场或玩家存档。

@export var id: StringName
@export var display_name: String
@export_multiline var purpose: String
@export var layout: StringName
@export var map_size: Vector2i = Vector2i(48, 32)
@export var seed_value: int = 20261104
@export var resource_count: int = 48
@export var resource_weights: Dictionary = {}
@export var unlock_note: String = "区域预览，尚未接入主世界"
