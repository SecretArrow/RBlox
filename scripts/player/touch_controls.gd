extends CanvasLayer
## Touch controls layer (mobile, landscape): floating joystick on the left
## half, camera look drag on the right half, and jump / sprint / action
## buttons in the bottom-right corner.
##
## The layer stays hidden until bind_player() attaches it to the local
## player (game.gd owns the instantiation). Multitouch: joystick and look
## are tracked per touch index so both thumbs can be used at once.

signal move_changed(vec: Vector2)
signal look_delta(delta: Vector2)
signal jump_pressed
signal jump_released
signal sprint_toggled(on: bool)
signal action_a_pressed

const UIKIT_PATH := "res://scripts/ui/ui_kit.gd"
const STICK_RADIUS := 62.0
const DEAD_ZONE := 0.08
const MOUSE_TOUCH_ID := 100  # Synthetic touch index for desktop mouse testing.
const LAYER_ORDER := 14      # Above HUD, below pause overlay (20).

var _player = null
var _root: Control = null
var _stick = null  # JoystickView instance
var _stick_center := Vector2.ZERO
var _stick_index := -1
var _look_index := -1
var _look_last := Vector2.ZERO
var _mouse_down := false
var _button_rects: Array = []
var _rest_stick_pos := Vector2.ZERO
var _btn_jump: Button = null
var _btn_sprint: Button = null
var _btn_action: Button = null


# Custom-drawn joystick (base ring + knob), input-transparent.
class JoystickView extends Control:
	var radius := 62.0
	var knob := Vector2.ZERO

	func set_knob(offset: Vector2) -> void:
		knob = offset
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, radius, Color(1.0, 1.0, 1.0, 0.08))
		draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.35), 2.0, true)
		draw_circle(center + knob, radius * 0.42, Color(1.0, 1.0, 1.0, 0.30))
		draw_arc(center + knob, radius * 0.42, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.5), 1.5, true)


func _ready() -> void:
	layer = LAYER_ORDER
	visible = false
	set_process_input(false)
	add_to_group("touch_controls")

	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th: Theme = Settings.get_theme()
	if th != null:
		_root.theme = th
	add_child(_root)
	_root.resized.connect(_layout)

	_stick = JoystickView.new()
	_stick.name = "Joystick"
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.radius = STICK_RADIUS
	_stick.size = Vector2(STICK_RADIUS * 2.0 + 12.0, STICK_RADIUS * 2.0 + 12.0)
	_root.add_child(_stick)

	_btn_jump = _make_button(_t("hud_jump", "Lompat", "Jump"), 72.0, true)
	_btn_sprint = _make_button(_t("hud_sprint", "Sprint", "Sprint"), 64.0, false)
	_btn_sprint.toggle_mode = true
	_btn_action = _make_button(_t("hud_action", "Aksi", "Action"), 60.0, false)
	for b in [_btn_jump, _btn_sprint, _btn_action]:
		_root.add_child(b)
	_btn_jump.button_down.connect(_on_jump_down)
	_btn_jump.button_up.connect(_on_jump_up)
	_btn_sprint.toggled.connect(_on_sprint_toggled)
	_btn_action.pressed.connect(_on_action_pressed)
	Locale.language_changed.connect(_apply_texts)

	_layout()


func _exit_tree() -> void:
	_release_actions()


## Locale.t with inline id/en fallback while locale JSON lacks hud_* keys.
func _t(key: String, fb_id: String, fb_en: String) -> String:
	var s := String(Locale.t(key))
	if s != key:
		return s
	return fb_en if Locale.get_language() == "en" else fb_id


func _apply_texts() -> void:
	if _btn_jump != null and is_instance_valid(_btn_jump):
		_btn_jump.text = _t("hud_jump", "Lompat", "Jump")
		_btn_sprint.text = _t("hud_sprint", "Sprint", "Sprint")
		_btn_action.text = _t("hud_action", "Aksi", "Action")


## Connect this layer to the local player node. Also makes the layer visible:
## it must only be on screen while a local player exists.
func bind_player(p: Node) -> void:
	_player = p
	visible = true
	set_process_input(true)
	if p.has_method("set_touch_move"):
		move_changed.connect(p.set_touch_move)
	if p.has_method("add_look"):
		look_delta.connect(p.add_look)
	if p.has_method("request_jump"):
		jump_pressed.connect(p.request_jump)
	if p.has_method("set_touch_sprint"):
		sprint_toggled.connect(p.set_touch_sprint)
	_layout()


func unbind() -> void:
	_player = null
	visible = false
	set_process_input(false)
	_stick_index = -1
	_look_index = -1
	_release_actions()
	move_changed.emit(Vector2.ZERO)


func _release_actions() -> void:
	Input.action_release("jump")
	Input.action_release("sprint")
	Input.action_release("action_a")


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not visible or _player == null or not is_instance_valid(_player):
		return
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Desktop fallback so the controls can be tested with a mouse.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		_mouse_down = event.pressed
		_handle_touch(MOUSE_TOUCH_ID, event.position, event.pressed)
	elif event is InputEventMouseMotion and _mouse_down:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		_handle_drag(MOUSE_TOUCH_ID, event.position)


