extends "res://scripts/world/mode_base.gd"
## Mode Racing — kart dari props (vehicle_kart.gd, guard); checkpoint urutan
## (polling jarak < 3), timer; semua checkpoint dilewati -> selesai ->
## achievement "win_race" + objective waktu.

const KART_PATH := "res://scripts/world/vehicle_kart.gd"
const CP_RANGE := 3.0

var _cps: Array = []
var _next := 0
var _time := 0.0
var _delay := 1.5
var _finished := false


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	# Spawn kart dari props (guard script vehicle_kart).
	var ks := guard_script(KART_PATH)
	if ks != null:
		for pr in props_of("kart"):
			var kart: Node = ks.new()
			if kart is Node3D:
				var k3d := kart as Node3D
				k3d.position = _vec3(pr.get("pos"))
				var yaw := float(pr.get("yaw", 0.0))
				if yaw != 0.0:
					k3d.rotation_degrees = Vector3(0, yaw, 0)
			if _root != null:
				_root.add_child(kart)
		# Checkpoint urutan (visual pelat neon + nomor).
	var cps := props_of("checkpoint")
	cps.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	var i := 0
	for cp in cps:
		i += 1
		var pos := _vec3(cp.get("pos"))
		prop_marker(pos, "#ffee58", Vector3(3.0, 0.25, 3.0), str(i))
		_cps.append(pos)


func tick(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		return
	if not _finished:
		_time += delta
	if _finished or _cps.is_empty() or player() == null:
		return
	var pos := player_pos()
	var target: Vector3 = _cps[_next]
	if (
		Vector2(pos.x - target.x, pos.z - target.z).length() < CP_RANGE
		and absf(pos.y - target.y) < 3.0
	):
		_next += 1
		if _next >= _cps.size():
			_finished = true
			GameState.unlock_achievement("win_race")


func get_objective_text() -> String:
	if _cps.is_empty():
		return ""
	if _finished:
		return Locale.t("mode_racing_done", {"t": "%.1f" % _time})
	return Locale.t("mode_racing_obj", {"x": _next, "y": _cps.size()})


## ---- Save/Resume sesi ----
func session_state() -> Dictionary:
	return {"next": _next, "time": _time, "finished": _finished}


func restore_session(s: Dictionary) -> void:
	_next = int(s.get("next", 0))
	_time = float(s.get("time", 0.0))
	_finished = bool(s.get("finished", false))
