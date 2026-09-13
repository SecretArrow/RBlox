extends Control
## AvatarEditor — editor avatar RBlox (landscape, touch, tombol >= 48px).
## Kiri: preview 3D (SubViewport, auto-rotate + drag yaw). Kanan: tab slot
## kosmetik, palet 24 warna (skin/shirt/pants/hair), 8 preset, Acak, Simpan.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const AvatarBuilder := preload("res://scripts/avatar/avatar_builder.gd")
const CosmeticsDB := preload("res://scripts/avatar/cosmetics_db.gd")

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SLOTS := ["hat", "hair", "face", "shirt", "pants", "accessory", "wings", "back", "hand"]
const PARTS := ["skin", "shirt", "pants", "hair"]
const PALETTE := [
	"#f5d3b3",
	"#e0b088",
	"#c68642",
	"#8d5524",
	"#5c3317",
	"#ffffff",
	"#d9d9d9",
	"#8a8a8a",
	"#3a3a3a",
	"#1a1a1a",
	"#e74c3c",
	"#c0392b",
	"#e91e63",
	"#ff69b4",
	"#9b59b6",
	"#6a3fa0",
	"#4f8cff",
	"#2f6fed",
	"#3498db",
	"#5ad48a",
	"#2f9e5f",
	"#27ae60",
	"#f1c40f",
	"#f39c12"
]
const SLOT_FB := {
	"hat": ["slot_hat", "Topi", "Hat"],
	"hair": ["slot_hair", "Rambut", "Hair"],
	"face": ["slot_face", "Wajah", "Face"],
	"shirt": ["slot_shirt", "Baju", "Shirt"],
	"pants": ["slot_pants", "Celana", "Pants"],
	"accessory": ["slot_acc", "Aksesori", "Acc"],
	"wings": ["slot_wings", "Sayap", "Wings"],
	"back": ["slot_back", "Punggung", "Back"],
	"hand": ["slot_hand", "Tangan", "Hand"]
}
const PART_FB := {
	"skin": ["part_skin", "Kulit", "Skin"],
	"shirt": ["part_shirt", "Baju", "Shirt"],
	"pants": ["part_pants", "Celana", "Pants"],
	"hair": ["part_hair", "Rambut", "Hair"]
}

var _cfg: Dictionary = {}
var _holder: Node3D = null
var _rig: Node3D = null
var _yaw: float = 0.0
var _drag: bool = false
var _active_part: String = "shirt"
var _part_group: ButtonGroup = null
var _toast_layer: Control = null
var _saving: bool = false


func _ready() -> void:
	theme = Settings.get_theme()
	_cfg = _sanitize(GameState.avatar_config.duplicate(true))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _process(delta: float) -> void:
	if _holder != null and is_instance_valid(_holder):
		if not _drag:
			_yaw += delta * 0.5
		_holder.rotation.y = _yaw
	if _rig != null and is_instance_valid(_rig) and _rig.has_method("animate"):
		_rig.animate(delta, 0.0, true)


# ------------------------------------------------------------------ UI ----
func _build_ui() -> void:
	add_child(
		UiKit.make_background(UiKit.COL_BG_DARK if Settings.is_dark_mode() else UiKit.COL_BG_LIGHT)
	)
	_toast_layer = UiKit.make_toast_layer()
	add_child(_toast_layer)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_top_btn(_tr("avatar_back", "Kembali", "Back"), _goto_menu, false, 140))
	var title := UiKit.make_title(_tr("avatar_title", "Editor Avatar", "Avatar Editor"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_top_btn(_tr("avatar_random", "Acak", "Random"), _randomize_cfg, false, 130))
	top.add_child(_top_btn(_tr("avatar_save", "Simpan", "Save"), _save, true, 150))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_3d())
	body.add_child(_build_right())


func _top_btn(text: String, cb: Callable, accent: bool, w: float) -> Button:
	var b := UiKit.make_button(text, Vector2(w, 52), accent)
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------------ 3D ----
func _build_3d() -> Control:
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cont.size_flags_stretch_ratio = 0.45
	cont.gui_input.connect(_on_view_input)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	cont.add_child(sv)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#232b3d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = env
	sv.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sv.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 3.1)
	cam.rotation_degrees = Vector3(-9, 0, 0)
	sv.add_child(cam)
	_holder = Node3D.new()
	sv.add_child(_holder)
	_spawn_rig()
	return cont


func _spawn_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.queue_free()
	_rig = null
	if _holder != null and is_instance_valid(_holder):
		_rig = AvatarBuilder.build(_cfg)
		if _rig != null:
			_holder.add_child(_rig)


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		_drag = ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT
	elif ev is InputEventMouseMotion and _drag and _holder != null and is_instance_valid(_holder):
		_yaw -= ev.relative.x * 0.012
		_holder.rotation.y = _yaw


