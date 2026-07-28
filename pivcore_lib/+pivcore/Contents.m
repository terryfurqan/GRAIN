% PIVCORE  Core modular PIVTerry (engine + IO sesi), standalone.
%   Paket fungsi inti PIVTerry yang dapat dipakai-ulang TANPA package
%   +pivterry maupun GUI tab apa pun. Pondasi untuk GUI standalone per-tab.
%   Lihat core/README.md untuk filosofi, kontrak dekopling, & peta pemakaian.
%
% pivcore.data — perhitungan dataset PIVLAB
%   bgAt              - Citra latar bingkai k dari dataset (cell bg_images)
%   buildDataset      - Ekstraksi struct data terstandar dari hasil load .mat PIVLAB
%   computeMagnitude  - Hitung magnitude kecepatan dari komponen u,v
%   computeShearRate  - Hitung shear strain rate dari medan kecepatan u,v
%   extractUnit       - Parsing satuan dari string units PIVLAB
%   frameCount        - Jumlah bingkai citra termuat (panjang cell data.x)
%   jitterSeries      - Deret (frame,jitter_px,accepted) dari prep.jitter.perFrame
%   jitterSummary     - Struct ringkasan jitter (prep.jitter.summary) atau []
%   listScalars       - Daftar bidang skalar yang tersedia pada dataset
%   listVectors       - Daftar sumber vektor yang tersedia pada dataset
%   nodeSpacing       - Estimasi jarak antar-node grid vektor PIV (px)
%   pickAnyVel        - Pilih bidang kecepatan apa pun yang tersedia (fallback)
%   resolveScalar     - Ambil bidang skalar 'sel' pada bingkai k
%   resolveVector     - Ambil bidang vektor sesuai pilihan pada bingkai k
%   safeFrame         - Akses aman ke C{k}; kembalikan [] jika tidak valid
%   syntheticDataset  - Dataset PIVLAB sintetik ringan (1 frame, grid kecil)
%
% pivcore.util — utilitas murni
%   anyToStr          - Konversi nilai apa pun ke string
%   applyOrientation  - Terapkan flip + rotasi pada koordinat dan data
%   baseName          - Nama berkas tanpa folder & ekstensi ('' bila kosong)
%   climDefaults      - Default rentang/colormap warna axMain (velCLim/shearAbs/...)
%   currentBG         - Ambil citra latar yang terkait bingkai k
%   dataExtent        - Hitung extent (xMin/xMax/yMin/yMax) dari koordinat
%   decodeBlob        - Decode blob byte (uint8) -> citra via tempfile+imread
%   decodePNGBytes    - Decode blob PNG -> citra (pembungkus decodeBlob)
%   divergingMap      - Colormap diverging biru-putih-merah (medan bertanda)
%   getfDefault       - Ambil field struct dgn default bila absen/kosong
%   glyphDefaults     - Default render glyph (spacing/lineWidth)
%   isFullLoaded      - TRUE bila semua bingkai dimuat (skalar logical aman &&)
%   movavg            - Moving average sederhana yang mempertahankan NaN
%   natsort           - Natural sort untuk nama berkas dengan angka
%   normalizeToRGB    - Normalisasi citra latar -> RGB double [0,1] (kernel murni)
%   orientImage       - Terapkan flip & rotasi pada citra (RGB)
%   potDefaults       - Default POT/PSG (psgFrac/gsAlpha)
%   processBGImage    - Pipeline pemrosesan citra latar -> RGB truecolor
%   resolveColormap   - Konversi nama colormap ke matriks n x 3
%   robustCLim        - Batas warna kokoh [lo, ~p98] tanpa Statistics TBX
%   rotMat            - Rotasi matriks generik (90 CCW / 90 CW / 180)
%   safeCloseWb       - Penutupan waitbar yang aman
%   scalarOr          - Paksa skalar numerik double (elemen pertama) atau default
%   snapClim          - Bulatkan batas atas CLim ke kelipatan (default 0.5)
%   turboFallback     - Fallback turbo() untuk MATLAB lama
%
% pivcore.pot — model perhitungan (tanpa GUI)
%   potexpModel       - Logika murni modul POT-EXP (eksplorasi POT)
%   potpsg3Model      - Model data POT-PSG3 (kurva terbaik per sesar)
%   potpsg4Model      - Model data POT-PSG4 (akuisisi titik sampling)
%   step1Collect      - Sampler headless Step 1 (dari struct data)
%   curveFeatures     - Ekstraksi fitur kuantitatif kurva POT (Step 3)
%   labels            - Grammar label HW-#/F-#/F0/FFW + warna deterministik
%   records           - Operasi tingkat-record POT (normalize/curveXY/label/warna)
%   assign            - Agregat assignment kurva per label (fromRecords/applySaved)
%   autoAggregate     - Pengelompokan otomatis-deterministik kurva POT-PSG4
%   autoIdentify      - Identifikasi otomatis kurva HW-#/F-#
%   contactDetect     - Deteksi titik kontak antar pasangan kurva
%   hw0Clean          - Logika "HW-0 Clean" (Step 3v2)
%
% pivcore.io — sesi load/save (self-describing .mat; format kompatibel suite)
%   step1Session      - Baca/tulis garis PSG manual + titik (Step 1)
%   step1Export       - Ekspor tampilan mentah Step 1 (PNG)
%   step1Index        - Cache index + progres pra-pemrosesan Step 1 (root)
%   step1Preview      - Cache pratinjau bingkai-1 (downscale 50%) -> browsing instan
%   indexScanner      - Pemindai folder kerja + index eksperimen
%   indexPicker       - Dialog modal startup folder-first
%   assignDataset     - Penulis dataset karakteristik assignment kurva (Step 3)
%   potSession        - Serialisasi progres tab POT
%   autopotSession    - Serialisasi progres _autopot (linchpin workflow)
%
%   CATATAN: core tidak memanggil GUI. IO sesi memulihkan STATE; penyegaran
%   kontrol & gambar adalah tanggung jawab GUI host (lihat README §4).
