extends Control
## SaveLoadPanel — simpan/muat/hapus/ekspor/impor dunia (.myworld).
## Sumber data: node pertama grup "game" dengan get_world_json() (di-guard).
## Simpan: Saves.save_world + GameState.unlock_achievement("world_saved") +
## label status. Muat: emit load_requested(path) + set GameState.pending_action
## {"mode":"play","world_path":path} — dimuat ulang saat kembali dari menu.
## Impor: scan user://imports. Pemakaian: panel.open(parent_control).

signal save_requested(world_name: String)
signal load_requested(path: String)

const TOAST_PATH := "res://scripts/ui/toast.gd"

var _name_edit: LineEdit
var _status: Label
var _worlds: ItemList
var _imports: ItemList
var _world_paths: Array = []
var _import_paths: Array = []
var _delete_target := ""
var _confirm: ConfirmationDialog


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Settings.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(700, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_title(v, Locale.t("sl_title"), 24)

	# Baris nama + Simpan + label status.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	v.add_child(name_row)
	var nl := Label.new()
	nl.text = Locale.t("sl_name")
	nl.custom_minimum_size = Vector2(90, 48)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Locale.t("sl_name_hint")
	_name_edit.custom_minimum_size = Vector2(0, 48)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	name_row.add_child(_btn(Locale.t("common_save"), _on_save))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6))
	v.add_child(_status)

	# Daftar dunia tersimpan + Muat / Hapus / Ekspor.
	_title(v, Locale.t("sl_worlds"), 16)
	_worlds = ItemList.new()
	_worlds.custom_minimum_size = Vector2(0, 150)
	_worlds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_worlds)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	actions.add_child(_btn(Locale.t("common_load"), _on_load))
	actions.add_child(_btn(Locale.t("common_delete"), _on_delete))
	actions.add_child(_btn(Locale.t("sl_export"), _on_export))

	# Berkas impor dari user://imports.
	_title(v, Locale.t("sl_imports"), 16)
	var hint := Label.new()
	hint.text = Locale.t("sl_import_hint")
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	_imports = ItemList.new()
	_imports.custom_minimum_size = Vector2(0, 90)
	v.add_child(_imports)
	var import_row := HBoxContainer.new()
	import_row.add_theme_constant_override("separation", 8)
	v.add_child(import_row)
	import_row.add_child(_btn(Locale.t("sl_import"), _on_import))
	import_row.add_child(_btn(Locale.t("sl_refresh"), _refresh))
	import_row.add_child(_btn(Locale.t("common_close"), close))

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = Locale.t("sl_confirm_delete")
	_confirm.ok_button_text = Locale.t("common_yes")
	_confirm.cancel_button_text = Locale.t("common_no")
	_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm)


## Tampilkan panel (pindah parent bila perlu) + segarkan daftar.
func open(parent: Control) -> void:
	if parent != null and get_parent() != parent:
		if get_parent() != null:
			get_parent().remove_child(self)
		parent.add_child(self)
	_name_edit.text = ""
	if _status != null:
		_status.text = ""
	_refresh()
	visible = true


func close() -> void:
	visible = false


# --------------------------------------------------------------------- aksi


func _on_save() -> void:
	var world_name := _name_edit.text.strip_edges()
	if world_name == "":
		world_name = Locale.t("sl_default_name")
	var data := _collect_world_data()
	if data.is_empty():
		_toast(Locale.t("sl_no_game"))
		save_requested.emit(world_name)
		return
	if Saves.save_world(world_name, data) == OK:
		GameState.unlock_achievement("world_saved")
		if _status != null:
			_status.text = Locale.t("sl_saved")
		_refresh()
	elif _status != null:
		_status.text = Locale.t("error_generic")


func _on_load() -> void:
	var path := _selected(_worlds, _world_paths)
	if path == "":
		_toast(Locale.t("sl_no_selection"))
		return
	# EN: simplest load path — queue world, applied after restart from menu.
	GameState.pending_action = {"mode": "play", "world_path": path}
	var lang := Locale.get_language()
	_toast(
		(
			"Restart from the main menu to load this world."
			if lang == "en"
			else "Kembali ke menu utama lalu mainkan untuk memuat dunia ini."
		)
	)
	load_requested.emit(path)
	close()


func _on_delete() -> void:
	var path := _selected(_worlds, _world_paths)
	if path == "":
		_toast(Locale.t("sl_no_selection"))
		return
	_delete_target = path
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _delete_target == "":
		return
	if Saves.delete_world(_delete_target) == OK:
		_toast(Locale.t("sl_deleted"))
	else:
		_toast(Locale.t("error_generic"))
	_delete_target = ""
	_refresh()


func _on_export() -> void:
	var path := _selected(_worlds, _world_paths)
	if path == "":
		_toast(Locale.t("sl_no_selection"))
		return
	var dest := Saves.export_world(path)
	_toast(Locale.t("sl_exported", {"path": dest}) if dest != "" else Locale.t("error_generic"))


func _on_import() -> void:
	var path := _selected(_imports, _import_paths)
	if path == "":
		_toast(Locale.t("sl_no_selection"))
		return
	var dest := Saves.import_world(path)
	_toast(Locale.t("sl_imported", {"path": dest}) if dest != "" else Locale.t("error_generic"))
	_refresh()


func _refresh() -> void:
	_worlds.clear()
	_world_paths.clear()
	for w in Saves.list_worlds():
		_worlds.add_item(str(w.get("name", "?")))
		_world_paths.append(str(w.get("path", "")))
	_imports.clear()
	_import_paths.clear()
	for f in DirAccess.get_files_at(Saves.IMPORTS_DIR):
		if String(f).ends_with(Saves.EXT):
			_imports.add_item(String(f))
			_import_paths.append(Saves.IMPORTS_DIR + "/" + String(f))


# ------------------------------------------------------------------ internal


func _collect_world_data() -> Dictionary:
	if get_tree() == null:
		return {}
	var game: Node = get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("get_world_json"):
		var d: Variant = game.call("get_world_json")
		if d is Dictionary and not (d as Dictionary).is_empty():
			return d
	return {}


func _selected(list: ItemList, paths: Array) -> String:
	var sel := list.get_selected_items() if list != null else PackedInt32Array()
	if sel.is_empty() or int(sel[0]) >= paths.size():
		return ""
	return str(paths[int(sel[0])])


func _title(parent: Control, text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(48, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _toast(msg: String) -> void:
	if ResourceLoader.exists(TOAST_PATH):
		var t: Variant = load(TOAST_PATH)
		if t != null and t.has_method("show"):
			t.show(self, msg)
			return
	print("[SaveLoadPanel] ", msg)
