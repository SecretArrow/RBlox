extends Node3D
## Game — orkestrator scene gameplay RBlox (Task 2-e1).
## Resolve world_json (Net > pending_action > fallback empty) -> build dunia ->
## pemain lokal/remote -> touch controls -> mode (tick 1/30) -> env -> HUD ->
## build -> chat -> tutorial -> pause panel. Net.leave() hanya lewat menu.

const MAIN_SCENE := "res://scenes/main_menu.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const TEMPLATES_PATH := "res://scripts/world/templates.gd"
const WORLD_MANAGER_PATH := "res://scripts/world/world_manager.gd"
const BUILD_MANAGER_PATH := "res://scripts/build/build_manager.gd"
const TOUCH_CONTROLS_PATH := "res://scripts/player/touch_controls.gd"
const DAY_NIGHT_PATH := "res://scripts/world/day_night.gd"
const WEATHER_PATH := "res://scripts/world/weather.gd"
const GAME_HUD_SCENE := "res://scenes/game_hud.tscn"
const BUILD_HUD_SCENE := "res://scenes/build_hud.tscn"
const CHAT_SCENE := "res://scenes/chat_overlay.tscn"
const TUTORIAL_PATH := "res://scripts/ui/tutorial.gd"
const MODE_SANDBOX_PATH := "res://scripts/world/modes/sandbox.gd"

var world_json: Dictionary = {}
var session_mode := "play"
var world_root: Node3D = null
var props_root: Node3D = null
var refs: Dictionary = {}
var blocks_root: Node3D = null
var terrain: Node3D = null
var spawn_points: Array = []
var local_player: Node = null
var mode: Node = null
var build_manager: Node = null
var build_hud: Node = null
var hud: Node = null
var _wm: GDScript = null
var _players_root: Node3D = null
var _build_active := false
var _pause_layer: CanvasLayer = null
var _pause_visible := false
var _pause_prev_edge := false
var _script_cache: Dictionary = {}


func _ready() -> void:
        add_to_group("game")
        _resolve_world_json()
        GameState.current_world = world_json
        _build_world()
        _spawn_players()
        _setup_touch_controls()
        _setup_mode()
        _setup_env()
        _setup_hud_and_build()
        _setup_chat_and_tutorial()
        _build_pause_ui()
        _apply_saved_session()


func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("pause_menu"):
                request_pause()
        elif event.is_action_pressed("toggle_build"):
                toggle_build_mode()


func _exit_tree() -> void:
        get_tree().paused = false


## Resolve dunia: Net aktif > pending_action (world_id/world_path) > fallback.
func _resolve_world_json() -> void:
        world_json = {}
        if Net.is_active():
                var nw := Net.current_world()
                if nw is Dictionary and not (nw as Dictionary).is_empty():
                        world_json = nw
        if world_json.is_empty():
                var pa: Dictionary = {}
                if GameState.pending_action is Dictionary:
                        pa = GameState.pending_action
                session_mode = String(pa.get("mode", "play"))
                if pa.has("world_id"):
                        var tpl := _load_script(TEMPLATES_PATH)
                        if tpl != null:
                                world_json = tpl.call("build_world_json", String(pa["world_id"]))
                elif pa.has("world_path"):
                        world_json = Saves.load_world(String(pa["world_path"]))
        if world_json.is_empty():
                var tpl2 := _load_script(TEMPLATES_PATH)
                if tpl2 != null:
                        world_json = tpl2.call("build_world_json", "empty")
        if world_json.is_empty():
                world_json = {
                        "format": "rblox-world",
                        "version": 1,
                        "meta": {"name": "Dunia"},
                        "settings": {"game_mode": "sandbox", "build_allowed": true},
                        "spawn_points": [[0, 3, 0]]
                }
        _normalize(world_json)


