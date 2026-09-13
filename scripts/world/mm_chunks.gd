extends Node3D
## MMChunks — renderer blok statis berbasis MultiMesh per chunk + LOD jarak.
## Tujuan roadmap v0.2: 10.000+ blok tetap 60 FPS di perangkat RAM 3-4GB.
## Cara kerja:
##  - Dunia dibagi chunk kubus 16 unit; tiap chunk mengelompokkan blok per
##    bucket "shape|material" menjadi SATU MultiMeshInstance3D (1 draw call
##    per bucket, bukan 1 per blok). Warna per blok via instance color.
##  - Node fisika (StaticBody3D + CollisionShape3D) tetap dibuat WorldManager
##    sehingga raycast build tool & collision pemain tidak berubah.
##  - LOD: tiap ~0.25s jarak chunk ke kamera dibandingkan profil kualitas
##    grafis (low/medium/high): jauh = sembunyikan, tengah = tanpa bayangan.
## API: register_block / unregister_block / update_block_transform /
##      update_block_color / flush_all / get_block_count.

const BlockLibrary := preload("res://scripts/build/block_library.gd")

const CHUNK := 16.0
const REBUILD_BUDGET := 8  # maks chunk direbuild per frame (di luar flush_all)
const LOD_INTERVAL := 0.25

# Profil LOD per kualitas grafis: [jarak_penuh (bayangan), jarak_hilang]
const LOD_PROFILES := {
	"low": [40.0, 72.0],
	"medium": [72.0, 112.0],
	"high": [104.0, 160.0],
}
const LOD_DEFAULT := [72.0, 112.0]

## Cache statis mesh unit & material (dibagi semua chunk & semua dunia).
static var _unit_meshes: Dictionary = {}
static var _materials: Dictionary = {}

var _blocks: Dictionary = {}  # id -> rec {chunk, bucket, xf, color, shape, mat}
var _chunks: Dictionary = {}  # Vector3i -> {center:Vector3, buckets:{bkey->{mmi, ids}}}
var _dirty: Dictionary = {}  # Vector3i -> true
var _lod_timer := 0.0
var _lod_profile: Array = LOD_DEFAULT
var _block_count := 0


func _ready() -> void:
	_lod_profile = _profile_for(String(Settings.get_value("graphics_quality", "medium")))
	Settings.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.disconnect(_on_setting_changed)


func _process(delta: float) -> void:
	if not _dirty.is_empty():
		_flush_budget()
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = LOD_INTERVAL
		_update_lod()


# ------------------------------------------------------------------- API --

## Daftarkan blok statis (anchored) ke renderer chunk. xf memuat posisi,
## rotasi Y, dan skala (ukuran blok). color/mat hex String.
func register_block(id: String, xf: Transform3D, shape: String, size: Vector3, color: String, mat: String) -> void:
	if id == "":
		return
	if _blocks.has(id):
		unregister_block(id)
	var ckey := _chunk_key(xf.origin)
	var bucket := String(shape) + "|" + String(mat)
	var ch: Dictionary = _chunks.get(ckey, {})
	if ch.is_empty():
		ch = {"center": _chunk_center(ckey), "buckets": {}}
		_chunks[ckey] = ch
	var b: Dictionary = ch["buckets"].get(bucket, {})
	if b.is_empty():
		b = {"mmi": null, "ids": []}
		ch["buckets"][bucket] = b
	(b["ids"] as Array).append(id)
	_blocks[id] = {
		"chunk": ckey, "bucket": bucket, "xf": xf,
		"color": BlockLibrary.parse_color(color), "shape": shape, "mat": mat,
		"size": size,
	}
	_dirty[ckey] = true
	_block_count += 1


func unregister_block(id: String) -> void:
	var rec: Variant = _blocks.get(id, {})
	if rec is Dictionary and not (rec as Dictionary).is_empty():
		var r: Dictionary = rec
		_blocks.erase(id)
		_block_count = maxi(0, _block_count - 1)
		_touch_bucket(r["chunk"], r["bucket"], id)
		_dirty[r["chunk"]] = true


func update_block_transform(id: String, xf: Transform3D) -> void:
	var rec: Variant = _blocks.get(id, {})
	if rec is Dictionary and not (rec as Dictionary).is_empty():
		var r: Dictionary = rec
		r["xf"] = xf
		_dirty[r["chunk"]] = true


func update_block_color(id: String, hex: String) -> void:
	var rec: Variant = _blocks.get(id, {})
	if rec is Dictionary and not (rec as Dictionary).is_empty():
		var r: Dictionary = rec
		r["color"] = BlockLibrary.parse_color(hex)
		_dirty[r["chunk"]] = true


## Rebuild semua chunk kotor secara sinkron (dipakai sekali saat world build).
func flush_all() -> void:
	for k in _dirty.keys():
		_rebuild_chunk(k)
	_dirty.clear()


func get_block_count() -> int:
	return _block_count


func has_block(id: String) -> bool:
	return _blocks.has(id)


