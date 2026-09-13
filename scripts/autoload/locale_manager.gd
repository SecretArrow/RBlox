extends Node
## Autoload: Locale — i18n ringan berbasis JSON (id/en).
## Pemakaian: Locale.t("menu_play") atau Locale.t("msg_hi", {"name": "Bob"})

signal language_changed

const LOCALE_DIR := "res://data/locales"
const FALLBACK := "en"

var _lang: String = ""
var _cache: Dictionary = {}


func t(key: String, vars: Dictionary = {}) -> String:
	var text := _lookup(key)
	for k in vars.keys():
		text = text.replace("{%s}" % k, str(vars[k]))
	return text


func set_language(lang: String) -> void:
	if lang != _lang:
		_lang = lang
		Settings.set_value("language", lang)
		language_changed.emit()


func get_language() -> String:
	return _get_lang()


func available_languages() -> Array:
	return ["id", "en"]


func _get_lang() -> String:
	if _lang == "":
		_lang = String(Settings.get_value("language", "id"))
	return _lang


func _lookup(key: String) -> String:
	var table := _get_table(_get_lang())
	if table.has(key):
		return String(table[key])
	var fb := _get_table(FALLBACK)
	if fb.has(key):
		return String(fb[key])
	return key


func _get_table(lang: String) -> Dictionary:
	if _cache.has(lang):
		return _cache[lang]
	var path := "%s/%s.json" % [LOCALE_DIR, lang]
	var table: Dictionary = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				table = parsed
	_cache[lang] = table
	return table
