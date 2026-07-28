# GRAIN4 — Ekosistem Eksplorasi, Jurnal & Analisis Sesar (Step 4)

**Status:** ✅ TERIMPLEMENTASI (2026-06-25). GRAIN4A + GRAIN4B + 8 engine (`+pivcore/+pot/{psgId,netslip,snapPoints,hwLabel}`, `+pivcore/+io/{grain4PotData,grain4Notes}`, `+pivui/{grain4Shell,grain4Annot}`) + 3 test (`test_grain4_engines`, `test_smoke_grain4a`, `test_smoke_grain4b`) — SEMUA LULUS R2025b; gerbang `run_rename_verify` bersih (66 file). Disusun 2026-06-25 (revisi 5 — **journaling POT terikat ke garis PSG ber-ID; 1 exp bisa banyak garis POT**; net-slip-tak-lengkap sbg warga kelas-satu; jurnal tingkat-folder; trigger ekspor JSON eksplisit; kejujuran manfaat-modular). Hash provenance & penanda-penulis = ditunda/diabaikan (bukan pokok).
**Kontrak induk:** memori `grainsa-pipeline-architecture` → "Step 4 = Komentar & Analisis".
**Patuh:** R2025b · tema terang · file versi baru (GRAIN3/GRAIN3a utuh) · governance `GRAIN/docs/FILE_GOVERNANCE.md`.

---

## 0. Istilah (acuan penamaan objek)

- **Package / paket** = folder `+nama` (mis. `+pivcore`). Dipanggil `pivcore.io.grain4Notes(...)`.
- **Sub-package / namespace** = paket dalam paket (`+pivcore/+pot`, `+pivcore/+io`, …).
- **Engine** = function/class berisi logika/perhitungan, hidup DI PAKET. Bisa di-test & reuse.
- **GUI wrapper** = file `GRAIN4*.m` di root — HANYA gambar panel/tombol/callback + panggil engine. **Tipis.**
- **Reuse** = memakai-ulang engine yang sudah ada (bukan menulis ulang di GUI).

**Prinsip emas modul ini:** *tidak ada perhitungan di dalam file `GRAIN4*.m`.* Semua hal yang menghitung/membaca/menulis data = engine di `+pivcore`. File GUI hanya merangkai.

**Soal jumlah baris (keputusan peneliti):** TAK masalah bila ribuan baris asalkan tidak "berat" dikerjakan — modular = supaya tiap potong wajar ditulis & dirawat. **Strategi model:** tulis fitur baru pakai **Opus Extra High**; debugging kecil pakai **Opus Low**. Modularitas membantu di sini: bug terisolasi di satu engine/file → bisa diperbaiki dengan model murah tanpa memuat seluruh ekosistem.

---

## 1. Alur & lingkup

```
GRAIN2 (Step 2) → MAT PIV → [ EKOSISTEM GRAIN4 ] → sidecar teks (jurnal + kuantitatif)
```
GRAIN3 (montase/MP4) & GRAIN3a (assign) **TIDAK terlibat** — tak ada rujukan, tak ada dependensi.

**Ekosistem GRAIN4 = dua GUI wrapper tipis, berbagi satu MAT PIV + satu pasang sidecar:**

| Modul | Peran | Isi |
|---|---|---|
| **GRAIN4A.m** | Eksplorasi + Jurnal + Kanal Claude | axMain (vel/shear+GS+glyph+slider) · axPOT (kurva POT on-the-fly) · garis PSG draggable · alat anotasi (garis/titik/ukur) · **panel catatan multi-level** · **tombol kanal Claude** |
| **GRAIN4B.m** | Labeling HW + Analisis sesar | klik kurva → tandai **HW-1/HW-2/FFW di tempat** · tandai **Start/NUC/FSR/END** (snap-to-curve) · **net-slip** HWₙ−HWₙ₊₁ + area + dNet · tabel per-HW |

