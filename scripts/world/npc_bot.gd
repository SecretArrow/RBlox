extends CharacterBody3D
## Bot NPC blocky (kontrak 2-e2): badan + kepala box warna per role,
## Label3D nama, bobbing ringan, gravity + step-up kecil (floor snap).
## Peran: wander (radius 8 sekitar spawn) / chase (local+remote player,
## 20 m) / patrol (params.waypoints) / flee (menjauh player < 10 m).
## Alias: villager=wander, zombie/seeker=chase, attacker=patrol.
## Tanpa NavigationAgent — gerak langsung. Pemakaian: set_role() lalu
## add_child. Mati -> sinyal "died" -> queue_free. Group: "npcs".

signal died

const GRAVITY := 12.0
const WANDER_RADIUS := 8.0
const CHASE_RANGE := 20.0
const FLEE_RANGE := 10.0

const ROLE_COLORS := {
	"wander": "#4fc3f7",
	"villager": "#8bc34a",
	"chase": "#e53935",
	"zombie": "#7cb342",
	"seeker": "#ff7043",
	"attacker": "#ef5350",
	"patrol": "#42a5f5",
	"flee": "#ffd54f",
}

const ROLE_SPEEDS := {
	"wander": 1.6,
	"villager": 1.3,
	"chase": 3.5,
	"zombie": 2.6,
	"seeker": 3.0,
	"attacker": 2.2,
	"patrol": 2.2,
	"flee": 3.2,
}

var role := "wander"
var params: Dictionary = {}
var health := 100
var npc_name := "Bot"
var enabled := true

var _speed := 1.6
var _dir := Vector3.ZERO
var _home := Vector3.ZERO
var _waypoints: Array = []
var _wp_index := 0
var _wander_timer := 0.0
var _bob_time := 0.0
var _flash := 0.0
var _pivot: Node3D = null
var _label: Label3D = null
var _mats: Array = []
var _base_cols: Array = []


func _ready() -> void:
	add_to_group("npcs")
	# Layer 3 = NPC; mask: dunia + pemain + NPC. Tanpa navmesh.
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.5
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.6)
	col.shape = box
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	_build_body()
	_home = global_position


func set_role(new_role: String, npc_params: Dictionary = {}) -> void:
	role = new_role
	params = npc_params.duplicate()
	_speed = float(params.get("speed", ROLE_SPEEDS.get(role, 1.6)))
	npc_name = String(params.get("name", npc_name))
	if _label != null:
		_label.text = npc_name
	_waypoints = []
	var wps: Variant = params.get("waypoints", [])
	if wps is Array:
		_set_waypoints(wps)
	var col_str := String(params.get("color", ""))
	if col_str != "":
		_apply_color(Color(col_str))
	else:
		_apply_color(Color(String(ROLE_COLORS.get(role, "#4fc3f7"))))


## Update target patrol saat runtime (mis. kasur terdekat berubah).
func set_waypoints(arr: Array) -> void:
	_set_waypoints(arr)
	_wp_index = 0


func set_enabled(v: bool) -> void:
	enabled = v


func set_display_name(n: String) -> void:
	npc_name = n
	if _label != null:
		_label.text = n


func take_damage(amount: float) -> void:
	if health <= 0:
		return
	health -= int(amount)
	_flash = 0.18
	if health <= 0:
		health = 0
		died.emit()
		queue_free()


func _physics_process(delta: float) -> void:
	if global_position.y < -30.0:
		queue_free()
		return
	var move := Vector3.ZERO
	if enabled:
		match role:
			"chase", "zombie", "seeker":
				move = _behavior_chase()
			"patrol", "attacker":
				move = _behavior_patrol()
			"flee":
				move = _behavior_flee()
			_:
				move = _behavior_wander(delta)
	# Flash merah saat kena damage
	var fc: Color
	if _flash > 0.0:
		_flash -= delta
		fc = Color(1.0, 0.25, 0.25)
	else:
		fc = _base_cols[0] if _base_cols.size() > 0 else Color("#4fc3f7")
	for m in _mats:
		(m as StandardMaterial3D).albedo_color = fc
	# Fisika + step-up kecil via floor snap
	var vel := velocity
	vel.y -= GRAVITY * delta
	vel.x = move.x
	vel.z = move.z
	velocity = vel
	move_and_slide()
	# Hadap arah gerak + bobbing ringan
	if move.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), 8.0 * delta)
		_bob_time += delta
		if _pivot != null:
			_pivot.position.y = absf(sin(_bob_time * 9.0)) * 0.06
	elif _pivot != null:
		_pivot.position.y = 0.0


