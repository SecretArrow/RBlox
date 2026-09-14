extends Node
## Uji fungsional PolyBudget (headless, dijalankan CI):
##  1. Tris primitif unit = SHAPE_TRIS (sinkron dengan MMChunks._unit_mesh)
##  2. node_tris untuk MeshInstance3D & MultiMeshInstance3D
##  3. classify + audit pohon scene
##  4. Verdict kategori (ok/warn/over) dan batas scene 100k/200k

const MMChunks := preload("res://scripts/world/mm_chunks.gd")


func _ready() -> void:
	var failures: Array[String] = []

	# 1. Tris primitif unit (harus sama dengan tabel SHAPE_TRIS).
	var shapes := {"box": 12, "wedge": 8, "cylinder": 192, "sphere": 288}
	for shape in shapes.keys():
		var mesh := MMChunks._unit_mesh(String(shape))
		var got := PolyBudget.mesh_tris(mesh)
		if got != int(shapes[shape]):
			failures.append("%s tris %d != %d" % [shape, got, int(shapes[shape])])
		var cst: int = PolyBudget.SHAPE_TRIS.get(shape, -1)
		if cst != int(shapes[shape]):
			failures.append("SHAPE_TRIS[%s]=%d != %d" % [shape, cst, int(shapes[shape])])

		# 2. node_tris MeshInstance3D & MultiMeshInstance3D.

		# 3. classify + audit pohon (mi di-group npc, mmi -> environment).

		# 4. Verdict kategori avatar (warn 2000, over 5000) dan batas scene.
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.add_to_group("npc")
	add_child(mi)
	if PolyBudget.node_tris(mi) != 12:
		failures.append("MeshInstance3D box tris != 12")

		# 3. classify + audit pohon (mi di-group npc, mmi -> environment).

		# 4. Verdict kategori avatar (warn 2000, over 5000) dan batas scene.
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 7
	mmi.multimesh = mm
	add_child(mmi)
	if PolyBudget.node_tris(mmi) != 84:
		failures.append("MultiMesh 7 box tris != 84")

		# 3. classify + audit pohon (mi di-group npc, mmi -> environment).

		# 4. Verdict kategori avatar (warn 2000, over 5000) dan batas scene.
	var rep := PolyBudget.audit(self)
	if int(rep["per_category"].get("npc", 0)) != 12:
		failures.append("audit npc %s != 12" % [rep["per_category"].get("npc", 0)])

		# 4. Verdict kategori avatar (warn 2000, over 5000) dan batas scene.
	if int(rep["total"]) < 96:
		failures.append("audit total %d < 96" % [int(rep["total"])])

		# 4. Verdict kategori avatar (warn 2000, over 5000) dan batas scene.
	if int(PolyBudget.verdict("avatar", 1000)["level"]) != 0:
		failures.append("verdict avatar 1000 != ok")
	if int(PolyBudget.verdict("avatar", 3000)["level"]) != 1:
		failures.append("verdict avatar 3000 != warn")
	if int(PolyBudget.verdict("avatar", 6000)["level"]) != 2:
		failures.append("verdict avatar 6000 != over")
	if (
		PolyBudget.scene_level(90_000) != 0
		or PolyBudget.scene_level(150_000) != 1
		or PolyBudget.scene_level(250_000) != 2
	):
		failures.append("scene_level salah")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BUDGET_TEST_PASS")
	else:
		for f in failures:
			print("BUDGET_TEST_FAIL: ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
