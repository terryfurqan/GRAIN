% PIVUI  Helper GUI bersama untuk seri GUI standalone PIVTerry.
%   Lapisan TIPIS pelengkap +pivcore: berisi util yang MEMEGANG handle
%   (figure/axes/uitable) — sengaja DIPISAH dari +pivcore yang headless (nol
%   panggilan GUI). Dipakai step1/step2/… agar widget bersama tak disalin.
%
% pivui — util GUI (memegang handle)
%   forceLightTheme   - Paksa jendela ke tema terang (abaikan dark-mode OS)
%   selectTableRow    - Pilih + gulir ke satu baris uitable
%   applyRowStyles    - Warnai latar/teks tiap baris uitable (uistyle)
%   setStatus         - Tulis pesan ke strip status (guidata h.txtStatus)
%   minimizeForDialog - Kecilkan jendela utama sebelum dialog berkas
%   restoreAfterDialog- Pulihkan + fokus jendela utama setelah dialog
%   lockAxInteractions- Matikan interaksi bawaan axes (zoom/pan/datatip)
%   clearFigModes     - Matikan mode figure (zoom/pan/rotate/datacursor/brush)
%   potStyle          - Palet warna & tebal garis ROI/kurva POT-PSG (GUI pratinjau)
%   makePsgLineROI    - Buat garis PSG interaktif (images.roi.Line) + listener
%   currentLineFromROI- Posisi garis PSG terkini dari ROI (fallback h.line)
%
%   CATATAN: untuk logika murni/headless lihat +pivcore. pivui BOLEH memanggil
%   pivcore, tapi pivcore TIDAK BOLEH memanggil pivui.
