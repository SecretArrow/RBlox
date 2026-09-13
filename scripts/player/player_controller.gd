extends CharacterBody3D
## Player controller — movement relative to camera yaw, jump/sprint, health,
## procedural avatar animation and lightweight multiplayer interpolation.
##
## Local: input comes from TouchControls signals (bound by game.gd) with a
## keyboard/joypad fallback via the standard input actions.
## Remote: input is disabled and the body lerps toward the last state pushed
## through set_net_state().

const CameraRigScript := preload("res://scripts/player/camera_rig.gd")
const AVATAR_BUILDER_PATH := "res://scripts/avatar/avatar_builder.gd"

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const JUMP_SPEED := 5.0
const MAX_HEALTH := 100.0
const FALL_LIMIT_Y := -15.0
const VOID_LIMIT_Y := -60.0
const FALL_DAMAGE := 100.0
const NET_SEND_INTERVAL := 1.0 / 15.0
const RESPAWN_DELAY := 1.0
const TURN_SPEED := 12.0
const STATE_IDLE := 0
const STATE_WALK := 1
const STATE_RUN := 2
const STATE_JUMP := 3

signal health_changed(hp: float, max_hp: float)
signal died

var info: Dictionary = {}
var is_local := false

var _gravity := 12.0
var _hp := MAX_HEALTH
var _max_hp := MAX_HEALTH
var _health_enabled := true
var _input_enabled := true
var _spawn_point := Vector3.ZERO
var _dead := false
var _dead_timer := 0.0

var _cam_rig = null  # camera_rig.gd instance (local only)
var _name_label: Label3D = null
var _rig: Node = null
var _built := false

# TouchControls state (written through bind_player hooks).
var _touch_move := Vector2.ZERO
var _touch_sprint := false
var _jump_queued := false

# Remote interpolation state.
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_anim := STATE_IDLE
var _net_has_state := false
var _send_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 12.0))
	_spawn_point = global_position
	_ensure_built()


## Contract API (called by game.gd before the node enters the tree).
## info = {name: String, avatar: Dictionary, peer_id: int}.
func setup(player_info: Dictionary, local: bool) -> void:
	info = player_info.duplicate(true)
	is_local = local
	if _built and is_inside_tree():
		# Late setup: refresh role-dependent visuals in place.
		_setup_role()
		_apply_identity()
	else:
		_ensure_built()


