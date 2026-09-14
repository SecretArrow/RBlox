# Prompt Library — Stylized Texturing PBR (Stable Diffusion / Midjourney)

Prompt untuk menghasilkan tekstur PBR seamless (Albedo → Normal/Roughness)
bergaya **hand-painted** atau **clean-plastic** khas Roblox. Catatan alur penting:
SD/MJ menghasilkan **gambar, bukan set PBR jadi** — albedo di-generate dari
prompt, lalu Normal & Roughness diturunkan dari albedo/height memakai tool
(Materialize, ShaderMap, xNormal, atau node Blender Bake).

Albedo ditulis dalam bahasa Inggris (alasan sama dengan prompt 3D: akurasi model).

---

## 1. Formula Prompt

```
[MATERIAL]  → clean plastic toy / hand-painted wood / stylized stone brick ...
[STYLE]     → Roblox clean plastic style / hand-painted stylized game texture
[DETAIL]    → micro scratches, soft corner shading, subtle grain
[TECHNICAL] → seamless tileable texture, flat lighting, top-down flat view,
             PBR albedo map, 1024x1024, no shadows, no perspective
```

**Aturan emas albedo:** permukaan harus **rata cahaya** — tanpa bayangan
direksional, tanpa highlight specular, tanpa vignette. Detail bayangan lembut
(AO) hanya boleh di sudut/dalam celah, dan sangat tipis.

## 2. Prompt Clean-Plastic (khas Roblox)

### 2a. Plastik polos warna solid

```
seamless tileable texture, clean plastic toy material surface, solid pastel
color with extremely subtle surface micro-scratches and faint speckle, soft
ambient occlusion shading only in tiny creases, flat lighting, top-down flat
view, no shadows, no specular highlight, no gradients, stylized game texture,
PBR albedo, 1024x1024
```

### 2b. Plastik metalik kusam (receiver pistol, mesin)

```
seamless tileable texture, matte brushed plastic-metal hybrid, uniform fine
brush strokes, clean toy robot material, very subtle edge wear speckle, flat
lighting, top-down flat view, no shadows, no reflections, stylized game texture,
PBR albedo, 1024x1024
```

## 3. Prompt Hand-Painted (props & bangunan stylized)

### 3a. Papan kayu

```
seamless tileable texture, hand-painted stylized wooden planks, 6 vertical
planks with visible chunky borders, warm brown with painterly grain strokes
and small knots, clean stylized game texture like Roblox catalog wood, flat
lighting, top-down flat view, no photorealistic detail, no shadows, PBR albedo,
1024x1024
```

### 3b. Bata/batu

```
seamless tileable texture, hand-painted stylized stone bricks, chunky offset
brick pattern with soft painted mortar lines, cool gray with slight color
variation per brick, clean stylized game texture, flat lighting, top-down flat
view, no photorealism, no shadows, PBR albedo, 1024x1024
```

### 3c. Genteng atap

```
seamless tileable texture, hand-painted stylized roof shingles, chunky
overlapping rows with painted darker under-shadow line per row (thin, flat,
not 3D), terracotta red-orange, clean stylized game texture, flat lighting,
top-down flat view, PBR albedo, 1024x1024
```

### 3d. Kain/tenda

```
seamless tileable texture, hand-painted stylized fabric canvas, tight weave
pattern with painterly cross-hatch strokes, muted color, clean stylized game
texture, flat lighting, top-down flat view, PBR albedo, 1024x1024
```

## 4. Negative Prompt Library

```
photorealistic, photograph, macro lens, depth of field, strong shadows,
directional lighting, specular highlights, glossy reflections, vignette,
dark corners, perspective, tiling seams, visible edges, watermark, text,
logo, jpeg artifacts, noise, high frequency detail, 3d render
```

## 5. Parameter Generator

| Tool | Setting |
| --- | --- |
| **Stable Diffusion** | Model stylized/toon; CFG 6-8; langkah 25-35; aktifkan **Tiling** (mode `--tile` / Tiled VAE); resolusi 1024; %prompt% masuk positive/negative di atas |
| **Midjourney** | Tambahkan `--tile --style raw --ar 1:1 --v 6`; jaga prompt tetap dekat formula |
| **Meshy AI Texture** | Bisa langsung menempel prompt di atas pada mode Text/Prompt texture mesh |

## 6. Alur Albedo → Set PBR Lengkap

1. Generate albedo (prompt di atas) → cek tiling dengan menggandakan 3x3 di
   Blender/Photoshop; retouch seam bila perlu.
2. **Height/Bump**: duplikat albedo → desaturasi → kontras level → blur 0.5px
   (garis papan/bata jadi tinggi).
3. **Normal map**: dari height via Materialize / ShaderMap / xNormal
   (strength rendah 0.3-0.5 — gaya Roblox itu lembut, bukan norak).
4. **Roughness**: dari albedo → desaturasi → invert → level: bagian "kotor/gores"
   jadi lebih kasar (terang); permukaan utama ~0.85-0.95.
5. **Metallic**: flat 0 (plastik) atau flat 0.9 khusus bagian logam via mask.
6. Simpan sebagai `mat_albedo.png`, `mat_normal.png`, `mat_rough.png` (1024px,
   compress VRAM saat import Godot).
7. Validasi di Blender dengan material preview + cek budget:
   **tekstur tidak menambah triangle** — ini inti tip #1 `docs/PERFORMANCE.md`.

> Catatan RBlox: dunia blok memakai vertex color (tanpa tekstur) untuk hemat
> memori & draw call. Tekstur PBR ini diprioritaskan untuk **props/kit-piece
> hasil AI** dan aksesoris avatar; jangan pakai tekstur pada blok dasar.
