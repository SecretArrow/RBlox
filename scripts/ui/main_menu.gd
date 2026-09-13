extends Control
## MainMenu — layar utama RBlox: judul, tagline, nama pemain + versi,
## navigasi besar (touch friendly), panel pengaturan, dan toast achievement.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

const SCENE_WORLD_SELECT := "res://scenes/world_select.tscn"
const SCENE_GAME := "res://scenes/game.tscn"
const SCENE_AVATAR := "res://scenes/avatar_editor.tscn"
const SCENE_LOBBY := "res://scenes/lobby.tscn"
const SETTINGS_SCRIPT := "res://scripts/ui/settings_menu.gd"

var _bg: ColorRect
var _ui_root: Control
var _toast_layer: Control


func _ready() -> void:
	theme = Settings.get_theme()
	_bg = UiKit.make_background(_bg_color())
	add_child(_bg)
	_ui_root = Control.new()
	_ui_root.name = "UiRoot"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ui_root)
	_toast_layer = UiKit.make_toast_layer()
	add_child(_toast_layer)
	_build_ui()
	_apply_audio_settings()
	Settings.theme_changed.connect(_on_theme_changed)
	Locale.language_changed.connect(_on_language_changed)
	GameState.achievement_unlocked.connect(_on_achievement)


func _build_ui() -> void:
	for c in _ui_root.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(UiKit.make_title(Locale.t("app_name")))
	var tagline := UiKit.make_label(Locale.t("tagline"), 20)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)

	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var who := UiKit.make_label("%s  |  v%s" % [GameState.player_name, ver], 16)  # EN: "<player> | v<version>"
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.modulate.a = 0.8
	box.add_child(who)
	box.add_child(UiKit.make_spacer(14.0))

	# EN: Play — open world selection screen.
	box.add_child(_menu_button(Locale.t("menu_play"), _goto_world_select))
	# EN: Create — start an empty world in build mode.
	box.add_child(_menu_button(Locale.t("menu_create"), _start_build_mode))
	# EN: Avatar — open avatar editor.
	box.add_child(_menu_button(Locale.t("menu_avatar"), _goto_avatar))
	# EN: Multiplayer — open local lobby.
	box.add_child(_menu_button(Locale.t("menu_multiplayer"), _goto_lobby))
	# EN: Settings — open settings overlay panel.
	box.add_child(_menu_button(Locale.t("menu_settings"), _open_settings))
	# EN: Quit — exit the application.
	box.add_child(_menu_button(Locale.t("menu_quit"), _quit_app))


func _menu_button(text: String, action: Callable) -> Button:
	var b := UiKit.make_button(text, Vector2(380, 60))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


func _goto_world_select() -> void:
	if ResourceLoader.exists(SCENE_WORLD_SELECT):
		GameState.goto_scene(SCENE_WORLD_SELECT)
	else:
		_show_fallback_toast()


func _start_build_mode() -> void:
	GameState.pending_action = {"mode": "build", "world_id": "empty"}
	if ResourceLoader.exists(SCENE_GAME):
		GameState.goto_scene(SCENE_GAME)
	else:
		_show_fallback_toast()


func _goto_avatar() -> void:
	if ResourceLoader.exists(SCENE_AVATAR):
		GameState.goto_scene(SCENE_AVATAR)
	else:
		_show_fallback_toast()


func _goto_lobby() -> void:
	if ResourceLoader.exists(SCENE_LOBBY):
		GameState.goto_scene(SCENE_LOBBY)
	else:
		_show_fallback_toast()


func _open_settings() -> void:
	for c in get_children():
		if c.has_meta("settings_overlay"):
			return
	if not ResourceLoader.exists(SETTINGS_SCRIPT):
		_show_fallback_toast()
		return
	var script: Variant = load(SETTINGS_SCRIPT)
	if script == null:
		_show_fallback_toast()
		return
	var panel: Control = script.new()
	panel.set_meta("settings_overlay", true)
	panel.call("open", self)


func _quit_app() -> void:
	get_tree().quit()


func _show_fallback_toast() -> void:
	UiKit.show_toast(_toast_layer, Locale.t("error_not_impl"))


func _on_theme_changed() -> void:
	theme = Settings.get_theme()
	if _bg != null and is_instance_valid(_bg):
		_bg.color = _bg_color()


func _on_language_changed() -> void:
	_build_ui()


func _on_achievement(id: String, _title: String) -> void:
	# Kunci dinamis per achievement; contoh EN: "ach_first_build": "First Block!"
	UiKit.show_toast(_toast_layer, Locale.t("ach_" + id))


func _bg_color() -> Color:
	return UiKit.COL_BG_DARK if Settings.is_dark_mode() else UiKit.COL_BG_LIGHT


func _apply_audio_settings() -> void:
	_apply_bus("Master", float(Settings.get_value("master_volume", 0.8)))
	_apply_bus("Music", float(Settings.get_value("music_volume", 0.7)))
	_apply_bus("SFX", float(Settings.get_value("sfx_volume", 0.9)))


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	if linear > 0.001:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
