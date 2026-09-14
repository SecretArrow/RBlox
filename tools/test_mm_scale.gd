extends Node3D
## Uji skala: 12.000 blok statis -> waktu build_world + flush_all (headless).
## Kriteria: selesai tanpa error; cetak durasi ms (build+flush, serialize).


func _ready() -> void:
	var wm: GDScript = load("res://scripts/world/world_manager.gd")
	var wj: Dictionary = {
		"format": "rblox-world",
		"version": 1,
		"meta": {"name": "Scale"},
		"settings": {},
		"spawn_points": [[0, 3, 0]],
		"blocks": [],
		"props": [],
		"terrain": {"size": 32, "seed": 1, "heights": [], "paint": []}
	}
	var blocks: Array = []
	for i in 12000:
		blocks.append(
			{
				"id": "s%d" % i,
				"shape": ["box", "box", "box", "sphere", "cylinder", "wedge"][i % 6],
				"pos": [float(i % 23), 1.0 + float((i / 23) % 40), float((i / 23) / 40)],
				"size": [1, 1, 1],
				"color": "#e0453a",
				"mat": ["plastic", "metal", "wood", "glass", "neon"][i % 5],
				"anchored": true
			}
		)
	wj["blocks"] = blocks
	var t0 := Time.get_ticks_msec()
	var res: Variant = wm.call("build_world", wj, self)
	var t1 := Time.get_ticks_msec()
	var ser: Variant = wm.call(
		"serialize_world", (res as Dictionary)["root"] as Node3D, wj.duplicate(true)
	)
	var t2 := Time.get_ticks_msec()
	var blocks_root: Node3D = (res as Dictionary)["blocks"] as Node3D
	var mmr: Node3D = blocks_root.find_child("MMChunks", true, false) as Node3D
	var count: int = mmr.call("get_block_count") if mmr != null else -1
	var mmi := 0
	for c in mmr.get_children():
		if c is MultiMeshInstance3D:
			mmi += 1
	print(
		(
			"SCALE_TEST build_ms=%d serialize_ms=%d blocks=%d mmi=%d nodes=%d"
			% [t1 - t0, t2 - t1, count, mmi, blocks_root.get_child_count()]
		)
	)
	print("SCALE_TEST_PASS" if count == 12000 and mmi > 0 else "SCALE_TEST_FAIL")
	get_tree().quit(0 if count == 12000 else 1)
