# Performance & Polygon Budget — RBlox

Dokumen ini adalah acuan resmi anggaran polygon (triangles/tris) RBlox agar game
tetap lancar **60 FPS** di perangkat Android, terutama HP kelas menengah ke bawah
(RAM 3–4 GB). Aturan yang sama berlaku untuk kontributor konten, pembuat aksesori,
dan pengembangan fitur baru: **detail tidak boleh dibayar dengan polygon**, karena
di mobile yang mahal bukan hanya penggambaran triangle itu sendiri, melainkan
fill-rate, draw call, dan panas (thermal throttling) yang mengikutinya.

## 1. Tabel Budget Polygon per Kategori

Batas maksimal Roblox Studio untuk satu MeshPart adalah 20.000 tris, namun angka
itu tidak disarankan untuk satu objek di game mobile. RBlox memakai anggaran
berikut (sudah dikodekan sebagai kebijakan di `scripts/autoload/poly_budget.gd`):

| Kategori Objek | Rekomendasi (warn) | Maksimum (over) | Keterangan |
| --- | --- | --- | --- |
| Karakter Utama / Playable Avatar | 2.000 tris | **5.000 tris** | Total gabungan badan & aksesoris (hat, hair, gear). |
| NPC / Enemy / Mob | 1.000 tris | **2.500 tris** | Karakter non-pemain yang sering muncul banyak sekaligus. |
| Objek Utama / Hero Prop | 1.500 tris | **4.000 tris** | Mobil, senjata utama, chest, dan objek fokus. |
| Aksesoris / Small Props | 300 tris | **1.000 tris** | Kursi, meja, senjata kecil, item pickup. |
| Environment / Latar | 50 tris | **500 tris** | Pohon, batu, dinding, dekorasi lingkungan. |

**Batas aman total scene (budget layar):** total polygon yang terlihat dalam satu
frame kamera dijaga **≤ 100.000 tris (ideal)** dan **tidak boleh melebihi
200.000 tris**. Kedua angka ini juga dikodekan sebagai `SCENE_TARGET` dan
`SCENE_MAX` di `PolyBudget`.

## 2. Angka Nyata RBlox (Primitif Bawaan)

Seluruh blok RBlox dirender lewat `MMChunks` (MultiMesh per chunk 16 unit), dan
setiap bentuk primitif sengaja dibuat rendah polygon sehingga satu objek apa pun
selalu masuk budget environment ≤ 500 tris:

| Bentuk | Tris per objek | Catatan |
| --- | --- | --- |
| Box (blok dasar) | **12** | 6 sisi × 2 triangle. |
| Wedge (prisma) | **8** | Ramp/atau miring. |
| Cylinder | **192** | 16 segmen radial + dua tutup. |
| Sphere | **288** | 16 segmen × 8 ring. |

Konsekuensi praktisnya:

- Limit dunia 12.000 blok × 12 tris (semua box) = 144.000 tris total dunia —
  masih di bawah batas 200.000, dan **yang terlihat kamera jauh lebih kecil**
  berkat LOD chunk (lihat bagian 3).
- Avatar blocky (6 box badan + aksesoris box) berada di kisaran ratusan tris —
  sangat aman di bawah rekomendasi 2.000. Editor avatar kini menampilkan counter
  `≈ N / 5.000 tris` yang berubah kuning/merah bila kombinasi aksesoris
  mendekati/melewati batas.
- Konsistensi tabel di atas **diverifikasi otomatis** oleh
  `tools/test_budget.gd` pada setiap push (CI): angka cylinder/sphere di tabel
  ini adalah hasil pengukuran aktual mesh Godot (bukan teori), dan bila seseorang
  menaikkan segmen primitif tanpa memperbarui tabel, CI langsung merah.

## 3. Cara RBlox Memenuhi Budget (Pemetaan Tips Mobile)

1. **Textures & detail murah (PBR/Normal Map).** Detail permukaan tidak dibuat
   dari polygon tambahan. Material primitif memakai vertex color + flat shading
   yang murah di GPU mobile; kerutan/baut/tekstur untuk mesh custom di masa depan
   wajib lewat normal map/baked texture, bukan geometry. Emission (`neon`) dan
   metallic (`metal`) juga ditangani material, bukan polygon.
2. **Reuse assets & instancing.** Semua blok statis dengan bentuk+material sama
   digabung menjadi **satu MultiMeshInstance3D per bucket per chunk** — menggambar
   10.000 blok identik hanya ~120 draw call, dan menambah blok ke-10.001 tidak
   menambah biaya geometri sama sekali karena mesh unit dibagi bersama
   (cache statis). Mesh/material kustom (hat, rambut, aksesori) juga di-cache
   agar 50 aksesoris tidak menduplikasi resource.
3. **Streaming (muat yang dekat saja).** Setara `StreamingEnabled`: setiap 0,25
   detik jarak chunk ke kamera dicek terhadap profil kualitas grafis
   (low/medium/high). Chunk jauh **disembunyikan sepenuhnya** (tidak dikirim ke
   GPU), chunk menengah dirender tanpa bayangan. Inilah yang menjaga tris
   on-screen di bawah 100k meski dunia berisi 12.000 blok.

## 4. Memantau di Dalam Game

Chip kanan-atas HUD menampilkan **`60 FPS • 84k tris`** (diperbarui 2×/detik):

- **Putih** — estimasi tris on-screen ≤ 100.000 (ideal).
- **Kuning** — 100.000–200.000 (waspadai; pertimbangkan kurangi objek/ubah
  kualitas grafis ke `low`).
- **Merah** — > 200.000 (di luar budget; kinerja dapat turun).

Estimasi berasal dari jumlah instance per chunk × tris bentuk (status LOD
terakhir), sehingga akurat untuk geometri blok yang mendominasi scene. Sinyal
`PolyBudget.budget_exceeded` dipancarkan (dengan pendinginan 10 detik) bila scene
melewati batas — dapat dihubungkan ke toast/telemetri di versi berikutnya.

## 5. Alur Kerja untuk Konten Baru

Saat menambah prop/NPC/aksesori baru:

1. Hitung target: gunakan tabel bagian 1; mulai dari rekomendasi, jangan langsung
   menuju maksimum.
2. Bangun dari primitif rendah polygon atau mesh custom yang sudah di-decimate;
   cek angkanya dengan `PolyBudget.mesh_tris(mesh)` atau `PolyBudget.audit(node)`
   (satu panggilan mengembalikan rekap per kategori + daftar pelanggar).
3. Klasifikasi otomatis mengikuti group/nama node: masukkan node ke group
   `avatar`/`npc`/`hero_prop`/`small_prop`/`environment` bila nama tidak
   mencerminkan kategori.
4. Jalankan uji lokal: `godot --headless res://tools/test_budget.tscn` harus
   mencetak `BUDGET_TEST_PASS`.
