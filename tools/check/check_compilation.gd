extends SceneTree
## 显式编译脚本，覆盖无 class_name、离线工具和编辑器插件脚本，不只依赖场景加载。

var _failures: int = 0
var _compiled: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	var paths: Array[String] = []
	for folder: String in ["res://scripts", "res://tools", "res://addons"]:
		_collect(folder, paths)
	paths.sort()
	for path: String in paths:
		# 当前入口已经编译并正在执行，不能在栈上重载自身。
		if path == get_script().resource_path:
			_compiled += 1
			continue
		var script := load(path) as GDScript
		if script == null or script.reload(true) != OK:
			_failures += 1
			printerr("[compilation] FAIL: " + path)
		else:
			_compiled += 1
	if _compiled < 100:
		_failures += 1
		printerr("[compilation] FAIL: source discovery did not reach the expected project scope")
	print("[compilation] %d scripts compiled, %d failures; reached end" % [_compiled, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _collect(folder: String, result: Array[String]) -> void:
	var directory := DirAccess.open(folder)
	if directory == null:
		_failures += 1
		return
	for file: String in directory.get_files():
		# tools 下的 _*.gd 是 .gitignore 声明的临时诊断脚本，不属于交付源码。
		if file.ends_with(".gd") and not (folder.begins_with("res://tools") and file.begins_with("_")):
			result.append(folder.path_join(file))
	for child: String in directory.get_directories():
		if not child.begins_with("."):
			_collect(folder.path_join(child), result)
