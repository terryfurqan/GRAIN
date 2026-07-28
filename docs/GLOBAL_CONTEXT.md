# GLOBAL CONTEXT — **GRAIN** (PIVlab Automasi Batch)

> Repo ini **didedikasikan untuk GRAIN**. Satu aplikasi single-app modular untuk
> analisis PIV deformasi tanah granular: dari foto mentah → arsip → analisis →
> produksi → interpretasi. Folder lain (`_reference/`) hanya **inspirasi/referensi**.
> Dibuat 2026-06-22 · ditata-ulang & difokuskan 2026-06-25.

---

## ⚠️ ATURAN GLOBAL
- **SELALU MATLAB R2025b** (`/Applications/MATLAB_R2025b.app`). JANGAN R2026a
  (`-batch` hang & bug ambil-ROI saat startup).
- Tema GUI **terang dipaksa**; jendela utama **minimize saat dialog berkas**, restore sesudah.
- Engine ilmiah modular **dipakai ulang — jangan duplikasi logika ilmiah**.
- `pab_sa_setup` menentukan root secara **relatif** (`mfilename('fullpath')`) →
  rename folder aman; tak ada hardcode path.

---

## TATA LETAK REPO
```
Automasi PIV LAB/
  GRAIN/             ← FOKUS KERJA. Semua pengembangan di sini.
  _reference/      ← INSPIRASI saja, JANGAN dikembangkan:
    PIVTerry/        prototipe analisis/POT (sumber pola axMain+axPOT, step2 note-taking)
    PIVprep_V2/      cikal-bakal pipeline V1–V5 (kekusutan lama yang GRAIN gantikan)
  RAW/ , "5 cm-1"/ ← DATA (gitignored, JANGAN di-commit, JANGAN dipindah)
```
**Aturan referensi:** kode di `_reference/` boleh **dibaca untuk inspirasi**
(pola GUI, algoritma, ide). Tapi GRAIN adalah satu-satunya yang dikembangkan;
jangan menambah ketergantungan baru ke `_reference/`. Bila ada logika berguna di
sana, **salin/adaptasi ke dalam paket GRAIN**, bukan memanggil lintas-folder.

---

## ARSITEKTUR WORKFLOW (desain kanonik)
Motivasi inti: **rapikan manajemen data → 1 eksperimen = 1 berkas**.
Lihat dokumen visual: [`ALUR_KERJA.html`](ALUR_KERJA.html).

Jalur produksi sehari-hari: **JPEG → MAT PREP → MAT PIV**.

| Step | Peran | Masukan | Keluaran |
|------|-------|---------|----------|
| **0** | Validasi frame (QPIV) — tandai frame bermasalah | JPEG | flag exclude/skip (non-destruktif) + setelan OVL/NOVL & skip |
| **1** | Stabilisasi: crop (Mode 0/1) + anchor jitter | JPEG (+flag) | **MAT PREP** (foto+EXIF+jitter+crop+riwayat+flag) |
| **2** | Analisis PIV: preview + batch | MAT PREP | **MAT PIV** (paket + GS + data gerak) |
| **3** | Produksi | MAT PIV | MP4 · Image Sequence · Montase |
| **4** | Komentar & analisis *(belum dibuat)* | MAT PIV | catatan deskriptif + kuantitatif (di dalam MAT PIV) |

**Prinsip kunci:**
- **Step 0 = penyaring KASAR berbantuan manusia** — deteksi pergeseran besar /
  frame tak-bergerak (mis. MaxIndentor 4→0/2/3). BUKAN stabilisasi, BUKAN presisi.
  Jitter sub-piksel (<1 px) & crop tak material di sini.
- **Reduksi 300→~100 NON-DESTRUKTIF** — frame ditandai (flag), tak pernah dibuang
  fisik. Keputusan bisa direvisi. Reduksi efektif terjadi saat Step 2 baca flag.
- **TIGA jenis .mat + retensi per-drive:**
  - `MAT PREP` (out Step 1) = **arsip utama** → drive **backup**.
  - `MAT RAW` = JPEG asli dibekukan; jaring pengaman utk kasus langka (reduksi
    besar-besaran); dibuat di akhir/di luar siklus → drive **backup**.
  - `MAT PIV` (out Step 2) = besar (GS+vektor) → satu-satunya di **hard disk aktif**.
- **Masukan Step 0 = JPEG saja**; ada unpacker MAT RAW→folder JPEG (boleh disemat di Step 0).
- **Step 4a = versi ringkas** (catatan saja, tanpa GS/data mentah) = view dari MAT
  PIV penuh; ramah analisis agentik (Claude).

**Catatan terbuka (antisipasi, jangan tambah kerumitan):** provenance dua-arah
(MAT PIV ↔ induk MAT PREP), binarisasi berkas (nanti), pewarisan konfigurasi
Step 0 → Step 2 (saat ini belum otomatis — lihat bagian KONFIG QPIV di bawah).

---

