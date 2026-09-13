extends "res://scripts/world/mode_base.gd"
## Mode City — dunia bebas; 3 NPC warga berjalan-jalan (wander) di sekitar
## titik spawn.


func setup(p_world_json: Dictionary, game_node: Node) -> void:
	super.setup(p_world_json, game_node)
	var base := spawn_point(0)
	var spots := [
		base + Vector3(5, 0.5, 2),
		base + Vector3(-5, 0.5, 4),
		base + Vector3(2, 0.5, -6),
	]
	for i in range(spots.size()):
		spawn_npc("villager", spots[i], {
			"name": "%s %d" % [Locale.t("npc_villager"), i + 1],
			"speed": 1.3,
			"color": "#8bc34a",
		})


func get_objective_text() -> String:
	return Locale.t("mode_city_obj")
