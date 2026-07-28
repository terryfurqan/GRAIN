# Glosarium ID → EN (migrasi teks UI GRAIN)

Acuan TUNGGAL penerjemahan teks UI GRAIN dari Bahasa Indonesia ke Inggris.
Tujuannya: istilah yang sama selalu diterjemahkan sama di semua modul.

## Aturan cakupan

**DITERJEMAHKAN** (teks yang dilihat pengguna):
- `Text`, `Title`, `Tooltip`, `Placeholder`, `ColumnName`, `Items` (tampilan dropdown)
- `title()` / `xlabel()` / `ylabel()` / `legend()` pada axes
- pesan `setStatus` / `setMid` / `uialert` / `uiconfirm` / `uiprogressdlg`
- judul dialog berkas (`uigetdir`, `uigetfile`, `uiputfile`)
- **teks** pesan `error()` / `warning()`

**TIDAK DISENTUH**:
- identifier error (`'GRAIN0:cancel'`), nama fungsi/variabel, field struct
- `ItemsData` dropdown, kunci JSON/sidecar, nama berkas & folder
- komentar kode (tahap terpisah bila diminta)
- `OLD GRAIN/` dan `_reference/`

**Hati-hati**: string opsi `uiconfirm` dibandingkan pakai `strcmp` — daftar opsi
dan perbandingannya HARUS diubah bersamaan. Begitu pula label tombol/`ColumnName`
yang dicari test.

## Istilah inti

| Indonesia | English |
|---|---|
| eksperimen / exp | experiment / exp |
| berkas | file |
| daftar | list |
| bingkai / frame | frame |
| gambar / citra / foto | image / photo |
| garis | line |
| titik | point |
| sesar | fault |
| kurva | curve |
| bidang sesar | fault plane |
| nukleasi | nucleation |
| net-slip | net slip |
| kemiringan / sudut | angle (tilt untuk kemiringan strip) |
| posisi | position |
| orientasi | orientation |
| pasangan (sequencing) | pairing |
| berurutan | consecutive |
| berpasangan | paired |
| ambang | threshold |
| mati (frame) | dead |
| bersih | clean |
| abaikan | ignore |
| ceklis | checkmark |
| kunci | lock |
| pratinjau | preview |
| tampilan | view |
| deskripsi | description |
| komentar | comment |
| tebal / ketebalan | thickness |
| kedalaman | depth |
| jarak | distance |
| lebar | width |
| panjang | length |
| baris / kolom | row / column |

## Kata kerja & status

| Indonesia | English |
|---|---|
| Pilih… | Pick… |
| Jalankan | Run |
| Proses | Process |
| Simpan | Save |
| Muat | Load |
| Hapus (dari daftar) | Remove (from list) |
| Hapus (dari disk) | Delete |
| Tambah | Add |
| Bersihkan | Clear |
| Kembalikan | Restore |
| Batal / Batalkan | Cancel |
| Lanjut → | Next → |
| Pindai / Scan ulang | Scan / Rescan |
| Ukur | Measure |
| Ekspor | Export |
| Tandai | Mark |
| Siap. | Ready. |
| Sedang sibuk… | Busy… |
| Selesai | Done / Finished |
| Belum ada … | No … yet |
| Gagal … | … failed |
| Dibatalkan pengguna | Cancelled by the user |
| Tersimpan | Saved |
| baru / tersimpan (status tabel) | new / saved |
| Kosong (judul alert) | Empty |
| Sebagian tak valid | Partly invalid |

## Frasa berulang

| Indonesia | English |
|---|---|
| `belum dipilih` | `none selected` |
| `tak di-path` | `is not on the path` |
| `%d frame ditandai abaikan.` | `%d frames marked ignore.` |
| `mis 1,2,5-9` | `e.g. 1,2,5-9` |
| `utk` / `dgn` / `dll` | `to`/`for` · `with` · `etc` |
| `tak berubah saat pindah exp` | `unchanged when switching exp` |

## Status per tahap

| Tahap | Modul | Status |
|---|---|---|
| 1 | `GRAIN0.m` (+ 4 test) | ✅ selesai — 152 penggantian, test LULUS R2025b |
| 2 | `GRAIN1.m` (+ stub questdlg di test) | ✅ selesai — 179 penggantian, test LULUS R2025b |
| 3 | `GRAIN2.m` | ✅ selesai — 262 penggantian, test LULUS R2025b |
| 4 | `GRAIN3.m`, `GRAIN3a.m` | ⏳ |
| 5 | `GRAIN4.m` (+ turunan) | ⏳ |
| 6 | `GRAIN5.m`, `GRAIN6_temp.m` | ⏳ |
| 7 | tool standalone (GRAINMASK, GRAINEXPORT, GRAINEDIT, …) | ⏳ |
| 8 | teks UI di `pivcore_lib/` | ⏳ |
