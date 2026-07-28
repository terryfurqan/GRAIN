# PAB4 → CLCW: Panduan Membaca JSON (studi lifecycle FSR)

Dokumen ini menjelaskan **isi & cara parse** dua JSON yang diproduksi PAB4, supaya
CLCW dapat merakit laporan tanpa perlu membuka MATLAB.

- **`<exp>_desc.json`** — sidecar pengamatan (ground-truth PAB4), ditulis tiap **Save
  Progress** & **Commit**. Berada di folder yang sama dengan file `.mat` PIV.
- **`<exp>_desc.json` di dalam folder Commit** — `PAB4_DESC/<exp>/<ddmmyy-HHMMSS>_<psg>/`.
  Berisi SEMUA yang ada di sidecar **plus** blok interpretasi sesar (`faults[]`)
  ber-`geometry.perDx` + `lifecycle`, **plus** blok top-level **`referenceGeom`**
  (garis ref horizontal + dinding pembatas + base + ketebalan model; koordinat robust).
  Ini yang dipakai untuk laporan.

> **Di mana data REFERENSI GEOMETRI di JSON commit:** (1) top-level `referenceGeom`
> `{refHorizonPts, limitWallPts, basePts, modelThicknessCm}` — sumber utama; (2) juga
> disalin di tiap `faults[].geometry` (header). Data TITIK NUKLEASI (`nucVerts`,
> `nucDistCm`, `nucDepthPx`, `nucDepthCm`) ada di **`rows[]`** (setiap baris DX) DAN di
> `faults[].geometry.perDx` (hanya F# yang sudah di-assign HW/FW di PAB5).

Semua angka pengukuran memakai **4 desimal**. Nilai kosong = JSON `null` (bekas `NaN`).

---

## 1. Konsep inti: geometri sesar itu PER-DX (bukan per-sesar)

Setiap **baris deskripsi (DX = satu titik pengamatan / POI)** punya **bidang sesarnya
sendiri**: bentuk (polyline `vertices`), **sudut** (`angleDeg`), dan **panjang**
(`lenCm`). Satu sesar (F#) = urutan beberapa DX pada frame berbeda.

**Lifecycle FSR** (Fault Surface Rupture) dilacak lewat POI:

| POI | Makna | FSR_length (`lenCm`) | `angleDeg` | `vertices` |
|-----|-------|----------------------|-----------|------------|
| `NUC-FSR` | FSR nukleasi (mulai) | **0** (otomatis) | `null` | `[]` |
| `PRP-FSR` | FSR mulai terbentuk (propagasi) | diukur (0 → panjang) | diukur | ada |
| `ACT-FSR` | FSR **aktif / maksimum** (boleh beberapa DX) | diukur | diukur | ada |
| `X-FS` | FSR berhenti aktif | **0** (otomatis) | `null` | `[]` |

> **Growth rate** = laju perubahan panjang antar-DX berurutan (per sesar):
> `growthRate[n] = (lenCm[n] − lenCm[n−1]) / (Δframe[n−1→n] × dtSec)`.
> DX pertama tiap sesar → `growthRate = null` (tak ada n−1).
> Karena `NUC-FSR` punya `lenCm=0`, growth `PRP-FSR` pertama dihitung relatif 0.

> **CATATAN MIGRASI:** nama lama `FS-max` → `ACT-FSR`, `FS-x` → `X-FS`. File lama
> otomatis dibaca dengan nama baru. Jangan lagi mengharapkan `FS-max`/`FS-x`.

> **WARISAN BENTUK (evolusi ACT-FSR):** bidang sesar aktif BEREVOLUSI antar-DX. Warisan
> HANYA berlaku antar **`ACT-FSR`**. Saat DX `ACT-FSR` baru ditambahkan, `vertices`-nya
> **di-copy dari `ACT-FSR` terdekat DI BAWAH** (frame lebih rendah, F# sama). Bila DX
> disisip di antara dua `ACT-FSR` lama, `ACT-FSR` **di atasnya** ikut ditimpa copy dari
> DX baru. `PRP-FSR` TIDAK menjadi sumber/tujuan warisan. Konsekuensi untuk CLCW: dua
> `ACT-FSR` berurutan bisa punya `vertices` IDENTIK (belum di-edit user) → normal;
> `growthRate` antar keduanya = 0.

---

## 2. Struktur `<exp>_desc.json` (sidecar)

```json
{
  "formatName": "PAB4 Description Table",
  "formatVersion": 2,
  "source": "P-CON-4cm-F.mat",
  "meta": {
    "basename": "P-CON-4cm-F",
    "refHorizonDeg": 1.5,           // sudut REFERENSI HORIZONTAL (koreksi kemiringan
                                    //   kamera, derajat). null = tak diset (pakai 0°).
                                    //   SEMUA angleDeg sudah RELATIF nilai ini.
    // --- REFERENSI GEOMETRI (koordinat robust) — SUMBER UTAMA = KOTAK MODEL 4-titik ---
    "modelBoxPts": [[120,100],[2900,110],[2910,900],[125,895]],
                                    //   4 titik sudut CLOCKWISE dari KIRI-ATAS:
                                    //   [KiAtas, KaAtas, KaBawah, KiBawah]. Menurunkan SEMUA ref:
                                    //   sisi KIRI = dinding pendorong (X0; datum jarak nukleasi),
                                    //   KANAN = dinding pembatas (Lpos; kalibrasi cmPerPx via L0),
                                    //   ATAS = ref horizontal (datum kedalaman), BAWAH = base.
    "refHorizonPts": [[10,300],[3000,340]],  // (fallback/manual) garis ref horizontal 2x2 px.
    "limitWallPts":  [],           // (fallback) dinding pembatas bila kotak TAK dipakai
    "indenterInitPts": [],         // (fallback) indenter/pendorong awal bila kotak TAK dipakai
    "basePts":       [],           // (fallback) base bila kotak TAK dipakai
    "modelThicknessCm": 4          // KETEBALAN model (cm; default 4) = tinggi base->permukaan (skala Y).
  },
  "rows": [ /* array baris DX — lihat §3 */ ],
  "faults": [ /* diisi saat Commit — lihat §4 */ ],
  "interpretation": {              // metadata garis PSG yang di-commit
    "psgId": "", "psgName": "", "producedAt": "",
    "nFrames": null, "strainTotalPct": null, "velMult": null
  }
}
```

### 3. Satu elemen `rows[]` (baris DX / titik pengamatan)

```json
{
  "psgId":   "psg1",          // id garis PSG pemilik (1 exp bisa >1 garis penampang)
  "fNum":    "F1",            // nomor sesar tampil (string, mis. "F1"). "" = tanpa sesar
  "frame":   35,              // nomor frame yang diamati (di AX main)
  "fTrx":    null,            // frame akhir transisi (khusus POI=TRX); else null
  "poi":     "PRP-FSR",       // titik lifecycle (lihat tabel §1)
  "actF":    3,               // # active fault: jumlah sesar aktif tampil di frame ini
  "isOost":  "1",             // 1 = in-sequence, 2 = out-of-sequence thrust
  "fsrDir":  "UP",            // arah pembentukan FSR: UP / DWN / both / SIM (— = kosong)
                              //   SIM = FSR terbentuk SIMULTAN (pasangan nucPos=ALL)
  "nucPos":  "FT",            // posisi nukleasi (hanya berarti saat POI=NUC-FSR):
                              //   T=Top · M=Mid · B=Bottom · FT=Fault-Tip · ALL=semua posisi
  "desc":    "FSR mulai terbentuk",   // deskripsi lisan (teks bebas)

  // --- GEOMETRI BIDANG SESAR per-DX ---
  "vertices": [[512,301],[566,336],[623,361]],  // polyline (Nx2) [x,y] PIXEL gambar
                                                //   AX main. [] bila tak diukur.
  "angleDeg": 28.5012,        // sudut/dip regresi vertex, RELATIF refHorizonDeg (°).
                              //   null bila tak diukur / POI ujung (NUC-FSR/X-FS).
  "lenCm":    2.1043,         // panjang polyline (cm). 0 utk NUC-FSR/X-FS; null bila
                              //   tak diukur pada POI ukur.

  // --- TITIK NUKLEASI (HANYA baris POI=NUC-FSR) ---
  // Input di PAB4 = GARIS 2-TITIK di AX main: vertex-1 = POSISI NUKLEASI;
  // vertex-2 = DINDING PENDORONG (user tarik ke sana; berubah tiap DX -> memungkinkan
  //            ukur dari sesar pertama). Dinding pendorong TIDAK disimpan sbg garis tetap.
  "nucVerts":    [[210,410],[205,405]],  // Nx2 [x,y] pixel; [1]=nukleasi, [2]=dinding pendorong.
  "nucDistCm":   0.1414,      // JARAK nukleasi -> DINDING PENDORONG = panjang garis (cm).
  "nucDepthPx":  282.3,       // KEDALAMAN tegak-lurus nukleasi ke garis ref horizontal (PIXEL).
  "nucDepthCm":  5.65,        // = nucDepthPx × cmPerPx (kalibrasi indenter).
  "nucDistF1Cm": null         // (usang; target diganti ke dinding pendorong -> null).
}
```

**Cara CLCW menghitung ulang (bila perlu verifikasi):**
- Panjang px = Σ `hypot(x[i+1]−x[i], y[i+1]−y[i])` sepanjang `vertices`.
- `lenCm = panjang_px × cmPerPx` (cmPerPx = `dxCm / lebarFrameSumbuX`; sudah dihitung
  PAB4, cukup baca `lenCm`).
- `angleDeg` = regresi least-squares vertex, dinormalkan (−90, 90], **dikurangi**
  `refHorizonDeg`. (Sudah dihitung; cukup baca.)

---

## 4. Blok `faults[]` (hanya di JSON hasil **Commit**)

Tiap sesar ber-HW pada garis PSG aktif menghasilkan satu objek. Field inti dari
interpretasi PAB5 (`hw/fw/netslip/poi/...`) **plus** dua blok tambahan PAB4:

```json
{
  "id": "F1", "angleDeg": 31.2044,       // angleDeg top-level = sudut DX terakhir
  "hw": { "values": [ ... ], "units": "px/frame" },
  "fw": { "values": [ ... ], "units": "px/frame" },
  "netslip": [ ... ],                    // net-slip HW−FW (px/frame)
  "poi": { ... },                        // POI ber-strain% (dari PAB5)

  // === GEOMETRI per-DX (LENGKAP 2026-07-17) ===
  "geometry": {
    "units": { "length": "cm", "angle": "deg", "rate": "cm/s" },
    "refHorizonDeg": 1.5,
    "refHorizonPts": [[10,300],[3000,340]],  // POSISI garis ref horizontal (datum kedalaman)
    "limitWallPts":  [[2900,0],[2905,900]],  // dinding pembatas (batas model)
    "basePts":       [[0,850],[3000,850]],   // referensi base (dasar model)
    "modelThicknessCm": 4,   // ketebalan model (cm)
    "perDx": [               // 1 item per DX (baris DESKRIPSI) ber-geometri/taper/catatan
      {
        // --- atribut lisan / POI (semua yang dicatat di tabel DESC) ---
        "frame": 35,
        "poi": "PRP-FSR",
        "actF": 3,                       // # sesar aktif teramati di DX ini (null bila kosong)
        "isOost": "1",                   // IS/OOST (in-sequence / out-of-sequence)
        "nucPos": "FT",                  // posisi nukleasi: T/M/B/FT (kosong bila —)
        "fsrDir": "UP",                  // arah pembentukan FSR: UP/DWN/both
        "fTrx": null,                    // frame akhir transisi (POI=TRX); null bila -
        "desc": "catatan lisan DX",      // deskripsi teks bebas
        // --- BIDANG SESAR (polyline yang diukur, Ctrl+Q) ---
        "angleDeg": 28.5012,             // sudut/dip regresi vertex, RELATIF refHorizonDeg
        "lenCm": 2.1043,                 // panjang polyline sesar (cm)
        "growthRate": 0.0068,            // (lenCm−lenCm[n−1])/(Δframe·dt); null utk DX pertama
        "vertices": [[512,301],[566,336],[623,361]],   // Nx2 [x,y] pixel; [] bila tak digambar
        // --- TAPER (kemiringan TOPOGRAFI permukaan, Ctrl+W) ---
        "taperDeg": 12.5000,             // sudut taper relatif refHorizonDeg; null bila tak diukur
        "taperLenCm": 1.8021,            // panjang garis taper (cm); null bila tak ada
        "taperVertices": [[400,250],[480,250]]         // Nx2 [x,y] pixel garis taper; [] bila tak ada
      }
    ]
  },

  // === LIFECYCLE (timeline fase dari POI) ===
  "lifecycle": [ { "phase": "...", "frameStart": ..., "frameEnd": ...,
                   "strainStartPct": ..., "rate": ..., "rateType": "..." }, ... ]
}
```

> `geometry.perDx` kini memuat **SETIAP DX yang punya bidang sesar (vertices≥2) ATAU
> taper (taperDeg) ATAU catatan berarti (POI≠</blank>, atau desc/nucPos/fsrDir terisi)** —
> jadi SELURUH informasi tabel DESC ada di sini per-DX (bidang sesar + taper + atribut
> lisan). DX benar-benar kosong dilewati. `vertices`/`taperVertices` = `[]` bila komponen
> itu tak digambar. NUC-FSR/X-FS: `lenCm=0`, `vertices=[]` (ujung siklus), tapi tetap
> muncul bila ber-POI (menandai batas lifecycle).
>
> **CATATAN**: blok `perDx` HANYA dibangun utk sesar yang sudah di-assign HW/FW di PAB5.
> Sesar yang baru dideskripsikan di PAB4 (belum ber-HW) tetap terekam LENGKAP di `rows[]`
> mentah (lihat bagian atas) — `rows[]` = sumber kebenaran semua field, selalu lengkap.

---

## 5. Resep parse untuk CLCW (langkah demi langkah)

1. **Baca sidecar** `<exp>_desc.json`. Ambil `meta.refHorizonDeg` (koreksi kamera).
2. **Kelompokkan `rows[]` per `fNum`** (per sesar), lalu **urutkan per `frame`** menaik.
3. Untuk tiap sesar, telusuri lifecycle dari POI:
   - `NUC-FSR` (frame awal, FSR_length=0) → `PRP-FSR`/`ACT-FSR` (ukur panjang & sudut)
     → `X-FS` (frame akhir, FSR_length=0).
   - **Rentang aktivitas FSR** = frame `NUC-FSR` pertama … `X-FS` terakhir (per sesar).
4. **Kurva pertumbuhan panjang FSR**: plot `lenCm` vs `frame` untuk DX ber-`vertices`.
   Growth rate tiap segmen = `growthRate` (sudah dihitung) atau hitung sendiri
   `(lenCm[n]−lenCm[n−1])/(Δframe·dtSec)`.
5. **Sudut sesar tiap POI**: baca `angleDeg` (sudah relatif horizontal terkoreksi).
6. Untuk laporan lengkap gunakan JSON **Commit** (`faults[].geometry.perDx`) yang sudah
   memaketkan geometri per-DX + growth + lifecycle per sesar.

### Pseudo-kode
```python
import json
doc = json.load(open("P-CON-4cm-F_desc.json"))
ref = doc["meta"].get("refHorizonDeg")            # koreksi kamera (bisa null)

faults = {}
for r in doc["rows"]:
    faults.setdefault(r["fNum"], []).append(r)

for fnum, rows in faults.items():
    rows = sorted(rows, key=lambda r: (r["frame"] is None, r["frame"]))
    # rentang aktivitas FSR
    nuc = [r["frame"] for r in rows if r["poi"] == "NUC-FSR"]
    xfs = [r["frame"] for r in rows if r["poi"] == "X-FS"]
    fsr_start = min(nuc) if nuc else None
    fsr_end   = max(xfs) if xfs else None
    # kurva panjang FSR (hanya DX yang diukur)
    measured = [r for r in rows if r.get("lenCm") not in (None, 0) and r["vertices"]]
    prev = None
    for r in rows:                      # growth relatif DX sebelumnya (per sesar)
        if prev and r.get("lenCm") is not None and prev.get("lenCm") is not None \
           and r["frame"] and prev["frame"]:
            dframe = abs(r["frame"] - prev["frame"])
            growth = (r["lenCm"] - prev["lenCm"]) / (dframe * DT)  # DT dari kalibrasi
        prev = r
```

---

## 6. Ringkas perubahan vs versi lama (untuk CLCW yang punya parser lama)

| Lama | Baru |
|------|------|
| POI `FS-max` | **`ACT-FSR`** (FSR aktif/maksimum) |
| POI `FS-x` | **`X-FS`** (FSR berhenti) |
| geometri per-sesar (`verticesNuc`/`verticesDie`, `lenNucCm`/`lenDieCm`, sidecar `_faultgeom.json`) | **geometri per-DX** di `rows[].vertices/angleDeg/lenCm` + `faults[].geometry.perDx` |
| kolom `F TRX` di tabel | field `fTrx` tetap ada di JSON (kolom UI dibuang) |
| fill hitam = FS-max→FS-max berpasangan | rentang **NUC-FSR pertama → X-FS terakhir** per sesar |

> `_faultgeom.json` **dipensiunkan** — jangan dibaca lagi; semua geometri kini di
> `_desc.json`.