## KONVENSI NAMA (sedang bertransisi)
Target: **GRAINSA → GRAIN**, fungsi **`PAB_step_1` → `GRAIN1`** dst. Folder sudah
`GRAIN/`. Rename fungsi dikerjakan **bertahap** — lihat [`RENAME_PLAN.md`](RENAME_PLAN.md).
Selama transisi, nama fungsi lama `PAB_step_*` masih berlaku.

---

## STRUKTUR KODE GRAIN (mandiri)
```
GRAIN/
  pab_sa_setup.m       bootstrap path (1×/sesi): paket + lib/ + pivcore_lib/ + PIVlab inti
  PAB_step_0.m  0a 0b  Step 0 validasi frame (QPIV): exclusion + jitter-probe/map
  PAB_step_1.m  1a 1b  Step 1 stabilisasi (GUI PPB2) + pratinjau .mat + cek jitter
  PAB_step_2.m         Step 2 analisis PIV penuh dari .mat
  PAB_step_3.m  3a     Step 3 pratinjau hasil + assign POT
  ALUR_KERJA.html      dokumentasi visual workflow
  test_smoke_*.m       uji headless per-step
  +pivprep/            paket ilmiah: +stab (SURF/phasecorr) +geom +io +util
  +batchpivprep2/      PIVPrep V2: +core.processFolder (stab+crop), +io.*Preset
  +pivanalyze/         engine analisis PIV: config +core +io +geom +util
  +pivanalyzemat/      bridge .mat → folder sementara → engine (Step 2)
  lib/                 helper non-paket: pivprepSingle, pivprepPackFolder,
                       PIVlab_automasi*, pivprepFrameExclusion, pivprepRawExifDt, …
  pivcore_lib/         +pivcore + +pivui (POT/PSG/colormap utk QPIV & preview GUI)
```
Namespace bare (`pivprep.*`, `batchpivprep2.*`, `pivanalyze.*`, `pivanalyzemat.*`,
`pivcore.*`, `pivui.*`) → paket di ROOT GRAIN, di-addpath lewat root. PIVlab inti
eksternal (Add-Ons MathWorks) auto-detect via `which('PIVlab_GUI.m')`.

---

## STATUS IMPLEMENTASI per-STEP

### STEP 1 — GUI BatchPIVPrep2 (PPB2) PENUH ✓
`PAB_step_1` = **peluncur tipis** GUI PPB2 matang (`batchpivprep2.ui.buildGUI` +
`installCallbacks`), memaksa `cbPackMat=1` (jaminan single .mat). GUI custom lama
diarsip → `*_DEPRECATED.m.bak`. PPB2 punya: tabel folder (Add/Add-recursive/Remove/
Clear) + kolom Anchor/Crop/Output editable; tab **Stabilization Anchor** (preset
New/Load/Save, SURF/PhaseCorr, jitterTol, Assign SELECTED/ALL, View/Draw/Edit
Frame 1); tab **Cropping ROI** (Mode 1 rectangle / Mode 2 polygon-squaring, preset,
Assign, View/Draw/Edit); Output Settings (suffix, RAW/GS q, lokasi, checkbox
"Kemas → 1 .mat"); **WQPIV** (Quick PIV) + Save/Load Progress.
- Output **single .mat `pivprep_single_v1`** via `runBatch` → `pivprepPackFolder`.
- **WQPIV** = `PIVlab_automasi_qpiv_GUI_V2` (window QPIV STANDAR). axMain tampil
  foto 5× lebih luas dari strip (`i_viewRoi`); komputasi (`out.roi`) tak berubah.
- **PROGRESS per-ROOT**: `PAB_progress.mat` di dalam folder root yang di-scan
  (`PIVlab_automasi_progress('setfile', …)`); file ada → resume otomatis. Field
  entry: `pab_src/pab_cropmode/pab_out/pab_nimg/pab_anchor/pab_crop/pab_listed` +
  `ignore_frames`. Saat Prep, exclude → `.mat` `prep.qpiv_ignore` (non-destruktif).
- Smoke lulus: 6 frame → .mat 6.95 MB (97.2%), QPIV 5 frame.

### STEP 1a/1b — pratinjau & cek jitter ✓ READ-ONLY
- **1a** pratinjau ISI `.mat` Step 1 (`pivprep_single_v1`) tanpa membongkar:
  axImg (RAW + slider + overlay ROI anchor/crop + toggle GS regen), axJit (kurva
  jitter per-frame + frame ditolak), ringkasan + tabel EXIF. Scan via
  `pivanalyzemat.core.scanMats` (metadata ringan, `PIV_*/` terlewat).
- **1b** kurva jitter multi-exp dari `.mat` Step 1 (tabel + overlay + ekspor PNG).

### STEP 2 — ANALISIS PIV PENUH dari `.mat` ✓
= `PIVlab_automasi_batch_GUI_V4` PERSIS, tapi **unit input = BERKAS `.mat`**.
Strategi **unpack** (rekomendasi): tiap `.mat` dibongkar → folder PIVPrep
sementara → engine `+pivanalyze` (sama V4/V5) APA ADANYA → zero duplikasi.
- Paket **`+pivanalyzemat`**: `scanMats` (pindai root), `unpackMat` (bongkar+cache
  per path .mat), `sessionTmpRoot`/`cleanupTmp`, `processBatchMat` (bangun struct
  `folders` bentuk `scanprep` → `scanExperiments`+`processBatch`).