Navigasi muter: GRAIN4A ⇄ GRAIN4B berbagi `<base>.mat`. (Slot **GRAIN4C** dicadangkan; **launcher utama** dibuat BELAKANGAN setelah 4A/4B jadi.)

> **Net-slip butuh kelengkapan label — perlakukan kasus belum-lengkap sbg WARGA KELAS-SATU.** Net-slip = HWₙ − HWₙ₊₁ (sesar terakhir vs FFW) → minimal **2 HW + 1 FFW** ter-label benar. Banyak eksperimen TAK lengkap (1 HW, atau FFW belum ditandai). GRAIN4B HARUS: (a) tabel per-HW + Start/NUC/FSR/END tetap **berguna penuh** walau net-slip tak bisa dihitung; (b) status eksplisit "Net-slip: butuh ≥2 HW + FFW (sekarang: N HW, FFW=ada/tidak)"; (c) JANGAN terasa rusak/blank saat label belum lengkap. Net-slip = bonus saat label lengkap, bukan prasyarat agar modul jalan.

## 2. Keputusan desain (terkonfirmasi peneliti 2026-06-25)

| Aspek | Keputusan |
|---|---|
| Sumber data | **Langsung MAT PIV dari GRAIN2**; GRAIN3/GRAIN3a tak dipakai |
| Labeling HW | **Di dalam GRAIN4B langsung** (ringan), bukan via GRAIN3a — TAPI **wajib bisa meng-import `_autopot.mat` GRAIN3a sebagai seed** bila ada (lihat §3d) agar tak ada dua kebenaran berbeda |
| Kanal agentik | **Sidecar Markdown + JSON** terpisah (lihat §3); bukan di `.mat` biner |
| Sidecar | **File GRAIN4 sendiri**; TIDAK menyentuh `_autopot.mat` milik GRAIN3a |
| Granularitas catatan | Per-eksperimen + Per-kurva POT + Per-frame |
| Net-slip → Claude | Ikut ke `_potdata.json` (titik, area, dNet) |
| Struktur GUI | **GRAIN4A + GRAIN4B** (dua file tipis), engine di paket |
| Launcher utama | Ya, **nanti** setelah 4A/4B jadi |

---

## 3. Arsitektur file — kanal dua arah (Claude ⇄ peneliti)

Untuk tiap MAT PIV `<base>.mat`, ekosistem GRAIN4 mengelola **dua sidecar teks** di folder sama:

```
PIV_2026-06-25/
  _GRAIN4_journal.md       <- JURNAL SERI/FOLDER: catatan & tren lintas-eksperimen (1 per folder)
  TKS-5_cm-1.mat         <- MAT PIV (biner, TIDAK disentuh GRAIN4)
  TKS-5_cm-1_notes.md    <- JURNAL per-exp: catatan peneliti + balasan Claude (manusia-readable)
  TKS-5_cm-1_potdata.json<- KUANTITATIF per-exp: kurva POT + label HW + titik + net-slip
  TKS-5_cm-1_autopot.mat <- (milik GRAIN3a, bila ada — GRAIN4 TAK menulis, TAPI BOLEH membaca sbg seed)
  TKS-5_cm-2.mat … dst   <- folder nyata berisi BANYAK exp (TKS-5_cm-1..8)
```

> **Dua tingkat jurnal.** Folder nyata berisi banyak eksperimen (mis. `TKS-5_cm-1..8`). `_GRAIN4_journal.md` (1 per folder) = catatan **lintas-eksperimen/seri** (mis. "tren dNet naik exp-1→exp-8, kesimpulan seri"). `<base>_notes.md` (1 per exp) = catatan per-eksperimen. Claude membaca KEDUANYA: yang per-exp untuk detail, yang seri untuk pola. GRAIN4A menulis ke seksi seri lewat tombol "Catatan seri…".

> **Catatan duplikasi:** `_potdata.json` sebagian menampung info yang juga ada di `_autopot.mat` (kurva, label HW, garis PSG). Ini sengaja — `.json` adalah kebenaran milik GRAIN4 yang mesin-readable & lintas-modul. Untuk mencegah dua-kebenaran, lihat protokol seed §3d.

