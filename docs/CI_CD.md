# CI/CD RBlox — Build APK, Release & Auto-Fix

Dokumentasi pipeline CI/CD GitHub Actions untuk proyek Godot 4.4 **RBlox** (Android).
Semua workflow hanya memakai `${{ secrets.GITHUB_TOKEN }}` bawaan GitHub — tidak ada
PAT/token keras yang disimpan di repo.

## Diagram alur (teks)

```text
                         ┌────────────────────────────────────────────┐
   push/PR ke main ─────►│  Workflow: Build Android APK (build.yml)   │
   tag push v*      ────►│  (juga: manual workflow_dispatch)          │
                         └───────────────────┬────────────────────────┘
                                             │ job "build"
                     Checkout → Java 17 → Android SDK 34 → cache/install Godot 4.4.1
                     → debug keystore → pasang template gradle (android/build)
                     → godot --import → godot --export-release "Android"
                         │                     │ gagal?
                         │                     └── fallback: preset "Android-Quick"
                         │                          (prebuilt, tanpa gradle)
                     cek ukuran APK ≤ 300 MB → upload artifact "RBlox-Android"
                                             │
              ┌──────────────────────────────┼───────────────────────────────┐
              │ push ke main?                │ tag v* atau input             │
              ▼                              │ create_release = true?        │
   ┌──────────────────────┐                  ▼                               │
   │ job "dev-release"    │       ┌──────────────────────┐                   │
   │ pre-release persisten│       │ job "tag-release"    │                   │
   │ "dev-build" (upsert) │       │ GitHub Release + APK │                   │
   └──────────────────────┘       └──────────────────────┘                   │
                                             │
                         build GAGAL? ──► trigger (workflow_run: completed)
                                             ▼
                         ┌────────────────────────────────────────────┐
                         │  Workflow: CI Auto-Fix (autofix.yml)       │
                         │  python tools/ci_autofix.py                │
                         └────────────────────────────────────────────┘
```

## Workflow 1: `Build Android APK` (`.github/workflows/build.yml`)

Terpicu oleh: push ke `main`, pull request ke `main`, push tag `v*`
(dibaca lewat kondisi job), dan manual `workflow_dispatch` (opsi
`create_release`). Godot versi **4.4.1** (env `GODOT_VERSION`).

### Job `build` — Export Android APK

1. **Checkout** + **Setup Java 17** (Temurin) — dibutuhkan Gradle.
2. **Setup Android SDK**: terima lisensi, pasang `build-tools;34.0.0`,
   `platforms;android-34`, `platform-tools` (sesuai targetSdk 34 preset "Android").
3. **Cache Godot & template** (`actions/cache`): biner `/usr/local/bin/godot` +
   `~/.local/share/godot/export_templates`. Cache miss → unduh editor & export
   templates resmi 4.4.1-stable dari GitHub releases Godot.
4. **Generate debug keystore** (`~/.android/debug.keystore`) agar Gradle bisa
   menandatangani APK untuk pengujian.
5. **Install Android build template**: unzip `android_source.zip` dari template
   ke `android/build/` (direktori gradle_build pada `export_presets.cfg`).
6. **Import aset**: `godot --headless --import --path "$PWD"`.
7. **Export APK**: preset **"Android"** (gradle, minSdk 24 / targetSdk 34).
   Bila gagal → `::warning::` lalu fallback ke preset **"Android-Quick"**
   (prebuilt, tanpa gradle). Hasil: `build/RBlox.apk`.
8. **Cek ukuran APK** maksimum **300 MB** (gagal bila lebih).
9. **Upload artifact** `RBlox-Android` (retensi 14 hari, error bila APK tidak ada).

### Job `dev-release` — Pre-release berkelanjutan

- Syarat: hanya untuk **push ke `main`**.
- Mengunduh artifact APK lalu **menghapus & membuat ulang** release
  `dev-build` (pre-release, judul "RBlox Dev Build") dengan `gh release`.
  Selalu ada satu APK dev terbaru yang bisa diunduh pemain.

### Job `tag-release` — GitHub Release resmi

- Syarat: push **tag `v*`** ATAU dispatch manual dengan input
  `create_release = true`.
