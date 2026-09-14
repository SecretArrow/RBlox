# Prompt Library — AI 3D Asset Generation (Gaya "Roblox Modern")

Library prompt untuk generator AI 3D (**Meshy**, **Tripo3D**, **CSM**) demi
menghasilkan mesh mentah bergaya Roblox Modern: chunky, beveled edges, clean
geometry, low-poly. Semua prompt sengaja ditulis dalam **bahasa Inggris** karena
model generasi 3D dilatih dominan pada deskripsi Inggris — hasil jauh lebih akurat.

Seluruh aset hasil pipeline ini wajib melewati audit budget polygon RBlox
(lihat `docs/PERFORMANCE.md`): avatar ≤ 5.000 tris, NPC ≤ 2.500, hero prop
≤ 4.000, prop kecil ≤ 1.000, environment ≤ 500 — dan script
`tools/blender/rbx_pipeline.py` akan memvalidasinya otomatis.

---

## 1. Formula Prompt Universal

Setiap prompt disusun dengan blok tetap berikut. Blok "STYLE ANCHORS" adalah DNA
gaya Roblox Modern — jangan dihapus atau diubah urutannya.

```
[SUBJECT]              → objek utama + fungsi + pose
[STYLE ANCHORS]        → chunky stylized game asset, boxy modular geometry,
                         soft beveled edges, clean flat surfaces, low-poly
                         toy-like plastic, matte finish, bold simple silhouette
[GEOMETRY RULES]       → grid-aligned, uniform scale, closed manifold mesh,
                         no floating parts, thick proportions, mobile game-ready
[TECH SPECS]           → target triangle budget, pose, orientation, scale
[NEGATIVE]             → hal-hal yang dilarang (lihat §5)
```

## 2. Karakter Blocky / Ranthro

> Catatan teknis: badan avatar RBlox **sudah dibangun prosedural dari box**
> (`scripts/avatar/avatar_builder.gd`) — itu cara paling bersih dan paling murah
> (ratusan tris). Prompt AI karakter paling bernilai untuk **aksesoris** (topi,
> rambut, sayap, gear) yang butuh bentuk khas namun tetap blocky.

### 2a. Karakter blocky penuh (untuk NPC/hero custom)

```
Blocky humanoid game character, Roblox R6 style proportions, boxy rectangular
torso and limbs with rounded-corner joints, chunky 2:1:1 head-to-body ratio,
sturdy stance, T-pose, perfectly symmetric left-right, color-blocked regions
(skin, shirt, pants, shoes), chunky stylized game asset, boxy modular geometry,
soft beveled edges, clean flat surfaces, low-poly toy-like plastic, matte
finish, bold simple silhouette, closed manifold mesh, mobile game-ready,
under 5000 triangles
```

**Negative:**

```
organic, realistic human anatomy, muscles, fingers, flowing cloth, hair strands,
high-poly, sculpted details, surface noise, asymmetric limbs, thin fragile
parts, pose, skin texture, photorealistic
```

### 2b. Aksesoris kepala (topi/rambut/masker)

```
[DESKRIPSI: e.g. "blocky pirate tricorn hat", "chunky spiky anime hair helmet",
"robot visor mask"], Roblox accessory style, single solid piece designed to sit
on a boxy head, chunky stylized game asset, boxy modular geometry, soft beveled
edges, clean flat surfaces, low-poly toy-like plastic, matte finish, bold simple
silhouette, centered origin, mobile game-ready, under 1000 triangles
```

### 2c. Gear tangan / sayap / punggung

```
[DESKRIPSI: e.g. "chunky rocket wings backpack", "blocky blaster tool"],
Roblox gear style, one-piece solid prop with grip area aligned to a blocky hand,
chunky stylized game asset, ... (sama seperti 2b) ..., under 1000 triangles
```

## 3. Rumah / Gedung Modular

Prinsip kunci: **jangan pernah memprompt "sebuah rumah utuh"**. Prompt SATU
kit-piece modular, lalu rakit di engine dengan snap-to-grid. Semua kit-piece
berbagi footprint grid 4x4 unit (setara 4 stud) dan pivot di dasar-tengah.

### 3a. Dinding standar

