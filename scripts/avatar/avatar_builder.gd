extends Node3D
## AvatarBuilder — rig avatar blocky (Roblox-like) untuk RBlox.
## var rig: Node3D = AvatarBuilder.build(GameState.avatar_config) lalu add_child.
## rig.animate(delta, speed, grounded) dipanggil pemilik node (player/game).
## apply_item(rig, item) / clear_slot(rig, slot) untuk kosmetik. Rig menghadap +Z.

const CosmeticsDB := preload("res://scripts/avatar/cosmetics_db.gd")

const DEF_CFG := {
	"skin": "#e0b088", "shirt": "#4f8cff", "pants": "#34495e", "hair": "#3b2314", "face": "smile"
}
const PARENT_NODE := {
	"head": "Head",
	"torso": "Torso",
	"arm_l": "ArmL",
	"arm_r": "ArmR",
	"leg_l": "LegL",
	"leg_r": "LegR"
}

static var _mat_cache: Dictionary = {}

var _t: float = 0.0
var _amp: float = 0.0
var _freq: float = 6.0


# ------------------------------------------------------------------- build
static func build(config: Dictionary) -> Node3D:
	var rig: Node3D = null
	var sc: Variant = load("res://scripts/avatar/avatar_builder.gd")
	if sc is Script:
		var inst: Variant = sc.new()
		if inst is Node3D:
			rig = inst
	if rig == null:
		rig = Node3D.new()
	rig.name = "AvatarRig"
	rig.set_meta("avatar_config", config.duplicate(true))
	var skin := _cfg_color(config, "skin")
	var shirt := _cfg_color(config, "shirt")
	var pants := _cfg_color(config, "pants")
	_part(rig, "Head", Vector3(0, 1.55, 0), Vector3(0.5, 0.5, 0.5), skin)
	_part(rig, "Torso", Vector3(0, 1.0, 0), Vector3(0.55, 0.7, 0.3), shirt)
	_pivot_part(
		rig,
		"ArmL",
		Vector3(-0.385, 1.32, 0),
		Vector3(0.22, 0.65, 0.22),
		Vector3(0, -0.325, 0),
		skin
	)
	_pivot_part(
		rig, "ArmR", Vector3(0.385, 1.32, 0), Vector3(0.22, 0.65, 0.22), Vector3(0, -0.325, 0), skin
	)
	_pivot_part(
		rig, "LegL", Vector3(-0.14, 0.7, 0), Vector3(0.22, 0.65, 0.22), Vector3(0, -0.35, 0), pants
	)
	_pivot_part(
		rig, "LegR", Vector3(0.14, 0.7, 0), Vector3(0.22, 0.65, 0.22), Vector3(0, -0.35, 0), pants
	)
	_face_plane(rig, str(config.get("face", "smile")))
	var eq: Variant = config.get("equipped", {})
	if eq is Dictionary:
		for slot in eq.keys():
			var id := str(eq.get(slot, ""))
			if id == "":
				continue
			var item := CosmeticsDB.get_item(id)
			if not item.is_empty():
				apply_item(rig, item)
	return rig


