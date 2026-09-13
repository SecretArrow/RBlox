extends CanvasLayer
## Tutorial — overlay 6 langkah untuk pemain baru (panel tengah + highlight pseudo).
## Pemakaian (mis. dari game.gd bila Settings.get_value("tutorial_done") == false):
##   var tut := preload("res://scripts/ui/tutorial.gd").new()
##   add_child(tut)
##   tut.start()
## Selesai (atau dilewati) -> Settings.set_value("tutorial_done", true), GameState.first_run = false.

signal finished

const STEPS: Array = [
	{"title": "tut_1_title", "body": "tut_1_body", "hl": "none"},
	{"title": "tut_2_title", "body": "tut_2_body", "hl": "left"},
	{"title": "tut_3_title", "body": "tut_3_body", "hl": "right"},
	{"title": "tut_4_title", "body": "tut_4_body", "hl": "bottom_right"},
	{"title": "tut_5_title", "body": "tut_5_body", "hl": "none"},
	{"title": "tut_6_title", "body": "tut_6_body", "hl": "none"},
]

var _index: int = -1
var _built: bool = false
var _panel: PanelContainer
var _title: Label
var _body: Label
var _next_btn: Button
var _skip_btn: Button
var _hl: Panel


func start() -> void:
	if not _built:
		_build()
	_index = 0
	_show_step()


func _build() -> void:
	_built = true
	layer = 50

	# Dim ringan; input tetap lolos agar pemain bisa langsung mencoba.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Kotak highlight pseudo (outline putih) di posisi kiri/kanan sesuai langkah.
	_hl = Panel.new()
	var hsb := StyleBoxFlat.new()
	hsb.draw_center = false
	hsb.set_corner_radius_all(8)
	hsb.set_border_width_all(2)
	hsb.border_color = Color(1.0, 1.0, 1.0, 0.85)
	_hl.add_theme_stylebox_override("panel", hsb)
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.visible = false
	add_child(_hl)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.15, 0.95)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.2)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.theme = Settings.get_theme()

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 15)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(420.0, 0.0)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_body)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)

	_skip_btn = Button.new()
	_skip_btn.text = _t("common_skip", "Lewati", "Skip")
	_skip_btn.custom_minimum_size = Vector2(110.0, 48.0)
	_skip_btn.pressed.connect(_on_skip)
	hb.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.text = _t("common_next", "Lanjut", "Next")
	_next_btn.custom_minimum_size = Vector2(130.0, 48.0)
	_next_btn.pressed.connect(_on_next)
	hb.add_child(_next_btn)

	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_viewport_size_changed)


func _show_step() -> void:
	if _index < 0 or _index >= STEPS.size():
		_finish()
		return
	var step: Dictionary = STEPS[_index]
	var last := _index >= STEPS.size() - 1
	_title.text = _t(String(step["title"]), _fb_title(), _fb_title_en())
	_body.text = _t(String(step["body"]), _fb_body(), _fb_body_en())
	_next_btn.text = _t("common_ok", "OK", "OK") if last else _t("common_next", "Lanjut", "Next")
	_skip_btn.visible = not last
	_place_highlight(String(step["hl"]))


func _on_next() -> void:
	_index += 1
	if _index >= STEPS.size():
		_finish()
	else:
		_show_step()


func _on_skip() -> void:
	_finish()


func _finish() -> void:
	Settings.set_value("tutorial_done", true)
	GameState.first_run = false
	finished.emit()
	queue_free()


func _place_highlight(side: String) -> void:
	if _hl == null:
		return
	if side == "none":
		_hl.visible = false
		return
	var vs := Vector2(1280.0, 720.0)
	var vp := get_viewport()
	if vp != null:
		vs = vp.get_visible_rect().size
	var rect := Rect2()
	match side:
		"left":
			rect = Rect2(36.0, vs.y * 0.5 - 110.0, 170.0, 220.0)
		"right":
			rect = Rect2(vs.x - 206.0, vs.y * 0.5 - 110.0, 170.0, 220.0)
		"bottom_right":
			rect = Rect2(vs.x - 250.0, vs.y - 270.0, 214.0, 240.0)
		_:
			_hl.visible = false
			return
	_hl.visible = true
	_hl.position = rect.position
	_hl.size = rect.size


func _on_viewport_size_changed() -> void:
	if _index >= 0 and _index < STEPS.size():
		_place_highlight(String(STEPS[_index]["hl"]))


func _t(key: String, fb_id: String, fb_en: String) -> String:
	var s := String(Locale.t(key))
	if s != key:
		return s
	return fb_en if Locale.get_language() == "en" else fb_id


func _fb_title() -> String:
	match _index:
		0:
			return "Selamat Datang di RBlox"
		1:
			return "Bergersi"
		2:
			return "Kamera"
		3:
			return "Lompat & Lari"
		4:
			return "Mode Bangun"
		5:
			return "Simpan Dunia"
	return "RBlox"


func _fb_title_en() -> String:
	match _index:
		0:
			return "Welcome to RBlox"
		1:
			return "Moving Around"
		2:
			return "Camera"
		3:
			return "Jump & Sprint"
		4:
			return "Build Mode"
		5:
			return "Save Your World"
	return "RBlox"


func _fb_body() -> String:
	match _index:
		0:
			return "Jelajahi dunia, bangun apa saja, lalu bagikan ke temanmu. Ikuti panduan singkat ini."
		1:
			return "Gunakan joystick di sisi kiri layar untuk berjalan."
		2:
			return "Sentuh dan seret di sisi kanan layar untuk melihat sekeliling."
		3:
			return "Tombol besar di kanan bawah: lompat, lari, dan aksi."
		4:
			return "Buka mode bangun, pilih blok, lalu tempatkan di dunia."
		5:
			return "Simpan duniamu dari menu jeda agar tidak hilang."
	return ""


func _fb_body_en() -> String:
	match _index:
		0:
			return "Explore the world, build anything, then share it with friends. Quick guide ahead."
		1:
			return "Use the joystick on the left side of the screen to walk."
		2:
			return "Touch and drag on the right side of the screen to look around."
		3:
			return "Big buttons at the bottom right: jump, sprint, and action."
		4:
			return "Open build mode, pick a block, then place it in the world."
		5:
			return "Save your world from the pause menu so it is never lost."
	return ""
