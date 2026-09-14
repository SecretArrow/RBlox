extends Node
## PolyBudget — penjaga polygon budget agar RBlox stabil 60 FPS di Android.
##
## Mengimplementasikan anggaran tris per kategori objek (mengacu batas aman
## mobile): karakter 2.000-5.000, NPC 1.000-2.500, hero prop 1.500-4.000,
## prop kecil 300-1.000, lingkungan 50-500 per objek, dan total scene yang
## terlihat 100.000-200.000 tris per frame.
##
## API:
##   mesh_tris(mesh) / node_tris(node)  -> hitung tris aktual
##   classify(node)                     -> tebak kategori dari group/nama
##   verdict(category, tris)            -> {level: 0 ok | 1 warn | 2 over, limit}
##   audit(root)                        -> rekap tris per kategori + pelanggar
##   estimate_onscreen_tris()           -> estimasi tris terlihat (chunk MM)
##   register_chunks(mm)                -> MMChunks mendaftar agar dihitung

signal budget_exceeded(category: String, tris: int, limit: int)

## [rekomendasi (warn), maksimum (over)] dalam triangles, per kategori.
const BUDGETS := {
	"avatar": [2000, 5000],
	"npc": [1000, 2500],
	"hero_prop": [1500, 4000],
	"small_prop": [300, 1000],
	"environment": [50, 500],
}

## Batas aman total scene yang terlihat dalam satu frame kamera.
const SCENE_TARGET := 100_000
const SCENE_MAX := 200_000

## Jumlah tris mesh primitif unit RBlox (terukur). HARUS sinkron dengan
## MMChunks._unit_mesh() (diverifikasi otomatis oleh tools/test_budget.gd).
const SHAPE_TRIS := {
	"box": 12,
	"wedge": 8,
	"cylinder": 192,
	"sphere": 288,
}

var onscreen_tris := 0.0  # rata bergerak estimasi tris terlihat
var draw_calls := 0

var _chunks: Array = []
var _warn_cooldown := 0.0


func _process(delta: float) -> void:
	draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var est := 0
	for c in _chunks:
		if is_instance_valid(c):
			est += int(c.call("visible_tris"))
	onscreen_tris = onscreen_tris * 0.85 + float(est) * 0.15
	if onscreen_tris > float(SCENE_MAX):
		_warn_cooldown -= delta
		if _warn_cooldown <= 0.0:
			_warn_cooldown = 10.0
			budget_exceeded.emit("scene", int(onscreen_tris), SCENE_MAX)


# ------------------------------------------------------------ pengukuran --


## Jumlah triangles aktual sebuah Mesh (jumlah semua surface).
static func mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if not idx.is_empty():
			total += idx.size() / 3
		else:
			total += verts.size() / 3
	return total


## Tris yang digambar sebuah node (MeshInstance3D atau MultiMeshInstance3D).
static func node_tris(node: Node) -> int:
	if node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null:
			return mesh_tris(mm.mesh) * mm.instance_count
		return 0
	if node is MeshInstance3D:
		return mesh_tris((node as MeshInstance3D).mesh)
	return 0


## Tebak kategori budget dari group, lalu dari nama node.
static func classify(node: Node) -> String:
	for g in BUDGETS.keys():
		if node.is_in_group(String(g)):
			return String(g)
	var n := node.name.to_lower()
	if n.contains("avatar") or n.contains("player"):
		return "avatar"
	if n.contains("npc") or n.contains("mob") or n.contains("enemy"):
		return "npc"
	return "environment"


## Kebijakan: tris <= rekomendasi = ok (0), <= maksimum = warn (1), else over (2).
static func verdict(category: String, tris: int) -> Dictionary:
	var lim: Array = BUDGETS.get(category, [500, 500])
	if tris <= int(lim[0]):
		return {"level": 0, "limit": int(lim[0])}
	if tris <= int(lim[1]):
		return {"level": 1, "limit": int(lim[1])}
	return {"level": 2, "limit": int(lim[1])}


## Rekap tris seluruh subtree: per kategori + total + daftar pelanggar.
static func audit(root: Node) -> Dictionary:
	var per_cat := {}
	var total := 0
	var offenders: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		var t := node_tris(n)
		if t > 0:
			var cat := classify(n)
			per_cat[cat] = int(per_cat.get(cat, 0)) + t
			total += t
			var v := verdict(cat, t)
			if v["level"] == 2:
				(
					offenders
					. append(
						{
							"node": String(n.name),
							"category": cat,
							"tris": t,
							"limit": v["limit"],
						}
					)
				)
		for c in n.get_children():
			stack.append(c)
	return {"per_category": per_cat, "total": total, "offenders": offenders}


## Estimasi tris terlihat kamera (dari semua chunk MultiMesh terdaftar).
func estimate_onscreen_tris() -> int:
	var t := 0
	for c in _chunks:
		if is_instance_valid(c):
			t += int(c.call("visible_tris"))
	return t


func scene_level(tris: int) -> int:
	if tris <= SCENE_TARGET:
		return 0
	return 1 if tris <= SCENE_MAX else 2


## Dipanggil MMChunks saat siap agar estimasi on-screen menghitung blok.
func register_chunks(mm: Node) -> void:
	if not _chunks.has(mm):
		_chunks.append(mm)


func unregister_chunks(mm: Node) -> void:
	_chunks.erase(mm)
