# RENAME PLAN — konvensi nama PAB (bertahap)

> Tujuan: rapikan jalur pemanggilan nama. **PABSA → PAB**, dan fungsi
> **`PAB_step_N` → `PABN`** (mis. `PAB_step_1` → `PAB1`, `PAB_step_0b` → `PAB0b`).
> Dikerjakan **BERTAHAP & non-destruktif** — tiap fase berdiri sendiri, diuji,
> bisa di-commit terpisah. Selama transisi nama lama TETAP berfungsi.

## Prinsip transisi aman
1. **Forwarder dulu, hapus belakangan.** Saat membuat `PAB1.m`, biarkan
   `PAB_step_1.m` jadi **forwarder tipis** (`function PAB_step_1(varargin); PAB1(varargin{:}); end`)
   sampai semua pemanggil pindah. Tak ada yang patah di tengah jalan.
2. **Satu step per commit.** Jangan rename semua sekaligus — mudah salah & sulit di-bisect.
3. **Uji tiap fase** dengan `test_smoke_*` terkait sebelum lanjut (R2025b).
4. **`pab_sa_setup` paling akhir** — tersebut di 24 file; sentuh terakhir.
5. Penyebutan di **komentar/teks** boleh diikutkan kapan saja (tak fungsional).

## Inventaris ketergantungan (per 2026-06-25)
| Nama | #file menyebut | Pemanggil internal penting |
|---|---|---|
| `PAB_step_0` | 9 | `PAB_step_0b.m:779` (`onGoStep1` → `PAB_step_0`), test_smoke_step0 |
| `PAB_step_1` | 11 | `PAB_step_0*.m` (tombol "Lanjut"), test_smoke_step0/1a/1b |
| `PAB_step_2` | 7 | run_check_step2, run_parsecheck, Provenance string |
| `PAB_step_3` | 8 | test_smoke_step3/3a |
| `pab_sa_setup` | 24 | hampir semua step + test (panggil di awal) |

---

## FASE 0 — folder & konteks ✅ SELESAI (2026-06-25)
- [x] `PIVTerry/`, `PIVprep_V2/` → `_reference/` (git mv).
- [x] `PAB_SA/` → `PAB/` (rename folder; `pab_sa_setup` relatif → tak patah).
- [x] Tulis ulang `GLOBAL_CONTEXT.md` (fokus PAB; `_reference/` = inspirasi).
- [x] `ALUR_KERJA.html` (dokumentasi workflow).
- [x] `RENAME_PLAN.md` (dokumen ini).

## FASE 1 — selaraskan "Step 0b" → "Step 0" (semantik) — KEPUTUSAN: DITUNDA
> Keputusan (2026-06-25, oleh asisten saat AFK): **JANGAN gabung semantik.**
> Ketiga varian step-0 dipertahankan utuh sebagai alat terpisah dan hanya
> di-rename mekanis di Fase 3: `PAB0` (ROI jitter/anchor), `PAB0a` (peta jitter),
> `PAB0b` (QPIV exclusion). Penggabungan/renomeran semantik berisiko mengubah
> perilaku tanpa pengawasan, jadi disisakan untuk diputuskan manual nanti.
- [ ] (opsional, manual) Putuskan mana **Step 0 utama**; buang "KIPIF" dari teks.
- [ ] (opsional) Uji ulang: `test_smoke_pab_step0`, `_step0a`, `_step0b`.

## FASE 2 — `PAB_step_1` → `PAB1` (+ 1a/1b) ✅ SELESAI (commit bdd28fa)
- [x] Rename file + fungsi `PAB_step_1/1a/1b` → `PAB1/1a/1b` (+ self-ref).
- [x] Forwarder tipis nama lama (non-destruktif).
- [x] Update pemanggil: tombol "Lanjut" `PAB0:916`, `pab_setup` "Buka GUI",
      `run_parsecheck`, test step0/1a/1b.
- [x] Verifikasi R2025b: 82 file PARSE CLEAN, nama baru+forwarder RESOLVE.

## FASE 3 — `PAB_step_0*` → `PAB0*` ✅ SELESAI (commit 66b64a5)
- [x] Rename `PAB_step_0/0a/0b` → `PAB0/0a/0b` (+ forwarder).
- [x] Update `onGoStep1` (`PAB0b:779` → `PAB0`) & `fileread(which('PAB0'))` di test.
- [x] Verifikasi: 85 file PARSE CLEAN.

## FASE 4 — `PAB_step_2` → `PAB2` ✅ SELESAI (commit 40f6d36)
- [x] Rename file + fungsi (+ forwarder).
- [x] `run_check_step2`/`run_parsecheck` → `PAB2.m`; Provenance `'PAB_step_2'`→`'PAB2'`
      (tak ada reader yg switch pd nilai literal).
- [x] Verifikasi: `run_check_step2` LULUS (parse + strainText + no-local-strainText).

## FASE 5 — `PAB_step_3` → `PAB3` (+ 3a) ✅ SELESAI (commit 5fc1fd9)
- [x] Rename file + fungsi (+ forwarder).
- [x] Update test step3/3a + `run_parsecheck` (semua nama kanonik).
- [x] Verifikasi: 88 file PARSE CLEAN; `run_parsecheck` LULUS.

## FASE 6 — rename test & helper "pabsa" → "pab" ✅ SELESAI (commit 0240c3a)
- [x] `test_smoke_pabsa*.m` → `test_smoke_pab*.m`; update `run_smoke_subset`.
- [x] `pab_sa_setup` → `pab_setup` (+ forwarder varargout passthrough);
      sapu SEMUA caller ke `pab_setup`.
- [x] Verifikasi: 89 file PARSE CLEAN; `pab_sa_setup() == pab_setup()` (struct identik).

## FASE 7 — bersih-bersih (DITUNDA — destruktif, perlu konfirmasi manual)
> Semua forwarder masih HIDUP. Hapus hanya bila yakin tak ada pemanggil luar
> (skrip di luar repo, kebiasaan ketik nama lama, dll). Repo saat ini konsisten:
> nama kanonik di semua tempat, nama lama jadi shim tipis.
- [ ] Hapus forwarder `PAB_step_*.m` & `pab_sa_setup.m`.
- [ ] Sapu sisa penyebutan "PABSA"/"PAB_SA"/"pabsa" di komentar/banner/tooltip.
- [ ] Update `GLOBAL_CONTEXT.md` & `ALUR_KERJA.html` ke nama final.

---

**Status:** Fase 0 & **2–6 SELESAI** (rename + forwarder + verifikasi tiap fase).
Fase 1 ditunda (keputusan semantik manual). Fase 7 ditunda (destruktif).
**Catatan:** kerjakan satu fase, uji, commit, baru lanjut. Jangan diborong.
**Gerbang verifikasi:** `run_rename_verify` (parse-clean + resolusi nama),
`run_parsecheck`, `run_check_step2` — semua LULUS di R2025b.
