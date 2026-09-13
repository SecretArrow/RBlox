extends Control
## Lobby multiplayer LAN: buat room (host), cari & gabung room (client),
## pilih dunia, dan mulai game. Semua akses multiplayer lewat facade Net;
## implementasi ada di scripts/multiplayer/lan_backend.gd.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TEMPLATES_PATH := "res://scripts/world/templates.gd"
const TRANSPORT_LAN := 0
const BTN_MIN_HEIGHT := 48.0
const NAME_MAX_CHARS := 24

var _transport: OptionButton
var _name_edit: LineEdit
var _host_btn: Button
var _host_section: VBoxContainer
var _host_ip_label: Label
var _players_box: VBoxContainer
var _world_option: OptionButton
var _world_sources: Array = []
var _start_btn: Button
var _rooms_list: ItemList
var _rooms: Array = []
var _ip_edit: LineEdit
var _scan_btn: Button
var _join_btn: Button
var _leave_btn: Button
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _scanning: bool = false
var _tpl_cache: Variant = null


func _ready() -> void:
	theme = Settings.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_worlds()
	_update_host_section()
	Net.player_list_changed.connect(_on_players_changed)
	Net.room_state_changed.connect(_on_room_state)
	Net.game_started.connect(_on_game_started)
	Net.kicked.connect(_on_kicked)
	Net.connection_failed.connect(_on_connection_failed)
	Net.connection_lost.connect(_on_connection_lost)


# ------------------------------------------------------------------- UI


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	header.add_child(_mk_label(Locale.t("lobby_title"), 26))
	var hspacer := Control.new()
	hspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hspacer)
	header.add_child(_mk_label(Locale.t("mp_transport"), 15))
	_transport = OptionButton.new()
	_transport.add_item(Locale.t("mp_transport_lan"), 0)
	_transport.add_item(Locale.t("mp_transport_bt"), 1)
	_transport.add_item(Locale.t("mp_transport_wfd"), 2)
	_transport.selected = 0
	_transport.custom_minimum_size = Vector2(230, BTN_MIN_HEIGHT)
	_transport.item_selected.connect(_on_transport_selected)
	header.add_child(_transport)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	body.add_child(_build_host_panel())
	body.add_child(VSeparator.new())
	body.add_child(_build_join_panel())

	var footer := HBoxContainer.new()
	root.add_child(footer)
	var fspacer := Control.new()
	fspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fspacer)
	_leave_btn = _mk_button(Locale.t("mp_leave"))
	_leave_btn.pressed.connect(_on_leave_pressed)
	footer.add_child(_leave_btn)

	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.z_index = 50
	_toast_label = _mk_label("", 15)
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)
	_toast_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24
	)


func _build_host_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)

	panel.add_child(_mk_label(Locale.t("lobby_host"), 20))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	panel.add_child(name_row)
	name_row.add_child(_mk_label(Locale.t("mp_name"), 16))
	_name_edit = LineEdit.new()
	_name_edit.text = GameState.player_name
	_name_edit.max_length = NAME_MAX_CHARS
	_name_edit.custom_minimum_size = Vector2(220, BTN_MIN_HEIGHT)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)

	_host_btn = _mk_button(Locale.t("lobby_host"))
	_host_btn.pressed.connect(_on_host_pressed)
	panel.add_child(_host_btn)

	_host_section = VBoxContainer.new()
	_host_section.visible = false
	_host_section.add_theme_constant_override("separation", 8)
	panel.add_child(_host_section)

	_host_section.add_child(_mk_label(Locale.t("lobby_your_ip"), 16))
	_host_ip_label = _mk_label("-", 14)
	_host_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_section.add_child(_host_ip_label)

	_host_section.add_child(_mk_label(Locale.t("lobby_players"), 16))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	_host_section.add_child(scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_players_box)

	_host_section.add_child(_mk_label(Locale.t("mp_world"), 16))
	_world_option = OptionButton.new()
	_world_option.custom_minimum_size = Vector2(0, BTN_MIN_HEIGHT)
	_host_section.add_child(_world_option)

	_start_btn = _mk_button(Locale.t("lobby_start"))
	_start_btn.pressed.connect(_on_start_pressed)
	_host_section.add_child(_start_btn)
	return panel


