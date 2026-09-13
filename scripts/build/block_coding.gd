extends Control
## BlockCoding — coding visual tap-based untuk blok/NPC terpilih; program
## Array of {"cmd","arg"} disimpan ke meta target (block_data.script/script).
## MVP: langkah async jeda 0.4 s; repeat_n ulang SELURUH program min(n,10)
## (loop luar); wait maks 5 s; if_player_near stop bila pemain jauh. Alpha: penuh.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const MINI_PATH := "res://scripts/build/mini_script.gd"
const TOAST_PATH := "res://scripts/ui/toast.gd"
const COMMANDS: Array[String] = [
        "move_forward",
        "turn_left",
        "turn_right",
        "jump",
        "wait",
        "repeat_n",
        "if_player_near",
        "set_color",
        "say"
]
const ARGS := {
        "wait": "1.0", "repeat_n": "2", "if_player_near": "4.0", "set_color": "#e0453a", "say": "Halo"
}
const MAX_REPEAT := 10
const STEP_DELAY := 0.4
const WAIT_MAX := 5.0

var _target: Node3D = null
var _program: Array = []
var _running := false
var _pending := ""
var _editing := -1
var _arg_row: HBoxContainer
var _arg_edit: LineEdit
var _list: ItemList


func _ready() -> void:
        visible = false
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_STOP
        theme = Settings.get_theme()
        var dim := ColorRect.new()
        dim.color = Color(0, 0, 0, 0.55)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(dim)
        var panel := PanelContainer.new()
        panel.custom_minimum_size = Vector2(760, 0)
        panel.set_anchors_preset(Control.PRESET_CENTER)
        panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
        panel.grow_vertical = Control.GROW_DIRECTION_BOTH
        add_child(panel)
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 8)
        panel.add_child(box)
        # Palet: 9 tombol perintah -> tambah {cmd, arg} ke program.
        var grid := GridContainer.new()
        grid.columns = 3
        box.add_child(grid)
        for cmd in COMMANDS:
                grid.add_child(_tap_btn(Locale.t("bc_cmd_" + cmd), _on_cmd.bind(cmd), Vector2(230, 48)))
        # Baris argumen: tambah item baru / ubah arg item terpilih.
        _arg_row = HBoxContainer.new()
        _arg_row.visible = false
        _arg_row.add_theme_constant_override("separation", 8)
        box.add_child(_arg_row)
        _arg_edit = LineEdit.new()
        _arg_edit.custom_minimum_size = Vector2(0, 48)
        _arg_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _arg_row.add_child(_arg_edit)
        _arg_row.add_child(UiKit.make_button(Locale.t("common_ok"), Vector2(96, 48), true))
        _list = ItemList.new()
        _list.custom_minimum_size = Vector2(0, 150)
        _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _list.item_selected.connect(_on_item_selected)
        box.add_child(_list)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        box.add_child(row)
        for c in [
                ["bc_up", _edit_item.bind(-1, false)],
                ["bc_down", _edit_item.bind(1, false)],
                ["common_delete", _edit_item.bind(0, true)],
                ["bc_run", func() -> void: run_script(_target)],
                ["common_save", _on_save],
                ["bc_advanced", _on_advanced],
                ["common_close", func() -> void: visible = false]
        ]:
                row.add_child(_tap_btn(Locale.t(str(c[0])), c[1]))


## Tombol tap (UiKit + sambung sinyal pressed).
func _tap_btn(text: String, cb: Callable, size: Vector2 = Vector2(120, 48)) -> Button:
        var b := UiKit.make_button(text, size, false)
        b.pressed.connect(cb)
        return b


func open(parent: Control, target: Node3D) -> void:
        if parent != null and get_parent() != parent:
                if get_parent() != null:
                        get_parent().remove_child(self)
                parent.add_child(self)
        if target == null or not is_instance_valid(target):
                # EN: no target selected — hint "select a block first", then dismiss.
                _toast(Locale.t("build_select_first"))
                return
        _target = target
        _program.clear()
        var scr: Variant = target.get_meta("block_data", {}).get(
                "script", target.get_meta("script", [])
        )
        for e in scr if scr is Array else []:
                if e is Dictionary:
                        _program.append({"cmd": str(e.get("cmd", "")), "arg": str(e.get("arg", ""))})
        _refresh_list()
        visible = true


func _on_cmd(cmd: String) -> void:
        _pending = cmd
        _editing = -1
        if not ARGS.has(cmd):
                _arg_row.visible = false
                _append(cmd, "")
                return
        _arg_edit.text = str(ARGS[cmd])
        _arg_row.visible = true


## Pilih item di list -> edit argumennya lewat baris arg yang sama.
func _on_item_selected(idx: int) -> void:
        if idx < 0 or idx >= _program.size():
                return
        var e: Dictionary = _program[idx]
        if not ARGS.has(str(e.get("cmd", ""))):
                _arg_row.visible = false
                return
        _editing = idx
        _pending = str(e.get("cmd", ""))
        _arg_edit.text = str(e.get("arg", ""))
        _arg_row.visible = true


func _on_arg_ok() -> void:
        if _pending == "":
                return
        var cmd := _pending
        var arg := _arg_edit.text.strip_edges()
        _arg_row.visible = false
        if _editing >= 0 and _editing < _program.size():
                _program[_editing]["arg"] = arg
                _refresh_list()
        else:
                _append(cmd, arg)
        _pending = ""
        _editing = -1


func _append(cmd: String, arg: String) -> void:
        _program.append({"cmd": cmd, "arg": arg})
        _refresh_list()