## Lengkapi field skema wajib agar modul lain bisa membaca dengan aman.
func _normalize(w: Dictionary) -> void:
        if String(w.get("format", "")) != "rblox-world":
                w["format"] = "rblox-world"
        w["version"] = int(w.get("version", 1))
        if not (w.get("meta") is Dictionary):
                w["meta"] = {"name": "Dunia"}
        if not (w.get("settings") is Dictionary):
                w["settings"] = {}
        var s: Dictionary = w["settings"]
        var defaults := {
                "game_mode": "sandbox",
                "weather": "clear",
                "cycle_minutes": 10.0,
                "day_night": true,
                "health_enabled": true,
                "build_allowed": false
        }
        for k in defaults.keys():
                if not s.has(k):
                        s[k] = defaults[k]
        for k in ["spawn_points", "blocks", "props"]:
                if not (w.get(k) is Array):
                        w[k] = []


func _build_world() -> void:
        _wm = _load_script(WORLD_MANAGER_PATH)
        if _wm != null:
                var res: Variant = _wm.call("build_world", world_json, self)
                if res is Dictionary:
                        var d: Dictionary = res
                        world_root = d.get("root") as Node3D
                        blocks_root = d.get("blocks") as Node3D
                        terrain = d.get("terrain") as Node3D
                        props_root = d.get("props") as Node3D
                        refs = d.duplicate()
                        if d.get("spawn_points") is Array:
                                spawn_points = d["spawn_points"]
        if world_root == null:  # Fallback bila WorldManager belum tersedia
                world_root = Node3D.new()
                world_root.name = "WorldRoot"
                add_child(world_root)
        if blocks_root == null:
                blocks_root = Node3D.new()
                blocks_root.name = "Blocks"
                world_root.add_child(blocks_root)
        if spawn_points.is_empty():
                spawn_points = world_json.get("spawn_points", [])
        if refs.is_empty():
                refs = {
                        "root": world_root,
                        "blocks": blocks_root,
                        "props": props_root,
                        "terrain": terrain,
                        "spawn_points": spawn_points
                }


func _spawn_players() -> void:
        _players_root = Node3D.new()
        _players_root.name = "Players"
        add_child(_players_root)
        var info := {
                "name": GameState.player_name, "avatar": GameState.avatar_config, "peer_id": Net.my_id()
        }
        local_player = _make_player(info, true, Net.my_id(), 0)
        if Net.is_active():
                _refresh_remote_players()
                Net.player_list_changed.connect(_refresh_remote_players)
                Net.world_block_changed.connect(_on_world_block_changed)


func _make_player(info: Dictionary, local: bool, peer_id: int, spawn_idx: int) -> Node:
        var p: Node = _instance_scene(PLAYER_SCENE)
        if p == null:
                p = CharacterBody3D.new()  # Fallback tanpa visual avatar
        p.name = "LocalPlayer" if local else str(peer_id)
        if p is Node3D:
                (p as Node3D).position = _spawn_pos(spawn_idx)
        if not local:
                p.set_multiplayer_authority(peer_id)
        if p.has_method("setup"):
                p.call("setup", info, local)
        p.add_to_group("local_player" if local else "remote_players")
        _players_root.add_child(p)
        return p


func _spawn_pos(idx: int) -> Vector3:
        var arr: Array = spawn_points
        if arr.is_empty():
                arr = world_json.get("spawn_points", [])
        if not arr.is_empty():
                var p: Variant = arr[posmod(idx, arr.size())]
                if p is Array and (p as Array).size() >= 3:
                        return Vector3(float(p[0]), float(p[1]), float(p[2]))
        var sp: Variant = world_json.get("settings", {}).get("spawn", [0, 3, 0])
        if sp is Array and (sp as Array).size() >= 3:
                return Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
        return Vector3(0, 3, 0)