# --------------------------------------------------------------- panel ----
func _build_right() -> Control:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.55
	right.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 320)
	scroll.add_child(tabs)
	for slot in SLOTS:
		tabs.add_child(_slot_page(slot))
	right.add_child(_palette_panel())
	right.add_child(_preset_grid())
	return right


func _cell(text: String, cb: Callable) -> Button:
	var b := UiKit.make_button(text, Vector2(124, 52), false)
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _slot_page(slot: String) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_child(_cell(_tr("avatar_none", "Tanpa", "None"), _equip.bind(slot, "")))
	for it in CosmeticsDB.items_for_slot(slot):
		var id := str(it.get("id", ""))
		if id != "":
			grid.add_child(_cell(_item_name(it), _equip.bind(slot, id)))
	return grid


func _palette_panel() -> Control:
	var panel := UiKit.make_panel(Color(0, 0, 0, 0.18))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", 8)
	v.add_child(parts)
	_part_group = ButtonGroup.new()
	for p in PARTS:
		var fb: Array = PART_FB.get(p, [p, p, p])
		var b := UiKit.make_button(_tr(fb[0], fb[1], fb[2]), Vector2(0, 48), false)
		b.toggle_mode = true
		b.button_group = _part_group
		b.button_pressed = p == _active_part
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _active_part = p)
		parts.add_child(b)
	var grid := GridContainer.new()
	grid.columns = 12
	v.add_child(grid)
	for hex in PALETTE:
		grid.add_child(_swatch(hex))
	return panel


func _swatch(hex: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(hex)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.4)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(_apply_color.bind(hex))
	return b


func _preset_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	for p in CosmeticsDB.presets():
		grid.add_child(_cell(_item_name(p), _apply_preset.bind(p)))
	return grid


# --------------------------------------------------------------- aksi -----
func _equip(slot: String, id: String) -> void:
	var eq: Dictionary = _cfg.get("equipped", {})
	eq[slot] = id
	_cfg["equipped"] = eq
	if slot == "face":
		if id == "":
			_cfg["face"] = "smile"
		else:
			var pr: Variant = CosmeticsDB.get_item(id).get("param", {})
			if pr is Dictionary and pr.has("expression"):
				_cfg["face"] = str(pr.get("expression", "smile"))
	_spawn_rig()


func _apply_color(hex: String) -> void:
	_cfg[_active_part] = hex
	_spawn_rig()


func _apply_preset(p: Dictionary) -> void:
	var c: Variant = p.get("config", {})
	if c is Dictionary:
		_cfg = _sanitize(c.duplicate(true))
		_spawn_rig()


func _randomize_cfg() -> void:
	for p in PARTS:
		_cfg[p] = PALETTE.pick_random()
	_cfg["face"] = ["smile", "cool", "sad", "angry", "neutral"].pick_random()
	var eq: Dictionary = _cfg.get("equipped", {})
	for slot in SLOTS:
		var items := CosmeticsDB.items_for_slot(slot)
		eq[slot] = (
			"" if items.is_empty() or randf() < 0.2 else str(items.pick_random().get("id", ""))
		)
	_cfg["equipped"] = eq
	_spawn_rig()


func _save() -> void:
	if _saving:
		return
	_saving = true
	GameState.set_avatar_config(_cfg.duplicate(true))
	if GameState.unlock_achievement("avatar_customized"):
		UiKit.show_toast(
			_toast_layer, _tr("ach_avatar_customized", "Avatar tersimpan!", "Avatar customized!")
		)
		await get_tree().create_timer(0.9).timeout
	_goto_menu()


func _goto_menu() -> void:
	if ResourceLoader.exists(SCENE_MENU):
		GameState.goto_scene(SCENE_MENU)


# -------------------------------------------------------------- helper ----
func _sanitize(cfg: Dictionary) -> Dictionary:
	var def: Dictionary = GameState.DEFAULT_AVATAR
	for k in PARTS + ["face"]:
		if not cfg.has(k) or not (cfg[k] is String) or str(cfg[k]) == "":
			cfg[k] = str(def.get(k, ""))
	var eq: Variant = cfg.get("equipped", {})
	if not (eq is Dictionary):
		eq = {}
	var defeq: Variant = def.get("equipped", {})
	for s in SLOTS:
		if not eq.has(s):
			eq[s] = str(defeq.get(s, ""))
	cfg["equipped"] = eq
	return cfg


func _tr(key: String, fb_id: String, fb_en: String) -> String:
	var v := Locale.t(key)
	if v != key:
		return v
	return fb_en if Locale.get_language() == "en" else fb_id


func _item_name(it: Dictionary) -> String:
	var nm: Variant = it.get("name", {})
	if nm is Dictionary and not nm.is_empty():
		return str(nm.get(Locale.get_language(), nm.get("id", "")))
	return str(it.get("id", ""))
