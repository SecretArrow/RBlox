extends Node
## Autoload: Settings — penyimpanan preferensi pengguna (user://settings.cfg) & tema.

signal setting_changed(key: String, value: Variant)
signal theme_changed

const SAVE_PATH := "user://settings.cfg"

const DEFAULTS := {
	"language": "id",
	"dark_mode": true,
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.9,
	"graphics_quality": "medium",
	"chat_enabled": true,
	"camera_sensitivity": 1.0,
	"tutorial_done": false,
	"player_name": "",
}

var _values: Dictionary = {}
var _theme: Theme = null
var _theme_is_dark: bool = true


func _ready() -> void:
	_load()


func get_value(key: String, default: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return default


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	_save()
	setting_changed.emit(key, value)
	if key == "dark_mode":
		_theme = null
		theme_changed.emit()


func get_language() -> String:
	return String(get_value("language", "id"))


func is_dark_mode() -> bool:
	return bool(get_value("dark_mode", true))


func set_dark_mode(dark: bool) -> void:
	set_value("dark_mode", dark)


func chat_enabled() -> bool:
	return bool(get_value("chat_enabled", true))


func get_theme() -> Theme:
	if _theme == null or _theme_is_dark != is_dark_mode():
		_theme_is_dark = is_dark_mode()
		_theme = _build_theme()
	return _theme


func _build_theme() -> Theme:
	var tb_path := "res://scripts/ui/theme_builder.gd"
	if ResourceLoader.exists(tb_path):
		var builder: Variant = load(tb_path)
		if builder != null and builder.has_method("build"):
			return builder.build(_theme_is_dark)
	return _fallback_theme()


func _fallback_theme() -> Theme:
	var t := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2f6fed")
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	t.set_stylebox("normal", "Button", sb)
	return t


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		for key in DEFAULTS.keys():
			_values[key] = cf.get_value("settings", key, DEFAULTS[key])


func _save() -> void:
	var cf := ConfigFile.new()
	for key in _values.keys():
		cf.set_value("settings", key, _values[key])
	cf.save(SAVE_PATH)