# ------------------------------------------------------------- internal --

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "graphics_quality":
		_lod_profile = _profile_for(String(Settings.get_value("graphics_quality", "medium")))


func _profile_for(quality: String) -> Array:
	return LOD_PROFILES.get(quality, LOD_DEFAULT) if LOD_PROFILES.has(quality) else LOD_DEFAULT


func _chunk_key(pos: Vector3) -> Vector3i:
	return Vector3i(floori(pos.x / CHUNK), floori(pos.y / CHUNK), floori(pos.z / CHUNK))


func _chunk_center(key: Vector3i) -> Vector3:
	return Vector3(
		(float(key.x) + 0.5) * CHUNK, (float(key.y) + 0.5) * CHUNK, (float(key.z) + 0.5) * CHUNK
	)


func _touch_bucket(ckey: Variant, bucket: Variant, id: String) -> void:
	var ch: Variant = _chunks.get(ckey, {})
	if ch is Dictionary and not (ch as Dictionary).is_empty():
		var buckets: Dictionary = (ch as Dictionary)["buckets"]
		var b: Variant = buckets.get(bucket, {})
		if b is Dictionary and not (b as Dictionary).is_empty():
			(b as Dictionary)["ids"].erase(id)


## Rebuild maksimal REBUILD_BUDGET chunk kotor per frame (hindari hitch).
func _flush_budget() -> void:
	var n := 0
	for k in _dirty.keys():
		_rebuild_chunk(k)
		_dirty.erase(k)
		n += 1
		if n >= REBUILD_BUDGET:
			break


func _rebuild_chunk(ckey: Variant) -> void:
	var ch: Variant = _chunks.get(ckey, {})
	if ch is Dictionary and (ch as Dictionary).is_empty():
		return
	var chunk: Dictionary = ch
	var buckets: Dictionary = chunk["buckets"]
	for bkey in buckets.keys():
		var b: Dictionary = buckets[bkey]
		var ids: Array = (b["ids"] as Array).filter(
			func(i: Variant) -> bool: return _blocks.has(i)
		)
		b["ids"] = ids
		if ids.is_empty():
			if b["mmi"] != null and is_instance_valid(b["mmi"]):
				(b["mmi"] as Node3D).queue_free()
			b["mmi"] = null
			continue
		var first: Dictionary = _blocks[ids[0]]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _unit_mesh(String(first["shape"]))
		mm.instance_count = ids.size()
		for i in ids.size():
			var rec: Dictionary = _blocks[ids[i]]
			mm.set_instance_transform(i, rec["xf"])
			mm.set_instance_color(i, rec["color"])
		if b["mmi"] == null or not is_instance_valid(b["mmi"]):
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "MM_" + String(bkey).replace("|", "_")
			mmi.material_override = _material(String(first["mat"]))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.position = Vector3.ZERO
			add_child(mmi)
			b["mmi"] = mmi
		(b["mmi"] as MultiMeshInstance3D).multimesh = mm


## LOD: chunk jauh disembunyikan, chunk menengah tanpa bayangan (hemat fill).
func _update_lod() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var cam_pos := cam.global_position
	var d_full := float(_lod_profile[0])
	var d_far := float(_lod_profile[1])
	for ckey in _chunks.keys():
		var chunk: Dictionary = _chunks[ckey]
		var dist := cam_pos.distance_to(chunk["center"])
		var vis := dist < d_far
		var shadow := dist < d_full
		var buckets: Dictionary = chunk["buckets"]
		for bkey in buckets.keys():
			var mmi: Variant = (buckets[bkey] as Dictionary).get("mmi")
			if mmi != null and is_instance_valid(mmi):
				var g := mmi as MultiMeshInstance3D
				g.visible = vis
				if vis:
					g.cast_shadow = (
						GeometryInstance3D.SHADOW_CASTING_SETTING_ON
						if shadow
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					)


## Mesh unit (skala 1) per bentuk; ukuran blok diset lewat skala transform.
static func _unit_mesh(shape: String) -> Mesh:
	if _unit_meshes.has(shape):
		return _unit_meshes[shape]
	var m: Mesh
	match shape:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 16
			sm.rings = 8
			m = sm
		"cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 1.0
			cm.radial_segments = 16
			m = cm
		"wedge":
			var pm := PrismMesh.new()
			pm.size = Vector3.ONE
			m = pm
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE
			m = bm
	_unit_meshes[shape] = m
	return m


## Material bersama per jenis (vertex color = warna per instance MultiMesh).
static func _material(mat: String) -> StandardMaterial3D:
	if _materials.has(mat):
		return _materials[mat]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	match mat:
		"metal":
			m.metallic = 0.9
			m.roughness = 0.3
		"wood":
			m.roughness = 0.95
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1, 1, 1, 0.4)
			m.roughness = 0.1
			m.metallic = 0.1
		"neon":
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 0.9
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_:
			m.roughness = 0.8
	_materials[mat] = m
	return m