### 3a. `<base>_notes.md` — jurnal manusia ⇄ Claude
Markdown berseksi, **append-only** (tak ada konflik tulis). Footer cursor `<!-- grain4:cursor lastWriteByUser=… lastReadByClaude=… -->` sebagai antrean. Penanda penulis `[USER]`/`[CLAUDE]` (identitas akun tak penting — bisa ISMA atau tegar; tak di-hardcode, ambil dari config/`getenv` bila ada).

**KUNCI (poin peneliti): journaling POT terikat ke GARIS PSG, dan 1 eksperimen bisa punya BANYAK garis POT.** Observasi POT selalu dilakukan pada **satu garis PSG yang fix** — pindah garis = observasi lain. Maka seksi jurnal:
- `## Eksperimen (umum)` — kesan/kesimpulan global exp.
- `## Garis POT: <psgId>` — **unit observasi POT utama**. Tiap garis PSG punya **ID stabil** (`psgId`, lihat §3b) + ringkasan geometri garis (p1/p2/frac). Catatan kurva di garis ITU ditulis di sini.
  - `### Kurva: <label> @<psgId>` — catatan untuk kurva tertentu **pada garis itu** (label kurva hanya bermakna dalam konteks satu garis).
- `## Frame: <n>` — catatan menempel frame (lintas-garis; mis. "frame 42 ada artefak").

> **Kenapa per-garis:** kurva POT = hasil sampling sepanjang garis PSG. Geser garis → kurva berubah → indeks/label kurva tak lagi cocok. Mengikat catatan ke `psgId` membuat round-trip stabil: buka lagi exp → garis yang sama → kurva sama → catatan nyambung. Peneliti boleh menyimpan **beberapa garis** per exp (mis. garis di 70%, garis di lokasi anchor) — tiap garis = sub-observasi tersendiri.

### 3b. `<base>_potdata.json` — kanal kuantitatif
**Satuan & tanda WAJIB eksplisit** (output ilmiah ke Claude tak boleh ambigu):
- `units`: ambil dari `pivcore.pot.units` (sudah ada). Default POT = px/frame; bila ada dt EXIF → px/s. Field `units` & `sampleRate` ikut ditulis.
- `signConvention`: `"signed"` atau `"absolute"` — cermin toggle drift GRAIN (SIGNED/ABSOLUT). Net-slip mengikuti konvensi ini.

**Struktur berpusat pada GARIS PSG (poin 6).** Akar JSON punya array `psgLines[]`; tiap garis ber-`id` stabil dan MEMBAWA kurva + net-slip + anotasinya sendiri. Satu exp = banyak garis. `id` dibuat dari geometri garis (mis. `frac=0.70` → `"frac070"`, atau hash pendek p1/p2) supaya garis yang sama dibuka ulang menghasilkan `id` sama → catatan `_notes.md` nyambung.

```json
{ "source":"TKS-5_cm-1.mat",
  "meta":{"frames":106,"basename":"TKS-5_cm-1"},
  "units":"px/frame", "sampleRate":null, "signConvention":"signed",
  "indenter": [...],
  "psgLines": [
    { "id":"frac070", "p1":[0,645], "p2":[3000,645], "frac":0.70, "spacingPx":3,
      "curves": [ {"label":"HW-1","origin":[x,y],"values":[…]}, … ],
      "netslip": [ {"hw":1,"partner":"HW-2","start":5,"nuc":12,"fsr":18,"end":40,
                    "area":15.1,"dNet":2.3,"units":"px/frame","values":[…]} ],
      "annotations": {"lines":[…],"points":[…],"measures":[…]} },
    { "id":"anchor1", "p1":[…], "p2":[…], "frac":null, "curves":[…], "netslip":[…],
      "annotations":{…} }
  ] }
```
> `dNet` = selisih net (HWₙ − partner) pada konvensi tanda terpilih; `area` = integral selisih `start`..`end`. Definisi + satuan di docstring `pivcore.pot.netslip`. (Hash provenance file besar = DITUNDA — bukan pokok; sementara cukup `basename`+`frames`.)