```
Modular building kit piece: straight wall segment, 4x4 grid footprint, 3 units
tall, uniform thickness with top cap, two small square window cutouts,
chunky stylized game asset, boxy modular geometry, soft beveled edges, clean
flat surfaces, low-poly toy-like plastic, matte finish, flat solid colors,
grid-aligned pivot at bottom center, closed manifold mesh, mobile game-ready,
under 500 triangles
```

### 3b. Varian kit (ganti [KIT PIECE])

| Kit Piece | Ganti bagian awal prompt dengan |
| --- | --- |
| Sudut | `corner wall segment, L-shaped footprint 4x4 grid` |
| Pintu | `doorway wall segment, 4x4 grid footprint, rectangular door opening with top frame` |
| Jendela besar | `window wall segment, 4x4 grid footprint, one large square window opening` |
| Atap datar | `flat roof slab piece, 4x4 grid footprint, slight overhang lip on all sides` |
| Atap miring | `roof wedge piece, 4x4 grid footprint, single sloped face, triangular side walls` |
| Tangga | `staircase piece, 4x4 grid footprint, 6 chunky blocky steps` |
| Lantai | `floor tile piece, 4x4 grid footprint, thin slab with beveled border` |

### 3c. Gedung landmark (hero prop, sekali generasi)

```
Chunky low-poly watchtower building, modular block construction look made of
stacked boxes and wedges, 3 levels with balcony ring, chunky stylized game
asset, boxy modular geometry, soft beveled edges, clean flat surfaces, toy-like
plastic, matte finish, bold silhouette, closed manifold mesh, mobile game-ready,
under 4000 triangles
```

## 4. Benda / Tools

### 4a. Pedang

```
Stylized game sword, chunky broad blade with soft beveled edges, blocky
crossguard, cylindrical grip with pommel, fantasy-Roblox toy style, chunky
stylized game asset, clean flat surfaces, low-poly toy-like plastic, matte
finish, bold simple silhouette readable as inventory icon, grip aligned to
Z-axis, origin at grip center, closed manifold mesh, mobile game-ready,
under 1000 triangles
```

### 4b. Pistol

```
Stylized cartoon pistol, chunky blocky receiver and grip, thick barrel with
rounded muzzle, trigger guard as single beveled loop, no tiny parts, sci-fi
toy style, chunky stylized game asset, soft beveled edges, clean flat surfaces,
low-poly toy-like plastic, matte finish, bold silhouette readable as inventory
icon, grip aligned to Z-axis, origin at grip center, closed manifold mesh,
mobile game-ready, under 1000 triangles
```

### 4c. Ramuan (potion)

```
Stylized potion flask, chunky rounded-triangle bottle with flat shoulders,
thick blocky cork, liquid line visible as a simple color band (model the liquid
as separate closed submesh), magic-Roblox toy style, chunky stylized game asset,
soft beveled edges, clean flat surfaces, low-poly, matte glass body with flat
bright liquid color, bold silhouette readable as inventory icon, origin at
bottle base center, closed manifold mesh, mobile game-ready, under 1000
triangles
```

> Likuid dibuat sebagai submesh tertutup terpisah, bukan cairan transparan —
> transparansi di engine diatur material `glass` (lihat docs/ASSET_PIPELINE.md).

## 5. Negative Prompt Library (semua kategori)

```
organic, sculpted, realistic, photorealistic, high-poly, dense topology,
surface noise, texture noise, thin fragile parts, dangling chains, complex
curves, fillets everywhere, asymmetric, tilted, duplicate objects, base
pedestal, ground plane, background, text, watermark
```

## 6. Setting per Tool + QC

| Tool | Setting yang disarankan |
| --- | --- |
| **Meshy** | Mode Text-to-3D; Art Style = *Cartoon*/*Hard surface*; Topology = *Quad*; Target poly = sesuai budget tabel di atas; AI PBR = **off** (kita set material sendiri) |
| **Tripo3D** | Mode Text; face count = budget target; aktifkan *symmetry*; export **glb** |
| **CSM** | Gunakan image-to-3D dari render prompt 2D bila bentuk sulit; export glb |

**QC sebelum masuk pipeline Blender (rbx_pipeline.py):**

1. Silhouette terbaca dalam 1 detik (uji icon 64px).
2. Tidak ada part melayang / mesh terbuka.
3. Orientasi: +Y atas (glTF standar), grip/pivot sesuai prompt.
4. Tri count mentah ≤ 2x budget (script akan decimate jika lebih).