func _build_join_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)

	panel.add_child(_mk_label(Locale.t("lobby_join"), 20))

	_scan_btn = _mk_button(Locale.t("lobby_scan"))
	_scan_btn.pressed.connect(_on_scan_pressed)
	panel.add_child(_scan_btn)

	_rooms_list = ItemList.new()
	_rooms_list.custom_minimum_size = Vector2(0, 210)
	_rooms_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms_list.item_selected.connect(_on_room_selected)
	panel.add_child(_rooms_list)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = Locale.t("lobby_enter_ip")
	_ip_edit.custom_minimum_size = Vector2(0, BTN_MIN_HEIGHT)
	panel.add_child(_ip_edit)

	_join_btn = _mk_button(Locale.t("lobby_join"))
	_join_btn.pressed.connect(_on_join_pressed)
	panel.add_child(_join_btn)
	return panel


func _mk_label(text: String, font_size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BTN_MIN_HEIGHT)
	return b


func _toast(text: String) -> void:
	if _toast_panel == null:
		return
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.8)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_hide_toast)


func _hide_toast() -> void:
	if _toast_panel != null:
		_toast_panel.visible = false


# ------------------------------------------------------------- handlers


func _on_transport_selected(index: int) -> void:
	if index != TRANSPORT_LAN:
		_toast(Locale.t("error_not_impl"))
		_transport.select(TRANSPORT_LAN)
		return
	if Net.set_transport(TRANSPORT_LAN) != OK:
		_toast(Locale.t("error_not_impl"))
		_transport.select(TRANSPORT_LAN)


func _save_name() -> bool:
	var n := _name_edit.text.strip_edges()
	if n == "":
		_toast(Locale.t("mp_name_empty"))
		return false
	if n.length() > NAME_MAX_CHARS:
		n = n.substr(0, NAME_MAX_CHARS)
	GameState.player_name = n
	Settings.set_value("player_name", n)
	return true


func _on_host_pressed() -> void:
	if not _save_name():
		return
	var err: Error = Net.host_room(16)
	if err != OK:
		_toast(Locale.t("error_generic"))
		return
	_toast(Locale.t("toast_hosted"))
	_update_host_section()
	_refresh_players(Net.players())


func _on_start_pressed() -> void:
	if not (Net.is_active() and Net.is_host()):
		return
	var idx := _world_option.selected
	if idx < 0 or idx >= _world_sources.size():
		_toast(Locale.t("mp_select_world"))
		return
	var src: Dictionary = _world_sources[idx]
	var world := {}
	var kind := String(src.get("kind", ""))
	if kind == "empty":
		world = _empty_world_json()
	elif kind == "file":
		world = Saves.load_world(String(src.get("path", "")))
	elif kind == "template":
		if _tpl_cache != null and _tpl_cache.has_method("build_world_json"):
			var built: Variant = _tpl_cache.build_world_json(String(src.get("tid", "")))
			if typeof(built) == TYPE_DICTIONARY:
				world = built
	if world.is_empty():
		_toast(Locale.t("error_generic"))
		return
	Net.start_game(world)
	GameState.current_world = world
	GameState.goto_scene(GAME_SCENE)


func _on_scan_pressed() -> void:
	if _scanning:
		return
	_scanning = true
	_scan_btn.disabled = true
	_scan_btn.text = Locale.t("common_loading")
	_rooms_list.clear()
	_rooms.clear()
	await get_tree().process_frame
	var rooms: Array = Net.list_lan_rooms(1.5)
	_scan_btn.text = Locale.t("lobby_scan")
	_scan_btn.disabled = false
	_scanning = false
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var entry := {
			"name": String(r.get("name", "?")),
			"ip": String(r.get("ip", "")),
			"players": int(r.get("players", 1)),
			"max": int(r.get("max", 16)),
		}
		_rooms.append(entry)
		_rooms_list.add_item(
			"%s  |  %s  |  %d/%d" % [entry["name"], entry["ip"], entry["players"], entry["max"]]
		)
	if _rooms.is_empty():
		_toast(Locale.t("mp_no_rooms"))
	elif _rooms.size() == 1:
		_rooms_list.select(0)
		_on_room_selected(0)


func _on_room_selected(index: int) -> void:
	if index >= 0 and index < _rooms.size():
		_ip_edit.text = String(_rooms[index]["ip"])


