extends "res://scripts/world/mode_base.gd"
## Mode Survival — mendengar hour_changed (group "env_day_night").
## Jam 20-04: spawn zombie (role chase, maks 8 hidup, interval 4 dtk) dari
## props zombie_spawner. Jam 5: bersihkan zombie + wave++. Kontak zombie
## (jarak < 1.4) -> damage pemain.

const MAX_ZOMBIES := 8
const SPAWN_INTERVAL := 4.0
const HIT_RANGE := 1.4
const HIT_DAMAGE := 8.0

var _zombies: Array = []
var _spawners: Array = []
var _wave := 1
var _night := false
var _connected := false
var _spawn_cd := 2.0
var _hit_cd := 0.0
var _spawner_idx := 0


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	for pr in props_of("zombie_spawner"):
		_spawners.append(_vec3(pr.get("pos")))
	if _spawners.is_empty():
		# Fallback: lingkaran di sekitar spawn.
		var c := spawn_point(0)
		for i in range(5):
			var a := TAU * float(i) / 5.0
			_spawners.append(c + Vector3(cos(a) * 24.0, 0.5, sin(a) * 24.0))


## env dibuat game.gd SETELAH mode -> sambungkan di tick pertama.
func _connect_env() -> void:
	if _connected:
		return
	for n in get_tree().get_nodes_in_group("env_day_night"):
		if n != null and n.has_signal("hour_changed"):
			if not n.hour_changed.is_connected(_on_hour_changed):
				n.hour_changed.connect(_on_hour_changed)
			_connected = true
			break


func _on_hour_changed(hour_v: Variant) -> void:
	var hour := int(hour_v) % 24
	_night = hour >= 20 or hour < 4
	if hour == 5:
		# Pagi hari: bersihkan zombie, gelombang berikutnya.
		_clear_zombies()
		_wave += 1


func tick(delta: float) -> void:
	_connect_env()
	_hit_cd -= delta
	if _night:
		_spawn_cd -= delta
		if _spawn_cd <= 0.0 and _alive_zombies() < MAX_ZOMBIES:
			_spawn_cd = SPAWN_INTERVAL
			_spawn_zombie()
	else:
		_spawn_cd = 2.0
	if not player_alive():
		return
	var ppos := player_pos()
	if _hit_cd <= 0.0:
		for z in _zombies:
			if not is_instance_valid(z):
				continue
			var z3d := z as Node3D
			if (
				Vector2(z3d.global_position.x - ppos.x, z3d.global_position.z - ppos.z).length()
				< HIT_RANGE
			):
				_hit_cd = 0.9
				damage_player(HIT_DAMAGE)
				break
	_zombies = _zombies.filter(func(z): return is_instance_valid(z))


func _alive_zombies() -> int:
	var n := 0
	for z in _zombies:
		if is_instance_valid(z):
			n += 1
	return n


func _spawn_zombie() -> void:
	var base: Vector3 = _spawners[_spawner_idx % _spawners.size()]
	_spawner_idx += 1
	var pos := base + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
	var npc := spawn_npc("chase", pos, {"speed": 2.6, "name": "Zombie", "color": "#7cb342"})
	if npc != null:
		_zombies.append(npc)


func _clear_zombies() -> void:
	for z in _zombies:
		if is_instance_valid(z):
			z.queue_free()
	_zombies.clear()


func get_objective_text() -> String:
	return Locale.t("mode_survival_obj", {"n": _wave})
