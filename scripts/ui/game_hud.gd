extends CanvasLayer
## GameHUD — HUD in-game: profil kesehatan, minimap, objective, kontrol sentuh, toast.
## Hanya MEMBACA group/sinyal modul lain (tidak meng-instance player/build manager):
## - group "game": request_pause(), toggle_build_mode()
## - group "local_player": sinyal health_changed(hp, max_hp), died
## - group "mode_controller": get_objective_text()
## - group "env_weather": cycle_weather(), get_weather()
## - node "ChatOverlay" (cari di root): toggle(), open_emotes()
## Achievement: GameState.achievement_unlocked -> toast.

const Toast := preload("res://scripts/ui/toast.gd")
const Screenshot := preload("res://scripts/meta/screenshot.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

const MARGIN := 16.0
const BTN_MIN := 48.0
const JOYSTICK_CLEARANCE := 150.0
const MAP_SIZE := 160.0

var _root: Control
var _profile_panel: PanelContainer
var _name_label: Label
var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _health_text: Label
var _fps_label: Label
var _objective: PanelContainer
var _objective_label: Label
var _minimap: Control = null
var _build_btn: Button = null
var _weather_btn: Button = null
var _right_ctl: Control = null
var _player: Node = null


func _ready() -> void:
        layer = 1
        _build_ui()
        _apply_world_settings()
        _try_bind_player()

        var retry := Timer.new()
        retry.wait_time = 1.0
        retry.autostart = true
        retry.timeout.connect(_try_bind_player)
        add_child(retry)

        var obj_timer := Timer.new()
        obj_timer.wait_time = 0.5
        obj_timer.autostart = true
        obj_timer.timeout.connect(_poll_objective)
        add_child(obj_timer)

        var fps_timer := Timer.new()
        fps_timer.wait_time = 0.5
        fps_timer.autostart = true
        fps_timer.timeout.connect(_poll_fps)
        add_child(fps_timer)

        GameState.achievement_unlocked.connect(_on_achievement)

        # Sembunyikan tombol duplikat bila TouchControls (joystick) aktif
        _hide_dup_actions.call_deferred()


func _exit_tree() -> void:
        Input.action_release("jump")
        Input.action_release("action_a")
        Input.action_release("sprint")


func _build_ui() -> void:
        _root = Control.new()
        _root.name = "HUDRoot"
        _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _root.theme = Settings.get_theme()
        add_child(_root)

        # ---- Kiri-atas: kartu profil (nama + health) + chip FPS ----
        var top_left := VBoxContainer.new()
        top_left.name = "TopLeft"
        top_left.add_theme_constant_override("separation", 6)
        top_left.set_anchors_and_offsets_preset(
                Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN)
        )
        top_left.grow_horizontal = Control.GROW_DIRECTION_END
        top_left.grow_vertical = Control.GROW_DIRECTION_END
        _root.add_child(top_left)

        var profile := PanelContainer.new()
        profile.name = "ProfilePanel"
        profile.add_theme_stylebox_override("panel", _glass(12, 8.0))
        top_left.add_child(profile)
        _profile_panel = profile

        var pv := VBoxContainer.new()
        pv.add_theme_constant_override("separation", 4)
        profile.add_child(pv)

        _name_label = Label.new()
        _name_label.text = String(GameState.player_name)
        _name_label.add_theme_font_size_override("font_size", 14)
        pv.add_child(_name_label)

        var hp_holder := Control.new()
        hp_holder.custom_minimum_size = Vector2(200.0, 18.0)
        hp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pv.add_child(hp_holder)

        _health_bar = ProgressBar.new()
        _health_bar.min_value = 0.0
        _health_bar.max_value = 100.0
        _health_bar.value = 100.0
        _health_bar.show_percentage = false
        _health_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var hp_bg := StyleBoxFlat.new()
        hp_bg.bg_color = Color(0.0, 0.0, 0.0, 0.45)
        hp_bg.set_corner_radius_all(7)
        _health_fill = StyleBoxFlat.new()
        _health_fill.bg_color = Color("#4ad48a")
        _health_fill.set_corner_radius_all(7)
        _health_fill.shadow_color = Color(1, 1, 1, 0.25)
        _health_fill.shadow_size = 1
        _health_bar.add_theme_stylebox_override("background", hp_bg)
        _health_bar.add_theme_stylebox_override("fill", _health_fill)
        hp_holder.add_child(_health_bar)

        _health_text = Label.new()
        _health_text.text = "100/100"
        _health_text.add_theme_font_size_override("font_size", 11)
        _health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _health_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _health_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hp_holder.add_child(_health_text)

        var fps_chip := PanelContainer.new()
        fps_chip.name = "FpsChip"
        fps_chip.add_theme_stylebox_override("panel", _glass(9, 4.0))
        fps_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _fps_label = Label.new()
        _fps_label.text = "60 FPS"
        _fps_label.add_theme_font_size_override("font_size", 12)
        _fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
        _fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        fps_chip.add_child(_fps_label)
        top_left.add_child(fps_chip)

        # ---- Kanan-atas: minimap + tombol Pause (48dp) ----
        var right_col := VBoxContainer.new()
        right_col.add_theme_constant_override("separation", 8)
        right_col.set_anchors_and_offsets_preset(
                Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN)
        )
        right_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        right_col.grow_vertical = Control.GROW_DIRECTION_END
        _root.add_child(right_col)

        _minimap = MinimapScript.new()
        right_col.add_child(_minimap)

        var pause_btn := Button.new()
        pause_btn.text = _t("hud_pause", "Jeda", "Pause")
        pause_btn.custom_minimum_size = Vector2(MAP_SIZE, BTN_MIN)
        pause_btn.pressed.connect(_on_pause)
        right_col.add_child(pause_btn)

        # ---- Tengah-atas: objective (poll mode_controller) ----
        _objective = PanelContainer.new()
        _objective.name = "ObjectivePanel"
        var osb := _glass(12, 6.0)
        osb.border_width_left = 3
        osb.border_color = Color("#4f8cff")
        _objective.add_theme_stylebox_override("panel", osb)
        _objective.set_anchors_and_offsets_preset(
                Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(MARGIN)
        )
        _objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _objective.grow_vertical = Control.GROW_DIRECTION_END
        _objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _objective.visible = false
        _root.add_child(_objective)

        _objective_label = Label.new()
        _objective_label.add_theme_font_size_override("font_size", 14)
        _objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _objective.add_child(_objective_label)

        # ---- Kanan-bawah: kolom kontrol gerak ----
        _right_ctl = VBoxContainer.new()
        var right_ctl: VBoxContainer = _right_ctl
        right_ctl.add_theme_constant_override("separation", 10)
        right_ctl.set_anchors_and_offsets_preset(
                Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN)
        )
        right_ctl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        right_ctl.grow_vertical = Control.GROW_DIRECTION_BEGIN
        _root.add_child(right_ctl)

        var jump_btn := Button.new()
        jump_btn.text = _t("hud_jump", "Lompat", "Jump")
        jump_btn.custom_minimum_size = Vector2(132.0, 72.0)
        jump_btn.button_down.connect(func() -> void: Input.action_press("jump"))
        jump_btn.button_up.connect(func() -> void: Input.action_release("jump"))
        right_ctl.add_child(jump_btn)

        var sprint_btn := Button.new()
        sprint_btn.text = _t("hud_sprint", "Lari", "Sprint")
        sprint_btn.toggle_mode = true
        sprint_btn.custom_minimum_size = Vector2(132.0, 56.0)
        sprint_btn.toggled.connect(_on_sprint_toggled)
        right_ctl.add_child(sprint_btn)

        var action_btn := Button.new()
        action_btn.text = _t("hud_action", "Aksi", "Action")
        action_btn.custom_minimum_size = Vector2(132.0, 56.0)
        action_btn.button_down.connect(func() -> void: Input.action_press("action_a"))
        action_btn.button_up.connect(func() -> void: Input.action_release("action_a"))
        right_ctl.add_child(action_btn)

        # ---- Kiri-bawah: baris tombol kecil DI ATAS area joystick (offset bawah 150px) ----
        var left_row := HBoxContainer.new()
        left_row.add_theme_constant_override("separation", 8)
        left_row.set_anchors_and_offsets_preset(
                Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN)
        )
        left_row.grow_horizontal = Control.GROW_DIRECTION_END
        left_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
        left_row.offset_bottom -= JOYSTICK_CLEARANCE
        left_row.offset_top -= JOYSTICK_CLEARANCE
        _root.add_child(left_row)

        left_row.add_child(_small_button(_t("hud_chat", "Chat", "Chat"), _on_chat))
        left_row.add_child(_small_button(_t("hud_emote", "Emote", "Emote"), _on_emote))
        left_row.add_child(_small_button(_t("hud_shot", "Foto", "Photo"), _on_screenshot))
        _build_btn = _small_button(_t("hud_build", "Bangun", "Build"), _on_build)
        left_row.add_child(_build_btn)
        _weather_btn = _small_button(_t("hud_weather", "Cuaca", "Weather"), _on_weather)
        left_row.add_child(_weather_btn)


