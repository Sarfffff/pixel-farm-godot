extends CanvasLayer
## 全屏黑幕：进出屋、睡觉这类"世界要换一下"的场合用它遮住过程。
##
## 放在最高的 CanvasLayer（128），能盖住 HUD 与所有面板。
## 用法：
##   await fade.fade_out(0.3)   # 渐黑
##   ...换场景/推进一天...
##   await fade.fade_in(0.5)    # 渐亮
##
## 黑屏期间默认不拦截鼠标（`MOUSE_FILTER_IGNORE`），避免吞掉面板点击；
## 需要"黑屏时不许乱点"由调用方锁玩家输入负责。

const FADE_LAYER: int = 128
const CAPTION_COLOR := Color(0.96, 0.90, 0.72, 1.0)

var _rect: ColorRect
var _caption: Label
var _tween: Tween


func _ready() -> void:
	add_to_group(&"screen_fade")
	layer = FADE_LAYER
	_build()


func fade_out(duration: float = 0.35) -> void:
	await _fade_to(1.0, duration)


func fade_in(duration: float = 0.35) -> void:
	await _fade_to(0.0, duration)


func is_black() -> bool:
	return _rect != null and _rect.color.a >= 0.99


## 黑屏中央的一句话（"晚安 · 第 1 天"这类）。传空串等于清掉。
func show_caption(text: String) -> void:
	if _caption == null:
		return
	_caption.text = text
	_caption.visible = not text.is_empty()


func hide_caption() -> void:
	if _caption != null:
		_caption.visible = false


func _fade_to(alpha: float, duration: float) -> void:
	if _rect == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duration <= 0.0:
		_rect.color.a = alpha
		return
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", alpha, duration)
	await _tween.finished


func _build() -> void:
	_rect = ColorRect.new()
	_rect.name = "Curtain"
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.visible = false
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", _make_font())
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", CAPTION_COLOR)
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 项目没有内置字体，界面统一用系统字体。
func _make_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif"])
	return font
