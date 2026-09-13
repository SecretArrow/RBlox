extends RefCounted
## Katalog 10 template dunia & generator world JSON (skema "rblox-world").
## Dipakai world_select (kartu template) dan game (pending world_id / fallback).
## Skema kontrak Task 1:
## {"format":"rblox-world","version":1,"meta":{name,is_template},
##  "settings":{game_mode,day_night,cycle_minutes,weather,health_enabled,
##   build_allowed,spawn},"spawn_points":[[x,y,z]],
##  "blocks":[{id,shape,pos,size,color,mat,anchored,script}],
##  "props":[{type,role,pos,...}],"terrain":{size,seed,heights[],paint[]}}

const VERSION := 1

const TEMPLATES := [
        {"id": "obby", "name_key": "tpl_obby", "desc_key": "tpl_obby_desc", "color": "#ff7043"},
        {"id": "racing", "name_key": "tpl_racing", "desc_key": "tpl_racing_desc", "color": "#29b6f6"},
        {"id": "city", "name_key": "tpl_city", "desc_key": "tpl_city_desc", "color": "#90a4ae"},
        {
                "id": "survival",
                "name_key": "tpl_survival",
                "desc_key": "tpl_survival_desc",
                "color": "#66bb6a"
        },
        {"id": "horror", "name_key": "tpl_horror", "desc_key": "tpl_horror_desc", "color": "#5c6bc0"},
        {
                "id": "bedwars",
                "name_key": "tpl_bedwars",
                "desc_key": "tpl_bedwars_desc",
                "color": "#ef5350"
        },
        {
                "id": "hide_seek",
                "name_key": "tpl_hide_seek",
                "desc_key": "tpl_hide_seek_desc",
                "color": "#ffb300"
        },
        {"id": "empty", "name_key": "tpl_empty", "desc_key": "tpl_empty_desc", "color": "#9e9e9e"},
        {
                "id": "adventure",
                "name_key": "tpl_adventure",
                "desc_key": "tpl_adventure_desc",
                "color": "#26a69a"
        },
        {"id": "tycoon", "name_key": "tpl_tycoon", "desc_key": "tpl_tycoon_desc", "color": "#ab47bc"},
]

const CITY_COLORS := [
        "#ef9a9a",
        "#90caf9",
        "#a5d6a7",
        "#fff59d",
        "#ce93d8",
        "#ffcc80",
        "#80cbc4",
        "#b0bec5",
]


static func catalog() -> Array:
        return TEMPLATES.duplicate(true)


## JSON lengkap satu template; id tak dikenal jatuh ke "empty".
static func build_world_json(id: String) -> Dictionary:
        var wid := id
        var known := false
        for t in TEMPLATES:
                if String(t.get("id", "")) == wid:
                        known = true
                        break
        if not known:
                wid = "empty"
        var w := {
                "format": "rblox-world",
                "version": VERSION,
                "meta": {"name": _display_name(wid), "is_template": true},
                "settings":
                {
                        "game_mode": wid,
                        "day_night": true,
                        "cycle_minutes": 10.0,
                        "weather": "clear",
                        "health_enabled": true,
                        "build_allowed": false,
                        "spawn": [0.0, 2.0, 0.0],
                },
                "spawn_points": [],
                "blocks": [],
                "props": [],
        }
        match wid:
                "obby":
                        _build_obby(w)
                "racing":
                        _build_racing(w)
                "city":
                        _build_city(w)
                "survival":
                        _build_survival(w)
                "horror":
                        _build_horror(w)
                "bedwars":
                        _build_bedwars(w)
                "hide_seek":
                        _build_hide_seek(w)
                "empty":
                        _build_empty(w)
                "adventure":
                        _build_adventure(w)
                "tycoon":
                        _build_tycoon(w)
        return w


# ------------------------------------------------------------------ builders