## Sinkronkan pemain remote dengan roster Net (spawn/despawn delta).
func _refresh_remote_players(_players: Variant = null) -> void:
        if not Net.is_active() or _players_root == null:
                return
        var seen := {}
        for pv in Net.players():
                if not (pv is Dictionary):
                        continue
                var pid := int(pv.get("id", 0))
                if pid <= 0 or pid == Net.my_id() or _players_root.get_node_or_null(str(pid)) != null:
                        continue
                seen[pid] = true
                var av: Variant = pv.get("avatar")
                _make_player(
                        {
                                "name": String(pv.get("name", "Player")),
                                "avatar": av if av is Dictionary else {},
                                "peer_id": pid
                        },
                        false,
                        pid,
                        seen.size()
                )
        for c in _players_root.get_children():
                var cname := String(c.name)
                if c != local_player and (not cname.is_valid_int() or not seen.has(int(cname))):
                        c.queue_free()


func _on_world_block_changed(data: Dictionary, removed: bool) -> void:
        _call_if(_wm, "apply_block_update", [blocks_root, data, removed])


func _setup_touch_controls() -> void:
        var scr := _load_script(TOUCH_CONTROLS_PATH)
        if scr == null or local_player == null:
                return
        var tc: Node = scr.new()
        add_child(tc)
        tc.add_to_group("touch_controls")
        _call_if(tc, "bind_player", [local_player])


func _setup_mode() -> void:
        var gm := String(world_json.get("settings", {}).get("game_mode", "sandbox"))
        var s := _load_script("res://scripts/world/modes/%s.gd" % gm)
        if s == null:
                s = _load_script(MODE_SANDBOX_PATH)
        if s == null:
                return
        mode = s.new()
        mode.name = "ModeController"
        add_child(mode)
        _call_if(mode, "setup", [world_json, self])
        var t := Timer.new()
        t.wait_time = 1.0 / 30.0
        t.autostart = true
        t.timeout.connect(func() -> void: _call_if(mode, "tick", [1.0 / 30.0]))
        add_child(t)


func _setup_env() -> void:
        var s: Dictionary = world_json.get("settings", {})
        for cfg in [
                [DAY_NIGHT_PATH, "env_day_night", "DayNight"], [WEATHER_PATH, "env_weather", "Weather"]
        ]:
                var scr := _load_script(cfg[0])
                if scr == null:
                        continue
                var node: Node = scr.new()
                node.name = cfg[2]
                node.add_to_group(cfg[1])
                add_child(node)
                _call_if(node, "configure", [s])


func _setup_hud_and_build() -> void:
        hud = _instance_scene(GAME_HUD_SCENE)
        if hud != null:
                add_child(hud)
        var allowed: bool = (
                session_mode == "build"
                or (
                        bool(world_json.get("settings", {}).get("build_allowed", false))
                        and (not Net.is_active() or Net.is_host())
                )
        )
        if allowed:
                _setup_build()


func _setup_build() -> void:
        var bm_scr := _load_script(BUILD_MANAGER_PATH)
        if bm_scr != null:
                build_manager = bm_scr.new()
                build_manager.name = "BuildManager"
                add_child(build_manager)
                _call_if(build_manager, "set_terrain", [terrain])
                _call_if(build_manager, "set_blocks_root", [blocks_root])
                _call_if(build_manager, "set_camera", [_player_camera()])
                if build_manager.has_signal("block_changed"):
                        build_manager.connect("block_changed", _on_block_net)
        build_hud = _instance_scene(BUILD_HUD_SCENE)
        if build_hud != null:
                add_child(build_hud)
                _call_if(build_hud, "bind_build_manager", [build_manager])
                _call_if(build_hud, "set_camera", [_player_camera()])
        if session_mode == "build":
                toggle_build_mode()


func _player_camera() -> Camera3D:
        if local_player != null and is_instance_valid(local_player):
                var c: Variant = (
                        local_player.call("get_camera") if local_player.has_method("get_camera") else null
                )
                if c is Camera3D:
                        return c
                var cams := local_player.find_children("*", "Camera3D", true, false)
                if not cams.is_empty():
                        return cams[0] as Camera3D
        var vp := get_viewport()
        return vp.get_camera_3d() if vp != null else null


