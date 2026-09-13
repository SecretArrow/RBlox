# Rencana Pengembangan RBlox — MVP → Alpha → v1.0

## Fase 1 — MVP (v0.1, sekarang) ✅

Fondasi lengkap yang bisa dimainkan:

- [x] Engine core Godot 4.4 (mobile renderer, landscape, 60 FPS target)
- [x] Kontrol sentuh penuh (joystick, kamera drag, lompat/sprint/aksi) + gamepad
- [x] Avatar blocky + editor (52 kosmetik, 8 preset, palet warna, ekspresi)
- [x] Build mode: blok 4 bentuk × 5 material × 24 warna, undo/redo, fisika anchored/dynamic
- [x] Terrain editor 64×64 (naik/turun/rata/cat) + collision
- [x] Save/Load world + ekspor/impor `.myworld`
- [x] 10 template world + 10 game mode dasar + NPC bot + kart
- [x] Multiplayer LAN/hotspot 16 pemain (host-client, discovery, chat, kick, reconnect)
- [x] Block coding visual (tap-based) + mini scripting (Expression)
- [x] Siklus siang-malam, cuaca (hujan/kabut/salju), minimap, health
- [x] Tutorial interaktif, achievement offline, kontrol orang tua (chat)
- [x] i18n Indonesia/English, dark/light mode
- [x] CI/CD: APK otomatis tiap push, dev pre-release, auto-fix workflow

## Fase 2 — Alpha (v0.2 → v0.6, bulanan)

| Rilis | Fokus | Item utama |
|---|---|---|
| v0.2 | Performa | **MultiMesh** untuk blok (target 10.000+), LOD + occlusion sederhana, object pooling NPC/partikel, texture ASTC audit |
| v0.3 | Multiplayer luas | **Plugin Android Bluetooth (RFCOMM) 2-8 pemain** + WiFi Direct (komponen `android_plugins/` sudah disiapkan), migrasi host, late-joiner menerima world, voice ringan (opsional) |
| v0.4 | Kreasi lanjut | Drag-and-drop block coding penuh, **script VM mirip Lua** (sandboxed), katalog tekstur prosedural, kendaraan tambahan, ragdoll |
| v0.5 | Audio & media | Paket audio (musik menu, SFX, langkah), **screen recorder** (MediaProjection plugin), share `.myworld` via intent berbagi |
| v0.6 | Polish | Parental control + PIN, inkubator template komunitas, polish UI/UX, animasi avatar lanjutan |

## Fase 3 — v1.0 (stabil publik)

- Stabilitas 60 FPS di perangkat RAM 3-4GB (benchmark matrix: 5 perangkat kelas bawah-menengah)
- Suite pengujian otomatis (smoke test headless per scene + mode)
- Dokumentasi pembuat konten (buku panduan build & scripting)
- 15+ template world tambahan, galeri in-app
- Signed release keystore via GitHub Secrets + kepatuhan penuh Google Play (target SDK terbaru, data safety form)
- Store listing + roadmap update bulanan publik

## Roadmap Bulanan (kalender)

| Bulan | Milestone |
|---|---|
| Bulan 1 | v0.2 performa (MultiMesh, LOD) |
| Bulan 2 | v0.3 Bluetooth + WiFi Direct |
| Bulan 3 | v0.4 scripting & kreasi lanjut |
| Bulan 4 | v0.5 audio + recorder + share |
| Bulan 5 | v0.6 parental + polish |
| Bulan 6 | v1.0 stabil + publikasi |

## Kriteria Kelulusan Antar-Fase

1. **MVP → Alpha**: build CI hijau stabil, APK terinstall & playable di Android 7 (API 24) dan Android 14 (API 34), semua 10 template jalan offline, sesi multiplayer LAN 4 pemain tanpa crash 30 menit.
2. **Alpha → v1.0**: benchmark 60 FPS rata-rata di perangkat target, crash-free rate > 99% sesi uji, fitur Alpha lengkap, dokumen konten kreator terbit.

## Changelog singkat

- **v0.2.0** — Build & rilis **split per ABI** (arm64-v8a, armeabi-v7a, x86_64,
  universal), cache Gradle di CI, smoke test headless otomatis per push,
  versionCode 2. Semua APK dirilis di pre-release `dev-build` dan release
  bertag `v*`.
