extends "res://scripts/world/mode_base.gd"
## Mode Obby — checkpoint dari props (visual beacon); sentuh (jarak < 1.5)
## -> tersimpan sebagai titik respawn. Jatuh di bawah y -12 -> respawn ke
## checkpoint terakhir + damage 10 (bila health_enabled). Interaksi via
## polling jarak di tick (sederhana & aman).

const FALL_Y := -12.0
const CP_RANGE := 1.5
const CP_DAMAGE := 10.0

var _cps: Array = []  # [{pos: Vector3, hit: bool}]
var _current := 0
var _respawn := Vector3.ZERO
var _cd := 0.0


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	_respawn = spawn_point(0) + Vector3(0, 1.0, 0)
	var cps := props_of("checkpoint")
	cps.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	var shown := 0
	for cp in cps:
		var pos := _vec3(cp.get("pos"))
		shown += 1
		prop_marker(pos, "#26c6da", Vector3(1.2, 2.4, 1.2), str(shown))
		_cps.append({"pos": pos, "hit": false})


func tick(delta: float) -> void:
	_cd -= delta
	var p := player()
	if p == null or not (p is Node3D):
		return

		# Jatuh ke kehampaan -> respawn checkpoint + damage ringan
	var pos := (p as Node3D).global_position
	for cp in _cps:
		if bool(cp["hit"]):
			continue
		var cpos: Vector3 = cp["pos"]
		if (
			Vector2(pos.x - cpos.x, pos.z - cpos.z).length() < CP_RANGE
			and absf(pos.y - cpos.y) < 2.5
		):
			cp["hit"] = true
			_current += 1
			_respawn = cpos + Vector3(0, 1.2, 0)
			toast(Locale.t("mode_obby_reach", {"x": _current}))
		# Jatuh ke kehampaan -> respawn checkpoint + damage ringan
	if pos.y < FALL_Y and _cd <= 0.0:
		_cd = 0.6
		respawn_player(_respawn)
		damage_player(CP_DAMAGE)


func get_objective_text() -> String:
	if _cps.is_empty():
		return ""
	return Locale.t("mode_obby_obj", {"x": _current, "y": _cps.size()})


## ---- Save/Resume sesi ----
func session_state() -> Dictionary:
	var hits := []
	for cp in _cps:
		hits.append(bool(cp.get("hit", false)))
	return {
		"current": _current,
		"respawn": [_respawn.x, _respawn.y, _respawn.z],
		"hits": hits,
	}


func restore_session(s: Dictionary) -> void:
	_current = int(s.get("current", 0))
	var r: Variant = s.get("respawn", [])
	if r is Array and (r as Array).size() >= 3:
		_respawn = Vector3(float(r[0]), float(r[1]), float(r[2]))
	var hits: Variant = s.get("hits", [])
	if hits is Array:
		for i in range(mini(_cps.size(), (hits as Array).size())):
			_cps[i]["hit"] = bool(hits[i])