func toggle_build_mode() -> void:
        if build_manager == null:
                return
        if build_hud != null and build_hud.has_method("open"):
                var show: bool = not (build_hud as CanvasLayer).visible
                _call_if(build_hud, "open" if show else "close")
                _build_active = show
        else:
                _build_active = not _build_active
                _call_if(build_manager, "activate", [_build_active])


func _on_block_net(data: Dictionary, removed: bool) -> void:
        if Net.is_active() and Net.is_host():
                Net.rpc_block_update(data, removed)


func _setup_chat_and_tutorial() -> void:
        if Net.is_active():
                var chat := _instance_scene(CHAT_SCENE)
                if chat != null:
                        chat.name = "ChatOverlay"
                        add_child(chat)
        if bool(Settings.get_value("tutorial_done", false)):
                return
        var scr := _load_script(TUTORIAL_PATH)
        if scr == null:
                return
        var tut: Node = scr.new()
        tut.name = "Tutorial"
        add_child(tut)
        _call_if(tut, "start")


func _build_pause_ui() -> void:
        _pause_layer = CanvasLayer.new()
        _pause_layer.name = "PauseLayer"
        _pause_layer.layer = 30
        _pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
        _pause_layer.visible = false
        add_child(_pause_layer)
        var dim := ColorRect.new()
        dim.color = Color(0, 0, 0, 0.55)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        _pause_layer.add_child(dim)
        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        _pause_layer.add_child(center)
        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(340, 0)
        box.add_theme_constant_override("separation", 12)
        var panel := PanelContainer.new()
        panel.add_child(box)
        center.add_child(panel)
        var title := Label.new()
        title.text = Locale.t("pause_title")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(title)
        _pause_button(box, Locale.t("pause_resume"), _on_resume)
        if not Net.is_active():
                _pause_button(box, Locale.t("common_save"), _on_save)
        _pause_button(box, Locale.t("pause_main_menu"), _on_main_menu)
        var poll := Timer.new()
        poll.wait_time = 0.15
        poll.autostart = true
        poll.timeout.connect(_poll_pause_input)
        _pause_layer.add_child(poll)


func _pause_button(box: VBoxContainer, text: String, cb: Callable) -> void:
        var b := Button.new()
        b.text = text
        b.custom_minimum_size = Vector2(0, 56)
        b.pressed.connect(cb)
        box.add_child(b)


func request_pause() -> void:
        _set_paused(not _pause_visible)


func _set_paused(v: bool) -> void:
        _pause_visible = v
        if _pause_layer != null:
                _pause_layer.visible = v
        get_tree().paused = v


func _poll_pause_input() -> void:
        var pressed := Input.is_action_pressed("pause_menu")
        if _pause_visible and pressed and not _pause_prev_edge:
                _set_paused(false)
        _pause_prev_edge = pressed


func _on_resume() -> void:
        _set_paused(false)


func _on_save() -> void:
        if Net.is_active():
                return
        var meta: Dictionary = world_json.get("meta", {})
        var wname := String(meta.get("name", "Dunia Saya"))
        var data := get_world_json()
        # EN: attach live session state (player, mode progress, day/weather) to the save.
        data["session"] = capture_session()
        if Saves.save_world(wname, data) == OK:
                GameState.unlock_achievement("world_saved")
                var toast: GDScript = _load_script("res://scripts/ui/toast.gd")
                if toast != null:
                        toast.call("show", self, Locale.t("toast_session_saved"))


func _on_main_menu() -> void:
        if Net.is_active():
                Net.leave()
        _set_paused(false)
        GameState.goto_scene(MAIN_SCENE)


# ------------------------------------------------------- save/resume sesi


