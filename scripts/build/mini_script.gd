extends Control
## MiniScript — editor teks mini (advanced) untuk blok/NPC terpilih.
## MVP subset: parser manual per baris, whitelist perintah, TANPA akses engine.
## Bahasa penuh (loop, fungsi, event) hanya di Alpha. Format baris:
##   # komentar / var nama = ekspresi -> diabaikan / variabel lokal
##   set_color("#f00") / rotate_y(90) / move(1,0,0) / set_scale(2,1,2)
## Ekspresi dievaluasi via Expression (angka + variabel + "self", mis.
## self.position.y). Error per baris -> label merah. open(parent, target).

const TOAST_PATH := "res://scripts/ui/toast.gd"
const COMMANDS: Array[String] = ["set_color", "rotate_y", "move", "set_scale"]
const SCALE_MIN := 0.1
const SCALE_MAX := 10.0

var _target: Node3D = null
var _code: TextEdit
var _output: Label
var _self_re: RegEx
var _cmd_re: RegEx
var _assign_re: RegEx


func _ready() -> void:
	_self_re = RegEx.new()
	_self_re.compile("\\bself\\b")
	_cmd_re = RegEx.new()
	_cmd_re.compile("^([a-z_]+)\\s*\\((.*)\\)\\s*$")
	_assign_re = RegEx.new()
	_assign_re.compile("^([A-Za-z_]\\w*)\\s*=\\s*(.+)$")
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Settings.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = Locale.t("ms_title")
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
	_code = TextEdit.new()
	_code.custom_minimum_size = Vector2(0, 200)
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code.placeholder_text = 'set_color("#f00")\nrotate_y(90)\nmove(1, 0, 0)'
	v.add_child(_code)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(_btn(Locale.t("ms_run"), _on_run))
	row.add_child(_btn(Locale.t("common_save"), _on_save))
	row.add_child(_btn(Locale.t("common_close"), close))
	_output = Label.new()
	_output.custom_minimum_size = Vector2(0, 48)
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.add_theme_font_size_override("font_size", 15)
	v.add_child(_output)
	var hint := Label.new()
	hint.text = Locale.t("ms_hint")
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)


## Buka panel di atas parent dan ikat ke target blok/NPC.
func open(parent: Control, target: Node3D) -> void:
	if parent != null and get_parent() != parent:
		if get_parent() != null:
			get_parent().remove_child(self)
		parent.add_child(self)
	set_target(target)
	visible = true


func close() -> void:
	visible = false


## Ikat target dan muat script tersimpan (String) bila ada.
func set_target(node: Node3D) -> void:
	_target = node
	_code.text = ""
	_output.text = ""
	_output.remove_theme_color_override("font_color")
	if _valid():
		var meta: Dictionary = _target.get_meta("block_data", {})
		var scr: Variant = meta.get("script", _target.get_meta("script", ""))
		if scr is String:
			_code.text = scr


func _on_run() -> void:
	_output.remove_theme_color_override("font_color")
	_output.text = ""
	if not _valid():
		_fail(Locale.t("bc_no_target"))
		return
	var vars := {}
	var lines := _code.text.split("\n")
	for i in lines.size():
		var line := str(lines[i]).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var err := _run_line(line, vars)
		if err != "":
			_fail("%s %d: %s" % [Locale.t("ms_error"), i + 1, err])
			return
	_output.text = Locale.t("ms_ok")


func _fail(msg: String) -> void:
	_output.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_output.text = msg


## Simpan script (String) ke meta target sesuai skema (script "" = advanced).
func _on_save() -> void:
	if not _valid():
		_toast(Locale.t("bc_no_target"))
		return
	var meta: Dictionary = _target.get_meta("block_data", {})
	if not meta.is_empty():
		meta["script"] = _code.text
		_target.set_meta("block_data", meta)
	else:
		_target.set_meta("script", _code.text)
	_toast(Locale.t("bc_saved"))


