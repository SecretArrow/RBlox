extends Control
## SettingsMenu — overlay panel pengaturan: bahasa, tema, audio, kualitas grafis,
## kontrol orang tua, sensitivitas kamera, tutorial, dan dialog Tentang.
## Pemakaian: var sm = load("res://scripts/ui/settings_menu.gd").new(); sm.open(parent_control)

signal closed

const UiKit := preload("res://scripts/ui/ui_kit.gd")

const LANG_CODES := ["id", "en"]
const QUALITY_CODES := ["low", "medium", "high"]

var _info_label: Label
var _info_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	Locale.language_changed.connect(_on_language_changed)
	Settings.theme_changed.connect(_on_theme_changed)


func open(parent: Control) -> void:
	if parent == null:
		return
	if get_parent() == null:
		parent.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _close() -> void:
	closed.emit()
	queue_free()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	# Header + tombol tutup (EN: Close)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var title := UiKit.make_title(Locale.t("settings_title"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := UiKit.make_button(Locale.t("common_close"), Vector2(150, 56), false)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)
	content.add_child(UiKit.make_separator())

	# Bahasa (EN: Language)
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 16)
	content.add_child(lang_row)
	lang_row.add_child(UiKit.make_label(Locale.t("settings_language"), 20))
	var lang_ob := UiKit.make_option_button(["Indonesia", "English"])
	var lang_idx := LANG_CODES.find(String(Settings.get_value("language", "id")))
	lang_ob.select(maxi(lang_idx, 0))
	lang_ob.item_selected.connect(_on_language_selected)
	lang_row.add_child(lang_ob)

	# Mode Gelap (EN: Dark Mode)
	var dark_cb := UiKit.make_check(Locale.t("settings_dark"), Settings.is_dark_mode())
	dark_cb.toggled.connect(_on_dark_toggled)
	content.add_child(dark_cb)

	# Audio (EN: Audio)
	content.add_child(UiKit.make_label(Locale.t("settings_audio"), 24))
	_add_volume_row(content, Locale.t("settings_master"), "master_volume")  # EN: Master Volume
	_add_volume_row(content, Locale.t("settings_music"), "music_volume")  # EN: Music Volume
	_add_volume_row(content, Locale.t("settings_sfx"), "sfx_volume")  # EN: SFX Volume

	# Kualitas Grafis (EN: Graphics Quality)
	content.add_child(UiKit.make_label(Locale.t("settings_graphics"), 20))
	var q_ob := (
		UiKit
		. make_option_button(
			[
				Locale.t("settings_quality_low"),  # EN: Low
				Locale.t("settings_quality_medium"),  # EN: Medium
				Locale.t("settings_quality_high"),  # EN: High
			]
		)
	)
	var q_idx := QUALITY_CODES.find(String(Settings.get_value("graphics_quality", "medium")))
	q_ob.select(maxi(q_idx, 0))
	q_ob.item_selected.connect(_on_quality_selected)
	content.add_child(q_ob)

	content.add_child(UiKit.make_separator())

	# Kontrol Orang Tua (EN: Parental Controls)
	content.add_child(UiKit.make_label(Locale.t("settings_parental"), 24))
	var chat_cb := UiKit.make_check(Locale.t("settings_chat_enable"), Settings.chat_enabled())  # EN: Allow Text Chat
	chat_cb.toggled.connect(_on_chat_toggled)
	content.add_child(chat_cb)

	# Sensitivitas Kamera (EN: Camera Sensitivity)
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 16)
	content.add_child(sens_row)
	sens_row.add_child(UiKit.make_label(Locale.t("settings_sensitivity"), 18))
	var sens_val := UiKit.make_label(
		"%.2fx" % float(Settings.get_value("camera_sensitivity", 1.0)), 18
	)
	sens_val.custom_minimum_size = Vector2(72, 0)
	sens_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sens_row.add_child(sens_val)
	var sens := UiKit.make_hslider(0.3, 2.0, float(Settings.get_value("camera_sensitivity", 1.0)))
	sens.step = 0.05
	sens.value_changed.connect(_on_sensitivity_changed.bind(sens_val))
	sens_row.add_child(sens)

	content.add_child(UiKit.make_separator())

	# Ulangi Tutorial (EN: Replay Tutorial)
	var tut_btn := UiKit.make_button(Locale.t("settings_tutorial"), Vector2(340, 56), false)
	tut_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tut_btn.pressed.connect(_on_reset_tutorial)
	content.add_child(tut_btn)

	# Tentang RBlox (EN: About RBlox)
	var about_btn := UiKit.make_button(Locale.t("settings_credits"), Vector2(340, 56), false)
	about_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	about_btn.pressed.connect(_on_about)
	content.add_child(about_btn)

	_info_label = UiKit.make_label("", 16)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_info_label)


