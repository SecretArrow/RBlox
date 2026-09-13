extends RefCounted
## ThemeBuilder — membangun Theme UI lengkap untuk RBlox (mode gelap / terang).
## Dipakai otomatis oleh Settings.get_theme(); tidak perlu dipanggil manual.

const CORNER := 12
const FONT_DEFAULT := 20


static func build(dark: bool) -> Theme:
	var bg := Color("#141824") if dark else Color("#f4f6fb")
	var panel := Color("#1e2433") if dark else Color("#ffffff")
	var text := Color("#eef1f8") if dark else Color("#1a2233")
	var accent := Color("#4f8cff") if dark else Color("#2f6fed")
	var accent2 := Color("#5ad48a") if dark else Color("#2f9e5f")
	var field := Color("#262e40") if dark else Color("#e9edf6")
	var t := Theme.new()
	t.default_font_size = FONT_DEFAULT
	_style_button(t, accent)
	_style_panel(t, panel)
	_style_label(t, text)
	_style_line_edit(t, bg, text, accent)
	_style_option_button(t, field, text)
	_style_check_button(t, field, text, accent)
	_style_slider(t, field, accent2)
	_style_tab_container(t, panel, text, accent)
	_style_scroll_container(t)
	_style_popup_menu(t, panel, text, accent)
	_style_separator(t, text)
	return t


static func _style_button(t: Theme, accent: Color) -> void:
	t.set_stylebox("normal", "Button", _flat(accent, CORNER, 20.0, 12.0))
	t.set_stylebox("hover", "Button", _flat(accent.lightened(0.10), CORNER, 20.0, 12.0))
	t.set_stylebox("pressed", "Button", _flat(accent.darkened(0.18), CORNER, 20.0, 14.0))
	t.set_stylebox("disabled", "Button", _flat(Color(0.5, 0.53, 0.6, 0.45), CORNER, 20.0, 12.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.92, 0.95, 1.0))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1.0, 1.0, 1.0, 0.5))
	t.set_font_size("font_size", "Button", FONT_DEFAULT)


static func _style_panel(t: Theme, panel: Color) -> void:
	t.set_stylebox("panel", "Panel", _flat(panel, CORNER, 0.0, 0.0))
	t.set_stylebox("panel", "PanelContainer", _flat(panel, CORNER, 16.0, 14.0))


static func _style_label(t: Theme, text: Color) -> void:
	t.set_color("font_color", "Label", text)


static func _style_line_edit(t: Theme, bg: Color, text: Color, accent: Color) -> void:
	t.set_stylebox("normal", "LineEdit", _flat(bg, 10, 14.0, 12.0))
	var sb_focus := _flat(bg, 10, 14.0, 12.0)
	sb_focus.set_border_width_all(2)
	sb_focus.border_color = accent
	t.set_stylebox("focus", "LineEdit", sb_focus)
	t.set_stylebox("read_only", "LineEdit", _flat(bg.darkened(0.04), 10, 14.0, 12.0))
	t.set_color("font_color", "LineEdit", text)
	t.set_color("font_placeholder_color", "LineEdit", Color(text.r, text.g, text.b, 0.45))
	t.set_color("caret_color", "LineEdit", accent)
	t.set_color("selection_color", "LineEdit", Color(accent.r, accent.g, accent.b, 0.35))
	t.set_font_size("font_size", "LineEdit", FONT_DEFAULT)


static func _style_option_button(t: Theme, field: Color, text: Color) -> void:
	t.set_stylebox("normal", "OptionButton", _flat(field, CORNER, 18.0, 12.0))
	t.set_stylebox("hover", "OptionButton", _flat(field.lightened(0.08), CORNER, 18.0, 12.0))
	t.set_stylebox("pressed", "OptionButton", _flat(field.darkened(0.10), CORNER, 18.0, 14.0))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_stylebox(
		"disabled", "OptionButton", _flat(Color(0.5, 0.53, 0.6, 0.35), CORNER, 18.0, 12.0)
	)
	t.set_color("font_color", "OptionButton", text)
	t.set_color("font_hover_color", "OptionButton", text)
	t.set_color("font_pressed_color", "OptionButton", text)
	t.set_color("font_focus_color", "OptionButton", text)
	t.set_color("font_disabled_color", "OptionButton", Color(text.r, text.g, text.b, 0.45))
	t.set_font_size("font_size", "OptionButton", FONT_DEFAULT)


static func _style_check_button(t: Theme, field: Color, text: Color, accent: Color) -> void:
	t.set_color("font_color", "CheckButton", text)
	t.set_color("font_hover_color", "CheckButton", text)
	t.set_color("font_pressed_color", "CheckButton", text)
	t.set_color("font_focus_color", "CheckButton", text)
	t.set_color("font_disabled_color", "CheckButton", Color(text.r, text.g, text.b, 0.45))
	t.set_font_size("font_size", "CheckButton", FONT_DEFAULT)
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _toggle_icon(true, accent, Color.WHITE))
	t.set_icon(
		"unchecked", "CheckButton", _toggle_icon(false, field, Color(text.r, text.g, text.b, 0.75))
	)
	t.set_icon(
		"checked_disabled",
		"CheckButton",
		_toggle_icon(true, Color(0.5, 0.53, 0.6, 0.5), Color(1.0, 1.0, 1.0, 0.6))
	)
	t.set_icon(
		"unchecked_disabled",
		"CheckButton",
		_toggle_icon(false, Color(0.5, 0.53, 0.6, 0.4), Color(1.0, 1.0, 1.0, 0.5))
	)


