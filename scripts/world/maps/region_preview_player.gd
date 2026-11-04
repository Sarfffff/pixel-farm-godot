extends CharacterBody2D
## 仅用于地图碰撞和比例预览；不接入正式角色的背包或存档。

@onready var _sprite: AnimatedSprite2D = $Sprite
var _facing: String = "down"


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = direction * 90.0
	move_and_slide()
	if direction.length_squared() > 0:
		_facing = ("right" if direction.x > 0 else "left") if absf(direction.x) > absf(direction.y) else ("down" if direction.y > 0 else "up")
	var animation: StringName = StringName(("walk_" if direction.length_squared() > 0 else "idle_") + _facing)
	if _sprite.sprite_frames.has_animation(animation): _sprite.play(animation)
