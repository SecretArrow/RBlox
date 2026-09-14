extends CanvasLayer
## BuildHUD — toolbar mode build (CanvasLayer layer 10, sentuh, >= 48dp).
## game.gd: bind_build_manager(bm) + set_camera(cam) + open()/close().
## Tutup: bm.activate(false) + HUD queue_free diri; semua aksi di-guard.

signal closed

const BlockLibrary := preload("res://scripts/build/block_library.gd")
const SAVELOAD_PATH := "res://scripts/ui/save_load_panel.gd"
const CODING_PATH := "res://scripts/build/block_coding.gd"
const TOAST_PATH := "res://scripts/ui/toast.gd"
const BTN := Vector2(56, 56)
const SWATCH := 40.0

var _bm: Node = null
var _root: Control
var _tool_group := ButtonGroup.new()
var _anchor_btn: Button
var _shape_opt: OptionButton
var _mat_opt: OptionButton
var _paint_opt: OptionButton
var _swatch_btns: Dictionary = {}
var _selected_hex := ""
var _saveload: Control = null
var _coding: Control = null


func _ready() -> void:
	layer = 10
	_selected_hex = BlockLibrary.DEFAULT_COLOR
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Settings.get_theme()
	add_child(_root)
	_build_bottom()
	visible = false


func _process(_delta: float) -> void:
	if _bm == null or not is_instance_valid(_bm):
		return
	var on := bool(_bm.get("active"))  # EN: BuildManager.active
	if visible != on:
		visible = on
		if not on:
			closed.emit()


## Buka mode build: tampilkan HUD + aktifkan BuildManager.
func open() -> void:
	visible = true
	_call_bm("activate", [true])


## Tutup mode build: matikan BuildManager, sembunyikan, bebaskan HUD.
func close() -> void:
	_call_bm("activate", [false])
	visible = false
	closed.emit()


## Terima kamera dari game.gd; diteruskan ke BuildManager bila didukung.
func set_camera(cam: Camera3D) -> void:
	if _bm != null and _bm.has_method("set_camera"):
		_bm.call("set_camera", cam)


## Sambungkan tombol ke BuildManager.
func bind_build_manager(bm: Node) -> void:
	_bm = bm


# ------------------------------------------------------------------ helpers
func _btn(text: String, cb: Callable, size: Vector2 = BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _tool_btn(text: String, tool_name: String) -> Button:
	var b := _btn(text, _on_tool.bind(tool_name))
	b.toggle_mode = true
	b.button_group = _tool_group
	return b


## Satu baris tombol: HBox di dalam HScrollContainer (scroll horizontal).
func _row(parent: Control, h: float) -> HBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, h)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(sc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	sc.add_child(row)
	return row


func _opt(items: Array, cb: Callable, w: float) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.custom_minimum_size = Vector2(w, BTN.y)
	ob.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		ob.item_selected.connect(cb)
	return ob


func _build_bottom() -> void:
	var panel := PanelContainer.new()
	panel.name = "Toolbar"
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.06, 0.08, 0.13, 0.93)
	tsb.corner_radius_top_left = 18
	tsb.corner_radius_top_right = 18
	tsb.border_width_top = 1
	tsb.border_color = Color(1, 1, 1, 0.08)
	tsb.shadow_color = Color(0, 0, 0, 0.40)
	tsb.shadow_size = 12
	tsb.content_margin_left = 10.0
	tsb.content_margin_right = 10.0
	tsb.content_margin_top = 10.0
	tsb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", tsb)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 8.0
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var tools := _row(col, BTN.y + 8.0)
	tools.add_child(_tool_btn(Locale.t("build_place"), "place"))
	tools.add_child(_tool_btn(Locale.t("build_remove"), "remove"))
	tools.add_child(_tool_btn(Locale.t("build_rotate"), "rotate"))
	tools.add_child(_btn(Locale.t("terrain_raise"), _call_bm.bind("terrain_raise", [])))
	tools.add_child(_btn(Locale.t("terrain_lower"), _call_bm.bind("terrain_lower", [])))
	tools.add_child(_btn(Locale.t("terrain_flatten"), _call_bm.bind("terrain_flatten", [])))
	_paint_opt = _opt(_paints(), Callable(), 110.0)
	tools.add_child(_paint_opt)
	tools.add_child(_btn(Locale.t("terrain_paint"), _on_paint))
	var sel := _row(col, BTN.y + 8.0)
	_shape_opt = _opt(BlockLibrary.SHAPES, _on_shape, 130.0)
	_shape_opt.select(0)
	sel.add_child(_shape_opt)
	_mat_opt = _opt(BlockLibrary.MATERIALS, _on_mat, 130.0)
	_mat_opt.select(0)
	sel.add_child(_mat_opt)
	_anchor_btn = _btn(Locale.t("build_anchor"), _on_anchor)
	_anchor_btn.toggle_mode = true
	sel.add_child(_anchor_btn)
	sel.add_child(_btn(Locale.t("build_undo"), _call_bm.bind("undo", [])))
	sel.add_child(_btn(Locale.t("build_redo"), _call_bm.bind("redo", [])))
	sel.add_child(_btn(Locale.t("build_save_load"), _open_save_load))
	sel.add_child(_btn(Locale.t("build_coding"), _open_coding))
	sel.add_child(_btn(Locale.t("build_close"), close))
	var pal := _row(col, SWATCH + 8.0)
	for hex in BlockLibrary.COLORS:
		var sw := _btn("", _on_color.bind(hex), Vector2(SWATCH, SWATCH))
		_style_swatch(sw, hex, hex == _selected_hex)
		_swatch_btns[hex] = sw
		pal.add_child(sw)


