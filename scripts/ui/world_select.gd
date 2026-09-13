extends Control
## World Select — pilih template (10 kartu) atau dunia tersimpan,
## impor dunia (.myworld) via FileDialog / folder user://imports.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TEMPLATES_PATH := "res://scripts/world/templates.gd"

var _tpl: GDScript = null
var _list_box: VBoxContainer = null
var _import_box: VBoxContainer = null
var _confirm: ConfirmationDialog = null
var _file_dialog: FileDialog = null
var _pending_delete := ""


func _ready() -> void:
	theme = Settings.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(TEMPLATES_PATH):
		var r: Variant = load(TEMPLATES_PATH)
		if r is GDScript:
			_tpl = r
	_build_ui()
	_refresh_worlds()


# ------------------------------------------------------------------ UI dasar

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	# Header: tombol kembali + judul
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	var back := Button.new()
	back.text = Locale.t("common_back")
	back.custom_minimum_size = Vector2(120, 52)
	back.pressed.connect(_go_back)
	head.add_child(back)
	var title := Label.new()
	title.text = Locale.t("ws_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	head.add_child(title)
	# Tab: Template & Dunia Saya
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_make_templates_tab())
	tabs.add_child(_make_worlds_tab())


func _make_templates_tab() -> Control:
	var tab := ScrollContainer.new()
	tab.name = Locale.t("ws_templates")
	tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(grid)
	if _tpl == null:
		grid.add_child(_make_info_label(Locale.t("error_generic")))
		return tab
	var catalog: Array = _tpl.call("catalog")
	if catalog.is_empty():
		grid.add_child(_make_info_label(Locale.t("error_generic")))
		return tab
	for entry in catalog:
		if entry is Dictionary:
			grid.add_child(_make_template_card(entry))
	return tab


func _make_template_card(entry: Dictionary) -> Control:
	var id := String(entry.get("id", "empty"))
	var col := Color(String(entry.get("color", "#607d8b")))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 156)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	btn.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = col.lightened(0.18)
	btn.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = col.darkened(0.25)
	btn.add_theme_stylebox_override("pressed", sbp)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_play_template.bind(id))
	# Label nama & deskripsi di dalam kartu (abaikan mouse agar klik tembus)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 6)
	btn.add_child(vb)
	var nm := Label.new()
	nm.text = Locale.t(String(entry.get("name_key", id)))
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var desc := Label.new()
	desc.text = Locale.t(String(entry.get("desc_key", id)))
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(desc)
	return btn


func _make_worlds_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Locale.t("ws_my_worlds")
	tab.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)
	# Baris impor: tombol FileDialog + keterangan
	var imp_row := HBoxContainer.new()
	imp_row.add_theme_constant_override("separation", 12)
	tab.add_child(imp_row)
	var imp_btn := Button.new()
	imp_btn.text = Locale.t("ws_import")
	imp_btn.custom_minimum_size = Vector2(150, 52)
	imp_btn.pressed.connect(_open_import_dialog)
	imp_row.add_child(imp_btn)
	var hint := Label.new()
	hint.text = Locale.t("ws_import_hint")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	imp_row.add_child(hint)
	# Daftar file di user://imports (fallback impor)
	_import_box = VBoxContainer.new()
	_import_box.add_theme_constant_override("separation", 8)
	tab.add_child(_import_box)
	return tab


# ------------------------------------------------------------------ dunia saya

func _refresh_worlds() -> void:
	_clear_children(_list_box)
	_clear_children(_import_box)
	var worlds: Array = Saves.list_worlds()
	if worlds.is_empty():
		_list_box.add_child(_make_info_label(Locale.t("ws_empty")))
	for w in worlds:
		if w is Dictionary:
			_list_box.add_child(_make_world_row(w))
	# Fallback impor: daftar berkas di user://imports
	var files := DirAccess.get_files_at(Saves.IMPORTS_DIR)
	for f in files:
		var fname := String(f)
		if not fname.ends_with(Saves.EXT):
			continue
		_import_box.add_child(_make_import_row(fname))


func _make_world_row(w: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var nm := Label.new()
	nm.text = String(w.get("name", "?"))
	nm.add_theme_font_size_override("font_size", 18)
	info.add_child(nm)
	var dt := Label.new()
	dt.text = _fmt_time(int(w.get("modified", 0)))
	dt.add_theme_font_size_override("font_size", 12)
	dt.modulate = Color(1, 1, 1, 0.6)
	info.add_child(dt)
	hb.add_child(info)
	var play := Button.new()
	play.text = Locale.t("common_play")
	play.custom_minimum_size = Vector2(110, 52)
	play.pressed.connect(_play_world.bind(String(w.get("path", ""))))
	hb.add_child(play)
	var del := Button.new()
	del.text = Locale.t("common_delete")
	del.custom_minimum_size = Vector2(110, 52)
	del.pressed.connect(_ask_delete.bind(String(w.get("path", ""))))
	hb.add_child(del)
	return panel


func _make_import_row(fname: String) -> Control:
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	var nm := Label.new()
	nm.text = fname.trim_suffix(Saves.EXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 15)
	hb.add_child(nm)
	var play := Button.new()
	play.text = Locale.t("common_play")
	play.custom_minimum_size = Vector2(110, 52)
	play.pressed.connect(_play_import.bind(Saves.IMPORTS_DIR + "/" + fname))
	hb.add_child(play)
	return panel


func _fmt_time(unix: int) -> String:
	if unix <= 0:
		return ""
	return Time.get_datetime_string_from_unix_time(unix).replace("T", " ")


# ------------------------------------------------------------------ aksi

func _play_template(id: String) -> void:
	GameState.pending_action = {"mode": "play", "world_id": id}
	GameState.goto_scene(GAME_SCENE)


func _play_world(path: String) -> void:
	GameState.pending_action = {"mode": "play", "world_path": path}
	GameState.goto_scene(GAME_SCENE)


func _play_import(src_path: String) -> void:
	var imported := Saves.import_world(src_path)
	if imported != "":
		_play_world(imported)


func _ask_delete(path: String) -> void:
	_pending_delete = path
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.ok_button_text = Locale.t("common_yes")
		_confirm.cancel_button_text = Locale.t("common_no")
		_confirm.confirmed.connect(_do_delete)
		add_child(_confirm)
	_confirm.dialog_text = Locale.t("ws_confirm_delete")
	_confirm.popup_centered()


func _do_delete() -> void:
	if _pending_delete != "":
		Saves.delete_world(_pending_delete)
		_pending_delete = ""
		_refresh_worlds()


func _open_import_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.filters = PackedStringArray(["*.myworld ; RBlox World"])
		_file_dialog.file_selected.connect(_on_import_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(900, 560))


func _on_import_selected(path: String) -> void:
	Saves.import_world(path)
	_refresh_worlds()


func _go_back() -> void:
	GameState.goto_scene(MENU_SCENE)


# ------------------------------------------------------------------ util

func _make_info_label(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _clear_children(box: VBoxContainer) -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.free()
