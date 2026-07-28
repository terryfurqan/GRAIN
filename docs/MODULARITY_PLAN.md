# PAB_SA — Rencana Modularitas (audit terverifikasi)

> Hasil audit multi-agent (39 agen, 26/31 klaster terkonfirmasi adversarial).
> Tujuan: hilangkan logika **hardcoded/duplikat yang dipakai bersama** lintas
> `PAB_step_1/1a/1b/2/3/3a`. Kernel ilmiah & primitif → paket bersama; cangkang
> callback yang terikat `guidata` tetap lokal per-file.
> Baseline smoke (R2025b) HIJAU sebelum mulai: step_3, step_3a, step_1a, step_1b. ✓

## Prinsip
- Ekstrak hanya **kernel murni / primitif / konstanta**; biarkan cangkang callback
  yang terikat `h`/`guidata` di tiap file (panggil kernel bersama).
- JANGAN satukan salinan yang sengaja dicermin: `pivanalyze.core.processBatch`
  (mirror di PIVprep_V2), paket `+batchpivprep2` (2 salinan), `lib/pivprepPackFolder.m`.
- Smoke per-step setelah TIAP aksi; tahan baseline hijau dari aksi 0.

## Paket baru / perluasan
| Rumah | Isi |
|---|---|
| `+pivui` (perluas) | `setStatus`, `minimizeForDialog`, `restoreAfterDialog`, `lockAxInteractions`, `clearFigModes`, `makePsgLineROI`, `currentLineFromROI`, `potStyle()` |
| `pivcore.data` (baru) | `jitterSeries(p)`, `jitterSummary(p)` |
| `pivcore.util` (baru) | `decodeBlob(bytes,ext)`, `decodePNGBytes`, `getfDefault`, `baseName`, `isFullLoaded`, `scalarOr`, `numStr`, `glyphDefaults`, `climDefaults`, `snapClim`, `potDefaults` |
| `pivcore.montage` (baru publik) | `renderScalarPanel(ax,data,k,scalar,cfg)` ← promosi `i_drawPanel` privat |
| `pivcore.pot` (baru) | `renderPOT(ax,recs,opts)` + `records.indenterEnvelope` |
| `pivanalyzemat.core` (perluas) | `dateTag`, `pivOutDir`, `isPivOutName`, `matScan.collect/probe`, `prepAccessor`, `progressTag`, `progressFileName` |

