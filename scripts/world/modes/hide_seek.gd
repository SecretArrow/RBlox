extends "res://scripts/world/mode_base.gd"
## Mode Hide & Seek — fase sembunyi 10 dtk (seeker beku), lalu seeker NPC
## (props seeker, role chase, speed 4) memburu pemain. Tertangkap (jarak
## < 1.5) -> game over. Bertahan 90 dtk -> achievement "hide_master".

const HIDE_TIME := 10.0
const SURVIVE_TIME := 90.0
const CATCH_RANGE := 1.5

var _seeker: Node = null
var _countdown := HIDE_TIME
var _survive := 0.0
var _hiding := true
var _caught := false
var _won := false


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	var spos := spawn_point(0) + Vector3(0, 0.5, -40)
	var seekers := props_of("seeker")
	if not seekers.is_empty():
		spos = _vec3(seekers[0].get("pos"))
	_seeker = spawn_npc(
		"chase",
		spos,
		{
			"speed": 4.0,
			"always": true,
			"name": Locale.t("npc_seeker"),
			"color": "#ff7043",
		}
	)
	_stop_seeker()


func tick(delta: float) -> void:
	if _caught or _won or _seeker == null or not is_instance_valid(_seeker):
		return
	if _hiding:
		_countdown -= delta
		if _countdown <= 0.0:
			_hiding = false
			if _seeker.has_method("set_enabled"):
				_seeker.call("set_enabled", true)
		return
	_survive += delta
	if _survive >= SURVIVE_TIME:
		_won = true
		_stop_seeker()
		GameState.unlock_achievement("hide_master")
		return
	if not player_alive():
		return
	var p := player()
	var s3d := _seeker as Node3D
	if s3d.global_position.distance_to((p as Node3D).global_position) < CATCH_RANGE:
		_caught = true
		_stop_seeker()


func _stop_seeker() -> void:
	if _seeker != null and is_instance_valid(_seeker) and _seeker.has_method("set_enabled"):
		_seeker.call("set_enabled", false)


func get_objective_text() -> String:
	if _caught:
		return Locale.t("mode_caught")
	if _won:
		return Locale.t("mode_survived")
	if _hiding:
		return Locale.t("mode_hidesk_hide", {"n": int(ceil(_countdown))})
	return Locale.t("mode_hidesk_seek", {"n": int(SURVIVE_TIME - _survive)})
