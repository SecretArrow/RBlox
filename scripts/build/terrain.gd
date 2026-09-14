extends Node3D
## Terrain — heightmap persegi (default 64x64, tile 1 unit, tinggi 0..8).
## Satu MeshInstance3D: quad per tile + skirt tebing, vertex color per paint
## (grass/dirt/rock/sand), water plane transparan terpisah (tanpa collision),
## collision StaticBody3D + ConcavePolygonShape3D dari mesh.
## Pemakaian: Terrain.build_from(data) -> Node3D; ops: raise/lower/flatten/
## paint; get_height_at(x,z); serialize().

const SCRIPT_PATH := "res://scripts/build/terrain.gd"
const PAINTS: Array[String] = ["grass", "dirt", "rock", "sand"]
const PAINT_COLORS := {
	"grass": Color("#4caf50"),
	"dirt": Color("#795548"),
	"rock": Color("#9e9e9e"),
	"sand": Color("#ffcc80"),
}
const DEFAULT_TERRAIN_SIZE := 64
const MAX_HEIGHT := 8
## Permukaan terrain ditenggelamkan sedikit di bawah ground blok template
## (top y=0) agar tidak koplanar — bebas z-fighting/moiré di semua GPU.
const SURFACE_SINK := 0.05
const WATER_LEVEL := 1.0
const BUILD_RADIUS := 3.0

var terrain_size := DEFAULT_TERRAIN_SIZE
var terrain_seed := 1
var heights: Array = []
var paint_data: Array = []

var _dirty := false
var _surface: MeshInstance3D = null
var _body: StaticBody3D = null
var _water: MeshInstance3D = null


