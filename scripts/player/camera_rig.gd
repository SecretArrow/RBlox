extends Node3D
## Third-person camera rig for the local player.
##
## Structure: yaw pivot (top_level, follows the player head height)
##   -> pitch node (tilts) -> Camera3D (parked behind the head).
## Look input enters through add_look() (touch drag / captured mouse);
## sensitivity comes from Settings "camera_sensitivity".

const SENS_BASE := 0.004
const PITCH_MIN := -1.2217  # -70 degrees (looking down)
const PITCH_MAX := 1.3963  # +80 degrees (looking up)
const DIST_DEFAULT := 4.5
const DIST_MIN := 2.0
const DIST_MAX := 8.0
const HEAD_HEIGHT := 1.5
const CAM_LIFT := 0.3

var _target: Node3D = null
var _yaw := 0.0
var _pitch := -0.12
var _distance := DIST_DEFAULT
var _pitch_node: Node3D = null
var _camera: Camera3D = null


func setup(target: Node3D) -> void:
        _target = target
        top_level = true
        _pitch_node = Node3D.new()
        _pitch_node.name = "CamPitch"
        add_child(_pitch_node)
        _camera = Camera3D.new()
        _camera.name = "PlayerCamera"
        _camera.fov = 70.0
        _camera.position = Vector3(0.0, CAM_LIFT, _distance)
        _camera.current = true
        _pitch_node.add_child(_camera)
        _apply()


## delta in pixels (x = drag right, y = drag down).
func add_look(delta: Vector2) -> void:
        var sens := float(Settings.get_value("camera_sensitivity", 1.0))
        _yaw = wrapf(_yaw - delta.x * SENS_BASE * sens, -PI, PI)
        _pitch = clampf(_pitch - delta.y * SENS_BASE * sens, PITCH_MIN, PITCH_MAX)


func set_yaw(yaw: float) -> void:
        _yaw = yaw


func get_yaw() -> float:
        return _yaw


## Basis to convert input (x = right, y = back) into world direction.
func get_move_basis() -> Basis:
        return Basis(Vector3.UP, _yaw)


func set_distance(d: float) -> void:
        _distance = clampf(d, DIST_MIN, DIST_MAX)
        if _camera != null:
                _camera.position = Vector3(0.0, CAM_LIFT, _distance)


## Set pitch langsung (radian, negatif = melihat ke bawah). Dipakai demo
## screenshot & fitur sinematik lain; tetap dalam batas PITCH_MIN..PITCH_MAX.
func set_pitch(p: float) -> void:
        _pitch = clampf(p, PITCH_MIN, PITCH_MAX)


func get_distance() -> float:
        return _distance


func _unhandled_input(event: InputEvent) -> void:
        # Desktop fallback: captured mouse look + wheel zoom. Touch uses TouchControls.
        if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
                add_look(event.relative)
        elif event is InputEventMouseButton and event.pressed:
                if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                        set_distance(_distance - 0.5)
                elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                        set_distance(_distance + 0.5)


func _process(_delta: float) -> void:
        _apply()


func _apply() -> void:
        if _target != null and is_instance_valid(_target):
                global_position = _target.global_position + Vector3(0.0, HEAD_HEIGHT, 0.0)
        rotation = Vector3(0.0, _yaw, 0.0)
        if _pitch_node != null:
                _pitch_node.rotation.x = _pitch