static func _style_slider(t: Theme, field: Color, fill: Color) -> void:
	t.set_stylebox("slider", "Slider", _strip(_flat(field, 6, 0.0, 0.0), 6.0))
	t.set_stylebox("grabber_area", "Slider", _strip(_flat(fill, 6, 0.0, 0.0), 6.0))
	t.set_stylebox(
		"grabber_area_highlight", "Slider", _strip(_flat(fill.lightened(0.15), 6, 0.0, 0.0), 6.0)
	)
	t.set_icon("grabber", "Slider", _circle_icon(40, Color.WHITE, Color(0.2, 0.25, 0.35, 0.6)))
	t.set_icon(
		"grabber_highlight", "Slider", _circle_icon(44, Color.WHITE, Color(0.2, 0.25, 0.35, 0.6))
	)
	t.set_icon("grabber_disabled", "Slider", _circle_icon(40, Color(1.0, 1.0, 1.0, 0.5)))
	t.set_stylebox("focus", "Slider", StyleBoxEmpty.new())


static func _style_tab_container(t: Theme, panel: Color, text: Color, accent: Color) -> void:
	t.set_stylebox("panel", "TabContainer", _flat(panel, CORNER, 12.0, 12.0))
	var sb_sel := _flat(panel.lightened(0.06), 8, 16.0, 10.0)
	sb_sel.corner_radius_bottom_left = 0
	sb_sel.corner_radius_bottom_right = 0
	sb_sel.border_width_top = 3
	sb_sel.border_color = accent
	t.set_stylebox("tab_selected", "TabContainer", sb_sel)
	var sb_un := _flat(panel.darkened(0.06), 8, 16.0, 10.0)
	sb_un.corner_radius_bottom_left = 0
	sb_un.corner_radius_bottom_right = 0
	t.set_stylebox("tab_unselected", "TabContainer", sb_un)
	t.set_color("font_selected_color", "TabContainer", text)
	t.set_color("font_unselected_color", "TabContainer", Color(text.r, text.g, text.b, 0.6))
	t.set_font_size("font_size", "TabContainer", FONT_DEFAULT)


static func _style_scroll_container(t: Theme) -> void:
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())


static func _style_popup_menu(t: Theme, panel: Color, text: Color, accent: Color) -> void:
	t.set_stylebox("panel", "PopupMenu", _flat(panel.lightened(0.04), 10, 6.0, 6.0))
	t.set_stylebox("hover", "PopupMenu", _flat(accent, 8, 8.0, 6.0))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Color(text.r, text.g, text.b, 0.4))
	t.set_color("font_accelerator_color", "PopupMenu", Color(text.r, text.g, text.b, 0.55))
	t.set_font_size("font_size", "PopupMenu", FONT_DEFAULT)
	t.set_stylebox(
		"separator", "PopupMenu", _flat(Color(text.r, text.g, text.b, 0.15), 0, 0.0, 1.0)
	)


static func _style_separator(t: Theme, text: Color) -> void:
	var line := _flat(Color(text.r, text.g, text.b, 0.18), 0, 0.0, 1.0)
	t.set_stylebox("separator", "HSeparator", line)
	t.set_stylebox("separator", "VSeparator", line)


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


static func _strip(sb: StyleBoxFlat, thickness: float) -> StyleBoxFlat:
	sb.content_margin_top = thickness
	sb.content_margin_bottom = thickness
	return sb


static func _toggle_icon(is_on: bool, track: Color, knob: Color) -> ImageTexture:
	var w := 88
	var h := 48
	var r := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if _in_rounded_rect(float(x) + 0.5, float(y) + 0.5, float(w), float(h), float(r)):
				img.set_pixel(x, y, track)
	var kx := float(w - r) if is_on else float(r)
	var cy := float(h) * 0.5
	for y in h:
		for x in w:
			if Vector2(float(x) + 0.5 - kx, float(y) + 0.5 - cy).length() <= 18.0:
				img.set_pixel(x, y, knob)
	return ImageTexture.create_from_image(img)


static func _circle_icon(
	diameter: int, color: Color, outline: Color = Color(0, 0, 0, 0)
) -> ImageTexture:
	var img := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := float(diameter) * 0.5
	var rad := c - 1.0
	for y in diameter:
		for x in diameter:
			var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
			if d <= rad:
				var col := color
				if outline.a > 0.0 and d >= rad - 2.0:
					col = outline
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _in_rounded_rect(px: float, py: float, w: float, h: float, r: float) -> bool:
	var cx := clampf(px, r, w - r)
	var cy := clampf(py, r, h - r)
	return Vector2(px - cx, py - cy).length() <= r