func _glass(radius: int, margin_v: float) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.05, 0.07, 0.12, 0.72)
        sb.set_corner_radius_all(radius)
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.08)
        sb.shadow_color = Color(0, 0, 0, 0.25)
        sb.shadow_size = 6
        sb.shadow_offset = Vector2(0, 3)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = margin_v
        sb.content_margin_bottom = margin_v
        return sb


func _poll_fps() -> void:
        if _fps_label != null and is_instance_valid(_fps_label):
                _fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _small_button(text: String, handler: Callable) -> Button:
        var b := Button.new()
        b.text = text
        b.custom_minimum_size = Vector2(0.0, BTN_MIN)
        b.add_theme_font_size_override("font_size", 13)
        b.focus_mode = Control.FOCUS_NONE
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.05, 0.07, 0.12, 0.72)
        sb.set_corner_radius_all(24)
        sb.content_margin_left = 16.0
        sb.content_margin_right = 16.0
        sb.border_width_bottom = 3
        sb.border_color = Color(0.0, 0.0, 0.0, 0.85)
        b.add_theme_stylebox_override("normal", sb)
        var hover := sb.duplicate() as StyleBoxFlat
        hover.bg_color = Color(0.10, 0.13, 0.20, 0.85)
        b.add_theme_stylebox_override("hover", hover)
        var press := sb.duplicate() as StyleBoxFlat
        press.bg_color = Color(0.02, 0.03, 0.06, 0.90)
        b.add_theme_stylebox_override("pressed", press)
        b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        b.add_theme_color_override("font_color", Color.WHITE)
        b.add_theme_color_override("font_hover_color", Color.WHITE)
        b.add_theme_color_override("font_pressed_color", Color.WHITE)
        b.pressed.connect(handler)
        UiKit.attach_press_animation(b)
        return b