- Membuat release dengan nama tag (mis. `v1.0.0`) + `--generate-notes`.
- Bila dipicu manual (ref = `main`), nama tag otomatis `v<timestamp>-manual`.
- Bila release sudah ada → upload APK ulang (`gh release upload --clobber`).

## Workflow 2: `CI Auto-Fix` (`.github/workflows/autofix.yml`)

- **Kapan jalan**: setiap workflow `Build Android APK` selesai dengan status
  `failure` (via `workflow_run`), atau manual lewat `workflow_dispatch`.
- Menjalankan `python tools/ci_autofix.py` dengan Python 3.11 dan
  `gdtoolkit==4.*` (menyediakan `gdformat`).

### Apa yang diperbaiki

1. **`gdformat`** pada semua `**/*.gd` (menyeragamkan format kode GDScript).
2. **`tools/sync_locales.py`**: memastikan setiap `Locale.t("key")` di kode
   tersedia di `data/locales/en.json` & `id.json` (key baru otomatis ditambah).
3. Bila ada perubahan → commit **`[autofix] perbaikan otomatis CI (format+locale)`**
   dan push ke `main` (push baru otomatis memicu build ulang).

### Guard anti-loop

- Bila commit terakhir di `main` sudah diawali `[autofix]` → **tidak push**
  (mencegah siklus build → autofix → build tanpa akhir).
- Bila tidak ada perubahan → tidak commit, tidak push.

### Issue otomatis

- Bila auto-fix tidak bisa menyelesaikan (tidak ada perubahan / anti-loop
  aktif), script membuat atau mengomentari issue berjudul
  **"CI merah - perlu perbaikan manual"** berisi ekstrak baris error
  (pola `Parse Error|SCRIPT ERROR|ERROR|error:`, maks 60 baris) + link ke run
  yang gagal. Dedupe dilakukan lewat `gh issue list` berdasarkan judul persis,
  jadi tidak menumpuk issue duplikat.
- Script selalu exit 0 (kecuali error fatal kritis) agar workflow auto-fix
  sendiri tidak ikut merah.

## Cara membuat release

**Cara 1 — tag (disarankan):**

```bash
git tag v1.0.0
git push origin v1.0.0
```

Build jalan → `tag-release` membuat release `v1.0.0` + APK + release notes otomatis.

**Cara 2 — manual dispatch:** tab *Actions* → *Build Android APK* → *Run
workflow* → centang **create_release** → APK diunggah ke release
`v<tanggal-jam>-manual`.

**APK dev harian:** setiap push ke `main` memperbarui pre-release `dev-build`.

## Catatan keamanan

- Hanya memakai **`GITHUB_TOKEN` bawaan** (via `permissions: contents: write`
  dan `issues: write`) — **tanpa PAT** dan **tanpa secret tambahan** di repo.
- Keystore yang dipakai CI adalah **debug keystore yang dibuat ulang setiap
  run** — hanya untuk pengujian internal, BUKAN untuk distribusi publik.
- Untuk rilis publik nanti: simpan keystore release + password sebagai
  **GitHub Actions secrets** (mis. `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`) dan tanda tangani APK di job release;
  jangan pernah commit keystore ke repo.

## Tips mempercepat build

- **Cache Godot & template**: biner editor (~100 MB) + export templates
  (~1 GB) hanya diunduh saat versi berubah / cache tereduksi (key
  `godot-4.4.1-linux-templates`).
- **Concurrency `build-${{ github.ref }}`** dengan `cancel-in-progress: true`:
  push beruntun ke branch yang sama membatalkan run lama yang masih jalan.
- **Concurrency `autofix`** dengan `cancel-in-progress: false`: antrikan
  auto-fix agar tidak saling menimpa commit.
- APK artifact disimpan 14 hari — cukup untuk QA tanpa memenuhi storage.

## Release split per ABI (v0.2.0+)

Setiap build sekarang menghasilkan **4 APK** (artifact `RBlox-Android`,
pre-release `dev-build`, dan GitHub Release bertag `v*`):

| File | Arsitektur | Untuk |
|---|---|---|
| `RBlox-arm64-v8a.apk` | 64-bit ARM | HP modern (disarankan, terkecil & tercepat) |
| `RBlox-armeabi-v7a.apk` | 32-bit ARM | HP/laptop lama |
| `RBlox-x86_64.apk` | 64-bit x86 | Emulator, ChromeOS |
| `RBlox-universal.apk` | semua | Cadangan/kompatibilitas maksimum |

