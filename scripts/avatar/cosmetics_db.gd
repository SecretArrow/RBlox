extends RefCounted
## CosmeticsDB — static item database for avatar cosmetics.
## Data is loaded once from data/cosmetics/cosmetics.json and
## data/cosmetics/presets.json (static cache).

const COSMETICS_PATH := "res://data/cosmetics/cosmetics.json"
const PRESETS_PATH := "res://data/cosmetics/presets.json"

static var _items: Array = []
static var _presets: Array = []
static var _loaded := false


static func all_items() -> Array:
	_ensure()
	return _items


static func items_for_slot(slot: String) -> Array:
	_ensure()
	var out: Array = []
	for it in _items:
		if it is Dictionary and str(it.get("slot", "")) == slot:
			out.append(it)
	return out


static func get_item(id: String) -> Dictionary:
	_ensure()
	for it in _items:
		if it is Dictionary and str(it.get("id", "")) == id:
			return it
	return {}


static func presets() -> Array:
	_ensure()
	return _presets


# ------------------------------------------------------------------ internal


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var raw: Variant = _read_json(COSMETICS_PATH)
	if raw is Array:
		_items = raw
	elif raw is Dictionary:
		_items = raw.get("items", [])
	var clean: Array = []
	for it in _items:
		if it is Dictionary and it.has("id") and it.has("slot"):
			clean.append(it)
	_items = clean

	var praw: Variant = _read_json(PRESETS_PATH)
	if praw is Array:
		_presets = praw
	elif praw is Dictionary:
		_presets = praw.get("presets", [])
	var pclean: Array = []
	for p in _presets:
		if p is Dictionary and p.has("config"):
			pclean.append(p)
	_presets = pclean


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed
