extends RefCounted
## BlockLibrary — katalog statis bentuk, material & warna blok RBlox.
## Pemakaian: const BlockLibrary := preload("res://scripts/build/block_library.gd")
## Shape: box/sphere/cylinder/wedge. Material: plastic/metal/wood/glass/neon.
## Semua mesh dibuat di pusat (0,0,0) dengan ukuran (size) penuh.

const SHAPES: Array[String] = ["box", "sphere", "cylinder", "wedge"]
const MATERIALS: Array[String] = ["plastic", "metal", "wood", "glass", "neon"]
const DEFAULT_COLOR := "#e0453a"
const DEFAULT_SIZE := Vector3(1.0, 1.0, 1.0)

## Palet 24 warna hex (brick-style: merah..oranye..netral gelap).
const COLORS: Array[String] = [
	"#e0453a",
	"#ff7f27",
	"#ffb300",
	"#ffe23d",
	"#c8e04a",
	"#4caf50",
	"#2e9e6b",
	"#26c6da",
	"#4fc3f7",
	"#3b7bff",
	"#3f51b5",
	"#7e57c2",
	"#ab47bc",
	"#e91e63",
	"#f48fb1",
	"#ffcc80",
	"#d7a86e",
	"#8d6e63",
	"#5d4037",
	"#b0b0b0",
	"#607d8b",
	"#37474f",
	"#1b1b1b",
	"#f5f5f5",
]


static func is_valid_shape(shape: String) -> bool:
	return shape in SHAPES


static func is_valid_material(mat: String) -> bool:
	return mat in MATERIALS


## Ukuran default blok per bentuk (Kubus 1 unit, gaya part klasik).
static func default_size(shape: String) -> Vector3:
	return DEFAULT_SIZE


## Mesh untuk satu blok. size kosong -> default_size(shape).
static func make_mesh(shape: String, size: Vector3 = Vector3.ZERO) -> Mesh:
	var s := size
	if s == Vector3.ZERO:
		s = default_size(shape)
	var radius := minf(s.x, s.z) * 0.5
	match shape:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = radius
			sm.height = s.y
			sm.radial_segments = 24
			sm.rings = 12
			return sm
		"cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = radius
			cm.bottom_radius = radius
			cm.height = s.y
			cm.radial_segments = 24
			return cm
		"wedge":
			var pm := PrismMesh.new()
			pm.size = s
			return pm
		_:
			var bm := BoxMesh.new()
			bm.size = s
			return bm


## Material fisik per jenis + warna hex.
static func make_material(mat: String, color: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var col := parse_color(color)
	m.albedo_color = col
	match mat:
		"metal":
			m.metallic = 0.9
			m.roughness = 0.3
		"wood":
			m.roughness = 0.95
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(col.r, col.g, col.b, 0.4)
			m.roughness = 0.1
			m.metallic = 0.1
		"neon":
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 2.5
		_:
			m.roughness = 0.8
	return m


## CollisionShape sesuai bentuk; wedge memakai ConvexPolygonShape3D.
static func make_collision(shape: String, size: Vector3 = Vector3.ZERO) -> Shape3D:
	var s := size
	if s == Vector3.ZERO:
		s = default_size(shape)
	var radius := minf(s.x, s.z) * 0.5
	match shape:
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = radius
			return sp
		"cylinder":
			var cy := CylinderShape3D.new()
			cy.radius = radius
			cy.height = s.y
			return cy
		"wedge":
			var hx := s.x * 0.5
			var hy := s.y * 0.5
			var hz := s.z * 0.5
			var cp := ConvexPolygonShape3D.new()
			cp.points = PackedVector3Array(
				[
					Vector3(-hx, -hy, -hz),
					Vector3(hx, -hy, -hz),
					Vector3(-hx, -hy, hz),
					Vector3(hx, -hy, hz),
					Vector3(0.0, hy, -hz),
					Vector3(0.0, hy, hz),
				]
			)
			return cp
		_:
			var bx := BoxShape3D.new()
			bx.size = s
			return bx


## Parse hex aman ("#rrggbb"); fallback DEFAULT_COLOR bila tidak valid.
static func parse_color(hex: String) -> Color:
	var h := hex.strip_edges()
	if h.is_empty():
		h = DEFAULT_COLOR
	if not h.begins_with("#"):
		h = "#" + h
	if not Color.html_is_valid(h):
		h = DEFAULT_COLOR
	return Color(h)
