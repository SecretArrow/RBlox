extends Node3D
## BuildManager — mode bangun: raycast tap dari kamera (pusat layar / mouse /
## touch), ghost transparan snap grid 0.5, place/remove/rotate/anchor, ops
## terrain, undo/redo 50 langkah, limit 12000 blok (MultiMesh chunk), statistik
## & achievement. Sinyal block_changed(data, removed) dipakai game.gd untuk
## sync multiplayer.

signal block_changed(data: Dictionary, removed: bool)

const BlockLibrary := preload("res://scripts/build/block_library.gd")
const WorldTerrain := preload("res://scripts/build/terrain.gd")
const WORLD_MANAGER_PATH := "res://scripts/world/world_manager.gd"
const TOAST_PATH := "res://scripts/ui/toast.gd"
const GRID := 0.5
const MAX_BLOCKS := 12000
const UNDO_LIMIT := 50
const TERRAIN_RADIUS := 3.0
const RAY_DIST := 120.0
const TAP_GUARD_MS := 120

var active := false

var _tool := "place"
var _shape := "box"
var _material := "plastic"
var _color := BlockLibrary.DEFAULT_COLOR
var _paint := "grass"
var _terrain: Node = null
var _camera: Camera3D = null
var _ghost: MeshInstance3D = null
var _last_hit := Vector3.ZERO
var _has_hit := false
var _undo_stack: Array = []
var _redo_stack: Array = []
var _wm: GDScript = null
var _toast_scr: GDScript = null
var _blocks_cache: Node3D = null
var _id_base := 0
var _id_seq := 0
var _last_action_ms := 0


func _ready() -> void:
        if ResourceLoader.exists(WORLD_MANAGER_PATH):
                _wm = load(WORLD_MANAGER_PATH) as GDScript
        if ResourceLoader.exists(TOAST_PATH):
                _toast_scr = load(TOAST_PATH) as GDScript
        _id_base = Time.get_ticks_msec()
        _make_ghost()


func activate(on: bool) -> void:
        active = on
        if _ghost != null:
                _ghost.visible = false


func set_terrain(t: Node) -> void:
        _terrain = t


func set_camera(cam: Camera3D) -> void:
        _camera = cam


func set_shape(shape: String) -> void:
        if BlockLibrary.is_valid_shape(shape):
                _shape = shape
                if _ghost != null:
                        _ghost.mesh = BlockLibrary.make_mesh(_shape)


func set_material(mat: String) -> void:
        if BlockLibrary.is_valid_material(mat):
                _material = mat


func set_color(color: String) -> void:
        _color = color
        if _ghost != null:
                var mat := _ghost.material_override as StandardMaterial3D
                if mat != null:
                        mat.albedo_color = Color(BlockLibrary.parse_color(_color), 0.5)


func get_color() -> String:
        return _color


func set_tool(tool_name: String) -> void:
        _tool = tool_name


func _unhandled_input(event: InputEvent) -> void:
        if not active:
                return
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.pressed:
                        _apply_tool_at(mb.position)
        elif event is InputEventScreenTouch:
                var st := event as InputEventScreenTouch
                if st.pressed:
                        _apply_tool_at(st.position)


func _process(_delta: float) -> void:
        if not active:
                if _ghost != null:
                        _ghost.visible = false
                return
        var hit := _ray_hit()
        _has_hit = not hit.is_empty()
        if _has_hit:
                _last_hit = hit["position"]
        if _ghost != null:
                _ghost.visible = _has_hit and _tool == "place"
                if _ghost.visible:
                        _ghost.position = _snap_place(
                                hit["position"], hit["normal"], BlockLibrary.default_size(_shape)
                        )


func _apply_tool_at(screen_pos: Vector2) -> void:
        var now := Time.get_ticks_msec()
        if now - _last_action_ms < TAP_GUARD_MS:
                return
        _last_action_ms = now
        var hit := _ray_hit(screen_pos)
        if hit.is_empty():
                return
        _last_hit = hit["position"]
        _has_hit = true
        var collider: Object = hit.get("collider")
        match _tool:
                "place":
                        _do_place(hit)
                "remove", "rotate", "anchor":
                        _edit_block(collider, _tool)
                _:
                        _terrain_op(_tool, _last_hit)


func _do_place(hit: Dictionary) -> void:
        var root := _blocks_root()
        if root == null or _wm == null:
                return
        if root.get_child_count() >= MAX_BLOCKS:
                _toast_tr("build_limit", "Batas blok tercapai (%d)" % MAX_BLOCKS)
                return
        var size := BlockLibrary.default_size(_shape)
        var center := _snap_place(hit["position"], hit["normal"], size)
        _id_seq += 1
        var data := {
                "id": "b%d" % (_id_base + _id_seq),
                "shape": _shape,
                "pos": [center.x, center.y, center.z],
                "size": [size.x, size.y, size.z],
                "color": _color,
                "mat": _material,
                "anchored": true,
        }
        var node: Node3D = _wm.call("place_block", root, data)
        if node == null:
                return
        _push_history({"data": data, "removed": false})
        block_changed.emit(data, false)
        var total := GameState.add_stat("blocks_placed")
        GameState.unlock_achievement("first_block")
        if total >= 100:
                GameState.unlock_achievement("builder_100")