Mekanisme: 3 preset ekspor tambahan (`Android-arm64`, `Android-armv7`,
`Android-x86_64`) di `export_presets.cfg` — masing-masing hanya mengaktifkan
satu arsitektur sehingga Gradle menghasilkan APK terpisah per ABI, ditambah
preset universal. Semua preset memakai `min_sdk=24`, `target_sdk=34`,
versionCode `2`, dan keystore debug yang diisi otomatis oleh CI via `sed`.

Rilis bertag: buat tag `v0.2.0` (`git tag v0.2.0 && git push origin v0.2.0`)
→ workflow `tag-release` melampirkan keempat APK ke GitHub Release.

## Pratinjau screenshot tanpa install (mode demo)

Engine dapat dirender tanpa APK untuk dokumentasi/QA:

```bash
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp &
sleep 2
DISPLAY=:99 godot --path . --resolution 1920x1080 \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --audio-driver Dummy -- --screenshot-demo --shot-dir=/abs/path
```

Menghasilkan 5 tangkapan 1080p: `rblox-menu.png` (menu utama),
`rblox-gameplay.png` (kota aerial sinematik), `rblox-build.png` (mode build
dengan lengkung pelangi + HUD), `rblox-obby.png` (spiral platform senja),
dan `rblox-avatar.png` (editor avatar). Kualitas tangkapan dijaga khusus
untuk rasterizer software (llvmpipe): bayangan dimatikan (bebas shadow
acne), gedung kaca dibuat solid (alpha blend pada wajah miring menghasilkan
arsir dither), air hanya muncul pada terrain yang di-sculpt (plane air y=1
dulu "membanjiri" dunia flat), tanah kota satu box tanpa sambungan antar
tile, dan jalan berupa box tebal ber-atap 0.1u (curb yang bisa dilangkahi).

Hasil render dipakai untuk galeri README (`docs/screenshots/`, nama file
dipertahankan apa adanya). Workflow CI juga menjalankan job `screenshots`
paralel yang mengunggah kelima PNG sebagai artifact `RBlox-Screenshots`
pada setiap push main. Catatan: `xvfb-run` butuh `xauth` yang mungkin tak
tersedia; pakai `Xvfb` langsung seperti di atas.

## Auto-run APK rilisan di emulator (job `smoke-test`)

Setiap push main (dev pre-release `dev-build`) dan tag `v*`, job `smoke-test`
menguji **APK hasil release yang sudah terbit** — bukan artifact mentah build:

1. `gh release download` APK `RBlox-x86_64.apk` (fallback `RBlox-universal.apk`)
   dari tag rilisan yang diuji (`dev-build` atau tag `v*`).
2. Android emulator (API 34, google_apis, x86_64, KVM, Pixel 5) dinyalakan
   headless (`-no-window -gpu swiftshader_indirect`).
3. `ci/emulator_smoke.sh`: `adb install` → launch via monkey → tunggu aktivitas
   game jadi ResumedActivity → tunggu log `Godot Engine v...` → cek crash-buffer
   logcat paket `com.secretarrow.rblox` → screenshot → tap layar → screenshot →
   pastikan proses masih hidup. Lulus = `EMULATOR_SMOKE_PASS`.
4. Screenshot `emulator-1.png` / `emulator-2.png` diunggah sebagai artifact
   `RBlox-Emulator-Smoke` **dan dilampirkan ke release** (`--clobber`) sehingga
   bisa dilihat tanpa install.

Catatan teknis: renderer project adalah `mobile` (Vulkan). Emulator CI tanpa
GPU host tidak punya Vulkan, sehingga `rendering_device/fallback_to_opengl3=true`
membuat Godot otomatis memakai backend OpenGL (Compatibility) saat smoke test —
perangkat fisik yang mendukung Vulkan tetap memakai jalur Vulkan penuh. Job ini
dilewati untuk event pull_request dan tetap hijau saat salah satu job rilisan
di-skip (kondisi `!contains(needs.*.result, 'failure')`).