static func _part(rig: Node3D, pname: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = pname
	mi.mesh = _make_mesh("box", size)
	mi.material_override = _material(color)
	mi.position = pos
	rig.add_child(mi)


static func _pivot_part(
	rig: Node3D, pname: String, pivot_pos: Vector3, size: Vector3, offset: Vector3, color: Color
) -> void:
	var pivot := Node3D.new()
	pivot.name = pname
	pivot.position = pivot_pos
	rig.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.name = pname + "Mesh"
	mi.mesh = _make_mesh("box", size)
	mi.material_override = _material(color)
	mi.position = offset
	pivot.add_child(mi)


static func _face_plane(rig: Node3D, expr: String) -> void:
	var head: Node3D = rig.get_node_or_null(^"Head")
	if head == null:
		return
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = ImageTexture.create_from_image(_face_image(expr))
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Face"
	mi.mesh = mesh
	mi.position = Vector3(0, 0, 0.26)
	mi.rotation.x = PI * 0.5  # normal +Z, sisi atas gambar ke atas
	head.add_child(mi)


# ----------------------------------------------------------------- animate
## speed kecil = jalan (freq 6, amp 0.3), cepat = lari (freq 10, amp 0.6),
## di udara: lengan naik, kaki sedikit menekuk.
func animate(dt: float, speed: float, grounded: bool) -> void:
	_t += dt
	var target_amp := 0.3
	var target_freq := 6.0
	if not grounded:
		target_amp = 0.0
	elif speed > 4.5:
		target_amp = 0.6
		target_freq = 10.0
	elif speed < 0.1:
		target_amp = 0.0
	var k := clampf(dt * 10.0, 0.0, 1.0)
	_amp = lerpf(_amp, target_amp, k)
	_freq = lerpf(_freq, target_freq, k)
	var al := _pivot("ArmL")
	var ar := _pivot("ArmR")
	var ll := _pivot("LegL")
	var lr := _pivot("LegR")
	if al == null or ar == null or ll == null or lr == null:
		return
	if grounded:
		var sw := sin(_t * _freq) * _amp
		al.rotation.x = sw
		ar.rotation.x = -sw
		ll.rotation.x = -sw
		lr.rotation.x = sw
	else:
		var kk := clampf(k * 2.0, 0.0, 1.0)
		al.rotation.x = lerpf(al.rotation.x, -2.5, kk)
		ar.rotation.x = lerpf(ar.rotation.x, -2.5, kk)
		ll.rotation.x = lerpf(ll.rotation.x, 0.4, kk)
		lr.rotation.x = lerpf(lr.rotation.x, -0.3, kk)


func _pivot(pname: String) -> Node3D:
	return get_node_or_null(NodePath(pname)) as Node3D


# --------------------------------------------------------------- kosmetik
## Pasang item: item.shapes -> MeshInstance3D pada part induk. Node diberi
## meta "cosmetic_slot" + grup "cosmetic_<slot>". Warna "" = warna config part.
static func apply_item(rig: Node3D, item: Dictionary) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var slot := str(item.get("slot", ""))
	var shapes: Variant = item.get("shapes", [])
	if not (shapes is Array):
		return
	for sh in shapes:
		if not (sh is Dictionary):
			continue
		var pkey := str(sh.get("parent", "torso"))
		var mtype := str(sh.get("type", "box"))
		var size := _vec3(sh.get("size", [0.2, 0.2, 0.2]))
		var holder: Node = rig.get_node_or_null(NodePath(str(PARENT_NODE.get(pkey, "Torso"))))
		if holder == null:
			holder = rig
		var mi := MeshInstance3D.new()
		mi.mesh = _make_mesh(mtype, size)
		if mtype == "sphere" or mtype == "cylinder":
			mi.scale = size  # mesh unit (diameter/tinggi 1) -> ukuran penuh
		mi.position = _vec3(sh.get("pos", [0, 0, 0]))
		var col_s := str(sh.get("color", ""))
		var col := _fallback_color(rig, pkey) if col_s == "" else _hex(col_s, Color.WHITE)
		mi.material_override = _material(col)
		mi.set_meta("cosmetic_slot", slot)
		mi.add_to_group("cosmetic_" + slot)
		holder.add_child(mi)


## Hapus semua node kosmetik pada satu slot.
static func clear_slot(rig: Node3D, slot: String) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	for n in rig.find_children("*", "", true, false):
		if n is Node and n.has_meta("cosmetic_slot") and str(n.get_meta("cosmetic_slot")) == slot:
			n.queue_free()


# ----------------------------------------------------------------- helpers
static func _make_mesh(mtype: String, size: Vector3) -> Mesh:
	match mtype:
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			return m
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			return c
		"prism":
			var p := PrismMesh.new()
			p.size = size
			return p
		_:
			var b := BoxMesh.new()
			b.size = size
			return b


static func _material(col: Color) -> StandardMaterial3D:
	var key := col.to_html(false)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	_mat_cache[key] = m
	return m


static func _fallback_color(rig: Node3D, pkey: String) -> Color:
	var cfg: Variant = rig.get_meta("avatar_config", {})
	if not (cfg is Dictionary):
		return Color.WHITE
	match pkey:
		"head":
			return _cfg_color(cfg, "hair")
		"torso", "arm_l", "arm_r":
			return _cfg_color(cfg, "shirt")
		"leg_l", "leg_r":
			return _cfg_color(cfg, "pants")
		_:
			return Color.WHITE


static func _cfg_color(config: Dictionary, key: String) -> Color:
	return _hex(str(config.get(key, DEF_CFG.get(key, "#ffffff"))), Color.WHITE)


static func _vec3(arr: Variant) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


## Hex aman: hanya "#rrggbb" valid, selain itu fallback.
static func _hex(s: String, fallback: Color) -> Color:
	var t := s.strip_edges()
	if t.begins_with("#") and t.substr(1).is_valid_hex_number():
		return Color(t)
	return fallback


## Pola muka 64x64 per ekspresi (alpha 0 = transparan).
static func _face_image(expr: String) -> Image:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	var dark := Color("#20242e")
	var white := Color("#f4f4f6")
	match expr:
		"cool":
			_rect(img, 12, 21, 40, 7, Color("#14161f"))
			_rect(img, 10, 22, 2, 5, Color("#14161f"))
			_rect(img, 52, 22, 2, 5, Color("#14161f"))
			_rect(img, 15, 23, 4, 2, Color("#8a94a8"))
			_rect(img, 24, 45, 16, 2, dark)
		"angry":
			_rect(img, 14, 22, 12, 9, dark)
			_rect(img, 38, 22, 12, 9, dark)
			for i in range(11):
				_px(img, 13 + i, 14 + int(i * 0.7), dark)
				_px(img, 50 - i, 14 + int(i * 0.7), dark)
			_rect(img, 24, 45, 16, 3, dark)
		"sad":
			_eyes(img, white, dark)
			for x in range(24, 41):
				_px(img, x, 44 if absi(x - 32) <= 6 else 45, dark)
			_rect(img, 22, 46, 2, 1, dark)
			_rect(img, 40, 46, 2, 1, dark)
		"neutral":
			_eyes(img, white, dark)
			_rect(img, 24, 44, 16, 2, dark)
		_:
			_eyes(img, white, dark)
			for x in range(22, 43):
				_px(img, x, 45 if absi(x - 32) <= 8 else 44, dark)
			_px(img, 21, 43, dark)
			_px(img, 42, 43, dark)
	return img


static func _eyes(img: Image, white: Color, dark: Color) -> void:
	_rect(img, 14, 20, 12, 10, white)
	_rect(img, 38, 20, 12, 10, white)
	_rect(img, 18, 24, 5, 5, dark)
	_rect(img, 42, 24, 5, 5, dark)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			_px(img, ix, iy, c)
