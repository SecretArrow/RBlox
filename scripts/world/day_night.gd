extends Node3D
## Day/Night — siklus siang-malam: DirectionalLight3D berputar mengikuti jam +
## WorldEnvironment (BG_SKY + ProceduralSkyMaterial, ambient dari sky, fog opsional).
## Kontrak: game.gd memanggil configure(settings: Dictionary).
## Sinyal hour_changed(hour) diemit saat jam bulat berganti. Group: "env_day_night".
## set_fog_density(d) dipakai modul cuaca (dipanggil lewat group, aman bila absen).

signal hour_changed(hour: int)

const NIGHT := Color("#0a0e1a")
const DAWN := Color("#ff9a5a")
const DAY := Color("#8ec9ff")
const DUSK := Color("#ff7a3c")

var enabled: bool = true
var cycle_minutes: float = 10.0
var hour: float = 8.0

var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _fog_base: float = 0.0
var _last_hour: int = 8


func _ready() -> void:
	add_to_group("env_day_night")
	_build()
	_apply_time()


func configure(settings: Dictionary) -> void:
	enabled = bool(settings.get("day_night", true))
	var minutes := float(settings.get("cycle_minutes", 10.0))
	cycle_minutes = minutes if minutes > 0.0 else 10.0
	_fog_base = clampf(float(settings.get("fog_density", 0.0)), 0.0, 0.5)
	set_fog_density(0.0)
	_apply_time()


func set_time(h: float) -> void:
	hour = fposmod(h, 24.0)
	_last_hour = int(floor(hour)) % 24
	_apply_time()


func get_time() -> float:
	return hour


func set_fog_density(d: float) -> void:
	if _env == null:
		return
	var density := maxf(_fog_base, maxf(d, 0.0))
	_env.fog_density = density
	_env.fog_enabled = density > 0.0005


func _process(delta: float) -> void:
	if not enabled:
		return
	var speed := 24.0 / maxf(cycle_minutes * 60.0, 1.0)
	hour = fposmod(hour + delta * speed, 24.0)
	_apply_time()


func _build() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = DAY
	_sky_mat.sky_horizon_color = DAY.lightened(0.25)
	_sky_mat.ground_horizon_color = DAY.lightened(0.15)
	_sky_mat.ground_bottom_color = NIGHT.darkened(0.2)

	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.ambient_light_energy = 1.0
	_env.fog_enabled = false
	_env.fog_density = 0.0

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	add_child(_sun)

	if String(Settings.get_value("graphics_quality", "medium")) == "low":
		_sun.shadow_enabled = false


func _apply_time() -> void:
	# Elevasi matahari sinusoidal: 06.00 = 0 (horizon), 12.00 = 90 (zenit).
	var elev := sin((hour - 6.0) * TAU / 24.0) * 90.0
	var day_factor := clampf(sin(deg_to_rad(elev)), 0.0, 1.0)
	if _sun != null:
		_sun.rotation_degrees = Vector3(-elev, 0.0, 0.0)
		_sun.light_energy = lerpf(0.05, 1.2, day_factor)
		var warm := clampf(1.0 - absf(elev) / 30.0, 0.0, 1.0)
		_sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.62, 0.38), warm)
	var col := _sky_color(hour)
	if _sky_mat != null:
		_sky_mat.sky_top_color = col
		_sky_mat.sky_horizon_color = col.lightened(0.3)
		_sky_mat.ground_horizon_color = col.lightened(0.15)
		_sky_mat.ground_bottom_color = col.darkened(0.55)
	var h := int(floor(hour)) % 24
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)


func _sky_color(h: float) -> Color:
	var keys := [0.0, 5.0, 6.5, 8.0, 16.5, 18.0, 19.5, 24.0]
	var cols := [NIGHT, NIGHT, DAWN, DAY, DAY, DUSK, NIGHT, NIGHT]
	for i in range(keys.size() - 1):
		if h >= float(keys[i]) and h <= float(keys[i + 1]):
			var t := (h - float(keys[i])) / maxf(float(keys[i + 1]) - float(keys[i]), 0.001)
			return (cols[i] as Color).lerp(cols[i + 1] as Color, t)
	return NIGHT
