extends "res://scripts/world/mode_base.gd"
## Mode Adventure — kumpulkan semua bintang dari props star (jarak < 2);
## semua terkumpul -> achievement "collect_all_stars". Chest memberi reward
## + toast (sekali).

const PICK_RANGE := 2.0

var _stars: Array = []  # [{pos: Vector3, hit: bool}]
var _chest := Vector3.ZERO
var _has_chest := false
var _chest_open := false
var _count := 0
var _done := false


func setup(p_world_json: Dictionary, game_node: Node) -> void:
        super.setup(p_world_json, game_node)
        var stars := props_of("star")
        stars.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
        for s in stars:
                var pos := _vec3(s.get("pos"))
                prop_marker(pos, "#ffd54f", Vector3(0.6, 0.6, 0.6))
                _stars.append({"pos": pos, "hit": false})
        var chests := props_of("chest")
        if not chests.is_empty():
                _chest = _vec3(chests[0].get("pos"))
                _has_chest = true
                prop_marker(_chest, "#8d6e63", Vector3(0.9, 0.7, 0.7))


func tick(_delta: float) -> void:
        if not player_alive():
                return
        var pos := player_pos()
        for s in _stars:
                if bool(s["hit"]):
                        continue
                var spos: Vector3 = s["pos"]
                if pos.distance_to(spos) < PICK_RANGE:
                        s["hit"] = true
                        _count += 1
                        if _count >= _stars.size() and not _done:
                                _done = true
                                GameState.unlock_achievement("collect_all_stars")
        if _has_chest and not _chest_open and pos.distance_to(_chest) < PICK_RANGE:
                _chest_open = true
                toast(Locale.t("adventure_chest"))
                if GameState.has_method("add_stat"):
                        GameState.add_stat("chests_opened", 1)


func get_objective_text() -> String:
        if _stars.is_empty():
                return ""
        if _done:
                return Locale.t("mode_stars_done")
        return Locale.t("mode_adventure_obj", {"x": _count, "y": _stars.size()})


## ---- Save/Resume sesi ----
func session_state() -> Dictionary:
        var hits := []
        for st in _stars:
                hits.append(bool(st.get("hit", false)))
        return {
                "star_hits": hits, "has_chest": _has_chest, "chest_open": _chest_open,
                "count": _count, "done": _done,
        }


func restore_session(s: Dictionary) -> void:
        _has_chest = bool(s.get("has_chest", false))
        _chest_open = bool(s.get("chest_open", false))
        _count = int(s.get("count", 0))
        _done = bool(s.get("done", false))
        var hits: Variant = s.get("star_hits", [])
        if hits is Array:
                for i in range(mini(_stars.size(), (hits as Array).size())):
                        _stars[i]["hit"] = bool(hits[i])