func _run_line(line: String, vars: Dictionary) -> String:
	var body := line
	if body.begins_with("var "):
		body = body.substr(4).strip_edges()
	var m := _cmd_re.search(body)
	if m != null and m.get_string(1) in COMMANDS:
		return _run_command(m.get_string(1), m.get_string(2), vars)
	m = _assign_re.search(body)
	if m != null:
		var rhs := m.get_string(2)
		if (
			rhs.begins_with("=")
			or rhs.begins_with("!")
			or rhs.begins_with("<")
			or rhs.begins_with(">")
		):
			return Locale.t("ms_err_assign")
		var val := _eval(rhs, vars)
		if val == null:
			return Locale.t("ms_err_expr") + " " + rhs
		vars[m.get_string(1)] = val
		return ""
	return Locale.t("ms_err_line")


func _run_command(cmd: String, args_raw: String, vars: Dictionary) -> String:
	var args: Array = []
	var raw := args_raw.strip_edges()
	if raw != "":
		for part in raw.split(","):
			args.append(_eval(part, vars))
		if args.has(null):
			return Locale.t("ms_err_expr") + " " + raw
	match cmd:
		"set_color":
			if args.size() != 1 or not (args[0] is String) or not Color.html_is_valid(str(args[0])):
				return Locale.t("ms_err_color")
			_apply_color(str(args[0]))
		"rotate_y":
			if args.size() != 1 or not (args[0] is float or args[0] is int):
				return Locale.t("ms_err_num") + " rotate_y(deg)"
			_target.rotate_y(deg_to_rad(float(args[0])))
		"move":
			if args.size() != 3 or not _all_num(args):
				return Locale.t("ms_err_num") + " move(x, y, z)"
			_target.translate(Vector3(float(args[0]), float(args[1]), float(args[2])))
		"set_scale":
			if args.size() != 3 or not _all_num(args):
				return Locale.t("ms_err_num") + " set_scale(x, y, z)"
			var s := Vector3(float(args[0]), float(args[1]), float(args[2]))
			_target.scale = s.clamp(Vector3.ONE * SCALE_MIN, Vector3.ONE * SCALE_MAX)
	return ""


## Evaluasi satu token: string terkutip, literal #hex, atau ekspresi matematis.
func _eval(text: String, vars: Dictionary) -> Variant:
	var t := text.strip_edges()
	if (
		t.length() >= 2
		and ((t.begins_with('"') and t.ends_with('"')) or (t.begins_with("'") and t.ends_with("'")))
	):
		return t.substr(1, t.length() - 2)
	if t.begins_with("#"):
		return t
	var names := PackedStringArray()
	var values: Array = []
	for k in vars.keys():
		names.append(str(k))
		values.append(vars[k])
	# EN: "self" is mapped to "selfv" to avoid parser keyword clashes.
	var prepared := str(_self_re.sub(t, "selfv", true))
	names.append("selfv")
	values.append(_target)
	var expr := Expression.new()
	if expr.parse(prepared, names) != OK:
		return null
	var out: Variant = expr.execute(values, null, false)
	return null if expr.has_execute_failed() else out


func _all_num(args: Array) -> bool:
	return args.all(func(a: Variant) -> bool: return a is float or a is int)


func _apply_color(hex: String) -> void:
	if not _valid():
		return
	var mi := _find_mesh(_target)
	if mi != null:
		var m: StandardMaterial3D = null
		if mi.material_override is StandardMaterial3D:
			m = (mi.material_override as StandardMaterial3D).duplicate()
		elif mi.mesh != null and mi.mesh.surface_get_material(0) is StandardMaterial3D:
			m = (mi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		if m == null:
			m = StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		mi.material_override = m
	var meta: Dictionary = _target.get_meta("block_data", {})
	if not meta.is_empty():
		meta["color"] = hex
		_target.set_meta("block_data", meta)


func _valid() -> bool:
	return _target != null and is_instance_valid(_target)


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	var found := root.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(48, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _toast(msg: String) -> void:
	if ResourceLoader.exists(TOAST_PATH):
		load(TOAST_PATH).call("show", self, msg)
	else:
		print("[MiniScript] ", msg)
