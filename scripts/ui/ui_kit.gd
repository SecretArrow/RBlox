extends RefCounted
## UiKit — helper statis untuk membangun widget UI secara programatik.
## Dirancang untuk layar sentuh: target sentuh minimal 48px, tinggi tombol >= 56.
## Semua StyleBoxFlat memakai sudut membulat 12 dengan state normal/hover/pressed.

# ------------------------------------------------------------ palet warna --
# EN: dark palette
const COL_BG_DARK := Color("#141824")
const COL_PANEL_DARK := Color("#1e2433")
const COL_TEXT_DARK := Color("#eef1f8")
const COL_ACCENT := Color("#4f8cff")
const COL_ACCENT2 := Color("#5ad48a")
# EN: light palette
const COL_BG_LIGHT := Color("#f4f6fb")
const COL_PANEL_LIGHT := Color("#ffffff")
const COL_TEXT_LIGHT := Color("#1a2233")
const COL_ACCENT_LIGHT := Color("#2f6fed")
const COL_ACCENT2_LIGHT := Color("#2f9e5f")

const CORNER := 12
const BTN_MIN_HEIGHT := 56.0
const TOUCH_MIN := 48.0


static func make_button(
	text: String, min_size: Vector2 = Vector2(160, 56), accent: bool = true
) -> Button:
	var b := Button.new()
	var sz := min_size
	if sz.y < BTN_MIN_HEIGHT:
		sz.y = BTN_MIN_HEIGHT
	b.custom_minimum_size = sz
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var base := COL_ACCENT if accent else COL_ACCENT2
	b.add_theme_stylebox_override("normal", _flat(base, CORNER, 20.0, 12.0))
	b.add_theme_stylebox_override("hover", _flat(base.lightened(0.10), CORNER, 20.0, 12.0))
	b.add_theme_stylebox_override("pressed", _flat(base.darkened(0.18), CORNER, 20.0, 14.0))
	b.add_theme_stylebox_override(
		"disabled", _flat(Color(0.5, 0.53, 0.6, 0.45), CORNER, 20.0, 12.0)
	)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.95, 1.0))
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.5))
	b.add_theme_font_size_override("font_size", 20)
	return b


static func make_label(text: String, font_size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func make_title(text: String) -> Label:
	var l := make_label(text, 42)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func make_panel(bg: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	if bg.a > 0.0:
		p.add_theme_stylebox_override("panel", _flat(bg, CORNER, 16.0, 14.0))
	return p


static func make_hslider(min_value: float, max_value: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.value = value
	s.step = 0.01
	s.custom_minimum_size = Vector2(320, TOUCH_MIN)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	return s


static func make_option_button(items: Array) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.custom_minimum_size = Vector2(220, TOUCH_MIN + 8.0)
	ob.focus_mode = Control.FOCUS_NONE
	return ob


static func make_check(text: String, is_on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = is_on
	c.custom_minimum_size = Vector2(0, TOUCH_MIN)
	c.focus_mode = Control.FOCUS_NONE
	return c


static func make_separator() -> HSeparator:
	var s := HSeparator.new()
	s.custom_minimum_size = Vector2(0, 18)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


static func make_spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func make_background(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


static func make_toast_layer() -> Control:
	var layer := Control.new()
	layer.name = "ToastLayer"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.anchor_left = 0.5
	stack.anchor_right = 0.5
	stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stack.offset_top = 24.0
	stack.offset_bottom = 24.0
	stack.add_theme_constant_override("separation", 8)
	layer.add_child(stack)
	return layer


static func show_toast(layer: Control, text: String, duration: float = 2.6) -> void:
	if layer == null or not layer.is_inside_tree():
		return
	var stack: Node = layer.get_node_or_null("Stack")
	if stack == null:
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", _flat(Color(0.07, 0.09, 0.14, 0.94), CORNER, 20.0, 12.0)
	)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	stack.add_child(panel)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(panel.queue_free)


static func _flat(
	bg: Color, radius: int = CORNER, margin_h: float = 0.0, margin_v: float = 0.0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb
