extends Node3D
## Weather — clear/rain/fog/snow dengan GPUParticles3D ringan + kilat opsional saat hujan.
## Kontrak API: configure(settings), set_weather(name), cycle_weather(), get_weather().
## Group: "env_weather". Fog diatur via node group "env_day_night" method set_fog_density(d)
## (kompatibel: bila method tidak ada, dilewati).

const ORDER: Array[String] = ["clear", "rain", "fog", "snow"]
const FOG_DENSITY := 0.09
const RAIN_FOG_DENSITY := 0.02
const EMIT_BOX := Vector3(15.0, 10.0, 15.0)  # box emitter 30x20x30

var _weather: String = "clear"
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _bolt: DirectionalLight3D
var _bolt_timer: Timer
var _bolt_tween: Tween
var _player: Node3D


func _ready() -> void:
	add_to_group("env_weather")
	var low_quality := String(Settings.get_value("graphics_quality", "medium")) == "low"
	_rain = _make_particles(
		Color(0.45, 0.62, 1.0, 0.55),
		150 if low_quality else 400,
		Vector3(0.0, -30.0, 0.0),
		Vector2(0.07, 0.6),
		false,
		22.0,
		1.3
	)
	_snow = _make_particles(
		Color(1.0, 1.0, 1.0, 0.9),
		120 if low_quality else 300,
		Vector3(0.0, -2.5, 0.0),
		Vector2(0.18, 0.18),
		true,
		1.5,
		7.0
	)
	add_child(_rain)
	add_child(_snow)

	_bolt = DirectionalLight3D.new()
	_bolt.light_color = Color(0.85, 0.9, 1.0)
	_bolt.light_energy = 0.0
	_bolt.shadow_enabled = false
	add_child(_bolt)

	_bolt_timer = Timer.new()
	_bolt_timer.one_shot = true
	_bolt_timer.timeout.connect(_on_bolt_timer)
	add_child(_bolt_timer)


func configure(settings: Dictionary) -> void:
	set_weather(String(settings.get("weather", "clear")))


func set_weather(name: String) -> void:
	var w := name.to_lower().strip_edges()
	if not ORDER.has(w):
		w = "clear"
	_weather = w
	if _rain != null:
		_rain.emitting = w == "rain"
	if _snow != null:
		_snow.emitting = w == "snow"
	_apply_fog()
	_update_bolt_timer()


func cycle_weather() -> void:
	var idx := ORDER.find(_weather)
	set_weather(ORDER[(idx + 1) % ORDER.size()])


func get_weather() -> String:
	return _weather


func _process(_delta: float) -> void:
	# Emitter mengikuti player lokal (group "local_player"); aman bila belum ada.
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("local_player")
		_player = players[0] as Node3D if players.size() > 0 else null
	if _player != null:
		var top := _player.global_position + Vector3(0.0, 6.0, 0.0)
		if _rain != null:
			_rain.global_position = top
		if _snow != null:
			_snow.global_position = top


func _exit_tree() -> void:
	# Kembalikan fog ke dasar agar tidak membeku saat scene berganti.
	if not is_inside_tree():
		return
	for dn in get_tree().get_nodes_in_group("env_day_night"):
		if dn != null and dn.has_method("set_fog_density"):
			dn.call("set_fog_density", 0.0)


func _make_particles(
	color: Color,
	amount: int,
	gravity: Vector3,
	quad_size: Vector2,
	billboard: bool,
	speed: float,
	lifetime: float
) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = EMIT_BOX
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 4.0
	mat.initial_velocity_min = speed * 0.7
	mat.initial_velocity_max = speed
	mat.gravity = gravity
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = quad_size
	var sm := StandardMaterial3D.new()
	sm.albedo_color = color
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.disable_receive_shadows = true
	if billboard:
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		sm.billboard_keep_scale = true
	mesh.material = sm
	p.draw_pass_1 = mesh
	return p


func _apply_fog() -> void:
	if not is_inside_tree():
		return
	var d := 0.0
	if _weather == "fog":
		d = FOG_DENSITY
	elif _weather == "rain":
		d = RAIN_FOG_DENSITY
	for dn in get_tree().get_nodes_in_group("env_day_night"):
		if dn != null and dn.has_method("set_fog_density"):
			dn.call("set_fog_density", d)


func _update_bolt_timer() -> void:
	if _bolt_timer == null:
		return
	if _weather == "rain" and is_inside_tree():
		_bolt_timer.wait_time = randf_range(3.0, 8.0)
		_bolt_timer.start()
	else:
		_bolt_timer.stop()
		if _bolt != null:
			_bolt.light_energy = 0.0


func _on_bolt_timer() -> void:
	if _weather != "rain":
		return
	_flash()
	_bolt_timer.wait_time = randf_range(3.0, 8.0)
	_bolt_timer.start()


func _flash() -> void:
	if _bolt == null:
		return
	_bolt.rotation_degrees = Vector3(-40.0, randf_range(0.0, 360.0), 0.0)
	if _bolt_tween != null and _bolt_tween.is_valid():
		_bolt_tween.kill()
	_bolt_tween = create_tween()
	_bolt_tween.tween_property(_bolt, "light_energy", 1.6, 0.05)
	_bolt_tween.tween_property(_bolt, "light_energy", 0.15, 0.08)
	_bolt_tween.tween_property(_bolt, "light_energy", 1.1, 0.05)
	_bolt_tween.tween_property(_bolt, "light_energy", 0.0, 0.2)