### 3c. Protokol antrean Claude
1. Peneliti tulis di GRAIN4A → engine append `[USER …]` + set `lastWriteByUser`.
2. `_potdata.json` di-tulis **HANYA pada aksi eksplisit**, BUKAN tiap perubahan: (a) tombol **"Export untuk Claude"**, (b) saat **pindah modul** (4A→4B), (c) saat **tutup** modul. Geser garis PSG / scrub frame / pilih kurva TIDAK menulis disk (kurva disampel on-the-fly, JSON file besar — menulis tiap event ROI = boros I/O). Penulisan **WAJIB atomic**: tulis `<base>_potdata.json.tmp` lalu `movefile` ke nama final.
3. Peneliti minta sesi Claude Code: "baca jurnal GRAIN4 yang baru". Claude pindai `PIV_*/**/*_notes.md` + `_GRAIN4_journal.md`, baca yang `lastWriteByUser > lastReadByClaude` + `_potdata.json` pasangannya, **append** `[CLAUDE …]`, set `lastReadByClaude`.
4. Tombol GUI "Muat balasan Claude" → render entri `[CLAUDE]` terbaru.

> **Realitas kanal (jangan over-sold):** ini IPC **filesystem berbasis polling manual** — MATLAB TIDAK memanggil API; Claude membaca berkas hanya saat peneliti memintanya di sesi terpisah. `_notes.md` append-only (anti-konflik). `_potdata.json` ditulis-ulang utuh pada aksi eksplisit → diamankan oleh atomic write (langkah 2), bukan append.

### 3d. Seed label dari GRAIN3a (anti dua-kebenaran)
Saat GRAIN4B membuka `<base>.mat`, bila `<base>_autopot.mat` ada **dan** garis PSG yang dipilih belum punya label HW di `_potdata.json`:
- engine `pivcore.io.autopotSession` (sudah ada) dibaca **read-only** → garis PSG + label HW/F/F0/FFW dari GRAIN3a dipakai sebagai **seed** untuk garis yang cocok geometrinya (`psgId` sama).
- Peneliti boleh override di GRAIN4B; sejak override, `_potdata.json` jadi otoritatif untuk GRAIN4. GRAIN4 **tetap tak menulis** `_autopot.mat`.
- Bila keduanya ada & berbeda → status bar memperingatkan "label GRAIN4 ≠ GRAIN3a" (bukan merge diam-diam).

---

## 4. MODULARITAS — peta reuse vs ekstrak (INTI rencana)

### 4a. Engine yang SUDAH ADA → tinggal reuse (TANPA tulis ulang)
- `pivcore.data.{buildDataset, safeFrame, frameCount, resolveScalar, computeShearRate, nodeSpacing}` — muat & olah dataset.
- `pivcore.pot.{records, labels, step1Collect.collectAlongLine, vscale}` — sampling POT on-the-fly (IDENTIK PIVTerry Step 1).
- `pivcore.io.{step1Session, autopotSession}` — termasuk **`saveStep4Points`/`loadStep4Points` yang SUDAH jadi engine** (dipakai 4B bila perlu kompat; sidecar utama GRAIN4 tetap json).
- `pivcore.util.{velColormap(JET), grayCLAHE, drawGlyphs, robustCLim, snapClim, climDefaults, glyphDefaults, potDefaults, baseName}` — render axMain.
- `pivcore.montage.*` — bila perlu ekspor gambar dari GRAIN4A.