## Tangkap state sesi berjalan (pemain, progres mode, siang/cuaca) untuk resume.
func capture_session() -> Dictionary:
        var ses := {"saved_at": Time.get_unix_time_from_system(), "session_mode": session_mode}
        if local_player != null and is_instance_valid(local_player):
                var hp := -1.0
                if local_player.has_method("get_health"):
                        hp = float(local_player.call("get_health"))
                ses["player"] = {
                        "pos": [local_player.position.x, local_player.position.y, local_player.position.z],
                        "yaw": local_player.rotation.y,
                        "hp": hp,
                }
        var dn: Variant = get_tree().get_first_node_in_group("env_day_night")
        if dn != null and (dn as Node).has_method("get_time"):
                ses["day_time"] = float((dn as Node).call("get_time"))
        var we: Variant = get_tree().get_first_node_in_group("env_weather")
        if we != null and (we as Node).has_method("get_weather"):
                ses["weather"] = String((we as Node).call("get_weather"))
        if mode != null and is_instance_valid(mode) and mode.has_method("session_state"):
                var ms: Variant = mode.call("session_state")
                if ms is Dictionary:
                        ses["mode"] = ms
        return ses


## Terapkan state sesi tersimpan (dipanggil deferred setelah dunia siap).
func apply_session(ses: Dictionary) -> void:
        if ses.is_empty():
                return
        var pv: Variant = ses.get("player", {})
        if pv is Dictionary and local_player != null and is_instance_valid(local_player):
                var p: Dictionary = pv
                var pos: Variant = p.get("pos", [])
                if pos is Array and (pos as Array).size() >= 3:
                        local_player.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
                local_player.rotation.y = float(p.get("yaw", 0.0))
                var hp := float(p.get("hp", -1.0))
                if hp >= 0.0 and local_player.has_method("get_health"):
                        var diff := hp - float(local_player.call("get_health"))
                        if diff < -0.01 and local_player.has_method("take_damage"):
                                local_player.call("take_damage", -diff)
                        elif diff > 0.01 and local_player.has_method("heal"):
                                local_player.call("heal", diff)
        var dn: Variant = get_tree().get_first_node_in_group("env_day_night")
        if dn != null and (dn as Node).has_method("set_time") and ses.get("day_time") != null:
                (dn as Node).call("set_time", float(ses["day_time"]))
        var we: Variant = get_tree().get_first_node_in_group("env_weather")
        if we != null and (we as Node).has_method("set_weather") and ses.get("weather") != null:
                (we as Node).call("set_weather", String(ses["weather"]))
        if mode != null and is_instance_valid(mode) and mode.has_method("restore_session"):
                var ms: Variant = ses.get("mode", {})
                if ms is Dictionary and not (ms as Dictionary).is_empty():
                        mode.call("restore_session", ms)


func _apply_saved_session() -> void:
        var ses: Variant = world_json.get("session", {})
        if ses is Dictionary and not (ses as Dictionary).is_empty():
                apply_session.call_deferred(ses)


## Autosave sesi saat aplikasi masuk background / ditutup (mobile friendly).
func _notification(what: int) -> void:
        if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
                _autosave()


func _autosave() -> void:
        if Net.is_active() or world_json.is_empty():
                return
        var data := get_world_json()
        data["session"] = capture_session()
        if data.get("meta") is Dictionary:
                (data["meta"] as Dictionary)["name"] = "Autosave"
        Saves.save_world("Autosave", data)


func get_world_json() -> Dictionary:
        var base := world_json.duplicate(true)
        if _wm != null and world_root != null and _wm.has_method("serialize_world"):
                var out: Variant = _wm.call("serialize_world", world_root, base)
                if out is Dictionary and not (out as Dictionary).is_empty():
                        return out
        return base


func _load_script(path: String) -> GDScript:
        if _script_cache.has(path):
                return _script_cache[path]
        var s: GDScript = load(path) as GDScript if ResourceLoader.exists(path) else null
        _script_cache[path] = s
        return s


func _instance_scene(path: String) -> Node:
        if not ResourceLoader.exists(path):
                return null
        var ps := load(path) as PackedScene
        return ps.instantiate() if ps != null else null


## Panggil method pada node hanya bila ada (guard lintas modul).
func _call_if(node: Variant, method: String, args: Array = []) -> void:
        if node != null and is_instance_valid(node) and node.has_method(method):
                node.callv(method, args)
