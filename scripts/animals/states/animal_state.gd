extends RefCounted
## 状态窄接口。不持有宿主或状态机引用，避免相互持有形成引用环。


func enter(_context: RefCounted) -> void:
	pass


func tick(_context: RefCounted, _delta: float, _position: Vector2) -> void:
	pass


func exit(_context: RefCounted) -> void:
	pass
