extends RefCounted
## Toast — notifikasi kecil di bawah-tengah layar, fade in/out lalu auto free.
## Aman dipanggil dari mana saja (node apa pun yang berada di tree):
##   const Toast := preload("res://scripts/ui/toast.gd")
##   Toast.show(self, "Teks notifikasi")
## Beberapa toast aktif akan menumpuk ke atas otomatis.

const LAYER := 100
const STEP_Y := 56.0
const BASE_OFFSET_Y := -36.0


static func show(context: Node, text: String, duration: float = 2.5) -> void:
	if context == null or not context.is_inside_tree():
		return
	var tree := context.get_tree()
	if tree == null or tree.root == null:
		return

	var layer := CanvasLayer.new()
	layer.layer = LAYER

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.18)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	layer.add_child(panel)
	tree.root.add_child(layer)

	# Tumpuk ke atas bila sudah ada toast lain yang tampil.
	var count := tree.get_nodes_in_group("ui_toast").size()
	var y_off := BASE_OFFSET_Y - float(count) * STEP_Y
	panel.offset_top = y_off
	panel.offset_bottom = y_off
	panel.modulate.a = 0.0
	layer.add_to_group("ui_toast")

	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	if duration > 0.0:
		tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(layer.queue_free)
