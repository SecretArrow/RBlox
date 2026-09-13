# Arsitektur RBlox

## Ringkasan

RBlox adalah game sandbox 3D (Godot 4.4 / GDScript) dengan pola **orchestrator + autoload facade**:

```
main_menu ──▶ world_select ──▶ game.tscn (Orchestrator)
   │              │                 │
   │              │                 ├── WorldManager.build_world(json)  → WorldRoot/Blocks/Props/Terrain
   │              │                 │     └── Blocks/MMChunks (MultiMesh per chunk 16u + LOD jarak)
   │              │                 ├── player.tscn (local + remote)
   │              │                 ├── mode controller (10 game mode)
   │              │                 ├── day_night + weather + game_hud (+ minimap)
   │              │                 ├── build_manager + build_hud (bila diizinkan)
   │              │                 └── chat_overlay (bila multiplayer)
   ├── avatar_editor (SubViewport 3D preview)
   └── lobby (host/join via Net facade → lan_backend)
```

## Autoload (kontrak tetap)

| Autoload | Tanggung jawab | API kunci |
|---|---|---|
| `Locale` | i18n JSON `data/locales/{id,en}.json` | `t(key, vars)`, `set_language`, sinyal `language_changed` |
| `Settings` | Preferensi `user://settings.cfg` + tema | `get_value/set_value`, `get_theme()` (dark/light via `scripts/ui/theme_builder.gd`), `chat_enabled()` |
| `GameState` | Sesi, avatar, statistik, achievement, input map bootstrap | `player_name`, `avatar_config`, `pending_action`, `goto_scene()`, `unlock_achievement()`, `add_stat()` |
| `Saves` | File world `.myworld` (JSON), ekspor/impor, screenshot | `list_worlds`, `save_world`, `load_world`, `export_world`, `import_world` |
| `Net` | **Facade** multiplayer; delegasi ke backend | `host_room/join_room/leave/players/send_chat/kick/start_game/rpc_block_update/send_player_state/list_lan_rooms` + 8 sinyal |

**Aturan**: modul lain TIDAK boleh mengubah autoload; backend multiplayer (`scripts/multiplayer/lan_backend.gd`) di-resolve dinamis oleh facade (`ResourceLoader.exists`), sehingga proyek tetap jalan meski backend dirombak.

## Skema Data

### World `.myworld` (JSON)
```json
{
  "format": "rblox-world", "version": 1,
  "meta": { "name": "...", "is_template": false },
  "settings": { "game_mode": "obby", "day_night": true, "cycle_minutes": 10,
                "weather": "clear", "health_enabled": true, "build_allowed": false },
  "spawn_points": [[0,3,0]],
  "blocks":  [{ "id": "b1", "shape": "box", "pos": [x,y,z], "size": [1,1,1],
                "color": "#ff0000", "mat": "plastic", "anchored": true, "script": [] }],
  "props":   [{ "type": "checkpoint", "pos": [x,y,z], "...": {} }],
  "terrain": { "size": 64, "seed": 1, "heights": [4096], "paint": ["grass"] }
}
```
- `shape` ∈ box/sphere/cylinder/wedge · `mat` ∈ plastic/metal/wood/glass/neon
- `pos` = titik tengah blok (snap grid 0.5)
- Terrain: heightmap 64×64 (tinggi 0..8), paint ∈ grass/dirt/rock/sand

### Kosmetik `data/cosmetics/cosmetics.json`
```json
{ "id": "hat_cap_red", "slot": "hat", "name": {"id": "...", "en": "..."},
  "shapes": [{ "type": "box", "parent": "head", "pos": [0,0.3,0], "size": [0.42,0.12,0.42], "color": "#d33" }] }
```
52 item pada 9 slot (hat/hair/face/shirt/pants/accessory/wings/back/hand) + 8 preset.

## Multiplayer (host-client)

- **Transport MVP**: ENet TCP/UDP andal Godot, port **24565** (data) + UDP **24566** (discovery broadcast).
- **Topologi**: host = server = authority dunia. `SceneMultiplayer.server_relay` aktif → client dapat RPC antar-client via server.
- **Protokol RPC**: register pemain (reliable), player state (unreliable_ordered 15 Hz), chat (reliable, cap 200 char, parental gate), world JSON chunked 32 KB, block update (reliable, host→all), kick (notify + disconnect).
- **Reconnect**: client auto-rejoin 3× (interval 2 s); watchdog host 8 s.
- **Sinkronisasi blok**: build manager host → `Net.rpc_block_update` → broadcast → `WorldManager.apply_block_update` di semua klien.
- Detail lengkap: [MULTIPLAYER.md](MULTIPLAYER.md). Bluetooth/WiFi Direct: skeleton plugin Kotlin di `android_plugins/bluetooth/` (Alpha).

## Game Scene (orchestrator)

`scripts/world/game.gd` mengorkestrasi seluruh sesi dengan **defensive loading** (`ResourceLoader.exists` + `has_method` + fallback), sehingga satu modul yang rusak tidak menjatuhkan game:

1. Resolve world: `Net.current_world()` → `GameState.pending_action` (world_id template / world_path file) → fallback "empty".
2. Build dunia → spawn player lokal + remote (authority per peer) → touch controls → mode controller → env (day/night, weather) → HUD → build mode (bila `build_allowed` & host/SP) → chat (MP) → tutorial (first run).
3. Sinyal bersih: mode/HUD membaca via **group** (`local_player`, `remote_players`, `npcs`, `game`, `mode_controller`, `env_day_night`, `touch_controls`) — bukan referensi keras.

## Performa Rendering Blok (v0.2)

Modul `scripts/world/mm_chunks.gd` (MMChunks, anak dari `Blocks/`):

- **Chunked MultiMesh**: dunia dibagi chunk kubus 16 unit; tiap chunk
  mengelompokkan blok statis per bucket `shape|material` menjadi satu
  `MultiMeshInstance3D` (1 draw call per bucket, bukan 1 per blok).
  Warna per blok lewat instance color (material `vertex_color_use_as_albedo`).
- **Fisika tak berubah**: `StaticBody3D` + `CollisionShape3D` tetap dibuat
  per blok sehingga raycast build tool & collision pemain identik. Blok
  rigid (non-anchored) tetap memakai `MeshInstance3D` (jalur legacy).
- **LOD jarak** per kualitas grafis (`graphics_quality`): low 40/72,
  medium 72/112, high 104/160 — chunk jauh disembunyikan, chunk menengah
  tanpa bayangan; diperbarui tiap 0.25s.
- **Cache statis**: 5 mesh unit + 5 material dibagi seluruh dunia (hemat RAM
  untuk perangkat 3-4GB). Limit build naik 4000 → 12000 blok.
- **Uji headless**: `tools/test_mm.tscn` (fungsional, dijalankan CI) dan
  `tools/test_mm_scale.gd` (12.000 blok → ~120 draw call, build 0.4s).

## Standar Kode

- GDScript 4.4, indentasi konsisten per file, tanpa `class_name` global (pakai `preload` + const).
- UI dibangun **programatik**; `.tscn` minimal (root + script) agar aman di-review & merge.
- Semua teks via `Locale.t()`; key disinkron otomatis oleh `tools/sync_locales.py` (lokal & CI).
- Anggaran performa MVP: ≤ 4000 blok (Node3D), NPC ≤ 8 aktif, terrain 64×64 single-mesh; MultiMesh & LOD menyusul di Alpha.
