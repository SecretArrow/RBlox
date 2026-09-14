extends "res://scripts/world/mode_base.gd"
## Mode Bed Wars (SP) — lindungi kasur tim 0. Satu NPC penyerang aktif
## (maks 1 hidup): mengejar kasur terdekat (waypoints di-update tiap 0.5 s)
## dan merusaknya lewat jarak (HP 100, 10/dtk). Kasur tim 0 hancur -> kalah.
## Pemain mati & kasur tim 0 hidup -> respawn di kasur.

const BED_MAX_HP := 100.0
const BED_DPS := 10.0
const ATTACKER_INTERVAL := 12.0
const BED_HIT_RANGE := 2.2
const PLAYER_HIT_RANGE := 1.3

var _beds: Array = []  # [{pos, team, hp, alive}]
var _attacker: Node = null
var _spawn_cd := 6.0
var _over := false
var _hit_cd := 0.0
var _respawn_cd := 0.0
var _target_cd := 0.0


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	for pr in props_of("bed"):
		var team := int(pr.get("team", 0))
		var pos := _vec3(pr.get("pos"))
		var col := "#ef5350" if team == 0 else "#29b6f6"
		prop_marker(pos, col, Vector3(2.0, 0.5, 1.2))
		_beds.append({"pos": pos, "team": team, "hp": BED_MAX_HP, "alive": true})
	var p := player()
	if p != null and p.has_signal("died"):
		if not p.died.is_connected(_on_player_died):
			p.died.connect(_on_player_died)


func _on_player_died() -> void:
	_respawn_cd = 1.2


func tick(delta: float) -> void:
	_hit_cd -= delta
	_target_cd -= delta
	if _respawn_cd > 0.0:
		_respawn_cd -= delta
		if _respawn_cd <= 0.0:
			var home: Dictionary = _home_bed()
			if not home.is_empty() and bool(home["alive"]):
				respawn_player(Vector3(home["pos"]) + Vector3(0, 1.2, 0))

		# Spawn penyerang berkala (maks 1 hidup).

		# Kejar kasur terdekat: perbarui waypoint NPC.

		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	if _over:
		return

		# Spawn penyerang berkala (maks 1 hidup).

		# Kejar kasur terdekat: perbarui waypoint NPC.

		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	if _attacker != null and not is_instance_valid(_attacker):
		_attacker = null
		# Spawn penyerang berkala (maks 1 hidup).

		# Kejar kasur terdekat: perbarui waypoint NPC.

		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and _attacker == null:
		_spawn_cd = ATTACKER_INTERVAL
		_spawn_attacker()

		# Kejar kasur terdekat: perbarui waypoint NPC.

		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	if _attacker == null:
		return

		# Kejar kasur terdekat: perbarui waypoint NPC.

		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	var a3d := _attacker as Node3D
	var bed := _nearest_alive_bed(a3d.global_position)
	if bed.is_empty():
		return

		# Kejar kasur terdekat: perbarui waypoint NPC.

		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	var bpos: Vector3 = bed["pos"]
	# Kejar kasur terdekat: perbarui waypoint NPC.
	if _target_cd <= 0.0 and _attacker.has_method("set_waypoints"):
		_attacker.call("set_waypoints", [bpos])
		_target_cd = 0.5
		# Rusak kasur lewat jarak.

		# Damage kontak ke pemain.
	if (
		Vector2(a3d.global_position.x - bpos.x, a3d.global_position.z - bpos.z).length()
		< BED_HIT_RANGE
	):
		bed["hp"] = float(bed["hp"]) - BED_DPS * delta
		if float(bed["hp"]) <= 0.0:
			bed["alive"] = false
			bed["hp"] = 0.0
			if int(bed["team"]) == 0:
				_over = true
				toast(Locale.t("mode_bedwars_lost"))
		# Damage kontak ke pemain.
	if _hit_cd <= 0.0 and player_alive():
		var ppos := player_pos()
		if (
			Vector2(a3d.global_position.x - ppos.x, a3d.global_position.z - ppos.z).length()
			< PLAYER_HIT_RANGE
		):
			_hit_cd = 1.0
			damage_player(6.0)


func _spawn_attacker() -> void:
	# Turun di pulau tengah lalu berjalan ke kasur terdekat.
	var npc := spawn_npc(
		"attacker",
		Vector3(0, 0.8, 0),
		{
			"speed": 2.2,
			"name": Locale.t("npc_attacker"),
			"color": "#ef5350",
		}
	)
	if npc != null:
		_attacker = npc


func _home_bed() -> Dictionary:
	for b in _beds:
		if int(b["team"]) == 0:
			return b
	if _beds.is_empty():
		return {}
	return _beds[0]


func _nearest_alive_bed(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for b in _beds:
		if not bool(b["alive"]):
			continue
		var d: float = from.distance_to(Vector3(b["pos"]))
		if d < best_d:
			best_d = d
			best = b
	return best


func get_objective_text() -> String:
	if _over:
		return Locale.t("mode_bedwars_lost")
	var home := _home_bed()
	if home.is_empty():
		return ""
	return Locale.t("mode_bedwars_obj", {"n": int(float(home["hp"]))})


## ---- Save/Resume sesi ----
func session_state() -> Dictionary:
	var beds := []
	for b in _beds:
		beds.append([float(b.get("hp", 100.0)), bool(b.get("alive", true))])
	return {"beds": beds, "over": _over}


func restore_session(s: Dictionary) -> void:
	_over = bool(s.get("over", false))
	var beds: Variant = s.get("beds", [])
	if beds is Array:
		for i in range(mini(_beds.size(), (beds as Array).size())):
			var e: Variant = beds[i]
			if e is Array and (e as Array).size() >= 2:
				_beds[i]["hp"] = float(e[0])
				_beds[i]["alive"] = bool(e[1])
