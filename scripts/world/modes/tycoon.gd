extends "res://scripts/world/mode_base.gd"
## Mode Tycoon — berdiri di atas buypad (jarak < 1.5, selisih y < 2)
## menghasilkan uang 10/dtk. Tiap pad punya harga beli (meta "price",
## default 100): uang cukup + sentuh -> beli -> pad jadi milik (emas),
## dropper + conveyor di-spawn via WorldManager.place_block + toast.

const INCOME_RATE := 10.0
const DEFAULT_PRICE := 100.0
const PAD_RANGE := 1.5
const PAD_SIZE := Vector3(2.2, 0.24, 2.2)

var _cash := 0.0
var _pads: Array = []  # [{pos, price, owned, marker}]
var _plot := 0


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	for pr in props_of("buypad"):
		var pos := _vec3(pr.get("pos"))
		var price := float(pr.get("price", DEFAULT_PRICE))
		var marker := prop_marker(pos, "#43a047", PAD_SIZE, str(int(price)))
		_pads.append({"pos": pos, "price": price, "owned": false, "marker": marker})


func tick(delta: float) -> void:
	if not player_alive():
		return
	var ppos := player_pos()
	for pad in _pads:
		var pv: Vector3 = pad["pos"]
		if Vector2(ppos.x - pv.x, ppos.z - pv.z).length() < PAD_RANGE and absf(ppos.y - pv.y) < 2.0:
			_cash += INCOME_RATE * delta
			if not bool(pad["owned"]) and _cash >= float(pad["price"]):
				_buy(pad)


func _buy(pad: Dictionary) -> void:
	pad["owned"] = true
	_cash = maxf(0.0, _cash - float(pad["price"]))
	_plot += 1
	_replace_marker(pad, "#ffd54f")
	_spawn_property(Vector3(pad["pos"]))
	toast(Locale.t("tycoon_bought"))


## "Dropper" menara + "conveyor" menuju pad, sebagai blok JSON resmi
## (meta block_data -> ikut tersimpan di world).
func _spawn_property(base: Vector3) -> void:
	var a := TAU * float(_plot % 8) / 8.0
	var drop := base + Vector3(cos(a) * 4.0, 0.0, sin(a) * 4.0)
	var parts := [
		{
			"pos": drop + Vector3(0, 1.0, 0),
			"size": Vector3(1.0, 1.0, 1.0),
			"color": "#7e57c2",
			"mat": "plastic"
		},
		{
			"pos": drop + Vector3(0, 2.0, 0),
			"size": Vector3(1.2, 0.4, 1.2),
			"color": "#d1c4e9",
			"mat": "neon"
		},
		{
			"pos": (drop + base) * 0.5 + Vector3(0, 0.2, 0),
			"size": Vector3(2.0, 0.3, 2.0),
			"color": "#4dd0e1",
			"mat": "metal"
		},
	]
	var i := 0
	for part in parts:
		i += 1
		var data := {
			"id": "tycoon_%d_%d" % [_plot, i],
			"shape": "box",
			"pos": _arr3(part["pos"]),
			"size": _arr3(part["size"]),
			"color": part["color"],
			"mat": part["mat"],
			"anchored": true,
			"script": "",
		}
		if place_block(data) == null:
			# Fallback visual bila WorldManager/blocks_root tak tersedia.
			prop_marker(part["pos"], String(part["color"]), part["size"])


func _replace_marker(pad: Dictionary, color: String) -> void:
	var old: Node3D = pad["marker"]
	if old != null and is_instance_valid(old):
		old.queue_free()
	pad["marker"] = prop_marker(pad["pos"], color, PAD_SIZE)


func _arr3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.5), snappedf(v.y, 0.5), snappedf(v.z, 0.5)]


func get_objective_text() -> String:
	return Locale.t("mode_tycoon_obj", {"n": int(_cash)})