func _style_swatch(btn: Button, hex: String, selected: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(hex) if Color.html_is_valid(hex) else Color.WHITE
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3 if selected else 2)
	sb.border_color = Color(1, 1, 1, 0.95) if selected else Color(0, 0, 0, 0.5)
	if selected:
		sb.shadow_color = Color(1, 1, 1, 0.55)
		sb.shadow_size = 4
	btn.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.border_color = Color(1, 1, 1, 0.9)
	for st in ["hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sbp)


## EN: paint names mirror Terrain.PAINTS (kept in sync here).
func _paints() -> Array:
	return ["grass", "dirt", "rock", "sand"]


# ----------------------------------------------------------------- callbacks


func _call_bm(method: String, args: Array = []) -> void:
	if _bm != null and is_instance_valid(_bm) and _bm.has_method(method):
		_bm.callv(method, args)


func _on_tool(tool_name: String) -> void:
	if _anchor_btn != null:
		_anchor_btn.set_pressed_no_signal(false)
	_call_bm("set_tool", [tool_name])


func _on_anchor() -> void:
	var on := _anchor_btn != null and _anchor_btn.button_pressed
	if _bm != null and _bm.has_method("set_anchored"):
		_bm.call("set_anchored", [on])
	else:
		_call_bm("set_tool", ["anchor" if on else "place"])


func _on_shape(idx: int) -> void:
	if idx >= 0 and idx < BlockLibrary.SHAPES.size():
		_call_bm("set_shape", [BlockLibrary.SHAPES[idx]])


func _on_mat(idx: int) -> void:
	if idx >= 0 and idx < BlockLibrary.MATERIALS.size():
		_call_bm("set_material", [BlockLibrary.MATERIALS[idx]])


func _on_color(hex: String) -> void:
	_selected_hex = hex
	for h in _swatch_btns:
		var btn: Button = _swatch_btns[h]
		if btn != null and is_instance_valid(btn):
			_style_swatch(btn, String(h), String(h) == hex)
	_call_bm("set_color", [hex])


func _on_paint() -> void:
	var idx := _paint_opt.selected if _paint_opt != null else -1
	var paints := _paints()
	if idx >= 0 and idx < paints.size():
		_call_bm("terrain_paint", [str(paints[idx])])


func _selected_block() -> Node3D:
	if _bm != null and _bm.has_method("get_selected_block"):
		var n: Variant = _bm.call("get_selected_block")
		if n is Node3D:
			return n
	return null


# -------------------------------------------------------------------- panels


func _open_panel(path: String) -> Control:
	if not ResourceLoader.exists(path):
		return null
	var scr := load(path) as GDScript
	if scr == null:
		return null
	var panel: Control = scr.new()
	_root.add_child(panel)
	return panel


func _open_save_load() -> void:
	if _saveload == null:
		_saveload = _open_panel(SAVELOAD_PATH)
	if _saveload == null:
		_toast(Locale.t("error_not_impl"))
		return
	_saveload.open(_root)


func _open_coding() -> void:
	var target := _selected_block()
	if target == null:
		_toast(Locale.t("build_select_first"))
	if _coding == null:
		_coding = _open_panel(CODING_PATH)
	if _coding == null:
		_toast(Locale.t("error_not_impl"))
		return
	_coding.open(_root, target)


func _toast(msg: String) -> void:
	if ResourceLoader.exists(TOAST_PATH):
		var t: Variant = load(TOAST_PATH)
		if t != null and t.has_method("show"):
			t.show(self, msg)
			return
	print("[BuildHUD] ", msg)
