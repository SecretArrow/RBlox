extends Node
## ModeBase — dasar semua controller mode gameplay (scripts/world/modes/*.gd).
## Kontrak game.gd (2-e1): preload modes/<game_mode>.gd -> new() ->
## setup(world_json, game) -> tick(1/30). Mode masuk group "mode_controller"
## dan wajib override get_objective_text().
## Refs dunia diambil dari game: game.refs {root, blocks, props, terrain,
## spawn_points} bila ada, else properti world_root/blocks_root/props_root.
## Props dikonsumsi dari meta "prop_data" (kontrak 2-c1), fallback JSON.

const NPC_BOT_PATH := "res://scripts/world/npc_bot.gd"
const TOAST_PATH := "res://scripts/ui/toast.gd"
const WORLD_MANAGER_PATH := "res://scripts/world/world_manager.gd"

## Jaring pengaman input (runtime-only, TIDAK menyentuh project.godot):
## memastikan action ada di InputMap agar Input.get_vector/is_action_*
## tidak error saat keymap belum ditulis agent lain. Idempotent.
const ACTION_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"action_a": [KEY_E],
	"pause_menu": [KEY_ESCAPE],
	"toggle_build": [KEY_B],
}

var world_json: Dictionary = {}
var game: Node = null
var _settings: Dictionary = {}
var _root: Node3D = null
var _props_root: Node3D = null
var _blocks_root: Node3D = null
var _refs: Dictionary = {}
var _script_cache: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("mode_controller")
	_ensure_input_actions()


func setup(p_world_json: Dictionary, p_game: Node) -> void:
	world_json = p_world_json
	game = p_game
	if world_json.get("settings") is Dictionary:
		_settings = world_json["settings"]
	_grab_refs()
	_root = Node3D.new()
	_root.name = "ModeRoot"
	if game != null:
		game.add_child(_root)


func tick(_delta: float) -> void:
	pass


func get_objective_text() -> String:
	return ""


# ------------------------------------------------------------------ helpers

func player() -> Node:
	for n in get_tree().get_nodes_in_group("local_player"):
		if is_instance_valid(n):
			return n
	return null


func player_alive() -> bool:
	var p := player()
	return p != null and not bool(p.get("_dead"))


func player_pos() -> Vector3:
	var p := player()
	if p is Node3D:
		return (p as Node3D).global_position
	return Vector3.ZERO


func is_local_player(body: Node) -> bool:
	return body != null and body.is_in_group("local_player")


func health_enabled() -> bool:
	return bool(_settings.get("health_enabled", true))


func props_of(type: String) -> Array:
	# Kontrak 2-c1: props = children Node3D dengan meta "prop_data".
	var out: Array = []
	if _props_root != null and is_instance_valid(_props_root):
		for child in _props_root.get_children():
			var n := child as Node3D
			if n == null or not n.has_meta("prop_data"):
				continue
			var d: Dictionary = n.get_meta("prop_data", {})
			if String(d.get("type", "")) == type:
				out.append(d)
		return out
	# Fallback bila refs belum tersedia: baca langsung dari JSON dunia.
	var arr: Variant = world_json.get("props", [])
	if arr is Array:
		for pr in arr:
			if pr is Dictionary and String(pr.get("type", "")) == type:
				out.append(pr)
	return out


func spawn_point(index: int = 0) -> Vector3:
	var arr: Array = []
	var sp: Variant = _refs.get("spawn_points")
	if sp is Array:
		arr = sp
	if arr.is_empty():
		var jsp: Variant = world_json.get("spawn_points", [])
		if jsp is Array:
			arr = jsp
	if arr.is_empty():
		return Vector3(0, 2, 0)
	return _vec3(arr[posmod(index, arr.size())])


func spawn_npc(role: String, pos: Vector3, npc_params: Dictionary = {}) -> Node:
	var s := guard_script(NPC_BOT_PATH)
	if s == null:
		return null
	var npc: Node = s.new()
	if npc is Node3D:
		(npc as Node3D).position = pos
	if _root != null:
		_root.add_child(npc)
	elif game != null:
		game.add_child(npc)
	if npc.has_method("set_role"):
		npc.call("set_role", role, npc_params)
	return npc


func respawn_player(at: Vector3) -> void:
	var p := player()
	if p == null:
		return
	if p.has_method("respawn"):
		p.call("respawn", at)
	elif p is Node3D:
		(p as Node3D).global_position = at


func damage_player(amount: float) -> void:
	if not health_enabled():
		return
	var p := player()
	if p != null and p.has_method("take_damage"):
		p.call("take_damage", amount)


func toast(msg: String) -> void:
	var s := guard_script(TOAST_PATH)
	if s != null and self.is_inside_tree():
		s.call("show", self, msg)


## Visual ringan untuk prop JSON (checkpoint/fuse/star/bed/buypad/...).
func prop_marker(pos: Vector3, color: String, size: Vector3 = Vector3(1, 1, 1), label: String = "") -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.emission_enabled = true
	mat.emission = Color(color)
	mat.emission_energy_multiplier = 0.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	if label != "":
		var lbl := Label3D.new()
		lbl.text = label
		lbl.position = Vector3(0, size.y * 0.5 + 0.7, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 34
		lbl.pixel_size = 0.006
		lbl.outline_size = 8
		lbl.no_depth_test = true
		holder.add_child(lbl)
	if _root != null:
		_root.add_child(holder)
	elif game != null:
		game.add_child(holder)
	return holder


## Spawn blok via WorldManager.place_block (kontrak 2-c1), guard refs.
func place_block(data: Dictionary) -> Node:
	var wm := guard_script(WORLD_MANAGER_PATH)
	if wm == null or _blocks_root == null or not is_instance_valid(_blocks_root):
		return null
	var out: Variant = wm.call("place_block", _blocks_root, data)
	if out is Node:
		return out
	return null


# ------------------------------------------------------------------ internal

func _grab_refs() -> void:
	if game == null:
		return
	var r: Variant = game.get("refs")
	if r is Dictionary:
		_refs = r
	else:
		_refs = {
			"root": game.get("world_root"),
			"blocks": game.get("blocks_root"),
			"props": game.get("props_root"),
			"spawn_points": game.get("spawn_points"),
		}
	_props_root = _as_node3d(_refs.get("props"))
	_blocks_root = _as_node3d(_refs.get("blocks"))


func _as_node3d(v: Variant) -> Node3D:
	if v is Node3D:
		return v
	return null


func guard_script(path: String) -> GDScript:
	if _script_cache.has(path):
		return _script_cache[path]
	var s: GDScript = null
	if ResourceLoader.exists(path):
		var r: Variant = load(path)
		if r is GDScript:
			s = r
	_script_cache[path] = s
	return s


func _vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


func _ensure_input_actions() -> void:
	for action in ACTION_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTION_KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(key)
			InputMap.action_add_event(action, ev)
