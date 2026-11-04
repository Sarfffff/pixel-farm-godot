extends Resource
## 地面资源美术和占地约定。planned_drop 只是接入规划，不自动发放物品。

@export var id: StringName
@export var display_name: String
@export var texture: Texture2D
@export var footprint: Vector2i = Vector2i.ONE
@export var visual_scale: float = 1.0
@export var blocks_movement: bool = false
@export var tool_hint: String = "徒手采集"
@export var planned_drop: StringName
@export var region_tags: Array[StringName] = []
@export var integration_status: String = "视觉与碰撞预览，采集尚未接入"
