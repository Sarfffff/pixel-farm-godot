extends Node
## 技能只读显示适配；经验、等级与能力均由服务查询，View 没有加经验入口。

var _service: RefCounted
var _view: Control
var _selected: StringName = &""


func configure(service: RefCounted, view: Control = null) -> void:
	dispose()
	_service = service
	_view = view
	_selected = &""
	_service.changed.connect(refresh)
	if is_instance_valid(_view):
		_view.selection_requested.connect(_select)
		_view.refresh_requested.connect(refresh)
		_view.tree_exiting.connect(dispose)
	refresh()


func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var detail: Dictionary = {}
	if _service == null: return {"rows": rows, "selected_id": &"", "detail": detail}
	for definition: SkillDefinition in _service.definitions():
		var level: int = _service.level_of(definition.id)
		var xp: int = _service.xp_of(definition.id)
		rows.append({"id": definition.id, "text": "%s · %d/%d级" % [definition.display_name, level, definition.levels.size()]})
		if _selected == &"": _selected = definition.id
		if definition.id != _selected: continue
		var next: String = "已满级 · 经验已封顶"
		if level < definition.levels.size():
			next = "距离%d级：%d经验（累计%d）" % [level + 1, definition.cumulative_xp[level] - xp, definition.cumulative_xp[level]]
		var active: Array[String] = []
		var roadmap: Array[String] = []
		for index in definition.levels.size():
			var description: String = definition.levels[index].description
			if index < level: active.append(description)
			roadmap.append("%d级 · %s%s" % [index + 1, description, " ✓" if index < level else ""])
		detail = {"title": "%s · %d/%d级" % [definition.display_name, level, definition.levels.size()],
			"text": "总经验 %d/%d\n%s\n\n经验来源\n%s\n\n当前能力（即时生效）\n%s\n\n五级成长\n%s" % [
				xp, definition.max_xp(), next, definition.labor_hint,
				"\n".join(active) if not active.is_empty() else "尚未升级 · 完成真实劳动即可积累", "\n".join(roadmap)]}
	return {"rows": rows, "selected_id": _selected, "detail": detail}


## 只读夜间摘要；调用或漏看不会发奖，也不会确认已经展示。
func upgrade_lines(day: int = 0) -> PackedStringArray:
	var lines := PackedStringArray()
	if _service == null: return lines
	for row: Dictionary in _service.pending_upgrades(day):
		lines.append("%s升至%d级 · %s" % [row.skill_name, row.level, row.description])
	return lines


func refresh() -> void:
	if is_instance_valid(_view): _view.render(snapshot())


func open() -> void:
	if is_instance_valid(_view):
		refresh()
		_view.set_open(true)


func _select(id: StringName) -> void:
	if _service == null: return
	for definition: SkillDefinition in _service.definitions():
		if definition.id == id:
			_selected = id
			refresh()
			return


func _exit_tree() -> void:
	dispose()


func dispose() -> void:
	if is_instance_valid(_service) and _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)
	if is_instance_valid(_view):
		if _view.selection_requested.is_connected(_select): _view.selection_requested.disconnect(_select)
		if _view.refresh_requested.is_connected(refresh): _view.refresh_requested.disconnect(refresh)
		if _view.tree_exiting.is_connected(dispose): _view.tree_exiting.disconnect(dispose)
	_service = null
	_view = null