func _on_join_pressed() -> void:
	if not _save_name():
		return
	var ip := _ip_edit.text.strip_edges()
	if ip == "" and _rooms_list.is_anything_selected():
		var sel := _rooms_list.get_selected_items()
		if sel.size() > 0 and int(sel[0]) < _rooms.size():
			ip = String(_rooms[int(sel[0])]["ip"])
	if ip == "":
		_toast(Locale.t("lobby_enter_ip"))
		return
	var err: Error = Net.join_room(ip)
	if err != OK:
		_toast(Locale.t("error_generic"))
		return
	_toast(Locale.t("mp_joining"))


func _on_leave_pressed() -> void:
	Net.leave()
	_toast(Locale.t("toast_left"))
	GameState.goto_scene(MENU_SCENE)


func _on_kick_pressed(peer_id: int) -> void:
	Net.kick(peer_id)


# ------------------------------------------------------- sinyal dari Net


func _on_players_changed(list: Array) -> void:
	_refresh_players(list)


func _on_room_state() -> void:
	_update_host_section()
	if Net.is_active():
		if Net.is_host():
			GameState.unlock_achievement("host_mp")
		else:
			GameState.unlock_achievement("join_mp")
			_toast(Locale.t("toast_joined"))


func _on_game_started(world_data: Dictionary) -> void:
	if Net.is_host():
		return
	if world_data.is_empty():
		return
	GameState.current_world = world_data
	GameState.goto_scene(GAME_SCENE)


func _on_kicked(reason: String) -> void:
	_toast(String(reason))
	Net.leave()
	GameState.goto_scene(MENU_SCENE)


func _on_connection_failed(reason: String) -> void:
	_toast(String(reason))
	GameState.goto_scene(MENU_SCENE)


func _on_connection_lost() -> void:
	_toast(Locale.t("connection_lost_msg"))
	GameState.goto_scene(MENU_SCENE)


# ------------------------------------------------------------- internal


func _update_host_section() -> void:
	var hosting := Net.is_active() and Net.is_host()
	if _host_section != null:
		_host_section.visible = hosting
	if _host_btn != null:
		_host_btn.disabled = Net.is_active()
	if hosting:
		_host_ip_label.text = _local_ip_text()


func _local_ip_text() -> String:
	var lines: Array[String] = []
	for addr in IP.get_local_addresses():
		var s := String(addr)
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			lines.append(s)
	if lines.is_empty():
		return "-"
	return "\n".join(lines)


func _refresh_players(list: Array) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	var my := Net.my_id()
	for p in list:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s   (%d ms)" % [String(p.get("name", "?")), int(p.get("ping", 0))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var pid := int(p.get("id", 0))
		if Net.is_host() and pid != my:
			var kbtn := _mk_button(Locale.t("lobby_kick"))
			kbtn.custom_minimum_size = Vector2(120, BTN_MIN_HEIGHT)
			kbtn.pressed.connect(_on_kick_pressed.bind(pid))
			row.add_child(kbtn)
		_players_box.add_child(row)


func _refresh_worlds() -> void:
	_world_sources.clear()
	_world_option.clear()
	_world_sources.append({"kind": "empty"})
	_world_option.add_item(Locale.t("mp_world_empty"), 0)
	for w in Saves.list_worlds():
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var idx := _world_option.item_count
		_world_sources.append({"kind": "file", "path": String(w.get("path", ""))})
		_world_option.add_item(String(w.get("name", "?")), idx)
	if ResourceLoader.exists(TEMPLATES_PATH):
		var tpl: Variant = load(TEMPLATES_PATH)
		if tpl != null and tpl.has_method("catalog") and tpl.has_method("build_world_json"):
			_tpl_cache = tpl
			for entry in tpl.catalog():
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var tidx := _world_option.item_count
				_world_sources.append({"kind": "template", "tid": String(entry.get("id", ""))})
				_world_option.add_item(
					"%s: %s" % [Locale.t("ws_templates"), String(entry.get("name", "?"))], tidx
				)


func _empty_world_json() -> Dictionary:
	return {
		"format": "rblox-world",
		"version": 1,
		"meta": {"name": "MP Empty", "is_template": false},
		"settings":
		{
			"game_mode": "sandbox",
			"day_night": true,
			"cycle_minutes": 10.0,
			"weather": "clear",
			"health_enabled": true,
			"gravity": 12.0,
			"build_allowed": true,
		},
		"spawn_points": [[0, 2, 0]],
		"blocks": [],
		"props": [],
		"terrain": {"size": 64, "seed": 1, "heights": [], "paint": []},
	}
