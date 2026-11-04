extends SceneTree
## 发行就绪检查：导出预设、版权文件、版本号、素材隔离。
##
## 这是"静态"检查，不需要导出模板也能跑；模板没装时只提示、不算失败。
## --headless --path . --script res://tools/check/check_release.gd

const PRESET_PATH := "res://export_presets.cfg"
const CREDITS_PATH := "res://CREDITS.md"
const EXTERNAL_ART := "art/reference/stardew_valley"
const REQUIRED_CREDIT_TOKENS: Array[String] = ["Godot", "MIT", "星露谷", "ConcernedApe"]

var _failures: int = 0
var _notes: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[release] FAIL: " + message)


func _note(message: String) -> void:
	_notes.append(message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_check_project()
	_check_presets()
	_check_credits()
	_check_asset_isolation()
	_check_templates()
	_finish()


## 项目元信息：版本号、主场景、图标。
func _check_project() -> void:
	var version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	_check(not version.is_empty(), "project has application/config/version")
	var main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check(main_scene.begins_with("res://"), "main scene is set")
	_check(FileAccess.file_exists(main_scene), "main scene file exists: %s" % main_scene)
	var icon: String = String(ProjectSettings.get_setting("application/config/icon", ""))
	_check(icon.begins_with("res://") and FileAccess.file_exists(icon), "application icon exists")
	_note("版本号 %s，主场景 %s" % [version, main_scene])


## 导出预设：必须有可用的 Windows preset，且排除不该进包的东西。
func _check_presets() -> void:
	_check(FileAccess.file_exists(PRESET_PATH), "export_presets.cfg exists")
	if not FileAccess.file_exists(PRESET_PATH):
		return
	var config := ConfigFile.new()
	var err := config.load(PRESET_PATH)
	_check(err == OK, "export_presets.cfg parses")
	if err != OK:
		return
	_check(config.has_section("preset.0"), "preset.0 exists")
	if not config.has_section("preset.0"):
		return
	var platform: String = String(config.get_value("preset.0", "platform", ""))
	_check(platform == "Windows Desktop", "preset targets Windows Desktop (got %s)" % platform)
	var export_path: String = String(config.get_value("preset.0", "export_path", ""))
	_check(export_path.ends_with(".exe"), "export path ends with .exe (%s)" % export_path)

	var exclude: String = String(config.get_value("preset.0", "exclude_filter", ""))
	for pattern: String in ["tools/", "docs/", "art/", "archive/", "build/"]:
		_check(exclude.contains(pattern), "exclude_filter must skip %s" % pattern)

	var product: String = String(config.get_value("preset.0.options", "application/product_name", ""))
	_check(not product.is_empty(), "product_name is set")
	var embed: bool = bool(config.get_value("preset.0.options", "binary_format/embed_pck", false))
	_check(embed, "pcK embedded (single .exe)")
	_note("导出目标 %s，产品名 %s" % [export_path, product])


## 版权文件：存在且覆盖引擎、外部素材、原创声明。
func _check_credits() -> void:
	_check(FileAccess.file_exists(CREDITS_PATH), "CREDITS.md exists")
	if not FileAccess.file_exists(CREDITS_PATH):
		return
	var text := FileAccess.get_file_as_string(CREDITS_PATH)
	for token: String in REQUIRED_CREDIT_TOKENS:
		_check(text.contains(token), "CREDITS.md mentions %s" % token)
	_check(text.contains("MIT"), "CREDITS.md states the engine license")
	_note("CREDITS.md 覆盖：引擎 / 外部素材 / 音频 / 美术")


## 外部素材隔离：不该有运行时代码引用它，且必须有 .gdignore。
func _check_asset_isolation() -> void:
	var external_dir := "res://%s" % EXTERNAL_ART
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(external_dir)):
		_note("仓库内没有 %s，跳过隔离检查" % EXTERNAL_ART)
		return
	_check(
		FileAccess.file_exists(ProjectSettings.globalize_path(external_dir).path_join(".gdignore")),
		"%s must contain .gdignore" % EXTERNAL_ART
	)
	var offenders: Array[String] = []
	_scan_for_reference("res://scripts", offenders)
	_scan_for_reference("res://scenes", offenders)
	_scan_for_reference("res://data", offenders)
	_check(offenders.is_empty(), "no runtime file references %s (%s)" % [EXTERNAL_ART, ", ".join(offenders)])


func _scan_for_reference(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_for_reference(full, offenders)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var text := FileAccess.get_file_as_string(full)
			if text.contains(EXTERNAL_ART):
				offenders.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


## 导出模板：没有就提示，不判失败（本机可能还没下载模板）。
func _check_templates() -> void:
	var root := OS.get_data_dir().path_join("export_templates")
	if not DirAccess.dir_exists_absolute(root):
		_note("未安装导出模板：先运行 `godot --headless --export-release` 前需在编辑器下载 4.7.2 模板")
		return
	var versions: PackedStringArray = DirAccess.get_directories_at(root)
	_note("已安装导出模板：%s" % ", ".join(versions))


func _finish() -> void:
	for line: String in _notes:
		print("[release] " + line)
	if _failures == 0:
		print("[release] PASS")
	else:
		printerr("[release] FAIL，共 %d 项" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