## Factory statis: Node3D + script ini + setup(data) sebelum masuk tree.
static func build_from(data: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Terrain"
	var scr: Variant = load(SCRIPT_PATH)
	if scr is GDScript:
		node.set_script(scr)
		node.call("setup", data)
	return node


func setup(data: Dictionary) -> void:
	terrain_size = clampi(int(data.get("size", DEFAULT_TERRAIN_SIZE)), 8, 256)
	terrain_seed = int(data.get("seed", 1))
	if not _load_heights(data.get("heights", [])):
		_generate_noise()
	_load_paints(data.get("paint", []))
	_rebuild()


# ------------------------------------------------------------------ ops build


func raise(x: float, z: float, r: float = BUILD_RADIUS) -> void:
	_mod_heights(x, z, r, 1)


func lower(x: float, z: float, r: float = BUILD_RADIUS) -> void:
	_mod_heights(x, z, r, -1)


func flatten(x: float, z: float, r: float = BUILD_RADIUS) -> void:
	var target := int(get_height_at(x, z))
	if _for_each_tile(x, z, r, func(idx: int) -> void: heights[idx] = target):
		_dirty = true


func paint(x: float, z: float, r: float = BUILD_RADIUS, mat: String = "grass") -> void:
	if not (mat in PAINTS):
		return
	if _for_each_tile(x, z, r, func(idx: int) -> void: paint_data[idx] = mat):
		_dirty = true


## Tinggi permukaan (y dunia) pada posisi dunia x,z.
func get_height_at(x: float, z: float) -> float:
	var tx := clampi(floori(x), 0, terrain_size - 1)
	var tz := clampi(floori(z), 0, terrain_size - 1)
	var idx := tz * terrain_size + tx
	if idx >= 0 and idx < heights.size():
		return float(heights[idx])
	return 0.0


func serialize() -> Dictionary:
	return {
		"size": terrain_size,
		"seed": terrain_seed,
		"heights": heights.duplicate(),
		"paint": paint_data.duplicate(),
	}


# ------------------------------------------------------------------- internal


func _physics_process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


func _load_heights(raw: Variant) -> bool:
	var arr := _flatten(raw)
	var need := terrain_size * terrain_size
	if arr.size() < need:
		return false
	heights.resize(need)
	for i in need:
		heights[i] = clampi(int(round(float(arr[i]))), 0, MAX_HEIGHT)
	return true


## Noise murah sin/cos ber-seed (0..8) bila data heights tidak valid.
func _generate_noise() -> void:
	var need := terrain_size * terrain_size
	heights.resize(need)
	for z in terrain_size:
		for x in terrain_size:
			var h := (
				2.0
				+ 2.0 * sin(x * 0.35 + terrain_seed)
				+ 2.0 * cos(z * 0.28 + terrain_seed * 1.7)
				+ 1.2 * sin((x + z) * 0.15 + terrain_seed * 0.5)
			)
			heights[z * terrain_size + x] = clampi(int(round(h)), 0, MAX_HEIGHT)


func _load_paints(raw: Variant) -> void:
	var arr := _flatten(raw)
	var need := terrain_size * terrain_size
	paint_data.resize(need)
	for i in need:
		var p := String(arr[i]) if i < arr.size() else "grass"
		paint_data[i] = p if p in PAINTS else "grass"


func _flatten(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for item in raw:
			if item is Array:
				out.append_array(item)
			else:
				out.append(item)
	return out


func _for_each_tile(x: float, z: float, r: float, fn: Callable) -> bool:
	var cx := floori(x)
	var cz := floori(z)
	var ri := ceili(r)
	var changed := false
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if float(dx * dx + dz * dz) > r * r + 0.25:
				continue
			var tx := cx + dx
			var tz := cz + dz
			if tx < 0 or tz < 0 or tx >= terrain_size or tz >= terrain_size:
				continue
			fn.call(tz * terrain_size + tx)
			changed = true
	return changed


func _mod_heights(x: float, z: float, r: float, delta: int) -> void:
	if _for_each_tile(
		x,
		z,
		r,
		func(idx: int) -> void: heights[idx] = clampi(int(heights[idx]) + delta, 0, MAX_HEIGHT)
	):
		_dirty = true


func _paint_at(x: int, z: int) -> String:
	var idx := z * terrain_size + x
	if idx >= 0 and idx < paint_data.size():
		return String(paint_data[idx])
	return "grass"


func _rebuild() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in terrain_size:
		for x in terrain_size:
			var h := float(heights[z * terrain_size + x]) - SURFACE_SINK
			var c: Color = PAINT_COLORS.get(_paint_at(x, z), PAINT_COLORS["grass"])
			var v00 := Vector3(x, h, z)
			var v10 := Vector3(x + 1.0, h, z)
			var v01 := Vector3(x, h, z + 1.0)
			var v11 := Vector3(x + 1.0, h, z + 1.0)
			_add_quad(st, v00, v01, v11, v10, c)
			# Skirt tebing ke tetangga lebih rendah (rim peta turun ke 0).
			var hn := 0.0
			if x + 1 < terrain_size:
				hn = float(heights[z * terrain_size + x + 1]) - SURFACE_SINK
			if hn < h:
				_add_quad(st, v10, v11, Vector3(x + 1.0, hn, z + 1.0), Vector3(x + 1.0, hn, z), c)
			hn = 0.0
			if z + 1 < terrain_size:
				hn = float(heights[(z + 1) * terrain_size + x]) - SURFACE_SINK
			if hn < h:
				_add_quad(st, v01, v11, Vector3(x + 1.0, hn, z + 1.0), Vector3(x, hn, z + 1.0), c)
	var mesh := st.commit()
	if _surface == null:
		_surface = MeshInstance3D.new()
		_surface.name = "Surface"
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_surface.material_override = mat
		add_child(_surface)
	_surface.mesh = mesh
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "TerrainBody"
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		_body.add_child(cs)
		add_child(_body)
	var shape_node := _body.get_child(0) as CollisionShape3D
	if shape_node != null:
		shape_node.shape = mesh.create_trimesh_shape()
	_ensure_water()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.set_color(col)
		st.add_vertex(v)


func _ensure_water() -> void:
	# Air hanya bermakna pada terrain yang di-sculpt (ada sel > 0 untuk
	# menjadi cekungan danau). Dunia flat bawaan (template/sandbox) tidak
	# boleh "banjir" — plane air di y=1 menutupi jalan/plaza kota.
	var has_hill := false
	for h in heights:
		if int(h) > 0:
			has_hill = true
			break
	if _water != null:
		_water.visible = has_hill
		return
	if not has_hill:
		return
	_water = MeshInstance3D.new()
	_water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(terrain_size), float(terrain_size))
	_water.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.25, 0.5, 0.85, 0.55)
	mat.roughness = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.position = Vector3(terrain_size * 0.5, WATER_LEVEL, terrain_size * 0.5)
	add_child(_water)
