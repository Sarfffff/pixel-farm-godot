extends Node2D
## 社区中心：靠近按 F 打开上缴面板，逐阶段修好可以解锁新种子。

const INTERACT_RADIUS: float = 40.0


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	var community := get_tree().get_first_node_in_group(&"community")
	if community == null or not community.has_method(&"stage_count"):
		return "按 F 进社区中心"
	if community.is_finished():
		return "按 F 进社区中心（已全部修好）"
	return "按 F 进社区中心（%d/%d）" % [int(community.stage), int(community.stage_count())]


func interact(_cell: Vector2i) -> void:
	var panel := get_tree().current_scene.get_node_or_null("UI/CommunityPanel")
	if panel != null and panel.has_method(&"set_open"):
		panel.set_open(true)
