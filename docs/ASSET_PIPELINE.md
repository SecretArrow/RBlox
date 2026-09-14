# Asset Pipeline — Ekosistem Aset "Roblox Modern" (AI → Blender → Godot)

Panduan menyusun ekosistem aset (karakter, rumah/bangunan modular, prop/tools)
dengan estetika Roblox Modern: geometri modular chunky, beveled edges, tekstur
stylized bersih, low-poly. Pipeline dirancang untuk otomasi penuh lewat
**GLM + MCP** dan terintegrasi dengan sistem RBlox yang sudah ada
(MMChunks, PolyBudget, build grid).

```
Meshy / Tripo3D / CSM        Blender headless                Godot 4.4 (RBlox)
┌───────────────────┐   ┌──────────────────────────┐   ┌─────────────────────┐
│ prompts/3d_asset_ │   │ tools/blender/           │   │ assets/meshes/...   │
│ prompts.md        │──▶│ rbx_pipeline.py          │──▶│ import .glb         │
│ (prompt library)  │GLB│ decimate + bevel +       │GLB│ PolyBudget.audit()  │
│                   │   │ material + pivot + audit │   │ snap-to-grid build  │
└───────────────────┘   └──────────────────────────┘   └─────────────────────┘
        ▲                            ▲                          │
        └──── prompts/texture_prompts.md (albedo → normal/roughness)
```

## 1. Alur Kerja (GLM + MCP)

1. **Generate mesh mentah** — pilih prompt dari `prompts/3d_asset_prompts.md`,
   jalankan di Meshy/Tripo/CSM dengan setting tabel §6 di file tersebut, unduh
   `.glb`.
2. **Olah via Blender headless** — GLM mengeksekusi lewat MCP (shell tool):
   ```bash
   blender --background --python tools/blender/rbx_pipeline.py -- \
       --input sword_raw.glb --output sword_game.glb \
       --category small_prop --color "#c0392b"
   ```
   Baca `RBX_REPORT {...}` dari stdout: `within_budget: true` → lanjut;
   `false` → agent menaikkan `--decimate` manual atau regenerate.
3. **Tekstur (opsional)** — generate albedo dari `prompts/texture_prompts.md`,
   turunkan normal/roughness (§6 file tersebut), simpan di samping mesh.
4. **Masuk repo** — taruh di `assets/meshes/props/` (kit-piece bangunan:
   `assets/meshes/kit/`), commit, CI membangun APK.
5. **Audit runtime** — scene yang memakai prop diperiksa
   `PolyBudget.audit(root)`; klasifikasi via group
   (`hero_prop`/`small_prop`/`environment`) atau nama node.

## 2. Import ke Godot 4.4

- **Format: .glb** (glTF 2.0 binary). Godot mengimpor langsung; jangan
  komit .blend (butuh Blender di CI).
- Import dock: *Generate Tangents = on* (bila pakai normal map),
  *Mesh → Ensure Tangents*, *Compress = VRAM Compressed* untuk tekstur >512px.
- Nama material Blender `rbx_plastic` otomatis jadi material glTF; override di
  Godot dengan tabel §3 bila perlu.
- Simpan scene prop sebagai `.tscn` tipis: root `Node3D` bernama sesuai kategori
  (mis. `SmallPropSword`) → `PolyBudget.classify()` mengenali nama.

## 3. Material & Shader — Memancarkan Vibe Roblox

Prinsip: **plastik matte lembut + AO di lekukan**, bukan PBR norak.

