extends VehicleBody3D
## Kart kendaraan 4 roda (kontrak 2-e2). Body box 1.6x0.4x2.4 + 4
## VehicleWheel3D radius 0.3 (depan use_as_steering, belakang
## use_as_traction). Seat = Area3D marker; interaksi pakai polling jarak
## (< 3 m) — Label3D "kart_enter" tampil saat pemain dekat.
## Masuk: action_a -> kontrol pemain dimatikan (set_physics_process false,
## collision off, hidden; state disimpan) & kamera mengikuti kart lewat
## posisi pemain yang di-ikat tiap frame. Keluar: action_a lagi saat
## speed < 2 -> kontrol dikembalikan. Guard player null. Group: "vehicles".

signal player_entered
signal player_exited

const ENTER_RANGE := 3.0
const EXIT_SPEED := 2.0
const ENGINE_POWER := 80.0
const STEER_MAX := 0.4
const WHEEL_RADIUS := 0.3
const RIDER_OFFSET := Vector3(0, 1.05, 0)

var driver: Node = null

var _hint: Label3D = null
var _near: Node3D = null
var _saved_layer := 0
var _saved_mask := 0


func _ready() -> void:
	add_to_group("vehicles")
	mass = 60.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.3, 0)
	collision_layer = 1
	collision_mask = 1 | 2 | 4
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.6, 2.4)
	col.shape = box
	col.position = Vector3(0, 0.45, 0)
	add_child(col)
	_build_visuals()
	_make_seat()
	_make_wheel(Vector3(-0.72, 0.15, -0.95), true, false)
	_make_wheel(Vector3(0.72, 0.15, -0.95), true, false)
	_make_wheel(Vector3(-0.72, 0.15, 0.95), false, true)
	_make_wheel(Vector3(0.72, 0.15, 0.95), false, true)
	_hint = Label3D.new()
	_hint.text = Locale.t("kart_enter")
	_hint.position = Vector3(0, 1.7, 0)
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.font_size = 36
	_hint.pixel_size = 0.006
	_hint.outline_size = 8
	_hint.no_depth_test = true
	_hint.visible = false
	add_child(_hint)


func is_driven() -> bool:
	return driver != null


func _physics_process(_delta: float) -> void:
	if driver != null and not is_instance_valid(driver):
		_detach_driver(global_position + Vector3(0, 1.0, 0))
		driver = null
	if driver == null:
		engine_force = 0.0
		brake = 1.2
		steering = move_toward(steering, 0.0, 0.02)
		_near = _find_near_player()
		if _hint != null:
			_hint.visible = _near != null
		if _near != null and _action_just_pressed():
			_attach_driver(_near)
	else:
		if _hint != null:
			_hint.visible = false
		var mv := _move_vector()
		engine_force = -mv.y * ENGINE_POWER
		steering = -mv.x * STEER_MAX
		brake = 0.8 if absf(mv.y) < 0.05 else 0.0
		if _action_just_pressed() and linear_velocity.length() < EXIT_SPEED:
			var exit_at := global_position + global_basis.x * 1.8 + Vector3(0, 0.6, 0)
			_detach_driver(exit_at)
			driver = null
			return
		# Kamera ikat kart: pemain (dgn camera rig-nya) diikat ke kart.
		if driver is Node3D:
			(driver as Node3D).global_position = global_position + RIDER_OFFSET


# ------------------------------------------------------------------ internal


func _build_visuals() -> void:
	var body_mi := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.6, 0.4, 2.4)
	body_mi.mesh = body_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#e53935")
	body_mi.material_override = mat
	body_mi.position = Vector3(0, 0.45, 0)
	body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body_mi)
	var cab_mi := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = Vector3(1.1, 0.35, 1.0)
	cab_mi.mesh = cab_mesh
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color("#b71c1c")
	cab_mi.material_override = mat2
	cab_mi.position = Vector3(0, 0.82, 0.15)
	cab_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cab_mi)


func _make_seat() -> void:
	# Marker dudukan (Area3D); logika masuk pakai polling jarak.
	var seat := Area3D.new()
	seat.name = "Seat"
	seat.monitoring = false
	seat.monitorable = false
	seat.collision_layer = 0
	seat.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 1.0
	cs.shape = shape
	cs.position = Vector3(0, 0.95, 0.1)
	seat.add_child(cs)
	add_child(seat)


func _make_wheel(pos: Vector3, steer: bool, traction: bool) -> VehicleWheel3D:
	var w := VehicleWheel3D.new()
	w.position = pos
	w.wheel_radius = WHEEL_RADIUS
	w.wheel_rest_length = 0.25
	w.wheel_friction_slip = 3.0
	w.suspension_travel = 0.2
	w.suspension_stiffness = 35.0
	w.damping_compression = 3.0
	w.damping_relaxation = 4.0
	w.use_as_steering = steer
	w.use_as_traction = traction
	add_child(w)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = WHEEL_RADIUS
	mesh.bottom_radius = WHEEL_RADIUS
	mesh.height = 0.22
	mi.mesh = mesh
	mi.rotation_degrees = Vector3(0, 0, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#212121")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	return w


func _find_near_player() -> Node3D:
	var best: Node3D = null
	var best_d := ENTER_RANGE
	for n in get_tree().get_nodes_in_group("local_player"):
		if n is Node3D and is_instance_valid(n):
			var p3d := n as Node3D
			var flat := (
				Vector2(
					p3d.global_position.x - global_position.x,
					p3d.global_position.z - global_position.z
				)
				. length()
			)
			if flat < best_d and absf(p3d.global_position.y - global_position.y) < 3.0:
				best_d = flat
				best = p3d
	return best


func _attach_driver(p: Node) -> void:
	driver = p
	_saved_layer = int(p.get("collision_layer"))
	_saved_mask = int(p.get("collision_mask"))
	p.set("collision_layer", 0)
	p.set("collision_mask", 0)
	p.set("visible", false)
	p.set_physics_process(false)
	player_entered.emit()


func _detach_driver(at: Vector3) -> void:
	if driver != null and is_instance_valid(driver):
		driver.set_physics_process(true)
		driver.set("collision_layer", _saved_layer)
		driver.set("collision_mask", _saved_mask)
		driver.set("visible", true)
		if driver is Node3D:
			(driver as Node3D).global_position = at
		if driver is CharacterBody3D:
			(driver as CharacterBody3D).velocity = Vector3.ZERO
	player_exited.emit()


## Guard InputMap (mode_base mendaftarkan action runtime bila belum ada).
func _action_just_pressed() -> bool:
	return InputMap.has_action("action_a") and Input.is_action_just_pressed("action_a")


func _move_vector() -> Vector2:
	if not InputMap.has_action("move_left"):
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")
