extends RefCounted
## 应用和检查共用退出边界；退出请求合并，等待音频线程释放后结束引擎。

static var _quitting: bool = false


static func prepare_exit(tree: SceneTree) -> void:
	await tree.process_frame
	var audio: Node = tree.root.get_node_or_null("AudioManager")
	if audio != null:
		audio.shutdown()
	await tree.create_timer(0.25, true).timeout


static func quit(tree: SceneTree, code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	tree.paused = true
	await prepare_exit(tree)
	tree.quit(code)