## Status pelaksanaan
- ✅ Aksi 0–14 SELESAI & smoke hijau (1a/1b/3/3a + cek step_2; 61 file parse clean; PIVTerry pivcore smoke lulus). Paket bersama:
  `+pivui`(setStatus/minimizeForDialog/restoreAfterDialog/lockAxInteractions/clearFigModes/potStyle/**makePsgLineROI/currentLineFromROI**),
  `+pivcore.util`(getfDefault/baseName/scalarOr/isFullLoaded/decodeBlob/decodePNGBytes/glyphDefaults/climDefaults/snapClim/potDefaults),
  `+pivcore.data`(jitterSeries/jitterSummary), `+pivcore.montage.`**renderScalarPanel** (promosi i_drawPanel; 3 salinan→1),
  `+pivanalyzemat.core`(**dateTag/pivOutDir/isPivOutName/scanPivMats/probePivMat/prepJitterTol/prepTolKeys/prepRoiPts/prepGsScale**).
  (prepGsScale: skala GS 0.5/guard 0<s≤1 disatukan dari i_gsScale step_1a + unpackMat i_gsParams; teruji lewat step_2 PIV penuh.)
  pivcore/pivui DICERMIN ke `PIVTerry/core`; pivanalyzemat hanya 1 salinan (PAB_SA). strainText lokal step_2
  dihapus → `pivanalyze.geom.strainText` (Unicode `≤` fidelitas V4, dicermin ke PIVprep_V2). `i_scalar`
  disatukan `double(x(1))`. Konstanta render di-seed dari helper (String via sprintf, tampilan byte-identik).
  ROI PSG (warna/LW/MS) lewat potStyle. Pola: forwarder tipis lokal (titik panggil tak disentuh).
- ⏳ Aksi 15–16 DITUNDA (sesi terpisah): klaster axPOT — `pivcore.pot.renderPOT(ax,recs,opts)`
  ber-parameter {order,lineWidthFn,trimFn} + `records.indenterEnvelope` (step_3a SUPERSET step_3, HIGH
  risk, perlu verifikasi visual kurva POT). + POST: dataExtent (hanya dalam guard non-empty) & uiDefaults.

## Urutan aksi (risiko menaik)
0. **PRE-FLIGHT**: smoke suite hijau (sudah ✓).
1. **[nol-risiko]** step_2 light-theme inline → `pivui.forceLightTheme` (2 situs).
2. **[nol-risiko]** hapus `strainText` lokal step_2 → `pivanalyze.geom.strainText` (rekonsiliasi teks `L0≤0!` vs `L0<=0!`).
3. **[nol-risiko identik]** `pivui.setStatus` ← `i_setStatus` x4 (1a/1b/3/3a).
4. **[nol-risiko identik]** `pivui.minimizeForDialog/restoreAfterDialog` ← `i_minimize/i_restore` (1a/1b/3/3a) + nested `minFig/restoreFig` step_2.
5. **[nol-risiko identik]** `pivui.lockAxInteractions/clearFigModes` ← step_3/3a.
6. **[rendah]** `pivcore.util.getfDefault/baseName/isFullLoaded/scalarOr/numStr` (rekonsiliasi `i_scalar` double-cast; JANGAN lipat `i_str`→`anyToStr`).
7. **[rendah parser]** `pivcore.data.jitterSeries/jitterSummary` ← step_1a/1b.
8. **[rendah primitif]** `pivcore.util.decodeBlob/decodePNGBytes` ← step_1a/1b.
9. **[konstanta]** `glyphDefaults/climDefaults/snapClim/potDefaults` + `pivui.potStyle`; seed handle & String edit-box via `sprintf('%g',...)`.
10. **[kontrak]** `pivanalyzemat.core.dateTag/pivOutDir/isPivOutName` + `progressTag/progressFileName` ← step_2 producer.
11. **[medium scanner]** `pivanalyzemat.core.matScan.collect/probe` ← step_3/3a `i_collectMats/i_probeMat` (JANGAN pakai `scanMats`/`indexScanner` — format/scope beda).
12. **[medium render]** promosi `i_drawPanel`→`pivcore.montage.renderScalarPanel`; panggil dari buildMontage dulu lalu step_3/3a `i_renderMain`.
13. **[medium]** `pivui.makePsgLineROI/currentLineFromROI` ← step_3/3a ROI.
14. **[skema]** `pivanalyzemat.core.prepAccessor` ← step_1a/1b + scanMats/unpackMat.
15. **[TINGGI, terakhir]** rekonsiliasi klaster axPOT: `pivcore.pot.renderPOT(ax,recs,opts)` ber-parameter `{order,lineWidthFn,trimFn}` (step_3a superset step_3) + `records.indenterEnvelope`; 5 helper identik diekstrak dgn state-bundle.
16. **POST**: opsional `pivcore.util.dataExtent` di step_3 (HANYA dalam guard non-empty — handle tak punya `h.state`) + `pivanalyze.uiDefaults`.

## Bahaya
- Kopling `guidata`/handle = risiko utama → ekstrak kernel saja.
- `dataExtent` else-branch baca `h.state.lockedXLim` (step_3 tak punya `h.state`) → error bila dipanggil di luar guard non-empty.
- `matScan` HARUS pertahankan scope root+PIV_* langsung + filter substring `_autopot/progress` persis.
- POT cluster: step_3a superset (trim/view-order/LW tiers) → renderPOT default = perilaku flat step_3.
- Tag `pivprep_single_v1` di 4 GUI = komentar/UI-string saja → BIARKAN.
- Selalu R2025b (R2026a hang -batch + bug ROI).
