# +pivanalyze — engine analisis PIV modular

Engine inti lapisan `analyze/` PIVprep_V2, diekstrak dari `PIVlab_automasi_batch_V4`
(V4 dibiarkan utuh sebagai rujukan). Mengikuti pola `+pivprep`.

## Pakai cepat

```matlab
pivanalyze_addpaths();                        % atau pivprepv2_setup
cfg = pivanalyze.config('NumPasses', 4);      % default = perilaku V4
[folders, info] = pivanalyze.core.scanExperiments(parentFolder, cfg);
[summary, aborted] = pivanalyze.core.processBatch(folders, cfg);
```

Atau lewat wrapper berkompatibilitas V4:

```matlab
summary = PIVlab_automasi_batch_V5(parentFolder, 'NumPasses', 4);   % API == V4
```

Atau GUI: `PIVlab_automasi_GUI_V5`.

## Struktur

| Modul | Isi |
|---|---|
| `config` | struct opsi default (mirror inputParser V4) |
| `+core/scanExperiments` | pindai (scanprep) + laporan + penamaan unik |
| `+core/processBatch` | loop per-eksperimen: PIV → GS → EXIF+geometri → buang frame |
| `+io/listGsSorted` `mapFramesToGs` | pemetaan frame→GS |
| `+io/embedGS` `embedTimeGeom` | sematkan ke `.mat` (vector_gs_v1 / exif_time_v1 / geom_strain_v1) |
| `+io/resolveExifDir` `rawSortedNames` | resolusi EXIF & daftar RAW |
| `+geom/computeGeometry` `strainText` | geometri & strain kumulatif bertanda |
| `+util/utilities` | helper kecil (scalar, subfolderCI, dirof, ensureField, getIgnore) |

Dependensi warisan (tetap file terpisah di `3_analyze/`): `PIVlab_automasi`,
`PIVlab_automasi_scanprep`, `PIVlab_automasi_packgs`, `PIVlab_automasi_exiftime`,
`PIVlab_automasi_dropframes`, `PIVlab_automasi_uniquenames`, `PIVlab_automasi_progress`.

## Uji

- `test_smoke_pivanalyze` — cepat, tanpa PIV (config/geometri/io wiring).
- `test_regresi_v5(parentFolder)` — end-to-end V4 vs V5, toleransi numerik.
