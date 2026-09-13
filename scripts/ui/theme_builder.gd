extends RefCounted
## ThemeBuilder — tema UI kelas produksi untuk RBlox (dark / light).
## v0.2 "AAA pass": tombol chunky 3D (border bawah + bayangan + efek tekan),
## panel kaca membulat, font tebal untuk kontrol, ProgressBar & toggle jelas,
## palet kontras tinggi ala platform game modern (Roblox-like).
## Dipakai otomatis oleh Settings.get_theme(); tidak perlu dipanggil manual.

const CORNER := 14
const CORNER_SM := 10
const FONT_DEFAULT := 20
const FONT_SMALL := 16

static var _bold_font: FontVariation = null


## Font tebal bersama (bold feel ala game tanpa file font tambahan).
static func bold_font() -> FontVariation:
        if _bold_font == null:
                var fv := FontVariation.new()
                fv.base_font = ThemeDB.fallback_font
                fv.variation_embolden = 0.7
                _bold_font = fv
        return _bold_font


static func build(dark: bool) -> Theme:
        var bg := Color("#0e1220") if dark else Color("#eef1f8")
        var panel := Color("#1a2130") if dark else Color("#ffffff")
        var text := Color("#f0f3fa") if dark else Color("#1a2233")
        var subtext := Color("#a8b1c7") if dark else Color("#5a6478")
        var accent := Color("#4f8cff") if dark else Color("#2f6fed")
        var accent2 := Color("#4ad48a") if dark else Color("#2f9e5f")
        var field := Color("#242c40") if dark else Color("#e6ebf5")
        var t := Theme.new()
        t.default_font_size = FONT_DEFAULT
        _style_button(t, accent, accent2)
        _style_panel(t, panel)
        _style_label(t, text, subtext)
        _style_line_edit(t, bg, text, accent)
        _style_option_button(t, field, text, accent)
        _style_check_button(t, field, text, accent)
        _style_slider(t, field, accent2)
        _style_tab_container(t, panel, text, accent)
        _style_progress_bar(t, field, accent2)
        _style_scroll_container(t)
        _style_popup_menu(t, panel, text, accent)
        _style_separator(t, text)
        return t


# ------------------------------------------------------------------ tombol


static func _style_button(t: Theme, accent: Color, accent2: Color) -> void:
        var f := bold_font()
        t.set_font("font", "Button", f)
        t.set_font("font", "OptionButton", f)
        t.set_font("font", "CheckBox", f)
        t.set_font("font", "CheckButton", f)
        _apply_button_family(t, "Button", accent)
        _apply_toggle_states(t, "Button", accent2)


## StyleBox tombol chunky: bayangan lembut + border bawah tebal (kesan 3D).
static func _button_sb(base: Color, bottom: float, lift: bool) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = base
        sb.set_corner_radius_all(CORNER)
        sb.content_margin_left = 22.0
        sb.content_margin_right = 22.0
        sb.content_margin_top = (14.0 if not lift else 17.0)
        sb.content_margin_bottom = ((14.0 + bottom) if not lift else 12.0)
        sb.border_width_bottom = int(bottom)
        sb.border_color = base.darkened(0.35)
        sb.shadow_color = Color(0, 0, 0, 0.28)
        sb.shadow_size = 6
        sb.shadow_offset = Vector2(0, 3)
        return sb


static func _apply_button_family(t: Theme, cls: String, accent: Color) -> void:
        t.set_stylebox("normal", cls, _button_sb(accent, 4.0, false))
        t.set_stylebox("hover", cls, _button_sb(accent.lightened(0.12), 4.0, false))
        t.set_stylebox("pressed", cls, _button_sb(accent.darkened(0.22), 1.0, true))
        t.set_stylebox("disabled", cls, _button_sb(Color(0.45, 0.48, 0.56, 0.5), 2.0, false))
        t.set_stylebox("focus", cls, StyleBoxEmpty.new())
        for st in ["font_color", "font_hover_color", "font_focus_color"]:
                t.set_color(st, cls, Color.WHITE)
        t.set_color("font_pressed_color", cls, Color(0.94, 0.96, 1.0))
        t.set_color("font_disabled_color", cls, Color(1, 1, 1, 0.55))
        t.set_font_size("font_size", cls, FONT_DEFAULT)


## State toggle (tombol alat aktif): hijau accent2 + ring terang.
static func _apply_toggle_states(t: Theme, cls: String, accent2: Color) -> void:
        var on := _button_sb(accent2, 4.0, false)
        on.set_border_width_all(2)
        on.border_color = Color(1, 1, 1, 0.85)
        t.set_stylebox("pressed", cls, on)


static func _style_panel(t: Theme, panel: Color) -> void:
        t.set_stylebox("panel", "Panel", _glass(panel, CORNER))
        t.set_stylebox("panel", "PanelContainer", _glass(panel, CORNER))


