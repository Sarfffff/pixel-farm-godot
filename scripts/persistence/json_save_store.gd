extends "res://scripts/persistence/save_store.gd"
## 同目录临时文件 + 上一版备份。正式文件只在完整写入并 flush 成功后替换。


func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = FileAccess.get_open_error()
		return {}
	var parser := JSON.new()
	last_error = parser.parse(file.get_as_text())
	file.close()
	if last_error != OK or not parser.data is Dictionary:
		last_error = ERR_PARSE_ERROR
		return {}
	return parser.data


func write(path: String, document: Dictionary) -> bool:
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error != OK:
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		# 不用损坏的正式文件覆盖可恢复的备份。
		if not read(path).is_empty():
			last_error = DirAccess.copy_absolute(absolute, absolute + ".bak.tmp")
			if last_error != OK:
				return false
			last_error = _install(absolute + ".bak.tmp", absolute + ".bak")
			if last_error != OK:
				return false
	last_error = _install(ProjectSettings.globalize_path(temp), absolute)
	return last_error == OK


## 独立替换步骤可由故障测试替身覆盖，无需真的制造磁盘故障。
func _install(temp: String, destination: String) -> Error:
	return DirAccess.rename_absolute(temp, destination)