func _on_language_selected(idx: int) -> void:
	if idx >= 0 and idx < LANG_CODES.size():
		Locale.set_language(String(LANG_CODES[idx]))


func _on_dark_toggled(is_on: bool) -> void:
	Settings.set_dark_mode(is_on)


func _on_quality_selected(idx: int) -> void:
	if idx >= 0 and idx < QUALITY_CODES.size():
		Settings.set_value("graphics_quality", String(QUALITY_CODES[idx]))


func _on_chat_toggled(is_on: bool) -> void:
	Settings.set_value("chat_enabled", is_on)


func _on_sensitivity_changed(value: float, value_label: Label) -> void:
	Settings.set_value("camera_sensitivity", value)
	if value_label != null and is_instance_valid(value_label):
		value_label.text = "%.2fx" % value


func _add_volume_row(parent: Control, label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var lbl := UiKit.make_label(label_text, 18)
	lbl.custom_minimum_size = Vector2(240, 0)
	row.add_child(lbl)
	var val := UiKit.make_label(_percent(float(Settings.get_value(key, 0.8))), 18)
	val.custom_minimum_size = Vector2(64, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	var slider := UiKit.make_hslider(0.0, 1.0, float(Settings.get_value(key, 0.8)))
	slider.value_changed.connect(_on_volume_changed.bind(key, _bus_for_key(key), val))
	row.add_child(slider)


func _on_volume_changed(value: float, key: String, bus_name: String, value_label: Label) -> void:
	Settings.set_value(key, value)
	if value_label != null and is_instance_valid(value_label):
		value_label.text = _percent(value)
	_apply_bus(bus_name, value)


func _bus_for_key(key: String) -> String:
	if key == "music_volume":
		return "Music"
	if key == "sfx_volume":
		return "SFX"
	return "Master"


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	if linear > 0.001:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _percent(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


func _on_reset_tutorial() -> void:
	Settings.set_value("tutorial_done", false)
	_show_info(Locale.t("tutorial_reset_done"))  # EN: Tutorial will be shown again the next time you play.


func _show_info(text: String) -> void:
	if _info_label == null or not is_instance_valid(_info_label):
		return
	if _info_tween != null and _info_tween.is_valid():
		_info_tween.kill()
	_info_label.text = text
	_info_label.modulate.a = 1.0
	_info_tween = _info_label.create_tween()
	_info_tween.tween_interval(2.6)
	_info_tween.tween_property(_info_label, "modulate:a", 0.0, 0.5)


func _on_about() -> void:
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var dlg := AcceptDialog.new()
	dlg.title = Locale.t("settings_credits")
	# EN: "RBlox v{version}\nMade with Godot Engine.\n100% free, no ads."
	dlg.dialog_text = Locale.t("settings_about_text", {"version": ver})
	dlg.ok_button_text = Locale.t("common_ok")
	dlg.min_size = Vector2i(460, 240)
	add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_language_changed() -> void:
	_rebuild()


func _on_theme_changed() -> void:
	_rebuild()


func _rebuild() -> void:
	if is_inside_tree():
		_build()
