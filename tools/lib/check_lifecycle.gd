extends RefCounted
## 功能断言结束与引擎退出分开：先释放场景，再回收音频线程，保留完整退出日志。


static func finish(tree: SceneTree, code: int) -> void:
	await preload("res://scripts/platform/app_lifecycle.gd").prepare_exit(tree)
	print("[checks] lifecycle complete; exit=%d" % code)
	tree.quit(code)
