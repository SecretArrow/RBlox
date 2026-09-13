extends RefCounted
## WorldManager — helper statis membangun / update / serialize dunia dari JSON
## skema worklog Task 1:
##   {"format":"rblox-world","version":1,"meta":{...},"settings":{...},
##    "spawn_points":[[x,y,z]],
##    "blocks":[{id,shape,pos,size,color,mat,anchored,script}],
##    "props":[{type,role,pos,...}],
##    "terrain":{size,seed,heights[],paint[]}}
## Pemakaian: const WorldManager := preload("res://scripts/world/world_manager.gd")
## Node blok menyimpan datanya di meta "block_data" (termasuk rot_y derajat).

const BlockLibrary := preload("res://scripts/build/block_library.gd")
const WorldTerrain := preload("res://scripts/build/terrain.gd")
const BLOCK_DENSITY: float = 0.6
const DEFAULT_COLOR := "#e0453a"

static var _id_counter: int = 0


## Bangun pohon dunia di bawah parent (bila ada).
## Return {root, blocks, props, terrain, spawn_points:Array[Vector3]}.
static func build_world(world_json: Dictionary, parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "WorldRoot"
	var blocks := Node3D.new()
	blocks.name = "Blocks"
	root.add_child(blocks)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)

	# Terrain (flat 64x64 seed 1 bila data hilang/kosong).
	var tdata_raw: Variant = world_json.get("terrain", {})
	var tdata: Dictionary = {}
	if tdata_raw is Dictionary:
		tdata = tdata_raw

		# Blok.

		# Props: marker posisi sederhana; logika prop milik agent lain.

		# Spawn points.

		# Angkat spawn di atas permukaan terrain bila tertanam.
	if tdata.is_empty():
		var flat: Array = []
		flat.resize(64 * 64)
		for k in flat.size():
			flat[k] = 0
		tdata = {"size": 64, "seed": 1, "heights": flat, "paint": []}

		# Blok.

		# Props: marker posisi sederhana; logika prop milik agent lain.

		# Spawn points.

		# Angkat spawn di atas permukaan terrain bila tertanam.
	var terrain: Node3D = WorldTerrain.build_from(tdata)
	root.add_child(terrain)

	# Blok.
	var blocks_raw: Variant = world_json.get("blocks", [])
	if blocks_raw is Array:
		for bd in blocks_raw:
			if bd is Dictionary:
				place_block(blocks, bd)

		# Props: marker posisi sederhana; logika prop milik agent lain.

		# Spawn points.

		# Angkat spawn di atas permukaan terrain bila tertanam.
	var props_raw: Variant = world_json.get("props", [])
	if props_raw is Array:
		var idx := 0
		for pd in props_raw:
			if pd is Dictionary:
				var marker := Node3D.new()
				marker.name = "prop_%d" % idx
				marker.position = to_vec3(pd.get("pos", [0, 0, 0]))
				marker.set_meta("prop_data", pd)
				props.add_child(marker)
			idx += 1

		# Spawn points.

		# Angkat spawn di atas permukaan terrain bila tertanam.
	var spawns: Array[Vector3] = []
	var spl: Variant = world_json.get("spawn_points", [])
	if spl is Array:
		for sp in spl:
			if sp is Array and (sp as Array).size() >= 3:
				spawns.append(to_vec3(sp))

		# Angkat spawn di atas permukaan terrain bila tertanam.
	if spawns.is_empty():
		spawns.append(Vector3(0.0, 3.0, 0.0))
		# Angkat spawn di atas permukaan terrain bila tertanam.
	if terrain != null and terrain.has_method("get_height_at"):
		for i in spawns.size():
			var spv := spawns[i]
			var gh: Variant = terrain.call("get_height_at", spv.x, spv.z)
			var ground := float(gh)
			if spv.y < ground + 1.0:
				spawns[i] = Vector3(spv.x, ground + 1.0, spv.z)
	if parent != null:
		parent.add_child(root)
	return {
		"root": root,
		"blocks": blocks,
		"props": props,
		"terrain": terrain,
		"spawn_points": spawns,
	}


