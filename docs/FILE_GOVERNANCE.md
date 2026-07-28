# FILE_GOVERNANCE — Tata Kelola Berkas Folder GRAIN

> **Aturan inti:** ROOT folder `GRAIN/` **HANYA** berisi entry point `GRAIN*` + bootstrap
> `grain_setup.m` + paket/library. Semua berkas lain WAJIB tinggal di subfolder yang sesuai.

Berlaku sejak reorganisasi 2026-06-25. Tujuannya: root jadi daftar pintu masuk yang
bersih — buka MATLAB, jalankan `grain_setup`, lalu ketik `GRAIN1` dst.

---

## 1. Apa yang BOLEH di root

| Pola               | Isi                                                              |
|--------------------|-----------------------------------------------------------------|
| `GRAIN0 … GRAIN3a.m`   | Entry point GUI/tahap (pintu masuk yang dipanggil pengguna).     |
| `grain_setup.m`      | Bootstrap path tunggal per sesi.                                |
| `+*/`              | Paket MATLAB namespace (`+pivprep`, `+batchpivprep2`, `+pivanalyze`, `+pivanalyzemat`). |
| `lib/`             | Helper non-paket (`PIVlab_automasi*`, `pivprepSingle`, …).       |
| `pivcore_lib/`     | `+pivcore` / `+pivui` untuk QPIV GUI penuh.                      |
| `tests/`, `docs/`, `_compat/`, `data/` | Subfolder tata kelola (lihat di bawah).      |

**Tidak ada** file lepas `.m` / `.md` / `.html` / `.mat` / `.bak` di root selain yang di atas.

## 2. Subfolder dan isinya

| Folder      | Isi                                                                 | Git |
|-------------|---------------------------------------------------------------------|-----|
| `tests/`    | `test_smoke_*.m` (smoke per tahap) + `run_*.m` (driver/gerbang).     | dilacak |
| `docs/`     | Dokumentasi: `GLOBAL_CONTEXT.md`, `MODULARITY_PLAN.md`, `RENAME_PLAN.md`, `ALUR_KERJA.html`, file ini. | dilacak |
| `_compat/`  | Forwarder nama lama: `PAB_step_*.m`, `pab_sa_setup.m` (transisi, hapus saat RENAME Fase 7). Juga `*.bak` arsip. | `.m` dilacak; `.bak` diabaikan |
| `data/`     | Artefak runtime: `BatchPIVPrep2_progress.mat` & `.mat` lain.         | diabaikan (`*.mat`) |

> Catatan: `+pivanalyze/README.md` tetap **di dalam paket** — itu dokumentasi paket,
> bukan dokumentasi proyek; jangan dipindah ke `docs/`.

## 3. Cara path tetap utuh setelah pindah

`grain_setup.m` meng-`addpath` root **dan** subfolder `tests/` & `_compat/`. Jadi setelah
sekali `grain_setup`:

- entry point `GRAIN*` dan forwarder nama lama tetap resolve by-name;
- semua `test_smoke_*` / `run_*` dapat dipanggil by-name.

Bootstrap di file `tests/` memakai `addpath(here); addpath(fileparts(here))` agar **root**
(tempat `grain_setup`, `GRAIN*`) ikut masuk path bila test dijalankan langsung tanpa
`grain_setup` lebih dulu. Driver yang memindai root (`run_rename_verify`, `run_parsecheck`)
memakai `proj = fileparts(here)`; `run_smoke_subset` memakai `fileparts(fileparts(here))`
untuk mencapai `.../Automasi PIV LAB` (induk RAW).

## 4. Saat menambah berkas baru — taruh di mana?

- Pintu masuk tahap baru (`GRAIN4`, …) → **root**.
- Smoke test / driver → **`tests/`** (bootstrap: `addpath(here); addpath(fileparts(here))`).
- Dokumen/rencana/diagram → **`docs/`**.
- Forwarder transisi nama lama → **`_compat/`**.
- `.mat` / cache / progress → **`data/`** (atau biarkan gitignore menanganinya).

## 5. Verifikasi (gerbang)

```matlab
cd('.../Automasi PIV LAB/GRAIN'); grain_setup;
run_rename_verify({'GRAIN1','GRAIN2','GRAIN3a','grain_setup','PAB_step_2','pab_sa_setup', ...
                   'test_smoke_grain','run_smoke_subset'});
```

Harus melaporkan `PARSE: ALL N FILES CLEAN` dan `NAMES: ALL k RESOLVE`. Jalankan ini
setelah memindah/menambah berkas.
