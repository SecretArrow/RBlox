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
## Mengambil 5 tangkapan layar asli 1080p (menu, gameplay kota, mode build,
## obby senja, editor avatar) lalu keluar — pratinjau dokumentasi/README
## tanpa perlu memasang APK. Kamera sinematik berdiri sendiri dipakai agar
## komposisi terkontrol, dan bayangan dimatikan karena rasterizer software
## (llvmpipe di CI) memunculkan shadow acne pada shadow map.
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
	Settings.set_value("tutorial_done", true)
	_msaa_for_stills()
	# Kaca solid khusus tangkapan software (llvmpipe): alpha blend pada
	# wajah gedung yang nyaris sejajar layar menghasilkan arsir dither
	# 1px. Di perangkat nyata material kaca tetap transparan.
	var mmc: GDScript = load("res://scripts/world/mm_chunks.gd")
	var glass: Variant = mmc._material("glass")
	if glass is StandardMaterial3D:
		var gm := glass as StandardMaterial3D
		gm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		gm.albedo_color = Color(0.72, 0.82, 0.94, 1.0)

		# 1) Gameplay kota pagi — kamera sinematik menyusuri koridor jalan.

		# 2) Mode build di kota — lengkung pelangi + HUD build aktif.

		# 3) Obby senja — spiral platform warna-warni.

		# 4) Editor avatar — preview 3D + tab kustomisasi.
	await _wait_frames(60)
	_capture("%s/rblox-menu.png" % dir)
	# 1) Gameplay kota pagi — kamera sinematik menyusuri koridor jalan.
	pending_action = {"mode": "play", "world_id": "city"}
	goto_scene("res://scenes/game.tscn")
	await _wait_frames(55)
	_stage_city_shot()
	await _wait_frames(130)
	_capture("%s/rblox-gameplay.png" % dir)
	# 2) Mode build di kota — lengkung pelangi + HUD build aktif.
	pending_action = {"mode": "build", "world_id": "city"}
	goto_scene("res://scenes/game.tscn")
	await _wait_frames(55)
	_stage_build_shot()
	await _wait_frames(60)
	_capture("%s/rblox-build.png" % dir)
	# 3) Obby senja — spiral platform warna-warni.
	pending_action = {"mode": "play", "world_id": "obby"}
	goto_scene("res://scenes/game.tscn")
	await _wait_frames(55)
	_stage_obby_shot()
	await _wait_frames(130)
	_capture("%s/rblox-obby.png" % dir)
	# 4) Editor avatar — preview 3D + tab kustomisasi.
	goto_scene("res://scenes/avatar_editor.tscn")
	await _wait_frames(55)
	_capture("%s/rblox-avatar.png" % dir)
	await _wait_frames(10)
	get_tree().quit()


## Panggung gameplay kota: pemain beku di persimpangan, kamera sinematik
## terbang di koridor jalan x=16 (jalur bebas gedung sehingga gedung kaca
## transparan tidak memenuhi frame), jam 10.00 terang, label NPC & chip FPS
## disembunyikan agar bersih.
func _stage_city_shot() -> void:
	var game := get_tree().current_scene
	if game == null:
		return

		# Terrain flat kota tak terlihat (tertutup ubin tanah) — sembunyikan
		# agar rasterizer software tidak menggambar permukaan tersembunyi.

		# Aerial 3/4: seluruh elemen berada 30-80u dari kamera — zona paling
		# presisi bagi rasterizer software (kuantisasi kedalaman reversed-Z
		# paling kasar justru dekat kamera).
	_freeze_player_at(Vector3(16.0, 0.1, 16.0), PI * 0.3)
	_set_soft_render_env(10.0)
	_hide_npc_labels(game)
	_hide_fps_chip(game)
	# Terrain flat kota tak terlihat (tertutup ubin tanah) — sembunyikan
	# agar rasterizer software tidak menggambar permukaan tersembunyi.
	var terr: Node = game.get("terrain")
	if terr is Node3D:
		(terr as Node3D).visible = false
		# Aerial 3/4: seluruh elemen berada 30-80u dari kamera — zona paling
		# presisi bagi rasterizer software (kuantisasi kedalaman reversed-Z
		# paling kasar justru dekat kamera).
	_add_shot_cam(game, Vector3(16.0, 24.0, 56.0), Vector3(16.0, 1.0, -10.0), 58.0)


## Panggung mode build: lengkung pelangi di plaza dekat persimpangan, pemain
## menghadapnya, HUD build tampil otomatis (session_mode "build").
func _stage_build_shot() -> void:
	var game := get_tree().current_scene
	if game == null:
		return
	_freeze_player_at(Vector3(16.0, 0.1, 21.0), 0.0)
	_set_soft_render_env(10.0)
	_hide_npc_labels(game)
	_hide_fps_chip(game)
	_place_rainbow_arch(game)
	_add_shot_cam(game, Vector3(16.0, 3.4, 31.5), Vector3(16.0, 2.3, 7.0), 55.0)


## Panggung obby: pemain di platform ke-8 jalur spiral, kamera samping
## memotret deretan platform warna saat senja (jam 17.40).
func _stage_obby_shot() -> void:
	var game := get_tree().current_scene
	if game == null:
		return
	var ang := 0.55 * 8.0
	var ppos := Vector3(sin(ang) * 7.0, 1.0 + 8.0 * 0.28 + 0.25, 4.0 - 8.0 * 3.2)
	_freeze_player_at(ppos, PI * 0.5)
	_set_soft_render_env(17.4)
	_hide_npc_labels(game)
	_hide_fps_chip(game)
	_add_shot_cam(game, Vector3(13.0, 9.0, -6.0), Vector3(-3.0, 3.0, -36.0), 60.0)