func _apply_world_settings() -> void:
        var settings := _world_settings()
        if _profile_panel != null:
                _profile_panel.visible = bool(settings.get("health_enabled", true))
        if _build_btn != null:
                _build_btn.visible = bool(settings.get("build_allowed", true))
        if _weather_btn != null:
                _weather_btn.visible = (not GameState.is_multiplayer()) or GameState.is_host()


func _world_settings() -> Dictionary:
        var cw: Variant = GameState.current_world
        if typeof(cw) != TYPE_DICTIONARY:
                return {}
        var s: Variant = cw.get("settings", {})
        return s if typeof(s) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------- health binding


func _try_bind_player() -> void:
        if _player != null and is_instance_valid(_player):
                return
        var nodes := get_tree().get_nodes_in_group("local_player")
        if nodes.is_empty():
                return
        var p: Node = nodes[0]
        _player = p
        if p.has_signal("health_changed"):
                if not p.is_connected("health_changed", _on_health_changed):
                        p.connect("health_changed", _on_health_changed)
                var hp: Variant = p.get("health")
                var max_hp: Variant = p.get("max_health")
                _set_health(float(hp) if hp != null else 100.0, float(max_hp) if max_hp != null else 100.0)
        if p.has_signal("died"):
                if not p.is_connected("died", _on_player_died):
                        p.connect("died", _on_player_died)


func _on_health_changed(hp: float, max_hp: float) -> void:
        _set_health(hp, max_hp)


func _on_player_died() -> void:
        _set_health(0.0, _health_bar.max_value)


func _set_health(hp: float, max_hp: float) -> void:
        if _health_bar == null:
                return
        var mx := maxf(max_hp, 1.0)
        _health_bar.max_value = mx
        _health_bar.value = clampf(hp, 0.0, mx)
        _health_text.text = "%d/%d" % [int(round(hp)), int(round(mx))]
        if _health_fill != null:
                var ratio := clampf(_health_bar.value / mx, 0.0, 1.0)
                _health_fill.bg_color = Color("#ff5a5a").lerp(Color("#4ad48a"), ratio)


