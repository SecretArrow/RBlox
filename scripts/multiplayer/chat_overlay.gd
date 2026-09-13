extends CanvasLayer
## Overlay chat multiplayer: log pesan (maks 8 baris, fade tiap baris lama),
## input teks + kirim (hanya bila chat diizinkan orang tua), dan grid
## quick emote. Semua pengiriman lewat facade Net.send_chat().

const MAX_LINES := 8
const INPUT_MAX_CHARS := 200
const EMOTES: Array[String] = [
	"Halo",
	"GG",
	"Siap!",
	"Tunggu",
	"Ayo bangun!",
	":)",
	":D",
	"WOW",
	"LOL",
	"?",
]
const PANEL_MIN_WIDTH := 420.0
const BTN_MIN_HEIGHT := 48.0

var _panel: PanelContainer
var _log_box: VBoxContainer
var _input_row: HBoxContainer
var _line_edit: LineEdit
var _send_btn: Button
var _emote_grid: GridContainer
var _disabled_label: Label
var _fade_tween: Tween


func _ready() -> void:
	layer = 20
	_build_ui()
	Net.chat_received.connect(_on_chat_received)
	Settings.setting_changed.connect(_on_setting_changed)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12
	)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)

	_log_box = VBoxContainer.new()
	_log_box.alignment = BoxContainer.ALIGNMENT_END
	_log_box.add_theme_constant_override("separation", 2)
	root.add_child(_log_box)

	_disabled_label = Label.new()
	_disabled_label.text = Locale.t("chat_disabled")
	_disabled_label.add_theme_font_size_override("font_size", 14)
	_disabled_label.visible = not Settings.chat_enabled()
	root.add_child(_disabled_label)

	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 6)
	_input_row.visible = Settings.chat_enabled()
	root.add_child(_input_row)

	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = Locale.t("mp_chat_hint")
	_line_edit.max_length = INPUT_MAX_CHARS
	_line_edit.custom_minimum_size = Vector2(0, BTN_MIN_HEIGHT)
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.text_submitted.connect(_on_text_submitted)
	_input_row.add_child(_line_edit)

	_send_btn = Button.new()
	_send_btn.text = Locale.t("mp_chat_send")
	_send_btn.custom_minimum_size = Vector2(100, BTN_MIN_HEIGHT)
	_send_btn.pressed.connect(_on_send_pressed)
	_input_row.add_child(_send_btn)

	_emote_grid = GridContainer.new()
	_emote_grid.columns = 5
	_emote_grid.add_theme_constant_override("h_separation", 4)
	_emote_grid.add_theme_constant_override("v_separation", 4)
	root.add_child(_emote_grid)
	for emote in EMOTES:
		var btn := Button.new()
		btn.text = emote
		btn.custom_minimum_size = Vector2(76, BTN_MIN_HEIGHT)
		btn.pressed.connect(_on_emote_pressed.bind(emote))
		_emote_grid.add_child(btn)


# ----------------------------------------------------------------- API


func toggle() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	if _panel.visible and Settings.chat_enabled():
		_line_edit.grab_focus()


func open_emotes() -> void:
	if _panel == null:
		return
	_panel.visible = true
	_emote_grid.visible = not _emote_grid.visible


# ------------------------------------------------------------- handlers


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_chat"):
		toggle()
		get_viewport().set_input_as_handled()


func _on_text_submitted(_text: String) -> void:
	_send_text()


func _on_send_pressed() -> void:
	_send_text()


func _on_emote_pressed(emote: String) -> void:
	Net.send_chat(emote, true)


func _on_chat_received(sender: String, text: String, is_emote: bool) -> void:
	var prefix := ""
	if is_emote:
		prefix = "* "
	_add_line("%s%s: %s" % [prefix, sender, text])


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "chat_enabled":
		var enabled := Settings.chat_enabled()
		_input_row.visible = enabled
		_disabled_label.visible = not enabled


# ------------------------------------------------------------- internal


func _send_text() -> void:
	var text := _line_edit.text.strip_edges()
	if text == "":
		return
	Net.send_chat(text, false)
	_line_edit.clear()


func _add_line(line: String) -> void:
	var l := Label.new()
	l.text = line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_MIN_WIDTH - 24.0, 0)
	l.add_theme_font_size_override("font_size", 14)
	_log_box.add_child(l)
	while _log_box.get_child_count() > MAX_LINES:
		var oldest := _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()
	_refresh_fades()


func _refresh_fades() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	var kids := _log_box.get_children()
	for i in kids.size():
		var lbl := kids[i] as Label
		if lbl == null:
			continue
		var depth := (kids.size() - 1) - i
		var target := clampf(1.0 - 0.12 * float(depth), 0.25, 1.0)
		_fade_tween.tween_property(lbl, "modulate:a", target, 0.25)