### 4b. Engine BARU yang harus DIEKSTRAK ke paket (jangan ditaruh di GUI)
| Engine baru | Namespace/paket | Tugas | Asal |
|---|---|---|---|
| `pivcore.io.grain4Notes` | `+pivcore/+io` | `notesPath/appendEntry(level,key)/loadEntries/pendingForClaude/setCursor` — `level`∈{exp, psg, curve@psg, frame}; + jurnal seri `_GRAIN4_journal.md` | BARU |
| `pivcore.io.grain4PotData` | `+pivcore/+io` | `dataPath/write(atomic)/read` — struktur **`psgLines[]` ber-id** (banyak garis/exp) | BARU |
| `pivcore.pot.psgId` | `+pivcore/+pot` | ID garis PSG STABIL dari geometri (frac → `"frac070"`, atau hash pendek p1/p2) → catatan nyambung saat exp dibuka ulang | BARU (kecil) |
| `pivcore.pot.netslip` | `+pivcore/+pot` | `repVec` (kurva representatif), `netslipVec` (HWₙ−HWₙ₊₁/FFW), `area`, `dNet` | **RE-IMPLEMENTASI clean-room** (baca pola di `tabStep4`, tulis ulang sbg fungsi murni) |
| `pivcore.pot.snapPoints` | `+pivcore/+pot` | snap frame→kurva, normalisasi struct titik Start/NUC/FSR/END | RE-IMPLEMENTASI clean-room dari pola `tabStep4` |
| `pivcore.pot.hwLabel` | `+pivcore/+pot` | labeling HW/F/FFW ringan di-tempat (parse/warna/daftar HW) | sebagian reuse `pivcore.pot.labels` + tipis baru |
| `pivui.grain4Annot` | `+pivui` (top-level) | gambar/serialisasi anotasi garis/titik/ukur (ROI) | BARU |

> **Penting soal `tabStep4`:** file `tabStep4.m` (1327 baris, **GUI tab**) ada di `_reference/PIVTerry/` yang **read-only & TERLARANG dipanggil lintas-folder** (CLAUDE.md). Jadi ini **bukan "ekstrak/pindah"** yang bisa di-diff otomatis — melainkan **re-implementasi clean-room**: baca polanya, tulis fungsi murni di `+pivcore/+pot`, lalu validasi terhadap **angka golden yang dipanen manual** dari eksperimen yang diketahui (mis. `5_cm_(S2)-1.mat`). Unit test memakai golden itu, BUKAN memanggil `tabStep4`.

> **Lokasi `+pivui` (KOREKSI):** `+pivui` adalah **paket top-level** `pivcore_lib/+pivui/` → namespace `pivui.*` (mis. `pivui.makePsgLineROI`, `pivui.forceLightTheme`, `pivui.setStatus` — semua sudah ada). JANGAN taruh `grain4Shell`/`grain4Annot` di bawah `+pivcore/+pivui/` (itu paket bayangan `pivcore.pivui.*` yang tak cocok dengan panggilan `pivui.*`).

### 4c. Helper GUI bersama (agar 4A & 4B tak duplikasi kode panel)
Paket `pivui` (top-level) reuse yang **sudah ada**: `forceLightTheme`, `lockAxInteractions`, `makePsgLineROI`, `setStatus`, `minimizeForDialog`/`restoreAfterDialog`, `currentLineFromROI`, `potStyle`, `applyRowStyles`, `selectTableRow`, `clearFigModes`. Tambah baru **`pivui.grain4Shell`** (kerangka axMain+axPOT+tabel+panel kanan yang dipakai BERSAMA 4A & 4B → keduanya hanya isi panel kanan masing-masing). Ini yang paling memangkas baris.

**Estimasi baris — patokan jujur, BUKAN strawman "7000".** Modul lama (GRAIN0–GRAIN3a) **sudah** pakai engine pivcore dan tetap **1423–1699 baris**. Yang paling mirip, **GRAIN3 (preview axMain+axPOT+GS+slider+POT-auto-PSG+montase, read-only) = 1546 baris**. GRAIN4A melakukan itu **plus** PSG draggable + 3 alat anotasi ROI + panel catatan multi-level + tombol kanal Claude. Maka estimasi realistis (dengan `grain4Shell` menyerap kerangka bersama):

