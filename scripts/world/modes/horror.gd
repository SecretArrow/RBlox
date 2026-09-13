extends "res://scripts/world/mode_base.gd"
## Mode Horror — kumpulkan semua sekring dari props fuse (jarak < 2), lalu
## exit aktif; sentuh exit -> achievement "horror_escape". NPC penjaga
## (chase, speed 2.8) menyentuh pemain (jarak < 1.2) -> damage 20.

const PICK_RANGE := 2.0
const GUARD_HIT_RANGE := 1.2
const GUARD_DAMAGE := 20.0

var _fuses: Array = []  # [{pos: Vector3, hit: bool}]
var _exit := Vector3.ZERO
var _has_exit := false
var _count := 0
var _escaped := false
var _hit_cd := 0.0
var _guard: Node = null


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	var fuses := props_of("fuse")
	fuses.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	for f in fuses:
		var pos := _vec3(f.get("pos"))
		prop_marker(pos, "#4dd0e1", Vector3(0.5, 0.5, 0.5))
		_fuses.append({"pos": pos, "hit": false})
	var exits := props_of("exit")
	if not exits.is_empty():
		_exit = _vec3(exits[0].get("pos"))
		_has_exit = true
		prop_marker(_exit, "#66bb6a", Vector3(1.2, 2.6, 0.4), Locale.t("mode_horror_exitname"))
	# Satu penjaga yang mengejar terus.
	_guard = spawn_npc(
		"chase",
		spawn_point(0) + Vector3(0, 0.5, -6),
		{
			"speed": 2.8,
			"always": true,
			"name": Locale.t("npc_guard"),
			"color": "#5c6bc0",
		}
	)


func tick(delta: float) -> void:
	_hit_cd -= delta
	if not player_alive():
		return
	var pos := player_pos()
	for f in _fuses:
		if bool(f["hit"]):
			continue
		var fpos: Vector3 = f["pos"]
		if pos.distance_to(fpos) < PICK_RANGE:
			f["hit"] = true
			_count += 1
			toast(Locale.t("mode_horror_fuse", {"x": _count, "y": _fuses.size()}))
	var all_fuses := not _fuses.is_empty() and _count >= _fuses.size()
	if all_fuses and _has_exit and not _escaped:
		if pos.distance_to(_exit) < PICK_RANGE:
			_escaped = true
			GameState.unlock_achievement("horror_escape")
	# Sentuhan penjaga -> damage
	if _hit_cd <= 0.0 and _guard != null and is_instance_valid(_guard):
		var g3d := _guard as Node3D
		if g3d.global_position.distance_to(pos) < GUARD_HIT_RANGE:
			_hit_cd = 0.8
			damage_player(GUARD_DAMAGE)


func get_objective_text() -> String:
	if _escaped:
		return Locale.t("mode_horror_done")
	if not _fuses.is_empty() and _count >= _fuses.size():
		return Locale.t("mode_horror_exit")
	if _fuses.is_empty():
		return ""
	return Locale.t("mode_horror_obj", {"x": _count, "y": _fuses.size()})
