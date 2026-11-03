extends Control
## 社区中心面板：当前阶段要交什么、交够没有、修好能解锁什么。

@onready var _stage_title: Label = %StageTitle
@onready var _desc: Label = %Desc
@onready var _needs: VBoxContainer = %Needs
@onready var _reward: Label = %Reward
@onready var _donate: Button = %DonateButton
@onready var _message: Label = %Message
@onready var _overlay: ColorRect = $Overlay

var _font: Font


func _ready() -> void:
	_font = get_theme_font("font")
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_donate.pressed.connect(_on_donate_pressed)
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		if not _donate.disabled:
			_on_donate_pressed()
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	visible = open
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(open)
	var toolbar := get_node_or_null("../Toolbar")
	if toolbar != null and toolbar.has_method(&"set_ui_visible"):
		toolbar.set_ui_visible(not open)
	if not open:
		return
	for panel_name: String in ["InventoryPanel", "ShopPanel", "DaySummary", "DialoguePanel", "HelpPanel", "OrderPanel"]:
		var other := get_node_or_null("../%s" % panel_name) as Control
		if other != null and other.visible:
			other.call(&"set_open", false)
	_refresh()


func _refresh() -> void:
	_clear_needs()
	var community := get_tree().get_first_node_in_group(&"community")
	if community == null or not community.has_method(&"current"):
		_stage_title.text = "社区中心"
		_desc.text = "系统没准备好"
		_reward.text = ""
		_donate.disabled = true
		return
	if community.is_finished():
		_stage_title.text = "社区中心 · 全部修好了"
		_desc.text = "镇上的商队常来，农场也算有了个像样的门面。"
		_add_need_row(null, "已完成 %d 个阶段" % int(community.stage_count()), -1, -1)
		_reward.text = ""
		_donate.disabled = true
		_donate.text = "已完成"
		_message.text = ""
		return
	var current: Dictionary = community.current()
	_stage_title.text = "第 %d/%d 阶段 · %s" % [
		int(community.stage) + 1, int(community.stage_count()), String(current[&"title"])
	]
	_desc.text = String(current[&"desc"])
	for row: Dictionary in community.progress():
		_add_need_row(row[&"icon"], String(row[&"name"]), int(row[&"have"]), int(row[&"need"]))
	_reward.text = "奖励 %d 金币 · %s" % [int(current[&"reward"]), String(current[&"unlock"])]
	var ready: bool = community.can_donate()
	_donate.disabled = not ready
	_donate.text = "上缴" if ready else "材料不够"
	_message.text = "按 E 或点按钮上缴" if ready else ""


func _clear_needs() -> void:
	for child in _needs.get_children():
		child.queue_free()


## have < 0 时只显示一行说明文字（已完成的场合）。
func _add_need_row(icon: Texture2D, label_text: String, have: int, need: int) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)

	if icon != null:
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(16, 16)
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		texture_rect.texture = icon
		line.add_child(texture_rect)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", Color(0.88, 0.82, 0.66, 1))
	line.add_child(name_label)

	if need >= 0:
		var count_label := Label.new()
		count_label.text = "%d / %d" % [have, need]
		count_label.add_theme_font_override("font", _font)
		count_label.add_theme_font_size_override("font_size", 7)
		var enough := have >= need
		count_label.add_theme_color_override(
			"font_color", Color(0.66, 0.86, 0.56, 1) if enough else Color(0.9, 0.55, 0.45, 1)
		)
		line.add_child(count_label)

	_needs.add_child(line)


func _on_donate_pressed() -> void:
	var community := get_tree().get_first_node_in_group(&"community")
	if community == null or not community.has_method(&"donate"):
		return
	if not community.donate():
		_message.text = "材料还不够"
		return
	_refresh()
	_message.text = "阶段完成，新的种子上架了"


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
