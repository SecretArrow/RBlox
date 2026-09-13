extends Node
## Test headless untuk MMChunks + WorldManager (v0.2 MultiMesh & LOD).
## Jalur: godot --headless res://tools/test_mm.tscn
## Cetak MM_TEST_PASS bila semua cek lolos, keluar kode 0; selain itu
## cetak MM_TEST_FAIL: <alasan> dan keluar kode 1.

const TEMPLATES := "res://scripts/world/templates.gd"
const WORLD_MANAGER := "res://scripts/world/world_manager.gd"


func _ready() -> void:
        var failures: Array[String] = []
        var tpl: GDScript = load(TEMPLATES)
        var wm: GDScript = load(WORLD_MANAGER)
        var wj: Dictionary = tpl.call("build_world_json", "empty")
        var blocks_arr: Array = []
        for i in 500:
                blocks_arr.append(
                        {
                                "id": "t%d" % i, "shape": "box",
                                "pos": [float(i % 20), 2.0, float(i / 20)],
                                "size": [1, 1, 1], "color": "#26c6da", "mat": "plastic", "anchored": true
                        }
                )
        wj["blocks"] = blocks_arr
        var res: Variant = wm.call("build_world", wj, self)
        if not (res is Dictionary):
                failures.append("build_world tidak mengembalikan Dictionary")
                _finish(failures)
                return
        var r: Dictionary = res
        var blocks_root: Node3D = r.get("blocks") as Node3D
        var mmr: Node3D = blocks_root.find_child("MMChunks", true, false) as Node3D
        if mmr == null:
                failures.append("MMChunks tidak ditemukan di Blocks")
        else:
                var cnt: int = mmr.call("get_block_count")
                if cnt != 500:
                        failures.append("block_count %d != 500" % cnt)
                var mmi_count := 0
                var sum_instances := 0
                for c in mmr.get_children():
                        if c is MultiMeshInstance3D:
                                mmi_count += 1
                                var mm2 := (c as MultiMeshInstance3D).multimesh
                                if mm2 != null:
                                        sum_instances += mm2.instance_count
                if mmi_count == 0:
                        failures.append("tidak ada MultiMeshInstance3D (rebuild gagal)")
                if sum_instances != 500:
                        failures.append("total instance %d != 500" % sum_instances)
                var mmi: MultiMeshInstance3D = null
                for c in mmr.get_children():
                        if c is MultiMeshInstance3D:
                                mmi = c
                                break
                if mmi != null:
                        var mm := mmi.multimesh
                        if mm != null and mm.use_colors == false:
                                failures.append("use_colors harus true")
        # place_block manual (anchored -> harus teregistrasi MultiMesh).
        var body: Node3D = wm.call(
                "place_block",
                blocks_root,
                {"id": "x1", "shape": "box", "pos": [3, 5, 3], "size": [1, 1, 1],
                "color": "#ff0000", "mat": "neon", "anchored": true}
        )
        if body == null:
                failures.append("place_block mengembalikan null")
        elif mmr != null and not bool(mmr.call("has_block", "x1")):
                failures.append("register_block gagal untuk x1")
        # Blok non-anchored -> jalur legacy mesh, TIDAK teregistrasi.
        var rb: Node3D = wm.call(
                "place_block",
                blocks_root,
                {"id": "x2", "shape": "box", "pos": [4, 5, 3], "size": [1, 1, 1],
                "color": "#ff0000", "mat": "plastic", "anchored": false}
        )
        if rb == null:
                failures.append("place_block rigid mengembalikan null")
        elif rb.find_child("Mesh", true, false) == null:
                failures.append("blok rigid harus punya MeshInstance3D (legacy)")
        if rb != null and mmr != null and bool(mmr.call("has_block", "x2")):
                failures.append("blok rigid tidak boleh teregistrasi MultiMesh")
        # rotate + sync transform.
        if body != null:
                body.rotation.y = 1.0
                wm.call("sync_block_transform", blocks_root, body)
        # flush_all setelah place: total instance harus 501 (500 template + x1).
        if mmr != null:
                mmr.call("flush_all")
                var sum2 := 0
                for c in mmr.get_children():
                        if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh != null:
                                sum2 += (c as MultiMeshInstance3D).multimesh.instance_count
                if sum2 != 501:
                        failures.append("total instance setelah place %d != 501" % sum2)
        # recolor via path script.
        if body != null:
                wm.call("set_block_color", body, "#00ff00")
        # remove.
        if body != null:
                wm.call("remove_block", blocks_root, body)
                if mmr != null and bool(mmr.call("has_block", "x1")):
                        failures.append("unregister_block gagal setelah remove")
        # remove blok rigid legacy (ikut terserialize).
        if rb != null:
                rb.queue_free()
        # apply_block_update replace id sama.
        wm.call(
                "apply_block_update",
                blocks_root,
                {"id": "t0", "shape": "box", "pos": [0, 2, 0], "size": [1, 1, 1],
                "color": "#ffffff", "mat": "plastic", "anchored": true},
                false
        )
        # serialize: 500 blok (x1 sudah dihapus).
        var ser: Variant = wm.call("serialize_world", r.get("root") as Node3D, {"meta": {}})
        var arr: Array = (ser as Dictionary).get("blocks", []) if ser is Dictionary else []
        if arr.size() != 500:
                failures.append("serialize blocks %d != 500" % arr.size())
        _finish(failures)


func _finish(failures: Array[String]) -> void:
        if failures.is_empty():
                print("MM_TEST_PASS")
        else:
                for f in failures:
                        print("MM_TEST_FAIL: ", f)
        get_tree().quit(0 if failures.is_empty() else 1)
