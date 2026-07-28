# PLAN — Buang modifier Ctrl dari SEMUA hotkey PAB4 + guard fokus-mengetik

Status: **RENCANA (belum diimplementasi).** Fitur taper (yang pakai `w`) sudah jalan
lebih dulu dengan pola guarded (`w` polos + `i_typingFocus`) sebagai bukti-konsep.

## Tujuan
Semua hotkey PAB4 dipicu tombol POLOS (tanpa Ctrl). Mis. `,`/`.`=frame, `1`-`4`=POI,
`q`=bidang sesar, `w`=taper, `f`=toggle AXSLIP, `j/k/l/;`=loncat POI, dst. Shift tetap
sebagai varian (mis. `<`/`>`=5 frame, `Shift+1..4`=PRP).

## Risiko UTAMA (kenapa Ctrl ada sekarang)
`WindowKeyPressFcn` menangkap tombol dari SELURUH figure — termasuk saat kursor di
**tabel DESC** (mengetik kolom DESC) atau **kotak edit** (Durasi MP4, dll). Guard
tunggal `if ~any(strcmp(mods,'control')), return` (PAB4.m ~6308) adalah yang mencegah
tombol memicu aksi saat mengetik. Buang Ctrl -> mengetik `w`/`t`/`q`/`1`-`4`/`f`/`h`/`j`
di kolom DESC akan memicu aksi liar. **Praktis mustahil mengetik deskripsi tanpa guard.**

## Solusi: guard fokus-mengetik
Sudah tersedia helper `i_typingFocus(fig)` (PAB4.m): TRUE bila `fig.CurrentObject`
adalah `uitable` (Type='uitable') atau uicontrol `Style='edit'`. Terverifikasi andal
R2025b (uitable→Type='uitable'; edit→Style='edit'; button→Style='pushbutton').

### Langkah implementasi
1. **Ganti guard baris ~6308** dari:
   ```matlab
   if ~any(strcmp(mods,'control')), return; end   % SEMUA hotkey pakai Ctrl
   ```
   menjadi:
   ```matlab
   % Buang syarat Ctrl. Guard fokus: bila kursor di uitable/edit -> hotkey POLOS
   % dilewati (biar jadi teks). KECUALI alat interaktif yg sedang aktif (taper/
   % bidang sesar) -> tetap terima tombol kunci/simpan.
   toolActive = (isfield(hh,'taperOn') && hh.taperOn) || (isfield(hh,'faultPolyOn') && hh.faultPolyOn);
   if ~toolActive && i_typingFocus(fig), return; end
   ```
   (perlu `hh = guidata(fig)` lebih awal.)

2. **Hapus `mods='control'` dari SEMUA cabang** di `i_onKeyPress` — buang pengecekan
   Ctrl; pertahankan `hasShift`. Titik yang perlu disunting (per docstring & cabang):
   - Frame `,`/`.`/`<`/`>` (Shift=5)
   - `Shift+←/→` = geser jendela X 10 frame
   - `Shift+↑/↓` = cut-off net-slip
   - `Shift+Q` = loncat NUC-FSR ; `q`/`e`/`\` = toggle bidang sesar
   - `w` = taper (SUDAH polos; hapus jalur khusus, jadikan cabang biasa)
   - `-`/`+`/`=` = lebar jendela X
   - `[`/`]`/`{`/`}` = geser seleksi kurva
   - `f` = toggle AXSLIP
   - `` ` `` = cycle NUC POS ; `o` = cycle DX
   - `Shift+Backspace`/`Shift+D` = hapus baris
   - `1`-`4` (+Shift=PRP) / `t` = tambah baris POI
   - `m`/`/` = prev/next F#
   - `h`(+Shift) = cycle DX ; `j`/`k`/`l`/`;` = loncat POI

3. **Konflik tombol tanpa Ctrl** yang HARUS ditinjau:
   - `,`/`.` vs mengetik koma/titik di DESC → guard fokus menangani (fokus di tabel→lewat).
   - `1`-`4` vs mengetik angka di kolom # ACT F / IS/OOST (numeric edit dalam uitable)
     → uitable = CurrentObject → guard menangani. **PERLU UJI**: saat sel uitable dalam
     mode edit, apakah CurrentObject tetap uitable? (kemungkinan ya; uji manual.)
   - `w`/`q`/`e` saat alat aktif → `toolActive` bypass guard (benar; user menutup alat).
   - Kotak edit Durasi MP4 (`h.edMovieDur`) → Style='edit' → guard menangani.

4. **Update `i_hotkeyList()`** (PAB4.m ~4444) & docstring `i_onKeyPress`: buang "Ctrl +"
   di seluruh daftar; ganti jadi tombol polos. Ini juga tampil di TAB ⓪ Help.

## Uji (WAJIB sebelum pakai produksi)
Buat `tests/test_smoke_pab4hotkey.m`:
- **Guard fokus**: set `fig.CurrentObject=h.tblDesc` → kirim keyevent `w`/`1`/`t` →
  assert TIDAK ada perubahan (tak nambah baris, tak toggle taper). Set
  `CurrentObject=axMain` → kirim `w` → assert alat taper toggle ON.
- **Semua hotkey polos** memicu handler yang benar (fire keyevent sintetis dgn
  `evt.Key`/`evt.Character`, `Modifier={}`), bandingkan efek dgn versi Ctrl lama.
- **Regresi**: `test_smoke_pab4` A-G + `test_smoke_pab4taper` A-E tetap LULUS.
- **Uji MANUAL interaktif** (headless tak menangkap fokus-ketik uitable dgn setia):
  ketik deskripsi panjang berisi `w t q 1 2 3 4 f h j k` di kolom DESC → pastikan
  TAK ada aksi liar; klik axMain lalu tekan tombol polos → aksi berjalan.

## Catatan
- Simulasi keyevent headless: buat struct `evt` dgn field `Key`,`Character`,`Modifier`
  lalu panggil `i_onKeyPress(fig, evt)` langsung (fungsi privat → test di folder sama
  atau via `feval` pada handle). Alternatif set `fig.CurrentObject` lalu
  `i_onKeyPress`.
- CurrentObject saat MENGETIK (bukan klik) di uitable: MATLAB meng-update CurrentObject
  saat klik untuk fokus; mengetik setelahnya tetap uitable. Namun ada kemungkinan edge
  (fokus keyboard vs CurrentObject) → **uji manual** menentukan apakah guard cukup atau
  perlu fallback tambahan (mis. cek `fig.CurrentCharacter` / listener uitable edit-mode).
- Bila guard fokus TERBUKTI bocor saat mengetik, mundur ke: pertahankan Ctrl untuk
  hotkey yang tombolnya juga karakter-teks umum (`t`,`q`,`w`,`1`-`4`,huruf), buang Ctrl
  hanya untuk tombol non-teks (panah, `[`/`]`, `,`/`.`). Ini kompromi paling aman.