func _edit_block(collider: Object, op: String) -> void:
        var data := _block_data(collider)
        var node := collider as Node3D
        if data.is_empty() or node == null:
                return
        var root := _blocks_root()
        if op == "remove":
                if _wm != null and root != null:
                        _wm.call("remove_block", root, node)
                else:
                        node.queue_free()
                _push_history({"data": data, "removed": true})
                block_changed.emit(data, true)
        elif op == "rotate":
                node.rotation.y += PI * 0.5
                data["rot_y"] = wrapf(rad_to_deg(node.rotation.y), 0.0, 360.0)
                if _wm != null and root != null:
                        _wm.call("sync_block_transform", root, node)
                block_changed.emit(data, false)
        elif _wm != null:
                data = data.duplicate(true)
                data["anchored"] = not bool(data.get("anchored", true))
                if root != null:
                        _wm.call("apply_block_update", root, data, false)
                block_changed.emit(data, false)


func terrain_raise() -> void:
        _terrain_op("raise")


func terrain_lower() -> void:
        _terrain_op("lower")


func terrain_flatten() -> void:
        _terrain_op("flatten")


func terrain_paint(paint_name: String) -> void:
        if paint_name in WorldTerrain.PAINTS:
                _paint = paint_name
        _terrain_op("paint")


func _terrain_op(op_name: String, pos: Vector3 = Vector3.INF) -> void:
        if pos == Vector3.INF:
                if not _has_hit:
                        var hit := _ray_hit()
                        if hit.is_empty():
                                return
                        _last_hit = hit["position"]
                        _has_hit = true
                pos = _last_hit
        if _terrain == null or not is_instance_valid(_terrain):
                _toast_tr("build_no_terrain", "Terrain not available")
                return
        if not _terrain.has_method(op_name):
                return
        if op_name == "paint":
                _terrain.call("paint", pos.x, pos.z, TERRAIN_RADIUS, _paint)
        else:
                _terrain.call(op_name, pos.x, pos.z, TERRAIN_RADIUS)


func undo() -> void:
        _step_history(_undo_stack, _redo_stack, true)


func redo() -> void:
        _step_history(_redo_stack, _undo_stack, false)


func _step_history(from_stack: Array, to_stack: Array, undoing: bool) -> void:
        if from_stack.is_empty():
                return
        var entry: Dictionary = from_stack.pop_back()
        var data: Dictionary = entry.get("data", {})
        if data.is_empty():
                return
        to_stack.append(entry)
        var root := _blocks_root()
        if root == null:
                return
        if bool(entry.get("removed", false)) != undoing:
                var id := String(data.get("id", ""))
                for child in root.get_children():
                        var n := child as Node3D
                        if n != null and String(n.get_meta("block_data", {}).get("id", "")) == id:
                                if _wm != null:
                                        _wm.call("remove_block", root, n)
                                else:
                                        n.queue_free()
                                break
                block_changed.emit(data, true)
        elif _wm != null:
                _wm.call("place_block", root, data)
                block_changed.emit(data, false)


func _push_history(entry: Dictionary) -> void:
        _undo_stack.append(entry)
        while _undo_stack.size() > UNDO_LIMIT:
                _undo_stack.pop_front()
        _redo_stack.clear()


## Pusat blok: snap (floor(p/0.5)*0.5) + size*0.5; p = titik bidang kena ray.
func _snap_place(pos: Vector3, normal: Vector3, size: Vector3) -> Vector3:
        var half := size * 0.5
        var raw_min := pos + normal * half - half
        return (
                Vector3(
                        floor(raw_min.x / GRID) * GRID,
                        floor(raw_min.y / GRID) * GRID,
                        floor(raw_min.z / GRID) * GRID
                )
                + half
        )


## Ray dari kamera; tanpa argumen memakai pusat layar (mobile-first).
func _ray_hit(screen_pos: Vector2 = Vector2.INF) -> Dictionary:
        if not is_inside_tree() or get_world_3d() == null:
                return {}
        var cam := _camera
        if cam == null or not is_instance_valid(cam):
                var vp := get_viewport()
                cam = vp.get_camera_3d() if vp != null else null
        if cam == null:
                return {}
        if screen_pos == Vector2.INF:
                var vp2 := get_viewport()
                screen_pos = vp2.get_visible_rect().size * 0.5 if vp2 != null else Vector2.ZERO
        var from := cam.project_ray_origin(screen_pos)
        var dir := cam.project_ray_normal(screen_pos)
        if dir == Vector3.ZERO:
                return {}
        var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_DIST)
        query.collide_with_bodies = true
        query.collide_with_areas = false
        return get_world_3d().direct_space_state.intersect_ray(query)


func _blocks_root() -> Node3D:
        if _blocks_cache == null or not is_instance_valid(_blocks_cache):
                var tree := get_tree()
                if tree != null and tree.current_scene != null:
                        _blocks_cache = tree.current_scene.find_child("Blocks", true, false) as Node3D
        return _blocks_cache


func _block_data(node: Object) -> Dictionary:
        if node is Node and _wm != null:
                var out: Variant = _wm.call("block_data_of", node)
                return out if out is Dictionary else {}
        var n := node as Node3D
        return n.get_meta("block_data", {}) if n != null and n.has_meta("block_data") else {}


func _make_ghost() -> void:
        _ghost = MeshInstance3D.new()
        _ghost.name = "Ghost"
        _ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var mat := StandardMaterial3D.new()
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color = Color(BlockLibrary.parse_color(_color), 0.5)
        _ghost.material_override = mat
        _ghost.mesh = BlockLibrary.make_mesh(_shape)
        add_child(_ghost)
        _ghost.visible = false


func _toast_tr(key: String, fallback: String) -> void:
        var msg := Locale.t(key)
        if _toast_scr != null:
                _toast_scr.call("show", self, fallback if msg == key else msg)