# ------------------------------------------------------------------- actions


func _on_pause() -> void:
        var game := get_tree().get_first_node_in_group("game")
        if game != null and game.has_method("request_pause"):
                game.call("request_pause")
        else:
                Toast.show(
                        self,
                        _t("hud_pause_unavailable", "Menu jeda belum tersedia", "Pause menu is not available")
                )


func _on_sprint_toggled(pressed: bool) -> void:
        if pressed:
                Input.action_press("sprint")
        else:
                Input.action_release("sprint")


func _on_chat() -> void:
        var chat := _find_chat_overlay()
        if chat != null and chat.has_method("toggle"):
                chat.call("toggle")
        else:
                Toast.show(self, _t("hud_chat_unavailable", "Chat belum tersedia", "Chat is not available"))


func _on_emote() -> void:
        var chat := _find_chat_overlay()
        if chat != null and chat.has_method("open_emotes"):
                chat.call("open_emotes")
        else:
                Toast.show(
                        self, _t("hud_emote_unavailable", "Emote belum tersedia", "Emotes are not available")
                )


func _on_screenshot() -> void:
        var path := Screenshot.capture(self)
        if path == "":
                Toast.show(
                        self,
                        _t("error_generic", "Terjadi kesalahan. Coba lagi.", "Something went wrong. Try again.")
                )
        else:
                Toast.show(self, path)


func _on_build() -> void:
        var game := get_tree().get_first_node_in_group("game")
        if game != null and game.has_method("toggle_build_mode"):
                game.call("toggle_build_mode")
        else:
                Toast.show(
                        self,
                        _t("hud_build_unavailable", "Mode bangun belum tersedia", "Build mode is not available")
                )


func _on_weather() -> void:
        var weather := get_tree().get_first_node_in_group("env_weather")
        if weather == null:
                Toast.show(
                        self, _t("hud_weather_unavailable", "Cuaca belum tersedia", "Weather is not available")
                )
                return
        if weather.has_method("cycle_weather"):
                weather.call("cycle_weather")
        var w := ""
        if weather.has_method("get_weather"):
                w = String(weather.call("get_weather"))
        Toast.show(self, _t("hud_weather_now", "Cuaca", "Weather") + ": " + _weather_label(w))


func _weather_label(w: String) -> String:
        match w:
                "rain":
                        return _t("weather_rain", "Hujan", "Rain")
                "fog":
                        return _t("weather_fog", "Berkabut", "Fog")
                "snow":
                        return _t("weather_snow", "Salju", "Snow")
        return _t("weather_clear", "Cerah", "Clear")


func _on_achievement(id: String, _title: String) -> void:
        var label := String(Locale.t("ach_" + id))
        if label == "ach_" + id:
                label = String(id).replace("_", " ").capitalize()
        Toast.show(self, label + " +1")


func _poll_objective() -> void:
        var text := ""
        var mc := get_tree().get_first_node_in_group("mode_controller")
        if mc != null and mc.has_method("get_objective_text"):
                text = String(mc.call("get_objective_text"))
        if _objective_label != null:
                _objective_label.text = text
        if _objective != null:
                _objective.visible = text != ""


func _find_chat_overlay() -> Node:
        var tree := get_tree()
        if tree == null or tree.root == null:
                return null
        if tree.root.has_node("ChatOverlay"):
                return tree.root.get_node("ChatOverlay")
        return _find_node_by_name(tree.root, "ChatOverlay")


func _find_node_by_name(node: Node, target: String) -> Node:
        for child in node.get_children():
                if String(child.name) == target:
                        return child
                var found := _find_node_by_name(child, target)
                if found != null:
                        return found
        return null


func _hide_dup_actions() -> void:
        if _right_ctl == null:
                return
        var tc := get_tree().get_first_node_in_group("touch_controls")
        if tc != null:
                _right_ctl.visible = false


func _t(key: String, fb_id: String, fb_en: String) -> String:
        var s := String(Locale.t(key))
        if s != key:
                return s
        return fb_en if Locale.get_language() == "en" else fb_id