## Bekukan pemain di satu titik (gravitasi nol) dengan hadapan yaw tertentu.
func _freeze_player_at(pos: Vector3, yaw: float) -> void:
	var game := get_tree().current_scene
	if game == null:
		return
	var p: Node = game.get("local_player")
	if p is Node3D:
		var body := p as Node3D
		if body.has_method("set_gravity"):
			body.call("set_gravity", 0.0)  # beku di panggung, tak jatuh
		body.rotation = Vector3(0.0, yaw, 0.0)
		body.global_position = pos


## Waktu + pencahayaan aman untuk rasterizer software (llvmpipe CI):
## bayangan DirectionalLight dimatikan agar bebas shadow acne.
func _set_soft_render_env(time_h: float) -> void:
	var dn := get_tree().get_first_node_in_group("env_day_night")
	if dn != null:
		dn.call("set_time", time_h)
		for c in dn.get_children():
			if c is DirectionalLight3D:
				(c as DirectionalLight3D).shadow_enabled = false


func _hide_npc_labels(game: Node) -> void:
	for lb in game.find_children("*", "Label3D", true, false):
		var l := lb as Label3D
		if l != null and String(l.text).to_lower().begins_with("npc"):
			l.visible = false


func _hide_fps_chip(game: Node) -> void:
	for lb in game.find_children("*", "Label", true, false):
		var l := lb as Label
		if l != null and l.text.ends_with("FPS") and l.get_parent() is Control:
			(l.get_parent() as Control).visible = false


## Kamera sinematik berdiri sendiri (rig pemain tetap utuh, hanya kamera
## aktif yang digantikan selama tangkapan). Near/far rapat agar presisi
## depth tinggi — rasterizer software bebas z-fighting/moiré di tanah.
func _add_shot_cam(game: Node, from_pos: Vector3, to_pos: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.name = "ShotCam"
	cam.fov = fov
	# Near 2.0: subjek tangkapan selalu > 8u — near lebih jauh menyempurna
	# kuantisasi kedalaman reversed-Z di dekat kamera (bebas kontur arsir).
	cam.near = 2.0
	cam.far = 220.0
	game.add_child(cam)
	cam.global_position = from_pos
	cam.look_at(to_pos)
	cam.make_current()


## MSAA dinonaktifkan khusus tangkapan software: MSAA 4x pada llvmpipe
## memaksa presisi depth turun sehingga jalan 0.1u di atas tanah saling
## bersilang (arsir komb). Tanpa MSAA, depth 24-bit penuh & permukaan bersih.
func _msaa_for_stills() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = Viewport.MSAA_DISABLED


## Tempatkan lengkung pelangi + panggung + pilar neon di plaza persimpangan
## via WorldManager.place_block agar blok ikut MultiMesh chunk renderer.
func _place_rainbow_arch(game: Node) -> void:
	var wm: GDScript = game.get("_wm")
	var root: Node3D = game.get("blocks_root")
	if wm == null or root == null:
		return
	var colors := ["#ff5252", "#ff9800", "#ffd600", "#66bb6a", "#29b6f6", "#5c6bc0", "#ab47bc"]
	var seg := 14
	for i in range(seg):
		var ang := PI * float(i) / float(seg - 1)
		var pos := Vector3(16.0 - 6.0 * cos(ang), 0.6 + 5.0 * sin(ang), 8.0)
		_place_shot_block(
			wm,
			root,
			"arch%d" % i,
			"box",
			pos,
			Vector3(1.4, 1.4, 1.4),
			colors[i % colors.size()],
			"plastic"
		)
	_place_shot_block(
		wm,
		root,
		"stage",
		"box",
		Vector3(16.0, 0.1, 8.0),
		Vector3(16.0, 0.2, 5.0),
		"#37474f",
		"plastic"
	)
	_place_shot_block(
		wm,
		root,
		"pillar_l",
		"cylinder",
		Vector3(9.2, 2.0, 8.0),
		Vector3(0.8, 4.0, 0.8),
		"#ffffff",
		"neon"
	)
	_place_shot_block(
		wm,
		root,
		"pillar_r",
		"cylinder",
		Vector3(22.8, 2.0, 8.0),
		Vector3(0.8, 4.0, 0.8),
		"#ffffff",
		"neon"
	)


func _place_shot_block(
	wm: GDScript,
	root: Node3D,
	id: String,
	shape: String,
	pos: Vector3,
	size: Vector3,
	color: String,
	mat: String
) -> void:
	wm.call(
		"place_block",
		root,
		{
			"id": id,
			"shape": shape,
			"pos": [pos.x, pos.y, pos.z],
			"size": [size.x, size.y, size.z],
			"color": color,
			"mat": mat,
			"anchored": true
		}
	)


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _capture(path: String) -> void:
	var scene := get_tree().current_scene
	if scene != null:
		# Bot NPC & label checkpoint bisa muncul setelah staging —
		# bersihkan sekali lagi tepat sebelum jepret.
		_hide_npc_labels(scene)
		_hide_fps_chip(scene)
		for lb in scene.find_children("*", "Label3D", true, false):
			var l3 := lb as Label3D
			if l3 != null and l3.visible and l3.text.strip_edges().is_valid_int():
				l3.visible = false
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