| Berkas | Estimasi |
|---|---|
| `pivui.grain4Shell` (kerangka bersama) | ~500–700 |
| `GRAIN4A.m` | ~900–1200 |
| `GRAIN4B.m` | ~800–1000 |
| **Total ekosistem** | **~2200–2900** |

Sehat & modular — tapi jangan jual angka per-file "700–900" yang lebih kecil dari GRAIN3 padahal fungsinya lebih banyak.

> **Kejujuran manfaat-modular.** Total ~2200–2900 baris ≈ sebanding satu file monolitik — **memecah tidak menghemat total baris**. Manfaat sebenarnya = **keterbacaan & isolasi**: tiap file ≤~1200 baris bisa dibuka/dipahami/di-debug terpisah, engine bisa di-test sendiri, satu modul berubah tanpa menyentuh yang lain. Itulah alasan memecah — bukan "lebih sedikit kode".

---

## 5. Berkas yang dibuat/diubah

| Berkas | Aksi |
|---|---|
| `GRAIN/GRAIN4A.m` | **BARU** — GUI eksplorasi + jurnal + kanal Claude (tipis) |
| `GRAIN/GRAIN4B.m` | **BARU** — GUI labeling HW + net-slip (tipis) |
| `GRAIN/pivcore_lib/+pivcore/+io/grain4Notes.m` | **BARU** — engine `_notes.md` (per-exp) + `_GRAIN4_journal.md` (seri); penanda penulis netral-akun |
| `GRAIN/pivcore_lib/+pivcore/+io/grain4PotData.m` | **BARU** — engine `_potdata.json` |
| `GRAIN/pivcore_lib/+pivcore/+pot/netslip.m` | **BARU** — engine net-slip (ekstrak dari tabStep4) |
| `GRAIN/pivcore_lib/+pivcore/+pot/snapPoints.m` | **BARU** — engine snap titik |
| `GRAIN/pivcore_lib/+pivcore/+pot/hwLabel.m` | **BARU** — labeling HW ringan |
| `GRAIN/pivcore_lib/+pivcore/+pot/psgId.m` | **BARU** — ID garis PSG stabil (poin 6) |
| `GRAIN/pivcore_lib/+pivui/grain4Shell.m` | **BARU** — kerangka GUI bersama 4A/4B (namespace `pivui.*`, BUKAN `+pivcore/+pivui`) |
| `GRAIN/pivcore_lib/+pivui/grain4Annot.m` | **BARU** — anotasi garis/titik/ukur (namespace `pivui.*`) |
| `GRAIN/tests/test_smoke_grain4a.m`, `test_smoke_grain4b.m` | **BARU** — smoke per modul |
| `GRAIN/tests/test_grain4_engines.m` | **BARU** — unit engine (netslip/notes/potdata round-trip) |
| `GRAIN/GRAIN3.m`, `GRAIN/GRAIN3a.m` | **TIDAK disentuh** |

Governance: entry `GRAIN4A/4B` di root; engine di paket; test di `tests/` (bootstrap dua-addpath). Jalankan gerbang `run_rename_verify` setelah selesai.

---

## 6. Langkah implementasi (engine dulu, GUI belakangan)