func _sel_index() -> int:
        var sel := _list.get_selected_items()
        return int(sel[0]) if not sel.is_empty() else -1


## dir != 0 -> geser posisi item; remove -> hapus item terpilih.
func _edit_item(dir: int, remove: bool) -> void:
        var i := _sel_index()
        if remove:
                if i >= 0:
                        _program.remove_at(i)
        elif i >= 0 and i + dir >= 0 and i + dir < _program.size():
                var e: Dictionary = _program[i]
                _program.remove_at(i)
                _program.insert(i + dir, e)
                _list.select(i + dir)
        _refresh_list()


func _refresh_list() -> void:
        _list.clear()
        for i in _program.size():
                var e: Dictionary = _program[i]
                var a := str(e.get("arg", ""))
                _list.add_item("%d. %s%s" % [i + 1, str(e.get("cmd", "")), ("  " + a) if a != "" else ""])


func run_script(target: Node3D) -> void:
        if _running or _program.is_empty():
                _toast(Locale.t("bc_running") if _running else Locale.t("bc_empty"))
                return
        if target == null or not is_instance_valid(target):
                _toast(Locale.t("bc_no_target"))
                return
        _target = target
        _running = true
        # EN: repeat_n -> run the whole program min(n, 10) times (outer loop).
        var passes := 1
        for e in _program:
                if str(e.get("cmd", "")) == "repeat_n":
                        var s := str(e.get("arg", "2"))
                        passes = clampi(int(s) if s.is_valid_int() else 2, 1, MAX_REPEAT)
                        break
        var stopped := false
        for _p in passes:
                for i in _program.size():
                        var cmd := str(_program[i].get("cmd", ""))
                        if cmd == "repeat_n":
                                continue
                        if cmd == "if_player_near":
                                var r := str(_program[i].get("arg", ""))
                                if not _player_near(float(r) if r.is_valid_float() else 4.0):
                                        _toast(Locale.t("bc_far"))
                                        stopped = true
                                        break
                                continue
                        await _exec(_program[i])
                if stopped or not _valid():
                        break
        _running = false
        if not stopped:
                _toast(Locale.t("bc_done"))


func _exec(e: Dictionary) -> void:
        if not _valid():
                return
        var arg := str(e.get("arg", ""))
        var t := get_tree()
        match str(e.get("cmd", "")):
                "move_forward":
                        _target.translate_object_local(Vector3(0, 0, -1))
                        await t.create_timer(STEP_DELAY).timeout
                "turn_left":
                        _target.rotate_y(PI * 0.5)
                        await t.create_timer(STEP_DELAY).timeout
                "turn_right":
                        _target.rotate_y(-PI * 0.5)
                        await t.create_timer(STEP_DELAY).timeout
                "jump":  # EN: small hop: +0.6 up, then back down.
                        _target.translate(Vector3(0, 0.6, 0))
                        await t.create_timer(0.3).timeout
                        if _valid():
                                _target.translate(Vector3(0, -0.6, 0))
                "wait":
                        var secs := minf(float(arg) if arg.is_valid_float() else 1.0, WAIT_MAX)
                        await t.create_timer(maxf(secs, 0.05)).timeout
                "set_color":
                        _apply_color(arg)
                "say":
                        _say(arg)


func _on_save() -> void:
        if not _valid():
                _toast(Locale.t("bc_no_target"))
                return
        var arr := _program.duplicate(true)
        var meta: Dictionary = _target.get_meta("block_data", {})
        if not meta.is_empty():
                meta["script"] = arr
                _target.set_meta("block_data", meta)
        else:
                _target.set_meta("script", arr)
        _toast(Locale.t("bc_saved"))


## Buka MiniScript (teks) dengan target yang sama.
func _on_advanced() -> void:
        if not _valid() or not ResourceLoader.exists(MINI_PATH):
                _toast(Locale.t("bc_no_target") if not _valid() else Locale.t("error_not_impl"))
                return
        var host: Control = (get_parent() as Control) if get_parent() is Control else self
        (load(MINI_PATH).new() as Node).call("open", host, _target)
        visible = false


func _player_near(radius: float) -> bool:
        if not _valid() or get_tree() == null:
                return false
        for p in get_tree().get_nodes_in_group("local_player"):
                var n3 := p as Node3D
                if n3 != null and _target.global_position.distance_to(n3.global_position) <= radius:
                        return true
        return false


func _apply_color(hex: String) -> void:
        if not _valid():
                return
        var c := hex if Color.html_is_valid(hex) else "#e0453a"
        # EN: unified color path — meta + legacy mesh + MultiMesh chunk renderer.
        var wm := load("res://scripts/world/world_manager.gd")
        if wm != null and (wm as GDScript).has_method("set_block_color"):
                (wm as GDScript).call("set_block_color", _target, c)


func _say(text: String) -> void:
        if not _valid() or text == "" or get_tree() == null:
                return
        var l := Label3D.new()
        l.text = text
        l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        l.position = Vector3(0, 1.6, 0)
        _target.add_child(l)
        get_tree().create_timer(2.0).timeout.connect(l.queue_free)


func _valid() -> bool:
        return _target != null and is_instance_valid(_target)


func _find_mesh(root: Node) -> MeshInstance3D:
        if root is MeshInstance3D:
                return root
        var found := root.find_children("*", "MeshInstance3D", true, false)
        return found[0] as MeshInstance3D if not found.is_empty() else null


func _toast(msg: String) -> void:
        if ResourceLoader.exists(TOAST_PATH):
                load(TOAST_PATH).call("show", self, msg)
        else:
                print("[BlockCoding] ", msg)