| Parameter StandardMaterial3D | Nilai | Alasan |
| --- | --- | --- |
| Albedo | vertex color / tekstur stylized | warna blok datar khas Roblox |
| Roughness | 0.85 – 1.0 | plastik mainan tidak mengkilap |
| Metallic | 0 (atau 0.9 via mask logam) | plastic-only kecuali part logam |
| Specular | 0.3 – 0.4 | highlight tipis agar bentuk terbaca |
| Normal map | opsional, strength 0.3 – 0.5 | detail murah tanpa polygon (tip #1) |
| Vertex Color → Albedo | ON untuk blok | selaras MMChunks |
| Cull Mode | Back | standar; pastikan mesh manifold |
| Transparency | hanya material `glass` (alpha 0.4) | sesuai `_material()` mm_chunks |

Blok statis JANGAN diberi tekstur (vertex color sudah cukup); tekstur PBR
diprioritaskan untuk prop/kit-piece AI dan aksesoris avatar.

## 4. Snap-to-Grid Modular System

Grid dasar RBlox = 1 unit blok; kit-piece modular memakai footprint **4 unit**;
snap prop = 0.5 unit. Pipeline Blender sudah menjamin pivot dasar-tengah
(`step_origin_grid`), sehingga di engine cukup:

```gdscript
const GRID := 0.5  # 1.0 untuk blok dasar; 4.0 untuk footprint kit bangunan

func snap(pos: Vector3) -> Vector3:
        return Vector3(snappedf(pos.x, GRID), snappedf(pos.y, GRID), snappedf(pos.z, GRID))

# Rotasi kit-piece hanya kelipatan 90 derajat:
func snap_yaw(yaw: float) -> float:
        return roundf(yaw / (PI / 2.0)) * (PI / 2.0)
```

Aturan kit modular (agar semua piece sambung mulus):

1. Semua piece lahir dari footprint 4x4 unit, tinggi kelipatan 3 unit
   (dinding), pivot dasar-tengah — dijamin script Blender (`--fit 4`).
2. Dinding punya "tongue" kosong 0.5 unit di kedua ujung → sudut diisi piece
   corner; atap menutupi toleransi via overhang lip.
3. Rotasi hanya 0/90/180/270; tidak ada skala non-seragam.
4. Pratinjau penempatan (ghost) memakai material transparan sebelum klik
   place — pola yang sama dengan build tool RBlox.

## 5. Lighting & AO — Setting Dunia Roblox-like

Vibe Roblox = ambient tinggi, bayangan lembut satu arah, warna jenuh bersih.

| Setting (Environment) | Nilai | Catatan |
| --- | --- | --- |
| Ambient light | source COLOR, energy 1.0 – 1.2, warna putih hangat | dasar "flat" khas toy |
| Tonemap | FILMIC, exposure 1.0 | kontras lembut tanpa pucat |
| Glow | off kecuali material `neon`, intensity ≤ 0.6 | hemat di mobile |
| SSAO | low = OFF, medium/high = ON (radius 0.5, intensity 1.5) | AO murah di lekukan bevel |
| DirectionalLight3D | energy 1.2 – 1.4, sudut -35°, shadow blur 1.0 | satu matahari |
| Shadow | `low`: off; `medium/high`: on | selaras LOD MMChunks |

AO paling meyakinkan justru dari **bevel geometry** (sudut menangkap AO alami)
— itulah kenapa pipeline Blender memaksakan bevel pada semua sudut tajam.
SSAO hanya pemanis di kualitas medium/ke atas.

## 6. Instancing & Budget

- Prop unik (hero prop, tool) = `MeshInstance3D` biasa, hitungannya masuk
  `PolyBudget.audit`.
- Prop yang berulang banyak (pohon, batu, kursi) → jadikan **MultiMesh**
  (sama seperti blok) atau setidaknya share mesh+material resource —
  lihat tip #2 docs/PERFORMANCE.md.
- Total tris terlihat dipantau chip HUD (`60 FPS • N tris`); jika kuning/merah,
  kurangi kepadatan prop atau turunkan profil LOD.

## 7. Checklist QC Akhir (per aset)

- [ ] `RBX_REPORT` `within_budget: true` sesuai kategori.
- [ ] Silhouette terbaca di ikon 64px.
- [ ] Pivot dasar-tengah, rotasi 0/90/180/270 menghasilkan sambungan mulus
      (uji 4 piece dinding + corner + atap).
- [ ] Material: roughness ≥ 0.85, metallic 0 (kecuali mask logam).
- [ ] Tekstur 1024px, tiling mulus 3x3, normal strength ≤ 0.5.
- [ ] Di game: tidak menaikkan chip tris melewati hijau (≤ 100k on-screen).
