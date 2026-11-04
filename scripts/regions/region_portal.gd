extends Node2D
## 显式E交互，避免加载或出生在入口附近时自动来回传送。

signal requested(target: StringName, arrival: StringName)
var target: StringName
var arrival: StringName
var destination_name: String


func _ready() -> void:
	add_to_group(&"interactable")
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/packs/content_v1/objects/craftables/sign_board.png")
	sprite.offset = Vector2(0, -14)
	add_child(sprite)
	var label := Label.new()
	label.text = destination_name
	label.position = Vector2(-26, -34)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color("f0dfb5"))
	label.add_theme_color_override("font_outline_color", Color("514c40"))
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)


func player_in_range(player: Node2D) -> bool:
	return is_visible_in_tree() and player.global_position.distance_to(global_position) <= 23.0


func hint() -> String:
	return "[E] 前往" + destination_name


func interact(_cell: Vector2i) -> void:
	requested.emit(target, arrival)
