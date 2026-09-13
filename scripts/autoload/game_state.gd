extends Node
## Autoload: GameState — status sesi global, avatar pemain, statistik & achievement offline.

signal achievement_unlocked(id: String, title: String)
signal avatar_changed

const AVATAR_PATH := "user://avatar.json"
const PROGRESS_PATH := "user://progress.json"

const DEFAULT_AVATAR := {
	"skin": "#e0b088",
	"shirt": "#4f8cff",
	"pants": "#34495e",
	"hair": "#3b2314",
	"face": "smile",
	"equipped":
	{
		"hat": "",
		"hair": "hair_short",
		"face": "face_smile",
		"shirt": "shirt_basic",
		"pants": "pants_basic",
		"accessory": "",
		"wings": "",
		"back": "",
		"hand": "",
	},
}

var player_name: String = "Player"
var avatar_config: Dictionary = {}
var current_world: Dictionary = {}
var current_world_path: String = ""
var pending_action: Dictionary = {}
var first_run: bool = false

var _stats: Dictionary = {}
var _achievements: Dictionary = {}


func _enter_tree() -> void:
	_register_inputs()


func _ready() -> void:
	first_run = not FileAccess.file_exists(AVATAR_PATH)
	_load_avatar()
	_load_progress()
	var saved_name := String(Settings.get_value("player_name", ""))
	if saved_name == "":
		player_name = "Player%04d" % (randi() % 10000)
		Settings.set_value("player_name", player_name)
	else:
		player_name = saved_name


func save_avatar() -> void:
	var f := FileAccess.open(AVATAR_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(avatar_config, "\t"))
	avatar_changed.emit()


func set_avatar_config(cfg: Dictionary) -> void:
	avatar_config = cfg
	save_avatar()


func add_stat(key: String, amount: int = 1) -> int:
	_stats[key] = int(_stats.get(key, 0)) + amount
	_save_progress()
	return int(_stats[key])


func get_stat(key: String) -> int:
	return int(_stats.get(key, 0))


func unlock_achievement(id: String) -> bool:
	if bool(_achievements.get(id, false)):
		return false
	_achievements[id] = true
	_save_progress()
	achievement_unlocked.emit(id, id)
	return true


func is_achievement_unlocked(id: String) -> bool:
	return bool(_achievements.get(id, false))


func achievements_state() -> Dictionary:
	return _achievements.duplicate()


func is_multiplayer() -> bool:
	return Net != null and Net.is_active()


func is_host() -> bool:
	return Net != null and Net.is_host()


func goto_scene(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)


# ------------------------------------------------------------------ internal


func _load_avatar() -> void:
	avatar_config = DEFAULT_AVATAR.duplicate(true)
	if FileAccess.file_exists(AVATAR_PATH):
		var f := FileAccess.open(AVATAR_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var cfg: Dictionary = parsed
				for k in cfg.keys():
					avatar_config[k] = cfg[k]


func _load_progress() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_stats = parsed.get("stats", {})
				_achievements = parsed.get("achievements", {})


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"stats": _stats, "achievements": _achievements}, "\t"))


# ------------------------------------------------------- input map bootstrap


func _register_inputs() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("action_a", KEY_E)
	_add_key_action("toggle_build", KEY_B)
	_add_key_action("open_chat", KEY_T)
	_add_key_action("pause_menu", KEY_ESCAPE)
	_add_button_action("jump", JOY_BUTTON_A)
	_add_button_action("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_add_button_action("action_a", JOY_BUTTON_X)
	_add_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis_action("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis_action("move_back", JOY_AXIS_LEFT_Y, 1.0)


func _add_key_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action, ev)


func _add_button_action(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _add_axis_action(action: String, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