# ------------------------------------------------------------------ internal

func _build_body() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var defs := [
		[Vector3(0, 0.95, 0), Vector3(0.7, 0.9, 0.45)],
		[Vector3(0, 1.67, 0), Vector3(0.6, 0.55, 0.55)],
		[Vector3(-0.46, 0.95, 0), Vector3(0.22, 0.75, 0.45)],
		[Vector3(0.46, 0.95, 0), Vector3(0.22, 0.75, 0.45)],
		[Vector3(-0.18, 0.36, 0), Vector3(0.3, 0.72, 0.4)],
		[Vector3(0.18, 0.36, 0), Vector3(0.3, 0.72, 0.4)],
	]
	for d in defs:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = d[1]
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(String(ROLE_COLORS.get(role, "#4fc3f7")))
		mi.material_override = mat
		mi.position = d[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pivot.add_child(mi)
		_mats.append(mat)
		_base_cols.append(mat.albedo_color)
	_label = Label3D.new()
	_label.text = npc_name
	_label.position = Vector3(0, 2.25, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 8
	_label.no_depth_test = true
	add_child(_label)


func _apply_color(c: Color) -> void:
	for i in range(_mats.size()):
		_base_cols[i] = c
		(_mats[i] as StandardMaterial3D).albedo_color = c


func _set_waypoints(arr: Array) -> void:
	for wp in arr:
		if wp is Vector3:
			_waypoints.append(wp)
		elif wp is Array and (wp as Array).size() >= 3:
			_waypoints.append(Vector3(float(wp[0]), float(wp[1]), float(wp[2])))


## Target = node terdekat dari group local_player / remote_players.
func _nearest_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for grp in ["local_player", "remote_players"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D and is_instance_valid(n):
				var d: float = global_position.distance_to((n as Node3D).global_position)
				if d < best_d:
					best_d = d
					best = n
	return best


func _behavior_wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.2, 3.0)
		var from_home := Vector2(global_position.x - _home.x, global_position.z - _home.z)
		if randf() < 0.3:
			_dir = Vector3.ZERO
		elif from_home.length() > WANDER_RADIUS:
			_dir = Vector3(-from_home.x, 0.0, -from_home.y).normalized()
		else:
			_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	return _dir * _speed * 0.6


func _behavior_chase() -> Vector3:
	var t := _nearest_target()
	if t == null:
		return _behavior_wander(get_physics_process_delta_time())
	var d3: Vector3 = t.global_position - global_position
	var dist := Vector2(d3.x, d3.z).length()
	var always := bool(params.get("always", false))
	if not always and dist > CHASE_RANGE:
		return _behavior_wander(get_physics_process_delta_time())
	if dist > 1.1:
		_dir = Vector3(d3.x, 0, d3.z).normalized()
		return _dir * _speed
	_dir = Vector3.ZERO
	return Vector3.ZERO


func _behavior_patrol() -> Vector3:
	if _waypoints.is_empty():
		return _behavior_wander(get_physics_process_delta_time())
	var wp: Vector3 = _waypoints[_wp_index % _waypoints.size()]
	var d3: Vector3 = wp - global_position
	if Vector2(d3.x, d3.z).length() < 0.9:
		_wp_index = (_wp_index + 1) % _waypoints.size()
		return Vector3.ZERO
	_dir = Vector3(d3.x, 0, d3.z).normalized()
	return _dir * _speed


func _behavior_flee() -> Vector3:
	var t := _nearest_target()
	if t == null:
		return _behavior_wander(get_physics_process_delta_time())
	var d3: Vector3 = global_position - t.global_position
	if Vector2(d3.x, d3.z).length() < FLEE_RANGE:
		_dir = Vector3(d3.x, 0, d3.z).normalized()
		return _dir * _speed
	return _behavior_wander(get_physics_process_delta_time())
