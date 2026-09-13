extends RefCounted
## Screenshot — util statis kapture tampilan game lalu simpan via autoload Saves.
## Pemakaian: var path := preload("res://scripts/meta/screenshot.gd").capture(self)
## Return path PNG ("user://screenshots/...") atau "" bila gagal.


static func capture(context: Node) -> String:
	if context == null or not context.is_inside_tree():
		return ""
	var vp := context.get_viewport()
	if vp == null:
		return ""
	var tex := vp.get_texture()
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null:
		return ""
	var saves := context.get_tree().root.get_node_or_null("Saves")
	if saves == null or not saves.has_method("save_screenshot"):
		return ""
	return String(saves.call("save_screenshot", img))