static func _build_obby(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        var rng := _rng_for("obby")
        # Platform start
        _box(blocks, Vector3(0, 0, 8), Vector3(8, 1, 8), "#9e9e9e", "plastic")
        var cp := 0
        var last := Vector3.ZERO
        for i in range(30):
                var ang := float(i) * 0.55
                var pos := Vector3(sin(ang) * 7.0, 1.0 + float(i) * 0.28, 4.0 - float(i) * 3.2)
                last = pos
                _box(blocks, pos, Vector3(3, 0.5, 3), _hsl_color(rng), "plastic")
                if (i + 1) % 6 == 0:
                        (
                                props
                                . append(
                                        {
                                                "type": "checkpoint",
                                                "role": "obby",
                                                "index": cp,
                                                "pos": _pvec(pos + Vector3(0, 0.8, 0)),
                                        }
                                )
                        )
                        cp += 1
        # Platform akhir (finish neon)
        _box(blocks, last + Vector3(0, 0.5, -6.0), Vector3(10, 1, 10), "#ffd54f", "neon")
        _set_spawn(w, Vector3(0, 2.5, 10))


static func _build_racing(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        # Tanah
        _box(blocks, Vector3(0, -0.5, 0), Vector3(80, 1, 60), "#6d4c41", "plastic")
        # Track oval: 2 ring konsentris agar permukaan mulus
        var seg := 32
        for ring in range(2):
                for i in range(seg):
                        var a := TAU * (float(i) + (0.5 if ring == 1 else 0.0)) / float(seg)
                        var pos := Vector3(cos(a) * 26.0, 0.4, sin(a) * 17.0)
                        var col := "#455a64" if (i + ring) % 2 == 0 else "#90a4ae"
                        _box(blocks, pos, Vector3(4.5, 0.3, 4.5), col, "plastic")
        # Garis start
        _box(blocks, Vector3(26, 0.6, 0), Vector3(2, 0.1, 8), "#ffffff", "neon")
        # Checkpoint 4 arah mata angin
        for i in range(4):
                var a := TAU * float(i) / 4.0
                (
                        props
                        . append(
                                {
                                        "type": "checkpoint",
                                        "role": "racing",
                                        "index": i,
                                        "pos": _pvec(Vector3(cos(a) * 26.0, 1.0, sin(a) * 17.0)),
                                }
                        )
                )
        props.append(
                {"type": "kart", "role": "racing", "yaw": 90.0, "pos": _pvec(Vector3(24, 1.2, 2.5))}
        )
        props.append(
                {"type": "kart", "role": "racing", "yaw": 90.0, "pos": _pvec(Vector3(24, 1.2, -2.5))}
        )
        _set_spawn(w, Vector3(28, 1.5, 0))


static func _build_city(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        var rng := _rng_for("city")
        # Tanah: tile 12.5 unit (bukan satu box 100 unit) — segitiga kecil bebas
        # artefak interpolasi/moiré pada rasterizer software & z-order lebih rapi.
        for ix in range(8):
                for iz in range(8):
                        _box(
                                blocks,
                                Vector3(-43.75 + 12.5 * ix, -0.5, -43.75 + 12.5 * iz),
                                Vector3(12.5, 1, 12.5),
                                "#9e9e9e",
                                "plastic"
                        )
        # Jalan grid (2 sejajar X + 2 sejajar Z), disegmentasi 12.5 unit
        for i in range(8):
                var c := -43.75 + 12.5 * i
                _box(blocks, Vector3(c, 0.05, -16), Vector3(12.5, 0.1, 6), "#4a4f54", "plastic")
                _box(blocks, Vector3(c, 0.05, 16), Vector3(12.5, 0.1, 6), "#4a4f54", "plastic")
                _box(blocks, Vector3(-16, 0.05, c), Vector3(6, 0.1, 12.5), "#4a4f54", "plastic")
                _box(blocks, Vector3(16, 0.05, c), Vector3(6, 0.1, 12.5), "#4a4f54", "plastic")
        # 20 bangunan box tinggi warna acak pada grid 5x5
        var slots: Array = []
        for gx in range(5):
                for gz in range(5):
                        slots.append(Vector2i([-38, -24, 0, 24, 38][gx], [-38, -24, 0, 24, 38][gz]))
        for i in range(slots.size() - 1, 0, -1):
                var j := rng.randi_range(0, i)
                var tmp: Vector2i = slots[i]
                slots[i] = slots[j]
                slots[j] = tmp
        var count := 0
        for s in slots:
                if count >= 20:
                        break
                count += 1
                var h := snappedf(rng.randf_range(6.0, 18.0), 0.5)
                var col: String = CITY_COLORS[rng.randi_range(0, CITY_COLORS.size() - 1)]
                var mat := "glass" if rng.randf() < 0.25 else "plastic"
                _box(blocks, Vector3(float(s.x), h * 0.5, float(s.y)), Vector3(8, h, 8), col, mat)
        # Lampu jalan di tiap kuadran persimpangan
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        for off in [Vector2(4, 4), Vector2(-4, -4)]:
                                (
                                        props
                                        . append(
                                                {
                                                        "type": "streetlamp",
                                                        "role": "city",
                                                        "pos": _pvec(Vector3(16.0 * sx + off.x, 0.5, 16.0 * sz + off.y)),
                                                }
                                        )
                                )
        _set_spawn(w, Vector3(0, 2, 16))


static func _build_survival(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        var rng := _rng_for("survival")
        # Tanah rumput
        _box(blocks, Vector3(0, -0.5, 0), Vector3(60, 1, 60), "#689f38", "plastic")
        # Pohon: batang coklat + tajuk hijau
        for i in range(12):
                var a := TAU * float(i) / 12.0
                var r := rng.randf_range(13.0, 24.0)
                var px := snappedf(cos(a) * r, 0.5)
                var pz := snappedf(sin(a) * r, 0.5)
                _box(blocks, Vector3(px, 1.0, pz), Vector3(1, 2, 1), "#795548", "wood")
                _box(blocks, Vector3(px, 2.9, pz), Vector3(2.5, 2, 2.5), "#2e7d32", "plastic")
        # Perapian + batu
        props.append({"type": "campfire", "role": "survival", "pos": _pvec(Vector3(0, 0.5, 0))})
        for i in range(6):
                var sa := TAU * float(i) / 6.0
                _box(
                        blocks,
                        Vector3(cos(sa) * 1.6, 0.25, sin(sa) * 1.6),
                        Vector3(0.5, 0.5, 0.5),
                        "#757575",
                        "plastic"
                )
        # Spawner zombie mengelilingi arena
        for i in range(5):
                var za := TAU * float(i) / 5.0 + 0.4
                (
                        props
                        . append(
                                {
                                        "type": "zombie_spawner",
                                        "role": "survival",
                                        "pos": _pvec(Vector3(cos(za) * 26.0, 0.5, sin(za) * 26.0)),
                                }
                        )
                )
        w["settings"]["cycle_minutes"] = 6.0
        _set_spawn(w, Vector3(0, 2, 5))


static func _build_horror(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        # Labirin 36x36, dinding tinggi 3: keliling + dinding dalam bercelah
        _box(blocks, Vector3(0, 1.5, -18), Vector3(37, 3, 1), "#37474f", "plastic")
        _box(blocks, Vector3(0, 1.5, 18), Vector3(37, 3, 1), "#37474f", "plastic")
        _box(blocks, Vector3(-18, 1.5, 0), Vector3(1, 3, 37), "#37474f", "plastic")
        _box(blocks, Vector3(18, 1.5, 0), Vector3(1, 3, 37), "#37474f", "plastic")
        for gx in [1, 3, 5, 7]:
                var x := -18.0 + float(gx) * 4.0
                _box(blocks, Vector3(x, 1.5, -10), Vector3(1, 3, 16), "#455a64", "plastic")
                _box(blocks, Vector3(x, 1.5, 10), Vector3(1, 3, 16), "#455a64", "plastic")
        for gz in [1, 3, 5, 7]:
                var z := -18.0 + float(gz) * 4.0
                _box(blocks, Vector3(-10, 1.5, z), Vector3(16, 3, 1), "#455a64", "plastic")
                _box(blocks, Vector3(10, 1.5, z), Vector3(16, 3, 1), "#455a64", "plastic")
        # 5 fuse tersebar + pintu keluar
        var fuse_pos := [
                Vector3(-14, 1, -14),
                Vector3(14, 1, -14),
                Vector3(-14, 1, 14),
                Vector3(14, 1, 10),
                Vector3(0, 1, -14),
        ]
        for i in range(fuse_pos.size()):
                props.append({"type": "fuse", "role": "horror", "index": i, "pos": _pvec(fuse_pos[i])})
        props.append({"type": "exit", "role": "horror", "pos": _pvec(Vector3(16, 1, 16))})
        w["settings"]["day_night"] = false
        w["settings"]["weather"] = "fog"
        _set_spawn(w, Vector3(0, 2, 0))


static func _build_bedwars(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        var teams := [
                {"sx": 1.0, "sz": 1.0, "col": "#ef5350"},
                {"sx": -1.0, "sz": 1.0, "col": "#29b6f6"},
                {"sx": 1.0, "sz": -1.0, "col": "#66bb6a"},
                {"sx": -1.0, "sz": -1.0, "col": "#ffee58"},
        ]
        var spawns: Array = []
        # Pulau tengah + generator utama
        _box(blocks, Vector3(0, 0, 0), Vector3(10, 1, 10), "#8d6e63", "plastic")
        props.append({"type": "generator", "role": "bedwars", "pos": _pvec(Vector3(0, 0.6, 0))})
        for i in range(teams.size()):
                var t: Dictionary = teams[i]
                var ix := 20.0 * float(t["sx"])
                var iz := 20.0 * float(t["sz"])
                # Pulau tim + jembatan menuju tengah
                _box(blocks, Vector3(ix, 0, iz), Vector3(8, 1, 8), String(t["col"]), "plastic")
                _box(
                        blocks, Vector3(10.5 * float(t["sx"]), 0.25, iz), Vector3(11, 0.5, 2), "#a1887f", "wood"
                )
                _box(
                        blocks, Vector3(ix, 0.25, 10.5 * float(t["sz"])), Vector3(2, 0.5, 11), "#a1887f", "wood"
                )
                props.append(
                        {"type": "bed", "role": "bedwars", "team": i, "pos": _pvec(Vector3(ix, 0.6, iz))}
                )
                (
                        props
                        . append(
                                {
                                        "type": "generator",
                                        "role": "bedwars",
                                        "team": i,
                                        "pos":
                                        _pvec(Vector3(ix + 3.0 * float(t["sx"]), 0.6, iz + 3.0 * float(t["sz"]))),
                                }
                        )
                )
                spawns.append(_pvec(Vector3(ix, 2, iz)))
        w["settings"]["day_night"] = false
        w["spawn_points"] = spawns
        w["settings"]["spawn"] = spawns[0]


static func _build_hide_seek(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        var rng := _rng_for("hide_seek")
        # Tanah
        _box(blocks, Vector3(0, -0.5, 0), Vector3(60, 1, 60), "#81c784", "plastic")
        # 30 kotak besar untuk bersembunyi
        for gx in range(6):
                for gz in range(5):
                        var h := snappedf(rng.randf_range(2.5, 4.0), 0.5)
                        var px := snappedf(-22.5 + gx * 9.0 + rng.randf_range(-2.0, 2.0), 0.5)
                        var pz := snappedf(-18.0 + gz * 9.0 + rng.randf_range(-2.0, 2.0), 0.5)
                        var sx := snappedf(rng.randf_range(3.0, 5.0), 0.5)
                        var sz := snappedf(rng.randf_range(3.0, 5.0), 0.5)
                        _box(blocks, Vector3(px, h * 0.5, pz), Vector3(sx, h, sz), _hsl_color(rng), "plastic")
        props.append({"type": "seeker", "role": "hide_seek", "pos": _pvec(Vector3(0, 1.5, -24))})
        w["settings"]["day_night"] = false
        _set_spawn(w, Vector3(0, 2, 24))


static func _build_empty(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        _box(blocks, Vector3(0, -0.5, 0), Vector3(64, 1, 64), "#8bc34a", "plastic")
        w["settings"]["build_allowed"] = true
        _set_spawn(w, Vector3(0, 2, 0))


static func _build_adventure(w: Dictionary) -> void:
        var props: Array = w["props"]
        # Terrain bukit 32x32 deterministik + paint per ketinggian
        var size := 32
        var heights: Array = []
        var paint: Array = []
        for x in range(size):
                for z in range(size):
                        var wx := float(x) - size * 0.5 + 0.5
                        var wz := float(z) - size * 0.5 + 0.5
                        var h := _adv_height(wx, wz)
                        heights.append(h)
                        if h < 1.0:
                                paint.append("#d7c98a")
                        elif h < 3.0:
                                paint.append("#7cb342")
                        elif h < 4.5:
                                paint.append("#558b2f")
                        else:
                                paint.append("#8d9aa0")
        w["terrain"] = {"size": size, "seed": 20240, "heights": heights, "paint": paint}
        # 10 bintang tersebar mengikuti tinggi bukit
        var star_pos := [
                Vector3(6, 0, -10),
                Vector3(-8, 0, -4),
                Vector3(10, 0, 2),
                Vector3(-4, 0, 10),
                Vector3(0, 0, -16),
                Vector3(14, 0, 12),
                Vector3(-14, 0, 8),
                Vector3(4, 0, 18),
                Vector3(-12, 0, -14),
                Vector3(8, 0, -6),
        ]
        for i in range(star_pos.size()):
                var sp: Vector3 = star_pos[i]
                sp.y = _adv_height(sp.x, sp.z) + 1.2
                props.append({"type": "star", "role": "adventure", "index": i, "pos": _pvec(sp)})
        # Peti harta di puncak tengah
        (
                props
                . append(
                        {
                                "type": "chest",
                                "role": "adventure",
                                "pos": _pvec(Vector3(0, _adv_height(0, 0) + 0.8, 0)),
                        }
                )
        )
        _set_spawn(w, Vector3(2, _adv_height(2, 2) + 2.0, 2))


static func _build_tycoon(w: Dictionary) -> void:
        var blocks: Array = w["blocks"]
        var props: Array = w["props"]
        # Baseplate
        _box(blocks, Vector3(0, -0.5, 0), Vector3(48, 1, 48), "#b0bec5", "plastic")
        # Menara dropper
        for i in range(4):
                _box(blocks, Vector3(-14, 2.5 + float(i), -14), Vector3(2, 1, 2), "#7e57c2", "plastic")
        _box(blocks, Vector3(-14, 6.5, -14), Vector3(2.2, 0.4, 2.2), "#d1c4e9", "neon")
        # Conveyor menuju tengah
        for i in range(6):
                _box(
                        blocks,
                        Vector3(-12.0 + float(i) * 2.0, 0.2, -14),
                        Vector3(2, 0.4, 2),
                        "#4dd0e1",
                        "metal"
                )
        # Buypad penghasil uang
        for off in [Vector3(8, 0.3, 8), Vector3(8, 0.3, -8), Vector3(-8, 0.3, 8), Vector3(-8, 0.3, -8)]:
                props.append({"type": "buypad", "role": "tycoon", "pos": _pvec(off)})
        _set_spawn(w, Vector3(18, 2, 18))


# ------------------------------------------------------------------ helpers


static func _display_name(id: String) -> String:
        ## Nama template via Locale (name_key) bila autoload hidup, fallback statis.
        var ml := Engine.get_main_loop()
        if ml is SceneTree:
                var loc := (ml as SceneTree).root.get_node_or_null("Locale")
                if loc != null and loc.has_method("t"):
                        var key := "tpl_" + id
                        var s := String(loc.call("t", key))
                        if s != key:
                                return s
        return _title(id)


static func _title(id: String) -> String:
        var names := {
                "obby": "Obby",
                "racing": "Racing",
                "city": "City",
                "survival": "Survival",
                "horror": "Horror Maze",
                "bedwars": "Bed Wars",
                "hide_seek": "Hide and Seek",
                "empty": "Empty World",
                "adventure": "Adventure",
                "tycoon": "Tycoon",
        }
        return String(names.get(id, "Dunia"))


static func _box(
        blocks: Array, pos: Vector3, size: Vector3, color: String, mat: String = "plastic"
) -> void:
        (
                blocks
                . append(
                        {
                                "id": "b%d" % blocks.size(),
                                "shape": "box",
                                "pos": _pvec(pos),
                                "size": _pvec(size),
                                "color": color,
                                "mat": mat,
                                "anchored": true,
                                "script": "",
                        }
                )
        )


static func _pvec(v: Vector3) -> Array:
        return [snappedf(v.x, 0.5), snappedf(v.y, 0.5), snappedf(v.z, 0.5)]


static func _set_spawn(w: Dictionary, pos: Vector3) -> void:
        var p := _pvec(pos)
        var settings: Dictionary = w["settings"]
        settings["spawn"] = p
        w["spawn_points"] = [p]


static func _rng_for(id: String) -> RandomNumberGenerator:
        var rng := RandomNumberGenerator.new()
        rng.seed = hash("rblox-" + id)
        return rng


static func _hsl_color(rng: RandomNumberGenerator) -> String:
        return "#" + Color.from_hsv(rng.randf(), 0.62, 0.85).to_html(false)


static func _adv_height(wx: float, wz: float) -> float:
        var h := 1.6 + 1.5 * sin(wx * 0.35) + 1.4 * cos(wz * 0.3) + 0.9 * sin((wx + wz) * 0.18)
        return maxf(0.3, snappedf(h, 0.25))