- **KUNCI PROGRES = path `.mat`** (stabil), bukan folder tmp (`entry.expdir=matfile`).
- **OUTPUT** → `PIV_<yyyy-MM-dd>/` di dalam folder root `.mat`; `<expname>.mat`
  per exp (vektor PIV + GS tersemat).
- Smoke lulus: 6 RAW → scanMats(1) → unpack(6) → PIV 5 + GS 5 + geometri −11.11%.

#### KONFIG QPIV → DASAR PRODUKSI .mat (per-eksperimen) ✓
Hasil Quick PIV yang disimpan user menjadi DASAR produksi PIV penuh exp itu
(menimpa setting global). Di `PIVlab_automasi_progress` per-`expdir`(=path .mat):
`iw_passes`+`num_passes`, `sequencing`, `skip`, `ignore_frames`, `qpiv_done`.
`pivanalyze.core.processBatch` baca IW/#pass per-exp.
⚠️ **File `processBatch` DIDUPLIKASI** di `_reference/PIVprep_V2/3_analyze/
+pivanalyze/+core/` — bila menyentuh, sinkronkan (atau putuskan tautan referensi).
Tabel Step 2: kolom `QPIV✓` + `Mode` (overlap/non-overlap) + `Skip` + `#drop`.

**⚠️ Config handoff gap (Step 0 → Step 2):** setelan QPIV Step 0 (OVL/NOVL+skip+
ignore) disimpan dengan key = folder RAW; Step 2 cari dengan key = path .mat →
tak ketemu → belum terbawa otomatis. Perbaikan: jembatan key RAW↔.mat (Step 1
isi `pab_src`; Step 2 fallback cari via `pab_src`). Belum dikerjakan.

### STEP 3 — pratinjau hasil Step 2 ✓ READ-ONLY (+ 3a assign)
Pratinjau `<expname>.mat` PIV+GS. Paradigma axMain+axPOT (pola PIVTerry StandAlone
`step2.m`) tapi READ-ONLY & POT on-the-fly.
- **axMain**: Vel mag ⇄ Shear (toggle) + overlay GS (CLAHE+auto-adjust, grayscale)
  + slider frame + glyph vektor (default ON). **Vel colormap = JET**
  (`pivcore.util.velColormap`, BUKAN parula/turbo). CLim Vel **otomatis dari
  indenter-max** (`ceil(max/0.5)*0.5`). axMain terkunci zoom-fit.
- **Garis PSG = ROI interaktif** (`images.roi.Line`, draggable, `ROIMoved` re-sampel).
- **axPOT**: POT on-the-fly. AUTO-PSG horizontal di 70% tinggi saat exp dimuat;
  sampling `pivcore.pot.step1Collect.collectAlongLine` (IDENTIK PIVTerry Step 1).
  Spaghetti + envelope MAX (indenter) + klik kurva sorot.
- **MONTASE** → PNG off-screen (`pivcore.montage.buildMontage`): grid kustom atau
  2-kolom (Vel|Shear). Mewarisi JET+GS+glyph. Frame: dibagi rata / selektif.
- **3a** assign kurva POT → HW-#/F/F0/FFW atas `.mat` Step 2 + auto-save `_autopot`.
- Smoke lulus: 106 frame, auto-PSG 229 titik, montase 2×4 + 2-kolom 8-baris.

### STEP 0 — validasi frame ✓ (perlu diselaraskan ke nama "Step 0")
- **PAB_step_0** ROI tarik-sekali (▭/⬡) + auto-jitter 4-kurva → progress → `PAB_step_1(path)` auto-load.
- **PAB_step_0a** pindai GRID area → heatmap kediaman → deteksi lokasi anchor (`pivprepJitterGrid`).
- **PAB_step_0b** QPIV multi-folder + exclusion frame MATI (|V|<ambang) + INTERVAL
  (dt EXIF outlier) (`pivprepFrameExclusion` + `pivprepRawExifDt`). **Nama target = Step 0**
  (buang "b"); reduksi harus non-destruktif (lihat arsitektur di atas).

---

## CARA PAKAI
```matlab
cd('.../Automasi PIV LAB/GRAIN'); pab_sa_setup;
PAB_step_0b     % validasi frame (QPIV exclusion)
PAB_step_1      % stabilisasi → MAT PREP (GUI PPB2)
PAB_step_2      % analisis PIV → MAT PIV
PAB_step_3      % pratinjau hasil
% headless: test_smoke_grainsa_step{0,0a,0b,1a,1b,2,3,3a}
```

## BERIKUTNYA (belum)
- **Step 4** (komentar & analisis — note-taking deskriptif + kuantitatif di MAT PIV).
- Menutup **config handoff gap** Step 0 → Step 2 (jembatan key RAW↔.mat).
- Rename konvensi nama PAB_step_* → GRAIN* (bertahap, lihat `RENAME_PLAN.md`).
- Preset anchor/crop interaktif per baris.