func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _over_button(pos):
			return  # Buttons handle themselves through the GUI.
		if _in_stick_zone(pos):
			_stick_index = index
			_stick_center = _clamp_stick_center(pos)
			_stick.position = _stick_center - _stick.size * 0.5
			_apply_stick(Vector2.ZERO)
		elif _look_index == -1:
			_look_index = index
			_look_last = pos
	else:
		if index == _stick_index:
			_stick_index = -1
			_apply_stick(Vector2.ZERO)
			_stick.position = _rest_stick_pos
		elif index == _look_index:
			_look_index = -1


func _handle_drag(index: int, pos: Vector2) -> void:
	if index == _stick_index:
		_apply_stick(pos - _stick_center)
	elif index == _look_index:
		var d := pos - _look_last
		_look_last = pos
		if d.length_squared() > 0.0:
			look_delta.emit(d)


func _apply_stick(offset: Vector2) -> void:
	var v := offset.limit_length(STICK_RADIUS)
	if _stick != null and is_instance_valid(_stick) and _stick.has_method("set_knob"):
		_stick.set_knob(v)
	var out := v / STICK_RADIUS
	if out.length() < DEAD_ZONE:
		out = Vector2.ZERO
	move_changed.emit(out)


func _in_stick_zone(pos: Vector2) -> bool:
	var vs := _view_size()
	return pos.x < vs.x * 0.5 and pos.y > vs.y * 0.3


func _clamp_stick_center(pos: Vector2) -> Vector2:
	var vs := _view_size()
	var m := STICK_RADIUS + 16.0
	return Vector2(
		clampf(pos.x, m, maxf(m, vs.x * 0.5 - 16.0)),
		clampf(pos.y, maxf(m, vs.y * 0.3 + m * 0.5), maxf(m + 1.0, vs.y - m))
	)


func _over_button(pos: Vector2) -> bool:
	for r in _button_rects:
		if r is Rect2 and (r as Rect2).has_point(pos):
			return true
	return false


func _view_size() -> Vector2:
	if _root != null and _root.size.x > 1.0:
		return _root.size
	var vp := get_viewport()
	if vp != null:
		return vp.get_visible_rect().size
	return Vector2(1280, 720)


# ------------------------------------------------------------------ buttons

func _on_jump_down() -> void:
	Input.action_press("jump")
	jump_pressed.emit()


func _on_jump_up() -> void:
	Input.action_release("jump")
	jump_released.emit()


func _on_sprint_toggled(on: bool) -> void:
	if on:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	sprint_toggled.emit(on)


func _on_action_pressed() -> void:
	Input.action_press("action_a")
	action_a_pressed.emit()
	if is_inside_tree():
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			Input.action_release("action_a"))


# ------------------------------------------------------------------ build

func _make_button(text: String, side: float, accent: bool) -> Button:
	# Prefer UiKit when available (>=48dp targets, consistent styling).
	if ResourceLoader.exists(UIKIT_PATH):
		var uk: Variant = load(UIKIT_PATH)
		if uk != null and uk.has_method("make_button"):
			var made: Variant = uk.make_button(text, Vector2(side, side), accent)
			if made is Button:
				return made
	# Fallback: plain translucent round button.
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.18, 0.78)
	sb.set_corner_radius_all(int(side * 0.5))
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.22)
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(0.2, 0.22, 0.3, 0.85)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.18, 0.42, 0.85, 0.9)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(side, side)
	return b


func _layout() -> void:
	if _root == null or _btn_jump == null:
		return
	var vs := _view_size()
	var jump := 72.0
	_btn_jump.custom_minimum_size = Vector2(jump, jump)
	_btn_jump.size = Vector2(jump, jump)
	_btn_jump.position = Vector2(vs.x - jump - 18.0, vs.y - jump - 22.0)
	_btn_sprint.custom_minimum_size = Vector2(64, 64)
	_btn_sprint.size = Vector2(64, 64)
	_btn_sprint.position = Vector2(vs.x - jump - 18.0 - 64.0 - 14.0, vs.y - 64.0 - 22.0)
	_btn_action.custom_minimum_size = Vector2(60, 60)
	_btn_action.size = Vector2(60, 60)
	_btn_action.position = Vector2(vs.x - 60.0 - 24.0, vs.y - jump - 22.0 - 60.0 - 14.0)
	var stick_size := Vector2(STICK_RADIUS * 2.0 + 12.0, STICK_RADIUS * 2.0 + 12.0)
	_stick.size = stick_size
	_rest_stick_pos = Vector2(20.0, vs.y - stick_size.y - 20.0)
	if _stick_index == -1:
		_stick.position = _rest_stick_pos
	_refresh_button_rects()


func _refresh_button_rects() -> void:
	_button_rects.clear()
	for b in [_btn_jump, _btn_sprint, _btn_action]:
		if b != null and is_instance_valid(b):
			_button_rects.append(Rect2(b.position, b.size))