## Buat satu node blok (StaticBody3D bila anchored, selain itu RigidBody3D
## dengan mass ~ volume) di bawah blocks_root. Meta "block_data" menyimpan
## data; id kosong -> "b<counter>" (unik terhadap isi Blocks). Return body.
static func place_block(blocks_root: Node3D, data: Dictionary) -> Node3D:
	var d := data.duplicate(true)
	var id := String(d.get("id", ""))
	if id == "":
		id = "b%d" % _id_counter
		_id_counter += 1
		while blocks_root != null and _find_block(blocks_root, id) != null:
			id = "b%d" % _id_counter
			_id_counter += 1
	d["id"] = id
	var shape := String(d.get("shape", "box"))
	if not BlockLibrary.is_valid_shape(shape):
		shape = "box"
	var size := to_vec3(d.get("size", []))
	if size == Vector3.ZERO:
		size = BlockLibrary.default_size(shape)
	d["size"] = [size.x, size.y, size.z]
	var color := String(d.get("color", DEFAULT_COLOR))
	var mat := String(d.get("mat", "plastic"))
	if not BlockLibrary.is_valid_material(mat):
		mat = "plastic"
	var anchored: bool = bool(d.get("anchored", true))
	var body: PhysicsBody3D
	if anchored:
		body = StaticBody3D.new()
	else:
		var rb := RigidBody3D.new()
		var volume: float = maxf(size.x * size.y * size.z, 0.1)
		rb.mass = clampf(volume * BLOCK_DENSITY, 0.1, 100.0)
		body = rb
	body.name = id
	body.position = to_vec3(d.get("pos", [0, 0, 0]))
	body.rotation.y = deg_to_rad(float(d.get("rot_y", 0.0)))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BlockLibrary.make_mesh(shape, size)
	mi.material_override = BlockLibrary.make_material(mat, color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = BlockLibrary.make_collision(shape, size)
	body.add_child(cs)
	body.set_meta("block_data", d)
	if blocks_root != null:
		blocks_root.add_child(body)
	return body


## Terapkan update blok lokal/remote: place (replace bila id sama) atau remove.
static func apply_block_update(blocks_root: Node3D, data: Dictionary, removed: bool) -> void:
	if blocks_root == null:
		return
	var id := String(data.get("id", ""))
	var existing := _find_block(blocks_root, id)
	if removed:
		if existing != null:
			existing.queue_free()
		return
	if existing != null:
		existing.queue_free()
	place_block(blocks_root, data)


## Kumpulkan meta block_data semua anak Blocks (+ serialize terrain) ke salinan
## base_json. Kunci meta/settings base_json dibiarkan utuh.
static func serialize_world(root: Node3D, base_json: Dictionary) -> Dictionary:
	var out := base_json.duplicate(true)
	var arr: Array = []
	if root != null:
		var blocks_root := root.find_child("Blocks", true, false) as Node3D
		if blocks_root != null:
			for child in blocks_root.get_children():
				if not is_instance_valid(child) or child.is_queued_for_deletion():
					continue
				var node := child as Node3D
				if node == null:
					continue
				var d: Dictionary = node.get_meta("block_data", {})
				if not d.is_empty():
					arr.append(d.duplicate(true))
	out["blocks"] = arr
	var terrain := find_terrain(root)
	if terrain != null and terrain.has_method("serialize"):
		out["terrain"] = terrain.call("serialize")
	return out


## Ambil block_data dari node (naik ke parent bila perlu).
static func block_data_of(node: Node3D) -> Dictionary:
	var cur: Node = node
	while cur != null:
		if cur is Node3D and (cur as Node3D).has_meta("block_data"):
			return (cur as Node3D).get_meta("block_data", {})
		cur = cur.get_parent()
	return {}


## Konversi Array [x,y,z] (atau Vector3) ke Vector3; default ZERO.
static func to_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float((v as Array)[0]), float((v as Array)[1]), float((v as Array)[2]))
	return Vector3.ZERO


## Cari node terrain (script terrain.gd) di bawah root.
static func find_terrain(root: Node3D) -> Node3D:
	if root == null:
		return null
	var scr: GDScript = load("res://scripts/build/terrain.gd") as GDScript
	if scr == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and (n as Node3D).get_script() == scr:
			return n
		stack.append_array(n.get_children())
	return null


static func _find_block(blocks_root: Node3D, id: String) -> Node3D:
	if id == "" or blocks_root == null:
		return null
	for child in blocks_root.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var meta: Dictionary = node.get_meta("block_data", {})
		if String(meta.get("id", "")) == id:
			return node
	return null
