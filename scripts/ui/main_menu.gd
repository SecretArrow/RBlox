extends Control
## MainMenu — layar utama RBlox (v0.2 AAA pass): gradien hero, blok dekoratif
## melayang, judul besar, navigasi tombol chunky dengan animasi tekan,
## panel pengaturan overlay, toast achievement, chip versi & nama pemain.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

const SCENE_WORLD_SELECT := "res://scenes/world_select.tscn"
const SCENE_GAME := "res://scenes/game.tscn"
const SCENE_AVATAR := "res://scenes/avatar_editor.tscn"
const SCENE_LOBBY := "res://scenes/lobby.tscn"
const SETTINGS_SCRIPT := "res://scripts/ui/settings_menu.gd"

var _bg_root: Control
var _ui_root: Control
var _toast_layer: Control


func _ready() -> void:
	theme = Settings.get_theme()
	_bg_root = Control.new()
	_bg_root.name = "BgRoot"
	_bg_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg_root)
	_build_background()
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


func _build_background() -> void:
	for c in _bg_root.get_children():
		c.queue_free()
	var top := Color("#141c30") if Settings.is_dark_mode() else Color("#f6f8fd")
	var bottom := Color("#0b0f1b") if Settings.is_dark_mode() else Color("#dde5f4")
	_bg_root.add_child(UiKit.make_gradient_bg(top, bottom))
	_bg_root.add_child(UiKit.make_decor_blocks())


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
	var tagline := UiKit.make_label(Locale.t("tagline"), 18)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	tagline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	tagline.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(tagline)

	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var who := UiKit.make_label("%s  |  v%s" % [GameState.player_name, ver], 15)  # EN: "<player> | v<version>"
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(who)
	box.add_child(UiKit.make_spacer(12.0))

	# EN: Continue — resume the most recent save (world + session state).
	if not Saves.list_worlds().is_empty():
		box.add_child(_menu_button(Locale.t("menu_continue"), _continue_last, true))
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

	# Chip versi kanan-bawah (identitas build ala konsol game).
	var chip := UiKit.make_chip("RBlox v" + ver, Color(0, 0, 0, 0.4))
	chip.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14
	)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui_root.add_child(chip)


func _menu_button(text: String, action: Callable, accent2: bool = false) -> Button:
	var b := UiKit.make_button(text, Vector2(400, 62), not accent2)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


func _goto_world_select() -> void:
	if ResourceLoader.exists(SCENE_WORLD_SELECT):
		GameState.goto_scene(SCENE_WORLD_SELECT)
	else:
		_show_fallback_toast()


## Lanjutkan: muat save terbaru (dunia + state sesi) langsung ke gameplay.
func _continue_last() -> void:
	var saves := Saves.list_worlds()
	if saves.is_empty():
		return
	var latest: Dictionary = saves[0]  # list_worlds() sudah urut terbaru dulu
	GameState.pending_action = {"mode": "play", "world_path": String(latest.get("path", ""))}
	GameState.goto_scene(SCENE_GAME)


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
	_build_background()


func _on_language_changed() -> void:
	_build_ui()


func _on_achievement(id: String, _title: String) -> void:
	# Kunci dinamis per achievement; contoh EN: "ach_first_build": "First Block!"
	UiKit.show_toast(_toast_layer, Locale.t("ach_" + id))


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