func set_net_state(pos: Vector3, yaw: float, anim: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_anim = anim
	_net_has_state = true


func get_anim_state() -> int:
	if not is_local or _dead:
		return _net_anim if not is_local else STATE_IDLE
	if not is_on_floor():
		return STATE_JUMP
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp > WALK_SPEED + 0.5:
		return STATE_RUN
	if sp > 0.5:
		return STATE_WALK
	return STATE_IDLE


# ------------------------------------------------------------------ health

func get_health() -> float:
	return _hp


func get_max_health() -> float:
	return _max_hp


func set_health_enabled(on: bool) -> void:
	_health_enabled = on
	if on:
		_hp = _max_hp
		_dead = false
	health_changed.emit(_hp, _max_hp)


func take_damage(amount: float) -> void:
	if not _health_enabled or _dead or amount <= 0.0:
		return
	_hp = clampf(_hp - amount, 0.0, _max_hp)
	health_changed.emit(_hp, _max_hp)
	if _hp <= 0.0:
		_dead = true
		_dead_timer = RESPAWN_DELAY
		died.emit()


func heal(amount: float) -> void:
	if not _health_enabled or _dead or amount <= 0.0:
		return
	_hp = clampf(_hp + amount, 0.0, _max_hp)
	health_changed.emit(_hp, _max_hp)


func respawn(at: Vector3) -> void:
	_spawn_point = at
	global_position = at + Vector3(0.0, 0.1, 0.0)
	velocity = Vector3.ZERO
	_dead = false
	_dead_timer = 0.0
	_hp = _max_hp
	_net_has_state = false
	health_changed.emit(_hp, _max_hp)


## Extra hooks for other modules.
func set_input_enabled(on: bool) -> void:
	_input_enabled = on
	if not on:
		_touch_move = Vector2.ZERO
		_jump_queued = false


func set_gravity(g: float) -> void:
	_gravity = maxf(0.0, g)


# -------------------------------------------------- TouchControls hooks

func set_touch_move(vec: Vector2) -> void:
	_touch_move = vec.limit_length(1.0)


func add_look(delta: Vector2) -> void:
	if _cam_rig != null and _cam_rig.has_method("add_look"):
		_cam_rig.add_look(delta)


func request_jump() -> void:
	_jump_queued = true


func set_touch_sprint(on: bool) -> void:
	_touch_sprint = on


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built or not is_inside_tree():
		return
	_built = true
	_setup_role()
	_build_avatar()
	_build_name_label()
	health_changed.emit(_hp, _max_hp)


func _setup_role() -> void:
	if Net.is_active():
		set_multiplayer_authority(int(info.get("peer_id", 1)))
	if is_local:
		add_to_group("local_player")
		_build_camera()
	# NOTE: TouchControls is instantiated and bound by game.gd, not here,
	# to guarantee a single on-screen layer.


func _apply_identity() -> void:
	if _name_label != null:
		_name_label.text = str(info.get("name", "Player"))
	if _rig != null and is_instance_valid(_rig):
		_rig.queue_free()
	_rig = null
	_build_avatar()


func _build_camera() -> void:
	if _cam_rig != null and is_instance_valid(_cam_rig):
		return
	_cam_rig = CameraRigScript.new()
	_cam_rig.name = "CameraRig"
	add_child(_cam_rig)
	if _cam_rig.has_method("setup"):
		_cam_rig.setup(self)
	if _cam_rig.has_method("set_yaw"):
		_cam_rig.set_yaw(rotation.y)


func _build_avatar() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	if not ResourceLoader.exists(AVATAR_BUILDER_PATH):
		return  # avatar_builder.gd is another module; stay functional without it.
	var builder: Variant = load(AVATAR_BUILDER_PATH)
	if builder == null or not builder.has_method("build"):
		return
	var cfg_v: Variant = info.get("avatar", {})
	var cfg: Dictionary = cfg_v if cfg_v is Dictionary else {}
	var built: Variant = builder.call("build", cfg)
	if built is Node:
		_rig = built
		add_child(_rig)


func _build_name_label() -> void:
	if _name_label != null and is_instance_valid(_name_label):
		return
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = str(info.get("name", "Player"))
	_name_label.font_size = 72
	_name_label.pixel_size = 0.004
	_name_label.outline_size = 18
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_name_label.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	_name_label.position = Vector3(0.0, 2.3, 0.0)
	add_child(_name_label)


# ------------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	if is_local:
		_process_local(delta)
	else:
		_process_remote(delta)
	_animate(delta)
	_process_net_send(delta)


func _process_local(delta: float) -> void:
	var grounded := is_on_floor()
	if _dead:
		# Fallback respawn; modes usually call respawn() earlier themselves.
		_dead_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not grounded:
			velocity.y -= _gravity * delta
		move_and_slide()
		if _dead_timer <= 0.0:
			respawn(_spawn_point)
		return

	var input := Vector2.ZERO
	var sprint := false
	if _input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if _touch_move.length_squared() > 0.0:
			input = _touch_move
		if Input.is_action_just_pressed("jump"):
			_jump_queued = true
		sprint = _touch_sprint or Input.is_action_pressed("sprint")

	# Movement direction is relative to the camera yaw.
	var cam_yaw := rotation.y
	if _cam_rig != null and _cam_rig.has_method("get_yaw"):
		cam_yaw = _cam_rig.get_yaw()
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if grounded:
		if _jump_queued:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= _gravity * delta
	_jump_queued = false

	move_and_slide()

	# Fall damage below the world; void safety when health is disabled.
	if global_position.y < FALL_LIMIT_Y:
		if _health_enabled:
			take_damage(FALL_DAMAGE)
		elif global_position.y < VOID_LIMIT_Y:
			respawn(_spawn_point)

	# Face the movement direction.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.6:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * TURN_SPEED))


func _process_remote(delta: float) -> void:
	# Remote players: no input, keep gravity, lerp toward the net state.
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _net_has_state:
		var w := minf(1.0, delta * 12.0)
		global_position = global_position.lerp(_net_pos, w)
		rotation.y = lerp_angle(rotation.y, _net_yaw, w)
	move_and_slide()


## Contract API: drive the avatar rig animation (safe when rig is missing).
func animate(dt: float, speed: float, grounded: bool) -> void:
	if _rig == null or not is_instance_valid(_rig) or not _rig.has_method("animate"):
		return
	_rig.animate(dt, speed, grounded)


func _animate(delta: float) -> void:
	var sp := 0.0
	if is_local:
		sp = Vector2(velocity.x, velocity.z).length()
	else:
		sp = _net_anim_speed(_net_anim)
	animate(delta, sp, is_on_floor())


func _net_anim_speed(anim: int) -> float:
	match anim:
		STATE_RUN:
			return SPRINT_SPEED
		STATE_WALK:
			return WALK_SPEED
		_:
			return 0.0


func _process_net_send(delta: float) -> void:
	if not is_local or not Net.is_active():
		return
	if not is_multiplayer_authority():
		return
	_send_timer += delta
	if _send_timer >= NET_SEND_INTERVAL:
		_send_timer = 0.0
		Net.send_player_state(global_position, rotation.y, get_anim_state())