## Panel "kaca": membulat + border halus + bayangan elevasi.
static func _glass(bg: Color, radius: int) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.set_corner_radius_all(radius)
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.08)
        sb.shadow_color = Color(0, 0, 0, 0.22)
        sb.shadow_size = 10
        sb.shadow_offset = Vector2(0, 4)
        sb.content_margin_left = 16.0
        sb.content_margin_right = 16.0
        sb.content_margin_top = 14.0
        sb.content_margin_bottom = 14.0
        return sb


static func _style_label(t: Theme, text: Color, subtext: Color) -> void:
        t.set_color("font_color", "Label", text)
        t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
        t.set_constant("shadow_offset_x", "Label", 1)
        t.set_constant("shadow_offset_y", "Label", 2)


static func _style_line_edit(t: Theme, bg: Color, text: Color, accent: Color) -> void:
        t.set_stylebox("normal", "LineEdit", _flat(bg, CORNER_SM, 14.0, 12.0))
        var sb_focus := _flat(bg, CORNER_SM, 14.0, 12.0)
        sb_focus.set_border_width_all(2)
        sb_focus.border_color = accent
        t.set_stylebox("focus", "LineEdit", sb_focus)
        t.set_stylebox("read_only", "LineEdit", _flat(bg.darkened(0.04), CORNER_SM, 14.0, 12.0))
        t.set_color("font_color", "LineEdit", text)
        t.set_color("font_placeholder_color", "LineEdit", Color(text.r, text.g, text.b, 0.45))
        t.set_color("caret_color", "LineEdit", accent)
        t.set_color("selection_color", "LineEdit", Color(accent.r, accent.g, accent.b, 0.35))
        t.set_font_size("font_size", "LineEdit", FONT_DEFAULT)


static func _style_option_button(t: Theme, field: Color, text: Color, accent: Color) -> void:
        t.set_stylebox("normal", "OptionButton", _flat(field, CORNER_SM, 18.0, 12.0))
        t.set_stylebox("hover", "OptionButton", _flat(field.lightened(0.08), CORNER_SM, 18.0, 12.0))
        t.set_stylebox("pressed", "OptionButton", _flat(field.darkened(0.10), CORNER_SM, 18.0, 12.0))
        t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
        var dis := _flat(Color(0.5, 0.53, 0.6, 0.35), CORNER_SM, 18.0, 12.0)
        t.set_stylebox("disabled", "OptionButton", dis)
        for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
                t.set_color(st, "OptionButton", text)
        t.set_color("font_disabled_color", "OptionButton", Color(text.r, text.g, text.b, 0.45))
        t.set_font_size("font_size", "OptionButton", FONT_DEFAULT)
        var f := bold_font()
        t.set_font("font", "OptionButton", f)


static func _style_check_button(t: Theme, field: Color, text: Color, accent: Color) -> void:
        for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
                t.set_color(st, "CheckButton", text)
        t.set_color("font_disabled_color", "CheckButton", Color(text.r, text.g, text.b, 0.45))
        t.set_font_size("font_size", "CheckButton", FONT_DEFAULT)
        t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
        t.set_icon("checked", "CheckButton", _toggle_icon(true, accent, Color.WHITE))
        t.set_icon(
                "unchecked", "CheckButton", _toggle_icon(false, field, Color(text.r, text.g, text.b, 0.75))
        )
        t.set_icon(
                "checked_disabled",
                "CheckButton",
                _toggle_icon(true, Color(0.5, 0.53, 0.6, 0.5), Color(1, 1, 1, 0.6))
        )
        t.set_icon(
                "unchecked_disabled",
                "CheckButton",
                _toggle_icon(false, Color(0.5, 0.53, 0.6, 0.4), Color(1, 1, 1, 0.5))
        )


static func _style_slider(t: Theme, field: Color, fill: Color) -> void:
        t.set_stylebox("slider", "Slider", _strip(_flat(field, 6, 0.0, 0.0), 6.0))
        t.set_stylebox("grabber_area", "Slider", _strip(_flat(fill, 6, 0.0, 0.0), 6.0))
        t.set_stylebox(
                "grabber_area_highlight", "Slider", _strip(_flat(fill.lightened(0.15), 6, 0.0, 0.0), 6.0)
        )
        t.set_icon("grabber", "Slider", _circle_icon(40, Color.WHITE, Color(0.2, 0.25, 0.35, 0.6)))
        t.set_icon(
                "grabber_highlight", "Slider", _circle_icon(44, Color.WHITE, Color(0.2, 0.25, 0.35, 0.6))
        )
        t.set_icon("grabber_disabled", "Slider", _circle_icon(40, Color(1, 1, 1, 0.5)))
        t.set_stylebox("focus", "Slider", StyleBoxEmpty.new())


