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
        _maybe_run_demo_shots()


# ------------------------------------------------- mode demo screenshot (CI)

## Jalankan dengan: godot -- --screenshot-demo --shot-dir=/abs/path
## Mengambil 2 tangkapan layar asli (menu & gameplay) lalu keluar — pratinjau
## untuk dokumentasi/README tanpa perlu memasang APK.
func _maybe_run_demo_shots() -> void:
        var args := OS.get_cmdline_user_args()
        if not args.has("--screenshot-demo"):
                return
        var dir := "user://demo_shots"
        for a in args:
                if String(a).begins_with("--shot-dir="):
                        dir = String(a).trim_prefix("--shot-dir=")
        _run_demo_shots(dir)


func _run_demo_shots(dir: String) -> void:
        DirAccess.make_dir_recursive_absolute(dir)
        await _wait_frames(60)
        _capture("%s/rblox-menu.png" % dir)
        Settings.set_value("tutorial_done", true)
        pending_action = {"mode": "play", "world_id": "city"}
        goto_scene("res://scenes/game.tscn")
        await _wait_frames(45)
        _stage_gameplay_shot()
        await _wait_frames(165)
        _capture("%s/rblox-gameplay.png" % dir)
        await _wait_frames(10)
        get_tree().quit()


## Atur panggung tangkapan gameplay: pemain dipindah ke persimpangan jalan
## kota (pemandangan terbuka, lampu jalan di frame), kamera over-the-shoulder
## mengarah ke pusat kota, jam 09.30 yang terang, dan bayangan matahari dimatikan
## agar render software (llvmpipe di CI) bebas artefak garis/shadow acne.
func _stage_gameplay_shot() -> void:
        var game := get_tree().current_scene
        if game == null:
                return
        var p: Node = game.get("local_player")
        if p is Node3D:
                var body := p as Node3D
                if body.has_method("set_gravity"):
                        body.call("set_gravity", 0.0)  # beku di panggung, tak jatuh
                body.rotation = Vector3(0.0, PI * 0.25, 0.0)
                body.global_position = Vector3(16.0, 0.1, 16.0)  # tengah persimpangan
                var rig := body.get_node_or_null("CameraRig")
                if rig != null:
                        rig.call("set_yaw", PI * 0.25)  # pandang ke pusat kota (0,0)
                        rig.call("set_pitch", -0.10)
                        rig.call("set_distance", 4.8)
        var dn := get_tree().get_first_node_in_group("env_day_night")
        if dn != null:
                dn.call("set_time", 9.5)
                for c in dn.get_children():
                        if c is DirectionalLight3D:
                                # Bayangan dimatikan khusus tangkapan CI: rasterizer software
                                # (llvmpipe) menghasilkan shadow-acak garis pada shadow map.
                                (c as DirectionalLight3D).shadow_enabled = false
        # Chip FPS disembunyikan untuk pratinjau (angka FPS llvmpipe tak relevan).
        for lb in game.find_children("*", "Label", true, false):
                var l := lb as Label
                if l != null and l.text.ends_with("FPS") and l.get_parent() is Control:
                        (l.get_parent() as Control).visible = false


func _wait_frames(n: int) -> void:
        for i in n:
                await get_tree().process_frame


func _capture(path: String) -> void:
        var vp := get_viewport()
        if vp == null:
                return
        var img := vp.get_texture().get_image()
        if img != null and not img.is_empty():
                img.save_png(path)
                print("DEMO_SHOT_SAVED: ", path)


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
