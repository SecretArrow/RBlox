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
	var sb := _button_3d(base)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", _button_3d(base.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _button_3d(base.darkened(0.22), true))
	b.add_theme_stylebox_override("disabled", _button_3d(Color(0.45, 0.48, 0.56, 0.5)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.94, 0.96, 1.0))
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.5))
	b.add_theme_font_size_override("font_size", 20)
	attach_press_animation(b)
	return b


## StyleBox tombol chunky ala game: border bawah gelap (3D) + bayangan.
static func _button_3d(base: Color, pressed: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(CORNER)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = (14.0 if not pressed else 17.0)
	sb.content_margin_bottom = (18.0 if not pressed else 12.0)
	sb.border_width_bottom = (0 if pressed else 4)
	sb.border_color = base.darkened(0.35)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


## Animasi tekan: tombol menyusut saat ditekan, memantul saat dilepas.
static func attach_press_animation(b: Button) -> void:
	b.button_down.connect(
		func() -> void:
			b.pivot_offset = b.size * 0.5
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.96, 0.96), 0.05)
	)
	b.button_up.connect(
		func() -> void:
			if not is_instance_valid(b):
				return
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(
				Tween.EASE_OUT
			)
	)


static func make_label(text: String, font_size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func make_title(text: String) -> Label:
	var l := make_label(text, 52)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.16, 0.28, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


## Kartu elevated: panel membulat dengan bayangan lembut (kesan kedalaman).
static func make_card(bg: Color = COL_PANEL_DARK, radius: int = CORNER) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	p.add_theme_stylebox_override("panel", sb)
	return p


## Chip/pil kecil: label dalam kapsul semi-transparan (badge, versi, status).
static func make_chip(text: String, bg: Color = Color(0, 0, 0, 0.45)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	return p


## Latar gradien vertikal (hero menu) — menggantikan ColorRect polos.
static func make_gradient_bg(top: Color, bottom: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([top, bottom])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 64
	gt.height = 64
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Dekorasi menu: blok-blok warna melayang pelan (kesan dunia sandbox).
static func make_decor_blocks() -> Control:
	var layer := Control.new()
	layer.name = "DecorBlocks"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# EN: deterministic layout (posisi, ukuran, warna, rotasi)
	var specs := [
		[0.08, 0.18, 54.0, "#e0453a", 18.0],
		[0.86, 0.14, 40.0, "#ffb300", -22.0],
		[0.16, 0.72, 44.0, "#26c6da", 32.0],
		[0.90, 0.66, 58.0, "#4ad48a", -14.0],
		[0.76, 0.82, 34.0, "#7e57c2", 24.0],
		[0.05, 0.45, 30.0, "#3b7bff", -30.0],
	]
	for s in specs:
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(String(s[3]), 0.30)
		sb.set_corner_radius_all(10)
		box.add_theme_stylebox_override("panel", sb)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.custom_minimum_size = Vector2(float(s[2]), float(s[2]))
		# EN: anchor to fractional position so it fits every aspect ratio
		box.anchor_left = float(s[0])
		box.anchor_top = float(s[1])
		box.anchor_right = float(s[0])
		box.anchor_bottom = float(s[1])
		box.offset_left = 0
		box.offset_top = 0
		box.offset_right = float(s[2])
		box.offset_bottom = float(s[2])
		box.rotation_degrees = float(s[4])
		box.pivot_offset = Vector2(float(s[2]) * 0.5, float(s[2]) * 0.5)
		layer.add_child(box)
		var tw := box.create_tween()
		tw.set_loops()
		(
			tw
			. tween_property(box, "position:y", -14.0, 2.4 + float(s[2]) * 0.01)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
			. as_relative()
		)
		(
			tw
			. tween_property(box, "position:y", 14.0, 2.4 + float(s[2]) * 0.01)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
			. as_relative()
		)
	return layer


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