static func _style_progress_bar(t: Theme, field: Color, fill: Color) -> void:
        var bg_sb := _flat(field, 8, 0.0, 0.0)
        t.set_stylebox("background", "ProgressBar", bg_sb)
        var fill_sb := _flat(fill, 8, 0.0, 0.0)
        fill_sb.shadow_color = Color(1, 1, 1, 0.25)
        fill_sb.shadow_size = 2
        t.set_stylebox("fill", "ProgressBar", fill_sb)
        t.set_color("font_color", "ProgressBar", Color.WHITE)


static func _style_tab_container(t: Theme, panel: Color, text: Color, accent: Color) -> void:
        t.set_stylebox("panel", "TabContainer", _glass(panel, CORNER))
        var sb_sel := _flat(panel.lightened(0.06), 8, 16.0, 10.0)
        sb_sel.corner_radius_bottom_left = 0
        sb_sel.corner_radius_bottom_right = 0
        sb_sel.border_width_top = 3
        sb_sel.border_color = accent
        t.set_stylebox("tab_selected", "TabContainer", sb_sel)
        var sb_un := _flat(panel.darkened(0.06), 8, 16.0, 10.0)
        sb_un.corner_radius_bottom_left = 0
        sb_un.corner_radius_bottom_right = 0
        t.set_stylebox("tab_unselected", "TabContainer", sb_un)
        t.set_color("font_selected_color", "TabContainer", text)
        t.set_color("font_unselected_color", "TabContainer", Color(text.r, text.g, text.b, 0.6))
        t.set_font_size("font_size", "TabContainer", FONT_DEFAULT)


static func _style_scroll_container(t: Theme) -> void:
        t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())


static func _style_popup_menu(t: Theme, panel: Color, text: Color, accent: Color) -> void:
        t.set_stylebox("panel", "PopupMenu", _glass(panel.lightened(0.04), CORNER_SM))
        t.set_stylebox("hover", "PopupMenu", _flat(accent, 8, 8.0, 6.0))
        for st in ["font_color", "font_accelerator_color"]:
                t.set_color(st, "PopupMenu", text)
        t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
        t.set_color("font_disabled_color", "PopupMenu", Color(text.r, text.g, text.b, 0.4))
        t.set_font_size("font_size", "PopupMenu", FONT_DEFAULT)
        t.set_stylebox(
                "separator", "PopupMenu", _flat(Color(text.r, text.g, text.b, 0.15), 0, 0.0, 1.0)
        )


static func _style_separator(t: Theme, text: Color) -> void:
        var line := _flat(Color(text.r, text.g, text.b, 0.18), 0, 0.0, 1.0)
        t.set_stylebox("separator", "HSeparator", line)
        t.set_stylebox("separator", "VSeparator", line)


# ------------------------------------------------------------------ helper


static func _flat(
        bg: Color, radius: int = CORNER, margin_h: float = 0.0, margin_v: float = 0.0
) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.set_corner_radius_all(radius)
        sb.content_margin_left = margin_h
        sb.content_margin_right = margin_h
        sb.content_margin_top = margin_v
        sb.content_margin_bottom = margin_v
        return sb


static func _strip(sb: StyleBoxFlat, thickness: float) -> StyleBoxFlat:
        sb.content_margin_top = thickness
        sb.content_margin_bottom = thickness
        return sb


static func _toggle_icon(is_on: bool, track: Color, knob: Color) -> ImageTexture:
        var w := 88
        var h := 48
        var r := 24
        var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
        for y in h:
                for x in w:
                        if _in_rounded_rect(float(x) + 0.5, float(y) + 0.5, float(w), float(h), float(r)):
                                img.set_pixel(x, y, track)
        var kx := float(w - r) if is_on else float(r)
        var cy := float(h) * 0.5
        for y in h:
                for x in w:
                        if Vector2(float(x) + 0.5 - kx, float(y) + 0.5 - cy).length() <= 18.0:
                                img.set_pixel(x, y, knob)
        return ImageTexture.create_from_image(img)


static func _circle_icon(
        diameter: int, color: Color, outline: Color = Color(0, 0, 0, 0)
) -> ImageTexture:
        var img := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
        var c := float(diameter) * 0.5
        var rad := c - 1.0
        for y in diameter:
                for x in diameter:
                        var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
                        if d <= rad:
                                var col := color
                                if outline.a > 0.0 and d >= rad - 2.0:
                                        col = outline
                                img.set_pixel(x, y, col)
        return ImageTexture.create_from_image(img)


static func _in_rounded_rect(px: float, py: float, w: float, h: float, r: float) -> bool:
        var cx := clampf(px, r, w - r)
        var cy := clampf(py, r, h - r)
        return Vector2(px - cx, py - cy).length() <= r
