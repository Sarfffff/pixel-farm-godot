extends Resource
## 活动布局与数值集中配置，逻辑不依赖素材图集编号。

@export var storage_capacity: int = 24
@export var chest_position: Vector2 = Vector2(568, 168)
@export var machine_position: Vector2 = Vector2(584, 208)
@export var fishing_position: Vector2 = Vector2(472, 292)
@export var fishing_target: Vector2 = Vector2(472, 330)
@export var fishing_limit: int = 3
@export var fishing_cost: int = 4
@export var fish_wait_min: float = 1.5
@export var fish_wait_max: float = 3.0
@export var fish_bite_window: float = 2.0
@export var fish_items: Array[StringName] = [&"crucian_carp", &"common_carp"]
@export var forage_respawn_per_day: int = 2
@export var forage_positions: Array[Vector2] = []
@export var forage_items: Array[StringName] = []
