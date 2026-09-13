extends Control
## Minimap 160x160 — gambar player lokal (segitiga kuning menghadap yaw),
## pemain remote group "remote_players" (putih), NPC group "npcs" (merah),
## spawn point dunia aktif (hijau). Skala default 1px = 2m. Konten di-clip.

const MAP_SIZE := 160.0
const DEFAULT_SPAN_M := 320.0  # 160px / 320m = 1px = 2m
const REDRAW_INTERVAL := 0.12

var _span_m: float = DEFAULT_SPAN_M
var _player: Node3D
var _accum: float = 0.0
var _bg_box: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	size = Vector2(MAP_SIZE, MAP_SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_box = StyleBoxFlat.new()
	_bg_box.bg_color = Color(0.04, 0.05, 0.09, 0.7)
	_bg_box.set_corner_radius_all(10)
	_bg_box.set_border_width_all(1)
	_bg_box.border_color = Color(1.0, 1.0, 1.0, 0.25)


func set_range(m: float) -> void:
	# Lebar peta dalam meter (span penuh horizontal).
	_span_m = clampf(m, 40.0, 2000.0)
	queue_redraw()


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REDRAW_INTERVAL:
		_accum = 0.0
		queue_redraw()


func _px_per_m() -> float:
	return size.x / _span_m


func _draw() -> void:
	if _bg_box == null:
		_bg_box = StyleBoxFlat.new()
	draw_style_box(_bg_box, Rect2(Vector2.ZERO, size))

	var center := size * 0.5
	var locals := get_tree().get_nodes_in_group("local_player")
	_player = null
	if locals.size() > 0:
		_player = locals[0] as Node3D
	var cpos := _player.global_position if _player != null else Vector3.ZERO
	var ppm := _px_per_m()
	var font := ThemeDB.fallback_font

	# Penanda arah utara.
	draw_string(
		font,
		Vector2(center.x - 8.0, 14.0),
		"N",
		HORIZONTAL_ALIGNMENT_CENTER,
		16.0,
		12,
		Color(1.0, 1.0, 1.0, 0.75)
	)

	# Spawn point dunia aktif (hijau).
	var cw: Variant = GameState.current_world
	if typeof(cw) == TYPE_DICTIONARY:
		var spawns: Variant = cw.get("spawn_points", [])
		if spawns is Array:
			for sp in spawns:
				if sp is Array and sp.size() >= 3:
					var p := _to_map(Vector3(float(sp[0]), float(sp[1]), float(sp[2])), cpos, ppm)
					draw_rect(
						Rect2(p - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
						Color(0.3, 0.85, 0.4, 0.9),
						false,
						1.5
					)

	# NPC (merah) dan pemain remote (putih).
	_draw_group(get_tree().get_nodes_in_group("npcs"), cpos, ppm, Color(0.95, 0.3, 0.3))
	_draw_group(
		get_tree().get_nodes_in_group("remote_players"), cpos, ppm, Color(1.0, 1.0, 1.0, 0.95)
	)

	# Player lokal: segitiga kuning menghadap yaw.
	if _player != null:
		var yaw: float = _player.rotation.y
		if "yaw" in _player:
			yaw = float(_player.get("yaw"))
		_draw_triangle(center, yaw)


func _draw_group(nodes: Array, cpos: Vector3, ppm: float, color: Color) -> void:
	for n in nodes:
		if n is Node3D and n != _player:
			var p := _to_map((n as Node3D).global_position, cpos, ppm)
			draw_circle(p, 3.5, color)


func _draw_triangle(center: Vector2, yaw: float) -> void:
	var a := -yaw
	var c := cos(a)
	var s := sin(a)
	var pts := PackedVector2Array()
	for v in [Vector2(0.0, -7.0), Vector2(5.0, 5.0), Vector2(-5.0, 5.0)]:
		pts.append(center + Vector2(v.x * c - v.y * s, v.x * s + v.y * c))
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.2))


func _to_map(world_pos: Vector3, cpos: Vector3, ppm: float) -> Vector2:
	return Vector2(
		size.x * 0.5 + (world_pos.x - cpos.x) * ppm, size.y * 0.5 + (world_pos.z - cpos.z) * ppm
	)