0. **`pivcore.pot.psgId`** (engine kecil) + unit test: garis sama → id sama; garis beda → id beda.
1. **Engine I/O sidecar** `grain4Notes` + `grain4PotData` (struktur `psgLines[]` ber-id) + unit round-trip (`test_grain4_engines`): tulis 2 garis berbeda + catatan masing-masing → baca ulang → `psgId` & catatan nyambung ke garis yang benar.
2. **Re-implementasi clean-room `netslip` + `snapPoints`** di `+pivcore/+pot` (baca pola `tabStep4`, JANGAN panggil lintas-folder) + unit test memakai **angka golden yang dipanen manual** dari `5_cm_(S2)-1.mat` (bukan diff terhadap `tabStep4`).
3. **`hwLabel`** (labeling ringan) + `pivui.grain4Shell` (kerangka bersama) + `pivui.grain4Annot`.
4. **GRAIN4A.m** — rakit shell + axMain/axPOT (reuse engine) + **manajemen banyak garis PSG**: simpan garis aktif (+ `psgId`), daftar garis tersimpan per exp, pilih/aktifkan/tambah/hapus garis → kurva & catatan ikut garis terpilih + panel catatan (per exp / per garis / per kurva@garis / per frame) + tombol kanal Claude + "Export untuk Claude". Smoke `test_smoke_grain4a` atas `5_cm_(S2)-1.mat`.
5. **GRAIN4B.m** — rakit shell + **seed label dari `_autopot.mat` GRAIN3a bila ada** (§3d, read-only) + labeling HW + Start/NUC/FSR/END (snap) + net-slip + tabel. **Uji jalur label-belum-lengkap**: 1 HW / tanpa FFW → tabel + titik tetap berfungsi, status "Net-slip: butuh ≥2 HW + FFW", modul tak blank. Smoke `test_smoke_grain4b`.
6. **Round-trip lintas-modul**: tulis di 4A → buka 4B → label+titik → balik 4A → catatan & data konsisten; sidecar dibaca ulang benar; **write `_potdata.json` terbukti atomic** (sisakan `.tmp` saat diinterupsi tak merusak file final).
7. **Simulasi Claude**: append `[CLAUDE]` ke `_notes.md` di luar GUI → "Muat balasan" di 4A merender.
8. Gerbang `run_rename_verify` + screenshot terang. Smoke jalan **R2025b `-batch`** (jangan R2026a); pastikan `grain4Shell` tak nge-block menunggu `uifigure`.
9. Memori `grain-step4-ecosystem` + pointer `MEMORY.md`.
10. (Lanjutan) **launcher utama** `GRAIN.m` tipis: tombol Step 1/2/3/4A/4B.

## 7. Risiko & mitigasi
- **GUI menggemuk lagi** → mitigasi: kerangka `grain4Shell` bersama + larangan logika di file GUI; patokan jujur GRAIN4A ≤ ~1200, GRAIN4B ≤ ~1000 (lihat §4c), bukan klaim ≤900.
- **netslip clean-room menyimpang dari pola PIVTerry** → unit test pakai **angka golden manual** dari `5_cm_(S2)-1.mat` (tak bisa diff `tabStep4` karena read-only + GUI).
- **Dua kebenaran label HW (GRAIN4B vs GRAIN3a)** → seed read-only dari `_autopot.mat` (§3d) + peringatan status bar bila beda; GRAIN4 tak pernah menulis `_autopot.mat`.
- **`psgId` tak stabil → catatan POT putus saat exp dibuka ulang** → `psgId` dari geometri garis (frac/hash p1-p2) diuji round-trip (langkah 0); toleransi pembulatan koordinat ditetapkan di `pivcore.pot.psgId`. Ini risiko PALING kritis untuk poin-6.
- **Banyak garis PSG membingungkan / catatan ketukar antar-garis** → tiap catatan & kurva DIBAWA di bawah `psgLines[].id`; GUI selalu tampilkan garis aktif + `psgId`-nya; daftar garis tersimpan jelas.
- **Konflik/korup tulis sidecar** → `_notes.md` append-only + cursor; `_potdata.json` **atomic write** (`.tmp`→`movefile`).
- **Net-slip tak bisa dihitung saat label belum lengkap** → kasus belum-lengkap = warga kelas-satu (§1): tabel + Start/NUC/FSR/END tetap jalan, status eksplisit, tak blank. Net-slip = bonus saat ≥2 HW + FFW.
- **I/O berlebihan menulis `_potdata.json` file besar** → tulis HANYA via tombol "Export untuk Claude" / pindah-modul / tutup; geser PSG & scrub tak menulis disk (§3c).
- **Scope creep / rilis berat** → rilis-1: alat anotasi garis/titik/ukur saja; dahulukan engine sidecar + GRAIN4B (net-slip = payload ilmiah), kanal Claude & render balasan boleh menyusul sebagai 4A.1.
