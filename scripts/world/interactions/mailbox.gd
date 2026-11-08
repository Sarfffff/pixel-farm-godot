extends Node2D
## 世界信箱：只报告打开意图与显示未读标记；投递和领奖均由公开服务完成。

signal open_requested
const TEXTURE: Texture2D = preload("res://assets/packs/content_v1/objects/craftables/mailbox.png")
var _unread: Callable
var _marker: Label


func _ready() -> void:
	add_to_group(&"interactable")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sprite := Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.scale = Vector2(0.5, 0.5)
	sprite.offset = Vector2(0, -16)
	add_child(sprite)
	var body := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 6)
	collider.shape = shape
	collider.position = Vector2(0, -3)
	body.add_child(collider)
	add_child(body)
	_marker = Label.new()
	_marker.position = Vector2(-5, -25)
	_marker.add_theme_font_size_override("font_size", 8)
	_marker.add_theme_color_override("font_color", Color("eedba5"))
	_marker.add_theme_color_override("font_outline_color", Color("514c40"))
	_marker.add_theme_constant_override("outline_size", 2)
	add_child(_marker)
	refresh()


func configure(unread: Callable) -> void:
	_unread = unread
	refresh()


func refresh() -> void:
	if _marker == null: return
	var count: int = int(_unread.call()) if _unread.is_valid() else 0
	_marker.text = "%d" % count
	_marker.visible = count > 0


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= 24.0


func hint() -> String:
	var count: int = int(_unread.call()) if _unread.is_valid() else 0
	return "[F] 查看信箱 · %d 封未读" % count if count > 0 else "[F] 查看信箱"


func interact(_cell: Vector2i) -> void:
	open_requested.emit()


func _exit_tree() -> void:
	_unread = Callable()
