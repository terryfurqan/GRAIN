function figOut = GRAIN4(rootDir, varargin)
%GRAIN4  Step 4 — EDITOR INTERPRETASI FINAL (laporan final; kedudukan DI ATAS GRAIN5).
%   Alur: GRAIN5 = alat ASSIGN awal (HW/FW + identifikasi sesar). GRAIN4 = tempat
%   FINALISASI interpretasi lengkap (tabel deskripsi per-frame). Jadi hasil GRAIN4
%   berkedudukan LEBIH TINGGI dari GRAIN5 — GRAIN4 = laporan final. NAMUN sidecar GRAIN4
%   (`<base>_desc.json`) BERDIRI SENDIRI: TIDAK mengganti/menulis `_faults.json`
%   GRAIN5. GRAIN4 ya GRAIN4 saja.
%
%   GRAIN4 = salinan GRAIN5 yang sistem ASSIGN-nya DILEPAS. Di sini user TIDAK
%   meng-assign HW/FW/sudut — hanya NAVIGASI (pindah frame/sesar/garis PSG/kurva)
%   dan MENCATAT interpretasi per-frame di TABEL DESKRIPSI gaya Excel (spec
%   `Tabel DESC V1.xlsx`). Assign awal (HW/FW) tetap dikerjakan di GRAIN5.
%
%   INPUT = SAMA seperti GRAIN5: pilih folder kerja (output Step 2 / PIV_<tgl>/),
%   lalu klik eksperimen di daftar kiri. Sidecar `<base>_faults.json` GRAIN5
%   di-BACA (tak ditulis) untuk konteks sesar (HW/FW/POI/sudut per garis PSG).
%
%   TABEL DESC (panel kanan) = 6 kolom: F# (auto, sesar aktif) · FRM (auto,
%   frame AX main) · POI (dropdown Start/NUC-T/NUC-D/FSR-T/FSR-D/MSR/End/
%   </blank>; auto-suggest dari _faults.json, bisa diubah) · # ACT F (ketik) ·
%   IS/OOST (numerik manual, default 1) · DESC (paste teks lisan). Tiap baris terikat ke
%   garis PSG aktif (psgId) — SELEKTOR garis PSG mengganti tabel yang tampil.
%
%   3 TOMBOL AKSI:
%     💾 Save Progress — simpan tabel ke `<base>_desc.json` (lanjut sesi lain).
%     ✅ Commit        — save + EXPORT gambar dunia-nyata (AX main velmag/shear
%                        + AX POT, JPG ≤700KB) + JSON interpretasi ke folder
%                        ber-versi PAB4_DESC/<exp>/<ddmmyy-HHMMSS>_<psg>/.
%     ↔ Edit di GRAIN5   — buka GRAIN5 pada folder yang sama untuk mengedit assign.
%
%   GRAIN4 = GROUND TRUTH laporan final; TIDAK menulis balik ke `_faults.json`
%   (GRAIN5 dibiarkan apa adanya). Gambar AX main mengikuti PENGATURAN TAMPILAN
%   panel tengah-atas (CLim/alpha/glyph live) — persis tampilan kerja + GS latar
%   + glyph. Engine: pivcore.io.grain4Desc / pivcore.io.grain4DescExport +
%   pivcore.io.grain5FaultExport.buildFaultJson (interpretasi, reuse).
%
%   HOTKEY navigasi: Ctrl+M/'/'=pindah sesar · Ctrl+,/.=frame · Ctrl+[/]/{/}=geser
%   kurva · Ctrl+J/K/L/;=loncat POI · Ctrl+E=ukur sesar (polyline) ·
%   Ctrl+F=toggle AXSLIP<->axPOT · Ctrl+- perlebar / Ctrl++ persempit jendela X
%   (cycle 5% total frame: 100/95/90/..; axPOT & AXSLIP SAMA; disimpan ke progress).
%   HOTKEY CATAT (tambah baris deskripsi pada FRAME live dgn POI sesuai tombol;
%   +Shift = fase PRP): Ctrl+1=NUC-BDF0 · Ctrl+2=NUC-BDF1 · Ctrl+3=NUC-FSR ·
%   Ctrl+4=FS-max (Ctrl+Shift+4=FS-x) · Ctrl+Shift+1..3=PRP-BDF0/BDF1/TF · Ctrl+T=</blank>.
%   Ctrl+` = cycle NUC POS (—/T/M/B/FT/ALL = Top/Mid/Bottom/Fault-Tip/semua) baris terpilih ·
%   Ctrl+O/H = cycle DX bawah, Ctrl+Shift+H = atas (+loncat frame) ·
%   Ctrl+Shift+Backspace = hapus baris. POI=TRX + kolom F TRX (frame akhir) ->
%   fill hijau (transisi/hand-off imbrikasi). Warna: FSR=merah,TF=cokelat,
%   BDF0=biru(alas),BDF1=hijau(tengah). Hotkey ASSIGN GRAIN5 (Ctrl+Q/W/Shift+W) MATI.
%
%   GRAIN4                        % pilih folder ROOT (dialog)
%   GRAIN4(rootDir)              % langsung ke folder
%
%   Jalankan `grain_setup` sekali per sesi. SELALU MATLAB R2025b.

    figOut = [];   % default (dialog batal / early-return)
    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivui.grain4Shell'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end
    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, 'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end
    initTab = 'desc';   % GRAIN4: hanya 1 panel (tabel deskripsi); arg 'tab' diabaikan
    for i = 1:2:numel(varargin)-1
        if strcmpi(varargin{i},'tab'), initTab = lower(char(varargin{i+1})); end
    end

    opts = struct();
    opts.Name = 'GRAIN4 — Pencatat Tabel Deskripsi (Step 4, laporan final)';
    opts.rightTitle = 'Deskripsi (Step 4 — pencatat)';
    opts.hooks = struct( ...
        'beforeLoad',      @i_beforeLoad, ...   % auto-flush progres exp lama sebelum ganti
        'onExpLoaded',     @i_onExpLoaded, ...
        'onLineChanged',   @i_onLineChanged, ...
        'onPotChanged',    @i_onPotChanged, ...
        'onCurveClick',    @i_onCurveClick, ...
        'onFrameChanged',  @i_onFrameChanged, ...
        'afterRenderMain', @i_afterRenderMain, ...
        'decoratePOT',     @i_decoratePOT, ...
        'slipOverride',    @i_slipOverride);   % GRAIN5: AXSLIP net-slip per-SESAR (HW−FW)

    h = pivui.grain4Shell.build(opts);
    % Ratakan DASAR kolom kanan (pnlR) dgn kolom kiri (pnlL y=0.01) + naikkan
    % sedikit puncaknya -> lebih banyak ruang vertikal utk kontrol tab. (Reposisi
    % lokal GRAIN5_temp; GRAIN4 shell tak diubah.)
    try, set(h.pnlR, 'Position', [0.686 0.010 0.308 0.985]); catch, end

    % --- axMain LEBIH TINGGI (isi whitespace vertikal) — GRAIN4 SAJA ---------------
    % Default shell axMain = [0.205 0.505 0.455 0.385] (top 0.890). Perbesar TINGGI:
    % naik ke atas mendekati toolbar frame (pnlC bawah ~0.895) & turun ke bawah
    % mendekati strip kontrol (Plot:axMain/Spacing/Skala-V top ~0.468). Data tetap
    % 1:1 (daspect di renderMain) -> gambar center + whitespace di dalam axMain
    % (bebas diatur via zoom/kunci pandang). axACtop/axACbot (overlay AX-AC) ikut
    % dipindah agar tetap sejajar saat di-toggle. TAK ganggu toolbar/strip/tab kanan.
    % CATATAN top 0.885 (bukan 0.888): sisakan ruang JUDUL axMain (dulu 0.888
    % menghalangi title). renderMain menambah colorbar tiap load -> axes menyusut;
    % karena itu posisi ini DISIMPAN (h.axMainPos) & DITERAPKAN ULANG di
    % i_afterRenderMain supaya axMain tetap tinggi SETELAH load eksperimen.
    AXMAIN_POS = [0.205 0.470 0.455 0.400];   % y 0.470..0.870 (tinggi 0.400; sisa judul)
    h.axMainPos = AXMAIN_POS;
    try, set(h.axMain, 'Position', AXMAIN_POS); catch, end
    try
        yB = AXMAIN_POS(2); hT = AXMAIN_POS(4); half = hT/2;
        set(h.axACbot, 'Position', [AXMAIN_POS(1) yB          AXMAIN_POS(3) half]);
        set(h.axACtop, 'Position', [AXMAIN_POS(1) yB+half     AXMAIN_POS(3) half]);
    catch, end
    guidata(h.fig, h);

    % --- Tombol ZOOM + KUNCI PANDANG axMain (berbagi ruang dgn "Plot: axMain") --
    % "Plot: axMain" default [0.182 0.432 0.168 0.036]. Kita PERSEMPIT jadi ~0.086
    % lalu selipkan 2 tombol (🔍 Zoom, 🔒 Pandang) di sisa ruang sampai x=0.350.
    try
        set(h.btnAxView, 'Position', [0.182 0.432 0.086 0.036]);
        h.btnAxZoom = uicontrol('Parent',h.fig,'Style','togglebutton','Units','normalized', ...
            'Position',[0.270 0.432 0.040 0.036],'String','🔍','Value',0,'FontWeight','bold', ...
            'TooltipString',['Zoom/pan axMain: ON = scroll utk zoom, drag utk geser (pan). ' ...
            'Untuk eksperimen sangat panjang -> perbesar area menarik lalu klik 🔒 utk KUNCI pandang. ' ...
            'Klik lagi (OFF): reset ke tampilan penuh.'], ...
            'Callback',@(s,e) i_onAxMainZoom(h.fig));
        h.btnAxViewLock = uicontrol('Parent',h.fig,'Style','togglebutton','Units','normalized', ...
            'Position',[0.312 0.432 0.038 0.036],'String','🔒','Value',0,'FontWeight','bold', ...
            'TooltipString',['KUNCI PANDANG axMain: bekukan area tampil (zoom/pan) sekarang supaya ' ...
            'TETAP saat ganti frame. Klik lagi (OFF): lepas kunci (kembali mengikuti ekstent penuh).'], ...
            'Callback',@(s,e) i_onAxMainViewLock(h.fig));
        % SEMBUNYIKAN tombol "🔒 Terkunci" garis PSG POT (shell h.btnLock) DI GRAIN4 SAJA
        % (fungsi onToggleLock TETAP ada; hanya GUI disembunyikan). Alasan: di GRAIN4
        % (pencatat DESKRIPSI) garis PSG sudah final -> klik tak sengaja tombol ini
        % membuka kunci garis -> tergeser -> sampling POT rusak & memicu warning
        % mode-manager. GRAIN5/GRAIN6 (shell shared) TAK terpengaruh.
        try
            if isfield(h,'btnLock') && ishghandle(h.btnLock)
                set(h.btnLock, 'Visible', 'off');
            end
        catch, end
        guidata(h.fig, h);
    catch
    end

    % --- State terpadu (SET SEBELUM i_buildTabs: builder membaca sebagian) ---
    % (Fase 1: sistem komentar/produksi-gambar/cerita + UI Net-slip DIBUANG.
    %  cdoc dipertahankan agar kontrak _comments.json GRAIN4 tetap dibaca/ditulis.)
    h.df=''; h.doc=[]; h.cdoc=[];
    h.activePsgId=''; h.selCurveLabel='';
    h.pts = pivcore.pot.snapPoints.emptyPts();
    h.activeHW=NaN; h.showNetslip=true; h.signConv='signed'; h.seedMsg='';
    h.poiRefs = {};        % token referensi paralel baris tabel POI
    h.selPoiTok = '';      % token POI terpilih
    % --- State SESAR (tab ① GRAIN5, fault-first) ---
    h.fdoc = [];           % dokumen sesar (pivcore.io.grain5Faults); diisi saat exp dimuat
    h.roiDetach = [];      % ROI garis bidang detachment (axMain; Tab ② pengukur sudut)
    h.roiFaultLine = [];   % ROI garis sesar utk hitung sudut (axMain; Tab ② pengukur sudut)
    % --- MODUL BIDANG SESAR PER-DX (GRAIN4; hotkey Ctrl+Q) ---
    %   Tiap baris DESKRIPSI (DX / titik pengamatan) punya BENTUK bidang sesarnya
    %   sendiri: polyline di axMain -> sudut (regresi) + panjang (cm), TERSIMPAN
    %   di BARIS DESC itu (_desc.json: vertices/angleDeg/lenCm). Growth per-DX =
    %   turunan antar-DX. TIDAK per-sesar lagi (_faultgeom.json dipensiunkan).
    h.roiFaultPoly   = [];     % ROI images.roi.Polyline di axMain (bidang sesar DX)
    h.faultPolyLabel = [];     % handle teks label metrik LIVE (axMain)
    h.faultPolyOn    = false;  % status modul aktif
    h.faultPolyDxIdx = [];     % indeks penuh BARIS DESC (DX) yg sedang diukur
    % --- TAPER ANGLE (kemiringan topografi) per-DX; hotkey 'w' ---------------
    %   Garis 2-titik di axMain (topografi permukaan) -> sudut relatif ref
    %   horizontal, disimpan ke BARIS DESC (taperVerts/taperDeg). Beda dari bidang
    %   sesar: ini kemiringan TOPOGRAFI. DX pertama F# = acuan (di-copy ke DX F#
    %   yg belum ber-taper). Interpolasi keyframe via engine grain4Interp (track
    %   terpisah), overlay hijau saat scrub.
    h.roiTaper       = [];     % ROI images.roi.Polyline (garis taper axMain)
    h.taperLabel     = [];     % handle teks label sudut taper LIVE
    h.taperOn        = false;  % status alat taper aktif
    h.taperDxIdx     = [];     % indeks penuh BARIS DESC (DX) yg sedang diukur
    % TITIK NUKLEASI (garis 2-titik; POI=NUC-FSR). Vertex-1 = posisi nukleasi;
    % vertex-2 = titik pd bidang sesar F-1. Jarak/kedalaman/jarak-F1 ke DX.
    h.roiNucPt       = [];     % ROI images.roi.Polyline (garis nukleasi axMain)
    h.nucPtLabel     = [];     % handle teks label metrik nukleasi LIVE
    h.nucPtOn        = false;  % status alat titik nukleasi aktif
    h.nucPtDxIdx     = [];     % indeks penuh BARIS DESC (DX) yg sedang diukur
    h.taperInterpOn  = true;   % interpolasi taper ALWAYS-ON (mesin latar; recompute event-driven)
    h.taperSamples   = containers.Map('KeyType','char','ValueType','any'); % sample interp taper per (psg|F#), MEMORI
    h.taperInterpDoc = pivcore.io.grain4TaperInterp.emptyDoc(''); % track taper LENGKAP per-frame (sidecar _taperinterp.json; kerja/evolusi)
    % INTERPOLASI evolusi bidang sesar antar-keyframe (engine grain4Interp; sidecar
    % _faultinterp.json). h.interpOn = tampilkan overlay evolusi (cyan) saat scrub.
    h.interpDoc      = pivcore.io.grain4Interp.emptyDoc('');
    h.interpOn       = true;    % overlay evolusi ALWAYS-ON (track dibaca dari sidecar _faultinterp.json yg sudah merekam terus). Tombol 🧬 Evolusi tetap bisa mematikan/menyalakan sementara.
    % DETEKSI (on-demand): map full-idx BARIS DESC -> string jumlah sesar aktif.
    % Kosong = belum dihitung (kolom Det tampil '·'). Diisi saat tombol 🔍 Deteksi.
    h.detMap         = containers.Map('KeyType','double','ValueType','char');
    % STICKY CTRL: tombol '⌃ Ctrl' -> hotkey tanpa tahan Control (hemat jari).
    h.stickyCtrl     = false;
    % Referensi horizontal (koreksi kemiringan kamera; ROI garis di axMain).
    h.roiRefHoriz    = [];     % ROI garis referensi
    h.refHorizOn     = false;  % status set-ref aktif
    h.refHorizLabel  = [];     % label sudut ref LIVE
    h.showRefHoriz   = true;   % overlay garis ref horizontal tersimpan (default ON)
    % REFERENSI GEOMETRI generik (dinding pembatas + base): garis 2-titik tersimpan
    % di meta _desc.json, alat toggle pola ref horizontal. Kind: 'limitWall'/'base'.
    h.roiMetaLine    = [];     % ROI garis referensi yg sedang di-edit
    h.metaLineKind   = '';     % kind aktif ('' = tak ada alat aktif)
    h.metaLineLabel  = [];     % label LIVE
    h.showLimitWall  = true;   % overlay dinding pembatas (default ON)
    h.showBaseRef    = true;   % overlay base (default ON)
    h.showIndenterInit = true; % overlay garis indenter awal (default ON)
    h.showModelBox   = true;   % overlay KOTAK MODEL 4-titik (default ON)
    h.boxCollect     = struct('active',false,'busy',false);  % state input 4-titik kotak (loupe)
    h.loupeAx        = [];     % axes kaca pembesar (loupe) saat input kotak
    h.activeFaultId = '';  % id sesar aktif ('' = belum ada)
    h.faultIds = {};       % id sesar paralel baris tabel sesar (= alias h.faultSlots)
    h.faultAssignTo = 'hw';% target klik kurva berikutnya: 'hw' | 'fw' (mode tempel cepat)
    h.subIds = {};         % id sub-fault paralel baris tabel (sinkron h.faultIds; '' utk baris F utama)
    % --- Model "slot spreadsheet" (rombak tabel sesar) ---
    h.faultSlots = {};     % id per-BARIS tabel ('' = baris kosong); sumber urutan tampil.
                           %   Baris X yang user ketik TETAP di posisi X (tak reorder).
                           %   Panjang >=15. Murni UI-state: TIDAK ditulis ke _faults.json.
    h.faultEditMode = false; % KUNCI penomoran: OFF=tolak duplikat nomor; ON=izinkan
                           %   duplikat (tukar-nukar). Keluar Edit -> auto-sort by nomor.
                           %   SF DINONAKTIFKAN sementara: sesar hanya bernomor 1,2,3,...
    % --- State fitur baru GRAIN5_temp (WAJIB sebelum builder tab membacanya) ---
    h.poiMarkerScale = 0.85;  % skala ukuran titik POI di axPOT (tombol ▲/▼); default diperkecil 1 tingkat
    h.psgLineWidth   = 1.0;   % tebal garis PSG di axMain (tipis; kontrol di bawah save)
    h.psgMarkerSize  = 6;     % ukuran titik/marker ujung garis PSG di axMain
    h.indMarkerSize  = 4;     % ukuran titik INDIKATOR (HW/FW axMain + seleksi kurva axPOT); spinner di baris klik
    h.zoneAlpha      = 0.45;  % transparansi fill zona/area sesar (naik: pastel dulu tak terlihat)
    % --- ZOOM + KUNCI PANDANG axMain (GRAIN5; eksperimen sangat panjang) ---------
    % Zoom/pan interaktif pada axMain + bekukan XLim/YLim supaya area pandang TETAP
    % saat ganti frame (render axMain reset ke ekstent penuh tiap frame; kita
    % re-apply view beku via hook afterRenderMain). Handle tombol dibuat di baris
    % strip shell (samping "Plot: axMain") tapi milik GRAIN5.
    h.axMainViewLock = false; % kunci pandang aktif -> pertahankan view tiap render
    h.axMainViewLim  = [];    % [xl(1) xl(2) yl(1) yl(2)] view beku (kosong = full)
    h.axMainZoomOn   = false; % mode zoom/pan interaktif sedang aktif (toggle)
    h.axMainLockLsnr = [];    % listener MarkedClean axMain (anti-FLICKER kunci pandang):
                              % re-set XLim/YLim ke view beku SEBELUM axes di-paint tiap
                              % render -> frame ZOOM-PENUH renderMain tak pernah muncul.
    % --- Mode XMAX N-frame AXSLIP (stretch horizontal kurva slip F#) ------------
    % Window frame AXSLIP di-batasi N frame di sekitar rentang START..END sesar
    % aktif (pusat = tengah START..END; clamp [1..nF]) -> kurva slip ter-stretch
    % horizontal utk mengamati detail slip F#. 0/Inf = Penuh (1..nF). Tombol di TAB②.
    h.slipXMax = 0;   % 0 = Penuh; else 50/100/150/200 (lebar window frame)
    h.helpLines = @() i_hotkeyList();   % hook: kolom kiri mode HELP -> daftar hotkey
    h.commitCancel = false;             % flag STOP proses Commit (tombol Cancel)
    h.zonePalette    = 'ngejreng'; % DEFAULT ngejreng (jenuh/terang); 'lembut'=pastel (user: pastel tak kelihatan)
    h.selCurveColor  = [0 0.70 0]; % warna sorot kurva terpilih (HIJAU; dibaca shell highlightSelPOT)
    h.showAllFaults  = false; % tampilkan SEMUA sesar (HW/FW + fill pastel) di axPOT
    h.hideAllFaults  = false; % SEMBUNYIKAN semua sesar teridentifikasi di axPOT (toggle 👁/🚫)
    h.showAllSlip    = false; % AXSLIP: net-slip SEMUA sesar bertumpuk (vs 1 sesar)
    h.faultLabelOn   = true;  % label area sesar aktif (checkbox)
    h.faultLabelPos  = 'top'; % posisi label area: 'center' (di tengah fill) | 'top' (melayang atas)
    h.maOn           = false; % moving average kurva POT (checkbox; default OFF)
    h.maWin          = 1;     % GRAIN4: MA window (1 = OFF; 2,3,4,.. haluskan). Spinner DESC.
    % --- AUTO — DX: cut-off net-slip (AXSLIP) utk auto-assign FS-max ------------
    % Ambang horizontal (satuan net-slip AXSLIP = px/frame). Kurva net-slip sesar
    % AKTIF yg MEMOTONG garis ambang -> tiap segmen (ns>=cutoff) diberi 2 DX FS-max
    % (frame masuk & keluar potongan). Spinner ▲/▼ langkah 0.1 (Ctrl+Shift+↑/↓).
    % Garis horizontal ambang divisualkan di AXSLIP saja. Default 2.0.
    h.axslipCutoff   = 2.0;   % ambang net-slip (px/frame) utk auto FS-max
    % --- Zoom horizontal axPOT (eksplorasi samping utk eksperimen panjang) ---
    %   potXWin = lebar jendela X (frame) yang tampil; 0/Inf = penuh (semua frame).
    %   potXCenter = frame pusat jendela. Saat seleksi F -> rata-kiri ke START-nya.
    h.potXWin        = 0;     % 0 = penuh; else N frame lebar jendela tampil
    h.potXPct        = 100;   % lebar jendela X dalam PERSEN total frame (100=penuh; cycle 5%)
    h.potXCenter     = NaN;   % frame pusat jendela (NaN = auto/tengah)
    h.clickCurveOn   = true;  % seleksi klik axPOT: KURVA aktif (checkbox, default ON)
    h.clickFrameOn   = true;  % seleksi klik axPOT: FRAME aktif (checkbox, default ON)
    % --- BUFFER area sampling POT (fitur baru GRAIN5_temp) ---
    % 0 = mati (sampling 1D di garis, = perilaku GRAIN4/GRAIN5 lama). k>0 = pita 2D:
    % lebar band = 2k baris offset (± k) pada arah NORMAL garis PSG, jarak antar
    % offset = spacing (nodeSpacing grid PIV). Nilai POT = rata-rata seluruh band
    % (area-average) -> lebih akurat utk sesar miring (posisi pengamatan lebih luas).
    % Dibaca shell collectPOT (via scalarOr; GRAIN4 tanpa field -> 0 -> jalur lama).
    h.bufferMult     = 0;     % DEFAULT MATI (tanpa buffer; sampling 1D di garis PSG).
    % --- L-GRID PSG (garis PSG acuan L1 + N garis di bawahnya utk export AXPOT) ---
    % Bukti sampling PSG dekat permukaan = info paling kaya. L1 = garis acuan; L2..Ln
    % dibuat TEMPORER di bawah L1 (offset tegak-lurus), buffer DIPAKSA OFF (1-D),
    % lalu export axPOT tiap L (satuan dunia nyata) + 1 axMain gabungan. Garis asli
    % user DIRESTORE sesudah export; L2..Ln TAK masuk h.doc.psgLines (tak mengotori).
    h.minFwWin       = 20;    % lebar zona (frame) di belakang MaxNS utk cari min FW (MinFW; spinner 5..60)
    h.nucTWin        = 40;    % lebar zona (frame) di belakang NUC-D utk cari titik belok NUC-T (spinner 10..100)
    h.refPsgId       = '';    % id garis PSG acuan L1 ('' = belum di-set)
    h.lgridN         = 3;     % jumlah garis PSG di bawah L1 (spinner, min 1)
    h.lgridDy        = 10;    % spasi antar-garis px (spinner, increment 10, min 10)
    h.lgridPreviewOn = false; % status kunci: Preview aktif -> tombol POT Export enabled
    h.lgridLines     = {};    % daftar geometri L1..Ln (tiap sel = [p1; p2]) hasil Preview
    % (DIBUANG: state "GENERATE N garis PSG PERMANEN" — genRefId/genN/genDy. GRAIN4 =
    %  PEMBACA garis; tak membuat garis. Multi-PSG dibuat di GRAIN3a/GRAIN5.)
    % --- SCOPING FAULT per-PSG (GRAIN5_temp_2) ----------------------------------
    % h.fdoc tetap 1 dokumen per-eksperimen; tiap fault.psgId = id garis pemiliknya.
    % Tabel sesar (h.tblFault) & slot HANYA menampilkan fault milik h.activePsgId.
    % h.faultSlots -> per-PSG lewat map ini (key = sanitasi psgId; value = cellstr slot).
    h.faultSlotsByPsg = struct();  % struct keyed by sanitized psgId -> cell slot ids (UI-state)
    % MATIKAN auto-load eksperimen pertama saat buka: user WAJIB memilih exp
    % secara manual di daftar kiri (permintaan user). Shell rescan hormati flag ini.
    h.noAutoLoadExp  = true;
    % Kolom EXTRA di tabel eksperimen (kiri): jumlah F# TERIDENTIFIKASI (punya HW
    % ATAU FW) + jumlah F# CHECKLIST (POI lengkap = ✓ biru). Baca _faults.json
    % tiap exp. Shell fillTable panggil hook ini per-baris (+ '__names__' utk judul).
    h.expTableExtra  = @(df) i_expFaultCounts(df);
    % Hook transformasi tampil kurva (moving average) -> dibaca shell dispYV.
    h.curveTransform = @(yv) i_maApply(h.fig, yv);

    % Simpan state ke figure DULU supaya callback builder (i_dispCtrls dst yang
    % baca/tulis guidata) konsisten, lalu bangun tab.
    guidata(h.fig, h);
    h = i_buildTabs(h);

    % --- Kontrol BUFFER (popup di strip tengah, sebelah "Spacing px") ---
    %     Ditempel ke figure (shell GRAIN4 tak diubah). Handle strip shell sudah ada.
    h = i_buildBufferCtrl(h);

    guidata(h.fig, h);
    set(h.fig, 'CloseRequestFcn', @(s,e) i_onClose(s));
    set(h.fig, 'WindowKeyPressFcn', @(s,e) i_onKeyPress(s, e));   % hotkey frame Ctrl+,/. & POI Ctrl+1..4
    i_syncAutoDxBtns(h.fig);   % grup AUTO — DX mulai DISABLED (view default = pot)
    i_selectTab(h, initTab);
    pivui.grain4Shell.setRoot(h.fig, rootDir);
    % --- Maximize window saat buka (skip di mode senyap tes agar tak rebut fokus) ---
    if ~pivui.quiet()
        try, set(h.fig, 'WindowState', 'maximized'); catch, end
    end
    if nargout > 0, figOut = h.fig; end
end


% =====================================================================
% GRAIN4: panel kanan = SATU panel DESKRIPSI (tanpa tab). Sistem assign GRAIN5
% (tab Anlz/Dip/Export/Help) DILEPAS. Panel berisi: selektor garis PSG +
% tabel sesar READ-ONLY (navigasi F) + tabel DESKRIPSI (Excel-like) + 3
% tombol aksi (Save Progress / Commit / Edit di GRAIN5).
% =====================================================================
function h = i_buildTabs(h)
    h = i_buildDescPanel(h, h.pnlR);
end

% --- Stub kompat tab (GRAIN4 tak punya tab; fungsi ini dipanggil hook shell) ---
function i_onTabChanged(fig) %#ok<DEFNU>
    % GRAIN4: tak ada tab -> segarkan tabel sesar + render (render sesar SELALU
    % tampil). Dipertahankan agar hook lama yang memanggilnya tak error.
    h = guidata(fig);
    i_clearGhostLine(fig);
    i_syncFaultSlipBtn(fig);
    i_refreshFaultTab(fig);
    pivui.grain4Shell.drawSampleMarker(fig);
end

function tf = i_onExportTab(~)
%I_ONEXPORTTAB  GRAIN4 tak punya tab Export -> selalu false.
    tf = false;
end

function i_syncTabIndicators(fig)
%I_SYNCTABINDICATORS  GRAIN4: hanya panel deskripsi. Sample marker kurva aktif
%   ON; titik observasi HW-model OFF (render sesar gambar titik sendiri).
    h = guidata(fig);
    h.showSampleMarker = true;
    h.showObsPoints    = false;
    guidata(fig, h);
end

function tf = i_onFaultTab(~)
%I_ONFAULTTAB  GRAIN4 tak punya tab Dip -> selalu false.
    tf = false;
end

function tf = i_faultVisible(~)
%I_FAULTVISIBLE  GRAIN4: render sesar (HW/FW + fill + titik POI + marker garis
%   PSG) SELALU tampil (hanya ada 1 panel; tak ada tab yang menyembunyikan).
    tf = true;
end

function i_selectTab(~, ~)
%I_SELECTTAB  GRAIN4: no-op (tak ada tab).
end


% =====================================================================
% GRAIN4 — PANEL DESKRIPSI (pengganti semua tab GRAIN5)
%   Selektor garis PSG (navigasi) · tabel sesar READ-ONLY (seleksi F) ·
%   tabel DESKRIPSI (Excel-like, 6 kolom) · 3 tombol aksi.
% =====================================================================
function opts = i_poiOptions()
%I_POIOPTIONS  Opsi dropdown POI (skema NUC-*/PRP-*; BDF pecah BDF0/BDF1) +
%   LIFECYCLE FSR: NUC-FSR (FSR_len=0) -> PRP-FSR (mulai terbentuk, ukur) ->
%   ACT-FSR (aktif/maks, ukur; boleh beberapa POI) -> X-FS (FSR_len=0, berhenti).
%   Warna: FSR=merah · TF=cokelat · BDF0=biru · BDF1=hijau · ACT-FSR=ungu ·
%   Start/X-FS=hitam (sel tabel abu2). Hotkey (+Shift utk fase PRP):
%     Ctrl+1 NUC-BDF1 · Ctrl+2 NUC-TF · Ctrl+3 NUC-FSR · Ctrl+4 ACT-FSR ·
%     Ctrl+Shift+1 PRP-BDF1 · Ctrl+Shift+2 PRP-TF · Ctrl+Shift+3 PRP-FSR ·
%     Ctrl+Shift+4 X-FS · Ctrl+T </blank>. TRX via dropdown. INTERPOLASI evolusi
%   bidang sesar = ALWAYS-ON (recompute otomatis saat keyframe di-commit via Ctrl+Q).
%   (Nama lama FS-max/FS-x dimigrasi -> ACT-FSR/X-FS.)
    opts = {'</blank>', ...
        'Start', ...   % awal aktivitas sesar
        'NUC-FSR','NUC-TF','NUC-BDF0','NUC-BDF1', ...   % NUC-FSR = FSR nukleasi (len 0)
        'PRP-FSR','PRP-TF','PRP-BDF0','PRP-BDF1', ...   % PRP-FSR = FSR mulai terbentuk (ukur)
        'ACT-FSR', ...  % FSR AKTIF/maksimum (ungu, garis penuh; ukur) — Ctrl+4
        'X-FS', ...    % FSR BERHENTI aktif (hitam; len 0) — Ctrl+Shift+4
        'TRX'};   % transisi: hand-off antar imbrikasi (frame=awal, F TRX=akhir)
end

function h = i_buildDescPanel(h, P)
    WHITE = [1 1 1]; fig = h.fig;

    % --- (0) GRUP "AUTO — DX": auto-assign FS-max dari cut-off net-slip AXSLIP --
    %   Aktif HANYA saat plot AXSLIP tampil (potView='slip'). Auto FS-max: kurva
    %   net-slip sesar aktif yg memotong garis ambang -> tiap segmen (ns>=cutoff)
    %   diberi 2 DX FS-max (frame masuk & keluar). Clear = hapus semua FS-max F#
    %   aktif. Spinner cut-off (default 2.0, langkah 0.1; Ctrl+Shift+↑/↓).
    % NB (2026-07-19): grup "AUTO — DX" + selektor "Garis PSG" + tombol Aktifkan/
    %   Slip/Zoom/Reset + X-win + MA DISEMBUNYIKAN atas permintaan user (garis PSG
    %   sudah dibaca otomatis; panel difokuskan ke tabel sesar + deskripsi). Handle
    %   TETAP dibuat ('Visible','off') supaya callback/hotkey/logika lain tak patah.
    %   Tabel sesar dinaikkan mepet atas + tabel deskripsi dipertinggi mengisi ruang.
    %   TETAP TAMPIL: ⇄ Ref horizontal, ⌃ Ctrl sticky, ◀F/F▶ (dipindah ke baris atas).
    h.btnAutoFsMax = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.940 0.40 0.026],'String','⚡ Auto ACT-FSR','Visible','off', ...
        'FontSize',8,'FontWeight','bold','ForegroundColor',[0.30 0.15 0.55], ...
        'TooltipString',['Auto-assign DX FS-max pada sesar AKTIF: tiap segmen kurva net-slip ' ...
        'yang MELEWATI garis cut-off diberi 2 FS-max (frame masuk & keluar potongan). ' ...
        'Hanya aktif saat plot AXSLIP tampil (tombol Slip F#).'], ...
        'Callback',@(s,e) i_onAutoFsMax(fig));
    h.txtAxslipCut = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.565 0.940 0.075 0.024],'String',sprintf('%.1f', h.axslipCutoff),'Visible','off', ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8, ...
        'TooltipString','Ambang net-slip (px/frame) utk auto FS-max. Langkah 0.1. Hotkey: Ctrl+Shift+↑/↓.');
    i_spinBtns(P, fig, 0.645, 0.940, @() i_onAxslipCutStep(fig,+1), @() i_onAxslipCutStep(fig,-1), 'spAxslipCut');
    set(findobj(P,'Tag','spAxslipCutUp','-or','Tag','spAxslipCutDn'),'Visible','off');
    h.btnClearFsMax = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.76 0.940 0.22 0.026],'String','🧹 Clear ACT-FSR','Visible','off', ...
        'FontSize',8,'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus SEMUA baris DX FS-max pada sesar AKTIF (garis PSG aktif). Hanya aktif saat AXSLIP tampil.', ...
        'Callback',@(s,e) i_onClearFsMax(fig));

    % --- (1) SELEKTOR garis PSG (DISEMBUNYIKAN; handle tetap utk logika lain) --
    h.lstLines = uicontrol('Parent',P,'Style','listbox','Units','normalized', ...
        'Position',[0.02 0.816 0.38 0.092],'String',{}, 'FontSize',8,'Visible','off', ...
        'TooltipString','Garis PSG ber-ID exp aktif. Klik → bayangan posisi; Aktifkan untuk pindah (tabel F & deskripsi ikut ganti).', ...
        'Callback',@(s,e) i_onPickLine(fig));

    % --- (1b) KONTROL garis PSG (Aktifkan/Zoom/Slip + X-win + MA) DISEMBUNYIKAN -
    h.btnFaultSlip = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.72 0.882 0.26 0.026],'String','Slip F#','Value',0,'FontSize',8,'Visible','off', ...
        'TooltipString','Toggle AXSLIP (net-slip HW−FW) sesar aktif <-> axPOT. Hotkey: Ctrl+F.', ...
        'Callback',@(s,e) i_onToggleFaultSlip(fig));
    % MA text (nilai dibaca oleh i_descMaWin refresh) — handle tetap, disembunyikan.
    h.txtDescMA = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.79 0.822 0.045 0.022],'String',sprintf('%d', i_descMaWin(h)),'Visible','off', ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8, ...
        'TooltipString','Window moving-average kurva POT. 1 = OFF; 2,3,4,.. = haluskan.');

    % --- (2) TABEL SESAR read-only (navigasi seleksi F#) — NAIK mepet atas ----
    % LAYOUT (2026-07-14, geometri per-DX): tabel RINGKAS 3 kolom TAMPIL:
    %   F# / DX (jumlah baris deskripsi) / Len# (jumlah DX yg SUDAH punya bidang
    %   sesar tergambar). Geometri (sudut/panjang/growth) kini PER-DX di tabel
    %   DESKRIPSI, bukan per-sesar. Sel MERAH: DX<4 (kol 2) + Len#=0 (kol 3).
    % NAIK mepet atas (2026-07-19): mengisi ruang bekas grup AUTO-DX/Garis PSG.
    %   Baris judul + navigasi di y 0.968; tabel di [0.812..0.962] (lebih tinggi).
    h.tblFault = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.02 0.812 0.42 0.150], ...
        'ColumnName',{'F#','DX',sprintf('Len#'), ...
                      [char(952) '0 °'],[char(952) '1 °'],[char(952) char(772) ' °'], ...
                      sprintf('Tp0\n°'),sprintf('Tp1\n°'),[char(916) 'Tp']}, ...
                      ... % 4=θ0(awal) · 5=θ1(akhir) · 6=θ̄(rata2) · 7=taper awal · 8=akhir · 9=change
        'ColumnWidth',{34 34 40 40 40 44 38 38 40}, ...
        'ColumnEditable',[false false false false false false false false false],'RowName',[],'FontSize',8, ...
        'CellSelectionCallback',@(s,e) i_onPickFaultRow(fig, e));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.02 0.970 0.30 0.016],'String','Sesar (klik → aktif):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',8);
    % --- Navigasi SESAR (F#) fisik: ◀F prev · F▶ next (= hotkey Ctrl+M / Ctrl+/) ---
    h.btnFaultPrev = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.315 0.968 0.055 0.020],'String','◀ F','FontSize',8,'FontWeight','bold', ...
        'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString','Sesar SEBELUMNYA (F#). Sama dgn hotkey Ctrl+M.', ...
        'Callback',@(s,e) i_stepFault(fig, -1));
    h.btnFaultNext = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.372 0.968 0.055 0.020],'String','F ▶','FontSize',8,'FontWeight','bold', ...
        'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString','Sesar BERIKUTNYA (F#). Sama dgn hotkey Ctrl+/.', ...
        'Callback',@(s,e) i_stepFault(fig, +1));
    % --- STICKY CTRL: tahan Control "menempel" supaya tak perlu tahan terus. ON:
    %     hotkey huruf/angka polos (q/w/1..4/dst) diperlakukan seolah +Ctrl. ---
    h.btnStickyCtrl = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.432 0.968 0.085 0.020],'String','⌃ Ctrl','Value',0,'FontSize',8, ...
        'FontWeight','bold','ForegroundColor',[0.55 0.15 0.15], ...
        'TooltipString',['TAHAN CONTROL menempel: ON = tekan hotkey TANPA menahan Ctrl ' ...
        '(q=Ctrl+Q, 1..4=Ctrl+1..4, dst). Hemat jari. Tetap bisa +Shift utk varian PRP. ' ...
        'OFF = perlu tahan Ctrl spt biasa.'], ...
        'Callback',@(s,e) i_onToggleStickyCtrl(fig));
    % ================================================================
    %   PANEL REFERENSI GEOMETRI (floating, VERTIKAL di kanan tabel sesar).
    %   Tabel sesar dipersempit ke kiri (x<=0.44); panel ini isi ruang kanan.
    %   SUMBER UTAMA = KOTAK MODEL (4 titik): pendorong=kiri · pembatas=kanan ·
    %   base=bawah · ref horizontal=atas. Ref horizontal manual = override sudut
    %   kamera. Tebal model (cm) = skala Y.
    % ================================================================
    rgX  = 0.455;              % kiri panel
    rgBW = 0.400;              % lebar tombol
    rgCX = rgX + rgBW + 0.010; % kiri checkbox
    rgCW = 0.115;              % lebar checkbox
    rgH  = 0.026;              % tinggi baris
    rgY  = @(i) 0.958 - (i-1)*(rgH+0.006);   % baris i dari atas
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[rgX rgY(0)+0.004 rgBW+rgCW+0.02 0.016], ...
        'String','— Referensi geometri (kotak model 4 titik) —','FontSize',7, ...
        'FontAngle','italic','HorizontalAlignment','left', ...
        'ForegroundColor',[0.35 0.35 0.40],'BackgroundColor',get(P,'BackgroundColor'));
    % (1) KOTAK MODEL 4-titik (sumber tunggal semua referensi)
    h.btnModelBox = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[rgX rgY(1) rgBW rgH],'String','⬚ Kotak model (4 klik)','Value',0,'FontSize',8, ...
        'FontWeight','bold','ForegroundColor',[0.45 0.20 0.65], ...
        'TooltipString',['KOTAK MODEL: klik 4 titik sudut BERURUT clockwise dari KIRI-ATAS ' ...
        '(kiri-atas → kanan-atas → kanan-bawah → kiri-bawah). Sumber TUNGGAL semua referensi: ' ...
        'sisi KIRI = dinding pendorong (X0, datum jarak nukleasi), KANAN = dinding pembatas ' ...
        '(Lpos, kalibrasi cmPerPx via L0), ATAS = ref horizontal (datum kedalaman), BAWAH = base. ' ...
        'Klik lagi utk RESET & input dari 0. Jarak nukleasi & kedalaman auto-hitung ulang.'], ...
        'Callback',@(s,e) i_onToggleModelBox(fig));
    h.chkShowModelBox = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[rgCX rgY(1) rgCW rgH],'String','tampil','Value',1,'FontSize',7, ...
        'ForegroundColor',[0.45 0.20 0.65],'BackgroundColor',get(P,'BackgroundColor'), ...
        'TooltipString','Tampilkan kotak model tersimpan (overlay semua frame). Default ON.', ...
        'Callback',@(s,e) i_onToggleShowModelBox(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[rgX rgY(2) 0.12 rgH],'String','🗑 Hapus kotak','FontSize',7, ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus kotak model (kembali ke garis manual / fallback).', ...
        'Callback',@(s,e) i_onClearModelBox(fig));
    % (2) Ref horizontal MANUAL (opsional; override sudut kamera + posisi bila kotak
    %     miring tak sesuai horizon). Kalau kotak ada, atas-kotak jadi default datum.
    h.btnRefHoriz = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[rgX+0.135 rgY(2) rgBW-0.135 rgH],'String','⇄ Ref horizontal (manual)','Value',0,'FontSize',7, ...
        'ForegroundColor',[0.10 0.45 0.20], ...
        'TooltipString',['OVERRIDE REFERENSI HORIZONTAL (koreksi kemiringan kamera). ON: garis ' ...
        'draggable (tersimpan ditampilkan). Tekan lagi KUNCI sudut+posisi. Dipakai utk SUDUT ' ...
        'sesar; kedalaman nukleasi pakai SISI ATAS kotak model bila kotak ada.'], ...
        'Callback',@(s,e) i_onToggleRefHoriz(fig));
    h.chkShowRefHoriz = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[rgCX rgY(2) rgCW rgH],'String','tampil','Value',1,'FontSize',7, ...
        'ForegroundColor',[0.10 0.45 0.20],'BackgroundColor',get(P,'BackgroundColor'), ...
        'TooltipString','Tampilkan garis ref horizontal manual tersimpan. Default ON.', ...
        'Callback',@(s,e) i_onToggleShowRefHoriz(fig));
    % (3) Ketebalan model (cm) — skala Y (tinggi base->permukaan)
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[rgX rgY(3)+0.002 0.24 0.020],'String','Tebal model (cm):','FontSize',8, ...
        'HorizontalAlignment','left','BackgroundColor',get(P,'BackgroundColor'), ...
        'ForegroundColor',[0.20 0.20 0.55]);
    h.edModelThick = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[rgX+0.245 rgY(3) 0.10 rgH],'String','4','FontSize',8, ...
        'BackgroundColor',[1 1 1], ...
        'TooltipString','Ketebalan model (cm; default 4) = tinggi lapisan pasir base->permukaan (skala Y). meta.modelThicknessCm.', ...
        'Callback',@(s,e) i_onSetModelThick(fig));
    % --- Baris tombol DI BAWAH tabel (0.778): Loncat · 📐Bidang · 🗑Hapus · 🧬Evolusi
    %     · Report A/B. Baris KEDUA (0.749): 📐Taper(w) · 🗑Taper · 🧬Interp taper.
    %     (2026-07-19: kedua baris NAIK +0.148 mengisi ruang bekas grup atas.) --
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.778 0.13 0.028],'String','⤓ Loncat POI', ...
        'FontSize',8,'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString','Loncat frame aktif ke POI berikutnya (siklik) sesar terseleksi. Hotkey: J/K/L/; (Ctrl+H/O kini = cycle antar DX).', ...
        'Callback',@(s,e) i_onJumpPoi(fig));
    h.btnFaultPoly = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.155 0.778 0.165 0.028],'String','📐 Bidang sesar','Value',0,'FontSize',8, ...
        'ForegroundColor',[0.15 0.15 0.15], ...
        'TooltipString',['INPUT BIDANG SESAR utk BARIS DESKRIPSI (DX) terpilih. Tiap titik ' ...
        'pengamatan punya bentuk+sudut+panjang sesarnya SENDIRI. axMain loncat ke frame DX; ' ...
        'gambar polyline HITAM (klik vertex, Enter selesai). LIVE: Sudut (regresi, relatif ref ' ...
        'horizontal) + Panjang (cm). Tekan lagi utk KUNCI & simpan ke baris DX (_desc.json). ' ...
        'Growth per-DX = (Len[n]-Len[n-1])/(Δframe·dt) dihitung otomatis. Hotkey: Ctrl+Q.'], ...
        'Callback',@(s,e) i_onToggleFaultPoly(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.325 0.778 0.13 0.028],'String','🗑 Hapus bidang','FontSize',8, ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus bidang sesar (vertices/sudut/panjang) BARIS DESKRIPSI (DX) terpilih.', ...
        'Callback',@(s,e) i_onClearFaultPoly(fig));
    % Alat TITIK NUKLEASI (SEMUA baris POI NUC-* + X-FS): 1 titik.
    h.btnNucPt = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.460 0.778 0.150 0.028],'String','🎯 Titik nukleasi','Value',0,'FontSize',8, ...
        'ForegroundColor',[0.10 0.45 0.55], ...
        'TooltipString',['INPUT TITIK (1 TITIK) utk BARIS DESKRIPSI (DX) ber-POI NUC-* ' ...
        '(NUC-FSR/NUC-TF/NUC-BDF0/NUC-BDF1) atau X-FS. Klik SATU titik di axMain = posisi titik. Sistem ' ...
        'catat: jarak HORIZONTAL ke dinding pendorong (datum X kotak model, proyeksi sumbu ' ...
        'shortening, cmPerPx kalibrasi X0/Lpos) & kedalaman tegak-lurus ke ref horizontal (cm). ' ...
        'Kolom "Nuk" jadi ✓. Tekan lagi utk KUNCI. Hotkey: Ctrl+R.'], ...
        'Callback',@(s,e) i_onToggleNucPt(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.615 0.778 0.055 0.028],'String','🗑','FontSize',8, ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus titik nukleasi (garis 2-titik) BARIS DESKRIPSI (DX) terpilih.', ...
        'Callback',@(s,e) i_onClearNucPt(fig));
    % Baris KEDUA (y=0.749): alat TAPER (kemiringan topografi) per-DX.
    h.btnTaper = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.02 0.749 0.125 0.026],'String','📐 Taper (⌃W)','Value',0,'FontSize',8, ...
        'ForegroundColor',[0.10 0.45 0.20], ...
        'TooltipString',['INPUT TAPER (kemiringan TOPOGRAFI) utk BARIS DESKRIPSI (DX) terpilih. ' ...
        'axMain loncat ke frame DX; gambar garis HIJAU 2-titik sepanjang permukaan topografi. ' ...
        'LIVE: sudut (relatif ref horizontal). Tekan lagi (atau Ctrl+W) utk KUNCI & simpan ke DX. ' ...
        'Gaya After Effects: DX kosong + interpolasi taper AKTIF -> garis DI-COPY dari INTERPOLASI ' ...
        '(edit=keyframe baru; commit auto-recompute frame antara). Hotkey: Ctrl+W.'], ...
        'Callback',@(s,e) i_onToggleTaper(fig));
    h.btnTaperGrab = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.150 0.749 0.115 0.026],'String','🔗 Grab (⌃G)','Value',0,'FontSize',8, ...
        'ForegroundColor',[0.55 0.30 0.05], ...
        'TooltipString',['GRAB keyframe taper TERDEKAT (kontinuitas topografi; hotkey Ctrl+G): ' ...
        'topografi KONTINU tapi jendela pengamatan per-sesar. Buka -> ROI di-SEED dari keyframe ' ...
        'taper terdekat, PRIORITAS F# SENDIRI dulu (mis. loncat ke POI pertama, grab dari frame ' ...
        'akhir sesar ini yg sudah digambar); bila F# aktif belum ada taper -> ambil dari F# LAIN ' ...
        '(zona overlap). Sesuaikan lalu Ctrl+G/Ctrl+W lagi = KUNCI ke DX F# AKTIF (+auto-recompute ' ...
        'interp taper). Pilih baris DX F# aktif dulu.'], ...
        'Callback',@(s,e) i_onToggleTaperGrab(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.270 0.749 0.055 0.026],'String','🗑','FontSize',8, ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus taper (kemiringan topografi) BARIS DESKRIPSI (DX) terpilih.', ...
        'Callback',@(s,e) i_onClearTaper(fig));
    % Interpolasi taper kini ALWAYS-ON (mesin latar; recompute saat commit/hapus taper).
    % Label non-interaktif sbg penanda (bukan tombol). Overlay HIJAU MUDA (F# aktif) +
    % bayangan ABU (F# tetangga overlap) muncul otomatis saat scrub bila ada >=2 keyframe.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.330 0.747 0.130 0.026],'String','🧬 Interp taper: auto', ...
        'FontSize',7,'ForegroundColor',[0.10 0.45 0.55],'HorizontalAlignment','left', ...
        'BackgroundColor',get(P,'BackgroundColor'), ...
        'TooltipString',['INTERPOLASI keyframe taper antar-DX = ALWAYS-ON (tanpa tombol/hotkey). ' ...
        'Isi taper >=2 DX (mis. awal & akhir F# via Ctrl+W/Ctrl+G) -> frame antara otomatis ' ...
        'di-interpolasi linear; overlay garis HIJAU (F# aktif) + bayangan PINK CERAH putus-putus ' ...
        '(F# tetangga yg overlap, label F# di tengah garis) saat scrub sbg panduan kontinuitas. Ctrl+W di frame antara ' ...
        'AUTO-SEED dari interpolasi. Status strip menunjukkan jumlah keyframe taper F# aktif ' ...
        '(butuh >=2 utk interpolasi). Recompute event-driven (commit/hapus/load); sample di memori.']);
    % --- DETEKSI: hitung otomatis jumlah sesar AKTIF per frame (on-demand) ---
    h.btnDeteksi = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.46 0.749 0.175 0.026],'String','🔍 Deteksi','FontSize',8, ...
        'FontWeight','bold','ForegroundColor',[0.35 0.15 0.55], ...
        'TooltipString',['DETEKSI: hitung OTOMATIS jumlah sesar AKTIF di tiap frame DX ' ...
        '(garis PSG aktif), menggantikan hitungan mata. Aturan: batas NUC PERTAMA & ' ...
        'X-FS EKSKLUSIF, frame di antaranya INKLUSIF (aktif). Di frame NUC sesar belum ' ...
        'terbentuk; di frame X-FS sesar sudah mati; sesar tanpa NUC tak dihitung. Klik = ' ...
        'baca ulang SEMUA DX & isi kolom Det. Baris di mana #ACT F (manual) BEDA dari ' ...
        'Det -> sel #ACT F ditandai MERAH.'], ...
        'Callback',@(s,e) i_onRunDeteksi(fig));
    % Interpolasi evolusi bidang sesar kini ALWAYS-ON (mesin latar; recompute saat
    % keyframe di-commit via Ctrl+Q). Label non-interaktif sbg penanda (bukan tombol).
    % Overlay CYAN (F# aktif) + BAYANGAN MERAH (sesar lain yg masih hidup) muncul
    % otomatis saat scrub bila ada >=2 keyframe supervised.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.46 0.776 0.125 0.028],'String','🧬 Evolusi: auto', ...
        'FontSize',7,'ForegroundColor',[0.10 0.45 0.55],'HorizontalAlignment','left', ...
        'BackgroundColor',get(P,'BackgroundColor'), ...
        'TooltipString',['INTERPOLASI evolusi bidang sesar antar-KEYFRAME supervised = ALWAYS-ON ' ...
        '(tanpa tombol/hotkey). Gambar bidang di beberapa frame keyframe (mis. PRP-FSR di awal + ' ...
        'ACT-FSR menjelang X-FS via Ctrl+Q; jumlah vertex sama) -> sistem ISI frame di antaranya ' ...
        '(interpolasi linear per-vertex) & tampilkan overlay CYAN otomatis saat scrub. Gaya ' ...
        'After Effects: di frame antara, Ctrl+Q meng-COPY bentuk interpolasi jadi ROI editable — ' ...
        'kalau diedit lalu dikunci, jadi keyframe SUPERVISED baru & interpolasi antar-keyframe ' ...
        'terdekat OTOMATIS menyesuaikan. Keyframe unsupervised (frame antara) ikut supervised ' ...
        'terdekat. Track di sidecar _faultinterp.json (tabel DESKRIPSI tetap bersih). ' ...
        'BONUS: sesar LAIN yg masih hidup (PRP-FSR..X-FS) di frame ini ditampilkan ' ...
        'sbg BAYANGAN MERAH putus-putus (copy bentuk ACT-FSR terakhir) — visual aid hitung ' ...
        'sesar aktif; TIDAK ikut perhitungan/ekspor.']);
    % --- REPORT A/B: generator PDF ber-pola (C-F placeholder dibuang dari UI) ---
    %   Output -> folder PAB4_export/<exp>/. Tombol Cancel bertumpuk (pola Commit).
    h.btnReportA = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.59 0.778 0.12 0.028],'String','Report A','FontSize',8,'FontWeight','bold', ...
        'ForegroundColor',[0.15 0.35 0.15], ...
        'TooltipString',['Report A: 1 halaman "Summary" 4-panel (semua frame). ' ...
            'Kiri-atas axPOT raw (spaghetti) · kanan-atas +HW/FW semua F#+fill · ' ...
            'kiri-bawah +garis DX (arsir FS-max→FS-max per sesar) · kanan-bawah AXSLIP ' ...
            'semua sesar+garis DX. PDF -> PAB4_export/<exp>/.'], ...
        'Callback',@(s,e) i_onReportA(fig));
    h.btnReportB = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.72 0.778 0.12 0.028],'String','Report B','FontSize',8,'FontWeight','bold', ...
        'ForegroundColor',[0.15 0.35 0.15], ...
        'TooltipString',['Report B: 1 halaman 4-panel per DX (SEMUA POI). ' ...
            'axPOT+AXSLIP (highlight sesar & FRAME DX aktif, garis merah tebal di POI itu) + ' ...
            'AX main velmag/shear. PDF -> PAB4_export/<exp>/.'], ...
        'Callback',@(s,e) i_onReportB(fig));
    % Tombol Cancel Report (tersembunyi; muncul saat Report B berjalan).
    h.btnReportBCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.85 0.778 0.13 0.028],'String','✖ Batal Report', ...
        'FontSize',8,'ForegroundColor',[0.7 0 0],'Visible','off', ...
        'TooltipString','Hentikan Report B yang sedang berjalan.', ...
        'Callback',@(s,e) i_onReportBCancel(fig));

    % --- (3) TABEL DESKRIPSI (Excel-like) ------------------------------------
    % LAYOUT (2026-07-13): seluruh blok deskripsi + tombol DINAIKKAN mengisi ruang
    % kosong di bawah tabel sesar (dulu 0.548, kini 0.600) + tabel DIPENDEKKAN ~2
    % baris (0.256 -> 0.196) supaya baris "MP4 selesai…"/tombol bawah TAK terpotong.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.02 0.721 0.50 0.022],'String','TABEL DESKRIPSI (nested per-F# saat filter):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    % Toggle FILTER nested per-F#: ON = hanya baris F# terpilih; OFF = semua baris.
    h.btnDescFilter = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.53 0.720 0.22 0.024],'String','⧉ Filter F#','Value',1,'FontSize',8, ...
        'TooltipString',['ON: tabel deskripsi HANYA menampilkan baris F# yang sedang terpilih ' ...
        '(nested). OFF: tampilkan SEMUA baris garis PSG aktif (termasuk tanpa F#).'], ...
        'Callback',@(s,e) i_onToggleDescFilter(fig));
    h.txtDescFilter = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.76 0.721 0.22 0.020],'String','Filter: —', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.30 0.30 0.55]);
    poiOpt = i_poiOptions();
    % Kolom (11) — GEOMETRI SESAR PER-DX (2026-07-14): F#/FRM (auto) · POI (dropdown,
    % diperlebar) · # ACT F · IS/OOST (numerik manual, default 1) · NUC POS (dropdown
    % —/T/M/B/FT/ALL) · PRP DIR (dropdown UP/DWN/both/SIM; field internal `fsrDir`) ·
    % SUDUT (°, read-only) · LEN (cm, read-only) · GROWTH (cm/s, read-only) ·
    % DESC (teks lisan). Sudut/Len/Growth = geometri bidang sesar DX itu (Ctrl+Q).
    % Kolom "F TRX" DIBUANG dari UI (field `fTrx` engine TETAP; via row-struct saja).
    % Semua angka pencatatan 4 desimal (hemat byte JSON).
    % Indeks: 1 F# · 2 FRM · 3 POI · 4 #ACT F · 5 IS/OOST · 6 NUC POS · 7 PRP DIR ·
    %         8 SUDUT · 9 LEN · 10 GROWTH · 11 DESC.
    % TABEL DIPERTINGGI (2026-07-19): tinggi 0.226 -> 0.374 (bottom tetap 0.342;
    % atas 0.568 -> 0.716) mengisi ruang bekas grup AUTO-DX/Garis PSG yg disembunyikan.
    % Tombol di bawah tabel (Tambah/Hapus/urut + Save/Commit + Next/Prev EXP) TETAP.
    h.tblDesc = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.02 0.342 0.96 0.374], ...
        'ColumnName',{'F#','FRM','POI','Det','# ACT F',sprintf('IS/\nOOST'),sprintf('NUC\nPOS'),sprintf('PRP\nDIR'),sprintf('Sud\n°'),sprintf('Len\ncm'),sprintf('Grw\ncm/s'),sprintf('Tpr\n°'),'Nuk','DESC'}, ...
        'ColumnWidth',{27 20 96 22 23 40 40 48 34 40 46 34 26 'auto'}, ...   % Det ≈2 char (22); POI +3 char (96); Nuk=✓ (26)
        'ColumnFormat',{'char','numeric',poiOpt,'char','numeric','numeric',{'—','T','M','B','FT','ALL'},{'—','UP','DWN','both','SIM'},'char','char','char','char','char','char'}, ...
        'ColumnEditable',[false false true false true true true true false false false false false true],'RowName',[],'FontSize',8, ...
        'CellEditCallback',@(s,e) i_onDescCellEdit(fig, e), ...
        'CellSelectionCallback',@(s,e) i_onDescPickRow(fig, e));
    % Baris tombol tabel: tambah / hapus / urut (dinaikkan mengikuti tabel).
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.306 0.44 0.028],'String','➕ Tambah baris (F# & FRM auto)', ...
        'FontWeight','bold','ForegroundColor',[0 0.45 0],'FontSize',8, ...
        'TooltipString','Tambah baris: F# = sesar aktif, FRM = frame yang tampil, POI auto-menyesuaikan (bisa diubah). Hotkey: Ctrl+T.', ...
        'Callback',@(s,e) i_onDescAddRow(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.47 0.306 0.15 0.028],'String','🗑 Hapus', ...
        'ForegroundColor',[0.7 0 0],'FontSize',8, ...
        'TooltipString','Hapus baris deskripsi terpilih. Hotkey: Ctrl+Shift+D (Backspace kerap dimakan fokus tabel).', ...
        'Callback',@(s,e) i_onDescDelRow(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.63 0.306 0.11 0.028],'String','↑', 'FontSize',8, ...
        'TooltipString','Naikkan baris terpilih.', ...
        'Callback',@(s,e) i_onDescMoveRow(fig,-1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.75 0.306 0.11 0.028],'String','↓', 'FontSize',8, ...
        'TooltipString','Turunkan baris terpilih.', ...
        'Callback',@(s,e) i_onDescMoveRow(fig,+1));
    % 🧨 Hapus SEMUA DX (baris deskripsi garis PSG aktif) — KONFIRMASI 3x.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.87 0.306 0.11 0.028],'String','🧨 ALL', ...
        'FontWeight','bold','ForegroundColor',[0.7 0 0],'FontSize',8, ...
        'TooltipString',['HAPUS SEMUA baris deskripsi (DX) untuk garis PSG yang aktif. ' ...
        'Ada 3x konfirmasi berturut sebelum dieksekusi. Tidak menghapus commit/ekspor, hanya isi tabel DESC.'], ...
        'Callback',@(s,e) i_onDescClearAll(fig));

    % --- (4) STATUS + TOMBOL AKSI (3 baris) — DITURUNKAN mepet batas bawah GUI --
    %   (2026-07-16) mengikuti tabel DESC yang dipertinggi +4 baris; baris tombol
    %   terbawah + Next/Prev EXP menempel ke dasar kolom kanan.
    h.txtDescStatus = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.02 0.272 0.96 0.024],'String','—', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.20 0.40 0.20]);
    % Baris 1: Save Progress | Sumbu cm (GRAINAXCAL)
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.228 0.62 0.038],'String','💾 Save Progress', ...
        'FontWeight','bold','FontSize',10,'BackgroundColor',[0.90 0.95 0.90], ...
        'TooltipString','Simpan tabel deskripsi ke <base>_desc.json (semua garis PSG). Bisa dilanjutkan sesi berikutnya.', ...
        'Callback',@(s,e) i_onSaveDescProgress(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.228 0.32 0.038],'String','⤢ Sumbu cm (GRAINAXCAL)', ...
        'FontSize',9,'BackgroundColor',[0.90 0.92 0.98], ...
        'TooltipString',['Buka GRAINAXCAL utk kalibrasi sumbu cm (X=Cummulative Shortening, ' ...
        'Y=Height) + segitiga indenter. Hasil (_axcal.json) dipakai saat Commit ekspor AX main.'], ...
        'Callback',@(s,e) i_onOpenAxCal(fig));
    % Checkbox: hapus SEMUA commit sebelumnya (export bersih) sebelum generate baru.
    h.chkCleanExport = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.02 0.188 0.62 0.024],'String','⚠ Hapus SEMUA commit lama exp ini sebelum generate (export bersih)', ...
        'Value',0,'BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.65 0 0], ...
        'TooltipString','ON: seluruh folder PAB4_DESC/<exp>/ dihapus dulu (semua versi commit lama) sebelum ekspor baru. Ada 2x konfirmasi.');
    % 🎬 Export MP4 AX main (velmag + shear, SEMUA frame). INPUT = TARGET DURASI
    % (detik) -> fps dihitung otomatis = nF / durasi. Label + edit box (kiri) +
    % tombol (kanan) + Cancel bertumpuk di atas tombol.
    % Baris MP4 (KOMPAK, 1 baris): "MP4 dur(s):" + edit + 🎬 exp ini + 🎬 semua.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.66 0.206 0.10 0.018],'String','MP4 dur(s):', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.10 0.40 0.15]);
    h.edMovieDur = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.76 0.202 0.05 0.026],'String','30', ...
        'BackgroundColor',[1 1 1],'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString',['Target durasi video (detik). fps dihitung otomatis = jumlah frame / durasi. ' ...
        'Mis. 348 frame, durasi 30 s -> 11.6 fps. Kosong/0 -> pakai 5 fps.']);
    % Dua tombol MP4: kiri = exp AKTIF, kanan = SEMUA exp. Keduanya pakai target
    % durasi dari kotak kiri (fps per-exp = nFrame/durasi). Cancel bersama.
    h.btnMovie = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.815 0.202 0.082 0.028],'String','🎬 exp ini', ...
        'FontWeight','bold','FontSize',8.5,'BackgroundColor',[0.86 0.94 0.86],'ForegroundColor',[0.10 0.40 0.15], ...
        'TooltipString',['Ekspor AX main (velmag + shear) SEMUA frame EKSPERIMEN AKTIF -> 2 file MP4 ' ...
        '(velmag.mp4 & shear.mp4) ke folder ber-versi PAB4_DESC/<exp>/<ts>_<garisPSG>_mp4/. ' ...
        'fps dari target durasi di kotak kiri. Memakai tampilan LIVE (GS + glyph + CLim + sumbu cm).'], ...
        'Callback',@(s,e) i_onExportMovie(fig));
    h.btnMovieAll = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.899 0.202 0.081 0.028],'String','🎬 semua', ...
        'FontWeight','bold','FontSize',8.5,'BackgroundColor',[0.80 0.90 0.80],'ForegroundColor',[0.08 0.34 0.13], ...
        'TooltipString',['Ekspor MP4 AX main (velmag + shear) untuk SEMUA eksperimen di folder ini. ' ...
        'Tiap exp dimuat bergiliran (semua frame) lalu di-ekspor ke folder ber-versi masing-masing. ' ...
        'Target durasi di kotak kiri SAMA untuk tiap video (fps menyesuaikan jumlah frame tiap exp).'], ...
        'Callback',@(s,e) i_onExportMovieAll(fig));
    h.btnMovieCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.76 0.202 0.22 0.028],'String','✖ CANCEL', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[1.0 0.85 0.85],'ForegroundColor',[0.6 0 0], ...
        'Visible','off', 'TooltipString','Hentikan pembuatan MP4 yang sedang berjalan (file parsial dihapus).', ...
        'Callback',@(s,e) i_onMovieCancel(fig));
    % Baris GAMBAR per-bingkai: "Frame img:" + edit rentang + 🖼 Ekspor frame.
    % Rentang: kosong=frame kini, "N"=1 frame, "A-B"/"A:B"=rentang. Tiap frame ->
    % 2 JPG (velmag + shear) memakai tampilan LIVE (kolom tengah), ke folder
    % ber-versi PAB4_DESC/<exp>/<ts>_<garisPSG>_frames/.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.66 0.180 0.10 0.018],'String','Frame img:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.30 0.15 0.55]);
    h.edFrameRange = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.735 0.176 0.043 0.026],'String','', ...
        'BackgroundColor',[1 1 1],'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString',['Rentang bingkai untuk ekspor gambar. Kosong = bingkai kini. ' ...
        '"12" = satu bingkai. "5-20" atau "5:20" = rentang. Di-clamp ke [1..jumlah frame].']);
    % Tiga tombol GAMBAR: rentang (dari kotak) | semua bingkai exp AKTIF |
    % semua bingkai SEMUA exp. Ketiganya pakai setelan tampilan (kolom tengah)
    % yang sama saat tombol ditekan. Cancel bersama (bertumpuk menutupi ketiga).
    h.btnFrameImg = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.780 0.176 0.063 0.028],'String','🖼 rentang', ...
        'FontWeight','bold','FontSize',7.5,'BackgroundColor',[0.90 0.86 0.98],'ForegroundColor',[0.30 0.15 0.55], ...
        'TooltipString',['Ekspor AX main tiap bingkai di RENTANG (kotak kiri) -> 2 JPG (velmag + shear) ke ' ...
        'PAB4_DESC/<exp>/<ts>_<garisPSG>_frames/. Memakai tampilan LIVE (GS + glyph + CLim + sumbu cm), ' ...
        'sama seperti MP4. Kosong = bingkai yang sedang tampil.'], ...
        'Callback',@(s,e) i_onExportFrameImg(fig));
    h.btnFrameExp = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.845 0.176 0.063 0.028],'String','🖼 exp ini', ...
        'FontWeight','bold','FontSize',7.5,'BackgroundColor',[0.86 0.80 0.96],'ForegroundColor',[0.26 0.12 0.50], ...
        'TooltipString',['Ekspor SEMUA bingkai (1..akhir) EKSPERIMEN AKTIF -> 2 JPG per bingkai ' ...
        '(velmag + shear). Setelan tampilan (kolom tengah) sama seperti saat ditekan.'], ...
        'Callback',@(s,e) i_onExportFramesExpCur(fig));
    h.btnFrameAllExp = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.910 0.176 0.070 0.028],'String','🖼 semua exp', ...
        'FontWeight','bold','FontSize',7.5,'BackgroundColor',[0.80 0.72 0.94],'ForegroundColor',[0.22 0.10 0.46], ...
        'TooltipString',['Ekspor SEMUA bingkai (1..akhir) untuk SEMUA eksperimen yang dimuat dari folder ini. ' ...
        'Tiap exp dimuat bergiliran lalu di-ekspor ke folder ber-versi masing-masing. ' ...
        'Setelan tampilan (kolom tengah) SAMA untuk semua exp.'], ...
        'Callback',@(s,e) i_onExportFramesAllExp(fig));
    h.btnFrameImgCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.735 0.176 0.245 0.028],'String','✖ CANCEL — hentikan ekspor gambar', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[1.0 0.85 0.85],'ForegroundColor',[0.6 0 0], ...
        'Visible','off', 'TooltipString','Hentikan ekspor gambar yang sedang berjalan (berhenti di bingkai berikutnya).', ...
        'Callback',@(s,e) i_onFrameImgCancel(fig));
    % Baris 2: Commit (exp aktif) | Commit SEMUA exp | Cancel (bertumpuk)
    h.btnCommit = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.132 0.42 0.038],'String','✅ Commit (JSON, exp ini)', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.82 0.92 1.0],'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString',['Simpan + tulis JSON interpretasi + baris DESC ke folder ber-versi ' ...
        'PAB4_DESC/<exp>/<ddmmyy-HHMMSS>_<garisPSG>/ (garis PSG AKTIF, eksperimen AKTIF saja).'], ...
        'Callback',@(s,e) i_onCommitDesc(fig));
    h.btnCommitAll = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.45 0.132 0.19 0.038],'String','📦 Semua exp', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.80 0.88 1.0],'ForegroundColor',[0.10 0.20 0.55], ...
        'TooltipString',['Commit JSON untuk SEMUA eksperimen yang dimuat dari folder ini (mis. 4 exp). ' ...
        'Tiap exp dimuat bergiliran (frame-1 saja, bukan semua frame) lalu tiap garis PSG yang ' ...
        'punya baris deskripsi di-commit. Eksperimen & garis PSG semula dipulihkan setelah selesai.'], ...
        'Callback',@(s,e) i_onCommitAllExp(fig));
    h.btnCommitCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.132 0.62 0.038],'String','✖ CANCEL — hentikan Commit', ...
        'FontWeight','bold','FontSize',10,'BackgroundColor',[1.0 0.85 0.85],'ForegroundColor',[0.6 0 0], ...
        'Visible','off', 'TooltipString','Hentikan proses Commit yang sedang berjalan (folder sesi ini dihapus).', ...
        'Callback',@(s,e) i_onCommitCancel(fig));
    % 📄 Report PDF (+ Cancel bertumpuk, seperti Commit). Rakit 1 PDF landscape
    % Group A–E utk garis PSG aktif (exp aktif). Reuse mesin ekspor Commit.
    h.btnReport = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.132 0.32 0.038],'String','📄 Report PDF', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.88 0.86 0.98],'ForegroundColor',[0.30 0.15 0.55], ...
        'TooltipString',['Rakit 1 file PDF landscape (Group A–E: ringkasan axPOT, tabel DESC, ' ...
        'POI per-sesar, POI per-jenis, slip-rate & net-slip & dip) untuk garis PSG aktif. ' ...
        'Teks statis PDF Bahasa Inggris. Gambar antara + PDF disimpan ke folder ber-versi ' ...
        'PAB4_DESC/<exp>/<ts>_<garisPSG>_report/.'], ...
        'Callback',@(s,e) i_onExportReport(fig));
    h.btnReportCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.132 0.32 0.038],'String','✖ CANCEL Report', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[1.0 0.85 0.85],'ForegroundColor',[0.6 0 0], ...
        'Visible','off', 'TooltipString','Hentikan pembuatan Report PDF yang sedang berjalan.', ...
        'Callback',@(s,e) i_onReportCancel(fig));
    % Baris 3: Edit di GRAIN5 (kiri) | Save & Tutup | Tutup
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.078 0.31 0.038],'String','↔ Edit di GRAIN5', ...
        'FontSize',8,'BackgroundColor',[0.96 0.94 0.86], ...
        'TooltipString','Simpan deskripsi lalu buka GRAIN5 (folder sama) untuk mengedit assign HW/FW/POI/sudut.', ...
        'Callback',@(s,e) i_onGoGRAIN5(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 0.078 0.31 0.038],'String','💾 Save & Tutup', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.80 0.90 0.80], ...
        'TooltipString','Simpan tabel deskripsi ke _desc.json lalu tutup jendela GRAIN4.', ...
        'Callback',@(s,e) i_onSaveClose(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.68 0.078 0.30 0.038],'String','✖ Tutup', ...
        'FontSize',10,'BackgroundColor',[0.95 0.90 0.90], ...
        'TooltipString','Tutup jendela (progres deskripsi tetap di-flush otomatis ke disk).', ...
        'Callback',@(s,e) i_onClose(fig));

    % Baris 4 (DASAR GUI): navigasi eksperimen ◀ Prev EXP | Next EXP ▶.
    %   (2026-07-16) Pindah exp = auto-flush progres exp kini (garis PSG _potdata
    %   + tabel DESC _desc.json) lewat hook beforeLoad -> tabel deskripsi TAK
    %   hilang. i_onStepExp menyorot baris tabel kiri + memuat exp lewat shell.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.02 0.036 0.48 0.036],'String','◀ Prev EXP', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.90 0.93 0.98],'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString',['Muat eksperimen SEBELUMNYA di daftar. Progres exp kini ' ...
        '(garis PSG + tabel deskripsi _desc.json) disimpan otomatis dulu.'], ...
        'Callback',@(s,e) i_onStepExp(fig,-1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.036 0.46 0.036],'String','Next EXP ▶', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.90 0.93 0.98],'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString',['Muat eksperimen BERIKUTNYA di daftar. Progres exp kini ' ...
        '(garis PSG + tabel deskripsi _desc.json) disimpan otomatis dulu.'], ...
        'Callback',@(s,e) i_onStepExp(fig,+1));

    % State tabel deskripsi.
    h.descDoc     = pivcore.io.grain4Desc.emptyDoc('');   % dokumen DESC (semua PSG)
    h.descSelRow  = [];                                 % baris DESC terpilih (indeks TAMPIL)
    h.descZoomOn  = false;
    % FILTER nested per-F#: bila ON, tabel DESC HANYA menampilkan baris milik F#
    % yang sedang aktif (seleksi sesar). OFF = tampil semua baris garis PSG aktif.
    h.descFilterF = true;                               % default ON (nested per-F#)
    h.descVisIdx  = [];                                 % peta baris tampil -> indeks penuh
    guidata(fig, h);
end


% =====================================================================
% GRAIN4 — HANDLER TABEL DESKRIPSI
% =====================================================================
function poi = i_poiForFrame(~, ~)
%I_POIFORFRAME  Skema POI baru (NUC-*/PRP-*) tak berkorespondensi dgn frame POI
%   GRAIN5 (_faults.json) -> auto-suggest default '</blank>' (user pilih via hotkey
%   Ctrl+1..6 atau dropdown).
    poi = '</blank>';
end

function i_onDescAddRow(fig)
%I_ONDESCADDROW  Tambah baris deskripsi: F# = sesar aktif (uiNum), FRM = frame
%   live, psgId = garis PSG aktif, POI = auto-suggest dari _faults.json.
    i_addDescRow(fig, '');   % POI auto-suggest
end

function i_onDescAddRowPoi(fig, poiForced)
%I_ONDESCADDROWPOI  Tambah baris deskripsi dgn POI DIPAKSA = `poiForced` (hotkey
%   Ctrl+1..7/T). F# = sesar aktif, FRM = frame yang sedang tampil di AX main.
%   Perilaku sama seperti tombol tambah baris, tapi POI ditetapkan langsung.
    i_addDescRow(fig, poiForced);
end

function i_addDescRow(fig, poiForced)
%I_ADDDESCROW  Inti tambah baris. poiForced kosong -> POI auto-suggest dari
%   _faults.json; else POI = poiForced (dari hotkey).
%
%   ATURAN 1 FRAME = 1 BARIS DESKRIPSI (DX) per garis PSG aktif: bila frame live
%   SUDAH punya baris di tabel, TIDAK membuat baris baru — hanya MENGGANTI POI-nya
%   (bila poiForced diberikan; kolom lain dipertahankan). "State utama" = 1 DX
%   per frame; sub-state (deskripsi/FS/dll) dijelaskan di kolom lain. Contoh:
%   Frm 50 belum ada DX + Ctrl+3 -> baris baru POI=NUC-FSR (seperti Ctrl+T);
%   Frm 50 SUDAH ada DX + Ctrl+Shift+4 -> POI baris itu ganti jadi PRP-FSR.
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);   % simpan editan tabel dulu
    h.detMap = containers.Map('KeyType','double','ValueType','char'); guidata(fig, h); % struktur baris berubah -> Deteksi usang
    [f, idx] = pivui.grain5Model.activeFault(h);
    fNum = '';
    if idx >= 1
        fNum = i_uiNumStr(f);
        if ~isempty(fNum) && ~strcmp(fNum,'—'), fNum = ['F' fNum]; else, fNum = ''; end
    end
    if ~isempty(poiForced)
        poi = poiForced;                       % hotkey menetapkan POI langsung
    elseif idx >= 1
        poi = i_poiForFrame(f, h.frame);       % auto-suggest dari _faults.json
    else
        poi = '</blank>';
    end
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    % Cari DX yg SUDAH ada di (F#, frame) SAMA (garis PSG aktif). ATURAN: DX unik
    % per-F#+frame -> F# BEDA boleh punya frame yg SAMA (mis. F1 & F2 di frame 35).
    exIdx = 0;
    for k = 1:numel(rows)
        v = rows{k}.frame;
        sameFrame = isscalar(v) && isfinite(v) && round(v)==frameLive;
        sameF = strcmp(strtrim(rows{k}.fNum), strtrim(fNum));
        if sameFrame && sameF, exIdx = k; break; end
    end
    if exIdx > 0
        % (F#,frame) ini sudah punya DX -> JANGAN duplikat. Ganti POI (bila hotkey/
        % auto memberi POI ber-arti); pertahankan kolom lain (FS/DESC/actF/dll).
        r = rows{exIdx};
        changed = false;
        prevPoiU = upper(strtrim(char(r.poi)));   % POI SEBELUM diubah hotkey
        if ~isempty(poiForced)
            r.poi = poi; changed = true;         % hotkey: paksa ganti POI
        end
        % KOREKSI (2026-07-17): saat POI DIUBAH menjadi ACT-FSR dari POI lain (mis.
        % PRP-FSR) yang KEBETULAN sudah punya bidang tergambar, buang bidang asing itu
        % supaya baris ACT-FSR MULAI KOSONG -> Ctrl+Q akan seed dari INTERPOLASI (garis
        % biru), bukan bentuk PRP. WARISAN copy-from-previous-POI SUDAH DIPENSIUNKAN:
        % interpolasi = satu-satunya sumber bentuk baris kosong (lihat i_onToggleFaultPoly
        % + i_interpVertsAtFrameForFault). ACT-FSR->ACT-FSR (redraw) tetap: bila baris
        % SUDAH punya vertices sendiri, tak diusik.
        if strcmpi(strtrim(char(r.poi)),'ACT-FSR') && ~strcmp(prevPoiU,'ACT-FSR')
            r.vertices = zeros(0,2); r.angleDeg = NaN; r.lenCm = NaN;
        end
        rows{exIdx} = r;
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
        guidata(fig, h);
        i_refreshDescTable(fig);
        i_selectDescByFullIdx(fig, exIdx);   % petakan full-idx -> baris tampil
        i_renderPotKeepZoom(fig);
        if changed
            i_setDescStatus(fig, sprintf('Frame %d sudah ada DX -> POI diganti jadi %s (tak buat baris baru).', frameLive, poi));
        else
            i_setDescStatus(fig, sprintf('Frame %d sudah ada DX (baris %d dipilih).', frameLive, exIdx));
        end
        return;
    end
    % Belum ada DX di (F#,frame) ini -> baris baru: IS/OOST default '1', FS & F TRX kosong.
    r = pivcore.io.grain4Desc.rowStruct(h.activePsgId, fNum, frameLive, poi, NaN, '1', '', '', '', NaN);
    % CATATAN (2026-07-17): baris baru MULAI KOSONG (tanpa bidang sesar). Warisan
    % copy-from-previous-POI (i_applyActFsrInherit) DIPENSIUNKAN — dulu ACT-FSR baru
    % meng-copy vertices ACT-FSR terdekat di bawah TANPA menghormati garis biru
    % interpolasi, sehingga Ctrl+Q memunculkan bentuk previous, bukan interpolasi.
    % Kini INTERPOLASI = metode utama: Ctrl+Q pada baris kosong (interp aktif) seed
    % dari bentuk interpolasi @frame itu (i_interpVertsAtFrameForFault).
    rows{end+1} = r;
    rows = i_sortDescRowsByFrame(rows);   % SORT: frame rendah di ATAS, tinggi di bawah
    newFull = i_findDescRowIdx(rows, fNum, frameLive);   % posisi baris baru pasca-sort
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    guidata(fig, h);
    i_refreshDescTable(fig);
    i_selectDescByFullIdx(fig, newFull);   % petakan full-idx -> baris tampil
    i_renderPotKeepZoom(fig);   % garis vertikal penanda DESC muncul, ZOOM TAK reset
    i_setDescStatus(fig, sprintf('Baris ditambah: %s frame %d (POI %s). Isi kolom lalu Save/Commit.', ...
        pivui.grain5Fmt.orDash(fNum), frameLive, poi));
end

function i_onDescDelRow(fig)
%I_ONDESCDELROW  Hapus baris deskripsi terpilih. descSelRow = indeks baris TAMPIL;
%   dipetakan ke indeks PENUH via descVisIdx (kompat filter nested per-F#).
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    h.detMap = containers.Map('KeyType','double','ValueType','char'); guidata(fig, h); % struktur berubah -> Deteksi usang
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    fullIdx = i_descSelFullIdx(h);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        i_setDescStatus(fig, 'Pilih baris deskripsi dulu.'); return;
    end
    rows(fullIdx) = [];
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    h.descSelRow = [];
    guidata(fig, h);
    i_rebuildAllTaperTracks(fig);   % keyframe taper bisa hilang -> buang sample basi
    i_refreshDescTable(fig);
    i_renderPotKeepZoom(fig);   % update garis vertikal penanda DESC, ZOOM TAK reset
    i_setDescStatus(fig, 'Baris dihapus.');
end

function i_onDescClearAll(fig)
%I_ONDESCCLEARALL  Hapus SEMUA baris deskripsi (DX) untuk garis PSG AKTIF.
%   Konfirmasi 3x berturut sebelum eksekusi (batal di salah satu -> tak
%   ada perubahan). Hanya mengosongkan tabel DESC garis PSG aktif; TIDAK
%   menyentuh commit/ekspor, garis PSG lain, atau _faults.json.
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    n = numel(rows);
    if n == 0
        i_setDescStatus(fig, 'Tidak ada baris DX untuk dihapus.'); return;
    end
    if ~i_confirmClearAllDesc(n)
        i_setDescStatus(fig, 'Hapus semua DX dibatalkan.'); return;
    end
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, {});
    h.descSelRow = [];
    guidata(fig, h);
    i_rebuildAllTaperTracks(fig);   % semua keyframe taper PSG hilang -> buang sample basi
    i_refreshDescTable(fig);
    i_renderPotKeepZoom(fig);   % bersihkan garis vertikal penanda DESC (zoom tetap)
    i_setDescStatus(fig, sprintf('%d baris DX dihapus (garis PSG aktif).', n));
end

function ok = i_confirmClearAllDesc(n)
%I_CONFIRMCLEARALLDESC  Konfirmasi 3x sebelum hapus SEMUA DX. Headless (quiet)
%   -> anggap dikonfirmasi (tombol = niat eksplisit). Batal di mana pun -> false.
    ok = false;
    if pivui.quiet(), ok = true; return; end
    m1 = sprintf(['HAPUS SEMUA %d baris deskripsi (DX) untuk garis PSG aktif?\n\n' ...
        'Isi tabel DESC garis ini akan dikosongkan.'], n);
    b1 = questdlg(m1, '🧨 Hapus semua DX (1/3)', 'Ya, lanjut', 'Batal', 'Batal');
    if ~strcmp(b1,'Ya, lanjut'), return; end
    m2 = 'KONFIRMASI ke-2: yakin menghapus SEMUA baris deskripsi garis PSG ini?';
    b2 = questdlg(m2, '🧨🧨 Hapus semua DX (2/3)', 'Ya, yakin', 'Batal', 'Batal');
    if ~strcmp(b2,'Ya, yakin'), return; end
    m3 = 'KONFIRMASI TERAKHIR (3/3): tindakan ini TIDAK bisa dibatalkan. Hapus semua DX sekarang?';
    b3 = questdlg(m3, '🧨🧨🧨 Hapus semua DX (3/3)', 'Ya, hapus semua', 'Batal', 'Batal');
    ok = strcmp(b3,'Ya, hapus semua');
end

function i_onDescMoveRow(fig, d)
%I_ONDESCMOVEROW  Geser baris terpilih naik(-1)/turun(+1) dalam daftar PENUH.
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    fullIdx = i_descSelFullIdx(h);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows), return; end
    nx = fullIdx + d;
    if nx < 1 || nx > numel(rows), return; end
    rows([fullIdx nx]) = rows([nx fullIdx]);
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    h.descSelRow = [];
    guidata(fig, h);
    i_refreshDescTable(fig);
end

function i_onDescCycleFs(fig)
%I_ONDESCCYCLEFS  Ctrl+` = CYCLE kolom NUC POS baris DESC terpilih: —>T>M>B>FT>—.
%   (Top/Mid/Bottom/Fault-Tip.) Baris = descSelRow (via descVisIdx).
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    fullIdx = i_descSelFullIdx(h);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        i_setDescStatus(fig, 'Pilih baris deskripsi dulu (klik) untuk cycle NUC POS.'); return;
    end
    r = rows{fullIdx};
    seq = {'','T','M','B','FT','ALL'};
    cur = ''; if isfield(r,'nucPos'), cur = r.nucPos; end
    ix = find(strcmp(seq, cur), 1); if isempty(ix), ix = 1; end
    r.nucPos = seq{mod(ix,numel(seq))+1};   % —>T>M>B>FT>ALL>—
    rows{fullIdx} = r;
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    guidata(fig, h);
    i_refreshDescTable(fig);
    nm = r.nucPos; if isempty(nm), nm = '—'; end
    i_setDescStatus(fig, sprintf('NUC POS -> %s (hanya berarti pada POI NUC-FSR: T/M/B/FT/ALL = Top/Mid/Bottom/Fault-Tip/semua posisi).', nm));
end

function i_onDescCycleRow(fig, d)
%I_ONDESCCYCLEROW  Cycle seleksi baris tabel DESC (siklik). Hotkey Ctrl+O / Ctrl+H
%   = ke BAWAH (d=+1); Ctrl+Shift+H = ke ATAS (d=-1). Berbasis baris TAMPIL
%   (descVisIdx). Update descSelRow + seleksi uitable + LONCAT frame pengamatan ke
%   frame DX terpilih.
    if nargin < 2 || isempty(d), d = +1; end
    d = sign(d); if d == 0, d = +1; end
    h = guidata(fig);
    if ~(isfield(h,'tblDesc') && ishghandle(h.tblDesc)), return; end
    D = get(h.tblDesc,'Data');
    n = 0; if iscell(D), n = size(D,1); end
    if n < 1, i_setDescStatus(fig,'Belum ada baris deskripsi.'); return; end
    cur = 0;
    if isfield(h,'descSelRow') && isscalar(h.descSelRow) && h.descSelRow>=1, cur = round(h.descSelRow); end
    nx = cur + d;
    if nx > n, nx = 1; elseif nx < 1, nx = n; end   % wrap siklik dua arah
    h.descSelRow = nx; guidata(fig, h);
    i_highlightDescRow(fig);   % sorot baris + set Selection
    i_gotoSelDescFrame(fig);   % LONCAT frame pengamatan ke frame DX terpilih
    i_setDescStatus(fig, sprintf('Baris deskripsi terpilih: %d/%d.', nx, n));
end

function i_gotoSelDescFrame(fig)
%I_GOTOSELDESCFRAME  Loncat frame pengamatan (AX main) ke FRAME baris DESC (DX)
%   yang sedang terpilih (descSelRow -> full via descVisIdx). No-op bila frame
%   baris tak valid. Dipakai saat seleksi DX (klik / Ctrl+O / Ctrl+H).
    h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows), return; end
    v = rows{fullIdx}.frame;
    if ~(isscalar(v) && isfinite(v)), return; end
    target = max(1, min(round(v), max(h.nF,1)));
    try, pivui.grain4Shell.gotoFrame(fig, target); catch, end
end

function n = i_dxCountForFault(h, uiNum)
%I_DXCOUNTFORFAULT  Jumlah baris DESC (DX) utk sesar ber-uiNum di garis PSG aktif.
    n = 0;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    for k = 1:numel(rows)
        if strcmp(strtrim(rows{k}.fNum), tgt), n = n + 1; end
    end
end

function n = i_dxGeomCountForFault(h, uiNum)
%I_DXGEOMCOUNTFORFAULT  Jumlah baris DESC (DX) sesar ber-uiNum (garis PSG aktif)
%   yang SUDAH punya bidang sesar tergambar (vertices >= 2 titik).
    n = 0;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    for k = 1:numel(rows)
        if ~strcmp(strtrim(rows{k}.fNum), tgt), continue; end
        V = pivcore.io.grain4Desc.normVerts(rows{k}.vertices);
        if size(V,1) >= 2, n = n + 1; end
    end
end

function m = i_faultMeanAngle(h, uiNum)
%I_FAULTMEANANGLE  Rata-rata (θ̄) SEMUA sudut terukur DX sesar ber-uiNum (garis PSG
%   aktif): mean angleDeg baris ber-bidang (vertices>=2 & angleDeg finite). Sudut =
%   relatif ref horizontal (angleDegRelOf, seperti kolom Sud° DESC). NaN bila tak
%   ada sudut terukur.
    m = NaN;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    acc = [];
    for k = 1:numel(rows)
        if ~strcmp(strtrim(rows{k}.fNum), tgt), continue; end
        V = pivcore.io.grain4Desc.normVerts(rows{k}.vertices);
        if size(V,1) < 2, continue; end
        a = pivcore.io.grain4Desc.scal(rows{k}.angleDeg);
        if isscalar(a) && isfinite(a), acc(end+1) = a; end %#ok<AGROW>
    end
    if ~isempty(acc), m = mean(acc); end
end

function [a0, a1, aMean] = i_faultStartEndMeanAngle(h, uiNum)
%I_FAULTSTARTENDMEANANGLE  Sudut bidang sesar AWAL/AKHIR/RATA-RATA sesar ber-uiNum
%   (garis PSG aktif). Dari baris DESC (DX) F# yg PUNYA bidang (vertices>=2 &
%   angleDeg finite), urut FRAME menaik:
%     a0    = angleDeg DX frame TERKECIL (sudut AWAL) ·
%     a1    = angleDeg DX frame TERBESAR (sudut AKHIR) ·
%     aMean = rata-rata semua angleDeg terukur (= θ̄, konsisten i_faultMeanAngle).
%   Sudut relatif ref horizontal (angleDegRelOf, sama basis kolom Sud° DESC). NaN
%   bila tak ada DX ber-bidang. 1 DX -> a0=a1=aMean.
    a0 = NaN; a1 = NaN; aMean = NaN;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    fr = []; ang = [];
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmp(strtrim(char(r.fNum)), tgt), continue; end
        V = pivcore.io.grain4Desc.normVerts(r.vertices);
        if size(V,1) < 2, continue; end
        a = pivcore.io.grain4Desc.scal(r.angleDeg);
        if ~(isscalar(a) && isfinite(a)), continue; end
        v = r.frame; if ~(isscalar(v) && isfinite(v)), v = inf; end   % tanpa frame -> ke akhir
        fr(end+1) = v; ang(end+1) = a; %#ok<AGROW>
    end
    if isempty(ang), return; end
    [~, ord] = sort(fr); angS = ang(ord);
    a0 = angS(1); a1 = angS(end); aMean = mean(ang);
end

function [tp0, tp1, tpD] = i_taperStartEndChange(h, uiNum)
%I_TAPERSTARTENDCHANGE  Taper AWAL/AKHIR/CHANGE sesar ber-uiNum (garis PSG aktif).
%   Dari baris DESC (DX) F#, urut FRAME menaik:
%     tp0 = taper DX frame TERKECIL · tp1 = DX frame TERBESAR · tpD = tp1−tp0.
%   NaN bila tak ada DX ber-taper. 1 DX ber-taper -> tp0=tp1, tpD=0.
%
%   PENTING (permintaan user 2026-07-18): pakai NILAI TAPER YANG TAMPIL di kolom
%   T° tabel deskripsi — i_taperValueForRow (status 'super'=keyframe manual ATAU
%   'auto'=interpolasi) — BUKAN hanya r.taperDeg (yg finite hanya utk 'super').
%   Jadi kolom Tp0/Tp1/ΔTp langsung mengikuti angka T° yang tampil TANPA perlu
%   bikin keyframe taper manual dulu. (Dulu taper 'auto' -> r.taperDeg NaN -> Tp
%   sesar '—' walau T° tampil.)
    tp0 = NaN; tp1 = NaN; tpD = NaN;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    fr = []; tp = [];
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmp(strtrim(char(r.fNum)), tgt), continue; end
        a = i_taperValueForRow(h, r);      % nilai T° yang TAMPIL (super+auto)
        v = r.frame;
        if ~(isscalar(a) && isfinite(a)), continue; end
        if ~(isscalar(v) && isfinite(v)), v = inf; end   % tanpa frame -> ke akhir
        fr(end+1) = v; tp(end+1) = a; %#ok<AGROW>
    end
    if isempty(tp), return; end
    [~, ord] = sort(fr); tp = tp(ord);
    tp0 = tp(1); tp1 = tp(end); tpD = tp1 - tp0;
end

function rows = i_sortDescRowsByFrame(rows)
%I_SORTDESCROWSBYFRAME  Urutkan baris DESC menaik berdasar FRAME (rendah di ATAS,
%   tinggi di bawah). STABIL (frame sama pertahankan urutan asal). Baris tanpa
%   frame (NaN) ditaruh di AKHIR.
    n = numel(rows);
    if n < 2, return; end
    fr = zeros(1,n);
    for k = 1:n
        v = rows{k}.frame;
        if isscalar(v) && isfinite(v), fr(k) = v; else, fr(k) = inf; end
    end
    [~, ord] = sortrows([fr(:) (1:n)']);   % kunci-2 = indeks asal -> STABIL
    rows = rows(ord);
end

function idx = i_findDescRowIdx(rows, fNum, frame)
%I_FINDDESCROWIDX  Cari indeks baris DESC ber-(fNum, frame). 0 bila tak ketemu.
    idx = 0; fr = round(frame);
    for k = 1:numel(rows)
        v = rows{k}.frame;
        if isscalar(v) && isfinite(v) && round(v)==fr && strcmp(strtrim(rows{k}.fNum), strtrim(fNum))
            idx = k; return;
        end
    end
end

function i_selectDescByFullIdx(fig, fullIdx)
%I_SELECTDESCBYFULLIDX  Set seleksi baris DESC (descSelRow = baris TAMPIL) dari
%   indeks daftar PENUH `fullIdx`, via peta descVisIdx (kompat filter F#). Bila
%   baris itu tak tampil (terfilter) -> seleksi dikosongkan. Lalu sorot.
    h = guidata(fig);
    vis = []; if isfield(h,'descVisIdx'), vis = h.descVisIdx; end
    visRow = [];
    if isempty(vis)
        visRow = fullIdx;                 % tak terfilter: 1:1
    else
        p = find(vis == fullIdx, 1);
        if ~isempty(p), visRow = p; end
    end
    h.descSelRow = visRow; guidata(fig, h);
    i_highlightDescRow(fig);
end

function idx = i_descSelFullIdx(h)
%I_DESCSELFULLIDX  Petakan baris TAMPIL terpilih (descSelRow) -> indeks dalam
%   daftar PENUH via descVisIdx. Kosong bila tak ada seleksi valid.
    idx = [];
    r = []; if isfield(h,'descSelRow'), r = h.descSelRow; end
    if isempty(r) || ~isscalar(r) || r < 1, return; end
    vis = []; if isfield(h,'descVisIdx'), vis = h.descVisIdx; end
    if ~isempty(vis) && r <= numel(vis), idx = vis(r); else, idx = r; end
end

function i_onDescPickRow(fig, evt)
%I_ONDESCPICKROW  Simpan baris terpilih (untuk hapus/geser).
    h = guidata(fig);
    try
        if ~isempty(evt) && isprop(evt,'Indices') && ~isempty(evt.Indices)
            h.descSelRow = evt.Indices(1); guidata(fig, h);
            i_highlightDescRow(fig);   % sorot baris yg baru diklik
            i_gotoSelDescFrame(fig);   % loncat frame pengamatan ke frame DX itu
        end
    catch
    end
end

function i_onRunDeteksi(fig)
%I_ONRUNDETEKSI  Tombol 🔍 Deteksi (on-demand): baca ULANG semua baris DX garis PSG
%   aktif -> hitung jumlah sesar AKTIF di tiap frame DX (engine
%   grain4Desc.activeCountAtFrame) -> isi h.detMap (full-idx -> str) -> refresh tabel
%   (kolom Det terisi; sel #ACT F yg BEDA dari Det ditandai merah). Tiap klik =
%   recompute penuh dari awal (DX baru ikut terhitung).
    i_suspendAxZoomForRoi(fig);   % matikan MODE zoom (view tetap) sebelum render
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);   % pastikan editan tabel tersimpan
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc))
        i_setDescStatus(fig,'Belum ada data deskripsi.'); return;
    end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    detMap = containers.Map('KeyType','double','ValueType','char');
    nMismatch = 0;
    for k = 1:numel(rows)
        r = rows{k};
        fr = r.frame;
        if ~(isscalar(fr) && isfinite(fr)), detMap(k) = '·'; continue; end
        c = pivcore.io.grain4Desc.activeCountAtFrame(rows, fr);
        detMap(k) = sprintf('%d', c);
        % hitung berapa yg beda dgn #ACT F manual (utk pesan).
        a = pivcore.io.grain4Desc.scal(r.actF);
        if isfinite(a) && round(a) ~= c, nMismatch = nMismatch + 1; end
    end
    h.detMap = detMap; guidata(fig, h);
    i_refreshDescTable(fig);
    if nMismatch > 0
        i_setDescStatus(fig, sprintf(['Deteksi selesai: %d baris DX dihitung · %d baris ' ...
            '#ACT F BEDA dari Deteksi (ditandai MERAH — cek manual vs sistem).'], numel(rows), nMismatch));
    else
        i_setDescStatus(fig, sprintf('Deteksi selesai: %d baris DX dihitung · #ACT F cocok semua.', numel(rows)));
    end
    i_reclaimFigureKeys(fig);   % kembalikan fokus keyboard ke figure (hotkey Ctrl.. hidup lagi)
end

function i_onDescCellEdit(fig, ~)
%I_ONDESCCELLEDIT  Sel diedit -> tangkap ulang seluruh tabel ke descDoc, lalu
%   REFRESH tabel dari descDoc supaya AUTO-ASSIGN 2-arah PRP DIR<->NUC POS
%   (i_syncPrpNucPos di i_rowFromTableLine) TAMPIL: pilih NUC POS -> PRP DIR ikut
%   terisi otomatis (& sebaliknya) + sel merah wajib hilang. i_refreshDescTable
%   memanggil i_stylePoiCells (fill warna POI + penanda merah wajib).
    i_captureDescFromTable(fig);
    i_refreshDescTable(fig);       % gambar ulang dari descDoc -> auto-assign terlihat
end

function i_captureDescFromTable(fig)
%I_CAPTUREDESCFROMTABLE  Baca Data uitable DESC (yg mungkin TERFILTER per-F#) ->
%   MERGE kembali ke daftar baris penuh garis PSG aktif. Baris TERSEMBUNYI (filter)
%   DIPERTAHANKAN — hanya baris TAMPIL (h.descVisIdx) yang di-update. Aman multiline.
    h = guidata(fig);
    if ~(isfield(h,'tblDesc') && ishghandle(h.tblDesc)), return; end
    D = get(h.tblDesc,'Data');
    full = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    vis  = [];
    if isfield(h,'descVisIdx'), vis = h.descVisIdx; end
    nD = 0; if iscell(D), nD = size(D,1); end
    % Bila jumlah baris tampil == baris penuh & tak ada peta -> anggap tak terfilter.
    if isempty(vis) || numel(vis) ~= nD
        vis = 1:nD;    % fallback: petakan 1:1 (mode tak-terfilter)
    end
    for i = 1:nD
        idx = vis(i);
        prev = [];   % baris LAMA (utk pertahankan geometri + fTrx yg tak ada kolomnya)
        if idx >= 1 && idx <= numel(full), prev = full{idx}; end
        r = i_rowFromTableLine(D, i, h.activePsgId, prev);
        if idx >= 1 && idx <= numel(full)
            full{idx} = r;                 % update baris penuh yg berkorespondensi
        else
            full{end+1} = r; %#ok<AGROW>   % baris baru (mode tak-terfilter)
        end
    end
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, full);
    guidata(fig, h);
end

function r = i_rowFromTableLine(D, i, psgId, prev)
%I_ROWFROMTABLELINE  Rakit row-struct dari baris tabel ke-i (11 kolom). Kolom
%   TAMPIL: 1 F# · 2 FRM · 3 POI · 4 Det(RO) · 5 #ACT F · 6 IS/OOST · 7 NUC POS ·
%   8 PRP DIR · 9 Sudut(RO) · 10 Len(RO) · 11 Growth(RO) · 12 Tpr(RO) · 13 DESC.
%   Kolom read-only (Det/Sudut/Len/Growth/Tpr, fTrx/vertices) DIPERTAHANKAN dari
%   `prev` (baris lama) -> tak dibaca dari tabel (sumber = perhitungan/geometri).
    if nargin < 4, prev = []; end
    fNum = i_cellStr(D{i,1});
    frame = i_cellNum(D{i,2});
    poi  = i_cellStr(D{i,3}); if isempty(poi), poi = '</blank>'; end
    % kol 4 = Det (read-only, tak dibaca).
    actF = i_cellNum(D{i,5});
    isv  = i_cellNum(D{i,6}); if isfinite(isv), isO = num2str(isv); else, isO = ''; end   % IS/OOST manual
    np   = i_cellStr(D{i,7}); if strcmp(np,'—'), np = ''; end     % NUC POS T/M/B/FT
    fdir = i_cellStr(D{i,8}); if strcmp(fdir,'—'), fdir = ''; end  % PRP DIR UP/DWN/both
    % AUTO-ASSIGN 2-arah PRP DIR <-> NUC POS (isi yg KOSONG dari yg terisi).
    [fdir, np] = i_syncPrpNucPos(fdir, np);
    % kol 13 = Nuk (checklist, read-only, tak dibaca). DESC kini kolom 14.
    desc = i_cellStr(D{i,14});
    % fTrx tak punya kolom -> ambil dari baris lama.
    fTrx = NaN;
    if isstruct(prev) && isfield(prev,'fTrx'), fTrx = prev.fTrx; end
    r = pivcore.io.grain4Desc.rowStruct(psgId, fNum, frame, poi, actF, isO, desc, fdir, np, fTrx);
    % PERTAHANKAN geometri bidang sesar DX (vertices/angleDeg/lenCm) + TAPER
    % (taperVerts/taperDeg) dari prev (read-only; sumber = alat 'w' di axMain).
    if isstruct(prev)
        if isfield(prev,'vertices'), r.vertices = pivcore.io.grain4Desc.normVerts(prev.vertices); end
        if isfield(prev,'angleDeg'), r.angleDeg = pivcore.io.grain4Desc.scal(prev.angleDeg); end
        if isfield(prev,'lenCm'),    r.lenCm    = pivcore.io.grain4Desc.scal(prev.lenCm);    end
        if isfield(prev,'taperVerts'), r.taperVerts = pivcore.io.grain4Desc.normVerts(prev.taperVerts); end
        if isfield(prev,'taperDeg'),   r.taperDeg   = pivcore.io.grain4Desc.scal(prev.taperDeg);   end
        % TITIK NUKLEASI (read-only; sumber = alat 🎯 di axMain).
        if isfield(prev,'nucVerts'),    r.nucVerts    = pivcore.io.grain4Desc.normVerts(prev.nucVerts); end
        if isfield(prev,'nucDistCm'),   r.nucDistCm   = pivcore.io.grain4Desc.scal(prev.nucDistCm);   end
        if isfield(prev,'nucDepthPx'),  r.nucDepthPx  = pivcore.io.grain4Desc.scal(prev.nucDepthPx);  end
        if isfield(prev,'nucDepthCm'),  r.nucDepthCm  = pivcore.io.grain4Desc.scal(prev.nucDepthCm);  end
        if isfield(prev,'nucDistF1Cm'), r.nucDistF1Cm = pivcore.io.grain4Desc.scal(prev.nucDistF1Cm); end
    end
end

function [fdir, np] = i_syncPrpNucPos(fdir, np)
%I_SYNCPRPNUCPOS  Auto-assign 2-arah PRP DIR <-> NUC POS. Isi HANYA sisi yang
%   KOSONG dari sisi yang terisi (bila keduanya terisi / keduanya kosong -> apa
%   adanya). Pemetaan (permintaan user):
%     PRP DIR -> NUC POS :  UP->FT · both->M · DWN->T · SIM->ALL
%     NUC POS -> PRP DIR :  FT->UP · B->UP · M->both · T->DWN · ALL->SIM
    fdir = char(fdir); np = char(np);
    hasF = ~isempty(strtrim(fdir)); hasN = ~isempty(strtrim(np));
    if hasF && ~hasN                       % PRP DIR terisi -> isi NUC POS
        switch upper(strtrim(fdir))
            case 'UP',   np = 'FT';
            case 'BOTH', np = 'M';
            case 'DWN',  np = 'T';
            case 'SIM',  np = 'ALL';   % simultan -> nukleasi SEMUA posisi
        end
    elseif hasN && ~hasF                   % NUC POS terisi -> isi PRP DIR
        switch upper(strtrim(np))
            case 'FT',  fdir = 'UP';
            case 'B',   fdir = 'UP';
            case 'M',   fdir = 'both';
            case 'T',   fdir = 'DWN';
            case 'ALL', fdir = 'SIM';  % SEMUA posisi -> simultan
        end
    end
end

function s = i_descNumFmt(v, nd)
%I_DESCNUMFMT  Format angka -> string nd desimal; '' (sel kosong) bila NaN.
    if ~(isscalar(v) && isfinite(v)), s = ''; return; end
    s = sprintf('%.*f', nd, v);
end

function m = i_descGrowthMap(h, full)
%I_DESCGROWTHMAP  Peta full-idx -> string growth (cm/s, 4 desimal) tiap DX.
%   Dikelompokkan per-F#, urut FRAME menaik: growth[n]=(Len[n]-Len[n-1])/
%   (Δframe[n-1..n]*dt). DX pertama tiap F# (atau tanpa Len/frame) -> '' (kosong).
    m = containers.Map('KeyType','double','ValueType','char');
    for i = 1:numel(full), m(i) = ''; end   % default kosong
    dt = i_faultDtSec(h);
    % kelompokkan indeks per fNum.
    groups = containers.Map('KeyType','char','ValueType','any');
    for i = 1:numel(full)
        key = strtrim(full{i}.fNum); if isempty(key), key = '(none)'; end
        if isKey(groups,key), groups(key) = [groups(key) i]; else, groups(key) = i; end
    end
    ks = keys(groups);
    for gi = 1:numel(ks)
        idxs = groups(ks{gi});
        % urut frame menaik (NaN di akhir), STABIL.
        fr = zeros(1,numel(idxs));
        for t = 1:numel(idxs)
            v = full{idxs(t)}.frame; if isscalar(v) && isfinite(v), fr(t) = v; else, fr(t) = inf; end
        end
        [~, ord] = sortrows([fr(:) (1:numel(idxs))']);
        sIdx = idxs(ord);
        rowsSorted = full(sIdx);
        for t = 2:numel(sIdx)
            g = pivcore.io.grain4Desc.growthPerDx(rowsSorted, t, dt);
            m(sIdx(t)) = i_descNumFmt(g, 4);
        end
    end
end

function i_refreshDescTable(fig)
%I_REFRESHDESCTABLE  Isi uitable DESC dari descDoc utk garis PSG AKTIF. Bila FILTER
%   nested per-F# aktif (h.descFilterF) & ada sesar terpilih -> HANYA tampilkan
%   baris milik F# itu (nested di bawah F terseleksi). h.descVisIdx = peta baris
%   tampil -> indeks dalam daftar penuh (dipakai capture agar baris tersembunyi
%   tak hilang saat edit).
    h = guidata(fig);
    if ~(isfield(h,'tblDesc') && ishghandle(h.tblDesc)), return; end
    full = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    % Tentukan F# filter aktif.
    fFilter = ''; doFilter = false;
    if isfield(h,'descFilterF') && h.descFilterF
        [fa, ia] = pivui.grain5Model.activeFault(h);
        if ia >= 1
            u = i_uiNumStr(fa);
            if ~isempty(u) && ~strcmp(u,'—'), fFilter = ['F' u]; doFilter = true; end
        end
    end
    visIdx = [];
    for i = 1:numel(full)
        if doFilter && ~strcmp(strtrim(full{i}.fNum), fFilter), continue; end
        visIdx(end+1) = i; %#ok<AGROW>
    end
    % Growth per-DX (cm/s) di-precompute untuk SEMUA baris (peta full-idx->str),
    % dikelompokkan per-F# urut frame: growth[n]=(Len[n]-Len[n-1])/(Δframe*dt).
    growthMap = i_descGrowthMap(h, full);
    detMap = containers.Map('KeyType','double','ValueType','char');
    if isfield(h,'detMap') && isa(h.detMap,'containers.Map'), detMap = h.detMap; end
    n = numel(visIdx);
    D = cell(n, 14);
    taperStat = repmat({'empty'}, 1, n);   % status taper per baris (super/auto/empty)
    for j = 1:n
        fi = visIdx(j); r = full{fi};
        D{j,1} = r.fNum;                                             % 1 F#
        if isfinite(r.frame), D{j,2} = round(r.frame); else, D{j,2} = []; end  % 2 FRM
        D{j,3} = r.poi;                                             % 3 POI
        % 4 Det (DETEKSI otomatis; read-only). Hanya terisi setelah tombol 🔍 Deteksi
        % diklik (detMap full-idx -> str). Belum dihitung -> '·'.
        if isKey(detMap, fi), D{j,4} = detMap(fi); else, D{j,4} = '·'; end
        if isfinite(r.actF), D{j,5} = r.actF; else, D{j,5} = []; end % 5 #ACT F
        isv = str2double(r.isOost);                                 % 6 IS/OOST
        if isfinite(isv), D{j,6} = isv; else, D{j,6} = []; end
        np = ''; if isfield(r,'nucPos'), np = r.nucPos; end          % 7 NUC POS
        if isempty(np), D{j,7} = '—'; else, D{j,7} = np; end
        fd = ''; if isfield(r,'fsrDir'), fd = r.fsrDir; end          % 8 PRP DIR
        if isempty(fd), D{j,8} = '—'; else, D{j,8} = fd; end
        % 9 SUDUT · 10 LEN · 11 GROWTH (read-only; geometri bidang sesar DX).
        ang = NaN; if isfield(r,'angleDeg'), ang = r.angleDeg; end
        len = NaN; if isfield(r,'lenCm'),    len = r.lenCm;    end
        D{j,9}  = i_descNumFmt(ang, 4);
        D{j,10} = i_descNumFmt(len, 4);
        D{j,11} = growthMap(fi);
        % 12 TAPER (T°): supervised (taperVerts sendiri) -> angka + BIRU; kosong tapi
        % ada interpolasi (F# sendiri/tetangga) -> angka auto + HIJAU; benar2 kosong ->
        % MERAH. Status disimpan di taperStat{j} utk i_stylePoiCells (pewarnaan).
        [tdeg, tstat] = i_taperValueForRow(h, r);
        D{j,12} = i_descNumFmt(tdeg, 4);
        taperStat{j} = tstat; %#ok<AGROW>
        % 13 Nuk (CHECKLIST titik nukleasi; read-only). ✓ bila DX ini punya garis
        % nukleasi (nucVerts>=2). Angka jarak/kedalaman disimpan di _desc.json.
        nucP = []; if isfield(r,'nucVerts'), nucP = pivcore.io.grain4Desc.nucPointPx(r.nucVerts); end
        if ~isempty(nucP), D{j,13} = '✓'; else, D{j,13} = ''; end
        D{j,14} = r.desc;                                          % 14 DESC
    end
    set(h.tblDesc,'Data',D);
    h.descVisIdx = visIdx;
    h.descTaperStat = taperStat;   % status taper per baris TAMPIL (super/auto/empty)
    guidata(fig, h);
    i_highlightDescRow(fig);         % fill sel POI (FSR/TF/BDF) + sorot baris terpilih
    % Update label filter + PERINGATAN baris tersembunyi (bila filter F# aktif
    % menyembunyikan baris DESC di F# LAIN, tampilkan jelas supaya data tak pernah
    % TERLIHAT "hilang" — bug user 2026-07-17: kira save gagal, padahal baris ada
    % di F# lain & filter menyembunyikannya).
    nHidden = numel(full) - n;   % baris DESC garis PSG ini yg TAK tampil (F# lain)
    if isfield(h,'txtDescFilter') && ishghandle(h.txtDescFilter)
        if doFilter
            if nHidden > 0
                set(h.txtDescFilter, 'String', ...
                    sprintf('Filter %s: %d tampil · %d TERSEMBUNYI di F# lain (mati filter utk lihat semua)', ...
                    fFilter, n, nHidden), 'ForegroundColor',[0.75 0.25 0]);
            else
                set(h.txtDescFilter,'String',sprintf('Filter: %s (%d)', fFilter, n), ...
                    'ForegroundColor',[0 0 0]);
            end
        else
            set(h.txtDescFilter,'String',sprintf('Filter: semua (%d)', n), 'ForegroundColor',[0 0 0]);
        end
    end
    % Kolom DX tabel sesar = jumlah baris DESC per-F#. Baris DESC bisa
    % ditambah/hapus/edit lewat banyak jalur (Ctrl+T dll.) yg cuma me-refresh
    % tabel DESC; ikutkan refresh tabel sesar di sini agar DX selalu tepat.
    % (i_refreshFaultTable tak memanggil balik i_refreshDescTable -> tak rekursif.)
    i_refreshFaultTable(fig);
end

function i_stylePoiCells(tb, D, tstat)
%I_STYLEPOICELLS  Fill warna sel kolom POI (kol 3) menurut akhiran POI:
%   FSR=merah muda, TF=cokelat muda, BDF=biru muda. Pakai uistyle/addStyle.
%   Indeks kolom (14-kolom): 3 POI · 4 Det · 5 #ACT F · 7 NUC POS · 8 PRP DIR ·
%   12 TAPER (T°): tstat{i} 'super'=BIRU (keyframe supervised) · 'auto'=HIJAU
%   (terisi dari interpolasi) · 'empty'=MERAH (belum ada data taper) ·
%   13 Nuk (checklist ✓ hijau saat titik nukleasi terisi).
    poiCol = 3; taperCol = 12; nukCol = 13;
    if nargin < 3, tstat = {}; end
    if ~ishghandle(tb), return; end
    try, removeStyle(tb); catch, end
    if ~iscell(D) || isempty(D), return; end
    red     = [1 0.72 0.72];   % penanda WAJIB-diisi yang masih kosong
    mismRed = [1 0.55 0.55];   % penanda #ACT F ≠ Deteksi (lebih pekat)
    tpBlue  = [0.72 0.82 1.0]; % taper supervised (keyframe)
    tpGreen = [0.74 0.92 0.74];% taper auto-fill dari interpolasi
    tpRed   = [1 0.72 0.72];   % taper belum ada data
    for i = 1:size(D,1)
        p = ''; if size(D,2)>=poiCol, p = char(D{i,poiCol}); end
        c = i_poiColor(p);
        pU = upper(strtrim(p));
        % NUC POS & PRP DIR WAJIB untuk SEMUA POI NUC-* + X-FS.
        needsPos     = startsWith(pU,'NUC-') || strcmp(pU,'X-FS');
        nucPosNeeded = needsPos;
        prpNeeded    = needsPos;
        if ~(strcmp(pU,'</BLANK>') || isequal(c,[0.10 0.55 0.45]))
            bg = 1 - 0.55*(1 - c);   % versi MUDA (fill lembut) dari warna POI
            try, addStyle(tb, uistyle('BackgroundColor', bg), 'cell', [i poiCol]); catch, end
        end
        % --- Penanda MERAH sel WAJIB kosong ---
        % (a) # ACT F (kol 5) kosong pada SEMUA baris.
        actEmpty = size(D,2)>=5 && i_cellEmpty(D{i,5});
        if actEmpty
            try, addStyle(tb, uistyle('BackgroundColor',red), 'cell', [i 5]); catch, end
        end
        % (a2) # ACT F (kol 5) TERISI TAPI BEDA dari Deteksi (kol 4) -> merah pekat.
        %   Deteksi = sistem otomatis; bila mata (actF) ≠ sistem -> tandai utk cek.
        if ~actEmpty && size(D,2)>=5
            detV = i_detNumOf(D{i,4});         % nilai Deteksi (NaN bila belum dihitung/'·')
            actV = str2double(i_cellStr(D{i,5}));
            if isfinite(detV) && isfinite(actV) && round(detV) ~= round(actV)
                try, addStyle(tb, uistyle('BackgroundColor',mismRed,'FontColor',[0.5 0 0], ...
                    'FontWeight','bold'), 'cell', [i 5]); catch, end
            end
        end
        % (b) NUC POS (kol 7) kosong utk POI NUC-*/X-FS.
        if nucPosNeeded && size(D,2)>=7 && i_cellEmpty(D{i,7})
            try, addStyle(tb, uistyle('BackgroundColor',red), 'cell', [i 7]); catch, end
        end
        % (c) PRP DIR (kol 8) kosong utk POI NUC-*/X-FS.
        if prpNeeded && size(D,2)>=8 && i_cellEmpty(D{i,8})
            try, addStyle(tb, uistyle('BackgroundColor',red), 'cell', [i 8]); catch, end
        end
        % (d) TAPER (kol 12): warna per status. super=BIRU · auto=HIJAU · empty=MERAH.
        if size(D,2) >= taperCol
            st = 'empty';
            if iscell(tstat) && i <= numel(tstat) && ~isempty(tstat{i}), st = tstat{i}; end
            switch st
                case 'super', tbg = tpBlue;
                case 'auto',  tbg = tpGreen;
                otherwise,    tbg = tpRed;
            end
            try, addStyle(tb, uistyle('BackgroundColor',tbg), 'cell', [i taperCol]); catch, end
        end
        % (e) Nuk (kol 13): ✓ hijau bila titik nukleasi terisi. RELEVAN utk SEMUA
        %   POI NUC-* + X-FS -> baris tsb tanpa titik ditandai merah muda (pengingat).
        if size(D,2) >= nukCol
            hasNuc = ~i_cellEmpty(D{i,nukCol});
            if hasNuc
                try, addStyle(tb, uistyle('BackgroundColor',[0.74 0.92 0.74],'FontColor',[0 0.4 0], ...
                    'FontWeight','bold'), 'cell', [i nukCol]); catch, end
            elseif i_isNucPoi(p)
                try, addStyle(tb, uistyle('BackgroundColor',red), 'cell', [i nukCol]); catch, end
            end
        end
    end
end

function v = i_detNumOf(cellVal)
%I_DETNUMOF  Ambil nilai numerik dari sel kolom Deteksi ('·' / '3' / 3). NaN bila
%   belum dihitung ('·'/kosong).
    v = NaN;
    s = strtrim(i_cellStr(cellVal));
    if isempty(s) || strcmp(s,'·') || strcmp(s,'—'), return; end
    v = str2double(s);
end

function tf = i_cellEmpty(x)
%I_CELLEMPTY  Sel tabel dianggap KOSONG: [], '', '—', atau NaN.
    tf = false;
    if isempty(x), tf = true; return; end
    if isnumeric(x), tf = ~any(isfinite(x)); return; end
    s = strtrim(char(x));
    tf = isempty(s) || strcmp(s,'—');
end

function i_highlightDescRow(fig)
%I_HIGHLIGHTDESCROW  Re-style tabel DESC: fill sel POI + SOROT baris terpilih
%   (descSelRow = baris TAMPIL) latar biru muda + set Selection. Selalu RESET
%   style dulu (i_stylePoiCells memanggil removeStyle) supaya sorotan lama tak
%   menumpuk saat pindah baris. Dipanggil di ekor i_refreshDescTable & tiap
%   perubahan seleksi (klik / Ctrl+O).
    h = guidata(fig);
    if ~(isfield(h,'tblDesc') && ishghandle(h.tblDesc)), return; end
    tb = h.tblDesc;
    D = get(tb,'Data'); n = 0; if iscell(D), n = size(D,1); end
    tstat = {}; if isfield(h,'descTaperStat'), tstat = h.descTaperStat; end
    i_stylePoiCells(tb, D, tstat);     % RESET + fill sel POI + warna kolom T° (removeStyle di dalam)
    r = []; if isfield(h,'descSelRow'), r = h.descSelRow; end
    if isempty(r) || ~isscalar(r) || r < 1 || r > n
        try, tb.Selection = []; catch, end
        return;
    end
    try, addStyle(tb, uistyle('BackgroundColor',[0.78 0.87 1.0]), 'row', r); catch, end
    try, tb.Selection = r; catch, end
end

function i_onToggleDescFilter(fig)
%I_ONTOGGLEDESCFILTER  Toggle FILTER nested per-F# (ON = hanya baris F# terpilih).
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);   % simpan editan tabel dulu
    on = true;
    if isfield(h,'btnDescFilter') && ishghandle(h.btnDescFilter)
        on = get(h.btnDescFilter,'Value')==1;
    else
        on = ~h.descFilterF;
    end
    h.descFilterF = on; h.descSelRow = []; guidata(fig, h);
    i_refreshDescTable(fig);
    i_renderPotKeepZoom(fig);   % garis vertikal DX ikut filter (ON=hanya F# aktif)
    if on, i_setDescStatus(fig,'Filter F# ON: hanya baris + garis DX F# aktif ditampilkan.');
    else,  i_setDescStatus(fig,'Filter F# OFF: semua baris + garis DX ditampilkan.'); end
end

function i_onDescZoomToggle(fig)
%I_ONDESCZOOMTOGGLE  Zoom kotak axPOT (baca bentuk kurva) / reset (toggle).
    h = guidata(fig);
    h.descZoomOn = ~h.descZoomOn; guidata(fig, h);
    try
        if h.descZoomOn
            pivui.grain4Shell.zoomBoxPOT(fig);
        else
            pivui.grain4Shell.resetViewPOT(fig);
        end
    catch
    end
end

function i_setDescStatus(fig, msg)
    if ~ishghandle(fig), return; end   % callback fire saat figure sudah ditutup -> diam
    h = guidata(fig);
    if isfield(h,'txtDescStatus') && ishghandle(h.txtDescStatus)
        set(h.txtDescStatus,'String',msg);
    end
    try, pivui.setStatus(fig, msg); catch, end
end

% --- helper baca sel uitable (aman) ---
function s = i_cellStr(x)
    if isempty(x), s = ''; return; end
    if ischar(x), s = reshape(x,1,[]); return; end
    if isnumeric(x) && isscalar(x)
        if isfinite(x), s = num2str(x); else, s = ''; end; return;
    end
    try, s = char(string(x)); s = reshape(s,1,[]); catch, s = ''; end
end
function v = i_cellNum(x)
    if isempty(x), v = NaN; return; end
    if isnumeric(x) && isscalar(x), v = double(x); return; end
    if ischar(x), v = str2double(x); return; end
    v = NaN;
end


% =====================================================================
% GRAIN4 — SAVE PROGRESS / COMMIT / EDIT-DI-GRAIN5
% =====================================================================
function i_onSaveDescProgress(fig)
%I_ONSAVEDESCPROGRESS  Simpan tabel deskripsi (semua garis PSG) + INTERPRETASI
%   (kurva HW/FW, POI, net-slip/AXSLIP, area/dNet/sudut tiap sesar ber-HW di garis
%   PSG aktif) ke _desc.json. Interpretasi di-REBUILD tiap simpan supaya JSON
%   selalu sinkron dengan keadaan tabel & assign terkini ("update tabel -> update
%   JSON"). Tak export gambar (itu di Commit).
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    if isempty(h.df)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    % Rebuild blok interpretasi ke descDoc (data kurva + POI + AXSLIP).
    h.descDoc = i_descBuildInterp(fig, h.descDoc);
    % (DIBUANG 2026-07-18: GRAIN4 TAK menulis _potdata.json. Menulis-ulang _potdata
    %  tiap Save berisiko menimpa garis PSG/kurva (data mendasar dari GRAIN3a) —
    %  user: "potdata tulis-ulang berisiko banget". GRAIN4 = pembaca _potdata; hanya
    %  _desc.json (deskripsi) yang GRAIN4 tulis, lewat gerbang berkonfirmasi.)
    guidata(fig, h);
    % _desc.json = data deskripsi berharga -> GERBANG KONFIRMASI (anti data-hilang).
    if ~i_confirmWriteDesc(fig, h.descDoc)
        i_setDescStatus(fig, 'Save Progress dibatalkan.'); return;
    end
    try
        if isfield(h,'interpDoc') && isstruct(h.interpDoc)
            try, pivcore.io.grain4Interp.write(h.df, h.interpDoc); catch, end   % track evolusi bidang sesar
        end
        if isfield(h,'taperInterpDoc') && isstruct(h.taperInterpDoc)
            try, pivcore.io.grain4TaperInterp.write(h.df, h.taperInterpDoc); catch, end   % track evolusi TAPER (kerja)
        end
        n  = numel(pivcore.io.grain4Desc.tocell(h.descDoc.rows));
        nf = numel(pivcore.io.grain4Desc.tocell(h.descDoc.faults));
        i_setDescStatus(fig, sprintf('Progres tersimpan: %d baris + %d sesar (kurva/POI/AXSLIP) → %s', ...
            n, nf, i_baseNameSafe(pivcore.io.grain4Desc.dataPath(h.df))));
    catch ME
        i_setDescStatus(fig, sprintf('GAGAL simpan: %s', ME.message));
    end
end

function doc = i_descBuildInterp(fig, doc)
%I_DESCBUILDINTERP  Isi doc.faults + doc.interpretation dgn data interpretasi
%   sesar (garis PSG AKTIF): kurva HW/FW values, POI (strain% + frame mentah),
%   net-slip cm/s (AXSLIP), area/dNet/angle. Reuse i_descFaultJsons.
    h = guidata(fig);
    if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(h.df); end
    cal       = i_descCalib(h);
    velMult   = cal.velMultUsed;
    strainTot = i_strainTotalSafe(h);
    opts = struct('dpi', i_descDpi(h), 'velMult', velMult);
    doc.faults = i_descFaultJsons(fig, opts, strainTot, velMult, cal);
    psgName = h.activePsgId; if isempty(psgName), psgName = 'PSG'; end
    doc.interpretation = struct( ...
        'psgId', h.activePsgId, 'psgName', psgName, 'producedAt', i_descNowStr(), ...
        'nFrames', h.nF, 'strainTotalPct', strainTot, 'velMult', velMult, ...
        'calibration', cal);
end

function i_onGoGRAIN5(fig)
%I_ONGOGRAIN5  Simpan deskripsi lalu buka GRAIN5 (folder sama) untuk edit assign.
    h = guidata(fig);
    root = '';
    if isfield(h,'root') && ischar(h.root), root = h.root; end
    try, i_onSaveDescProgress(fig); catch, end
    try, delete(fig); catch, end
    try
        if ~isempty(root) && isfolder(root), GRAIN5(root); else, GRAIN5(); end
    catch ME
        warning('GRAIN4:goGRAIN5','Gagal buka GRAIN5: %s', ME.message);
    end
end


function i_onOpenAxCal(fig)
%I_ONOPENAXCAL  Buka GRAINAXCAL (kalibrasi sumbu cm) pada folder exp aktif.
%   GRAIN4 TETAP hidup; saat GRAINAXCAL ditutup, GRAIN4 membaca ulang _axcal.json &
%   me-render ulang axMain (kalibrasi terbaru langsung terlihat). Non-blocking.
    h = guidata(fig);
    root = '';
    if isfield(h,'root') && ischar(h.root) && isfolder(h.root)
        root = h.root;
    elseif isfield(h,'df') && ischar(h.df)
        root = fileparts(h.df);
    end
    if ~pivui.quiet()
        try, set(fig,'WindowState','minimized'); catch, end
    end
    try
        if ~isempty(root) && isfolder(root), GRAINAXCAL(root); else, GRAINAXCAL(); end
    catch ME
        warning('GRAIN4:openAxCal','Gagal buka GRAINAXCAL: %s', ME.message);
        return;
    end
    % Segarkan GRAIN4 saat editor kalibrasi ditutup (baca ulang sidecar + render).
    cfgs = findall(0,'Type','figure');
    for f = cfgs(:).'
        nm = get(f,'Name');
        if ischar(nm) && contains(nm,'GRAINAXCAL') && f ~= fig
            set(f,'DeleteFcn', @(s,e) i_axCalClosed(fig));
        end
    end
end

function i_axCalClosed(fig)
%I_AXCALCLOSED  Callback saat GRAINAXCAL tutup: GRAIN4 baca ulang _axcal + render.
    if ~ishghandle(fig), return; end
    try, set(fig,'WindowState','normal'); catch, end
    h = guidata(fig);
    if ~isfield(h,'df') || isempty(h.df), return; end
    h.axCal = pivcore.io.grainAxCal.read(h.df);
    guidata(fig, h);
    try, pivui.grain4Shell.renderMain(fig); catch, end
end

function i_onCommitDesc(fig)
%I_ONCOMMITDESC  COMMIT garis PSG AKTIF (JSON). Thin wrapper -> i_commitDescActivePsg
%   (dipakai bersama tombol "Commit SEMUA exp"). Set status dari hasil.
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    if isempty(h.df)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    res = i_commitDescActivePsg(fig);
    i_setDescStatus(fig, res.msg);
end

function res = i_commitDescActivePsg(fig)
%I_COMMITDESCACTIVEPSG  COMMIT garis PSG AKTIF: (1) simpan _desc.json; (2) tulis
%   JSON interpretasi + baris DESC ke folder ber-versi PAB4_DESC/<exp>/
%   <ddmmyy-HHMMSS>_<garisPSG>/. IMMUTABLE (folder baru tiap kali). Mengembalikan
%   struct(ok, empty, nFrame, sessDir, msg). `empty`=true bila garis PSG aktif tak
%   punya baris DESC (bukan error — dilewati saat commit-semua). TIDAK menyentuh UI
%   status (pemanggil yang set). Hormati checkbox hapus-commit-lama (i_onCommitDesc
%   memanggil lewat wrapper; commit-semua menonaktifkan interaktivitas via quiet).
    res = struct('ok',false,'empty',false,'nFrame',0,'sessDir','','msg','');
    h = guidata(fig);
    if isempty(h.df), res.msg = 'Belum ada eksperimen dimuat.'; return; end
    % (Tulis _desc.json sumber DIBUANG: Commit meng-EXPORT baris ke folder versi
    %  PAB4_DESC/ dari descDoc di MEMORI; TIDAK menyentuh _desc.json sumber. Simpan
    %  sumber lewat 💾 Save eksplisit. Hanya Save yang menulis _desc.json.)

    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(rows)
        res.empty = true; res.msg = 'Garis PSG aktif belum punya baris deskripsi.'; return;
    end

    % folder induk GRAIN/ (override utk TES; TAK wajib sudah ada — dibuat mkdir).
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
        if ~isfolder(grainRoot), try, mkdir(grainRoot); catch, end, end
    end

    % --- CHECKBOX: hapus SEMUA commit lama exp ini (export bersih) + WARNING 2x ---
    cleanExport = isfield(h,'chkCleanExport') && ishghandle(h.chkCleanExport) && get(h.chkCleanExport,'Value')==1;
    if cleanExport
        expDir = pivcore.io.grain4DescExport.expDir(grainRoot, h.df);
        if isfolder(expDir)
            if ~i_confirmCleanExport(fig, expDir)   % 2x konfirmasi
                res.msg = 'Commit dibatalkan (hapus commit lama tidak dikonfirmasi).'; return;
            end
            try, rmdir(expDir, 's'); catch ME
                res.msg = sprintf('GAGAL hapus commit lama: %s', ME.message); return;
            end
        end
    end

    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride)
        ts = h.exportStampOverride;   % TES: timestamp deterministik
    end
    psgName = h.activePsgId; if isempty(psgName), psgName = 'PSG'; end
    sessDir = pivcore.io.grain4DescExport.sessionDir(grainRoot, h.df, ts, psgName);
    if ~isfolder(sessDir), mkdir(sessDir); end

    % KALIBRASI ruang-waktu benar (velMultGeom; fallback 0.005) — dipakai utk
    % net-slip cm/s pada JSON (konsisten dgn Report PDF). Lihat i_descCalib.
    cal = i_descCalib(h);
    velMult = cal.velMultUsed;
    strainTot = i_strainTotalSafe(h);
    opts = struct('dpi', i_descDpi(h), 'velMult', velMult);

    % COMMIT = JSON-ONLY. Export gambar JPG (AX main/POT/SLIP per frame) DIBUANG —
    % user hanya perlu JSON. Renderer (i_descShotAxMain/…) tetap dipakai Report PDF.
    nFrameSet = 0;
    seen = containers.Map('KeyType','char','ValueType','logical');
    for i = 1:numel(rows)
        r = rows{i};
        if ~isfinite(r.frame), continue; end
        key = sprintf('%s|%d', pivcore.io.grain4DescExport.faultTag(r.fNum), round(r.frame));
        if isKey(seen, key), continue; end
        seen(key) = true;
        nFrameSet = nFrameSet + 1;   % jumlah (F#,frame) unik yg dideskripsikan
    end

    % JSON interpretasi (per sesar di garis aktif) + baris DESC + kalibrasi + geometry + lifecycle
    info = struct();
    info.experiment    = i_baseNameSafe(h.df);
    info.psgId         = h.activePsgId;
    info.psgName       = psgName;
    info.producedAt    = i_descNowStr();
    info.nFrames       = h.nF;
    info.strainTotalPct= strainTot;
    info.velMult       = velMult;
    info.calib         = cal;   % kalibrasi ruang-waktu diperluas (velMultGeom/dt/dxCm/…)
    info.referenceGeom = i_descReferenceGeom(h);   % ref horizontal + dinding + base + tebal
    info.faults        = i_descFaultJsons(fig, opts, strainTot, velMult, cal);
    info.rows          = rows;
    sjson = pivcore.io.grain4DescExport.buildSessionJson(h.df, info);
    try
        pivcore.io.grain4DescExport.writeSessionJson(sessDir, h.df, sjson);
    catch ME
        res.msg = sprintf('JSON GAGAL: %s', ME.message);
        try, if isfolder(sessDir), rmdir(sessDir, 's'); end, catch, end
        return;
    end

    res.ok = true; res.nFrame = nFrameSet; res.sessDir = sessDir;
    res.msg = sprintf('COMMIT (JSON): %d frame terdeskripsi → %s', nFrameSet, sessDir);
end

function i_onCommitAllExp(fig)
%I_ONCOMMITALLEXP  Commit JSON untuk SEMUA eksperimen yang dimuat dari folder.
%   Untuk tiap exp di h.list: muat lewat shell (loadExperiment = frame-1 + sampling
%   POT, BUKAN semua frame gambar), lalu untuk tiap garis PSG NYATA yang punya baris
%   deskripsi -> aktifkan + i_commitDescActivePsg. Eksperimen & garis PSG semula
%   dipulihkan setelah selesai. Cancel via tombol Cancel (h.commitCancel).
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list)
        i_setDescStatus(fig, 'Belum ada daftar eksperimen (pilih folder dulu).'); return;
    end
    N = numel(h.list);
    % Flush editan tabel exp AKTIF dulu (jangan sampai baris DESC yg belum di-capture
    % hilang saat loadExperiment mengganti dataset).
    i_captureDescFromTable(fig); h = guidata(fig);
    origRow = 1; if isfield(h,'activeRow') && isscalar(h.activeRow) && h.activeRow>=1, origRow = h.activeRow; end
    origPsg = ''; if isfield(h,'activePsgId'), origPsg = h.activePsgId; end

    % KONFIRMASI 1x (proses panjang; muat ulang tiap exp).
    if ~pivui.quiet()
        b = questdlg(sprintf(['Commit JSON untuk SEMUA %d eksperimen yang dimuat?\n\n' ...
            'Tiap eksperimen dimuat bergiliran (frame-1 saja) lalu tiap garis PSG yang ' ...
            'punya baris deskripsi di-commit ke folder ber-versi. Bisa memakan waktu.'], N), ...
            '📦 Commit semua eksperimen', 'Ya, commit semua', 'Batal', 'Batal');
        if ~strcmp(b, 'Ya, commit semua')
            i_setDescStatus(fig, 'Commit semua exp dibatalkan.'); return;
        end
    end

    % Checkbox "hapus commit lama" DINONAKTIFKAN selama loop: kalau ON, commit PSG
    % ke-2 dalam satu exp akan menghapus hasil commit PSG ke-1 (rmdir seluruh
    % expDir). Simpan nilai lalu paksa OFF; dipulihkan di cleanup.
    chkVal0 = 0;
    if isfield(h,'chkCleanExport') && ishghandle(h.chkCleanExport)
        chkVal0 = get(h.chkCleanExport,'Value');
        set(h.chkCleanExport,'Value',0);
    end

    i_commitBtnState(fig, true);   % tampilkan Cancel, sembunyikan tombol commit
    wb = i_descWaitbar('Commit semua eksperimen…');
    cleaner = onCleanup(@() i_commitAllCleanup(fig, wb, chkVal0));  %#ok<NASGU>

    nExpOk = 0; nPsgOk = 0; nPsgEmpty = 0; nFrameTot = 0; expWithData = 0;
    cancelled = false;
    for i = 1:N
        % cek cancel
        h = guidata(fig);
        if isfield(h,'commitCancel') && h.commitCancel, cancelled = true; break; end
        nm = h.list(i).name;
        if ~isempty(wb) && ishghandle(wb)
            waitbar((i-1)/N, wb, sprintf('Exp %d/%d: %s — memuat…', i, N, nm));
        end
        try, h.tbl.Selection = i; catch, end
        pivui.grain4Shell.loadExperiment(fig, i);   % frame-1 + sampling POT (bukan semua frame)
        h = guidata(fig);

        ids = i_realPsgIds(h.doc);                % garis PSG NYATA exp ini
        if isempty(ids) && ~isempty(h.activePsgId), ids = {h.activePsgId}; end
        anyData = false;
        for k = 1:numel(ids)
            h = guidata(fig);
            if isfield(h,'commitCancel') && h.commitCancel, cancelled = true; break; end
            id = ids{k};
            % lewati garis PSG tanpa baris DESC (tak perlu aktifkan -> hemat)
            if isempty(pivcore.io.grain4Desc.rowsForPsg(h.descDoc, id))
                nPsgEmpty = nPsgEmpty + 1; continue;
            end
            if ~strcmp(id, h.activePsgId), i_activateLineById(fig, id); end
            if ~isempty(wb) && ishghandle(wb)
                waitbar((i-1)/N, wb, sprintf('Exp %d/%d: %s — commit %s…', i, N, nm, id));
            end
            res = i_commitDescActivePsg(fig);
            if res.ok
                nPsgOk = nPsgOk + 1; nFrameTot = nFrameTot + res.nFrame; anyData = true;
            elseif res.empty
                nPsgEmpty = nPsgEmpty + 1;
            end
        end
        if cancelled, break; end
        if anyData, nExpOk = nExpOk + 1; end
        expWithData = expWithData + double(anyData);
    end

    % --- PULIHKAN eksperimen & garis PSG semula ---
    if ~isempty(wb) && ishghandle(wb), waitbar(1, wb, 'Memulihkan eksperimen semula…'); end
    try, h = guidata(fig); h.tbl.Selection = origRow; catch, end
    pivui.grain4Shell.loadExperiment(fig, origRow);
    if ~isempty(origPsg)
        h = guidata(fig);
        if any(strcmp(i_realPsgIds(h.doc), origPsg)), i_activateLineById(fig, origPsg); end
    end

    if cancelled
        i_setDescStatus(fig, sprintf('DIBATALKAN. Sebelum batal: %d exp / %d garis PSG ter-commit (%d frame).', ...
            nExpOk, nPsgOk, nFrameTot));
    else
        i_setDescStatus(fig, sprintf('COMMIT SEMUA selesai: %d/%d exp ber-data, %d garis PSG ter-commit (%d frame), %d garis dilewati (kosong).', ...
            nExpOk, N, nPsgOk, nFrameTot, nPsgEmpty));
    end
end

function i_commitAllCleanup(fig, wb, chkVal0)
%I_COMMITALLCLEANUP  Tutup waitbar + reset tombol commit + pulihkan checkbox
%   clean-export (dipanggil onCleanup, aman walau ada error di tengah loop).
    i_descCloseWb(wb);
    i_commitBtnState(fig, false);
    if nargin >= 3
        h = guidata(fig);
        if isfield(h,'chkCleanExport') && ishghandle(h.chkCleanExport)
            try, set(h.chkCleanExport,'Value',chkVal0); catch, end
        end
    end
end

function J = i_descFaultJsons(fig, opts, strainTot, velMult, cal)
%I_DESCFAULTJSONS  Bangun cell JSON interpretasi (buildFaultJson) tiap sesar
%   ber-HW di garis PSG AKTIF. Reuse engine grain5FaultExport (interpretasi, bukan
%   kurva mentah penuh). Tiap sesar DILENGKAPI blok `geometry` (polyline 2-fase:
%   Len/sudut/growth/die-out + vertices) & `lifecycle` (timeline fase ber-stempel
%   dari POI NUC-FSR/FS-max/FS-x) supaya JSON commit = SELURUH informasi GRAIN4.
%   `cal` (opsional) = i_descCalib(h) untuk dtSec; absen -> dihitung di sini.
    h = guidata(fig);
    if nargin < 5 || ~isstruct(cal), cal = i_descCalib(h); end
    dtSec = NaN; if isstruct(cal) && isfield(cal,'dtSec'), dtSec = cal.dtSec; end
    ord = i_faultRowOrderPsg(h);
    J = {};
    for k = 1:numel(ord)
        f = ord{k};
        if ~(isstruct(f) && isfield(f,'hwPosPx') && isfinite(f.hwPosPx)), continue; end
        [ns, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f); %#ok<ASGLU>
        info = struct('experiment', i_baseNameSafe(h.df), 'nFrames', h.nF, ...
            'signConvention', h.signConv, 'strainTotalPct', strainTot, 'velMult', velMult, ...
            'netslip', ns);
        if okHW, info.hwCurveNum = i_curveNumSafe(h, hwRow, f.hwPosPx); end
        if okFW, info.fwCurveNum = i_curveNumSafe(h, fwRow, f.fwPosPx); end
        info.producedAt = i_descNowStr();
        try
            js = pivcore.io.grain5FaultExport.buildFaultJson(h.df, f, info);
            % LENGKAPI dgn data kurva HW & FW per-frame (px/frame mentah) + net-slip
            % cm/s (sudah ada di js.netslip). Ini "AXSLIP + kurva HW/FW" utk CLCW.
            hwV = i_faultHwVec(h, f); fwV = i_faultFwVec(h, f);
            js.hw.values = i_rowv(hwV);
            js.fw.values = i_rowv(fwV);
            js.hw.units  = 'px/frame';  js.fw.units = 'px/frame';
            % --- GEOMETRI bidang sesar PER-DX (_desc.json) -> blok js.geometry ---
            js.geometry  = i_descFaultGeomJson(h, f);
            % SINKRON: `js.angleDeg` top-level (buildFaultJson -> f.angleDeg) diisi
            % dari sudut DX TERAKHIR ber-bidang sesar (angleDeg finite) bila kosong.
            % (perDx kini bisa berisi item taper/lisan tanpa bidang -> cari yg finite.)
            if isstruct(js.geometry) && isfield(js.geometry,'perDx') && ~isempty(js.geometry.perDx)
                topA = NaN; if isfield(js,'angleDeg') && isscalar(js.angleDeg), topA = double(js.angleDeg); end
                if ~isfinite(topA)
                    pdx = js.geometry.perDx;
                    for q = numel(pdx):-1:1
                        if isfield(pdx{q},'angleDeg') && isfinite(pdx{q}.angleDeg)
                            js.angleDeg = pdx{q}.angleDeg; break;
                        end
                    end
                end
            end
            % --- LIFECYCLE: timeline fase ber-stempel dari POI DESC + rates ------
            js.lifecycle = i_descFaultLifecycle(h, f, strainTot, dtSec, js.geometry);
            J{end+1} = js; %#ok<AGROW>
        catch
        end
    end
end

function rg = i_descReferenceGeom(h)
%I_DESCREFERENCEGEOM  Blok REFERENSI GEOMETRI (koordinat robust) utk JSON commit:
%   ref horizontal (sudut+posisi = datum kedalaman) + dinding pembatas + base +
%   ketebalan model. Dari meta _desc.json. Dipakai buildSessionJson (top-level
%   s.referenceGeom) + tiap faults[].geometry (header). Garis 2x2 [x y] px -> cell
%   (jsonencode array-of-arrays); [] bila tak diset.
    rg = struct();
    rg.units            = struct('length','cm','angle','deg');
    rg.refHorizonDeg    = i_numOrNan(i_faultRefDeg(h));
    Pref = zeros(0,2); Plw = zeros(0,2); Pbase = zeros(0,2); Pind = zeros(0,2); thick = 4;
    if isfield(h,'descDoc') && isstruct(h.descDoc)
        Pref  = pivcore.io.grain4Desc.refHorizonPts(h.descDoc);
        Plw   = pivcore.io.grain4Desc.metaLine(h.descDoc,'limitWallPts');
        Pbase = pivcore.io.grain4Desc.metaLine(h.descDoc,'basePts');
        Pind  = pivcore.io.grain4Desc.metaLine(h.descDoc,'indenterInitPts');
        thick = pivcore.io.grain4Desc.modelThicknessCm(h.descDoc);
    end
    Pbox = zeros(0,2);
    if isfield(h,'descDoc') && isstruct(h.descDoc), Pbox = pivcore.io.grain4Desc.modelBoxPts(h.descDoc); end
    rg.modelBoxPts      = pivcore.io.grain4Desc.vertsToCell(Pbox);   % 4 titik (sumber utama semua ref)
    rg.refHorizonPts    = pivcore.io.grain4Desc.vertsToCell(Pref);   % datum kedalaman (fallback/manual)
    rg.limitWallPts     = pivcore.io.grain4Desc.vertsToCell(Plw);    % dinding pembatas (=Lpos; fallback)
    rg.indenterInitPts  = pivcore.io.grain4Desc.vertsToCell(Pind);   % indenter awal (=X0; fallback)
    rg.basePts          = pivcore.io.grain4Desc.vertsToCell(Pbase);  % base model (fallback)
    rg.modelThicknessCm = thick;                                  % ketebalan model (cm)
    % Datum EFEKTIF (dari kotak bila ada, else garis) -> memudahkan CLCW.
    Reff = i_modelRefs(h);
    rg.effPushWallX   = i_numOrNan(Reff.xLeft);    % x dinding pendorong (datum jarak)
    rg.effLimitWallX  = i_numOrNan(Reff.xRight);   % x dinding pembatas
    rg.effFromBox     = Reff.fromBox;
    % Kalibrasi cmPerPx nukleasi (X0/Lpos -> L0) + geometri eksperimen (bila ada).
    [cpp, note] = i_nucCmPerPx(h);
    rg.nucCmPerPx       = i_numOrNan(cpp);
    rg.nucCmPerPxSource = strtrim(note);
    if isfield(h,'df') && ~isempty(h.df)
        try
            gg = pivcore.export.frameCatalog.readGeomFull(h.df);
            rg.geomX0cm   = i_numOrNan(gg.X0_cm);
            rg.geomLposCm = i_numOrNan(gg.Lpos_cm);
            rg.geomL0cm   = i_numOrNan(gg.L0_cm);
        catch
        end
    end
end

function g = i_descFaultGeomJson(h, f)
%I_DESCFAULTGEOMJSON  Blok geometri sesar utk JSON commit — PER-DX (LENGKAP
%   2026-07-17). Tiap DX (baris DESKRIPSI) sesar ini = SATU item perDx dgn SELURUH
%   informasi yg dicatat di tabel DESC: bidang sesar (vertices/sudut/panjang/growth)
%   + TAPER topografi (vertices/sudut/panjang) + atribut lisan (POI/NUC POS/PRP DIR/
%   IS-OOST/#ACT F/fTrx/desc). Supaya CLCW baca SATU tempat = semua yg dikerjakan.
%   Item DIMASUKKAN bila DX punya bidang sesar (vertices>=2) ATAU taper (taperDeg
%   finite) ATAU catatan lisan berarti (POI selain </blank>, atau desc/nucPos/fsrDir
%   terisi). Struktur:
%     g.units        = {length:cm, angle:deg, rate:cm/s}
%     g.refHorizonDeg= ref horizontal (koreksi kamera)
%     g.perDx{i}     = { frame, poi, actF, isOost, nucPos, fsrDir, fTrx, desc,
%                        angleDeg, lenCm, growthRate, vertices,          (bidang sesar)
%                        taperDeg, taperLenCm, taperVertices }           (taper topografi)
    g = struct();
    g.units        = struct('length','cm','angle','deg','rate','cm/s');
    % REFERENSI GEOMETRI (sudut+posisi ref horizontal, dinding pembatas, base, tebal).
    rg = i_descReferenceGeom(h);
    g.refHorizonDeg    = rg.refHorizonDeg;
    g.modelBoxPts      = rg.modelBoxPts;
    g.refHorizonPts    = rg.refHorizonPts;
    g.limitWallPts     = rg.limitWallPts;
    g.indenterInitPts  = rg.indenterInitPts;
    g.basePts          = rg.basePts;
    g.modelThicknessCm = rg.modelThicknessCm;
    g.perDx        = {};
    ftag = i_faultUiTag(f); if isempty(ftag), return; end
    tgt = sprintf('F%s', ftag);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    % baris DX sesar ini, urut frame menaik (utk growth antar-DX).
    sub = {};
    for k = 1:numel(rows)
        if strcmp(strtrim(rows{k}.fNum), tgt), sub{end+1} = rows{k}; end %#ok<AGROW>
    end
    sub = i_sortDescRowsByFrame(sub);
    dt      = i_faultDtSec(h);
    cmPerPx = i_faultCmPerPx(h);
    for t = 1:numel(sub)
        r = sub{t};
        V  = pivcore.io.grain4Desc.normVerts(r.vertices);
        Vt = pivcore.io.grain4Desc.normVerts(r.taperVerts);
        hasFault = size(V,1)  >= 2;
        hasTaper = size(Vt,1) >= 2 || (isscalar(r.taperDeg) && isfinite(r.taperDeg));
        poiU = upper(strtrim(char(r.poi)));
        hasNote  = ~isempty(poiU) && ~strcmp(poiU,'</BLANK>') ...
                   || ~isempty(strtrim(char(r.desc))) ...
                   || ~isempty(strtrim(char(r.nucPos))) ...
                   || ~isempty(strtrim(char(r.fsrDir)));
        if ~(hasFault || hasTaper || hasNote), continue; end   % baris benar2 kosong -> skip
        d = struct();
        % --- atribut lisan / POI (yg dicatat di tabel DESC) ---
        d.frame      = i_numOrNan(r.frame);
        d.poi        = char(r.poi);
        d.actF       = i_numOrNan(r.actF);
        d.isOost     = char(r.isOost);
        d.nucPos     = char(r.nucPos);
        d.fsrDir     = char(r.fsrDir);
        d.fTrx       = i_numOrNan(r.fTrx);
        d.desc       = char(r.desc);
        % --- BIDANG SESAR (polyline vertices) ---
        gr = pivcore.io.grain4Desc.growthPerDx(sub, t, dt);
        d.angleDeg   = i_numOrNan(r.angleDeg);
        d.lenCm      = i_numOrNan(r.lenCm);
        d.growthRate = i_numOrNan(gr);
        d.vertices   = pivcore.io.grain4Desc.vertsToCell(V);   % [] bila tak ada
        % --- TAPER (kemiringan topografi) ---
        d.taperDeg      = i_numOrNan(r.taperDeg);
        d.taperLenCm    = i_numOrNan(pivcore.io.grain4Desc.lenCmOf(Vt, cmPerPx));
        d.taperVertices = pivcore.io.grain4Desc.vertsToCell(Vt);   % [] bila tak ada
        % --- TITIK NUKLEASI/X-FS (SEMUA POI NUC-* + X-FS): 1 titik. nucPoint =
        %     titik input (data lama garis 2-titik -> vertex-1). Jarak HORIZONTAL ke
        %     dinding pendorong + kedalaman ke ref horizontal (cm) dihitung saat input. ---
        Vn = pivcore.io.grain4Desc.normVerts(r.nucVerts);
        d.nucVertices  = pivcore.io.grain4Desc.vertsToCell(Vn);   % [] bila tak ada
        pN = pivcore.io.grain4Desc.nucPointPx(Vn);
        d.nucPoint     = pivcore.io.grain4Desc.vertsToCell(pN);   % [] atau {[x y]}
        d.nucDistCm    = i_numOrNan(r.nucDistCm);               % nukleasi -> bidang sesar
        d.nucDepthPx   = i_numOrNan(r.nucDepthPx);              % kedalaman ke ref horizontal (PIXEL)
        d.nucDepthCm   = i_numOrNan(r.nucDepthCm);              % kedalaman (cm = px*cmPerPx)
        d.nucDistF1Cm  = i_numOrNan(r.nucDistF1Cm);             % jarak ke vertex bidang sesar F-1
        g.perDx{end+1} = d; %#ok<AGROW>
    end
end

function lc = i_descFaultLifecycle(h, f, strainTot, dtSec, geom)
%I_DESCFAULTLIFECYCLE  Timeline fase siklus hidup sesar dari POI DESC (frame)
%   -> pivcore.io.grain4Lifecycle.lifecyclePhases. rates growth/die-out diambil
%   dari blok geometry (bila ada).
    poi = pivcore.io.grain4Lifecycle.poiStruct( ...
        i_faultNucFsrFrame(h, f), ...        % NUC-FSR (nukleasi mulai)
        i_faultFirstFsMax(h, f), ...         % FS-max pertama (FSR mulai)
        i_faultFsMaxSecondFrame(h, f), ...   % FS-max kedua (FSR menyempurnakan)
        i_faultFsxFrame(h, f));              % FS-x (berhenti aktif)
    % Rates kini PER-DX (di geom.perDx). Timeline lifecycle tetap dari POI frames;
    % growth/dieOut agregat tak lagi tunggal -> NaN (lihat geom.perDx utk detail).
    rates = struct('growth', NaN, 'dieOut', NaN);
    lc = pivcore.io.grain4Lifecycle.lifecyclePhases(poi, h.nF, strainTot, dtSec, rates);
end

function v = i_numOrNan(x)
%I_NUMORNAN  Skalar finite -> double; else NaN (jsonencode -> null).
    if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = NaN; end
end

function v = i_rowv(x)
%I_ROWV  Vektor baris double (NaN dibiarkan -> JSON null). Kosong -> [].
    if isempty(x), v = []; else, v = double(x(:)).'; end
end

function f = i_faultByUiNum(h, fTag)
%I_FAULTBYUINUM  Cari struct sesar (garis PSG aktif) yang uiNum-nya cocok dgn
%   string fTag ('F3' / '3'). Kosong -> [].
    f = [];
    s = strtrim(char(fTag));
    s = regexprep(s, '^[Ff]', '');           % buang prefiks F
    num = str2double(s);
    if ~isfinite(num), return; end
    ord = i_faultRowOrderPsg(h);
    for k = 1:numel(ord)
        if abs(pivui.grain5Model.faultUiNum(ord{k}) - num) < 0.5, f = ord{k}; return; end
    end
end

function asp = i_axMainDataAspect(h, kk)
%I_AXMAINDATAASPECT  Aspek rasio DATA axMain (xspan/yspan grid) utk frame kk. Dipakai
%   ekspor supaya figure = ukuran gambar (tanpa whitespace). Fallback 2.0 bila data
%   tak tersedia. Clamp [0.2 8] agar figure tak ekstrem.
    asp = 2.0;
    try
        if ~(isstruct(h) && isfield(h,'data') && ~isempty(h.data)), return; end
        xg = pivcore.data.safeFrame(h.data.x, kk); yg = pivcore.data.safeFrame(h.data.y, kk);
        if isempty(xg), xg = pivcore.data.safeFrame(h.data.x, 1); end
        if isempty(yg), yg = pivcore.data.safeFrame(h.data.y, 1); end
        if isempty(xg) || isempty(yg), return; end
        xspan = max(xg(:)) - min(xg(:));
        yspan = max(yg(:)) - min(yg(:));
        if isfinite(xspan) && isfinite(yspan) && xspan > 0 && yspan > 0
            asp = xspan / yspan;
        end
    catch, end
    asp = min(8, max(0.2, asp));
end

function ok = i_descShotAxMain(fig, scalar, k, file, opts, lc, strainTot)
%I_DESCSHOTAXMAIN  Render AX main (velmag/shear) frame k -> `file` JPG. Memakai
%   PENGATURAN TAMPILAN LIVE (cfg=h: climVel/shearAbs/gsAlpha/glyphOn/glyphLW/
%   glyphSp/glyphColor) — PERSIS tampilan kerja + GS latar + glyph. Garis PSG
%   oranye + caption. JPG Quality 90, guard ≤700KB.
    ok = false;
    h = guidata(fig);
    if isempty(h.data), return; end
    scKey = 'velocity_magnitude'; if strcmp(scalar,'shear'), scKey = 'shear'; end
    kWant = max(1, min(round(k), pivcore.util.scalarOr(h.imgFrames,1)));
    if kWant > 1 && ~pivcore.util.isFullLoaded(h)
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    kk = max(1, min(kWant, pivcore.util.scalarOr(h.imgFrames,1)));
    velMult = 0.005;
    if isstruct(opts) && isfield(opts,'velMult') && isscalar(opts.velMult) && opts.velMult>0
        velMult = opts.velMult;
    end

    % UKURAN FIGURE MENGIKUTI ASPEK DATA (utk laporan: axMain = ukuran gambar, TANPA
    % whitespace). Aspek = xspan/yspan grid data (renderScalarPanel pakai daspect 1:1
    % -> tanpa penyesuaian ini gambar lebar-pendek pas di 2:1 malah bikin whitespace).
    % Tinggi area-plot dipatok; lebar = tinggi*aspek + slot colorbar. Fallback 2:1.
    dataAsp = i_axMainDataAspect(h, kk);
    plotH = 520;                              % tinggi area plot (px)
    cbW   = 130;                              % slot colorbar+label (px)
    plotW = max(200, round(plotH * dataAsp)); % lebar area plot = tinggi*aspek
    figW  = plotW + cbW; figH = plotH + 90;   % +margin title/axis
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 figW figH]);
    try, pivui.forceLightTheme(tmp); catch, end
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    % axes isi area kiri (sisakan slot colorbar kanan + margin title atas/bawah).
    try, set(ax,'Units','normalized','Position',[0.04 0.06 plotW/figW*0.96 plotH/figH*0.90]); catch, end
    % cfg = h -> pakai SEMUA setting tampilan LIVE (GS alpha, glyph on/warna/tebal/
    % spacing, CLim velmag, shearAbs). Persis tampilan kerja user.
    cfg = h; cfg.scalarSrc = scKey;
    % Cache grayCLAHE lintas-panel per sesi ekspor (bila disediakan): GS frame
    % identik (velmag+shear) tak diproses ulang. Absen -> jalur lama identik.
    if isstruct(opts) && isfield(opts,'gsCache') && isa(opts.gsCache,'containers.Map')
        cfg.gsCache = opts.gsCache;
    end
    isShear = strcmp(scalar,'shear');
    pivcore.montage.renderScalarPanel(ax, h.data, kk, scKey, cfg);
    set(ax, 'Color','w', 'XColor',[0 0 0], 'YColor',[0 0 0], 'XTick',[], 'YTick',[]);
    cb = colorbar(ax);
    if isShear
        cb.Label.String = 'shear strain (du/dy+dv/dx)';
    else
        cb.Label.String = '|V| (cm/s)';
        cl = clim(ax); t = get(cb,'Ticks');
        if isempty(t), t = linspace(cl(1), cl(2), 6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*velMult), t, 'UniformOutput', false));
    end
    set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
    hold(ax,'on');
    if ~isempty(h.line) && isfield(h.line,'p1')
        plot(ax, [h.line.p1(1) h.line.p2(1)], [h.line.p1(2) h.line.p2(2)], ...
            '-', 'Color',[1 0.6 0.1], 'LineWidth',0.8);
    end
    hold(ax,'off');
    % Sumbu cm (tick X/Y + label + segitiga indenter) bila dikalibrasi (GRAINAXCAL).
    % Override tick pixel-kosong di atas. renderer BERSAMA -> ekspor = live axMain.
    if isfield(h,'axCal') && isstruct(h.axCal) && isfield(h.axCal,'enabled') && h.axCal.enabled
        xg = pivcore.data.safeFrame(h.data.x, kk); yg = pivcore.data.safeFrame(h.data.y, kk);
        if isempty(xg), xg = pivcore.data.safeFrame(h.data.x, 1); end
        if isempty(yg), yg = pivcore.data.safeFrame(h.data.y, 1); end
        if ~isempty(xg) && ~isempty(yg)
            xExt = [min(xg(:)) max(xg(:))]; yExt = [min(yg(:)) max(yg(:))];
            Rc = struct('dxCm', NaN);
            if isfield(h,'axCalR') && isfield(h.axCalR,'dxCm'), Rc.dxCm = h.axCalR.dxCm; end
            pivcore.export.frameCatalog.applyCmAxes(ax, h.axCal, Rc, kk, max(1,h.nF), xExt, yExt);
        end
    end
    st = i_frameToStrain(kk, h.nF, strainTot);
    if isfinite(st)
        cap = sprintf('%s — %s — frame %d (strain %.2f%%)', i_baseNameSafe(h.df), scalar, kk, st);
    else
        cap = sprintf('%s — %s — frame %d', i_baseNameSafe(h.df), scalar, kk);
    end
    title(ax, cap, 'Interpreter','none', 'Color',[0 0 0]);
    ok = i_descExportJpg(tmp, file, i_descDpiOf(opts));
end

function ok = i_shotAxPotCalibJpg(fig, f, file, opts, strainTot, velMult)
%I_SHOTAXPOTCALIBJPG  Sama i_shotAxPotCalib (copyobj live + kalibrasi strain%/cm/s
%   + XDir reverse) tapi output JPG Quality 90 (guard ≤700KB). win=[] (full).
    ok = false;
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT) || isempty(h.recs), return; end
    nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    drawnow;
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 560]);
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    try
        ax2 = copyobj(h.axPOT, tmp);
        set(ax2,'Units','normalized','Position',[0.075 0.13 0.90 0.80]);
        try, delete(findall(ax2,'Tag','frameLine')); catch, end
        try, delete(findall(ax2,'Tag','frameTxt')); catch, end
        kids = get(ax2,'Children');
        for c = kids(:).'
            try
                if isprop(c,'XData') && ~isempty(get(c,'XData')), set(c,'XData', xmap(get(c,'XData'))); end
                if isprop(c,'YData') && ~isempty(get(c,'YData')), set(c,'YData', get(c,'YData') * velMult); end
                if strcmp(get(c,'Type'),'text')
                    p = get(c,'Position');
                    if numel(p) >= 2, p(1) = xmap(p(1)); p(2) = p(2)*velMult; set(c,'Position',p); end
                end
            catch
            end
        end
        if xstrain, xlabel(ax2,'Cumulative strain (%)'); else, xlabel(ax2,'Frame'); end
        ylabel(ax2,'|V| (cm/s)');
        title(ax2, sprintf('%s — fault F%s', i_baseNameSafe(h.df), i_uiNumStr(f)), ...
            'Interpreter','none','Color',[0 0 0]);
        set(ax2,'YLimMode','auto','XLimMode','auto');
        if xstrain, set(ax2,'XDir','reverse'); end
        ok = i_descExportJpg(tmp, file, i_descDpiOf(opts));
    catch
        ok = false;
    end
end

function ok = i_descShotAxSlip(fig, f, file, opts, strainTot, velMult)
%I_DESCSHOTAXSLIP  Render AX SLIP (net-slip HW−FW sesar f) -> `file` JPG. Perlakuan
%   SAMA seperti AX POT export: X = cumulative strain % (0 KIRI, dibalik),
%   Y = cm/s (ns*velMult), arsir luas START..END + 4 garis vertikal POI bertingkat.
%   (Meniru i_shotNetslipCalib GRAIN5 tapi output JPG ≤700KB.) Hanya bila HW & FW ada.
    ok = false;
    h = guidata(fig);
    [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    if ~(okHW && okFW) || isempty(ns), return; end
    nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    y = ns(:).' * velMult;                       % cm/s
    x = 1:numel(y);
    gd = isfinite(y); if ~any(gd), return; end

    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 520]);
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top'); grid(ax,'on');
    hold(ax,'on');
    plot(ax, xmap(x(gd)), y(gd), '-', 'Color',[0.45 0.10 0.65], 'LineWidth',2.4);
    % Arsir luas START..END.
    a = f.startF; b = f.endF;
    if isfinite(a) && isfinite(b)
        a = max(1,round(min(a,b))); b = min(numel(y),round(max(a,b)));
        ia = a:b; ya = y(ia); gg = isfinite(ya);
        if sum(gg) >= 2
            xa = xmap(ia(gg)); ta = ya(gg);
            fill(ax, [xa fliplr(xa)], [ta zeros(1,numel(ta))], [0.55 0.30 0.75], ...
                'FaceAlpha',0.25,'EdgeColor','none');
        end
    end
    % Titik + garis vertikal POI (tinggi bertingkat).
    yl = [min(0,min(y(gd))) max(y(gd))]; if yl(2)<=yl(1), yl(2)=yl(1)+1; end
    poi = {'startF','START',0; 'nuc','NUC',1; 'fsr','FSR',2; 'endF','END',3};
    step = 0.075*(yl(2)-yl(1));
    for pk = 1:size(poi,1)
        kf = f.(poi{pk,1}); if ~(isscalar(kf)&&isfinite(kf)&&kf>=1&&kf<=numel(y)), continue; end
        kf = round(kf); col = pivcore.pot.snapPoints.color(lower(poi{pk,2}));
        yv = y(kf);
        if isfinite(yv)
            plot(ax, xmap(kf), yv, 'o','MarkerSize',5,'LineWidth',1.2, ...
                'MarkerEdgeColor',col,'MarkerFaceColor','w');
        end
        yLab = yl(2) - poi{pk,3}*step;
        plot(ax, [xmap(kf) xmap(kf)], [yl(1) yLab], '--','Color',[col 0.85],'LineWidth',1.1);
        st = i_frameToStrain(kf, nF, strainTot);
        if isfinite(st), lbl = sprintf('%s %.2f%%', poi{pk,2}, st); else, lbl = sprintf('%s f%d', poi{pk,2}, kf); end
        text(ax, xmap(kf), yLab, lbl, 'Color',col,'FontSize',7.5,'FontWeight','bold', ...
            'VerticalAlignment','top','HorizontalAlignment','center', ...
            'BackgroundColor',[1 1 1 0.6],'Margin',1);
    end
    hold(ax,'off');
    if xstrain, xlabel(ax,'Cumulative strain (%)'); set(ax,'XDir','reverse'); else, xlabel(ax,'Frame'); end
    ylabel(ax,'net-slip (cm/s)');
    title(ax, sprintf('%s — net-slip F%s', i_baseNameSafe(h.df), i_uiNumStr(f)), ...
        'Interpreter','none','Color',[0 0 0]);
    ok = i_descExportJpg(tmp, file, i_descDpiOf(opts));
end

function ok = i_descExportJpg(figH, file, dpi)
%I_DESCEXPORTJPG  Ekspor figure ke JPG Quality 90 dgn guard ≤700KB. R2025b
%   exportgraphics TAK menerima 'Quality' -> render ke PNG temp lalu imwrite JPG
%   (Quality dikontrol; turunkan bertahap bila > 700KB, min 55).
    ok = false;
    tmpPng = [tempname '.png'];
    cu = onCleanup(@() i_descRmFile(tmpPng)); %#ok<NASGU>
    try
        exportgraphics(figH, tmpPng, 'Resolution', dpi);
        img = imread(tmpPng);
        if size(img,3) == 1, img = repmat(img,1,1,3); end   % jpg butuh RGB/gray konsisten
        q = 90;
        imwrite(img, file, 'jpg', 'Quality', q);
        ok = true;
        while true
            d = dir(file);
            if isempty(d) || d.bytes <= 700e3 || q <= 55, break; end
            q = q - 10;
            imwrite(img, file, 'jpg', 'Quality', q);
        end
    catch
        ok = false;
    end
end

function i_descRmFile(p)
    try, if isfile(p), delete(p); end, catch, end
end

function dpi = i_descDpiOf(opts)
    dpi = 150;
    if isstruct(opts) && isfield(opts,'dpi') && isscalar(opts.dpi) && opts.dpi>0, dpi = opts.dpi; end
end

function dpi = i_descDpi(h)
    dpi = 150;
    if isfield(h,'descDpi') && isscalar(h.descDpi) && h.descDpi>0, dpi = h.descDpi; end
end

function v = i_descVelMult(h)
    v = 0.005;
    if isfield(h,'descVelMult') && isscalar(h.descVelMult) && h.descVelMult>0, v = h.descVelMult; end
end

function cal = i_descCalib(h)
%I_DESCCALIB  Rakit KALIBRASI ruang-waktu untuk Commit/JSON — REUSE fungsi murni
%   yang sudah dipakai jalur Report PDF supaya net-slip cm/s berdimensi BENAR
%   (bukan konstanta 0.005). Field:
%     velMultGeom   cm/s per (px/frame) dari geometri indenter (NaN bila tak lengkap)
%     velMultUsed   = velMultGeom bila finite>0, else fallback i_descVelMult (0.005)
%     velMultSource 'geom' | 'fallback'
%     dxCm          total geser indenter (cm) dari experiment_geometry
%     dtSec         detik/frame (EXIF; fallback 10)
%     dtSource      'exif_meta.dt_mean_s' | 'exif_median' | 'fallback10'
%     indenterMax   puncak envelope kurva POT (px/frame)
%     refHorizonDeg sudut referensi horizontal (koreksi kemiringan kamera; NaN=off)
    cal = struct('velMultGeom',NaN,'velMultUsed',NaN,'velMultSource','fallback', ...
        'dxCm',NaN,'dtSec',NaN,'dtSource','fallback10','indenterMax',NaN,'refHorizonDeg',NaN);
    indMax = i_reportIndenterMax(h);
    dtSec  = NaN;
    try, dtSec = pivcore.io.grain4Report.readDtMean(h.df); catch, end
    if ~(isscalar(dtSec) && isfinite(dtSec) && dtSec>0), dtSec = 10; end
    vm = NaN; vmInfo = struct('dxCm',NaN,'source','fallback');
    try, [vm, vmInfo] = pivcore.io.grain4Report.velMultGeom(h.df, indMax, dtSec, h.nF); catch, end
    fallback = i_descVelMult(h);
    if isscalar(vm) && isfinite(vm) && vm > 0
        used = vm; src = 'geom';
    else
        used = fallback; src = 'fallback';
    end
    cal.velMultGeom   = vm;
    cal.velMultUsed   = used;
    cal.velMultSource = src;
    if isstruct(vmInfo) && isfield(vmInfo,'dxCm'), cal.dxCm = vmInfo.dxCm; end
    cal.dtSec         = dtSec;
    try, cal.dtSource = i_reportDtSource(h.df); catch, end
    cal.indenterMax   = indMax;
    cal.refHorizonDeg = i_faultRefDeg(h);
end

function s = i_descNowStr()
    try, s = char(datetime('now','Format','yyyy-MM-dd HH:mm')); catch, s = ''; end
end

function i_onCommitCancel(fig)
%I_ONCOMMITCANCEL  Set flag CANCEL -> loop Commit berhenti di iterasi berikutnya.
    h = guidata(fig); h.commitCancel = true; guidata(fig, h);
    i_setDescStatus(fig, 'Membatalkan Commit… (menunggu frame berjalan selesai)');
    drawnow;
end

function i_commitBtnState(fig, running)
%I_COMMITBTNSTATE  running=true: sembunyikan Commit, tampilkan Cancel. false:
%   sebaliknya (reset). Aman bila handle absen.
    h = guidata(fig);
    if isfield(h,'btnCommit') && ishghandle(h.btnCommit)
        set(h.btnCommit,'Visible', pivui.grain5Fmt.tern(running,'off','on'));
    end
    if isfield(h,'btnCommitAll') && ishghandle(h.btnCommitAll)
        set(h.btnCommitAll,'Visible', pivui.grain5Fmt.tern(running,'off','on'));
    end
    if isfield(h,'btnCommitCancel') && ishghandle(h.btnCommitCancel)
        set(h.btnCommitCancel,'Visible', pivui.grain5Fmt.tern(running,'on','off'));
    end
    if ~running, h.commitCancel = false; guidata(fig, h); end
    drawnow limitrate;
end

function ok = i_confirmCleanExport(fig, expDir)
%I_CONFIRMCLEANEXPORT  Konfirmasi 2x sebelum menghapus SEMUA commit lama exp.
%   Headless (quiet) -> anggap sudah dikonfirmasi (checkbox = niat eksplisit).
    ok = false;
    if pivui.quiet(), ok = true; return; end
    [~, base] = fileparts(fileparts(expDir));   % nama exp folder induk
    m1 = sprintf(['HAPUS SEMUA hasil commit lama untuk eksperimen ini?\n\n%s\n\n' ...
        'Seluruh folder versi commit sebelumnya akan DIHAPUS PERMANEN sebelum ekspor baru.'], expDir);
    b1 = questdlg(m1, '⚠ Hapus commit lama (1/2)', 'Ya, hapus', 'Batal', 'Batal');
    if ~strcmp(b1,'Ya, hapus'), return; end
    m2 = 'KONFIRMASI TERAKHIR: benar-benar hapus semua commit lama? Tindakan ini TIDAK bisa dibatalkan.';
    b2 = questdlg(m2, '⚠⚠ Hapus commit lama (2/2)', 'Ya, hapus permanen', 'Batal', 'Batal');
    ok = strcmp(b2,'Ya, hapus permanen');
end

function wb = i_descWaitbar(msg)
    wb = [];
    if pivui.quiet(), return; end
    try, wb = waitbar(0, msg, 'Name','GRAIN4 Commit'); catch, wb = []; end
end
function i_descCloseWb(wb)
    try, if ~isempty(wb) && ishghandle(wb), close(wb); end, catch, end
end


% =====================================================================
% 🎬 EXPORT MP4 — AX main (velmag & shear) SEMUA frame -> 2 file MP4.
%   Reuse renderer LIVE i_descShotAxMain (GS + glyph + CLim + sumbu cm +
%   garis PSG oranye), tapi tiap frame -> getframe RGB -> VideoWriter.
%   Folder ber-versi PAB4_DESC/<exp>/<ts>_<psgName>_mp4/. Cancel bertumpuk.
% =====================================================================
function i_onExportMovie(fig)
%I_ONEXPORTMOVIE  Rakit 2 MP4 (velmag.mp4 & shear.mp4) berisi SELURUH frame
%   AX main dgn setting tampilan LIVE untuk EKSPERIMEN AKTIF SAJA. fps dari
%   target durasi (kotak input). Frame render off-screen ukuran TETAP.
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    % Cancel: siapkan flag + tampilkan tombol Cancel (menutupi kedua tombol MP4).
    h.movieCancel = false; guidata(fig, h);
    i_movieBtnState(fig, true);
    cuBtn = onCleanup(@() i_movieBtnState(fig, false)); %#ok<NASGU>

    res = i_exportMovieCurExp(fig);   % render exp AKTIF -> struct hasil
    if isempty(res), return; end
    if res.cancelled
        i_setDescStatus(fig, 'Export MP4 dibatalkan (file parsial dihapus).');
        return;
    end
    i_setDescStatus(fig, sprintf('MP4 selesai: %d file (%.2g fps ≈ %.1fs) -> %s', ...
        numel(res.written), res.fps, res.durActual, res.movDir));
    if ~pivui.quiet()
        try, msgbox(sprintf(['Export MP4 AX main selesai.\n\n%d frame × 2 (velmag + shear)\n' ...
            'Durasi ≈ %.1f detik @ %.2g fps.\n\nFolder:\n%s'], res.nF, res.durActual, res.fps, res.movDir), ...
            'GRAIN4 — MP4 AX main'); catch, end
    end
end


function i_onExportFrameImg(fig)
%I_ONEXPORTFRAMEIMG  Ekspor AX main bingkai (rentang dari kotak "Frame img")
%   -> 2 JPG (velmag + shear) per bingkai ke folder ber-versi ..._frames/.
%   REUSE i_movieFrameRGB (renderer LIVE, sama persis dgn MP4: GS + glyph +
%   CLim + sumbu cm dari kolom tengah). TIDAK menyentuh MP4 / commit / katalog.
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    % Pastikan SEMUA bingkai termuat (nF benar) sebelum parse rentang.
    nF = i_ensureFullFrames(fig); h = guidata(fig);
    rngTxt = '';
    if isfield(h,'edFrameRange') && ishghandle(h.edFrameRange)
        rngTxt = strtrim(get(h.edFrameRange,'String'));
    end
    frames = i_parseFrameRange(rngTxt, h.frame, nF);
    if isempty(frames)
        i_setDescStatus(fig, sprintf('Rentang frame tak valid: "%s" (1..%d).', rngTxt, nF)); return;
    end

    h.frameImgCancel = false; guidata(fig, h);
    i_frameImgBtnState(fig, true);
    cuBtn = onCleanup(@() i_frameImgBtnState(fig, false)); %#ok<NASGU>

    res = i_exportFramesCurExp(fig, frames);
    if isempty(res)
        i_setDescStatus(fig, 'Ekspor gambar gagal (tak ada data).'); return;
    end
    if res.cancelled
        i_setDescStatus(fig, sprintf('Ekspor gambar DIBATALKAN (%d JPG tertulis).', res.written)); return;
    end
    i_setDescStatus(fig, sprintf('🖼 Ekspor gambar selesai: %d JPG (%d bingkai × 2) -> %s', ...
        res.written, res.nFr, res.outDir));
    if ~pivui.quiet()
        try, msgbox(sprintf(['Ekspor gambar AX main selesai.\n\n%d bingkai × 2 (velmag + shear) = %d JPG.\n\n' ...
            'Folder:\n%s'], res.nFr, res.written, res.outDir), 'GRAIN4 — Ekspor frame'); catch, end
    end
end


function i_onExportFramesExpCur(fig)
%I_ONEXPORTFRAMESEXPCUR  Ekspor SEMUA bingkai (1..nF) EKSPERIMEN AKTIF -> JPG
%   (velmag + shear). Sama seperti tombol rentang tapi rentang = seluruh exp.
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    nF = i_ensureFullFrames(fig);
    h = guidata(fig); h.frameImgCancel = false; guidata(fig, h);
    i_frameImgBtnState(fig, true);
    cuBtn = onCleanup(@() i_frameImgBtnState(fig, false)); %#ok<NASGU>

    res = i_exportFramesCurExp(fig, 1:nF);
    if isempty(res)
        i_setDescStatus(fig, 'Ekspor gambar gagal (tak ada data).'); return;
    end
    if res.cancelled
        i_setDescStatus(fig, sprintf('Ekspor semua bingkai DIBATALKAN (%d JPG tertulis).', res.written)); return;
    end
    i_setDescStatus(fig, sprintf('🖼 Semua bingkai exp ini selesai: %d JPG (%d bingkai × 2) -> %s', ...
        res.written, res.nFr, res.outDir));
    if ~pivui.quiet()
        try, msgbox(sprintf(['Ekspor semua bingkai (exp ini) selesai.\n\n%d bingkai × 2 = %d JPG.\n\n' ...
            'Folder:\n%s'], res.nFr, res.written, res.outDir), 'GRAIN4 — Ekspor frame'); catch, end
    end
end


function i_onExportFramesAllExp(fig)
%I_ONEXPORTFRAMESALLEXP  Ekspor SEMUA bingkai (1..nF) untuk SEMUA eksperimen
%   yang dimuat dari folder (pola i_onExportMovieAll). Setelan tampilan (kolom
%   tengah) SAMA untuk tiap exp. Eksperimen & garis PSG semula dipulihkan.
%   Cancel via tombol bersama (h.frameImgCancel).
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list)
        i_setDescStatus(fig, 'Belum ada daftar eksperimen (pilih folder dulu).'); return;
    end
    N = numel(h.list);
    origRow = 1; if isfield(h,'activeRow') && isscalar(h.activeRow) && h.activeRow>=1, origRow = h.activeRow; end
    origPsg = ''; if isfield(h,'activePsgId'), origPsg = h.activePsgId; end

    if ~pivui.quiet()
        b = questdlg(sprintf(['Ekspor gambar SEMUA bingkai untuk SEMUA %d eksperimen?\n\n' ...
            'Tiap exp: seluruh bingkai (1..akhir) × 2 (velmag + shear) JPG ke folder ber-versi.\n' ...
            'Setelan tampilan (kolom tengah) SAMA untuk semua. Bisa memakan waktu.'], N), ...
            '🖼 Ekspor gambar semua exp', 'Ya, ekspor semua', 'Batal', 'Batal');
        if ~strcmp(b, 'Ya, ekspor semua')
            i_setDescStatus(fig, 'Ekspor gambar semua exp dibatalkan.'); return;
        end
    end

    h.frameImgCancel = false; guidata(fig, h);
    i_frameImgBtnState(fig, true);
    cuBtn = onCleanup(@() i_frameImgBtnState(fig, false)); %#ok<NASGU>

    nExpOk = 0; nFileTot = 0; cancelled = false;
    for i = 1:N
        h = guidata(fig);
        if isfield(h,'frameImgCancel') && h.frameImgCancel, cancelled = true; break; end
        nm = h.list(i).name;
        i_setDescStatus(fig, sprintf('Gambar semua exp %d/%d: %s — memuat…', i, N, nm));
        try, h.tbl.Selection = i; catch, end
        pivui.grain4Shell.loadExperiment(fig, i);   % frame-1 (helper akan ensureFull)
        nF = i_ensureFullFrames(fig);
        res = i_exportFramesCurExp(fig, 1:nF, sprintf('%d/%d: %s', i, N, nm));
        if isempty(res), continue; end
        if res.cancelled, cancelled = true; break; end
        nExpOk = nExpOk + 1; nFileTot = nFileTot + res.written;
    end

    % --- PULIHKAN eksperimen & garis PSG semula ---
    i_setDescStatus(fig, 'Memulihkan eksperimen semula…');
    try, h = guidata(fig); h.tbl.Selection = origRow; catch, end
    pivui.grain4Shell.loadExperiment(fig, origRow);
    if ~isempty(origPsg)
        h = guidata(fig);
        if any(strcmp(i_realPsgIds(h.doc), origPsg)), i_activateLineById(fig, origPsg); end
    end

    if cancelled
        i_setDescStatus(fig, sprintf('Gambar semua exp DIBATALKAN. Sebelum batal: %d exp (%d JPG) selesai.', nExpOk, nFileTot));
        return;
    end
    i_setDescStatus(fig, sprintf('🖼 Gambar SEMUA exp selesai: %d/%d exp (%d JPG).', nExpOk, N, nFileTot));
    if ~pivui.quiet()
        try, msgbox(sprintf(['Ekspor gambar (semua exp) selesai.\n\n' ...
            '%d/%d eksperimen -> %d JPG (velmag + shear).'], nExpOk, N, nFileTot), ...
            'GRAIN4 — Ekspor frame semua exp'); catch, end
    end
end


function res = i_exportFramesCurExp(fig, frames, tag)
%I_EXPORTFRAMESCUREXP  Render AX main tiap bingkai di `frames` -> 2 JPG (velmag
%   + shear) ke folder ber-versi ..._frames/ utk EKSPERIMEN AKTIF. Dipakai
%   bersama i_onExportFrameImg (rentang), i_onExportFramesExpCur (semua frame
%   exp ini) & i_onExportFramesAllExp (loop semua exp). Hormati flag
%   h.frameImgCancel. `tag` (opsional) = konteks untuk waitbar. TIDAK menyentuh
%   tombol/msgbox (caller yang urus). Return struct(written,nFr,outDir,cancelled);
%   [] bila tak ada data.
    res = [];
    if nargin < 3, tag = ''; end
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data), return; end

    nF = max(1, pivcore.data.frameCount(h.data));
    frames = frames(frames >= 1 & frames <= nF);
    if isempty(frames), return; end

    % Folder ber-versi (induk GRAIN/ atau override tes).
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
        if ~isfolder(grainRoot), try, mkdir(grainRoot); catch, end, end
    end
    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride), ts = h.exportStampOverride; end
    psgName = h.activePsgId; if isempty(psgName), psgName = 'PSG'; end
    outDir = pivcore.io.grain4DescExport.framesDir(grainRoot, h.df, ts, psgName);
    if ~isfolder(outDir), mkdir(outDir); end

    velMult   = i_descVelMult(h);
    strainTot = i_strainTotalSafe(h);
    % axPos: kotak-plot axMain (NORMALIZED). Ukuran figure DIHITUNG dari aspek
    % GAMBAR (ekstent grid px) supaya kotak-plot = ukuran gambar (tak letterbox,
    % tak seperti tampilan default axMain di GRAIN4). Margin: kiri/atas kecil,
    % kanan utk colorbar, bawah utk label state.
    axPos = [0.045 0.070 0.800 0.850];
    [figW, figH] = i_frameImgFigSize(h, axPos);
    opts = struct('dpi', i_descDpi(h), 'velMult', velMult, 'axPos', axPos);
    opts.gsCache = containers.Map('KeyType','char','ValueType','any');
    cuGs = onCleanup(@() i_mapClear(opts.gsCache)); %#ok<NASGU>

    frame0  = h.frame;
    scalars = pivcore.io.grain4DescExport.scalarNames();   % {'velmag','shear'}
    nFr = numel(frames);
    pfx = ''; if ~isempty(tag), pfx = [char(tag) ' — ']; end
    wb = i_descWaitbar(sprintf('%sEkspor %d bingkai × 2 (velmag + shear)…', pfx, nFr));
    cuw = onCleanup(@() i_descCloseWb(wb)); %#ok<NASGU>

    % Figure off-screen REUSE: ukuran = aspek gambar (dibuat sekali, cla per-frame).
    movFig = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 figW figH]);
    try, pivui.forceLightTheme(movFig); catch, end
    set(movFig,'Color','w');
    cuFig = onCleanup(@() i_closeIf(movFig)); %#ok<NASGU>

    written = 0; cancelled = false;
    for ii = 1:nFr
        hc = guidata(fig);
        if isfield(hc,'frameImgCancel') && hc.frameImgCancel, cancelled = true; break; end
        k = frames(ii);
        pivui.grain4Shell.setFrameQuiet(fig, k);   % pindah frame (skip render live)
        for si = 1:numel(scalars)
            sc = scalars{si};
            rgb = i_movieFrameRGB(fig, movFig, sc, k, opts, strainTot);
            if isempty(rgb), continue; end
            fn = pivcore.io.grain4DescExport.frameImgFile(h.df, sc, k, 'jpg');
            try, imwrite(rgb, fullfile(outDir, fn), 'jpg', 'Quality', 92); written = written + 1; catch, end
        end
        if ~isempty(wb) && ishghandle(wb)
            try, waitbar(ii/nFr, wb, sprintf('%sFrame %d (%d/%d)…', pfx, k, ii, nFr)); catch, end
        end
    end

    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end
    res = struct('written',written, 'nFr',nFr, 'outDir',outDir, 'cancelled',cancelled);
end


function nF = i_ensureFullFrames(fig)
%I_ENSUREFULLFRAMES  Pastikan SEMUA bingkai exp aktif termuat (bukan hanya
%   sampling), lalu kembalikan jumlah bingkai nyata. Andalkan JUMLAH data nyata
%   (bukan flag h.fullLoaded yang bisa basi setelah pindah exp).
    h = guidata(fig);
    nTot = max(1, round(pivcore.util.scalarOr(h.nF, 1)));
    if pivcore.data.frameCount(h.data) < nTot
        h.fullLoaded = false; guidata(fig, h);        % bersihkan flag basi
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    nF = max(1, pivcore.data.frameCount(h.data));
end


function i_onFrameImgCancel(fig)
%I_ONFRAMEIMGCANCEL  Set flag CANCEL -> loop ekspor gambar berhenti di bingkai
%   berikutnya (baik rentang, semua-frame, maupun semua-exp).
    h = guidata(fig); h.frameImgCancel = true; guidata(fig, h);
    i_setDescStatus(fig, 'Membatalkan ekspor gambar… (menunggu bingkai berjalan selesai)');
    drawnow;
end


function i_frameImgBtnState(fig, running)
%I_FRAMEIMGBTNSTATE  running=true: sembunyikan 3 tombol gambar, tampilkan Cancel.
    h = guidata(fig);
    ids = {'btnFrameImg','btnFrameExp','btnFrameAllExp'};
    for i = 1:numel(ids)
        if isfield(h,ids{i}) && ishghandle(h.(ids{i}))
            set(h.(ids{i}),'Visible', pivui.grain5Fmt.tern(running,'off','on'));
        end
    end
    if isfield(h,'btnFrameImgCancel') && ishghandle(h.btnFrameImgCancel)
        set(h.btnFrameImgCancel,'Visible', pivui.grain5Fmt.tern(running,'on','off'));
    end
    if ~running, h.frameImgCancel = false; guidata(fig, h); end
    drawnow limitrate;
end


function frames = i_parseFrameRange(txt, curFrame, nF)
%I_PARSEFRAMERANGE  Uraikan teks rentang bingkai -> vektor indeks terurut,
%   di-clamp ke [1..nF]. Kosong -> [curFrame]. Format: "N" | "A-B" | "A:B".
    frames = [];
    txt = strtrim(char(txt));
    if isempty(txt)
        frames = min(max(1, round(curFrame)), max(1,nF)); return;
    end
    txt = strrep(txt, ':', '-');
    parts = strtrim(strsplit(txt, '-'));
    if isempty(parts) || numel(parts) > 2, return; end
    nums = str2double(parts);
    if any(isnan(nums)), return; end          % non-numeric -> tolak
    a = nums(1);
    if numel(nums) >= 2, b = nums(2); else, b = a; end
    if ~isfinite(a) || ~isfinite(b), return; end
    a = round(a); b = round(b);
    if a > b, t = a; a = b; b = t; end
    a = max(1, a); b = min(nF, b);
    if a > b, return; end
    frames = a:b;
end


function [figW, figH] = i_frameImgFigSize(h, axPos)
%I_FRAMEIMGFIGSIZE  Ukuran figure (piksel) supaya KOTAK-PLOT axMain (rect axPos)
%   ber-aspek SAMA dgn GAMBAR (ekstent grid px), sisi-panjang kotak-plot ~ 1600
%   px (di-clamp). Dgn daspect 1:1, kotak-plot lalu terisi PENUH oleh gambar
%   -> ekspor = ukuran gambar, tanpa letterbox. Fallback aman 1120×560.
    figW = 1120; figH = 560;
    try
        xg = pivcore.data.safeFrame(h.data.x, 1);
        yg = pivcore.data.safeFrame(h.data.y, 1);
        if isempty(xg) || isempty(yg), return; end
        imgW = max(xg(:)) - min(xg(:));
        imgH = max(yg(:)) - min(yg(:));
        if ~(imgW > 0) || ~(imgH > 0), return; end
        targetLong = 1600;                       % sisi-panjang kotak-plot (px)
        s = targetLong / max(imgW, imgH);
        plotW = imgW * s; plotH = imgH * s;      % kotak-plot = gambar (skala)
        aw = axPos(3); ah = axPos(4);
        figW = round(plotW / aw);                % kotak-plot mengisi rect axPos
        figH = round(plotH / ah);
        figW = max(300, min(4000, figW));
        figH = max(200, min(4000, figH));
    catch
        figW = 1120; figH = 560;
    end
end


function i_onExportMovieAll(fig)
%I_ONEXPORTMOVIEALL  Rakit MP4 AX main (velmag+shear) untuk SEMUA eksperimen
%   di folder. Tiap exp dimuat bergiliran (pola i_onCommitAllExp: loadExperiment
%   -> ensureFull di helper), lalu i_exportMovieCurExp. TARGET DURASI (detik)
%   SAMA untuk semua exp (kotak input): fps per-exp = nFrame_exp / durasi, jadi
%   semua video berdurasi ≈ target yang sama walau jumlah frame beda. Eksperimen
%   & garis PSG semula dipulihkan di akhir. Cancel via tombol Cancel bersama.
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list)
        i_setDescStatus(fig, 'Belum ada daftar eksperimen (pilih folder dulu).'); return;
    end
    N = numel(h.list);
    origRow = 1; if isfield(h,'activeRow') && isscalar(h.activeRow) && h.activeRow>=1, origRow = h.activeRow; end
    origPsg = ''; if isfield(h,'activePsgId'), origPsg = h.activePsgId; end

    durSec = i_movieTargetDur(h);
    durTxt = '(kosong -> 5 fps)'; if isfinite(durSec) && durSec>0, durTxt = sprintf('%.4g detik', durSec); end
    if ~pivui.quiet()
        b = questdlg(sprintf(['Export MP4 AX main untuk SEMUA %d eksperimen?\n\n' ...
            'Tiap exp -> velmag.mp4 & shear.mp4 (SEMUA frame) ke folder ber-versi.\n' ...
            'Target durasi SAMA %s untuk tiap video (fps menyesuaikan jumlah frame).\n' ...
            'Bisa memakan waktu (semua frame tiap exp dimuat).'], N, durTxt), ...
            '🎬 Export MP4 semua exp', 'Ya, ekspor semua', 'Batal', 'Batal');
        if ~strcmp(b, 'Ya, ekspor semua')
            i_setDescStatus(fig, 'Export MP4 semua exp dibatalkan.'); return;
        end
    end

    % Cancel: siapkan flag + tampilkan tombol Cancel bersama.
    h.movieCancel = false; guidata(fig, h);
    i_movieBtnState(fig, true);
    cuBtn = onCleanup(@() i_movieBtnState(fig, false)); %#ok<NASGU>

    nExpOk = 0; nFileTot = 0; cancelled = false;
    for i = 1:N
        h = guidata(fig);
        if isfield(h,'movieCancel') && h.movieCancel, cancelled = true; break; end
        nm = h.list(i).name;
        i_setDescStatus(fig, sprintf('MP4 semua exp %d/%d: %s — memuat…', i, N, nm));
        try, h.tbl.Selection = i; catch, end
        pivui.grain4Shell.loadExperiment(fig, i);   % frame-1 + sampling POT (helper akan ensureFull)

        res = i_exportMovieCurExp(fig, sprintf('%d/%d: %s', i, N, nm));
        if isempty(res), continue; end
        if res.cancelled, cancelled = true; break; end
        if ~isempty(res.written), nExpOk = nExpOk + 1; nFileTot = nFileTot + numel(res.written); end
    end

    % --- PULIHKAN eksperimen & garis PSG semula ---
    i_setDescStatus(fig, 'Memulihkan eksperimen semula…');
    try, h = guidata(fig); h.tbl.Selection = origRow; catch, end
    pivui.grain4Shell.loadExperiment(fig, origRow);
    if ~isempty(origPsg)
        h = guidata(fig);
        if any(strcmp(i_realPsgIds(h.doc), origPsg)), i_activateLineById(fig, origPsg); end
    end

    if cancelled
        i_setDescStatus(fig, sprintf('MP4 semua exp DIBATALKAN. Sebelum batal: %d exp (%d file) selesai.', nExpOk, nFileTot));
        return;
    end
    i_setDescStatus(fig, sprintf('MP4 SEMUA exp selesai: %d/%d exp ber-video (%d file MP4).', nExpOk, N, nFileTot));
    if ~pivui.quiet()
        try, msgbox(sprintf(['Export MP4 AX main (semua exp) selesai.\n\n' ...
            '%d/%d eksperimen -> %d file MP4 (velmag + shear).\n' ...
            'Tiap video berdurasi ≈ target %s.'], nExpOk, N, nFileTot, durTxt), ...
            'GRAIN4 — MP4 semua exp'); catch, end
    end
end


function res = i_exportMovieCurExp(fig, tag)
%I_EXPORTMOVIECUREXP  Rakit 2 MP4 (velmag.mp4 & shear.mp4) untuk EKSPERIMEN
%   AKTIF. Dipakai bersama oleh i_onExportMovie (1 exp) & i_onExportMovieAll
%   (loop). TIDAK menyentuh tombol/msgbox (caller yang urus) — hanya render +
%   set status waitbar. `tag` (opsional) = teks konteks utk waitbar (mis. exp
%   i/N). Return struct(written,movDir,fps,durActual,nF,cancelled); [] bila
%   tak ada data / gagal buka VideoWriter.
    res = [];
    if nargin < 2, tag = ''; end
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    tagPfx = ''; if ~isempty(tag), tagPfx = [tag ' — ']; end

    % Pastikan semua frame termuat (velmag/shear per-frame).
    if ~pivcore.util.isFullLoaded(h)
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    nF = max(1, pivcore.util.scalarOr(h.imgFrames, h.nF));
    % TES: batasi jumlah frame (jalur render nyata, cepat) via h.movieMaxFrames.
    if isfield(h,'movieMaxFrames') && isscalar(h.movieMaxFrames) && h.movieMaxFrames>0
        nF = min(nF, round(h.movieMaxFrames));
    end

    % Folder ber-versi (induk GRAIN/ atau override tes).
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
        if ~isfolder(grainRoot), try, mkdir(grainRoot); catch, end, end
    end
    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride)
        ts = h.exportStampOverride;
    end
    psgName = h.activePsgId; if isempty(psgName), psgName = 'PSG'; end
    movDir = pivcore.io.grain4DescExport.movieDir(grainRoot, h.df, ts, psgName);
    if ~isfolder(movDir), mkdir(movDir); end

    % FPS dari TARGET DURASI (detik) di kotak input: fps = nF / durasi.
    % Kosong / tak valid / <=0 -> fallback 5 fps. Clamp fps ke [0.1 .. 120].
    durSec = i_movieTargetDur(h);              % NaN bila kotak kosong/tak valid
    if isfinite(durSec) && durSec > 0
        fps = nF / durSec;
    else
        fps = 5;                                % fallback (durasi tak diisi)
    end
    fps = max(0.1, min(120, fps));
    durActual = nF / fps;                       % durasi nyata (untuk status)
    velMult   = i_descVelMult(h);
    strainTot = i_strainTotalSafe(h);
    opts = struct('dpi', i_descDpi(h), 'velMult', velMult);
    opts.gsCache = containers.Map('KeyType','char','ValueType','any');
    cuGs = onCleanup(@() i_mapClear(opts.gsCache)); %#ok<NASGU>

    % state utk restore (setFrameQuiet mengubah frame live)
    frame0 = h.frame;

    % Cancel: flag + tombol Cancel DIURUS CALLER (i_onExportMovie / ...All) supaya
    % satu tombol Cancel menutupi seluruh sesi (1 exp atau loop semua exp).

    wb = i_descWaitbar(sprintf('%sRakit MP4 AX main (%d frame × 2, %.2g fps ≈ %.1fs)…', tagPfx, nF, fps, durActual));
    cuw = onCleanup(@() i_descCloseWb(wb)); %#ok<NASGU>

    scalars = pivcore.io.grain4DescExport.scalarNames();  % {'velmag','shear'}
    written = {}; cancelled = false;

    % --- OPTIMASI KECEPATAN (2026-07-13) ---
    % (1) Kedua skalar dirender dalam SATU loop frame (2 VideoWriter aktif) ->
    %     GS+CLAHE (gsCache) frame k dipakai ULANG utk velmag & shear (GS identik).
    % (2) Figure+axes off-screen dibuat SEKALI, di-cla tiap frame (bukan buat/buang
    %     figure 696×; hemat ~30ms/frame + hindari kebocoran handle).
    % (3) TANPA `drawnow` terpisah: getframe sudah memicu render yang diperlukan.
    %     drawnow off-screen di macOS ~600ms/frame = 68% waktu -> DIBUANG.
    % Hasil: ~900ms -> ~250ms per frame-render (≈3.5× lebih cepat).

    % Buka 2 VideoWriter sekaligus.
    vws = struct('sc',{},'vw',{},'file',{},'size',{});
    for si = 1:numel(scalars)
        sc = scalars{si};
        outFile = fullfile(movDir, pivcore.io.grain4DescExport.movieFile(h.df, sc));
        vw = VideoWriter(outFile, 'MPEG-4'); %#ok<TNMLP>
        vw.FrameRate = fps; vw.Quality = 90;
        try, open(vw); catch ME
            i_setDescStatus(fig, sprintf('%sGAGAL buka VideoWriter: %s', tagPfx, ME.message));
            try, close(vw); catch, end
            for j=1:numel(vws), i_movieCloseVw(vws(j).vw); end
            return;   % res tetap [] -> caller lanjut exp berikutnya (mode semua)
        end
        vws(end+1) = struct('sc',sc,'vw',vw,'file',outFile,'size',[]); %#ok<AGROW>
    end
    cuVws = onCleanup(@() i_movieCloseAll(vws)); %#ok<NASGU>

    % Figure + axes off-screen REUSE (dibuat sekali).
    movFig = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 1120 560]);
    try, pivui.forceLightTheme(movFig); catch, end
    set(movFig,'Color','w');
    cuFig = onCleanup(@() i_closeIf(movFig)); %#ok<NASGU>

    nWritten = zeros(1,numel(vws));
    for k = 1:nF
        hc = guidata(fig);
        if isfield(hc,'movieCancel') && hc.movieCancel, cancelled = true; break; end
        pivui.grain4Shell.setFrameQuiet(fig, k);   % pindah frame (skip render live)

        for si = 1:numel(vws)
            rgb = i_movieFrameRGB(fig, movFig, vws(si).sc, k, opts, strainTot);
            if isempty(rgb), continue; end
            if isempty(vws(si).size)
                vws(si).size = [size(rgb,1) size(rgb,2)];
            elseif ~isequal([size(rgb,1) size(rgb,2)], vws(si).size)
                rgb = i_movieFitSize(rgb, vws(si).size);   % samakan dimensi
            end
            try, writeVideo(vws(si).vw, rgb); nWritten(si)=nWritten(si)+1; catch, end
        end

        if ~isempty(wb) && ishghandle(wb)
            try, waitbar(k/nF, wb, sprintf('%sMP4 frame %d/%d (velmag+shear)…', tagPfx, k, nF)); catch, end
        end
        if mod(k,8)==0, drawnow limitrate; end   % beri kesempatan tombol Cancel (jarang)
    end

    % tutup semua VideoWriter (flush ke disk).
    for si = 1:numel(vws)
        i_movieCloseVw(vws(si).vw);
        if ~cancelled && nWritten(si)>0, written{end+1} = vws(si).file; end %#ok<AGROW>
    end
    if cancelled
        for si = 1:numel(vws)
            try, if isfile(vws(si).file), delete(vws(si).file); end, catch, end
        end
    end

    % restore frame live
    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end

    if cancelled
        try, if isfolder(movDir) && numel(dir(movDir))<=2, rmdir(movDir,'s'); end, catch, end
    end
    % Kembalikan hasil ke caller (caller yang set status akhir & msgbox).
    res = struct('written',{written}, 'movDir',movDir, 'fps',fps, ...
        'durActual',durActual, 'nF',nF, 'cancelled',cancelled);
end


function rgb = i_movieFrameRGB(fig, movFig, scalar, k, opts, strainTot)
%I_MOVIEFRAMERGB  Render AX main frame k (velmag/shear) ke figure off-screen
%   REUSE `movFig` (dibuat sekali oleh i_onExportMovie) -> getframe RGB. Tak
%   menulis file. Figure PIXEL TETAP [1120x560] -> dimensi frame konsisten.
%   OPTIMASI: cla per-frame (bukan buat/buang figure); TANPA drawnow terpisah
%   (getframe sudah memicu render); gsCache dibagi velmag+shear (GS identik).
    rgb = [];
    h = guidata(fig);
    if isempty(h.data), return; end
    scKey = 'velocity_magnitude'; if strcmp(scalar,'shear'), scKey = 'shear'; end
    kk = max(1, min(round(k), pivcore.util.scalarOr(h.imgFrames,1)));
    velMult = 0.005;
    if isstruct(opts) && isfield(opts,'velMult') && isscalar(opts.velMult) && opts.velMult>0
        velMult = opts.velMult;
    end

    if isempty(movFig) || ~ishghandle(movFig), return; end
    clf(movFig);                       % bersihkan sisa frame sebelumnya (reuse)
    % axPos opsional: posisi axes NORMALIZED [x y w h]. Dipakai ekspor GAMBAR
    % (i_onExportFrameImg) supaya kotak-plot axMain = aspek gambar (tak
    % letterbox). MP4 tak mengirim -> pakai default (dimensi frame tetap).
    haveAxPos = isstruct(opts) && isfield(opts,'axPos') && numel(opts.axPos)==4;
    if haveAxPos
        ax = axes('Parent',movFig,'Position',opts.axPos(:)');
    else
        ax = axes('Parent',movFig);
    end
    % cfg = h -> pakai SEMUA setting tampilan kolom-tengah LIVE (CLim velmag/shear,
    % GS overlay + alpha, CLAHE, glyph tebal/spacing/warna). Untuk MP4 GLYPH DIPAKSA
    % ON (user: "GLYPH selalu ON"), tapi SPACING/tebal/warna tetap ikut kolom tengah.
    cfg = h; cfg.scalarSrc = scKey;
    cfg.glyphOn = true;   % paksa ON utk MP4 (spacing = cfg.glyphSp dari kolom tengah)
    if isstruct(opts) && isfield(opts,'gsCache') && isa(opts.gsCache,'containers.Map')
        cfg.gsCache = opts.gsCache;
    end
    isShear = strcmp(scalar,'shear');
    try
        pivcore.montage.renderScalarPanel(ax, h.data, kk, scKey, cfg);
    catch
        return;
    end
    set(ax, 'Color','w', 'XColor',[0 0 0], 'YColor',[0 0 0], 'XTick',[], 'YTick',[]);
    cb = colorbar(ax);
    if isShear
        cb.Label.String = 'shear strain (du/dy+dv/dx)';
    else
        cb.Label.String = '|V| (cm/s)';
        cl = clim(ax); t = get(cb,'Ticks');
        if isempty(t), t = linspace(cl(1), cl(2), 6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*velMult), t, 'UniformOutput', false));
    end
    set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
    % Ekspor GAMBAR (axPos): colorbar MENGGESER axes -> kembalikan axes ke axPos
    % (kotak-plot EKSAK = aspek gambar) & taruh colorbar di margin kanan.
    if haveAxPos
        set(ax, 'Position', opts.axPos(:)');
        p = opts.axPos(:)';
        set(cb, 'Position', [min(0.965, p(1)+p(3)+0.012), p(2), 0.022, p(4)]);
    end
    hold(ax,'on');
    if ~isempty(h.line) && isfield(h.line,'p1')
        plot(ax, [h.line.p1(1) h.line.p2(1)], [h.line.p1(2) h.line.p2(2)], ...
            '-', 'Color',[1 0.6 0.1], 'LineWidth',0.8);
    end
    hold(ax,'off');
    % Sumbu cm (GRAINAXCAL) bila dikalibrasi.
    if isfield(h,'axCal') && isstruct(h.axCal) && isfield(h.axCal,'enabled') && h.axCal.enabled
        xg = pivcore.data.safeFrame(h.data.x, kk); yg = pivcore.data.safeFrame(h.data.y, kk);
        if isempty(xg), xg = pivcore.data.safeFrame(h.data.x, 1); end
        if isempty(yg), yg = pivcore.data.safeFrame(h.data.y, 1); end
        if ~isempty(xg) && ~isempty(yg)
            xExt = [min(xg(:)) max(xg(:))]; yExt = [min(yg(:)) max(yg(:))];
            Rc = struct('dxCm', NaN);
            if isfield(h,'axCalR') && isfield(h.axCalR,'dxCm'), Rc.dxCm = h.axCalR.dxCm; end
            try, pivcore.export.frameCatalog.applyCmAxes(ax, h.axCal, Rc, kk, max(1,h.nF), xExt, yExt); catch, end
        end
    end
    % JUDUL: nama skalar rapi + nama eksperimen SAJA (TANPA info frame/strain).
    if isShear, scName = 'Shear Strain'; else, scName = 'Velocity Magnitude'; end
    title(ax, sprintf('%s — %s', scName, i_baseNameSafe(h.df)), ...
        'Interpreter','none', 'Color',[0 0 0]);
    % LABEL STATE per-frame PERSIS FORMAT AX MAIN LIVE: "<short> cm · <strain> % ·
    % (k/N)" (frame, cm, persen). Reuse grain4Shell.drawStrainState (sumber geom sama
    % = h.axCalR: dxCm & strainTotalPct). Komponen NaN dilewati; frame k/N selalu.
    try
        nFimg = max(1, pivcore.util.scalarOr(h.imgFrames, h.nF));
        pivui.grain4Shell.drawStrainState(fig, ax, kk, nFimg);
    catch
    end
    % TANPA drawnow terpisah: getframe memicu render yg diperlukan (drawnow
    % off-screen di macOS ~600ms/frame -> dibuang; getframe cukup).
    try
        fr = getframe(movFig);
        rgb = fr.cdata;
    catch
        rgb = [];
    end
end


function i_movieCloseAll(vws)
%I_MOVIECLOSEALL  Tutup semua VideoWriter di array struct vws (onCleanup jaga-jaga).
    for i = 1:numel(vws)
        try, i_movieCloseVw(vws(i).vw); catch, end
    end
end


function rgb = i_movieFitSize(rgb, target)
%I_MOVIEFITSIZE  Paksa RGB ke [H W] target (crop/pad) supaya VideoWriter tak
%   menolak frame dgn dimensi berbeda (getframe kadang meleset ±1 px).
    H = target(1); W = target(2);
    h0 = size(rgb,1); w0 = size(rgb,2);
    if h0 >= H, rgb = rgb(1:H,:,:); else
        rgb(h0+1:H,:,:) = 255;
    end
    if w0 >= W, rgb = rgb(:,1:W,:); else
        rgb(:,w0+1:W,:) = 255;
    end
end


function i_movieCloseVw(vw)
    try, if ~isempty(vw), close(vw); end, catch, end
end


function i_onMovieCancel(fig)
%I_ONMOVIECANCEL  Set flag CANCEL -> loop MP4 berhenti di frame berikutnya.
    h = guidata(fig); h.movieCancel = true; guidata(fig, h);
    i_setDescStatus(fig, 'Membatalkan export MP4… (menunggu frame berjalan selesai)');
    drawnow;
end


function i_movieBtnState(fig, running)
%I_MOVIEBTNSTATE  running=true: sembunyikan tombol MP4, tampilkan Cancel.
    h = guidata(fig);
    if isfield(h,'btnMovie') && ishghandle(h.btnMovie)
        set(h.btnMovie,'Visible', pivui.grain5Fmt.tern(running,'off','on'));
    end
    if isfield(h,'btnMovieAll') && ishghandle(h.btnMovieAll)
        set(h.btnMovieAll,'Visible', pivui.grain5Fmt.tern(running,'off','on'));
    end
    if isfield(h,'btnMovieCancel') && ishghandle(h.btnMovieCancel)
        set(h.btnMovieCancel,'Visible', pivui.grain5Fmt.tern(running,'on','off'));
    end
    if ~running, h.movieCancel = false; guidata(fig, h); end
    drawnow limitrate;
end


function d = i_movieTargetDur(h)
%I_MOVIETARGETDUR  Baca TARGET DURASI (detik) dari kotak edit h.edMovieDur.
%   Kosong / non-numerik / <=0 -> NaN (caller pakai fallback fps 5). Menerima
%   koma desimal (mis. "12,5"). Hook TES: h.movieTargetDur (angka) menang.
    d = NaN;
    if isfield(h,'movieTargetDur') && isscalar(h.movieTargetDur) && isnumeric(h.movieTargetDur)
        d = double(h.movieTargetDur); return;
    end
    if isfield(h,'edMovieDur') && ishghandle(h.edMovieDur)
        s = strtrim(char(get(h.edMovieDur,'String')));
        s = strrep(s, ',', '.');            % terima koma desimal
        v = str2double(s);
        if isscalar(v) && isfinite(v) && v > 0, d = v; end
    end
end


% =====================================================================
% 📄 REPORT PDF (Group A–E) — 1 file PDF landscape per-eksperimen.
%   Reuse penuh mesin ekspor Commit (i_descShotAxMain / i_shotAxPotCalibJpg /
%   i_descShotAxSlip) untuk render gambar antara ke JPG, lalu dirakit ke PDF
%   via figure offscreen + exportgraphics(...,'Append',true). SEMUA teks statis
%   dalam PDF Bahasa Inggris. Dipicu tombol "📄 Report PDF" (exp+garis PSG aktif).
% =====================================================================
function i_onReportCancel(fig)
%I_ONREPORTCANCEL  Set flag CANCEL -> loop Report berhenti di iterasi berikutnya.
    h = guidata(fig); h.reportCancel = true; guidata(fig, h);
    i_setDescStatus(fig, 'Membatalkan Report… (menunggu langkah berjalan selesai)');
    drawnow;
end

% =====================================================================
% 📄 REPORT B — 1 halaman 4-panel per DX (SEMUA POI). Pola sampel
%   sample_dx_report_4panel: kiri-atas axPOT + kiri-bawah AXSLIP (snapshot GRAIN4
%   hidup, kalibrasi strain%/cm/s, highlight sesar & FRAME DX aktif = garis MERAH
%   tebal di POI itu; POI lain warna asli tipis) + kanan velmag/shear (AX main
%   standar, glyph sp10, colorbar southoutside). Output PDF -> PAB4_export/<exp>/.
% =====================================================================
function i_onReportDummy(fig, tag)
%I_ONREPORTDUMMY  Placeholder Report A/C/D/E/F (belum diimplementasi).
    i_setDescStatus(fig, sprintf('Report %s belum diimplementasi (placeholder).', tag));
end

function i_onReportBCancel(fig)
    h = guidata(fig); h.reportBCancel = true; guidata(fig, h);
    i_setDescStatus(fig, 'Membatalkan Report B…'); drawnow;
end

function i_reportBBtnState(fig, running)
    h = guidata(fig);
    if isfield(h,'btnReportB') && ishghandle(h.btnReportB)
        set(h.btnReportB,'Enable', pivui.grain5Fmt.tern(running,'off','on'));
    end
    if isfield(h,'btnReportBCancel') && ishghandle(h.btnReportBCancel)
        set(h.btnReportBCancel,'Visible', pivui.grain5Fmt.tern(running,'on','off'));
    end
    if ~running, h.reportBCancel = false; guidata(fig, h); end
    drawnow limitrate;
end

function i_onReportB(fig)
%I_ONREPORTB  Rakit PDF: 1 halaman per baris DX (SEMUA POI non-blank) garis PSG
%   aktif. Tiap halaman = 4-panel (axPOT/AXSLIP + velmag/shear), FRAME diobserve =
%   frame DX itu, POI di judul = POI baris DX, garis merah tebal HANYA di frame itu.
    i_captureDescFromTable(fig); h = guidata(fig);
    if isempty(h.df), i_setDescStatus(fig,'Belum ada eksperimen dimuat.'); return; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    % Kumpulkan (F#, frame, POI) baris DX POI non-blank -> 1 halaman masing2.
    items = {};
    for k = 1:numel(rows)
        r = rows{k};
        poi = strtrim(char(i_rowField(r,'poi','')));
        if isempty(poi) || strcmpi(poi,'</blank>'), continue; end
        fr = i_rowField(r,'frame',NaN);
        fn = strtrim(char(i_rowField(r,'fNum','')));
        if ~(isscalar(fr) && isfinite(fr)), continue; end
        items{end+1} = struct('fNum',fn,'frame',round(fr),'poi',poi); %#ok<AGROW>
    end
    if isempty(items)
        i_setDescStatus(fig,'Tak ada baris DX (POI) di garis PSG aktif untuk Report B.'); return;
    end
    % Hook DEBUG (opsional): h.reportBFilter = struct('fNum','F1','poi','NUC-FSR')
    % -> hanya render item yg cocok (utk sampel cepat). Kosong = semua.
    if isfield(h,'reportBFilter') && isstruct(h.reportBFilter)
        flt = h.reportBFilter; keep = true(1,numel(items));
        for k = 1:numel(items)
            if isfield(flt,'fNum') && ~isempty(flt.fNum)
                keep(k) = keep(k) && strcmpi(strtrim(items{k}.fNum), strtrim(flt.fNum));
            end
            if isfield(flt,'poi') && ~isempty(flt.poi)
                keep(k) = keep(k) && strcmpi(strtrim(items{k}.poi), strtrim(flt.poi));
            end
        end
        items = items(keep);
        if isempty(items)
            i_setDescStatus(fig,'reportBFilter tak cocok baris DX mana pun.'); return;
        end
    end
    % Urut per (F#, frame).
    [~,ord] = sortrows([cellfun(@(x) i_uiNumFromTag(x.fNum), items).' cellfun(@(x) x.frame, items).']);
    items = items(ord);

    % Folder output PAB4_export/<exp>/<stamp>_ReportB.pdf.
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
    end
    [~, base] = fileparts(h.df);
    outDir = fullfile(grainRoot, 'PAB4_export', base);
    if ~isfolder(outDir), mkdir(outDir); end
    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride), ts = h.exportStampOverride; end
    outPdf = fullfile(outDir, sprintf('%s_ReportB.pdf', ts));

    % Muat semua bingkai (velmag/shear).
    pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    velMult   = i_descVelMult(h);
    strainTot = i_strainTotalSafe(h);
    indMaxCms = i_reportIndenterMax(h) * velMult;
    if ~(isfinite(indMaxCms) && indMaxCms>0), indMaxCms = 0.05; end
    yTopPot = 1.2 * indMaxCms;
    nF = h.nF;

    % Semua DX (POI) garis PSG aktif utk garis vertikal konteks tiap halaman.
    dxAll = i_reportBDxAll(rows);

    % State restore + tombol Cancel.
    frame0 = h.frame; actId0 = h.activeFaultId; showAll0 = h.showAllFaults;
    glyph0 = struct('on',h.glyphOn,'col',h.glyphColor,'sp',h.glyphSp);
    fdoc0 = h.fdoc;
    h.reportBCancel = false; guidata(fig, h);
    i_reportBBtnState(fig, true);
    cuBtn = onCleanup(@() i_reportBBtnState(fig, false)); %#ok<NASGU>
    wb = i_descWaitbar('Report B…'); cuw = onCleanup(@() i_descCloseWb(wb)); %#ok<NASGU>

    if isfile(outPdf), try, delete(outPdf); catch, end, end
    firstPage = true; nPage = 0;
    try
        for i = 1:numel(items)
            h = guidata(fig);
            if isfield(h,'reportBCancel') && h.reportBCancel
                i_reportBRestore(fig, frame0, actId0, showAll0, glyph0, fdoc0);
                if isfile(outPdf), try, delete(outPdf); catch, end, end
                i_setDescStatus(fig,'Report B DIBATALKAN.'); return;
            end
            it = items{i};
            if ~isempty(wb) && ishghandle(wb)
                waitbar(i/numel(items), wb, sprintf('Report B: %s %s (frame %d) [%d/%d]', ...
                    it.fNum, it.poi, it.frame, i, numel(items)));
            end
            i_reportBPage(fig, base, it, dxAll, lo_(it.frame,nF), hi_(it.frame,nF), ...
                velMult, strainTot, yTopPot, outPdf, firstPage, fdoc0);
            firstPage = false; nPage = nPage + 1;
        end
    catch ME
        i_reportBRestore(fig, frame0, actId0, showAll0, glyph0, fdoc0);
        i_setDescStatus(fig, sprintf('Report B GAGAL: %s', ME.message)); return;
    end
    i_reportBRestore(fig, frame0, actId0, showAll0, glyph0, fdoc0);
    d = dir(outPdf); by = 0; if ~isempty(d), by = d.bytes; end
    i_setDescStatus(fig, sprintf('REPORT B: %d halaman, %.0f KB → %s', nPage, by/1024, outPdf));
end

function lo = lo_(frame, nF)
%LO_  Batas kiri jendela 150-frame dipusatkan di frame (clamp ke [1 nF]).
    win = 150; lo = frame - floor(win/2); hi = lo + win - 1;
    if lo < 1, lo = 1; end
    if hi > nF, lo = max(1, nF - win + 1); end
end
function hi = hi_(frame, nF)
    win = 150; lo = frame - floor(win/2); hi = lo + win - 1;
    if lo < 1, hi = min(nF, win); end
    if hi > nF, hi = nF; end
end

function i_reportBRestore(fig, frame0, actId0, showAll0, glyph0, fdoc0)
    try
        h = guidata(fig); h.showAllFaults = logical(showAll0);
        h.glyphOn = glyph0.on; h.glyphColor = glyph0.col; h.glyphSp = glyph0.sp;
        if nargin >= 6, h.fdoc = fdoc0; end
        guidata(fig, h);
    catch, end
    try, if ~isempty(actId0), i_setActiveFault(fig, actId0); end, catch, end
    try, pivui.grain4Shell.setPotView(fig, 'pot'); catch, end
    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
end

function dx = i_reportBDxAll(rows)
%I_REPORTBDXALL  {frame, poi, fNum} baris DX POI non-blank (semua F#).
    dx = {};
    for k = 1:numel(rows)
        r = rows{k};
        poi = strtrim(char(i_rowField(r,'poi','')));
        if isempty(poi) || strcmpi(poi,'</blank>'), continue; end
        fr = i_rowField(r,'frame',NaN);
        if ~(isscalar(fr) && isfinite(fr)), continue; end
        dx(end+1,:) = {round(fr), poi, strtrim(char(i_rowField(r,'fNum','')))}; %#ok<AGROW>
    end
end

function v = i_rowField(r, name, def)
    v = def;
    if isstruct(r) && isfield(r,name) && ~isempty(r.(name)), v = r.(name); end
end

function n = i_uiNumFromTag(ft)
    n = str2double(regexprep(strtrim(char(ft)), '^[Ff]', ''));
    if ~isfinite(n), n = 9999; end
end

function i_reportBPage(fig, base, it, dxAll, lo, hi, velMult, strainTot, yTopPot, outPdf, firstPage, fdoc0)
%I_REPORTBPAGE  Rakit 1 halaman 4-panel utk item DX (it.fNum/frame/poi).
    ftag = upper(strtrim(it.fNum)); if isempty(ftag), ftag = 'F?'; end
    obsFrame = it.frame;
    % Aktifkan sesar (bila teridentifikasi) + highlight hanya sesar itu.
    f = i_faultByUiNum(guidata(fig), ftag);
    h = guidata(fig);
    if ~isempty(f)
        h.activeFaultId = f.id;
        h.fdoc = i_enableOnlyFault(fdoc0, f.id);   % matikan sesar lain (fill hanya aktif)
    end
    h.showAllFaults = false; h.showAllSlip = false;
    h.lwRaw = 0.5;
    guidata(fig, h);

    pg = figure('Visible','off','Color','w','Units','pixels','Position',[50 50 1500 900]);
    try, pivui.forceLightTheme(pg); catch, end
    set(pg,'Color','w'); cu = onCleanup(@() i_closeIfH(pg)); %#ok<NASGU>
    annotation(pg,'textbox',[0.02 0.955 0.96 0.04],'String', ...
        sprintf('%s  —  %s  —  %s  (DX @ frame %d)', base, ftag, it.poi, obsFrame), ...
        'Interpreter','none','FontWeight','bold','Color',[0 0 0], ...
        'HorizontalAlignment','center','VerticalAlignment','middle','EdgeColor','none','FontSize',11);

    % Garis DX konteks = HANYA sesar ini (F#), bukan semua sesar. STRICT: bila
    % ftag tak cocok satu pun (mis. DX tanpa F#), dxF = KOSONG (jangan fallback ke
    % SEMUA sesar — itu yg bikin garis F# lain ikut terplot -> puyeng).
    dxF = cell(0,3);
    if size(dxAll,1) >= 1 && size(dxAll,2) >= 3
        keep = false(size(dxAll,1),1);
        for q = 1:size(dxAll,1)
            keep(q) = strcmpi(strtrim(char(dxAll{q,3})), ftag);
        end
        dxF = dxAll(keep,:);
    end

    xL=0.050; wL=0.30; xR=0.405; wR=0.585; yT=0.535; hR=0.375; yB=0.075;
    axP = axes('Parent',pg,'Position',[xL yT wL hR]);
    i_reportBSnapPot(fig, axP, 'pot', lo, hi, velMult, strainTot, yTopPot, dxF, obsFrame);
    title(axP, sprintf('AX POT — %s', ftag), 'Interpreter','none','Color',[0 0 0]);
    axS = axes('Parent',pg,'Position',[xL yB wL hR]);
    i_reportBSnapPot(fig, axS, 'slip', lo, hi, velMult, strainTot, NaN, dxF, obsFrame);
    title(axS, sprintf('AX SLIP — %s', ftag), 'Interpreter','none','Color',[0 0 0]);
    axV = axes('Parent',pg,'Position',[xR yT wR hR]);
    i_reportBSnapMain(fig, axV, 'velmag', obsFrame, velMult, strainTot, ...
        sprintf('%s - %s - Velocity Magnitude', ftag, it.poi));
    axH = axes('Parent',pg,'Position',[xR yB wR hR]);
    i_reportBSnapMain(fig, axH, 'shear', obsFrame, velMult, strainTot, ...
        sprintf('%s - %s - Shear Strain', ftag, it.poi));

    if firstPage
        exportgraphics(pg, outPdf, 'ContentType','image','Resolution',150);
    else
        exportgraphics(pg, outPdf, 'ContentType','image','Resolution',150,'Append',true);
    end
end

function fdoc = i_enableOnlyFault(fdoc, keepId)
    if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
    for k = 1:numel(fdoc.faults)
        fk = fdoc.faults{k};
        if isstruct(fk) && isfield(fk,'id'), fk.enabled = strcmp(char(fk.id),char(keepId)); fdoc.faults{k} = fk; end
    end
end

function i_reportBSnapPot(fig, axDst, view, lo, hi, velMult, strainTot, yTop, dxAll, obsFrame)
%I_REPORTBSNAPPOT  Snapshot axPOT/AXSLIP GRAIN4 hidup -> axDst, kalibrasi strain%/
%   cm/s. Highlight garis DX MERAH TEBAL HANYA di frame obsFrame (POI yg diplot).
    pivui.grain4Shell.setPotView(fig, view);
    pivui.grain4Shell.renderPOT(fig); drawnow;
    h = guidata(fig); src = h.axPOT; nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    try, delete(findall(src,'Tag','nsPoint'));       catch, end
    try, delete(findall(src,'Tag','poiVline'));      catch, end
    try, delete(findall(src,'Tag','axslipCutLine')); catch, end
    set(axDst,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top');
    grid(axDst,'on'); hold(axDst,'on');
    kids = copyobj(allchild(src), axDst);
    try, delete(findall(axDst,'Tag','frameLine')); catch, end
    try, delete(findall(axDst,'Tag','frameTxt'));  catch, end
    yWin = [];
    for c = kids(:).'
        try
            tg=''; if isprop(c,'Tag'), tg=get(c,'Tag'); end
            isV = strcmp(tg,'descVline');
            if isprop(c,'XData') && ~isempty(get(c,'XData'))
                xf=get(c,'XData'); inW = xf>=lo & xf<=hi;
                set(c,'XData', xmap(xf));
                if isprop(c,'YData')
                    yv=get(c,'YData')*velMult; set(c,'YData',yv);
                    if any(inW) && ~isV, yWin=[yWin, yv(inW & isfinite(yv))]; end %#ok<AGROW>
                end
            elseif isprop(c,'YData') && ~isempty(get(c,'YData'))
                set(c,'YData', get(c,'YData')*velMult);
            end
            if strcmp(get(c,'Type'),'text')
                p=get(c,'Position'); if numel(p)>=2, p(1)=xmap(p(1)); p(2)=p(2)*velMult; set(c,'Position',p); end
            end
        catch
        end
    end
    axDst.YDir = src.YDir;
    if xstrain, xlabel(axDst,'Cumulative strain (%)','Color',[0 0 0]); else, xlabel(axDst,'Frame','Color',[0 0 0]); end
    if strcmp(view,'slip'), ylabel(axDst,'|HW - FW| (cm/s)','Color',[0 0 0]); else, ylabel(axDst,'|V| (cm/s)','Color',[0 0 0]); end
    xl = sort([xmap(lo) xmap(hi)]); xlim(axDst, xl);
    if xstrain, set(axDst,'XDir','reverse'); end
    ylo = 0; if ~isempty(yWin), ylo = min(0, min(yWin)); end
    if ~(isscalar(yTop) && isfinite(yTop))
        if ~isempty(yWin), yTop = 1.2*max(yWin(isfinite(yWin))); else, yTop = ylo+1; end
    end
    if ~(yTop>ylo), yTop = ylo+1; end
    ylim(axDst, [ylo yTop]);
    % Buang salinan garis DX GRAIN4 -> gambar ulang (fokus by FRAME).
    try, delete(findall(axDst,'Tag','descVline')); catch, end
    ff = round(obsFrame);
    % --- ARSIR HITAM aktivitas FSR (sesar INI): NUC-FSR pertama -> X-FS terakhir ---
    %   Fill descVline ikut terhapus di atas -> gambar ulang di sini. dxAll sudah
    %   difilter ke F# ini. Digambar SEBELUM garis (di belakang).
    nucFr = []; xfsFr = [];
    for i = 1:size(dxAll,1)
        v = dxAll{i,1}; if ~(isscalar(v) && isfinite(v)), continue; end
        pU = upper(strtrim(char(dxAll{i,2})));
        if strcmp(pU,'NUC-FSR'), nucFr(end+1) = round(v); end %#ok<AGROW>
        if strcmp(pU,'X-FS'),    xfsFr(end+1) = round(v); end %#ok<AGROW>
    end
    if ~isempty(nucFr) && ~isempty(xfsFr)
        xa = xmap(min(nucFr)); xb = xmap(max(xfsFr));
        xlo = min(xa,xb); xhi = max(xa,xb);
        patch(axDst, [xlo xhi xhi xlo], [ylo ylo yTop yTop], [0 0 0], ...
            'FaceAlpha',0.30, 'EdgeColor','none', 'HitTest','off', ...
            'PickableParts','none', 'Tag','descVline');
    end
    % --- garis fokus (frame observasi) SELALU merah tebal, walau F# tak dikenal ---
    if isfinite(ff) && ff>=lo && ff<=hi && isempty(dxF_hasFocus(dxAll, ff))
        xs = xmap(ff);
        plot(axDst,[xs xs],[ylo yTop],'-','Color',[0.85 0 0],'LineWidth',2.6, ...
            'Tag','descVline','HitTest','off','PickableParts','none');
    end
    for i = 1:size(dxAll,1)
        xf = dxAll{i,1}; nm = dxAll{i,2};
        if ~(isscalar(xf)&&isfinite(xf)) || xf<lo || xf>hi, continue; end
        isFocus = round(xf)==ff;
        if isFocus, col=[0.85 0 0]; lw=2.6; else, col=i_poiColor(nm); lw=1.0; end
        xs = xmap(xf);
        plot(axDst,[xs xs],[ylo yTop],'-','Color',col,'LineWidth',lw, ...
            'Tag','descVline','HitTest','off','PickableParts','none');
        text(axDst, xs, yTop, [' ' nm], 'Rotation',90, 'Color',col, 'FontSize',7.5, ...
            'FontWeight', pivui.grain5Fmt.tern(isFocus,'bold','normal'), ...
            'HorizontalAlignment','right','VerticalAlignment','middle', ...
            'BackgroundColor',[1 1 1 0.6],'Margin',1,'Clipping','on','Tag','descVline');
    end
    axDst.YAxisLocation='left'; axDst.XAxisLocation='bottom';
    hold(axDst,'off');
    pivui.grain4Shell.setPotView(fig, 'pot');
end

function i_reportBSnapMain(fig, axDst, scalar, k, velMult, strainTot, ttl)
%I_REPORTBSNAPMAIN  AX main STANDAR GRAIN4 (renderMain: strain label + glyph sp10 +
%   GS) -> snapshot axDst, tick disembunyikan, colorbar SOUTHOUTSIDE.
    scKey='velocity_magnitude'; isShear=false;
    if strcmp(scalar,'shear'), scKey='shear'; isShear=true; end
    h = guidata(fig);
    kk = max(1, min(round(k), pivcore.data.frameCount(h.data)));
    h.frame=kk; h.scalarSrc=scKey; h.glyphOn=true; h.glyphSp=10; guidata(fig, h);
    pivui.grain4Shell.renderMain(fig); drawnow;
    h = guidata(fig); src = h.axMain;
    set(axDst,'Color','w','XColor',[0 0 0],'YColor',[0 0 0]);
    copyobj(allchild(src), axDst);
    axDst.YDir=src.YDir; axDst.XLim=src.XLim; axDst.YLim=src.YLim;
    set(axDst,'XTick',[],'YTick',[]); xlabel(axDst,''); ylabel(axDst,'');
    daspect(axDst,[1 1 1]); box(axDst,'on'); set(axDst,'Layer','top');
    colormap(axDst, colormap(src)); clim(axDst, clim(src));
    try, delete(findall(axDst,'Type','ColorBar')); catch, end
    cb = colorbar(axDst,'southoutside');
    if isShear
        cb.Label.String = 'shear strain (du/dy+dv/dx)';
    else
        cb.Label.String = '|V| (cm/s)';
        cl=clim(axDst); t=get(cb,'Ticks');
        if isempty(t), t=linspace(cl(1),cl(2),6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g',v*velMult), t, 'UniformOutput',false));
    end
    set(cb,'Color',[0 0 0]); cb.Label.Color=[0 0 0];
    if isempty(ttl), ttl = sprintf('AX main %s — frame %d', scalar, kk); end
    title(axDst, ttl, 'Interpreter','none','Color',[0 0 0]);
end

% =========================================================================
%  REPORT A — "Summary of <EXP>": 1 halaman 4-panel (semua frame dalam 1 plot)
% =========================================================================
function i_onReportA(fig)
%I_ONREPORTA  Rakit PDF 1 halaman "Summary of <EXP>" (garis PSG aktif), 4 panel
%   2x2 (semua frame): kiri-atas axPOT RAW (spaghetti, tanpa HW/DX) · kanan-atas
%   +HW/FW semua F# + fill · kiri-bawah + garis vertikal DX (tanpa label; arsir
%   FS-max→FS-max PER SESAR) · kanan-bawah AXSLIP semua sesar (fill dibedakan) +
%   garis DX. y-max axPOT = 1.2×indenter-max; y-max AXSLIP = 1.2×net-slip-max.
%   HALAMAN 2 (bila ada data taper): EVOLUSI KEMIRINGAN TAPER — X=frame/strain%,
%   Y=sudut taper (°), 1 kurva per F# (dari track _taperinterp.json), ● = keyframe.
    i_captureDescFromTable(fig); h = guidata(fig);
    if isempty(h.df), i_setDescStatus(fig,'Belum ada eksperimen dimuat.'); return; end
    pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);

    velMult   = i_descVelMult(h);
    strainTot = i_strainTotalSafe(h);
    % y-max axPOT = 1.2 × indenter max (cm/s).
    indMaxCms = i_reportIndenterMax(h) * velMult;
    if ~(isfinite(indMaxCms) && indMaxCms>0), indMaxCms = 0.05; end
    yTopPot = 1.2 * indMaxCms;
    % y-max AXSLIP = 1.2 × net-slip max SEMUA sesar (cm/s); fallback ke yTopPot.
    slipMaxCms = i_reportAMaxSlipPx(h) * velMult;
    if isfinite(slipMaxCms) && slipMaxCms>0, yTopSlip = 1.2*slipMaxCms; else, yTopSlip = yTopPot; end

    % Folder output PAB4_export/<exp>/<stamp>_ReportA.pdf (pola Report B).
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
    end
    [~, base] = fileparts(h.df);
    outDir = fullfile(grainRoot, 'PAB4_export', base);
    if ~isfolder(outDir), mkdir(outDir); end
    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride), ts = h.exportStampOverride; end
    outPdf = fullfile(outDir, sprintf('%s_ReportA.pdf', ts));

    % State restore.
    frame0 = h.frame; actId0 = h.activeFaultId; showAll0 = h.showAllFaults;
    showSlip0 = isfield(h,'showAllSlip') && h.showAllSlip;
    hideAll0 = isfield(h,'hideAllFaults') && h.hideAllFaults;
    glyph0 = struct('on',h.glyphOn,'col',h.glyphColor,'sp',h.glyphSp);
    wb = i_descWaitbar('Report A…'); cuw = onCleanup(@() i_descCloseWb(wb)); %#ok<NASGU>

    pg = figure('Visible','off','Color','w','Units','pixels','Position',[50 50 1500 900]);
    try, pivui.forceLightTheme(pg); catch, end
    set(pg,'Color','w'); cu = onCleanup(@() i_closeIfH(pg)); %#ok<NASGU>
    annotation(pg,'textbox',[0.02 0.955 0.96 0.04],'String', ...
        sprintf('Summary of %s', base), 'Interpreter','none','FontWeight','bold', ...
        'Color',[0 0 0],'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'EdgeColor','none','FontSize',13);

    % Layout 2x2.
    xL=0.055; wCol=0.415; xR=0.545; yT=0.545; yB=0.075; hRow=0.375;
    try
        axP1 = axes('Parent',pg,'Position',[xL yT wCol hRow]);
        i_reportASnap(fig, axP1, 'raw',       velMult, strainTot, yTopPot, yTopSlip, rows);
        title(axP1,'AX POT — raw (all curves)','Interpreter','none','Color',[0 0 0]);
        if ~isempty(wb)&&ishghandle(wb), waitbar(0.30,wb,'Report A: panel 2/4…'); end

        axP2 = axes('Parent',pg,'Position',[xR yT wCol hRow]);
        i_reportASnap(fig, axP2, 'faults',    velMult, strainTot, yTopPot, yTopSlip, rows);
        title(axP2,'AX POT — raw + HW/FW all faults + fill','Interpreter','none','Color',[0 0 0]);
        if ~isempty(wb)&&ishghandle(wb), waitbar(0.55,wb,'Report A: panel 3/4…'); end

        axP3 = axes('Parent',pg,'Position',[xL yB wCol hRow]);
        i_reportASnap(fig, axP3, 'faultspoi', velMult, strainTot, yTopPot, yTopSlip, rows);
        title(axP3,'AX POT — + DX lines (FS-max→FS-max fill per fault)','Interpreter','none','Color',[0 0 0]);
        if ~isempty(wb)&&ishghandle(wb), waitbar(0.80,wb,'Report A: panel 4/4…'); end

        axP4 = axes('Parent',pg,'Position',[xR yB wCol hRow]);
        i_reportASnap(fig, axP4, 'slipall',   velMult, strainTot, yTopPot, yTopSlip, rows);
        title(axP4,'AX SLIP — all faults + DX lines','Interpreter','none','Color',[0 0 0]);

        if isfile(outPdf), try, delete(outPdf); catch, end, end
        exportgraphics(pg, outPdf, 'ContentType','image','Resolution',150);
        % HALAMAN 2: EVOLUSI KEMIRINGAN TAPER (semua F#, semua frame) dari sidecar
        % _taperinterp.json (track kerja). Hanya bila ada >=1 F# ber-interpolasi taper.
        if ~isempty(wb)&&ishghandle(wb), waitbar(0.92,wb,'Report A: evolusi taper…'); end
        pg2 = i_reportATaperPage(fig, base, strainTot);
        if ~isempty(pg2) && ishghandle(pg2)
            cu2 = onCleanup(@() i_closeIfH(pg2)); %#ok<NASGU>
            exportgraphics(pg2, outPdf, 'ContentType','image','Resolution',150,'Append',true);
        end
    catch ME
        i_reportARestore(fig, frame0, actId0, showAll0, showSlip0, hideAll0, glyph0);
        i_setDescStatus(fig, sprintf('Report A GAGAL: %s', ME.message)); return;
    end
    i_reportARestore(fig, frame0, actId0, showAll0, showSlip0, hideAll0, glyph0);
    d = dir(outPdf); by = 0; if ~isempty(d), by = d.bytes; end
    i_setDescStatus(fig, sprintf('REPORT A: 1 halaman, %.0f KB → %s', by/1024, outPdf));
end

function i_reportARestore(fig, frame0, actId0, showAll0, showSlip0, hideAll0, glyph0)
    try
        h = guidata(fig);
        h.showAllFaults = logical(showAll0); h.showAllSlip = logical(showSlip0);
        h.hideAllFaults = logical(hideAll0);
        h.glyphOn = glyph0.on; h.glyphColor = glyph0.col; h.glyphSp = glyph0.sp;
        guidata(fig, h);
    catch, end
    try, if ~isempty(actId0), i_setActiveFault(fig, actId0); end, catch, end
    try, pivui.grain4Shell.setPotView(fig, 'pot'); catch, end
    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
end

function pg = i_reportATaperPage(fig, base, strainTot)
%I_REPORTATAPERPAGE  Halaman EVOLUSI KEMIRINGAN TAPER (Report A hal.2): X=strain
%   kumulatif % (0 KIRI, negatif ke KANAN via XDir reverse; = konvensi AX POT export)
%   atau Frame bila tak terkalibrasi; Y=sudut taper (°, 0 di BAWAH bila semua positif).
%   Kurva tumbuh kiri-bawah -> kanan-atas. Satu kurva per F# (garis PSG aktif) dari track
%   interpolasi taper (cache/h.taperInterpDoc). [] bila tak ada data. ● = keyframe.
    pg = [];
    h = guidata(fig);
    series = i_taperEvolutionSeries(h);   % cell of {uiNum, frames, angles, kfFrames}
    if isempty(series), return; end
    pg = figure('Visible','off','Color','w','Units','pixels','Position',[50 50 1400 780]);
    try, pivui.forceLightTheme(pg); catch, end
    set(pg,'Color','w');
    annotation(pg,'textbox',[0.02 0.945 0.96 0.045],'String', ...
        sprintf('Taper slope evolution — %s', base), 'Interpreter','none', ...
        'FontWeight','bold','Color',[0 0 0],'HorizontalAlignment','center', ...
        'VerticalAlignment','middle','EdgeColor','none','FontSize',13);
    ax = axes('Parent',pg,'Position',[0.08 0.11 0.86 0.78]);
    hold(ax,'on');
    useStrain = isfinite(strainTot) && strainTot ~= 0;
    nF = pivcore.util.scalarOr(h.nF, NaN);
    xmap = @(fr) fr;
    if useStrain && isfinite(nF) && nF > 1
        xmap = @(fr) (fr-1)/(nF-1) * strainTot;
    end
    cmap = lines(max(1,numel(series)));
    leg = {};
    for k = 1:numel(series)
        s = series{k};
        if numel(s.frames) < 2, continue; end
        xx = arrayfun(xmap, s.frames);
        col = cmap(mod(k-1,size(cmap,1))+1, :);
        plot(ax, xx, s.angles, '-', 'Color',col, 'LineWidth',1.6);
        % titik keyframe supervised (lingkaran pekat).
        if ~isempty(s.kfFrames)
            [tf, loc] = ismember(round(s.kfFrames), round(s.frames));
            loc = loc(tf);
            if ~isempty(loc)
                plot(ax, xx(loc), s.angles(loc), 'o', 'MarkerSize',6, ...
                    'MarkerFaceColor',col, 'MarkerEdgeColor',[0 0 0], 'LineWidth',0.8);
            end
        end
        leg{end+1} = sprintf('F%d', round(s.uiNum)); %#ok<AGROW>
    end
    hold(ax,'off'); grid(ax,'on'); box(ax,'on');
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0]);
    % SUMBU konvensi shortening (samakan AX POT export): X strain kumulatif -> 0 di KIRI
    % (bawah), nilai paling NEGATIF di KANAN (XDir reverse); Y sudut taper -> 0 di BAWAH,
    % terbesar di ATAS (YDir normal + batas bawah 0). Kurva "tumbuh" kiri-bawah->kanan-atas.
    if useStrain
        xlabel(ax,'Cumulative strain (%)','Color',[0 0 0]);
        set(ax,'XDir','reverse');
        try, xlim(ax, sort([0 strainTot])); catch, end   % rentang [strainTot..0], dibalik -> 0 kiri
    else
        xlabel(ax,'Frame','Color',[0 0 0]);
        try, xl = xlim(ax); xlim(ax, [0 max(xl(2), 1)]); catch, end
    end
    % Y: 0 di BAWAH bila semua sudut >=0; bila ADA sudut negatif tetap dimuat (batas
    % bawah = min data) supaya kurva tak terpotong. Atas = maks + margin 5%.
    try
        allA = [];
        for kk = 1:numel(series), allA = [allA, series{kk}.angles(:).']; end %#ok<AGROW>
        allA = allA(isfinite(allA));
        if ~isempty(allA)
            yLo = min(0, min(allA)); yHi = max(allA);
            if yHi <= yLo, yHi = yLo + 1; end
            ylim(ax, [yLo, yHi + 0.05*(yHi - yLo)]);
        end
    catch, end
    ylabel(ax,'Taper slope (°, rel. horizon)','Color',[0 0 0]);
    if ~isempty(leg), legend(ax, leg, 'Location','best','TextColor',[0 0 0]); end
    title(ax,'Interpolated taper slope per fault (● = supervised keyframe)', ...
        'Interpreter','none','Color',[0 0 0]);
end

function series = i_taperEvolutionSeries(h)
%I_TAPEREVOLUTIONSERIES  Kumpulkan seri evolusi taper per F# (garis PSG aktif) dari
%   cache h.taperSamples: {uiNum, frames(sorted), angles, kfFrames}. Hanya F# ber >=2
%   keyframe (yg punya entri cache). {} bila tak ada.
    series = {};
    if ~(isstruct(h) && isfield(h,'taperSamples') && isa(h.taperSamples,'containers.Map')), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    prefix = sprintf('%s|F', psg);
    keys = h.taperSamples.keys;
    for ki = 1:numel(keys)
        key = keys{ki};
        if ~startsWith(key, prefix), continue; end
        uN = str2double(key(numel(prefix)+1:end));
        if ~(isscalar(uN) && isfinite(uN)), continue; end
        S = h.taperSamples(key);
        samp = pivcore.io.grain4Interp.tocell(S.samples);
        fr = []; an = [];
        for t = 1:numel(samp)
            s = samp{t};
            if ~(isstruct(s) && isfield(s,'frame')), continue; end
            a = NaN; if isfield(s,'angleDeg'), a = s.angleDeg; end
            fr(end+1) = round(s.frame); an(end+1) = a; %#ok<AGROW>
        end
        if numel(fr) < 2, continue; end
        [fr, ord] = sort(fr); an = an(ord);
        kfF = []; if isfield(S,'keyFrames'), kfF = round(S.keyFrames); end
        series{end+1} = struct('uiNum',round(uN),'frames',fr,'angles',an,'kfFrames',kfF); %#ok<AGROW>
    end
    % urut per uiNum (legenda rapi).
    if ~isempty(series)
        us = cellfun(@(s) s.uiNum, series);
        [~, ord] = sort(us); series = series(ord);
    end
end

function m = i_reportAMaxSlipPx(h)
%I_REPORTAMAXSLIPPX  Nilai net-slip (HW−FW) MAKS px/frame lintas SEMUA sesar utama
%   garis PSG aktif (utk skala y AXSLIP). 0 bila tak ada sesar lengkap.
    m = 0;
    try, F = i_activeFaults(h); catch, F = {}; end
    for k = 1:numel(F)
        f = F{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end   % lewati SF
        try, [ns,~,~,okHW,okFW] = pivui.grain5Model.faultNetslip(h, f); catch, continue; end
        if ~(okHW && okFW) || isempty(ns), continue; end
        v = max(ns(isfinite(ns)));
        if ~isempty(v) && isfinite(v), m = max(m, v); end
    end
end

function i_reportASnap(fig, axDst, mode, velMult, strainTot, yTopPot, yTopSlip, rows)
%I_REPORTASNAP  Render live axPOT/AXSLIP menurut MODE lalu snapshot -> axDst,
%   kalibrasi X=strain% (dibalik) / Y=cm/s. MODE:
%     'raw'       hideAllFaults (spaghetti murni, tanpa HW/DX)
%     'faults'    showAllFaults (HW/FW semua F# + fill), tanpa DX
%     'faultspoi' faults + garis DX (tanpa label) + arsir FS-max→FS-max per-sesar
%     'slipall'   AXSLIP semua sesar + garis DX + arsir FS-max→FS-max per-sesar
    h = guidata(fig);
    h.hideAllFaults = false; h.showAllFaults = false; h.showAllSlip = false;
    switch mode
        case 'raw',       h.hideAllFaults = true; view='pot';  dx=false; isSlip=false;
        case 'faults',    h.showAllFaults = true; view='pot';  dx=false; isSlip=false;
        case 'faultspoi', h.showAllFaults = true; view='pot';  dx=true;  isSlip=false;
        case 'slipall',   h.showAllSlip   = true; view='slip'; dx=true;  isSlip=true;
        otherwise,        view='pot'; dx=false; isSlip=false;
    end
    guidata(fig, h);
    try, pivui.grain4Shell.setPotView(fig, view); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
    drawnow;
    h = guidata(fig); src = h.axPOT; nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    try, delete(findall(src,'Tag','frameLine')); catch, end
    try, delete(findall(src,'Tag','frameTxt'));  catch, end
    try, delete(findall(src,'Tag','nsPoint'));   catch, end
    try, delete(findall(src,'Tag','poiVline'));  catch, end
    set(axDst,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top');
    grid(axDst,'on'); hold(axDst,'on');
    kids = copyobj(allchild(src), axDst);
    try, delete(findall(axDst,'Tag','frameLine')); catch, end
    try, delete(findall(axDst,'Tag','frameTxt'));  catch, end
    for c = kids(:).'
        try
            if isprop(c,'XData') && ~isempty(get(c,'XData')), set(c,'XData', xmap(get(c,'XData'))); end
            if isprop(c,'YData') && ~isempty(get(c,'YData')), set(c,'YData', get(c,'YData')*velMult); end
            if strcmp(get(c,'Type'),'text')
                p = get(c,'Position');
                if numel(p) >= 2, p(1)=xmap(p(1)); p(2)=p(2)*velMult; set(c,'Position',p); end
            end
        catch
        end
    end
    axDst.YDir = src.YDir;
    if xstrain, xlabel(axDst,'Cumulative strain (%)','Color',[0 0 0]); else, xlabel(axDst,'Frame','Color',[0 0 0]); end
    if isSlip, ylabel(axDst,'|HW - FW| (cm/s)','Color',[0 0 0]); else, ylabel(axDst,'|V| (cm/s)','Color',[0 0 0]); end
    xl = sort([xmap(1) xmap(nF)]); xlim(axDst, xl);
    if xstrain, set(axDst,'XDir','reverse'); end
    ylo = 0; if isSlip, yTop = yTopSlip; else, yTop = yTopPot; end
    if ~(isscalar(yTop) && isfinite(yTop) && yTop>ylo), yTop = ylo + 1; end
    ylim(axDst, [ylo yTop]);
    % Buang salinan garis/fill DX GRAIN4 (dari renderPOT) -> gambar ulang PER-SESAR
    % (tanpa label; arsir FS-max→FS-max per sesar) hanya bila mode ber-DX.
    try, delete(findall(axDst,'Tag','descVline')); catch, end
    if dx, i_reportADrawDx(axDst, rows, xmap, ylo, yTop); end
    axDst.YAxisLocation='left'; axDst.XAxisLocation='bottom';
    hold(axDst,'off');
    try, pivui.grain4Shell.setPotView(fig, 'pot'); catch, end
end

function i_reportADrawDx(axDst, rows, xmap, ylo, yTop)
%I_REPORTADRAWDX  Gambar garis vertikal DX (POI non-blank) TANPA label + arsir
%   HITAM FS-max→FS-max PER SESAR (kelompokkan baris menurut F#; pasangkan frame
%   FS-max 2-2 dalam SATU sesar -> tak bocor antar-sesar). Warna garis per-POI.
    if isempty(rows), return; end
    hs = ishold(axDst); hold(axDst,'on');
    % Kelompokkan baris DX per F#.
    fmap = containers.Map('KeyType','char','ValueType','any');
    for k = 1:numel(rows)
        r = rows{k};
        poi = strtrim(char(i_rowField(r,'poi','')));
        if isempty(poi) || strcmpi(poi,'</blank>'), continue; end
        fr = i_rowField(r,'frame',NaN);
        if ~(isscalar(fr) && isfinite(fr)), continue; end
        fn = strtrim(char(i_rowField(r,'fNum','')));
        if ~isKey(fmap, fn), fmap(fn) = struct('nuc',[],'xfs',[],'lines',{{}}); end
        s = fmap(fn);
        pU = upper(poi);
        if strcmp(pU,'NUC-FSR'), s.nuc(end+1) = round(fr); end
        if strcmp(pU,'X-FS'),    s.xfs(end+1) = round(fr); end
        s.lines{end+1} = struct('fr',round(fr),'poi',poi);
        fmap(fn) = s;
    end
    ks = keys(fmap);
    % (1) ARSIR AKTIVITAS FSR per sesar: NUC-FSR pertama -> X-FS terakhir.
    for i = 1:numel(ks)
        s = fmap(ks{i});
        if isempty(s.nuc) || isempty(s.xfs), continue; end
        xa = xmap(min(s.nuc)); xb = xmap(max(s.xfs));
        xlo = min(xa,xb); xhi = max(xa,xb);
        patch(axDst, [xlo xhi xhi xlo], [ylo ylo yTop yTop], [0 0 0], ...
            'FaceAlpha',0.22, 'EdgeColor','none', 'HitTest','off', ...
            'PickableParts','none', 'Tag','descVline');
    end
    % (2) GARIS DX (tanpa label) di atas arsiran.
    for i = 1:numel(ks)
        s = fmap(ks{i});
        for j = 1:numel(s.lines)
            L = s.lines{j}; xs = xmap(L.fr); col = i_poiColor(L.poi);
            plot(axDst, [xs xs], [ylo yTop], '-', 'Color',[col 0.80], 'LineWidth',1.0, ...
                'Tag','descVline','HitTest','off','PickableParts','none');
        end
    end
    if ~hs, hold(axDst,'off'); end
end

function hit = dxF_hasFocus(dxAll, ff)
%DXF_HASFOCUS  Return [true] bila dxAll (garis DX F# ini) sudah punya baris di frame
%   fokus ff (jadi garis merah fokus digambar di loop utama); [] bila belum ada
%   (garis fokus perlu digambar terpisah supaya SELALU tampak).
    hit = [];
    for i = 1:size(dxAll,1)
        v = dxAll{i,1};
        if isscalar(v) && isfinite(v) && round(v)==ff, hit = true; return; end
    end
end

function i_closeIfH(hh)
    try, if ishghandle(hh), close(hh); end, catch, end
end

function i_reportBtnState(fig, running)
%I_REPORTBTNSTATE  running=true: sembunyikan Report, tampilkan Cancel; reset else.
    h = guidata(fig);
    if isfield(h,'btnReport') && ishghandle(h.btnReport)
        set(h.btnReport,'Visible', pivui.grain5Fmt.tern(running,'off','on'));
    end
    if isfield(h,'btnReportCancel') && ishghandle(h.btnReportCancel)
        set(h.btnReportCancel,'Visible', pivui.grain5Fmt.tern(running,'on','off'));
    end
    if ~running, h.reportCancel = false; guidata(fig, h); end
    drawnow limitrate;
end

function tf = i_reportCancelled(fig)
%I_REPORTCANCELLED  Baca flag cancel (drawnow supaya tombol Cancel terproses).
    drawnow limitrate;
    h = guidata(fig);
    tf = isfield(h,'reportCancel') && h.reportCancel;
end

function i_onExportReport(fig)
%I_ONEXPORTREPORT  Orkestrasi pembuatan Report PDF (Group A–E) utk garis PSG
%   aktif. (1) capture tabel + validasi; (2) render gambar antara ke folder
%   sesi (_img); (3) rakit PDF landscape per-halaman; (4) tulis sidecar JSON;
%   (5) restore frame/sesar. Tombol Cancel aktif selama proses.
    h = guidata(fig);
    i_captureDescFromTable(fig); h = guidata(fig);
    if isempty(h.df)
        i_setDescStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(rows)
        i_setDescStatus(fig, 'Garis PSG aktif belum punya baris deskripsi.'); return;
    end
    % (Tulis _desc.json DIBUANG: Report TIDAK menyimpan _desc.json — hanya membaca
    %  descDoc di memori utk render PDF. Simpan lewat 💾 Save eksplisit.)

    % --- folder induk GRAIN/ (override utk TES) ---
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
        if ~isfolder(grainRoot), try, mkdir(grainRoot); catch, end, end
    end
    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride)
        ts = h.exportStampOverride;
    end
    psgName = h.activePsgId; if isempty(psgName), psgName = 'PSG'; end
    rdir = pivcore.io.grain4Report.reportDir(grainRoot, h.df, ts, psgName);
    imgD = pivcore.io.grain4Report.imgDir(rdir);
    if ~isfolder(imgD), mkdir(imgD); end
    pdfPath = pivcore.io.grain4Report.pdfPath(rdir);
    if isfile(pdfPath), try, delete(pdfPath); catch, end, end

    % --- state utk restore + parameter kalibrasi (reuse Commit) ---
    frame0 = h.frame; actId0 = h.activeFaultId; showAll0 = h.showAllFaults;
    glyph0 = struct('on',h.glyphOn,'col',h.glyphColor,'sp',h.glyphSp);
    velMult = i_descVelMult(h);
    strainTot = i_strainTotalSafe(h);
    dtSec = pivcore.io.grain4Report.readDtMean(h.df);
    lc = pivui.grain4Shell.lockedClim(fig);
    opts = struct('dpi', i_descDpi(h), 'velMult', velMult);
    % Cache grayCLAHE per sesi Report (share ke semua shot axMain via ctx.opts).
    opts.gsCache = containers.Map('KeyType','char','ValueType','any');
    cuGs = onCleanup(@() i_mapClear(opts.gsCache)); %#ok<NASGU>
    expName = i_baseNameSafe(h.df);

    % --- KALIBRASI net-slip GEOMETRIS (cm/s per px/frame) via indenter ---
    %   velMultGeom = (|X0-X1| cm / ((nF-1)*dt)) / indenterMax(px/frame).
    %   Fallback ke velMult lama (0.005) bila geometri/indenter absen.
    indMax = i_reportIndenterMax(h);
    [vmGeom, vmInfo] = pivcore.io.grain4Report.velMultGeom(h.df, indMax, dtSec, h.nF);
    velMultNS = velMult; vmSource = 'fallback';
    if isfinite(vmGeom) && vmGeom > 0, velMultNS = vmGeom; vmSource = 'geom'; end

    % --- GLYPH: paksa ON hitam spacing 10 semasa render report (restore di akhir) ---
    h.glyphOn = true; h.glyphColor = [0 0 0]; h.glyphSp = 10;
    h.reportCancel = false; guidata(fig, h);
    i_reportBtnState(fig, true);
    cuBtn = onCleanup(@() i_reportBtnState(fig, false)); %#ok<NASGU>
    wb = i_descWaitbar('Report PDF…');
    cuw = onCleanup(@() i_descCloseWb(wb)); %#ok<NASGU>

    ctx = struct('rdir',rdir,'imgD',imgD,'pdfPath',pdfPath, ...
        'opts',opts,'lc',lc,'strainTot',strainTot,'velMult',velMult, ...
        'velMultNS',velMultNS, ...
        'dtSec',dtSec,'expName',expName,'rows',{rows}, 'nF',h.nF, 'firstPage',true, 'nPages',0, ...
        'wb',wb, 'axmainCache',{{}});
    % cache AXMAIN antar-group (Group C & D reuse): map key 'F#|frame|scalar' -> file JPG.
    ctx.axmainCache = containers.Map('KeyType','char','ValueType','char');
    meta = struct('dtSource', i_reportDtSource(h.df), 'dtSec',dtSec, ...
        'velMultNS',velMultNS, 'velMultSource',vmSource, ...
        'dxCm', vmInfo.dxCm, 'indenterMax', vmInfo.indenterMax, ...
        'skippedFaults',{{}});
    i_reportProgress(ctx, 0.02, 'Menyiapkan report…');

    abort = @() i_reportAbort(fig,ctx,frame0,actId0,showAll0,glyph0);
    try
        % ------- Group A: Summary (2x2 axPOT varian) -------
        i_reportProgress(ctx, 0.05, 'Group A — Summary (axPOT varian)…');
        [ctx, okA] = i_reportGroupA(fig, ctx); if ~okA && i_reportCancelled(fig), abort(); return; end
        % ------- Group B: Description Table (mentah) -------
        i_reportProgress(ctx, 0.15, 'Group B — Description Table…');
        ctx = i_reportGroupB(fig, ctx); if i_reportCancelled(fig), abort(); return; end
        % ------- Group C: Point of Interest from F<n> (per sesar) -------
        i_reportProgress(ctx, 0.25, 'Group C — Point of Interest per sesar…');
        ctx = i_reportGroupC(fig, ctx); if i_reportCancelled(fig), abort(); return; end
        % ------- Group D: per-jenis POI lintas F# (reuse gambar Group C) -------
        i_reportProgress(ctx, 0.70, 'Group D — POI per jenis…');
        ctx = i_reportGroupD(fig, ctx); if i_reportCancelled(fig), abort(); return; end
        % ------- Group E: perhitungan turunan (slip-rate, net-slip, dip) -------
        i_reportProgress(ctx, 0.85, 'Group E — Slip-rate, Net-slip, Dip…');
        [ctx, meta] = i_reportGroupE(fig, ctx, meta); if i_reportCancelled(fig), abort(); return; end
    catch ME
        i_reportRestore(fig, frame0, actId0, showAll0, glyph0);
        i_setDescStatus(fig, sprintf('Report GAGAL: %s', ME.message));
        return;
    end

    % --- restore live state (termasuk glyph) ---
    i_reportProgress(ctx, 0.97, 'Menyelesaikan PDF…');
    i_reportRestore(fig, frame0, actId0, showAll0, glyph0);

    if ctx.nPages < 1 || ~isfile(pdfPath)
        try, if isfolder(rdir), rmdir(rdir,'s'); end, catch, end
        i_setDescStatus(fig, 'Report kosong (tak ada halaman dihasilkan).');
        return;
    end

    % --- sidecar JSON ---
    try
        doc = struct();
        doc.formatName = 'GRAIN4 Report';
        doc.formatVersion = 1;
        doc.experiment = expName;
        doc.psgId = h.activePsgId;
        doc.producedAt = i_descNowStr();
        doc.pdf = 'report.pdf';
        doc.nPages = ctx.nPages;
        doc.calibration = struct('strainTotalPct', i_numOrNull(strainTot), ...
            'velMult', velMult, 'velMultNetSlip', velMultNS, ...
            'velMultSource', meta.velMultSource, ...
            'dxCm', i_numOrNull(meta.dxCm), 'indenterMax', i_numOrNull(meta.indenterMax), ...
            'nFrames', h.nF);
        doc.dt = struct('dtSec', dtSec, 'source', meta.dtSource);
        doc.skippedFaults = meta.skippedFaults;
        pivcore.io.grain4Report.writeJsonAtomic(pivcore.io.grain4Report.jsonPath(rdir), doc);
    catch
    end

    d = dir(pdfPath); bytes = 0; if ~isempty(d), bytes = d.bytes; end
    i_setDescStatus(fig, sprintf('REPORT: %d halaman, %.0f KB → %s', ...
        ctx.nPages, bytes/1024, pdfPath));
end

function i_reportAbort(fig, ctx, frame0, actId0, showAll0, glyph0)
%I_REPORTABORT  Batalkan: buang folder report parsial + restore state.
    try, if isfolder(ctx.rdir), rmdir(ctx.rdir,'s'); end, catch, end
    i_reportRestore(fig, frame0, actId0, showAll0, glyph0);
    i_setDescStatus(fig, 'REPORT DIBATALKAN — folder report dihapus.');
end

function i_reportRestore(fig, frame0, actId0, showAll0, glyph0)
    try
        h = guidata(fig); h.showAllFaults = logical(showAll0);
        if nargin >= 5 && isstruct(glyph0)
            h.glyphOn = glyph0.on; h.glyphColor = glyph0.col; h.glyphSp = glyph0.sp;
        end
        guidata(fig,h);
    catch, end
    try, if ~isempty(actId0), i_setActiveFault(fig, actId0); end, catch, end
    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
end

function i_reportProgress(ctx, frac, msg)
%I_REPORTPROGRESS  Update waitbar (bila ada) + narasi verbose. Guard [] & quiet.
    try
        if isfield(ctx,'wb') && ~isempty(ctx.wb) && ishghandle(ctx.wb)
            waitbar(max(0,min(1,frac)), ctx.wb, msg);
        end
    catch
    end
    drawnow limitrate;
end

function indMax = i_reportIndenterMax(h)
%I_REPORTINDENTERMAX  Puncak envelope kurva POT (px/frame) utk kalibrasi velMultGeom.
%   Prioritas: h.recs -> frameCatalog.indenterEnvelope; fallback CLim velmag atas.
    indMax = NaN;
    try
        if isfield(h,'recs') && ~isempty(h.recs)
            env = pivcore.export.frameCatalog.indenterEnvelope(h.recs, h.nF);
            if ~isempty(env), indMax = max(env(isfinite(env))); end
        end
    catch
    end
    if ~(isscalar(indMax) && isfinite(indMax) && indMax>0)
        if isfield(h,'climVel') && numel(h.climVel)>=2 && isfinite(h.climVel(2)) && h.climVel(2)>0
            indMax = h.climVel(2);   % batas atas CLim |V| = ~indenter max (fallback)
        end
    end
end

function v = i_numOrNull(x)
    if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = []; end
end

function s = i_reportDtSource(df)
%I_REPORTDTSOURCE  Deskripsi sumber dt (utk sidecar): exif_meta / exif_median / fallback10.
    s = 'fallback10';
    try
        V = whos('-file', df); names = {V.name};
        if any(strcmp(names,'exif_meta'))
            S = load(df,'exif_meta');
            if isstruct(S.exif_meta) && isfield(S.exif_meta,'dt_mean_s') ...
                    && isscalar(S.exif_meta.dt_mean_s) && isfinite(S.exif_meta.dt_mean_s) && S.exif_meta.dt_mean_s>0
                s = 'exif_meta.dt_mean_s'; return;
            end
        end
        dt = pivcore.export.frameCatalog.readExifDt(df);
        if isscalar(dt) && isfinite(dt) && dt>0, s = 'exif_median'; end
    catch
    end
end


% ---- Group render helpers ------------------------------------------------

function [ctx, ok] = i_reportGroupA(fig, ctx)
%I_REPORTGROUPA  1 halaman "Summary of <EXP>": 2x2 panel:
%   kiri-atas  'raw'       = axPOT MURNI (tanpa F#, tanpa DX)
%   kanan-atas 'faults'    = axPOT GRAIN4 + F# highlight/label (TANPA garis DX)
%   kanan-bwh  'faultspoi' = kanan-atas + SEMUA garis vertikal DX
%   kiri-bwh   'slipall'   = AXSLIP net-slip SEMUA F# + garis vertikal DX
    ok = true;
    imgs = {}; ttls = {};
    variants = {'raw','raw axPOT'; 'faults','axPOT + faults'; ...
                'faultspoi','axPOT + faults + DX lines'; 'slipall','AXSLIP all faults + DX'};
    for v = 1:size(variants,1)
        if i_reportCancelled(fig), ok=false; return; end
        f = fullfile(ctx.imgD, sprintf('groupA_%s.jpg', variants{v,1}));
        if i_reportAxpotVariant(fig, variants{v,1}, f, ctx)
            imgs{end+1} = f; ttls{end+1} = variants{v,2}; %#ok<AGROW>
        end
    end
    if isempty(imgs), return; end
    ttl = sprintf('Summary of %s', ctx.expName);
    ctx = i_pdfAppendImages(ctx, imgs, [2 2], ttl, ttls);
end

function ok = i_reportAxpotVariant(fig, mode, file, ctx)
%I_REPORTAXPOTVARIANT  Set state (showAllFaults/showAllSlip + view pot/slip),
%   render, gambar garis vertikal DX bila perlu, snapshot -> JPG terkalibrasi.
    ok = false;
    h = guidata(fig);
    allSlip0 = isfield(h,'showAllSlip') && h.showAllSlip;
    allSlip = false;
    switch mode
        case 'raw',       h.showAllFaults=false; view='pot';  poi=false;
        case 'faults',    h.showAllFaults=true;  view='pot';  poi=false;
        case 'faultspoi', h.showAllFaults=true;  view='pot';  poi=true;
        case 'slipall',   h.showAllFaults=true;  view='slip'; poi=true; allSlip=true;
        otherwise,        h.showAllFaults=false; view='pot';  poi=false;
    end
    h.showAllSlip = allSlip; guidata(fig, h);
    try, pivui.grain4Shell.setPotView(fig, view); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
    if poi, try, i_drawDescVlines(fig); catch, end, end
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
    ok = i_reportSnapAxpotCalib(fig, file, ctx);
    % kembalikan ke view pot + restore showAllSlip supaya varian berikut konsisten.
    h = guidata(fig); h.showAllSlip = allSlip0; guidata(fig, h);
    try, pivui.grain4Shell.setPotView(fig, 'pot'); catch, end
end

function ok = i_reportSnapAxpotCalib(fig, file, ctx)
%I_REPORTSNAPAXPOTCALIB  copyobj axPOT LIVE (apa adanya, termasuk fill/vline)
%   -> figure offscreen, kalibrasi X=strain% (dibalik) Y=cm/s, ekspor JPG.
    ok = false;
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
    nF = h.nF; strainTot = ctx.strainTot; velMult = ctx.velMult;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    drawnow;
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 560]);
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    try
        ax2 = copyobj(h.axPOT, tmp);
        set(ax2,'Units','normalized','Position',[0.075 0.13 0.90 0.80]);
        try, delete(findall(ax2,'Tag','frameLine')); catch, end
        try, delete(findall(ax2,'Tag','frameTxt')); catch, end
        kids = get(ax2,'Children');
        for c = kids(:).'
            try
                if isprop(c,'XData') && ~isempty(get(c,'XData')), set(c,'XData', xmap(get(c,'XData'))); end
                if isprop(c,'YData') && ~isempty(get(c,'YData')), set(c,'YData', get(c,'YData') * velMult); end
                if strcmp(get(c,'Type'),'text')
                    p = get(c,'Position');
                    if numel(p) >= 2, p(1) = xmap(p(1)); p(2) = p(2)*velMult; set(c,'Position',p); end
                end
            catch
            end
        end
        if xstrain, xlabel(ax2,'Cumulative strain (%)'); else, xlabel(ax2,'Frame'); end
        if strcmp(i_potViewOf(h),'slip'), ylabel(ax2,'net-slip (cm/s)'); else, ylabel(ax2,'|V| (cm/s)'); end
        set(ax2,'YLimMode','auto','XLimMode','auto');
        if xstrain, set(ax2,'XDir','reverse'); end
        ok = i_descExportJpg(tmp, file, i_descDpiOf(ctx.opts));
    catch
        ok = false;
    end
end

function v = i_potViewOf(h)
    v = 'pot'; if isfield(h,'potView') && ~isempty(h.potView), v = char(h.potView); end
end

function ctx = i_reportGroupB(fig, ctx)
%I_REPORTGROUPB  "Description Table of <EXP>": tabel DESC mentah (semua kolom),
%   paginasi bila baris banyak. Header English.
    rows = ctx.rows;
    hdr = {'F#','FRM','POI','#ACT F','IS/OOST','NUC POS','PRP DIR','Sudut','Len(cm)','DESC'};
    data = cell(numel(rows), numel(hdr));
    for k = 1:numel(rows)
        r = rows{k};
        data(k,:) = { i_rpS(r,'fNum'), i_rpN(r,'frame'), ...
            i_rpS(r,'poi'), i_rpN(r,'actF'), i_rpS(r,'isOost'), ...
            i_rpS(r,'nucPos'), i_rpS(r,'fsrDir'), i_rpN(r,'angleDeg'), i_rpN(r,'lenCm'), ...
            i_rpS(r,'desc') };
    end
    % Paginasi berbasis "budget baris" (DESC di-wrap -> baris bisa tinggi).
    % Tiap baris tabel = 1 + jumlah baris wrap DESC; budget ~26 baris teks/halaman.
    lineBudget = 26; descCol = numel(hdr);
    rowLines = zeros(1, size(data,1));
    for k=1:size(data,1)
        s = data{k, descCol}; if ~ischar(s), s = i_reportCellStr(s); end
        w = i_wrapText(s, 46);
        rowLines(k) = max(1, 1 + sum(w==newline));
    end
    % pecah data ke halaman menurut budget.
    pages = {}; a = 1;
    while a <= size(data,1)
        acc = 0; b = a - 1;
        while b < size(data,1) && acc + rowLines(b+1) <= lineBudget
            b = b + 1; acc = acc + rowLines(b);
        end
        if b < a, b = a; end   % 1 baris raksasa tetap muat sendiri
        pages{end+1} = [a b]; %#ok<AGROW>
        a = b + 1;
    end
    nPg = numel(pages);
    for pg = 1:nPg
        if i_reportCancelled(fig), return; end
        rng = pages{pg}; sub = data(rng(1):rng(2), :);
        ttl = sprintf('Description Table of %s', ctx.expName);
        if nPg > 1, ttl = sprintf('%s (page %d/%d)', ttl, pg, nPg); end
        % tabel = FIGURE teks -> append sbg halaman VEKTOR (teks tajam, bukan JPG).
        tfig = i_reportTableFig(hdr, sub, ttl, ctx);   % judul sudah di dalam figure
        ctx = i_pdfAppendFigure(ctx, tfig);
    end
end

function ctx = i_reportGroupC(fig, ctx)
%I_REPORTGROUPC  Per sesar (F#): "Point of Interest from F<n>".
%   Halaman 1 = axPOT (highlight F# ini) + AXSLIP F# (judul rata-atas). Halaman
%   berikut = AXMAIN velmag|shear tiap baris DESC F#, DIKELOMPOKKAN 3 PASANGAN /
%   halaman (grid [3 2]). Gambar AXMAIN di-CACHE (Group D reuse tanpa render ulang).
    h = guidata(fig);
    F = i_activeFaults(h);
    nF_ = numel(F);
    for fi = 1:nF_
        if i_reportCancelled(fig), return; end
        f = F{fi};
        ftag = ['F' i_uiNumStr(f)];
        frows = i_reportRowsForFault(ctx.rows, ftag);   % baris DESC unik-per-frame F#
        if isempty(frows), continue; end
        i_reportProgress(ctx, 0.25 + 0.45*(fi-1)/max(1,nF_), sprintf('Group C — %s (%d/%d)…', ftag, fi, nF_));

        % --- Halaman 1: axPOT F# + AXSLIP F# ---
        i_setActiveFault(fig, f.id); h = guidata(fig);
        himg = {};
        pf = fullfile(ctx.imgD, sprintf('groupC_%s_axpot.jpg', ftag));
        if i_reportFaultAxpot(fig, f, pf, ctx), himg{end+1} = pf; end %#ok<AGROW>
        ps = fullfile(ctx.imgD, sprintf('groupC_%s_axslip.jpg', ftag));
        if i_reportSlipCalib(fig, f, ps, ctx), himg{end+1} = ps; end %#ok<AGROW>
        ttl = sprintf('Point of Interest from %s', ftag);
        % axPOT (atas) + AXSLIP (bawah) SUSUN ATAS-BAWAH [2 1] -> gambar melebar
        % penuh (bukan kiri-kanan yg menyisakan banyak white space).
        if ~isempty(himg)
            ctx = i_pdfAppendImages(ctx, himg, [2 1], ttl, {'axPOT (all curves + POI)','net-slip (AXSLIP)'});
        end

        % --- Halaman AXMAIN: kumpulkan pasangan velmag|shear, 3 pasangan/halaman ---
        pairs = {};   % tiap elemen: struct(vf, sf, cap)
        for ri = 1:numel(frows)
            if i_reportCancelled(fig), return; end
            r = frows{ri};
            fk = round(r.frame); if ~isfinite(fk), continue; end
            [vf, sf, ctx] = i_reportEnsureAxmain(fig, ftag, fk, ctx);
            if isempty(vf) && isempty(sf), continue; end
            pairs{end+1} = struct('vf',vf,'sf',sf,'cap',i_reportCaption(r, fk, ctx)); %#ok<AGROW>
        end
        ctx = i_reportAppendPairs(fig, ctx, pairs, ttl);
    end
end

function ctx = i_reportGroupD(fig, ctx)
%I_REPORTGROUPD  Per JENIS POI lintas semua F#: judul "POI: <jenis>". Tiap
%   kejadian POI -> AXMAIN velmag|shear, 3 PASANGAN/halaman. Gambar AXMAIN
%   di-REUSE dari cache Group C (i_reportEnsureAxmain; tak render ulang).
    rows = ctx.rows;
    % kumpulkan jenis POI (urut kemunculan).
    order = {}; seen = containers.Map('KeyType','char','ValueType','logical');
    for k=1:numel(rows)
        p = strtrim(char(rows{k}.poi)); if isempty(p), p='</blank>'; end
        if ~isKey(seen,p), seen(p)=true; order{end+1}=p; end %#ok<AGROW>
    end
    for oi = 1:numel(order)
        if i_reportCancelled(fig), return; end
        poi = order{oi};
        i_reportProgress(ctx, 0.70 + 0.14*(oi-1)/max(1,numel(order)), sprintf('Group D — %s…', i_reportPoiLabel(poi)));
        idx = find(cellfun(@(r) strcmpi(strtrim(char(r.poi)), poi) || ...
            (isempty(strtrim(char(r.poi))) && strcmp(poi,'</blank>')), rows));
        ttl = sprintf('POI: %s', i_reportPoiLabel(poi));
        pairs = {};
        for j = 1:numel(idx)
            if i_reportCancelled(fig), return; end
            r = rows{idx(j)};
            fk = round(r.frame); if ~isfinite(fk), continue; end
            ftag = pivcore.io.grain4Report.normFtag(i_rpS(r,'fNum'));
            if isempty(ftag), continue; end   % baris tanpa F# tak punya AXMAIN cache F#
            [vf, sf, ctx] = i_reportEnsureAxmain(fig, ftag, fk, ctx);
            if isempty(vf) && isempty(sf), continue; end
            fl = strtrim(char(r.fNum)); if isempty(fl), fl='(no fault)'; end
            cap = sprintf('%s — frame %d — %s', fl, fk, i_reportStrainCap(fk, ctx));
            pairs{end+1} = struct('vf',vf,'sf',sf,'cap',cap); %#ok<AGROW>
        end
        ctx = i_reportAppendPairs(fig, ctx, pairs, ttl);
    end
end

function [vf, sf, ctx] = i_reportEnsureAxmain(fig, ftag, frame, ctx)
%I_REPORTENSUREAXMAIN  Pastikan JPG AXMAIN velmag & shear utk (F#,frame) ada.
%   Di-CACHE via ctx.axmainCache (key 'F#|frame|scalar'); render sekali, reuse
%   di Group C & D (buang redundansi). Pindah sesar+frame sebelum render.
    vf = ''; sf = '';
    tgt = pivcore.io.grain4Report.normFtag(ftag);
    kv = sprintf('%s|%d|velmag', tgt, frame);
    ks = sprintf('%s|%d|shear',  tgt, frame);
    haveV = isKey(ctx.axmainCache, kv); haveS = isKey(ctx.axmainCache, ks);
    if haveV, vf = ctx.axmainCache(kv); end
    if haveS, sf = ctx.axmainCache(ks); end
    if haveV && haveS, return; end   % keduanya sudah ada -> reuse penuh
    % perlu render: pindah sesar (bila ada) + frame.
    fx = i_faultByUiNum(guidata(fig), tgt);
    if ~isempty(fx), i_setActiveFault(fig, fx.id); end
    pivui.grain4Shell.setFrameQuiet(fig, frame);  % ekspor: skip render axMain live
    if ~haveV
        vp = fullfile(ctx.imgD, sprintf('axmain_%s_f%d_velmag.jpg', tgt, frame));
        if i_descShotAxMain(fig,'velmag',frame,vp,ctx.opts,ctx.lc,ctx.strainTot)
            vf = vp; ctx.axmainCache(kv) = vp;
        end
    end
    if ~haveS
        sp = fullfile(ctx.imgD, sprintf('axmain_%s_f%d_shear.jpg', tgt, frame));
        if i_descShotAxMain(fig,'shear',frame,sp,ctx.opts,ctx.lc,ctx.strainTot)
            sf = sp; ctx.axmainCache(ks) = sp;
        end
    end
end

function ctx = i_reportAppendPairs(fig, ctx, pairs, titleStr)
%I_REPORTAPPENDPAIRS  Susun daftar pasangan {vf,sf,cap} ke halaman AXMAIN:
%   3 PASANGAN (baris) velmag|shear per halaman -> grid [3 2]. Caption tiap
%   pasangan jadi **SUBTITLE per-baris** (di tile velmag kiri) — mis.
%   "NUC-BDF0 — -1.68% cumulative strain". Judul halaman ringkas (page n/m).
    if isempty(pairs), return; end
    per = 3;
    nPg = ceil(numel(pairs)/per);
    for pg = 1:nPg
        if i_reportCancelled(fig), return; end
        a = (pg-1)*per + 1; b = min(pg*per, numel(pairs));
        imgs = {}; ttls = {};
        for i = a:b
            p = pairs{i};
            imgs{end+1} = p.vf;  ttls{end+1} = p.cap; %#ok<AGROW>  % velmag (kiri) -> subtitle
            imgs{end+1} = p.sf;  ttls{end+1} = '';    %#ok<AGROW>  % shear (kanan) -> tanpa subtitle
        end
        ttl = titleStr;
        if nPg > 1, ttl = sprintf('%s (page %d/%d)', ttl, pg, nPg); end
        ctx = i_pdfAppendImages(ctx, imgs, [per 2], ttl, ttls);
    end
end

function [ctx, meta] = i_reportGroupE(fig, ctx, meta)
%I_REPORTGROUPE  Perhitungan turunan: (1) slip-rate overlay (trim FS-max→FS-max);
%   (2) tabel + bar Estimated Net-Slip; (3) tabel + bar Fault Dip.
    h = guidata(fig);
    F = i_activeFaults(h);
    % --- data per-sesar: net-slip vector, pairs FS-max, dip ---
    labels = {}; ests = []; dips = []; overlay = {}; skipped = {};
    for fi = 1:numel(F)
        f = F{fi}; un = i_uiNumStr(f); ftag = ['F' un];
        [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        pairs = pivcore.io.grain4Report.fsMaxPairs(ctx.rows, ftag);
        dip = NaN; if isfield(f,'angleDeg'), dip = f.angleDeg; end
        dips(end+1) = dip; %#ok<AGROW>
        labels{end+1} = ftag; %#ok<AGROW>
        if okHW && okFW && ~isempty(ns) && ~isempty(pairs)
            est = pivcore.io.grain4Report.estNetSlip(ns, pairs, ctx.velMultNS, ctx.dtSec);
            ests(end+1) = est; %#ok<AGROW>
            overlay{end+1} = struct('tag',ftag,'ns',ns,'pairs',pairs); %#ok<AGROW>
        else
            ests(end+1) = NaN; %#ok<AGROW>
            skipped{end+1} = ftag; %#ok<AGROW>
        end
    end
    meta.skippedFaults = skipped;

    % --- 4 CHART dalam 1 HALAMAN (grid 2x2): (1) slip-rate overlay ·
    %     (2) boxplot slip-rate per F# · (3) bar Estimated Net-Slip ·
    %     (4) bar Fault Dip. Tabel angka net-slip/dip disimpan HANYA di
    %     sidecar report.json (bukan halaman terpisah). ---
    imgs = {}; ttls = {};
    % (1) slip-rate overlay
    f1 = fullfile(ctx.imgD, 'groupE_sliprate.jpg');
    if ~isempty(overlay) && i_reportSlipOverlay(fig, overlay, f1, ctx)
        imgs{end+1} = f1; ttls{end+1} = 'Net-slip rate overlay (trimmed FS-max→FS-max)'; %#ok<AGROW>
    end
    if i_reportCancelled(fig), return; end
    % (2) BOXPLOT slip-rate per F# (distribusi ns*velMultNS dalam rentang FS-max)
    boxLbl = {}; boxData = {};
    for k = 1:numel(overlay)
        o = overlay{k};
        y = double(o.ns(:).') * ctx.velMultNS;   % cm/s
        keep = false(1, numel(y));
        for p = 1:size(o.pairs,1)
            a = max(1,round(o.pairs(p,1))); b = min(numel(y),round(o.pairs(p,2)));
            lo=min(a,b); hi=max(a,b); keep(lo:hi) = true;
        end
        yk = y(keep & isfinite(y));
        if ~isempty(yk), boxLbl{end+1} = o.tag; boxData{end+1} = yk; end %#ok<AGROW>
    end
    f2 = fullfile(ctx.imgD, 'groupE_boxplot.jpg');
    if ~isempty(boxData) && i_reportBoxplot(boxLbl, boxData, ...
            sprintf('Net-slip rate distribution per fault — %s', ctx.expName), 'net-slip rate (cm/s)', f2, ctx)
        imgs{end+1} = f2; ttls{end+1} = 'Net-slip rate distribution (boxplot)'; %#ok<AGROW>
    end
    if i_reportCancelled(fig), return; end
    % (3) bar Estimated Net-Slip
    f3 = fullfile(ctx.imgD, 'groupE_netslip_bar.jpg');
    if i_reportBarFig(labels, ests, sprintf('Estimated Net-Slip of %s Faults', ctx.expName), ...
            'Estimated net-slip (cm)', f3, ctx)
        imgs{end+1} = f3; ttls{end+1} = 'Estimated net-slip per fault (cm)'; %#ok<AGROW>
    end
    if i_reportCancelled(fig), return; end
    % (4) bar Fault Dip
    f4 = fullfile(ctx.imgD, 'groupE_dip_bar.jpg');
    if i_reportBarFig(labels, dips, sprintf('Fault Dip of %s', ctx.expName), ...
            'Dip (deg)', f4, ctx)
        imgs{end+1} = f4; ttls{end+1} = 'Fault dip per fault (deg)'; %#ok<AGROW>
    end
    % --- rakit 1 halaman 2x2 ---
    if ~isempty(imgs)
        ttlPage = sprintf('Derived Quantities of %s', ctx.expName);
        ctx = i_pdfAppendImages(ctx, imgs, [2 2], ttlPage, ttls);
    end
end


% ---- fault axPOT (highlight 1 F#) ----------------------------------------
function ok = i_reportFaultAxpot(fig, f, file, ctx)
%I_REPORTFAULTAXPOT  axPOT highlight HANYA F# ini (showAllFaults=false +
%   setActiveFault + garis vertikal POI filter F#) -> JPG terkalibrasi.
    h = guidata(fig);
    h.showAllFaults = false; guidata(fig, h);
    try, i_setActiveFault(fig, f.id); catch, end
    try, pivui.grain4Shell.setPotView(fig, 'pot'); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
    try, i_drawDescVlines(fig); catch, end
    ok = i_reportSnapAxpotCalib(fig, file, ctx);
end

function ok = i_reportSlipCalib(fig, f, file, ctx)
%I_REPORTSLIPCALIB  AXSLIP net-slip F# ini (view=slip) + garis vertikal DX GRAIN4
%   (BUKAN POI GRAIN5) -> snapshot terkalibrasi strain%/cm/s. Menggantikan
%   i_descShotAxSlip (yg menggambar START/NUC/FSR/END GRAIN5). Pola = i_reportFaultAxpot.
    h = guidata(fig);
    h.showAllFaults = false; h.showAllSlip = false; guidata(fig, h);   % net-slip F# aktif saja
    try, i_setActiveFault(fig, f.id); catch, end
    try, pivui.grain4Shell.setPotView(fig, 'slip'); catch, end
    try, pivui.grain4Shell.renderPOT(fig); catch, end   % -> i_slipOverride -> i_renderFaultSlip (+DX)
    try, i_drawDescVlines(fig); catch, end
    ok = i_reportSnapAxpotCalib(fig, file, ctx);
    try, pivui.grain4Shell.setPotView(fig, 'pot'); catch, end
end


% ---- slip-rate overlay figure --------------------------------------------
function ok = i_reportSlipOverlay(fig, overlay, file, ctx) %#ok<INUSL>
%I_REPORTSLIPOVERLAY  1 axes overlay net-slip beberapa F#, tiap kurva DI-TRIM
%   ke rentang FS-max→FS-max (union). X = strain% (dibalik), Y = cm/s. English.
    ok = false;
    h = guidata(fig); nF = h.nF; strainTot = ctx.strainTot;
    velMult = ctx.velMultNS;   % cm/s per px/frame (kalibrasi geometri; fallback 0.005)
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 620]);
    try, pivui.forceLightTheme(tmp); catch, end
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top'); grid(ax,'on');
    hold(ax,'on');
    cols = lines(max(1,numel(overlay)));
    any1 = false; leg = {};
    for i = 1:numel(overlay)
        o = overlay{i};
        y = double(o.ns(:).') * velMult;
        keep = false(1, numel(y));
        for p = 1:size(o.pairs,1)
            a = max(1,round(o.pairs(p,1))); b = min(numel(y),round(o.pairs(p,2)));
            lo=min(a,b); hi=max(a,b); keep(lo:hi) = true;
        end
        yk = y; yk(~keep) = NaN;
        gd = isfinite(yk);
        if ~any(gd), continue; end
        x = 1:numel(yk);
        plot(ax, xmap(x(gd)), yk(gd), '-', 'Color', cols(i,:), 'LineWidth', 2.2);
        leg{end+1} = o.tag; %#ok<AGROW>
        any1 = true;
    end
    hold(ax,'off');
    if ~any1, return; end
    if xstrain, xlabel(ax,'Cumulative strain (%)'); set(ax,'XDir','reverse'); else, xlabel(ax,'Frame'); end
    ylabel(ax,'net-slip (cm/s)');
    title(ax, sprintf('Net-slip rate overlay — %s', ctx.expName), 'Interpreter','none','Color',[0 0 0]);
    if ~isempty(leg), legend(ax, leg, 'Location','best','Box','on'); end
    ok = i_descExportJpg(tmp, file, i_descDpiOf(ctx.opts));
end


% ---- tabel figure (English headers) --------------------------------------
function figH = i_reportTableFig(hdr, data, titleStr, ctx)
%I_REPORTTABLEFIG  Bangun FIGURE tabel (header + baris) via axes+text/patch dan
%   KEMBALIKAN handle-nya (BUKAN tulis JPG) supaya bisa di-append ke PDF sbg
%   halaman VEKTOR (teks tajam & selectable, tak pecah saat zoom). Header/judul
%   English. Kolom DESC di-WORD-WRAP; tinggi baris variabel (tak menumpuk),
%   dilebarkan (span ~3.2 kolom) & rata-kiri. [] bila gagal.
    figH = [];
    nR = size(data,1); nC = numel(hdr);
    % --- kolom DESC = kolom terakhir bernama 'DESC' -> beri lebar ekstra ---
    descCol = 0; if nC>=1 && strcmpi(strtrim(hdr{nC}),'DESC'), descCol = nC; end
    descSpan = 3.2;                 % DESC selebar ~3.2 kolom biasa
    colW = ones(1, nC);
    if descCol>0, colW(descCol) = descSpan; end
    xEdge = [0 cumsum(colW)];       % tepi-X tiap kolom (0..totW)
    totW = xEdge(end);
    xc = @(c) 0.5*(xEdge(c)+xEdge(c+1));   % pusat kolom c
    wrapChars = 46;                 % lebar wrap kolom DESC (≈ karakter/baris)

    % --- pra-wrap + hitung tinggi (jumlah baris) tiap baris tabel ---
    cellLines = cell(nR, nC); rowH = ones(1, nR);
    for rIx=1:nR
        maxLn = 1;
        for c=1:nC
            s = data{rIx,c}; if ~ischar(s), s = i_reportCellStr(s); end
            if c==descCol && ~isempty(s), s = i_wrapText(s, wrapChars); end
            cellLines{rIx,c} = s;
            ln = 1 + sum(s==newline);
            if ln>maxLn, maxLn = ln; end
        end
        rowH(rIx) = max(1, maxLn*0.85);   % 1 baris = 0.85 unit tinggi
    end
    yEdge = [1 1+cumsum(rowH)];   % header di [0..1], baris data mulai y=1
    totH = yEdge(end);

    figPx = max(600, min(2400, round(totH/ max(1,nR) * 40 * nR + 120)));
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 figPx]);
    try, pivui.forceLightTheme(tmp); catch, end
    set(tmp,'Color','w','PaperOrientation','landscape');
    % TIDAK onCleanup close: caller yg menutup setelah append ke PDF.
    ax = axes('Parent',tmp,'Position',[0.03 0.03 0.94 0.90]);
    set(ax,'XLim',[0 totW],'YLim',[0 totH],'YDir','reverse','Visible','off','Color','w');
    hold(ax,'on');
    title(ax, titleStr, 'Interpreter','none','Color',[0 0 0],'FontSize',13,'FontWeight','bold','Visible','on');
    % header band
    patch(ax,[0 totW totW 0],[0 0 1 1],[0.82 0.86 0.94],'EdgeColor',[0.5 0.5 0.5]);
    for c=1:nC
        text(ax, xc(c), 0.5, hdr{c}, 'HorizontalAlignment','center', ...
            'VerticalAlignment','middle','FontWeight','bold','FontSize',9, ...
            'Color',[0 0 0],'Interpreter','none');
    end
    for rIx=1:nR
        yT = yEdge(rIx); yB = yEdge(rIx+1);
        if mod(rIx,2)==0, patch(ax,[0 totW totW 0],[yT yT yB yB],[0.94 0.96 0.99],'EdgeColor','none'); end
        for c=1:nC
            s = cellLines{rIx,c};
            if c==descCol
                % DESC: rata-KIRI, mulai dekat tepi kiri kolom.
                text(ax, xEdge(c)+0.06, 0.5*(yT+yB), s, 'HorizontalAlignment','left', ...
                    'VerticalAlignment','middle','FontSize',8,'Color',[0 0 0],'Interpreter','none');
            else
                text(ax, xc(c), 0.5*(yT+yB), s, 'HorizontalAlignment','center', ...
                    'VerticalAlignment','middle','FontSize',8,'Color',[0 0 0],'Interpreter','none');
            end
        end
    end
    % gridlines (kolom pakai tepi variabel; baris pakai tepi variabel)
    for c=0:nC, plot(ax,[xEdge(c+1) xEdge(c+1)],[0 totH],'-','Color',[0.85 0.85 0.85]); end
    plot(ax,[0 0],[0 totH],'-','Color',[0.85 0.85 0.85]);
    plot(ax,[0 totW],[0 0],'-','Color',[0.85 0.85 0.85]);
    for rIx=1:nR+1, plot(ax,[0 totW],[yEdge(rIx) yEdge(rIx)],'-','Color',[0.85 0.85 0.85]); end
    hold(ax,'off');
    figH = tmp;   % kembalikan handle; caller append-vector lalu tutup
end

function w = i_wrapText(s, maxChars)
%I_WRAPTEXT  Word-wrap `s` ke baris ≤ maxChars karakter (pecah di spasi; kata
%   super-panjang dipaksa dipotong). Kembalikan string ber-newline.
    s = char(s); s = regexprep(s, '\s+', ' '); s = strtrim(s);
    if isempty(s), w = ''; return; end
    words = strsplit(s, ' ');
    lines = {}; cur = '';
    for i = 1:numel(words)
        wd = words{i};
        while numel(wd) > maxChars    % kata lebih panjang dari baris -> potong keras
            if ~isempty(cur), lines{end+1} = cur; cur = ''; end %#ok<AGROW>
            lines{end+1} = wd(1:maxChars); %#ok<AGROW>
            wd = wd(maxChars+1:end);
        end
        if isempty(cur)
            cur = wd;
        elseif numel(cur)+1+numel(wd) <= maxChars
            cur = [cur ' ' wd]; %#ok<AGROW>
        else
            lines{end+1} = cur; cur = wd; %#ok<AGROW>
        end
    end
    if ~isempty(cur), lines{end+1} = cur; end
    w = strjoin(lines, newline);
end

function s = i_reportCellStr(x)
    if ischar(x), s = x; return; end
    if isnumeric(x) && isscalar(x)
        if isfinite(x), s = num2str(x); else, s = ''; end
        return;
    end
    try, s = char(string(x)); catch, s = ''; end
end


% ---- bar chart figure ----------------------------------------------------
function ok = i_reportBarFig(labels, vals, titleStr, ylab, file, ctx)
%I_REPORTBARFIG  Bar chart (kategori=labels, tinggi=vals). NaN -> 0 (di-skip
%   visual). English labels. -> JPG.
    ok = false;
    v = double(vals(:).'); v(~isfinite(v)) = 0;
    if isempty(v), return; end
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 700]);
    try, pivui.forceLightTheme(tmp); catch, end
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    b = bar(ax, v, 'FaceColor',[0.35 0.45 0.75],'EdgeColor',[0.2 0.25 0.4]); %#ok<NASGU>
    set(ax,'XTick',1:numel(labels),'XTickLabel',labels,'Color','w', ...
        'XColor',[0 0 0],'YColor',[0 0 0],'Box','on'); grid(ax,'on');
    xlabel(ax,'Fault number','Color',[0 0 0]); ylabel(ax, ylab,'Color',[0 0 0]);
    title(ax, titleStr, 'Interpreter','none','Color',[0 0 0],'FontWeight','bold');
    ok = i_descExportJpg(tmp, file, i_descDpiOf(ctx.opts));
end


% ---- boxplot figure -------------------------------------------------------
function ok = i_reportBoxplot(labels, dataCells, titleStr, ylab, file, ctx)
%I_REPORTBOXPLOT  Boxplot slip-rate per F#. PAKAI Statistics & ML Toolbox
%   (`boxchart`) bila tersedia -> box native rapi; else FALLBACK ke boxplot
%   manual (kuartil + whisker 1.5·IQR + outlier) supaya tetap jalan tanpa toolbox.
    ok = false;
    n = numel(dataCells);
    if n == 0, return; end
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 700]);
    try, pivui.forceLightTheme(tmp); catch, end
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on'); grid(ax,'on');

    if i_hasBoxchart()
        % --- Statistics & ML Toolbox: boxchart (grup kategori) ---
        gx = []; yv = [];
        for k = 1:n
            v = double(dataCells{k}(:)); v = v(isfinite(v));
            gx = [gx; k*ones(numel(v),1)]; yv = [yv; v]; %#ok<AGROW>
        end
        if isempty(yv), return; end
        gc = categorical(gx, 1:n, labels);
        boxchart(ax, gc, yv, 'BoxFaceColor',[0.35 0.55 0.80], ...
            'MarkerColor',[0.5 0.5 0.5], 'MarkerSize',3, 'BoxWidth',0.55);
    else
        % --- FALLBACK: boxplot manual (tanpa toolbox) ---
        hold(ax,'on'); bw = 0.5; fc = [0.55 0.72 0.90];
        for k = 1:n
            v = double(dataCells{k}(:).'); v = v(isfinite(v));
            if isempty(v), continue; end
            q1 = i_quantile(v,0.25); q2 = i_quantile(v,0.50); q3 = i_quantile(v,0.75);
            iqr = q3 - q1; loW = q1 - 1.5*iqr; hiW = q3 + 1.5*iqr;
            inw = v(v>=loW & v<=hiW); if isempty(inw), inw = v; end
            wLo = min(inw); wHi = max(inw); x = k;
            patch(ax, x+bw/2*[-1 1 1 -1], [q1 q1 q3 q3], fc, 'EdgeColor',[0.15 0.30 0.55], 'FaceAlpha',0.85);
            plot(ax, x+bw/2*[-1 1], [q2 q2], '-', 'Color',[0.6 0 0], 'LineWidth',2);
            plot(ax, [x x], [q3 wHi], '-', 'Color',[0.15 0.30 0.55]);
            plot(ax, [x x], [wLo q1], '-', 'Color',[0.15 0.30 0.55]);
            plot(ax, x+bw/4*[-1 1], [wHi wHi], '-', 'Color',[0.15 0.30 0.55]);
            plot(ax, x+bw/4*[-1 1], [wLo wLo], '-', 'Color',[0.15 0.30 0.55]);
            out = v(v<loW | v>hiW);
            if ~isempty(out), plot(ax, x*ones(1,numel(out)), out, 'o', ...
                    'MarkerSize',3,'MarkerEdgeColor',[0.5 0.5 0.5]); end
        end
        hold(ax,'off');
        set(ax,'XTick',1:n,'XTickLabel',labels,'XLim',[0.5 n+0.5]);
    end
    grid(ax,'on');
    xlabel(ax,'Fault number','Color',[0 0 0]); ylabel(ax, ylab,'Color',[0 0 0]);
    title(ax, titleStr, 'Interpreter','none','Color',[0 0 0],'FontWeight','bold');
    ok = i_descExportJpg(tmp, file, i_descDpiOf(ctx.opts));
end

function tf = i_hasBoxchart()
%I_HASBOXCHART  True bila `boxchart` (Statistics & ML Toolbox) tersedia.
    persistent p;
    if isempty(p)
        p = ~isempty(which('boxchart'));
    end
    tf = p;
end

function q = i_quantile(v, p)
%I_QUANTILE  Kuantil linear (fallback tanpa Statistics Toolbox). v vektor, p∈[0,1].
    v = sort(double(v(:).')); n = numel(v);
    if n == 0, q = NaN; return; end
    if n == 1, q = v(1); return; end
    idx = (n-1)*p + 1;            % posisi 1-based
    lo = floor(idx); hi = ceil(idx); frac = idx - lo;
    q = v(lo)*(1-frac) + v(hi)*frac;
end


% ---- PDF assembly --------------------------------------------------------
function ctx = i_pdfAppendImages(ctx, imgFiles, layout, titleStr, tileTitles)
%I_PDFAPPENDIMAGES  Susun gambar antara (JPG) ke SATU halaman landscape
%   (tiledlayout `layout`=[nrow ncol]) + judul English, lalu append ke PDF via
%   exportgraphics(...,'Append',true). Halaman-1 tanpa Append.
%   tileTitles (opsional) = cellstr sepanjang imgFiles; bila tak kosong, dipakai
%   sbg `title` per-tile (SUBTITLE per gambar) — mis. "NUC-BDF0 — strain".
    if nargin < 5, tileTitles = {}; end
    % Buang gambar tak-ada + selaraskan tileTitles.
    keep = cellfun(@(f) ischar(f) && isfile(f), imgFiles);
    imgFiles = imgFiles(keep);
    if ~isempty(tileTitles) && numel(tileTitles)==numel(keep), tileTitles = tileTitles(keep); end
    if isempty(imgFiles), return; end
    fig = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 990]);
    cu = onCleanup(@() i_closeIf(fig)); %#ok<NASGU>
    try, pivui.forceLightTheme(fig); catch, end
    set(fig,'Color','w','PaperOrientation','landscape');
    % Judul RATA-ATAS halaman (annotation, konsisten walau tile sedikit) — bukan
    % title(tl) yang mengambang di tengah grid.
    annotation(fig,'textbox',[0.02 0.945 0.96 0.05],'String',titleStr, ...
        'Interpreter','none','FontWeight','bold','FontSize',14,'Color',[0 0 0], ...
        'EdgeColor','none','HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FitBoxToText','off');
    % tiledlayout di bawah judul (sisakan pita atas ~6% utk judul).
    tl = tiledlayout(fig, layout(1), layout(2), 'Padding','tight','TileSpacing','tight');
    set(tl,'OuterPosition',[0 0 1 0.93]);
    for i = 1:numel(imgFiles)
        axi = nexttile(tl);
        try
            im = imread(imgFiles{i});
            image(axi, im); axis(axi,'image'); axis(axi,'off');
        catch
            axis(axi,'off');
        end
        % SUBTITLE per-tile (bila disediakan & tak kosong).
        if numel(tileTitles) >= i && ~isempty(tileTitles{i})
            title(axi, tileTitles{i}, 'Interpreter','none','FontSize',9, ...
                'FontWeight','bold','Color',[0 0 0]);
        end
    end
    try
        if ctx.firstPage
            exportgraphics(fig, ctx.pdfPath, 'ContentType','image');
            ctx.firstPage = false;
        else
            exportgraphics(fig, ctx.pdfPath, 'ContentType','image', 'Append', true);
        end
        ctx.nPages = ctx.nPages + 1;
    catch
    end
end

function ctx = i_pdfAppendFigure(ctx, figH, titleStr)
%I_PDFAPPENDFIGURE  Append FIGURE apa adanya sbg 1 halaman PDF VEKTOR
%   (ContentType='vector' -> teks tajam & selectable, tak pecah saat zoom).
%   Dipakai tabel DESC (teks) supaya bukan JPG raster. Menutup figH setelah.
    if isempty(figH) || ~ishghandle(figH), return; end
    cu = onCleanup(@() i_closeIf(figH)); %#ok<NASGU>
    try, pivui.forceLightTheme(figH); catch, end
    set(figH,'Color','w','PaperOrientation','landscape');
    if nargin >= 3 && ~isempty(titleStr)
        annotation(figH,'textbox',[0.02 0.955 0.96 0.04],'String',titleStr, ...
            'Interpreter','none','FontWeight','bold','FontSize',13,'Color',[0 0 0], ...
            'EdgeColor','none','HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FitBoxToText','off');
    end
    try
        if ctx.firstPage
            exportgraphics(figH, ctx.pdfPath, 'ContentType','vector');
            ctx.firstPage = false;
        else
            exportgraphics(figH, ctx.pdfPath, 'ContentType','vector', 'Append', true);
        end
        ctx.nPages = ctx.nPages + 1;
    catch
    end
end


% ---- small report helpers ------------------------------------------------
function s = i_rpS(r, f)
    s = ''; if isstruct(r) && isfield(r,f), v = r.(f); if ischar(v), s = v; else, s = i_reportCellStr(v); end, end
end
function s = i_rpN(r, f)
    s = ''; if isstruct(r) && isfield(r,f) && isscalar(r.(f)) && isfinite(r.(f)), s = num2str(round(r.(f))); end
end

function rows = i_reportRowsForFault(allRows, ftag)
%I_REPORTROWSFORFAULT  Baris DESC (unik-per-frame) milik F#=ftag ('F3').
    rows = {};
    tgt = pivcore.io.grain4Report.normFtag(ftag);
    for k=1:numel(allRows)
        r = allRows{k};
        ft = pivcore.io.grain4Report.normFtag(i_rpS(r,'fNum'));
        if strcmp(ft, tgt), rows{end+1} = r; end %#ok<AGROW>
    end
end

function cap = i_reportCaption(r, fk, ctx)
%I_REPORTCAPTION  "<POI> <strain%>" (English). Blank POI -> "(blank)".
    poi = i_reportPoiLabel(i_rpS(r,'poi'));
    cap = sprintf('%s — %s', poi, i_reportStrainCap(fk, ctx));
end

function s = i_reportStrainCap(fk, ctx)
    nF = 2; if isfield(ctx,'nF') && isscalar(ctx.nF) && ctx.nF>=1, nF = ctx.nF; end
    st = i_frameToStrain(fk, nF, ctx.strainTot);
    if isfinite(st), s = sprintf('%.2f%% cumulative strain', st);
    else, s = sprintf('frame %d', fk); end
end

function s = i_reportPoiLabel(poi)
    s = strtrim(char(poi));
    if isempty(s) || strcmp(s,'</blank>'), s = '(blank)'; end
end

function s = i_reportNumStr(x)
    if isscalar(x) && isfinite(x), s = sprintf('%.4g', x); else, s = 'n/a'; end
end

function t = i_safeTag(s)
    t = pivcore.io.grain4DescExport.safeName(s);
    if isempty(t), t = 'x'; end
end


% =====================================================================
% TAB ① SESAR (F#) — model fault-first GRAIN5
%   tiap sesar = 2 kurva (HW & FW) + titik NUC/FSR/START/END.
%   net-slip = HW−FW ; "1 sesar = 1 luas" = ∫ net-slip START..END.
% =====================================================================
function h = i_buildFaultTab(h, P)
%I_BUILDFAULTTAB  TAB ② "Sesar (F#)" = TAMPILAN / RENDER / FINAL saja.
%   Berisi tombol TAMPILAN (▦ Semua sesar / Zoom / Reset · Slip all / Slip F# /
%   Konv · Label area · zona alpha+palet). Tabel sesar (kini 10-kolom +"Sudut")
%   & pengukur SUDUT (toggle detachment + toggle hitung sudut) DIPINDAH ke TAB ①
%   Label HW bersama kontrol EDIT sesar (assign HW/FW + POI). Tema TERANG.
    WHITE = [1 1 1]; fig = h.fig;
    % --- Judul: Tab ② = TAMPILAN/RENDER saja (tabel & pengukur sudut pindah ke Tab ①) ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.964 0.92 0.026], ...
        'String','Tampilan & render sesar (EDIT + ukur sudut di Tab ① Label HW):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);

    % --- Otomasi POI batch (semua sesar) — metodologi FSR/nukleasi ---
    %   Urutan temporal PASTI tiap sesar: NUC < FSR(=START) < MaxNS < END.
    %   · MaxNS      = frame PUNCAK net-slip (nilai MAX HW−FW) -> f.fsr.
    %   · MinFW      = frame MINIMUM kecepatan Footwall DEKAT MaxNS: telusur mundur dari
    %                  puncak, cari dasar terendah -> plateau terdekat MaxNS -> tepi KIRI -> f.fsr.
    %   · Start>FSR  = f.startF := f.fsr (START selalu = FSR).
    %   · END        = net-slip TERENDAH pertama SETELAH MaxNS (frameMaxNS..nF) -> f.endF.
    %   · Rantai     = (lama) START(Fi)=FSR(Fi−1), END(Fi)=FSR(Fi+1).
    %   · Cek Inkon. = daftar anomali (langgar hipotesis) -> tabel h.tblIncon.
    %   NUC ditentukan MANUAL (dari shear tipis di AXmain). Batch = sesar utama enabled.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.918 0.50 0.024],'String','Otomasi POI (semua sesar):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    % Spinner lebar zona MinFW (frame di belakang MaxNS) — di kanan label.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.55 0.918 0.20 0.024],'String','win MinFW:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.txtMinFwWin = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.76 0.918 0.08 0.024],'String',sprintf('%d',h.minFwWin), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.85, 0.918, @() i_onMinFwWin(fig,+1), @() i_onMinFwWin(fig,-1), 'spMinFwWin');
    % Baris 1: MinFW (metode penetapan FSR). MaxNS/Auto-FSR DISEMBUNYIKAN dari GUI
    % (kurang berguna; user 2026-07-18). Tombol + callback dibiarkan utuh
    % ('Visible','off') supaya non-destruktif & test/otomasi lama tetap jalan.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.882 0.45 0.032],'String','⧉ MaxNS (puncak net-slip)', ...
        'FontWeight','bold','ForegroundColor',[0.10 0.45 0.10],'Tag','btnAutoFsr', ...
        'Visible','off', ...
        'TooltipString',['Assign FSR tiap sesar (utama, enabled) ke frame PUNCAK net-slip ' ...
        '(nilai maksimum HW−FW). Sesar tanpa HW+FW dilewati.'], ...
        'Callback',@(s,e) i_onAutoAssignFsr(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.882 0.92 0.032],'String','⧊ MinFW (min pertama FW)', ...
        'FontWeight','bold','ForegroundColor',[0.55 0.10 0.45],'Tag','btnMinFw', ...
        'TooltipString',['Assign FSR tiap sesar ke frame MINIMUM kecepatan Footwall (FW) dekat MaxNS. ' ...
        'Telusur MUNDUR dari puncak net-slip: cari nilai FW terendah (dasar) -> plateau terdekat ' ...
        'MaxNS -> tepi KIRI. Menjaga FSR tak nyangkut frame 1. Sesar tanpa FW/net-slip dilewati.'], ...
        'Callback',@(s,e) i_onAutoAssignMinFw(fig));
    % Baris 2: Start>FSR (kiri) | END (kanan).
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.846 0.45 0.032],'String','⮞ Start > FSR', ...
        'FontWeight','bold','ForegroundColor',[0.30 0.30 0.30],'Tag','btnStartFromFsr', ...
        'TooltipString','Set START tiap sesar = FSR-nya (timpa SEMUA START yang sudah ada). f.fsr/nuc/endF tak diubah.', ...
        'Callback',@(s,e) i_onStartFromFsr(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.846 0.45 0.032],'String','⮜ END (min net-slip)', ...
        'FontWeight','bold','ForegroundColor',[0.20 0.30 0.60],'Tag','btnEndMinNs', ...
        'TooltipString',['Assign END tiap sesar ke net-slip TERENDAH pertama SETELAH puncak MaxNS ' ...
        '(window frameMaxNS..nF; konvensi tanda aktif). Sesar tanpa net-slip dilewati.'], ...
        'Callback',@(s,e) i_onAutoAssignEnd(fig));
    % Baris 3: Rantai START/END (lama) | Cek Inkonsistensi.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.810 0.45 0.032],'String','⛓ Rantai START/END dari FSR', ...
        'FontWeight','bold','ForegroundColor',[0.20 0.30 0.60],'Tag','btnChainSE', ...
        'TooltipString',['Rantai tiap sesar (urutan tabel): START(Fi)=FSR(Fi−1), END(Fi)=FSR(Fi+1). ' ...
        'F1: START=frame 1. Sesar terakhir: END=frame terakhir. Lakukan SETELAH finalisasi FSR.'], ...
        'Callback',@(s,e) i_onChainStartEnd(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.810 0.45 0.032],'String','⚑ Cek Inkonsistensi', ...
        'FontWeight','bold','ForegroundColor',[0.70 0.10 0.10],'Tag','btnCheckIncon', ...
        'TooltipString',['Periksa aturan metodologis tiap sesar: START=FSR-D · NUC-D<FSR-D · ' ...
        'NUC-T<NUC-D · END=net-slip-terkecil-pertama-setelah-MaxNS. Anomali -> tabel di bawah.'], ...
        'Callback',@(s,e) i_onCheckInconsistency(fig));
    % Baris 4: Deteksi NUC-T (kiri) + spinner win NUC-T + Buat JSON ajar (kanan).
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.774 0.28 0.030],'String','⧗ Deteksi NUC-T', ...
        'FontWeight','bold','ForegroundColor',[0.55 0.15 0.75],'Tag','btnDetectNucT', ...
        'TooltipString',['Assign NUC-T (teoritis) = titik belok net-slip (kaki divergensi), telusur ' ...
        'MUNDUR dari NUC-D. BUTUH NUC-D terisi dulu. Zona = win NUC-T frame di belakang NUC-D.'], ...
        'Callback',@(s,e) i_onAutoAssignNucT(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.325 0.774 0.10 0.026],'String','win:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.txtNucTWin = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.435 0.774 0.06 0.026],'String',sprintf('%d',h.nucTWin), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.50, 0.774, @() i_onNucTWin(fig,+1), @() i_onNucTWin(fig,-1), 'spNucTWin');
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.62 0.774 0.34 0.030],'String','📖 Buat JSON (ajar)', ...
        'FontWeight','bold','ForegroundColor',[0.15 0.35 0.55],'Tag','btnLearnJson', ...
        'TooltipString',['Tulis SEMUA sesar (kurva net-slip/FW/HW + POI + MaxNS, frame MENTAH) ke ' ...
        'PAB5_learn/<exp>.json — kanal untuk mengajari CLCC cara membaca data.'], ...
        'Callback',@(s,e) i_onExportLearnJson(fig));
    % Tabel anomali (koleksi pelanggaran hipotesis; kosong bila konsisten).
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.746 0.92 0.020],'String','Anomali (langgar hipotesis) — kosong bila konsisten:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',8);
    h.tblIncon = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.04 0.610 0.92 0.134], ...   % ~4-5 baris + scroll vertikal otomatis
        'ColumnName',{'F#','Aturan','Detail'},'ColumnWidth',{40 120 'auto'}, ...
        'RowName',[],'Data',{},'FontSize',8,'BackgroundColor',WHITE);

    % --- L-GRID PSG: garis acuan L1 + N garis di bawahnya -> export AXPOT ---
    %   Membuktikan sampling PSG dekat permukaan = info paling kaya. L1 = garis PSG
    %   AKTIF (tombol "Jadikan L1"). Preview gambar L1..Ln (buffer OFF, sampling 1-D);
    %   sesudah terkunci, POT Export render axPOT tiap L (satuan nyata) + 1 axMain.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.578 0.92 0.024],'String','L-grid PSG (bukti sampling dekat permukaan):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.542 0.45 0.032],'String','★ Jadikan L1 (garis aktif)', ...
        'FontWeight','bold','ForegroundColor',[0.55 0.35 0],'Tag','btnSetRefLine', ...
        'TooltipString','Tandai garis PSG yang SEDANG AKTIF sebagai L1 (acuan; L2..Ln dibuat di bawahnya).', ...
        'Callback',@(s,e) i_onSetRefLine(fig));
    h.txtRefLine = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.51 0.544 0.45 0.026],'String','L1: — (belum di-set)', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.35 0.30 0.10]);
    % Spinner N garis + spasi antar-garis (px, increment 10).
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.508 0.14 0.024],'String','N garis:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.txtLgridN = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.18 0.508 0.08 0.024],'String',sprintf('%d',h.lgridN), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.27, 0.508, @() i_onLgridN(fig,+1), @() i_onLgridN(fig,-1), 'spLgridN');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.47 0.508 0.16 0.024],'String','spasi px:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.txtLgridDy = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.64 0.508 0.09 0.024],'String',sprintf('%d',h.lgridDy), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.74, 0.508, @() i_onLgridDy(fig,+1), @() i_onLgridDy(fig,-1), 'spLgridDy');
    % Preview (toggle: kunci) + POT Export (enabled hanya saat terkunci).
    h.btnLgridPreview = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 0.472 0.45 0.032],'String','👁 Preview garis PSG','Value',0, ...
        'FontWeight','bold','ForegroundColor',[0.10 0.25 0.55],'Tag','btnLgridPreview', ...
        'TooltipString',['Gambar posisi L1..Ln di axMain (L1 acuan, Ln paling bawah). ' ...
        'Klik = kunci (POT Export aktif); klik lagi = buka (overlay hilang).'], ...
        'Callback',@(s,e) i_onLgridPreview(fig));
    h.btnLgridExport = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.472 0.45 0.032],'String','📤 POT Export (L-grid)', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.86 0.93 1.0], ...
        'Enable','off','Tag','btnLgridExport', ...
        'TooltipString',['Export axPOT tiap L (X=strain%, Y=cm/s) + 1 axMain gabungan ke ' ...
        'PAB5_export/<exp>/PSG_LGRID/. Buffer DIPAKSA OFF; garis asli direstore sesudahnya. ' ...
        'Aktif hanya setelah Preview terkunci.'], ...
        'Callback',@(s,e) i_onLgridExport(fig));

    % --- Zona sesar: alpha (transparansi) + palet warna ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.442 0.14 0.026],'String','Zona:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.17 0.442 0.12 0.026],'String','alpha', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.txtZoneAlpha = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.30 0.442 0.09 0.026],'String',sprintf('%.2f',h.zoneAlpha), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.40, 0.444, @() i_onZoneAlpha(fig,+1), @() i_onZoneAlpha(fig,-1), 'spZoneA');
    h.popZonePalette = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.53 0.442 0.43 0.028],'String',{'Palet: lembut','Palet: ngejreng'}, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Koleksi warna zona/area sesar: lembut (pastel) atau ngejreng (jenuh).', ...
        'Callback',@(s,e) i_onZonePalette(fig));

    % --- Plot bawah: split Kurva Slip all / F# + konvensi ---
    h.btnSlipAll = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.406 0.28 0.032],'String','Slip all', ...
        'FontWeight','bold', ...
        'TooltipString',['Plot bawah: net-slip SEMUA sesar teridentifikasi bertumpuk. ' ...
        'Klik lagi -> kembali ke view Semua Kurva standar.'], ...
        'Callback',@(s,e) i_onFaultSlipAll(fig));
    h.btnFaultSlip = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.33 0.406 0.30 0.032],'String','Slip F#','Value',0, ...
        'FontWeight','bold', ...
        'TooltipString',['Plot bawah: net-slip SATU sesar aktif (HW−FW; luas START..END diarsir). ' ...
        'Klik lagi -> kembali ke kurva POT.'], ...
        'Callback',@(s,e) i_onToggleFaultSlip(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.64 0.408 0.12 0.026],'String','Konv:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.popFaultSign = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.76 0.406 0.20 0.030],'String',{'signed','absolute'}, ...
        'BackgroundColor',WHITE, ...
        'TooltipString',['Konvensi tanda net-slip. signed: HW−FW bisa +/− (arah nyata; luas bertanda). ' ...
        'absolute: |HW−FW| (selalu ≥0; besaran saja).'], ...
        'Callback',@(s,e) i_onFaultSign(fig));

    % --- Tampilkan semua sesar + Zoom/Reset ---
    h.btnShowAll = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 0.370 0.40 0.032],'String','▦ Semua sesar','Value',0, ...
        'FontWeight','bold', ...
        'TooltipString',['Tampilkan HANYA kurva sesar teridentifikasi (HW merah / FW biru) + ' ...
        'fill pastel transparan tiap sesar + label F#.'], ...
        'Callback',@(s,e) i_onToggleShowAll(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.45 0.370 0.25 0.032],'String','🔍 Zoom', ...
        'TooltipString','Tarik kotak di plot bawah untuk zoom-in (auto-kunci view).', ...
        'Callback',@(s,e) pivui.grain4Shell.zoomBoxPOT(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.71 0.370 0.25 0.032],'String','Reset view', ...
        'Callback',@(s,e) pivui.grain4Shell.resetViewPOT(fig));
    % Label area sesar (checkbox on/off + posisi tengah/atas).
    h.chkFaultLabel = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 0.338 0.40 0.028],'String','Label area','Value',1, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Tampilkan label F# pada area fill sesar (mode "Semua sesar").', ...
        'Callback',@(s,e) i_onToggleFaultLabel(fig));
    h.popFaultLabelPos = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.45 0.336 0.51 0.030],'String',{'label di ATAS (garis penunjuk)','label di TENGAH fill'}, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Posisi label area: melayang di atas (tak menghalangi kurva) atau di tengah fill.', ...
        'Callback',@(s,e) i_onFaultLabelPos(fig));

    % --- Stretch horizontal slip F# (mode XMAX N frame) ---
    %   Window frame AXSLIP dibatasi N frame di sekitar rentang START..END sesar
    %   aktif -> kurva net-slip ter-stretch horizontal utk mengamati detail slip.
    %   Berlaku pada plot bawah "Slip F#" & "Slip all". Penuh = 1..nF (default).
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.298 0.92 0.024], ...
        'String','Stretch slip F# (window frame di sekitar START..END):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    xmaxOpts = {0,'Penuh'; 50,'50'; 100,'100'; 150,'150'; 200,'200'};
    nB = size(xmaxOpts,1); gB = 0.008; wB = (0.92 - (nB-1)*gB)/nB;
    h.btnSlipXMax = gobjects(1, nB);
    for kk = 1:nB
        xB = 0.04 + (kk-1)*(wB+gB);
        val = xmaxOpts{kk,1};
        h.btnSlipXMax(kk) = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
            'Position',[xB 0.262 wB 0.032],'String',xmaxOpts{kk,2},'UserData',val, ...
            'Value',double(isequal(round(val), round(h.slipXMax))), ...   % sorot mode default (Penuh)
            'FontWeight','bold','FontSize',8,'ForegroundColor',[0.10 0.25 0.55], ...
            'TooltipString',['Batasi tampilan AXSLIP ke window frame ini (pusat = tengah START..END ' ...
            'sesar aktif). "Penuh" = seluruh eksperimen. Stretch horizontal utk baca detail slip F#.'], ...
            'Callback',@(s,e) i_onSlipXMax(fig, get(s,'UserData')));
    end

    % --- Kontrol tampilan tambahan (POI size · MA · garis PSG) DI ATAS save ---
    h = i_dispCtrls(h, P, fig, 0.04);
    i_saveBtn(P, fig, 0.04);
end


% =====================================================================
% TAB ⑨ EXPORT SESAR — kanal CLCW
%   Tabel sesar (baca-saja) + 2 tombol: export sesar terpilih / export semua.
%   Tiap sesar -> folder PAB5_export/<exp>/F<no>/ berisi:
%     · screenshot AX POT (sesar di-highlight + 4 garis vertikal POI berlabel)
%     · screenshot AX main velmag + shear di 4 POI (START/NUC/FSR/END)
%     · <exp>_F<no>.json lengkap (kurva HW/FW + net-slip + POI + daftar gambar)
% =====================================================================
function h = i_buildExportTab(h, P)
    WHITE = [1 1 1]; fig = h.fig;
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.958 0.92 0.030], ...
        'String','Export sesar → folder (screenshot + JSON) untuk dibaca CLCW:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);

    % Tabel sesar (BACA-SAJA): pilih baris utk "export terpilih".
    h.tblExport = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.04 0.560 0.92 0.372], ...
        'ColumnName',{'F#','HW','FW','START','NUC','FSR','END','luas','siap'}, ...
        'ColumnWidth',{34 34 34 44 40 40 44 50 40}, ...
        'ColumnEditable',false(1,9),'RowName',[],'FontSize',8, ...
        'CellSelectionCallback',@(s,e) i_onPickExportRow(fig, e));

    % Info kelengkapan + status.
    h.txtExportInfo = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.500 0.92 0.052], ...
        'String','', 'HorizontalAlignment','left','BackgroundColor',[0.96 0.96 0.90],'FontSize',8);

    % Opsi render.
    h.chkExpVel = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 0.456 0.44 0.028],'String','Vel mag (4 POI)','Value',1, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Screenshot AX main velocity magnitude di frame START/NUC/FSR/END.');
    h.chkExpShear = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.50 0.456 0.46 0.028],'String','Shear strain (4 POI)','Value',1, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Screenshot AX main shear strain di frame START/NUC/FSR/END.');
    h.chkExpAxpot = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 0.424 0.92 0.028],'String','AX POT terkalibrasi (full + zoom 200-frame; X=strain%, Y=cm/s)','Value',1, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString',['2 screenshot AX POT gelap: FULL + ZOOM 200 frame. Sumbu-X=% strain kumulatif, ' ...
        'Y=cm/s. HW merah/FW biru + titik POI + 4 garis vertikal POI berlabel.']);

    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.388 0.14 0.026],'String','DPI:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edExpDpi = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.17 0.386 0.14 0.030],'String','150','BackgroundColor',WHITE, ...
        'TooltipString','Resolusi gambar PNG (dpi).');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.35 0.388 0.30 0.026],'String','Mult cm/s:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edExpMult = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.58 0.386 0.20 0.030],'String','0.005','BackgroundColor',WHITE, ...
        'TooltipString',['Multiplier |V| px/frame -> cm/s (cm/s = px/frame x mult). ' ...
        'Dipakai utk sumbu-Y AX POT & net-slip JSON (semua terkalibrasi cm/s). Default 0.005.']);

    % Tombol EKSPOR utama.
    h.btnExpSel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.330 0.92 0.044],'String','📤 Export SESAR TERPILIH', ...
        'FontWeight','bold','FontSize',10,'BackgroundColor',[0.86 0.93 1.0], ...
        'TooltipString','Ekspor 1 sesar (baris tabel terpilih) ke folder PAB5_export/<exp>/F<no>/.', ...
        'Callback',@(s,e) i_onExportSelected(fig));
    h.btnExpAll = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.280 0.92 0.044],'String','📦 Export SEMUA SESAR', ...
        'FontWeight','bold','FontSize',10,'BackgroundColor',[0.88 1.0 0.88], ...
        'TooltipString','Ekspor SEMUA sesar teridentifikasi ke folder masing-masing.', ...
        'Callback',@(s,e) i_onExportAll(fig));

    % Buka folder hasil.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.232 0.60 0.038],'String','📂 Buka folder PAB5_export', ...
        'FontSize',9, ...
        'Callback',@(s,e) i_onOpenExportFolder(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.232 0.30 0.038],'String','↻ Segarkan', ...
        'FontSize',9, ...
        'Callback',@(s,e) i_refreshExportTab(fig));

    h.exportSelRow = [];   % baris sesar terpilih di tabel export (indeks tampil)
end


% =====================================================================
% TAB ⓪ HELP — daftar hotkey (read-only)
% =====================================================================
function h = i_buildHelpTab(h, P)
    WHITE = [1 1 1]; fig = h.fig; %#ok<NASGU>
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.955 0.92 0.032], ...
        'String','Daftar Hotkey (semua pakai Ctrl):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',10);
    lines = i_hotkeyList();
    uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.04 0.055 0.92 0.885], ...
        'Max',2,'Min',0,'Enable','inactive', ...   % multiline read-only (bisa di-scroll)
        'HorizontalAlignment','left','BackgroundColor',[0.98 0.98 0.96],'FontName','Courier New', ...
        'FontSize',10,'String',lines);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.010 0.92 0.036], ...
        'String','Catatan: Ctrl+panah dihindari (mac Mission Control). Ctrl+Shift = { } < > untuk langkah 5.', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.4 0.4 0.4]);
end

function lines = i_hotkeyList()
%I_HOTKEYLIST  Daftar hotkey (cellstr) — SATU sumber; dipakai TAB ⓪ Help &
%   docstring i_onKeyPress. Selaras dgn cabang di i_onKeyPress.
    lines = { ...
        '── FRAME (semua tab) ──────────────────────────'; ...
        '  Ctrl + ,   /  Ctrl + .      mundur / maju 1 frame'; ...
        '  Ctrl + <   /  Ctrl + >      mundur / maju 5 frame'; ...
        ''; ...
        '── LONCAT KE POI (sesar terpilih) ─────────────'; ...
        '  Ctrl + J    loncat ke START'; ...
        '  Ctrl + K    loncat ke END'; ...
        '  Ctrl + L    loncat ke NUC'; ...
        '  Ctrl + ;    loncat ke FSR'; ...
        '  Ctrl + H    cycle antar DX ke BAWAH + loncat frame'; ...
        '  Ctrl+Shift+H  cycle antar DX ke ATAS'; ...
        '  Ctrl + O    cycle antar DX ke bawah (sama Ctrl+H)'; ...
        ''; ...
        '── CATAT BARIS DESC (frame aktif, F# aktif) ───'; ...
        '  Ctrl + 1    NUC-BDF0   (Ctrl+Shift+1 = PRP-BDF0)'; ...
        '  Ctrl + 2    NUC-BDF1   (Ctrl+Shift+2 = PRP-BDF1)'; ...
        '  Ctrl + 3    NUC-FSR    (Ctrl+Shift+3 = PRP-TF)'; ...
        '  Ctrl + 4    ACT-FSR    (Ctrl+Shift+4 = X-FS)'; ...
        '  Ctrl + T    baris </blank> (tanpa POI)'; ...
        ''; ...
        '── EDIT BARIS DESC ────────────────────────────'; ...
        '  Ctrl + `    cycle NUC POS (—/T/M/B/FT/ALL = Top/Mid/Bottom/Fault-Tip/semua)'; ...
        '  Ctrl + O    cycle seleksi baris deskripsi'; ...
        '  Ctrl+Shift+D  hapus baris terpilih (Backspace kerap dimakan fokus tabel)'; ...
        ''; ...
        '── BIDANG SESAR & TAPER (per-DX; gaya After Effects) ──'; ...
        '  Ctrl + Q      input/copy BIDANG SESAR DX terpilih (interp evolusi'; ...
        '                ALWAYS-ON: DX kosong -> COPY bentuk interp jadi ROI'; ...
        '                editable; edit+kunci -> keyframe supervised + recompute)'; ...
        '  Ctrl + W      input TAPER DX (interpolasi taper ALWAYS-ON:'; ...
        '                DX kosong -> AUTO-SEED dari garis interpolasi)'; ...
        '  Ctrl + G      GRAB keyframe taper terdekat (kontinuitas)'; ...
        '                (prioritas F# SENDIRI lalu F# lain/overlap;'; ...
        '                 edit+kunci -> keyframe DX F# aktif)'; ...
        '                (tekan hotkey input lagi = KUNCI & simpan ke DX)'; ...
        '  Ctrl + R      TITIK DX (POI NUC-* atau X-FS): 1 klik titik'; ...
        '                (jarak horiz ke dinding pendorong + kedalaman ke'; ...
        '                 ref horizontal, cm; kolom Nuk -> ✓)'; ...
        ''; ...
        '── GESER SELEKSI KURVA (tabel kiri, mode Kurva) '; ...
        '  Ctrl + [    naik 1 kurva'; ...
        '  Ctrl + ]    turun 1 kurva'; ...
        '  Ctrl + {    naik 5 kurva   (Ctrl+Shift+[)'; ...
        '  Ctrl + }    turun 5 kurva  (Ctrl+Shift+])'; ...
        ''; ...
        '── NAVIGASI SESAR (tab sesar) ─────────────────'; ...
        '  Ctrl + M    sesar sebelumnya (F#)'; ...
        '  Ctrl + /    sesar berikutnya (F#)'; ...
        ''; ...
        '── PLOT BAWAH / ZOOM X ────────────────────────'; ...
        '  Ctrl + F    toggle AXSLIP <-> axPOT'; ...
        '  Ctrl + -    perlebar jendela X +5% (axPOT=AXSLIP)'; ...
        '  Ctrl + +    persempit jendela X -5%'; ...
        '              (100/95/90/..% total frame; disimpan ke progress)'; ...
        ''; ...
        '── AUTO — DX (saat AXSLIP tampil) ─────────────'; ...
        '  Ctrl+Shift+↑/↓  naik/turun cut-off net-slip (0.1)'; ...
        '              (Auto ACT-FSR: segmen ns>=cut-off -> 2 ACT-FSR)'; ...
        };
end


function i_refreshExportTab(fig)
%I_REFRESHEXPORTTAB  Isi tabel export dari sesar terisi (urutan tampil), tandai
%   kelengkapan (HW/FW ada + 4 POI finite = "siap"). Baris tampil PARALEL dgn
%   h.exportIds (id record per-baris) supaya seleksi -> id sesar.
    h = guidata(fig);
    if ~isfield(h,'tblExport') || ~ishghandle(h.tblExport), return; end
    ord = i_faultRowOrderPsg(h);   % cell struct sesar terurut (utama+SF) — HANYA garis PSG aktif
    n = numel(ord);
    data = repmat({''}, max(n,0), 9); ids = cell(1, n); ready = false(1, n);
    for k = 1:n
        f = ord{k};
        [ns, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        ids{k} = f.id;
        uN = pivui.grain5Model.faultUiNum(f); fCol = '';
        if ~isempty(uN), fCol = sprintf('%d', round(uN)); end
        hwNum = pivui.grain5Fmt.curveNumTag(h, hwRow, f.hwPosPx);
        isSub = ~isempty(pivui.grain5Model.parentId(f));
        if isSub, fwNum = '·'; else, fwNum = pivui.grain5Fmt.curveNumTag(h, fwRow, f.fwPosPx); end
        area = NaN;
        if okHW && okFW && ~isempty(ns), area = pivcore.pot.netslip.area(ns, f.startF, f.endF); end
        % CHECKLIST baru: HW + FW + START + END (NUC/FSR bukan syarat).
        chkDone = pivui.grain5Model.faultChecklistDone(f);
        on = pivui.grain5Model.faultEnabled(f);
        ready(k) = chkDone && on;
        if ~on, readyStr = 'OFF';
        elseif ready(k), readyStr = '✓';
        elseif okHW && okFW, readyStr = 'ST/EN?';
        else, readyStr = 'HW/FW?'; end
        data(k,:) = {fCol, hwNum, fwNum, ...
            pivui.grain5Fmt.numDash(f.startF), pivui.grain5Fmt.numDash(f.nuc), ...
            pivui.grain5Fmt.numDash(f.fsr), pivui.grain5Fmt.numDash(f.endF), ...
            pivui.grain5Fmt.num(area), readyStr};
    end
    set(h.tblExport,'Data',data);
    h.exportIds = ids; h.exportReady = ready;
    guidata(fig, h);
    nReady = sum(ready);
    if isfield(h,'txtExportInfo') && ishghandle(h.txtExportInfo)
        set(h.txtExportInfo,'String', sprintf(['%d sesar (%d siap: HW + FW + START + END).\n' ...
            'Pilih baris lalu "Export terpilih", atau "Export semua".'], n, nReady));
    end
end


function i_onPickExportRow(fig, evt)
    ind = []; try, ind = evt.Indices; catch, end
    if isempty(ind), return; end
    h = guidata(fig); h.exportSelRow = ind(1,1); guidata(fig, h);
end


function i_onExportSelected(fig)
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    row = []; if isfield(h,'exportSelRow'), row = h.exportSelRow; end
    if isempty(row) || ~isfield(h,'exportIds') || row < 1 || row > numel(h.exportIds)
        pivui.setStatus(fig,'Pilih baris sesar di tabel dulu (klik baris).'); return;
    end
    id = h.exportIds{row};
    if isempty(id), pivui.setStatus(fig,'Baris terpilih tak menunjuk sesar.'); return; end
    [f,ix] = pivcore.io.grain5Faults.findFault(h.fdoc, id);
    if ix>=1 && ~pivui.grain5Model.faultEnabled(f)
        pivui.setStatus(fig, sprintf('Sesar %s NONAKTIF (OFF) — aktifkan dulu untuk mengekspor.', id)); return;
    end
    i_runExport(fig, {id});
end


function i_onExportAll(fig)
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    % HANYA sesar AKTIF (enabled) yang PUNYA HW (skip slot kosong auto-fill & OFF).
    ids = {};
    for k = 1:numel(ord)
        f = ord{k};
        if ~pivui.grain5Model.faultEnabled(f), continue; end                 % sesar OFF -> skip
        if isfield(f,'hwPosPx') && isscalar(f.hwPosPx) && isfinite(f.hwPosPx)
            ids{end+1} = f.id; %#ok<AGROW>
        end
    end
    if isempty(ids), pivui.setStatus(fig,'Belum ada sesar AKTIF ber-HW untuk diekspor.'); return; end
    i_runExport(fig, ids);
end


function i_runExport(fig, ids)
%I_RUNEXPORT  Ekspor daftar sesar (id) -> folder + screenshot + JSON. Restore
%   sesar aktif & frame semula setelah selesai. Progress via waitbar (WAJIB utk
%   aksi batch — senyap saat pivui.quiet()).
    h = guidata(fig);
    grainRoot = fileparts(mfilename('fullpath'));   % GRAIN/ folder (GRAIN5_temp.m is at root)
    % Override parent folder (used by TESTS so the real PAB5_export is untouched).
    if isfield(h,'exportRootOverride') && ~isempty(h.exportRootOverride) && isfolder(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
    end
    stamp = char(datetime('now','Format','yyyy-MM-dd HH:mm'));

    % Save state for restore.
    prevActive = h.activeFaultId; prevFrame = h.frame;
    dpi = 150; if isfield(h,'edExpDpi') && ishghandle(h.edExpDpi)
        v = str2double(get(h.edExpDpi,'String')); if isfinite(v) && v>=50 && v<=600, dpi = round(v); end
    end
    velMult = 0.005; if isfield(h,'edExpMult') && ishghandle(h.edExpMult)
        v = str2double(get(h.edExpMult,'String')); if isfinite(v) && v>0, velMult = v; end
    end
    doVel   = i_chkOn(h,'chkExpVel',true);
    doShear = i_chkOn(h,'chkExpShear',true);
    doAxpot = i_chkOn(h,'chkExpAxpot',true);
    opts = struct('dpi',dpi,'velMult',velMult,'doVel',doVel,'doShear',doShear, ...
        'doAxpot',doAxpot,'stamp',stamp,'grainRoot',grainRoot);

    quiet = pivui.quiet();
    wb = []; if ~quiet
        try, wb = waitbar(0,'Preparing fault export…','Name','Fault export (TAB ⑨)'); pivui.forceLightTheme(wb); catch, wb = []; end
    end
    cleanWb = onCleanup(@() i_closeIf(wb)); %#ok<NASGU>

    nOk = 0; nSkip = 0; lastDir = '';
    for i = 1:numel(ids)
        id = ids{i};
        if ~isempty(wb) && ishghandle(wb)
            try, waitbar((i-1)/numel(ids), wb, sprintf('Exporting fault %d/%d…', i, numel(ids))); catch, end
        end
        [ok, dirOut, msg] = i_exportOneFault(fig, id, opts);
        if ok, nOk = nOk + 1; lastDir = dirOut; else, nSkip = nSkip + 1; end
        pivui.setStatus(fig, sprintf('[%d/%d] %s', i, numel(ids), msg));
    end

    % Restore original state (active fault + frame) + re-render.
    h = guidata(fig); h.activeFaultId = prevActive; guidata(fig, h);
    pivui.grain4Shell.gotoFrame(fig, prevFrame);
    i_setActiveFault(fig, prevActive);
    i_refreshExportTab(fig);
    if ~isempty(lastDir)
        pivui.setStatus(fig, sprintf('Export done: %d fault(s) OK, %d skipped. Folder: %s', nOk, nSkip, lastDir));
    else
        pivui.setStatus(fig, sprintf('Export done: %d OK, %d skipped.', nOk, nSkip));
    end
end


function [ok, dirOut, msg] = i_exportOneFault(fig, id, opts)
%I_EXPORTONEFAULT  Ekspor 1 sesar (id): highlight -> screenshot AX POT + AX main
%   (velmag/shear @ 4 POI) -> JSON. Return ok/dir/pesan. Sesar tak-lengkap tetap
%   diekspor (JSON + gambar POI yang ADA saja) tapi ditandai di pesan.
    ok = false; dirOut = ''; msg = '';
    h = guidata(fig);
    [f, idx] = pivcore.io.grain5Faults.findFault(h.fdoc, id);
    if idx < 1, msg = sprintf('sesar %s tak ada.', id); return; end

    % Highlight sesar ini (render axPOT dgn HW/FW + POI + garis vertikal POI).
    i_setActiveFault(fig, id);
    h = guidata(fig);

    % Derived data for JSON.
    [ns, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    tag = pivcore.io.grain5FaultExport.folderTag(f);
    dirOut = pivcore.io.grain5FaultExport.faultDir(opts.grainRoot, h.df, f);

    % Clean regenerate: purge old fault folder first (IMMUTABLE).
    pivcore.io.grain5FaultExport.purgeFault(opts.grainRoot, h.df, f);
    if ~isfolder(dirOut), mkdir(dirOut); end

    % Calibration constants (cumulative strain % + cm/s multiplier).
    strainTot = i_strainTotalSafe(h);
    velMult   = opts.velMult;
    images = struct();

    % --- AX POT screenshots (calibrated: X = cumulative strain %, Y = cm/s;
    %     DARK theme; fault highlighted HW red / FW blue + POI + POI vlines).
    %     TWO outputs: full frame span + zoom to a 200-frame window centred on
    %     the fault (START..END). ---
    if opts.doAxpot
        fnFull = pivcore.io.grain5FaultExport.axpotFile(h.df, f);           % *_axpot.png
        pFull = fullfile(dirOut, fnFull);
        if i_shotAxPotCalib(fig, f, pFull, opts, strainTot, velMult, [])
            images.axpot = fnFull;
        end
        win = i_zoomWindow(f, h.nF, 200);
        if ~isempty(win)
            fnZoom = pivcore.io.grain5FaultExport.axpotZoomFile(h.df, f);   % *_axpot_zoom.png
            pZoom = fullfile(dirOut, fnZoom);
            if i_shotAxPotCalib(fig, f, pZoom, opts, strainTot, velMult, win)
                images.axpot_zoom = fnZoom;
            end
        end
    end

    % --- NET-SLIP plot (HW−FW) cm/s, X = strain % (dibalik) + POI vlines. TWO
    %     outputs: full span + zoom 200-frame (bila nF>200). Hanya bila HW+FW ada. ---
    if opts.doAxpot && okHW && okFW && ~isempty(ns)
        fnNS = pivcore.io.grain5FaultExport.netslipFile(h.df, f);           % *_netslip.png
        pNS = fullfile(dirOut, fnNS);
        if i_shotNetslipCalib(fig, f, ns, pNS, opts, strainTot, velMult, [])
            images.netslip = fnNS;
        end
        winN = i_zoomWindow(f, h.nF, 200);
        if ~isempty(winN)
            fnNSz = pivcore.io.grain5FaultExport.netslipZoomFile(h.df, f); % *_netslip_zoom.png
            pNSz = fullfile(dirOut, fnNSz);
            if i_shotNetslipCalib(fig, f, ns, pNSz, opts, strainTot, velMult, winN)
                images.netslip_zoom = fnNSz;
            end
        end
        % NET-SLIP SEMUA sesar aktif bertumpuk (full + zoom). POI = sesar ini saja.
        fnNSa = pivcore.io.grain5FaultExport.netslipAllFile(h.df, f);       % *_netslip_all.png
        pNSa = fullfile(dirOut, fnNSa);
        if i_shotNetslipAllCalib(fig, f, pNSa, opts, strainTot, velMult, [])
            images.netslip_all = fnNSa;
        end
        if ~isempty(winN)
            fnNSaz = pivcore.io.grain5FaultExport.netslipAllZoomFile(h.df, f); % *_netslip_all_zoom.png
            pNSaz = fullfile(dirOut, fnNSaz);
            if i_shotNetslipAllCalib(fig, f, pNSaz, opts, strainTot, velMult, winN)
                images.netslip_all_zoom = fnNSaz;
            end
        end
    end

    % --- AX main velmag/shear @ 4 POI (DARK + HW/FW markers, English caption) ---
    lc = pivui.grain4Shell.lockedClim(fig);   % locked CLim per-exp (consistent scale)
    poiFlds = {'startF','start'; 'nuc','nuc'; 'fsr','fsr'; 'endF','end'};
    scalars = {}; if opts.doVel, scalars{end+1}='velmag'; end
    if opts.doShear, scalars{end+1}='shear'; end
    for si = 1:numel(scalars)
        sc = scalars{si};
        for pi = 1:size(poiFlds,1)
            fld = poiFlds{pi,1}; poi = poiFlds{pi,2};
            kf = NaN; if isfield(f,fld) && isscalar(f.(fld)), kf = f.(fld); end
            if ~(isfinite(kf) && kf>=1), continue; end   % POI not set -> skip
            fn = pivcore.io.grain5FaultExport.imageFile(h.df, f, sc, poi);
            p = fullfile(dirOut, fn);
            if i_shotAxMainCalib(fig, f, sc, round(kf), upper(poi), p, opts, lc, strainTot)
                images.(sprintf('%s_%s', sc, poi)) = fn;
            end
        end
    end

    % --- calibrated JSON ---
    info = struct();
    info.experiment    = i_baseNameSafe(h.df);
    info.nFrames       = h.nF;
    info.signConvention= h.signConv;
    info.spacingPx     = h.spacing;
    info.strainTotalPct= strainTot;
    info.velMult       = velMult;
    info.hwCurveNum    = i_curveNumSafe(h, hwRow, f.hwPosPx);
    info.fwCurveNum    = i_curveNumSafe(h, fwRow, f.fwPosPx);
    info.netslip       = ns;   % HW−FW series px/frame (engine calibrates -> cm/s)
    info.images        = images;
    info.producedAt    = opts.stamp;
    % Fill derivative cache f (area/dNet/values) so JSON is consistent.
    if okHW && okFW && ~isempty(ns)
        f.area   = pivcore.pot.netslip.area(ns, f.startF, f.endF);
        f.dNet   = pivcore.pot.netslip.dNet(ns, f.startF, f.endF);
        f.values = ns;
    end
    jstruct = pivcore.io.grain5FaultExport.buildFaultJson(h.df, f, info);
    try
        pivcore.io.grain5FaultExport.writeFaultJson(opts.grainRoot, h.df, f, jstruct);
        pivcore.io.grain5FaultExport.appendIndex(opts.grainRoot, h.df, f, opts.stamp);
    catch ME
        msg = sprintf('fault %s: failed to write JSON (%s).', tag, ME.message); return;
    end

    if pivui.grain5Model.faultChecklistDone(f)   % HW + FW + START + END
        msg = sprintf('fault %s: OK (complete).', tag);
    else
        msg = sprintf('fault %s: exported PARTIALLY (HW/FW/START/END incomplete).', tag);
    end
    ok = true;
end


% --- Calibration helpers (frame -> cumulative strain %; px/frame -> cm/s) ---
function pct = i_frameToStrain(k, nF, strainTot)
%I_FRAMETOSTRAIN  Cumulative strain % at frame k. NaN if strainTot unknown ->
%   caller falls back to frame axis.
    pct = NaN;
    if ~(isscalar(k) && isfinite(k)), return; end
    if ~(isscalar(strainTot) && isfinite(strainTot)), return; end
    if ~(isscalar(nF) && isfinite(nF) && nF>=1), return; end
    if nF <= 1, pct = strainTot; else, pct = (k-1)/(nF-1) * strainTot; end
end

function win = i_zoomWindow(f, nF, span)
%I_ZOOMWINDOW  Frame window [a b] of length `span` centred on the fault
%   START..END, clamped to [1 nF]. [] if nF <= span (zoom == full, skip).
    win = [];
    if ~(isscalar(nF) && isfinite(nF)) || nF <= span, return; end
    a = f.startF; b = f.endF;
    if ~(isfinite(a) && isfinite(b))
        c = f.fsr; if ~isfinite(c), c = round(nF/2); end
        a = c - span/2; b = c + span/2;
    end
    c = (a + b)/2;
    lo = round(c - span/2); hi = lo + span - 1;
    if lo < 1, lo = 1; hi = span; end
    if hi > nF, hi = nF; lo = nF - span + 1; end
    if lo < 1, lo = 1; end
    win = [lo hi];
end

function ok = i_shotAxPotCalib(fig, f, file, opts, strainTot, velMult, win, titleStr)
%I_SHOTAXPOTCALIB  Screenshot AX POT LIVE (kurva warna penuh + fill zona + HW/FW
%   highlight + titik POI + garis vertikal POI) via COPYOBJ ke figure offscreen,
%   LALU KALIBRASI sumbu di salinan: X frame -> cumulative strain % (bila strainTot
%   ada), Y px/frame -> cm/s (x velMult). Semua XData/YData child di-remap; label
%   sumbu diganti; zoom window (`win`=[a b] frame) diterapkan. Tema axPOT live
%   (terang) dipertahankan — persis rupa "highlight sesar" seperti versi lama yg
%   BENAR. `win`=[] -> full span. `titleStr` (opsional) = judul kustom (dipakai
%   L-grid PSG); absen -> judul "fault F<uiNum>" (dipakai ekspor sesar).
    if nargin < 8, titleStr = ''; end
    ok = false;
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT) || isempty(h.recs), return; end
    nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    drawnow;   % pastikan dekorasi sesar aktif (HW/FW/POI/vlines) sudah tergambar

    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 560]);
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    try
        ax2 = copyobj(h.axPOT, tmp);
        set(ax2,'Units','normalized','Position',[0.075 0.13 0.90 0.80]);
        % Buang garis FRAME-AKTIF (biru 'f<k>') yang ikut tersalin — bukan POI,
        % membingungkan di gambar arsip. POI vlines (Tag poiVline) DIPERTAHANKAN.
        try, delete(findall(ax2,'Tag','frameLine')); catch, end
        try, delete(findall(ax2,'Tag','frameTxt')); catch, end
        % --- KALIBRASI sumbu: remap semua child (XData->strain%, YData*velMult) ---
        kids = get(ax2,'Children');
        for c = kids(:).'
            try
                if isprop(c,'XData') && ~isempty(get(c,'XData'))
                    set(c,'XData', xmap(get(c,'XData')));
                end
                if isprop(c,'YData') && ~isempty(get(c,'YData'))
                    set(c,'YData', get(c,'YData') * velMult);
                end
                % Objek text (label vline/HW-FW): remap Position (x,y).
                if strcmp(get(c,'Type'),'text')
                    p = get(c,'Position');
                    if numel(p) >= 2, p(1) = xmap(p(1)); p(2) = p(2)*velMult; set(c,'Position',p); end
                end
            catch
            end
        end
        % Label sumbu + judul terkalibrasi.
        if xstrain, xlabel(ax2,'Cumulative strain (%)'); else, xlabel(ax2,'Frame'); end
        ylabel(ax2,'|V| (cm/s)');
        if ~isempty(titleStr)
            ttl = sprintf('%s — %s%s', i_baseNameSafe(h.df), char(titleStr), ...
                i_ifelse(isempty(win),'',' (zoom 200 frames)'));
        else
            ttl = sprintf('%s — fault F%s%s', i_baseNameSafe(h.df), i_uiNumStr(f), ...
                i_ifelse(isempty(win),'',' (zoom 200 frames)'));
        end
        title(ax2, ttl, 'Interpreter','none','Color',[0 0 0]);
        % Batas sumbu: auto-fit Y ke data (setelah scaling), X ke window bila zoom.
        set(ax2,'YLimMode','auto','XLimMode','auto');
        if ~isempty(win)
            xlim(ax2, sort([xmap(win(1)) xmap(win(2))]));
        end
        % SUMBU-X DIBALIK saat strain%: 0% di KIRI, -50% di KANAN (permintaan user).
        if xstrain, set(ax2,'XDir','reverse'); end
        exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true;
    catch
        ok = false;
    end
end

function ok = i_shotNetslipCalib(fig, f, ns, file, opts, strainTot, velMult, win)
%I_SHOTNETSLIPCALIB  Render NET-SLIP (HW−FW) sesar f ke `file`. LIGHT theme, X =
%   cumulative strain % (0 di KIRI, dibalik), Y = cm/s (ns*velMult). Arsir luas
%   START..END + titik + 4 garis vertikal POI (tinggi bertingkat). `win`=[a b]
%   frame -> zoom; [] -> full.
    ok = false;
    h = guidata(fig);
    nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    y = ns(:).' * velMult;                       % cm/s
    x = 1:numel(y);
    gd = isfinite(y); if ~any(gd), return; end

    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 520]);
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top'); grid(ax,'on');
    hold(ax,'on');
    % Kurva net-slip (ungu).
    plot(ax, xmap(x(gd)), y(gd), '-', 'Color',[0.45 0.10 0.65], 'LineWidth',2.4);
    % Arsir luas START..END.
    a = f.startF; b = f.endF;
    if isfinite(a) && isfinite(b)
        a = max(1,round(min(a,b))); b = min(numel(y),round(max(a,b)));
        ia = a:b; ya = y(ia); gg = isfinite(ya);
        if sum(gg) >= 2
            xa = xmap(ia(gg)); ta = ya(gg);
            fill(ax, [xa fliplr(xa)], [ta zeros(1,numel(ta))], [0.55 0.30 0.75], ...
                'FaceAlpha',0.25,'EdgeColor','none');
        end
    end
    % Titik + garis vertikal POI (tinggi bertingkat).
    yl = [min(0,min(y(gd))) max(y(gd))]; if yl(2)<=yl(1), yl(2)=yl(1)+1; end
    poi = {'startF','START',0; 'nuc','NUC',1; 'fsr','FSR',2; 'endF','END',3};
    step = 0.075*(yl(2)-yl(1));
    for pk = 1:size(poi,1)
        kf = f.(poi{pk,1}); if ~(isscalar(kf)&&isfinite(kf)&&kf>=1&&kf<=numel(y)), continue; end
        kf = round(kf); col = pivcore.pot.snapPoints.color(lower(poi{pk,2}));
        yv = y(kf);
        if isfinite(yv)
            plot(ax, xmap(kf), yv, 'o','MarkerSize',5,'LineWidth',1.2, ...
                'MarkerEdgeColor',col,'MarkerFaceColor','w');
        end
        yLab = yl(2) - poi{pk,3}*step;
        plot(ax, [xmap(kf) xmap(kf)], [yl(1) yLab], '--','Color',[col 0.85],'LineWidth',1.1);
        st = i_frameToStrain(kf, nF, strainTot);
        if isfinite(st), lbl = sprintf('%s %.2f%%', poi{pk,2}, st); else, lbl = sprintf('%s f%d', poi{pk,2}, kf); end
        text(ax, xmap(kf), yLab, lbl, 'Color',col,'FontSize',7.5,'FontWeight','bold', ...
            'VerticalAlignment','top','HorizontalAlignment','center', ...
            'BackgroundColor',[1 1 1 0.6],'Margin',1);
    end
    hold(ax,'off');
    if xstrain, xlabel(ax,'Cumulative strain (%)'); set(ax,'XDir','reverse'); else, xlabel(ax,'Frame'); end
    ylabel(ax,'net-slip (cm/s)');
    ttl = sprintf('%s — net-slip F%s%s', i_baseNameSafe(h.df), i_uiNumStr(f), ...
        i_ifelse(isempty(win),'',' (zoom 200 frames)'));
    title(ax, ttl, 'Interpreter','none','Color',[0 0 0]);
    if ~isempty(win), xlim(ax, sort([xmap(win(1)) xmap(win(2))])); end
    try, exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true; catch, ok = false; end
end

function ok = i_shotNetslipAllCalib(fig, fCur, file, opts, strainTot, velMult, win)
%I_SHOTNETSLIPALLCALIB  Render NET-SLIP SEMUA sesar AKTIF (enabled) ber-HW/FW
%   BERTUMPUK dalam 1 plot ke `file`. Tiap sesar warna beda + label F# di puncak.
%   Garis vertikal POI HANYA untuk sesar `fCur` (yang sedang di-export folder ini)
%   supaya tak penuh. LIGHT theme, X = cumulative strain % (0 KIRI, dibalik),
%   Y = cm/s (ns*velMult). `win`=[a b] frame -> zoom; [] -> full.
    ok = false;
    h = guidata(fig);
    nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);
    F = i_activeFaults(h);   % scoping multi-PSG: hanya sesar garis PSG aktif

    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 1400 520]);
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top'); grid(ax,'on');
    hold(ax,'on');
    pal = pivui.grain5Palette.zonePalette(h);   % palet warna zona (vivid/lembut)
    ci = 0; ymin = 0; ymax = 0; nDrawn = 0;
    for k = 1:numel(F)
        f = F{k};
        if ~pivui.grain5Model.faultEnabled(f), continue; end          % skip OFF
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end      % SF via induk (fokus F# utama)
        [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        if ~(okHW && okFW && ~isempty(ns)), continue; end
        y = ns(:).' * velMult; x = 1:numel(y);
        gd = isfinite(y); if ~any(gd), continue; end
        ci = ci + 1; col = pal{mod(ci-1,numel(pal))+1};
        lw = 1.8; if strcmp(f.id, fCur.id), lw = 3.0; col = [0.45 0.10 0.65]; end  % sesar ini tebal ungu
        plot(ax, xmap(x(gd)), y(gd), '-', 'Color',col, 'LineWidth',lw);
        ymin = min(ymin, min(y(gd))); ymax = max(ymax, max(y(gd)));
        nDrawn = nDrawn + 1;
        % Label F# di puncak (nilai paling ekstrem) kurva.
        [~, ix] = max(abs(y(gd))); xg = x(gd); yg = y(gd);
        uN = pivui.grain5Model.faultUiNum(f); lblF = f.id; if ~isempty(uN), lblF = sprintf('F%d', round(uN)); end
        text(ax, xmap(xg(ix)), yg(ix), [' ' lblF], 'Color',col*0.7, 'FontSize',8, 'FontWeight','bold', ...
            'VerticalAlignment','middle','HorizontalAlignment','left','BackgroundColor',[1 1 1 0.5],'Margin',1);
    end
    if nDrawn == 0, return; end
    % Garis vertikal POI utk sesar INI saja (bertingkat).
    yl = [min(0,ymin) ymax]; if yl(2)<=yl(1), yl(2)=yl(1)+1; end
    poi = {'startF','START',0; 'nuc','NUC',1; 'fsr','FSR',2; 'endF','END',3};
    step = 0.075*(yl(2)-yl(1));
    for pk = 1:size(poi,1)
        kf = fCur.(poi{pk,1}); if ~(isscalar(kf)&&isfinite(kf)&&kf>=1), continue; end
        kf = round(kf); col = pivcore.pot.snapPoints.color(lower(poi{pk,2}));
        yLab = yl(2) - poi{pk,3}*step;
        plot(ax, [xmap(kf) xmap(kf)], [yl(1) yLab], '--','Color',[col 0.85],'LineWidth',1.1);
        st = i_frameToStrain(kf, nF, strainTot);
        if isfinite(st), lbl = sprintf('%s %.2f%%', poi{pk,2}, st); else, lbl = sprintf('%s f%d', poi{pk,2}, kf); end
        text(ax, xmap(kf), yLab, lbl, 'Color',col,'FontSize',7.5,'FontWeight','bold', ...
            'VerticalAlignment','top','HorizontalAlignment','center', ...
            'BackgroundColor',[1 1 1 0.6],'Margin',1);
    end
    hold(ax,'off');
    if xstrain, xlabel(ax,'Cumulative strain (%)'); set(ax,'XDir','reverse'); else, xlabel(ax,'Frame'); end
    ylabel(ax,'net-slip (cm/s)');
    ttl = sprintf('%s — net-slip ALL faults (%d) — POI: F%s%s', i_baseNameSafe(h.df), nDrawn, ...
        i_uiNumStr(fCur), i_ifelse(isempty(win),'',' (zoom 200 frames)'));
    title(ax, ttl, 'Interpreter','none','Color',[0 0 0]);
    if ~isempty(win), xlim(ax, sort([xmap(win(1)) xmap(win(2))])); end
    try, exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true; catch, ok = false; end
end

function xo = i_xmapStrain(xf, nF, strainTot, on)
%I_XMAPSTRAIN  Map frame -> cumulative strain % (vectorised) or identity.
    if on && nF > 1
        xo = (xf-1)/(nF-1) * strainTot;
    else
        xo = xf;
    end
end

function v = i_ifelse(c, a, b)
    if c, v = a; else, v = b; end
end


function ok = i_shotAxMainCalib(fig, f, scalar, k, poiLabel, file, opts, lc, strainTot)
%I_SHOTAXMAINCALIB  Render AX main (velmag/shear) at frame k to `file`. LIGHT
%   theme (white bg, BLACK text), NO tick marks, |V| colorbar CALIBRATED to cm/s
%   (x velMult), English caption, thin PSG line, + HW (red) & FW (blue) markers
%   at the PSG sampling origins with a label NEAR THE TOP and a leader pointing
%   DOWN to the dot. scalar = 'velmag'|'shear'.
    velMult = 0.005;
    if isstruct(opts) && isfield(opts,'velMult') && isscalar(opts.velMult) && opts.velMult>0
        velMult = opts.velMult;
    end
    ok = false;
    h = guidata(fig);
    if isempty(h.data), return; end
    scKey = 'velocity_magnitude'; if strcmp(scalar,'shear'), scKey = 'shear'; end
    kWant = max(1, min(round(k), pivcore.util.scalarOr(h.imgFrames,1)));
    if kWant > 1 && ~pivcore.util.isFullLoaded(h)
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    kk = max(1, min(kWant, pivcore.util.scalarOr(h.imgFrames,1)));

    % UKURAN FIGURE MENGIKUTI ASPEK DATA (axMain = ukuran gambar, tanpa whitespace).
    dataAsp = i_axMainDataAspect(h, kk);
    plotH = 520; cbW = 130; plotW = max(200, round(plotH * dataAsp));
    figW = plotW + cbW; figH = plotH + 90;
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 figW figH]);
    try, pivui.forceLightTheme(tmp); catch, end   % LIGHT theme (bg putih)
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
    try, set(ax,'Units','normalized','Position',[0.04 0.06 plotW/figW*0.96 plotH/figH*0.90]); catch, end
    cfg = h; cfg.scalarSrc = scKey;
    isShear = strcmp(scalar,'shear');
    if isShear
        cfg.shearAbs = lc.shearAbs; lab = 'shear strain (du/dy+dv/dx)';
    else
        cfg.climVel = lc.velmag;
    end
    pivcore.montage.renderScalarPanel(ax, h.data, kk, scKey, cfg);
    % LIGHT theme: bg PUTIH, teks/aksen HITAM (bukan abu). POLOS: tanpa tickmark.
    set(ax, 'Color','w', 'XColor',[0 0 0], 'YColor',[0 0 0], 'XTick',[], 'YTick',[]);
    cb = colorbar(ax);
    if isShear
        cb.Label.String = lab;
    else
        % |V| DIKALIBRASI cm/s: label angka tick = px/frame * velMult (data/warna
        % tak diubah, hanya LABEL angka -> satuan tampil cm/s). Pola GRAINEXPORT.
        cb.Label.String = '|V| (cm/s)';
        cl = clim(ax); t = get(cb,'Ticks');
        if isempty(t), t = linspace(cl(1), cl(2), 6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*velMult), t, 'UniformOutput', false));
    end
    set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
    hold(ax,'on');
    % Thin PSG sampling line.
    if ~isempty(h.line) && isfield(h.line,'p1')
        plot(ax, [h.line.p1(1) h.line.p2(1)], [h.line.p1(2) h.line.p2(2)], ...
            '-', 'Color',[1 0.6 0.1], 'LineWidth',0.8);
    end
    % HW (red) & FW (blue) markers at sampling origins. Label NEAR TOP of axes
    % (a few % margin from top) with a leader going DOWN to the dot.
    [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    ms = i_markerSize(h);
    if okHW, i_axMainHWFW(ax, h, hwRow, [0.90 0.10 0.10], 'HW', ms); end
    if okFW, i_axMainHWFW(ax, h, fwRow, [0.10 0.30 0.90], 'FW', ms); end
    hold(ax,'off');

    st = i_frameToStrain(kk, h.nF, strainTot);
    if isfinite(st)
        cap = sprintf('%s — %s — F%s %s (strain %.2f%%)', ...
            i_baseNameSafe(h.df), scalar, i_uiNumStr(f), poiLabel, st);
    else
        cap = sprintf('%s — %s — F%s %s (frame %d)', ...
            i_baseNameSafe(h.df), scalar, i_uiNumStr(f), poiLabel, kk);
    end
    title(ax, cap, 'Interpreter','none', 'Color',[0 0 0]);
    try, exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true; catch, ok = false; end
end

function i_axMainHWFW(ax, h, row, col, label, ms)
%I_AXMAINHWFW  One HW/FW marker at the PSG sampling origin: a filled dot + a
%   vertical leader going UP to a label that sits NEAR THE TOP of the axes
%   (a few % margin below the top edge). The leader line runs from the label
%   DOWN to the dot (label -> down -> dot). Marker size `ms`.
    if nargin < 6 || isempty(ms), ms = 4; end
    if isempty(row) || row < 1 || row > numel(h.recs), return; end
    o = h.recs(row).origin;
    if numel(o)~=2 || ~all(isfinite(o)), return; end
    yl = ylim(ax); dir = get(ax,'YDir');
    % "Atas" pada layar: bila YDir 'reverse' (citra), atas = yl(1); else yl(2).
    if strcmpi(dir,'reverse')
        yTopEdge = yl(1); yLab = yl(1) + 0.06*(yl(2)-yl(1));  % 6% margin dari tepi atas
    else
        yTopEdge = yl(2); yLab = yl(2) - 0.06*(yl(2)-yl(1));
    end %#ok<NASGU>
    % Titik marker.
    plot(ax, o(1), o(2), 'o', 'MarkerSize',ms, 'LineWidth',1.0, ...
        'MarkerEdgeColor',[1 1 1], 'MarkerFaceColor',col, 'HitTest','off','PickableParts','none');
    % Leader dari label (atas) TURUN ke titik.
    plot(ax, [o(1) o(1)], [yLab o(2)], '-', 'Color',col, 'LineWidth',1.0, ...
        'HitTest','off','PickableParts','none');
    text(ax, o(1), yLab, label, 'Color',[1 1 1], 'BackgroundColor',col, ...
        'EdgeColor',[1 1 1], 'Margin',1, 'FontWeight','bold', 'FontSize',9, ...
        'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
        'HitTest','off','PickableParts','none');
end


function i_onOpenExportFolder(fig)
    h = guidata(fig);
    grainRoot = fileparts(mfilename('fullpath'));
    r = pivcore.io.grain5FaultExport.rootDir(grainRoot);
    if ~isfolder(r)
        pivui.setStatus(fig,'Folder PAB5_export belum ada (belum ada ekspor).'); return;
    end
    try
        if ispc, winopen(r);
        elseif ismac, system(['open "' r '"']);
        else, system(['xdg-open "' r '"']);
        end
    catch
    end
    pivui.setStatus(fig, sprintf('Folder: %s', r));
end


% --- helper kecil TAB ⑨ ------------------------------------------------
function tf = i_chkOn(h, name, dflt)
    tf = dflt;
    if isfield(h,name) && ishghandle(h.(name)), tf = logical(get(h.(name),'Value')); end
end
function i_closeIf(x)
    try, if ~isempty(x) && ishghandle(x), delete(x); end, catch, end
end
function i_mapClear(m)
%I_MAPCLEAR  Kosongkan containers.Map (cache GS ekspor) di akhir sesi via onCleanup.
    try, if isa(m,'containers.Map') && m.Count > 0, remove(m, keys(m)); end, catch, end
end
function s = i_baseNameSafe(df)
    [~, s] = fileparts(char(df));
end

function out = i_expFaultCounts(df)
%I_EXPFAULTCOUNTS  Hook kolom EXTRA tabel eksperimen. df='__names__' -> {judul};
%   df=path .mat -> {nPSG, nFaultChk} (string). Diagnostik multi-PSG:
%     #PSG = jumlah garis PSG di _potdata.json (harapan user = 1).
%     #F   = jumlah sesar TER-CHECKLIST (HW + FW + START + END finite) — total;
%            bila #PSG>1 ditulis "total (a+b+..)" per garis. '?' = sesar tanpa
%            psgId (orphan). Baca headless; gagal -> '0'/'-'.
    if ischar(df) && strcmp(df,'__names__')
        out = {'#PSG','✔ Desc'};   % judul: jumlah garis PSG | sesar SELESAI dideskripsi / total
        return;
    end
    % (1) Jumlah garis PSG dari _potdata.json (berpusat-PSG).
    nPSG = 0; psgIds = {};
    try
        pd = pivcore.io.grain4PotData.read(df);
        if isstruct(pd) && isfield(pd,'psgLines') && iscell(pd.psgLines)
            nPSG = numel(pd.psgLines);
            for k = 1:numel(pd.psgLines)
                ln = pd.psgLines{k};
                if isstruct(ln) && isfield(ln,'id'), psgIds{end+1} = char(ln.id); end %#ok<AGROW>
            end
        end
    catch
    end
    % (2)+(3) Hitung #F ter-checklist HANYA di garis PSG NYATA (psgId ∈ psgLines);
    %   sesar hantu/orphan dilaporkan "+Ng". Sama seperti GRAIN5.
    out = i_faultCountStrings(df, nPSG, psgIds);
end

function ids = i_realPsgIds(doc)
%I_REALPSGIDS  Cellstr id garis PSG NYATA dari doc.psgLines ({} bila tak ada).
    ids = {};
    if isstruct(doc) && isfield(doc,'psgLines') && iscell(doc.psgLines)
        for k = 1:numel(doc.psgLines)
            ln = doc.psgLines{k};
            if isstruct(ln) && isfield(ln,'id'), ids{end+1} = char(ln.id); end %#ok<AGROW>
        end
    end
end

function out = i_faultCountStrings(df, nPSG, psgIds)
%I_FAULTCOUNTSTRINGS  {#PSG, "selesai/total"} — kolom ✔ Desc.
%   total    = sesar ter-checklist (HW+FW+START+END finite) di garis PSG NYATA
%              (psgId ∈ psgLines), sama seperti sebelumnya.
%   selesai  = sesar tsb yg SUDAH selesai dideskripsi di <base>_desc.json:
%              punya minimal 3 POI -> NUC-FSR + FS-max + FS-x (garis PSG-nya).
%   Format "sel/tot" (mis. "4/10"); multi-PSG -> "sel/tot (a+b+..)" per garis
%   berbasis SELESAI. Hantu/orphan sesar -> "+Ng".
    realSet = containers.Map('KeyType','char','ValueType','logical');
    for k = 1:numel(psgIds), realSet(psgIds{k}) = true; end
    nIdTot = 0; nGhost = 0;
    perPsgTot  = containers.Map('KeyType','char','ValueType','double');
    perPsgDone = containers.Map('KeyType','char','ValueType','double');
    doneTot = 0;
    % Peta POI-selesai per (psgId|F#) dari _desc.json (dibaca sekali).
    descMap = i_descPoiMap(df);   % containers.Map key 'psg|f' -> struct hasNucfsr/hasFsmax/hasFsx
    try
        doc = pivcore.io.grain5Faults.read(df);
        if isstruct(doc) && isfield(doc,'faults')
            for k = 1:numel(doc.faults)
                f = doc.faults{k};
                if ~isstruct(f), continue; end
                if ~pivui.grain5Model.faultChecklistDone(f), continue; end
                pid = '';
                if isfield(f,'psgId') && (ischar(f.psgId)||isstring(f.psgId)), pid = char(f.psgId); end
                if isempty(pid) || ~isKey(realSet, pid)
                    nGhost = nGhost + 1; continue;
                end
                nIdTot = nIdTot + 1;
                if isKey(perPsgTot, pid), perPsgTot(pid) = perPsgTot(pid) + 1; else, perPsgTot(pid) = 1; end
                % Selesai dideskripsi?
                un = pivui.grain5Model.faultUiNum(f);
                key = '';
                if ~isempty(un) && isfinite(un), key = sprintf('%s|%d', pid, round(un)); end
                if ~isempty(key) && isKey(descMap, key)
                    st = descMap(key);
                    if st.hasNucfsr && st.hasFsmax && st.hasFsx
                        doneTot = doneTot + 1;
                        if isKey(perPsgDone, pid), perPsgDone(pid) = perPsgDone(pid) + 1; else, perPsgDone(pid) = 1; end
                    end
                end
            end
        end
    catch
    end
    if nPSG > 1
        parts = {};
        for k = 1:numel(psgIds)
            d = 0; if isKey(perPsgDone, psgIds{k}), d = perPsgDone(psgIds{k}); end
            parts{end+1} = sprintf('%d', d); %#ok<AGROW>
        end
        fStr = sprintf('%d/%d (%s)', doneTot, nIdTot, strjoin(parts, '+'));
    else
        fStr = sprintf('%d/%d', doneTot, nIdTot);
    end
    if nGhost > 0, fStr = sprintf('%s +%dg', fStr, nGhost); end
    out = {sprintf('%d', nPSG), fStr};
end

function m = i_descPoiMap(df)
%I_DESCPOIMAP  Baca <base>_desc.json -> containers.Map key 'psgId|F#' -> struct
%   dgn flag hasNucfsr/hasFsmax/hasFsx (POI yg menandai sesar SELESAI
%   dideskripsi). Headless & aman; gagal -> map kosong.
    m = containers.Map('KeyType','char','ValueType','any');
    try
        doc = pivcore.io.grain4Desc.read(df);
    catch
        return;
    end
    if ~isstruct(doc) || ~isfield(doc,'rows'), return; end
    all = pivcore.io.grain4Desc.tocell(doc.rows);
    for k = 1:numel(all)
        try, r = pivcore.io.grain4Desc.normRow(all{k}); catch, continue; end
        pid  = ''; if isfield(r,'psgId'), pid = char(r.psgId); end
        fnum = ''; if isfield(r,'fNum'),  fnum = strtrim(char(r.fNum)); end
        if isempty(fnum), continue; end
        % fNum tabel DESC disimpan ber-awalan 'F' (mis. 'F1', 'F10') sedangkan
        % kunci sesar pakai uiNum polos (1, 10). Ambil ANGKA pertama dari fNum
        % supaya cocok (str2double('F1') = NaN dulu bikin semua baris terlewat
        % -> kolom "✔ Desc" selalu 0/N).
        tok = regexp(fnum, '\d+', 'match', 'once');
        if isempty(tok), continue; end
        fv = str2double(tok); if ~isfinite(fv), continue; end
        key = sprintf('%s|%d', pid, round(fv));
        if isKey(m, key), st = m(key); else, st = struct('hasNucfsr',false,'hasFsmax',false,'hasFsx',false); end
        poi = ''; if isfield(r,'poi'), poi = upper(strtrim(char(r.poi))); end
        switch poi
            case 'NUC-FSR', st.hasNucfsr = true;
            case 'ACT-FSR',  st.hasFsmax  = true;
            case 'X-FS',    st.hasFsx    = true;
        end
        m(key) = st;
    end
end
function s = i_uiNumStr(f)
    n = pivui.grain5Model.faultUiNum(f); s = '?';
    if ~isempty(n) && isfinite(n), s = sprintf('%d', round(n)); end
end
function num = i_curveNumSafe(h, row, posPx)
    num = NaN;
    try
        if ~isempty(row) && row>=1 && row<=numel(h.recs)
            t = pivui.grain5Fmt.curveNumTag(h, row, posPx);
            v = str2double(t); if isfinite(v), num = v; end
        end
    catch
    end
end
function pct = i_strainTotalSafe(h)
%I_STRAINTOTALSAFE  Total cumulative strain % of the experiment, read from the
%   .mat geometry (experiment_geometry.strain_cumm_pct) via frameCatalog.readGeom.
%   NaN if unavailable -> callers fall back to a frame axis.
    pct = NaN;
    try
        if isfield(h,'strainTotal') && isscalar(h.strainTotal) && isfinite(h.strainTotal)
            pct = h.strainTotal; return;
        end
        if isfield(h,'df') && ~isempty(h.df) && isfile(h.df)
            g = pivcore.export.frameCatalog.readGeom(h.df);   % 1st out = strain_cumm_pct
            if isscalar(g) && isfinite(g), pct = double(g); end
        end
    catch
    end
end


function h = i_dispCtrls(h, P, fig, x)
    % Kontrol ukuran titik POI (axPOT) · Moving Average · garis PSG (axMain).
    % Ditata di pita tepat DI ATAS toggles klik + save (dasar kolom kanan).
    WHITE = [1 1 1];
    % Baris 1 (y≈0.176): ukuran titik POI + Moving Average.
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[x 0.176 0.20 0.024],'String','Titik POI:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, x+0.20, 0.176, @() i_onPoiSize(fig,+1), @() i_onPoiSize(fig,-1), 'spPoi');
    h.chkMA = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[x+0.42 0.176 0.30 0.026],'String','Moving Avg','Value',0, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','ON: semua kurva POT dihaluskan moving-average (window = angka; atur pakai ▲/▼).', ...
        'Callback',@(s,e) i_onToggleMA(fig));
    h.txtMAwin = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[x+0.72 0.176 0.10 0.024],'String',sprintf('w=%d',h.maWin), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, x+0.83, 0.176, @() i_onMAStep(fig,+1), @() i_onMAStep(fig,-1), 'spMA');
    % Baris 2 (y≈0.144): garis PSG tebal + ukuran titik (axMain).
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[x 0.144 0.22 0.024],'String','Garis PSG:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[x+0.22 0.144 0.10 0.024],'String','tebal', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, x+0.33, 0.144, @() i_onPsgLW(fig,+1), @() i_onPsgLW(fig,-1), 'spPsgLW');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[x+0.55 0.144 0.10 0.024],'String','titik', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, x+0.66 , 0.144, @() i_onPsgMS(fig,+1), @() i_onPsgMS(fig,-1), 'spPsgMS');
end

function i_spinBtns(P, fig, x, y, upFcn, dnFcn, tag)
    % Sepasang tombol panah ▲ / ▼ mungil bersebelahan (spinner tanpa field).
    % `tag` opsional -> ditulis ke Tag tombol (memudahkan tes/temu-balik).
    if nargin < 7, tag = ''; end
    w = 0.05; h = 0.028;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x y w h],'String','▲','FontSize',8,'Tag',[tag 'Up'], ...
        'Callback',@(s,e) upFcn());
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x+w+0.004 y w h],'String','▼','FontSize',8,'Tag',[tag 'Dn'], ...
        'Callback',@(s,e) dnFcn());
end


% --- Aksi sesar (model "slot spreadsheet") ----------------------------
%   Sesar TIDAK lagi lahir dari tombol; ia lahir saat user MENGETIK angka di
%   kolom F# tabel (i_onFaultCellEdit). Tombol "+F" hanya menambah 1 baris slot
%   kosong (bila butuh > 15 baris). Sisip-F#/SubF DIBUANG (bikin kacau saat rename).

function i_onFaultAddSlot(fig)
%I_ONFAULTADDSLOT  Tombol "+F": tambah 1 BARIS slot kosong di akhir tabel.
%   Hanya berguna bila daftar sesar sudah > 15 (default). Tak membuat record.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    slots = i_ensureSlots(h);
    slots{end+1} = '';
    h.faultSlots = slots; guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Tambah 1 baris slot (total %d). Ketik F# di baris kosong.', numel(slots)));
end

function F = i_activeFaults(h)
%I_ACTIVEFAULTS  (GRAIN5_temp_2) Cell fault milik garis PSG AKTIF (h.activePsgId).
%   Scoping multi-PSG: tabel/slot/render hanya lihat sesar garis aktif. Fault
%   upsert/find/remove tetap by-id atas h.fdoc PENUH (lintas semua PSG).
    F = {};
    if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults')), return; end
    pid = ''; if isfield(h,'activePsgId'), pid = char(h.activePsgId); end
    F = pivui.grain5Model.faultsForPsg(h.fdoc, pid);
end

function ord = i_faultRowOrderPsg(h)
%I_FAULTROWORDERPSG  (GRAIN5_temp_2) Urutan baris tabel DIBATASI ke garis PSG aktif.
%   = pivui.grain5Model.faultRowOrder(h) yang disaring: hanya sesar ber-psgId ==
%   h.activePsgId. Dipakai semua jalur TAMPIL/RENDER/EXPORT agar konsisten dgn
%   tabel per-PSG. (Engine faultRowOrder bersama tak diubah demi regresi GRAIN5/6.)
    ord = {};
    full = pivui.grain5Model.faultRowOrder(h);
    pid = ''; if isfield(h,'activePsgId'), pid = char(h.activePsgId); end
    for k = 1:numel(full)
        if strcmp(pivui.grain5Model.psgIdOf(full{k}), pid), ord{end+1} = full{k}; end %#ok<AGROW>
    end
end

function slots = i_ensureSlots(h)
%I_ENSURESLOTS  Pastikan h.faultSlots ada, sinkron dgn record garis PSG AKTIF, &
%   panjang >=15. Slot = per-PSG (scoping multi-PSG GRAIN5_temp_2): hanya sesar
%   milik h.activePsgId yang muncul.
%   - Kosong (mis. baru load / ganti PSG) -> seed dari fault garis aktif lalu pad.
%   - Slot yang id-nya tak lagi punya record (garis aktif) -> kosongkan ('').
%   - Record garis aktif yang belum di slot manapun -> tempel ke slot kosong.
    MINROWS = 15;
    if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults'))
        slots = repmat({''}, 1, MINROWS); return;
    end
    active = i_activeFaults(h);                          % HANYA sesar garis PSG aktif
    activeIds = cell(1, numel(active));
    for k = 1:numel(active), activeIds{k} = active{k}.id; end
    slots = {};
    if isfield(h,'faultSlots') && ~isempty(h.faultSlots), slots = h.faultSlots(:).'; end
    if isempty(slots)
        slots = activeIds;                              % seed awal dari fault garis aktif
    end
    % Kosongkan slot yang record-nya hilang ATAU bukan milik garis aktif.
    for k = 1:numel(slots)
        if isempty(slots{k}), continue; end
        if ~any(strcmp(activeIds, slots{k})), slots{k} = ''; end
    end
    % Tempel record garis aktif yang belum ada di slot manapun.
    for k = 1:numel(activeIds)
        if any(strcmp(slots, activeIds{k})), continue; end
        empt = find(cellfun(@isempty, slots), 1);
        if isempty(empt), slots{end+1} = activeIds{k}; else, slots{empt} = activeIds{k}; end %#ok<AGROW>
    end
    % Pad ke minimal 15 baris.
    if numel(slots) < MINROWS, slots(end+1:MINROWS) = {''}; end
end

function [val, ok] = i_parseCellNum(raw)
%I_PARSECELLNUM  Validasi isian sel F#/SF: kosong -> ([],true); angka bulat >=1
%   -> (n,true); selain itu (huruf/0/negatif/desimal) -> ([],false).
    val = []; ok = false;
    s = strtrim(char(raw));
    if isempty(s), ok = true; return; end
    n = str2double(s);
    if isscalar(n) && isfinite(n) && n == round(n) && n >= 1, val = n; ok = true; end
end

function i_onFaultCellEdit(fig, evt)
%I_ONFAULTCELLEDIT  Callback edit sel kolom F# (angka NOMOR TAMPIL sesar).
%   SF DINONAKTIFKAN sementara: sesar hanya bernomor 1,2,3,... (kolom SF read-only).
%   NOMOR TAMPIL = f.uiNum (BOLEH duplikat); id record = kunci UNIK internal.
%   - Baris kosong + F# -> buat record baru (id unik, uiNum = angka).
%   - Baris berisi + ganti F# -> ubah uiNum saja (id & data record TETAP).
%   - F# dikosongkan -> hapus record.
%   Mode NORMAL: tolak nomor DUPLIKAT. Mode EDIT (h.faultEditMode ON): IZINKAN
%   duplikat (utk tukar-nukar penomoran); keluar Edit -> auto-sort (i_onFaultSort).
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); i_refreshFaultTab(fig); return; end
    if ~isstruct(h.fdoc), h.fdoc = pivcore.io.grain5Faults.emptyDoc(h.df); end
    ind = []; try, ind = evt.Indices; catch, end
    if isempty(ind), return; end
    r = ind(1,1); c = ind(1,2);
    if c ~= 3, i_refreshFaultTab(fig); return; end             % hanya F# (kol 3) editable (SF nonaktif)
    raw = ''; try, raw = evt.NewData; catch, end

    [val, ok] = i_parseCellNum(raw);
    if ~ok
        pivui.setStatus(fig,'Kolom F# harus ANGKA bulat >=1 atau kosong.');
        i_refreshFaultTab(fig); return;                        % batalkan edit invalid
    end

    slots = i_ensureSlots(h);
    if r < 1 || r > numel(slots), i_refreshFaultTab(fig); return; end
    oldId = slots{r};

    % --- F# dikosongkan: hapus record baris ini (bila ada) ---
    if isempty(val)
        if i_slotHasRecord(oldId), h = i_deleteFaultById(h, oldId); slots = i_slotsClearId(h.faultSlots, oldId); end
        slots{r} = '';
        h.faultSlots = slots; h.activeFaultId = ''; guidata(fig, h);
        i_refreshFaultTab(fig); pivui.setStatus(fig, sprintf('Baris %d dikosongkan.', r)); return;
    end

    editMode = isfield(h,'faultEditMode') && h.faultEditMode;

    % --- Tolak DUPLIKAT nomor (hanya mode NORMAL) ---
    if ~editMode
        for k = 1:numel(slots)
            if k == r || ~i_slotHasRecord(slots{k}), continue; end
            [fk, ~] = pivcore.io.grain5Faults.findFault(h.fdoc, slots{k});
            if isempty(fk), continue; end
            if isequal(pivui.grain5Model.faultUiNum(fk), round(val))
                pivui.setStatus(fig, sprintf('Sesar %d sudah ada (baris %d). Aktifkan "Edit" untuk izinkan duplikat.', round(val), k));
                i_refreshFaultTab(fig); return;
            end
        end
    end

    % --- Terapkan: buat baru (slot kosong) | ubah uiNum (record ada) ---
    if ~i_slotHasRecord(oldId)
        uid = sprintf('F%d', pivui.grain5Model.nextUniqueIdNum(h.fdoc));   % id INTERNAL unik
        f = pivcore.io.grain5Faults.faultStruct(uid, NaN, NaN, NaN, NaN, NaN, NaN);
        f.uiNum = round(val);
        f.psgId = char(h.activePsgId);                 % scoping: sesar milik garis PSG aktif
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        slots{r} = uid;
    else
        [f, idx] = pivcore.io.grain5Faults.findFault(h.fdoc, oldId);
        f.uiNum = round(val);                                  % ubah NOMOR TAMPIL saja
        h.fdoc.faults{idx} = f;                                % in-place (warna/data stabil)
    end
    h.faultSlots = slots; h.activeFaultId = slots{r}; guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Baris %d -> sesar %d%s.', r, round(val), i_dupNote(editMode)));
end

function s = i_dupNote(editMode)
    s = ''; if editMode, s = ' (mode Edit: duplikat diizinkan)'; end
end

function i_onFaultSort(fig)
%I_ONFAULTSORT  Susun ulang BARIS tabel berdasarkan NOMOR sesar (uiNum) menaik.
%   Baris terisi diurut stabil (duplikat -> pertahankan urutan relatif lama);
%   slot kosong DIBUANG lalu dipad kembali ke belakang (>=15). id record & data
%   TAK berubah — hanya posisi baris.
    h = guidata(fig);
    slots = i_ensureSlots(h);
    filled = {}; nums = [];
    for k = 1:numel(slots)
        if ~i_slotHasRecord(slots{k}), continue; end
        [fk, ~] = pivcore.io.grain5Faults.findFault(h.fdoc, slots{k});
        if isempty(fk), continue; end
        n = pivui.grain5Model.faultUiNum(fk); if isempty(n), n = inf; end
        filled{end+1} = slots{k}; nums(end+1) = n; %#ok<AGROW>
    end
    if isempty(filled)
        pivui.setStatus(fig,'Belum ada sesar untuk diurutkan.'); i_refreshFaultTab(fig); return;
    end
    [~, ord] = sort(nums, 'ascend');           % STABLE (MATLAB sort stabil) -> duplikat urut lama
    sorted = filled(ord);
    MINROWS = 15;
    newSlots = sorted;
    if numel(newSlots) < MINROWS, newSlots(end+1:MINROWS) = {''}; end
    h.faultSlots = newSlots;
    % PERSIST urutan: susun ulang record di h.fdoc.faults sesuai urutan tampil ini
    % lalu TULIS _faults.json. Tanpa ini urutan hanya di memori -> modul lain (GRAIN4)
    % memuat urutan record LAMA (sesar "kembali sebelum diurut"). Reorder hanya sesar
    % garis PSG aktif; sesar garis lain dipertahankan (reorderFaults).
    h.fdoc = pivcore.io.grain5Faults.reorderFaults(h.fdoc, sorted);
    guidata(fig, h);
    try, pivcore.io.grain5Faults.write(h.df, h.fdoc); catch, end
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Diurutkan %d sesar berdasarkan nomor (urutan disimpan).', numel(sorted)));
end

function i_onFaultEditToggle(fig)
%I_ONFAULTEDITTOGGLE  Toggle KUNCI penomoran sesar.
%   OFF->ON: buka kunci -> boleh tulis nomor apa pun, TERMASUK DUPLIKAT (utk
%   tukar-nukar penomoran tanpa penjaga bentrok).
%   ON->OFF: kunci lagi + OTOMATIS SORT (i_onFaultSort). Bila ada duplikat nomor,
%   urutan ditentukan oleh nomor (stable) — duplikat bersebelahan.
    h = guidata(fig);
    cur = isfield(h,'faultEditMode') && h.faultEditMode;
    h.faultEditMode = ~cur; guidata(fig, h);
    if h.faultEditMode
        i_syncFaultEditBtn(fig);
        pivui.setStatus(fig,'MODE EDIT penomoran ON: boleh tulis nomor apa pun (duplikat OK). Klik lagi utk kunci + urutkan.');
    else
        i_onFaultSort(fig);                    % keluar Edit -> auto-sort
        i_syncFaultEditBtn(fig);
        pivui.setStatus(fig,'Penomoran DIKUNCI + diurutkan berdasarkan nomor.');
    end
end

function i_syncFaultEditBtn(fig)
%I_SYNCFAULTEDITBTN  Selaraskan label/warna tombol Edit + ColumnEditable dgn mode.
    h = guidata(fig);
    on = isfield(h,'faultEditMode') && h.faultEditMode;
    if isfield(h,'btnFaultEdit') && ishghandle(h.btnFaultEdit)
        if on
            set(h.btnFaultEdit,'String','🔓 Kunci+Urut','Value',1,'ForegroundColor',[0.75 0.35 0]);
        else
            set(h.btnFaultEdit,'String','✎ Edit no.','Value',0,'ForegroundColor',[0.20 0.30 0.60]);
        end
    end
end

function h = i_deleteFaultById(h, id)
%I_DELETEFAULTBYID  Hapus sesar id + (bila UTAMA) semua SF anaknya. Return h.
    if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults')), return; end
    [f, idx] = pivcore.io.grain5Faults.findFault(h.fdoc, id);
    if idx < 1, return; end
    removed = {id};
    if isempty(pivui.grain5Model.parentId(f))
        for k = 1:numel(h.fdoc.faults)
            fk = h.fdoc.faults{k};
            if strcmp(pivui.grain5Model.parentId(fk), id), removed{end+1} = fk.id; end %#ok<AGROW>
        end
    end
    for k = 1:numel(removed), h.fdoc = pivcore.io.grain5Faults.removeFault(h.fdoc, removed{k}); end
    h.faultSlots = i_slotsClearIds(i_field(h,'faultSlots',{}), removed);
end

function slots = i_slotsClearId(slots, id)
    if isempty(slots), return; end
    for k = 1:numel(slots), if strcmp(slots{k}, id), slots{k} = ''; end, end
end

function slots = i_slotsClearIds(slots, ids)
    for j = 1:numel(ids), slots = i_slotsClearId(slots, ids{j}); end
end

function v = i_field(s, name, dflt)
    v = dflt; if isstruct(s) && isfield(s, name), v = s.(name); end
end

% --- Konvensi nilai SLOT ------------------------------------------------
%   ''      = baris kosong ;  'F<n>' = record sesar (id INTERNAL unik).
%   (Nomor TAMPIL sesar = f.uiNum, boleh duplikat — bukan bagian dari nilai slot.)

function tf = i_slotHasRecord(id)
%I_SLOTHASRECORD  true bila nilai slot menunjuk record nyata ('' -> false).
    tf = ~isempty(id);
end

function i_onFaultRemove(fig)
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, pivui.setStatus(fig,'Pilih sesar dulu (klik baris tabel).'); return; end
    delId = f.id; delNum = pivui.grain5Model.faultUiNum(f);
    h = i_deleteFaultById(h, delId);          % hapus record + kosongkan slot
    h.activeFaultId = ''; guidata(fig, h);
    i_refreshFaultTab(fig);
    if isempty(delNum), pivui.setStatus(fig, 'Sesar dihapus.');
    else, pivui.setStatus(fig, sprintf('Sesar %d dihapus.', round(delNum))); end
end

function i_onPickFaultRow(fig, evt)
    ind = [];
    try, ind = evt.Indices; catch, end
    if isempty(ind), return; end
    r = ind(1,1);
    h = guidata(fig);
    if r < 1 || r > numel(h.faultIds), return; end
    id = h.faultIds{r};
    % Kolom ⏻ (toggle ON/OFF) TAK ditampilkan lagi -> klik baris = seleksi sesar.
    i_setActiveFault(fig, id);      % '' bila slot kosong (aman: tak menyeleksi)
end

function i_toggleFaultEnabled(fig, id)
%I_TOGGLEFAULTENABLED  Balik status ON/OFF sesar `id`. OFF -> tak dirender & tak
%   diekspor (input DIPERTAHANKAN). Refresh tabel + render + tabel export.
    h = guidata(fig);
    [f, idx] = pivcore.io.grain5Faults.findFault(h.fdoc, id);
    if idx < 1, return; end
    f.enabled = ~pivui.grain5Model.faultEnabled(f);
    h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f); guidata(fig, h);
    i_refreshFaultTab(fig);
    if ~isempty(h.recs), pivui.grain4Shell.renderPOT(fig); end
    i_drawFaultPsgMarker(fig);
    if isfield(h,'tblExport') && ishghandle(h.tblExport), i_refreshExportTab(fig); end
    st = 'ON'; if ~f.enabled, st = 'OFF'; end
    pivui.setStatus(fig, sprintf('Sesar %s: %s.', id, st));
end

function i_onToggleActiveFault(fig)
%I_ONTOGGLEACTIVEFAULT  Tombol ON/OFF di baris +F: balik status sesar AKTIF.
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, pivui.setStatus(fig,'Pilih sesar dulu (klik baris tabel).'); return; end
    i_toggleFaultEnabled(fig, f.id);
end

function i_setActiveFault(fig, id)
    % Pindah sesar aktif: TIDAK menghitung/mengubah titik START/END/NUC/FSR sesar
    % apa pun (nilai TERKUNCI seperti disimpan user). Hanya ganti fokus + render.
    h = guidata(fig); h.activeFaultId = char(id); guidata(fig, h);
    i_rebuildAllTaperTracks(fig);  % pastikan cache interp taper SEMUA F# terkini (bayangan referensi)
    h = guidata(fig);
    % Sinkronkan seleksi baris tabel (posisi di urutan tampil) + sorotan HIJAU.
    row = find(strcmp(h.activeFaultId, h.faultIds), 1);
    if ~isempty(row) && isfield(h,'tblFault') && ishghandle(h.tblFault)
        try, h.tblFault.Selection = row; catch, end
    end
    i_styleFaultTable(fig);        % pindahkan sorotan HIJAU ke baris sesar aktif baru
    if ~isempty(h.recs), pivui.grain4Shell.renderPOT(fig); end
    i_drawFaultPsgMarker(fig);     % titik HW/FW sesar aktif di garis PSG (axMain)
    i_refreshFaultAngleLabel(fig);
    i_refreshDescTable(fig);       % FILTER nested: tampilkan hanya baris DESC F# aktif
    % GRAIN4: bila jendela X aktif -> RATA-KIRI plot ke START sesar (skala X dijaga).
    [fa, ia] = pivui.grain5Model.activeFault(h);
    if ia >= 1, i_potXLeftAlign(fig, fa); else, i_applyPotXLim(fig); end
end

function i_stepFault(fig, d)
%I_STEPFAULT  Pindah seleksi sesar/SF ke tetangga TERISI di tabel (slot kosong
%   dilewati). d=-1 prev (Ctrl+M), d=+1 next (Ctrl+/). CLAMP di ujung (TAK wrap).
%   Belum ada seleksi -> pilih baris TERISI pertama.
    i_suspendAxZoomForRoi(fig);   % matikan MODE zoom (view tetap) -> render/set-fcn
                                  % tak ditolak (hindari warning "mode is active")
    h = guidata(fig);
    ids = h.faultIds;
    filled = find(~cellfun(@isempty, ids));           % indeks baris terisi
    if isempty(filled), pivui.setStatus(fig,'Belum ada sesar. Ketik F# di baris tabel dulu.'); return; end
    cur = find(strcmp(h.activeFaultId, ids), 1);
    if isempty(cur)
        i_setActiveFault(fig, ids{filled(1)});        % belum ada seleksi -> terisi pertama
        pivui.setStatus(fig, sprintf('Sesar aktif: %s.', ids{filled(1)})); return;
    end
    p = find(filled == cur, 1);                        % posisi cur di antara baris terisi
    if isempty(p), p = 1; end
    q = max(1, min(numel(filled), p + sign(d)));       % clamp, no wrap
    if q == p
        edge = 'pertama'; if d > 0, edge = 'terakhir'; end
        pivui.setStatus(fig, sprintf('Sudah di sesar %s (%s).', ids{cur}, edge)); return;
    end
    i_setActiveFault(fig, ids{filled(q)});
    pivui.setStatus(fig, sprintf('Sesar aktif: %s.', ids{filled(q)}));
    i_reclaimFigureKeys(fig);   % tombol ◀F/F▶ tak curi fokus keyboard
end

function i_onToggleStickyCtrl(fig)
%I_ONTOGGLESTICKYCTRL  Toggle STICKY CTRL (tombol '⌃ Ctrl'): ON = hotkey tanpa
%   menahan Control (huruf/angka polos diperlakukan +Ctrl di i_onKeyPress). OFF =
%   perlu tahan Ctrl seperti biasa. Selalu kembalikan fokus keyboard ke figure.
    i_suspendAxZoomForRoi(fig);   % matikan MODE zoom (view tetap) sebelum set-fcn
    h = guidata(fig);
    h.stickyCtrl = ~(isfield(h,'stickyCtrl') && h.stickyCtrl);
    guidata(fig, h);
    if isfield(h,'btnStickyCtrl') && ishghandle(h.btnStickyCtrl)
        try, set(h.btnStickyCtrl,'Value', double(h.stickyCtrl)); catch, end
    end
    if h.stickyCtrl
        pivui.setStatus(fig, ['Tahan-Ctrl AKTIF: tekan hotkey TANPA menahan Control ' ...
            '(q=Ctrl+Q, 1..4=POI, dst). +Shift utk varian PRP. Ketik di kotak teks tetap normal.']);
    else
        pivui.setStatus(fig, 'Tahan-Ctrl MATI: hotkey perlu tahan Control seperti biasa.');
    end
    i_reclaimFigureKeys(fig);   % kembalikan fokus keyboard (hotkey langsung hidup)
end

function i_onFaultAssign(fig, role)
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1
        pivui.setStatus(fig,'Ketik F# di tabel dulu, baru "⬆ Jadikan HW / ⬇ Jadikan FW".'); return;
    end
    if strcmpi(role,'fw') && ~isempty(pivui.grain5Model.parentId(f))
        pivui.setStatus(fig,'Sub-fault hanya bisa di-assign HANGING WALL (FW mengikuti F utama).'); return;
    end
    r = i_selCurveRow(h);
    if isempty(r)
        pivui.setStatus(fig,'Klik satu kurva di axPOT dulu, baru "Jadikan HW/FW".'); return;
    end
    posPx = NaN;
    if isfield(h.recs(r),'posPx') && isscalar(h.recs(r).posPx), posPx = h.recs(r).posPx; end
    if ~isfinite(posPx), pivui.setStatus(fig,'Kurva terpilih tak punya posPx valid.'); return; end
    if strcmpi(role,'fw'), f.fwPosPx = posPx; else, f.hwPosPx = posPx; end
    h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f); guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('%s: kurva posPx=%.0f jadi %s.', f.id, posPx, upper(char(role))));
end

function i_onFaultSetPoint(fig, which)
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, pivui.setStatus(fig,'Pilih/tambah sesar dulu.'); return; end
    nF = h.nF; k = max(1, min(pivcore.util.scalarOr(h.frame,1), max(nF,1)));
    [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    fsnap = k;
    if okHW
        [~, y] = pivcore.pot.records.curveXY(h.recs(hwRow), nF);
        y = pivui.grain4Shell.applyTrimYV(h.recs(hwRow), y);
        fsnap = pivcore.pot.snapPoints.snapFrame(y, k);
    elseif okFW
        [~, y] = pivcore.pot.records.curveXY(h.recs(fwRow), nF);
        y = pivui.grain4Shell.applyTrimYV(h.recs(fwRow), y);
        fsnap = pivcore.pot.snapPoints.snapFrame(y, k);
    end
    if ~isfinite(fsnap), fsnap = k; end
    switch lower(char(which))
        case 'start', f.startF = fsnap;
        case 'nuc',   f.nuc    = fsnap;
        case 'fsr',   f.fsr    = fsnap;
        case 'end',   f.endF   = fsnap;
    end
    h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f); guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('%s: %s = frame %d.', f.id, upper(char(which)), round(fsnap)));
end

function i_onAutoAssignFsr(fig)
%I_ONAUTOASSIGNFSR  Assign FSR tiap sesar UTAMA enabled ke frame PUNCAK net-slip
%   (nilai MAKSIMUM HW−FW, ber-konvensi tanda aktif = momen fault surface rupture).
%   Iterasi urutan tabel (faultRowOrder). Sesar tanpa HW+FW / tanpa nilai finite
%   dilewati. Reuse pivui.grain5Model.faultNetslip (sudah trim + signConv).
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    nSet = 0; nSkip = 0;
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end     % lewati SF
        if ~pivui.grain5Model.faultEnabled(f), continue; end          % lewati OFF
        ns = pivui.grain5Model.faultNetslip(h, f);
        if isempty(ns) || ~any(isfinite(ns)), nSkip = nSkip + 1; continue; end
        ns = ns(:).';
        vv = ns; vv(~isfinite(vv)) = -Inf;          % argmax hanya di nilai finite
        [~, kmax] = max(vv);
        f.fsr = kmax;
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        nSet = nSet + 1;
    end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('MaxNS: %d sesar di-set FSR ke puncak net-slip (%d dilewati).', nSet, nSkip));
end


% ---------------------------------------------------------------------
% Metodologi FSR/nukleasi — helper murni + otomasi POI baru.
%   Urutan temporal PASTI: NUC < FSR(=START) < MaxNS < END. Lihat memori
%   fsr-nucleation-methodology. Semua otomasi = batch sesar utama enabled.
% ---------------------------------------------------------------------
function idx = i_firstMinFrame(V, loF, hiF)
%I_FIRSTMINFRAME  Indeks frame PERTAMA (dari kiri) pada window [loF..hiF] di mana
%   vektor V mencapai nilai MINIMUM-nya. Abaikan NaN/Inf; plato minimum -> tepi
%   KIRI (kemunculan pertama, toleransi FP relatif). [] bila tak ada nilai finite
%   dalam window / window kosong. Mengembalikan indeks ABSOLUT (bukan relatif).
    idx = []; V = V(:).'; n = numel(V);
    lo = 1; hi = n;
    if nargin >= 2 && isscalar(loF) && isfinite(loF), lo = max(1, round(loF)); end
    if nargin >= 3 && isscalar(hiF) && isfinite(hiF), hi = min(n, round(hiF)); end
    if lo > hi || lo > n, return; end
    W = V(lo:hi); fin = isfinite(W);
    if ~any(fin), return; end
    mn = min(W(fin)); tol = 1e-9 * max(1, abs(mn));
    j = find(fin & (W <= mn + tol), 1, 'first');   % tepi KIRI plato minimum
    if isempty(j), return; end
    idx = lo + j - 1;                               % petakan balik ke frame absolut
end

function idx = i_minFwBackFromMax(V, kMax, win)
%I_MINFWBACKFROMMAX  Frame FSR dari kurva FW V, dicari pada ZONA SEMPIT tepat di
%   belakang puncak MaxNS. Metodologi: FSR = MINIMUM kecepatan FW DEKAT MaxNS —
%   TAK boleh nyangkut jauh di frame kecil (FW mulai ~0 di awal). Langkah:
%     zona = [max(1, kMax-win) .. kMax]  (win = lebar frame ke belakang; default full).
%     (1) mn  = NILAI minimum FW di zona (dasar; riak dangkal diabaikan).
%     (2) atMin = frame zona yang menyentuh dasar (|FW-mn| <= tol).
%     (3) rEdge = frame dasar TERBESAR (plateau terdekat MaxNS).
%     (4) FSR = tepi KIRI plateau itu (perluas ke kiri selama dasar bersambung).
%   [] bila zona kosong / tak ada nilai finite. Indeks ABSOLUT (offset loZ).
    idx = []; V = V(:).'; n = numel(V);
    hiZ = n;
    if nargin >= 2 && isscalar(kMax) && isfinite(kMax), hiZ = min(n, max(1, round(kMax))); end
    loZ = 1;
    if nargin >= 3 && isscalar(win) && isfinite(win) && win >= 0
        loZ = max(1, hiZ - round(win));             % zona sempit di belakang MaxNS
    end
    if hiZ < loZ, return; end
    W = V(loZ:hiZ); fin = isfinite(W);
    if ~any(fin), return; end
    mn = min(W(fin)); tol = 1e-9 * max(1, abs(mn));
    atMin = fin & (W <= mn + tol);                  % frame-frame di dasar minimum
    rEdge = find(atMin, 1, 'last');                 % plateau terdekat MaxNS (paling kanan)
    if isempty(rEdge), return; end
    lEdge = rEdge;
    while lEdge > 1 && atMin(lEdge-1)               % perluas ke kiri, dasar bersambung
        lEdge = lEdge - 1;
    end
    idx = loZ + lEdge - 1;                          % tepi KIRI plateau minimum (absolut)
end

function [frameMaxNS, ns] = i_faultMaxNsFrame(h, f)
%I_FAULTMAXNSFRAME  Frame PUNCAK (argmax) net-slip sesar f + vektor net-slip ns
%   (deret tampil + trim + signConv, via faultNetslip). [] bila net-slip tak ada.
    frameMaxNS = []; ns = [];
    nsv = pivui.grain5Model.faultNetslip(h, f);
    if isempty(nsv) || ~any(isfinite(nsv)), return; end
    ns = nsv(:).';
    vv = ns; vv(~isfinite(vv)) = -Inf;              % argmax hanya di nilai finite
    [~, kmax] = max(vv);
    frameMaxNS = kmax;
end

function [B, fwRow] = i_faultFwVec(h, f)
%I_FAULTFWVEC  Vektor nilai kurva FOOTWALL (FW) sesar f per-frame (deret tampil +
%   trim). [] bila FW tak ter-resolve. Reuse jalur faultNetslip (posPx->row).
    B = []; fwRow = [];
    [~, ~, fwRow, ~, okFW] = pivui.grain5Model.faultNetslip(h, f);
    if ~okFW || isempty(fwRow), fwRow = []; return; end
    [~, B] = pivcore.pot.records.curveXY(h.recs(fwRow), h.nF);
    B = pivui.grain4Shell.applyTrimYV(h.recs(fwRow), B);
end

function i_onAutoAssignMinFw(fig)
%I_ONAUTOASSIGNMINFW  Assign FSR-T tiap sesar UTAMA enabled ke frame MINIMUM kecepatan
%   Footwall (FW) dekat MaxNS. Telusur MUNDUR dari frameMaxNS (window 1..frameMaxNS):
%   cari NILAI FW terendah (dasar, riak dangkal diabaikan) -> plateau dasar TERDEKAT
%   MaxNS -> tepi KIRI plateau itu = FSR-T (i_minFwBackFromMax). Menjaga FSR-T dekat MaxNS
%   (tak nyangkut frame 1). Sesar tanpa FW / tanpa net-slip (MaxNS acuan) dilewati.
%   Menulis ke f.fsrT (TEORITIS); f.fsr (FSR-D deskriptif) diisi manual user, tak diubah.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    nSet = 0; nSkip = 0;
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end     % lewati SF
        if ~pivui.grain5Model.faultEnabled(f), continue; end          % lewati OFF
        B = i_faultFwVec(h, f);
        if isempty(B) || ~any(isfinite(B)), nSkip = nSkip + 1; continue; end
        frameMaxNS = i_faultMaxNsFrame(h, f);       % acuan zona sempit di belakangnya
        if isempty(frameMaxNS), nSkip = nSkip + 1; continue; end    % tanpa MaxNS: skip
        idx = i_minFwBackFromMax(B, frameMaxNS, h.minFwWin);
        if isempty(idx), nSkip = nSkip + 1; continue; end
        f.fsrT = idx;                                % FSR-T (teoritis); FSR-D (f.fsr) manual
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        nSet = nSet + 1;
    end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('MinFW: %d sesar di-set FSR-T ke minimum FW pada %d frame di belakang MaxNS (%d dilewati).', nSet, h.minFwWin, nSkip));
end

function i_onMinFwWin(fig, d)
%I_ONMINFWWIN  Spinner lebar zona MinFW (frame di belakang MaxNS). Range 5..60,
%   increment 5. Dipakai i_onAutoAssignMinFw (window [MaxNS-win .. MaxNS]).
    h = guidata(fig);
    h.minFwWin = max(5, min(60, round(h.minFwWin) + d*5));
    guidata(fig, h);
    if isfield(h,'txtMinFwWin') && ishghandle(h.txtMinFwWin)
        set(h.txtMinFwWin, 'String', sprintf('%d', h.minFwWin));
    end
    pivui.setStatus(fig, sprintf('MinFW: zona pencarian = %d frame di belakang MaxNS.', h.minFwWin));
end

function idx = i_nucTFromNucD(ns, nucD, win)
%I_NUCTFROMNUCD  Frame NUC-T (titik belok net-slip) dari net-slip ns, telusur MUNDUR
%   dari NUC-D. Metodologi: net-slip turun TERJAL saat mundur lalu jadi LANDAI / LEMBAH
%   -> NUC-T = "kaki" divergensi = awal daerah landai (min lokal pertama saat mundur).
%   Zona sempit = [max(1, nucD-win) .. nucD]. Net-slip MENTAH (tanpa smoothing).
%   [] bila zona kosong / net-slip tak finite. Indeks ABSOLUT.
    idx = []; ns = ns(:).'; n = numel(ns);
    if ~(isscalar(nucD) && isfinite(nucD)), return; end
    hiZ = min(n, max(1, round(nucD)));
    loZ = 1;
    if nargin >= 3 && isscalar(win) && isfinite(win) && win >= 0
        loZ = max(1, hiZ - round(win));
    end
    if hiZ < loZ, return; end
    W = ns(loZ:hiZ); m = numel(W);
    fin = isfinite(W);
    if nnz(fin) < 2, return; end
    % Telusur MUNDUR dari kanan (dekat NUC-D): net-slip menurun; NUC-T = frame pertama
    % (mundur) di mana net-slip BERHENTI turun (mulai datar/naik saat mundur) = awal
    % daerah landai / lembah. Bandingkan antar frame finite berurutan.
    gi = find(fin);                          % indeks finite (relatif zona), menaik
    tol = 1e-9 * max(1, max(abs(W(fin))));
    % mulai dari finite paling kanan (dekat NUC-D), mundur ke finite sebelumnya.
    curRel = gi(end);
    for j = numel(gi)-1 : -1 : 1
        prevRel = gi(j);
        % mundur: prev (frame lebih kecil) vs cur. Net-slip naik ke arah NUC-D, jadi
        % normalnya prev < cur (mundur => turun). "Berhenti turun" saat prev >= cur - tol
        % (datar) atau prev > cur (naik saat mundur = sudah di lembah/landai).
        if W(prevRel) >= W(curRel) - tol
            break;                           % curRel = awal daerah landai (kaki)
        end
        curRel = prevRel;                    % masih turun tajam saat mundur -> lanjut
    end
    idx = loZ + curRel - 1;                  % petakan ke frame absolut
end

function [A, hwRow] = i_faultHwVec(h, f)
%I_FAULTHWVEC  Vektor nilai kurva HANGING WALL (HW) sesar f per-frame (deret tampil +
%   trim). [] bila HW tak ter-resolve. Reuse jalur faultNetslip (posPx->row).
    A = []; hwRow = [];
    [~, hwRow, ~, okHW, ~] = pivui.grain5Model.faultNetslip(h, f);
    if ~okHW || isempty(hwRow), hwRow = []; return; end
    [~, A] = pivcore.pot.records.curveXY(h.recs(hwRow), h.nF);
    A = pivui.grain4Shell.applyTrimYV(h.recs(hwRow), A);
end

function i_onAutoAssignNucT(fig)
%I_ONAUTOASSIGNNUCT  Assign NUC-T (teoritis) tiap sesar UTAMA enabled = titik belok
%   net-slip (kaki divergensi) telusur MUNDUR dari NUC-D. BUTUH NUC-D (f.nuc) TERISI
%   sbg batas atas; sesar tanpa NUC-D / tanpa net-slip dilewati. Menulis ke f.nucT.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);
    nSet = 0; nSkip = 0;
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        if ~(isscalar(f.nuc) && isfinite(f.nuc)), nSkip = nSkip + 1; continue; end   % butuh NUC-D
        ns = pivui.grain5Model.faultNetslip(h, f);
        if isempty(ns) || ~any(isfinite(ns)), nSkip = nSkip + 1; continue; end
        idx = i_nucTFromNucD(ns, round(f.nuc), h.nucTWin);
        if isempty(idx), nSkip = nSkip + 1; continue; end
        f.nucT = idx;
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        nSet = nSet + 1;
    end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('NUC-T: %d sesar di-set titik belok net-slip pada %d frame di belakang NUC-D (%d dilewati; butuh NUC-D).', nSet, h.nucTWin, nSkip));
end

function i_onNucTWin(fig, d)
%I_ONNUCTWIN  Spinner lebar zona NUC-T (frame di belakang NUC-D). Range 10..100, step 10.
    h = guidata(fig);
    h.nucTWin = max(10, min(100, round(h.nucTWin) + d*10));
    guidata(fig, h);
    if isfield(h,'txtNucTWin') && ishghandle(h.txtNucTWin)
        set(h.txtNucTWin, 'String', sprintf('%d', h.nucTWin));
    end
    pivui.setStatus(fig, sprintf('NUC-T: zona pencarian = %d frame di belakang NUC-D.', h.nucTWin));
end

function i_onStartFromFsr(fig)
%I_ONSTARTFROMFSR  Set START tiap sesar UTAMA enabled = FSR-nya (START selalu =
%   FSR). Timpa SEMUA START yang sudah ada. f.fsr/nuc/endF tak diubah. Sesar tanpa
%   FSR (NaN) dilewati.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);
    nSet = 0; nSkip = 0;
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        if ~(isscalar(f.fsr) && isfinite(f.fsr)), nSkip = nSkip + 1; continue; end
        f.startF = round(f.fsr);
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        nSet = nSet + 1;
    end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Start>FSR: %d sesar START disamakan ke FSR (%d dilewati).', nSet, nSkip));
end

function i_onAutoAssignEnd(fig)
%I_ONAUTOASSIGNEND  Assign END tiap sesar UTAMA enabled ke frame net-slip TERENDAH
%   pertama SETELAH puncak MaxNS (window frameMaxNS..nF; konvensi tanda aktif).
%   Metodologis urutan terakhir. Sesar tanpa net-slip dilewati.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);
    nSet = 0; nSkip = 0;
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        [frameMaxNS, ns] = i_faultMaxNsFrame(h, f);
        if isempty(frameMaxNS) || isempty(ns), nSkip = nSkip + 1; continue; end
        idx = i_firstMinFrame(ns, frameMaxNS, numel(ns));   % min-pertama SETELAH puncak
        if isempty(idx), nSkip = nSkip + 1; continue; end
        f.endF = idx;
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        nSet = nSet + 1;
    end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('END: %d sesar di-set END ke net-slip terendah pertama setelah puncak (%d dilewati).', nSet, nSkip));
end

function i_onCheckInconsistency(fig)
%I_ONCHECKINCONSISTENCY  Periksa aturan metodologis tiap sesar UTAMA enabled &
%   kumpulkan ANOMALI (pelanggaran) ke tabel h.tblIncon (1 baris/pelanggaran):
%     (a) START == FSR-D                            -> 'START≠FSR-D'
%     (b) NUC-D < FSR-D                             -> 'NUC-D≥FSR-D'
%     (c) END == net-slip-terkecil-pertama-setelah-MaxNS -> 'END≠minNS'
%     (d) NUC-T < NUC-D  (nukleasi teoritis mendahului yg deskriptif) -> 'NUC-T≥NUC-D'
%   POI yang belum di-set (NaN) DILEWATI utk aturan terkait (belum diisi ≠ anomali).
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);
    rows = cell(0,3);
    fin = @(x) isscalar(x) && isfinite(x);
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        num = sprintf('F%g', pivui.grain5Model.faultUiNum(f));
        % (a) START == FSR-D.
        if fin(f.startF) && fin(f.fsr) && round(f.startF) ~= round(f.fsr)
            rows(end+1,:) = {num, 'START≠FSR-D', sprintf('START=%g, FSR-D=%g', round(f.startF), round(f.fsr))}; %#ok<AGROW>
        end
        % (b) NUC-D < FSR-D.
        if fin(f.nuc) && fin(f.fsr) && ~(f.nuc < f.fsr)
            rows(end+1,:) = {num, 'NUC-D≥FSR-D', sprintf('NUC-D=%g, FSR-D=%g', round(f.nuc), round(f.fsr))}; %#ok<AGROW>
        end
        % (d) NUC-T < NUC-D (nukleasi teoritis lebih awal dari deskriptif).
        if isfield(f,'nucT') && fin(f.nucT) && fin(f.nuc) && ~(f.nucT < f.nuc)
            rows(end+1,:) = {num, 'NUC-T≥NUC-D', sprintf('NUC-T=%g, NUC-D=%g', round(f.nucT), round(f.nuc))}; %#ok<AGROW>
        end
        % (c) END == net-slip terkecil pertama setelah MaxNS.
        if fin(f.endF)
            [frameMaxNS, ns] = i_faultMaxNsFrame(h, f);
            if ~isempty(frameMaxNS) && ~isempty(ns)
                endExp = i_firstMinFrame(ns, frameMaxNS, numel(ns));
                if ~isempty(endExp) && round(f.endF) ~= endExp
                    rows(end+1,:) = {num, 'END≠minNS', sprintf('END=%g, harusnya=%g', round(f.endF), endExp)}; %#ok<AGROW>
                end
            end
        end
    end
    if isfield(h,'tblIncon') && isvalid(h.tblIncon)
        if isempty(rows), set(h.tblIncon,'Data',{}); else, set(h.tblIncon,'Data',rows); end
    end
    if isempty(rows)
        pivui.setStatus(fig, 'Cek Inkonsistensi: semua sesar KONSISTEN dengan hipotesis. ✓');
    else
        pivui.setStatus(fig, sprintf('Cek Inkonsistensi: %d anomali ditemukan (lihat tabel).', size(rows,1)));
    end
end

function i_onExportLearnJson(fig)
%I_ONEXPORTLEARNJSON  Tombol "Buat JSON (ajar)": tulis SEMUA sesar utama enabled ke
%   satu file PAB5_learn/<exp>.json (frame MENTAH, px/frame). Per sesar: POI
%   {start,nucD,nucT,fsrD,fsrT,end} + maxNS + vektor netslip/fw/hw per-frame. Kanal
%   agar user mengajari CLCC cara membaca data (benang merah kurva<->POI). ATOMIC.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ~isempty(h.exportRootOverride) && isfolder(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
    end
    [~, base] = fileparts(h.df);
    outDir = fullfile(grainRoot, 'PAB5_learn');
    if ~isfolder(outDir), mkdir(outDir); end
    nF = max(1, round(pivcore.util.scalarOr(h.nF, 1)));
    nanNull = @(x) i_scalOrNull(x);
    ord = i_faultRowOrderPsg(h);
    faults = {};
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        A = i_faultHwVec(h, f);   % HW per-frame
        B = i_faultFwVec(h, f);   % FW per-frame
        maxNS = i_faultMaxNsFrame(h, f);
        s = struct();
        s.id     = f.id;
        s.uiNum  = nanNull(pivui.grain5Model.faultUiNum(f));
        s.hwPosPx = nanNull(f.hwPosPx);
        s.fwPosPx = nanNull(f.fwPosPx);
        s.poi = struct('start', nanNull(f.startF), 'nucD', nanNull(f.nuc), ...
            'nucT', nanNull(i_fldOr(f,'nucT')), 'fsrD', nanNull(f.fsr), ...
            'fsrT', nanNull(i_fldOr(f,'fsrT')), 'end', nanNull(f.endF));
        s.maxNS = nanNull(maxNS);
        s.okHW = okHW; s.okFW = okFW;
        s.netslip = i_vecOrEmpty(ns);
        s.hw      = i_vecOrEmpty(A);
        s.fw      = i_vecOrEmpty(B);
        faults{end+1} = s; %#ok<AGROW>
    end
    doc = struct('exp', base, 'nFrames', nF, 'units', 'px/frame', ...
        'signConvention', h.signConv, 'poiOrder', {{'start','nucT','nucD','fsrT','fsrD','end'}}, ...
        'note', 'NUC-D/FSR-D = deskriptif (manual user); NUC-T/FSR-T = teoritis (auto).', ...
        'faults', {faults});
    outPath = fullfile(outDir, sprintf('%s.json', i_safeName(base)));
    tmp = [outPath '.tmp'];
    txt = jsonencode(doc, 'PrettyPrint', true);
    fid = fopen(tmp, 'w');
    if fid < 0, pivui.setStatus(fig, sprintf('Gagal tulis JSON ajar: %s', outPath)); return; end
    fwrite(fid, txt, 'char'); fclose(fid);
    [ok, msg] = movefile(tmp, outPath, 'f');
    if ~ok, pivui.setStatus(fig, sprintf('Gagal simpan JSON ajar: %s', msg)); return; end
    pivui.setStatus(fig, sprintf('JSON ajar: %d sesar -> %s', numel(faults), outPath));
end

function v = i_scalOrNull(x)
%I_SCALORNULL  Skalar finite -> double; else [] (jsonencode -> null).
    v = [];
    if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); end
end

function v = i_fldOr(f, name)
%I_FLDOR  f.(name) bila ada & skalar; else NaN.
    v = NaN;
    if isstruct(f) && isfield(f,name) && isscalar(f.(name)), v = f.(name); end
end

function v = i_vecOrEmpty(x)
%I_VECOREMPTY  Vektor baris double (NaN dipertahankan -> null per elemen); [] bila kosong.
    v = [];
    if ~isempty(x) && isnumeric(x), v = double(x(:).'); end
end

function s = i_safeName(s)
%I_SAFENAME  Sanitasi nama file (buang karakter tak aman).
    s = regexprep(char(s), '[^\w\-.]', '_');
    if isempty(s), s = 'exp'; end
end

function i_onChainStartEnd(fig)
%I_ONCHAINSTARTEND  Rantai START/END tiap sesar UTAMA enabled dari FSR tetangganya
%   (urutan tabel): START(Fi)=FSR(Fi−1), END(Fi)=FSR(Fi+1). F1: START=frame 1.
%   Sesar TERAKHIR: END=frame terakhir (nF). FSR tetangga NaN -> POI itu dibiarkan.
%   Lakukan SETELAH finalisasi FSR (mis. sesudah Auto-FSR + koreksi manual user).
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    ord = i_faultRowOrderPsg(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    % Kumpulkan HANYA sesar utama enabled (urut tabel) -> daftar M.
    M = {};
    for k = 1:numel(ord)
        f = ord{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        M{end+1} = f; %#ok<AGROW>
    end
    nM = numel(M);
    if nM == 0, pivui.setStatus(fig,'Tak ada sesar aktif untuk dirantai.'); return; end
    nF = max(1, round(pivcore.util.scalarOr(h.nF, 1)));
    fsrOf = @(g) (isstruct(g) && isfield(g,'fsr') && isscalar(g.fsr) && isfinite(g.fsr)) * 1;
    nSet = 0;
    for i = 1:nM
        f = M{i};
        % START = FSR sesar SEBELUMNYA (Fi−1); F1 -> frame 1.
        if i == 1
            f.startF = 1;
        elseif fsrOf(M{i-1})
            f.startF = round(M{i-1}.fsr);
        end
        % END = FSR sesar BERIKUTNYA (Fi+1); sesar terakhir -> frame terakhir.
        if i == nM
            f.endF = nF;
        elseif fsrOf(M{i+1})
            f.endF = round(M{i+1}.fsr);
        end
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f);
        nSet = nSet + 1;
    end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Rantai START/END: %d sesar (F1 START=1, akhir END=frame %d).', nSet, nF));
end

function i_onJumpPoi(fig)
%I_ONJUMPPOI  Loncat frame aktif ke titik POI BERIKUTNYA yang SUDAH ADA pada F#
%   terseleksi, siklik START→NUC→FSR→END. Melewati POI yang belum di-set (NaN).
%   Bila frame kini = salah satu POI, loncat ke POI berikut (siklik).
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, pivui.setStatus(fig,'Pilih sesar dulu (klik baris tabel).'); return; end
    names = {'START','NUC','FSR','END'};
    vals = [f.startF, f.nuc, f.fsr, f.endF];
    have = isfinite(vals);
    if ~any(have)
        pivui.setStatus(fig, sprintf('%s belum punya titik POI. Tandai START/NUC/FSR/END dulu.', f.id)); return;
    end
    cur = round(pivcore.util.scalarOr(h.frame,1));
    % Cari POI ada berikutnya SETELAH frame kini (siklik). Bila frame = POI ada,
    % maju ke POI ada berikutnya; else POI ada pertama >= frame; else yang pertama.
    idxsHave = find(have);
    framesHave = round(vals(idxsHave));
    nextPos = [];
    for j = 1:numel(idxsHave)
        if framesHave(j) > cur, nextPos = idxsHave(j); break; end
    end
    if isempty(nextPos), nextPos = idxsHave(1); end   % siklik ke awal
    target = round(vals(nextPos));
    target = max(1, min(target, max(h.nF,1)));
    pivui.grain4Shell.gotoFrame(fig, target);
    pivui.setStatus(fig, sprintf('%s: loncat ke %s = frame %d.', f.id, names{nextPos}, target));
end

function i_hotChainFwHw(fig)
%I_HOTCHAINFWHW  MAKRO Ctrl+Shift+W: rantai kurva batas antar-sesar bertetangga.
%   Alur: (1) kurva terpilih -> FW sesar aktif (Fn); (2) pindah ke sesar TERISI
%   berikutnya (Fn+1, seperti Ctrl+/); (3) kurva SAMA -> HW (Fn+1). Sebuah kurva
%   batas fisik = FW sesar di kirinya & HW sesar di kanannya, jadi 1 gerakan
%   menautkan keduanya. GUARD: butuh kurva terpilih + ada sesar berikutnya.
    h = guidata(fig);
    % Prasyarat: kurva terpilih (dipakai kedua assign).
    if isempty(i_selCurveRow(h))
        pivui.setStatus(fig,'Klik satu kurva di axPOT dulu (Ctrl+Shift+W: FW→HW berikutnya).'); return;
    end
    % Prasyarat: sesar aktif ada.
    [~, idx0] = pivui.grain5Model.activeFault(h);
    if idx0 < 1
        pivui.setStatus(fig,'Pilih sesar dulu (Ctrl+Shift+W).'); return;
    end
    fnId = h.activeFaultId;
    % (1) FW pada sesar aktif (Fn).
    i_onFaultAssign(fig, 'fw');
    % (2) Pindah ke sesar berikutnya. Bila TAK pindah (sudah terakhir), batal HW.
    i_stepFault(fig, +1);
    h = guidata(fig);
    if strcmp(h.activeFaultId, fnId)
        pivui.setStatus(fig, sprintf('%s: FW di-set. Tak ada sesar berikutnya untuk HW.', fnId));
        return;
    end
    nextId = h.activeFaultId;
    % (3) HW pada sesar berikutnya (Fn+1) dgn kurva yang SAMA.
    i_onFaultAssign(fig, 'hw');
    pivui.setStatus(fig, sprintf('Rantai batas: kurva → FW(%s) & HW(%s).', fnId, nextId));
end

function i_onKeyPress(fig, evt)
%I_ONKEYPRESS  Hotkey GRAIN5_temp (SEMUA pakai Ctrl). evt = OBJEK KeyData (BUKAN
%   struct) -> akses properti LANGSUNG (isfield() selalu false pada objek). Ctrl
%   -> 'control', Shift -> 'shift'. Ctrl+panah DIHINDARI (mac Mission Control).
%   Daftar lengkap = i_hotkeyList() (dipakai juga oleh TAB ⓪ Help).
%     Frame (semua tab):  Ctrl+,/. = ±1 · Ctrl+</> = ±5
%     Sesar (tab sesar):  Ctrl+M = prev F# · Ctrl+/ = next F#
%     Set POI:            Ctrl+1=START · 2=END · 3=NUC · 4=FSR
%     Loncat POI:         Ctrl+J=START · K=END · L=NUC · ;=FSR · H=cycle
%     Bidang sesar:       Ctrl+Q = input/copy (kontekstual; interpolasi evolusi ALWAYS-ON, recompute saat commit)
%     Taper (topografi):  Ctrl+W = input (interp ALWAYS-ON, auto-seed) · Ctrl+G = grab keyframe terdekat
%     Ukur sesar (poly):  Ctrl+E = buka (gambar polyline) · Ctrl+E lagi = kunci/simpan
%     Geser seleksi kurva (tabel kiri): Ctrl+[ = naik 1 · ] = turun 1 ·
%                                       Ctrl+{ = naik 5 · } = turun 5
    try
        mods = {}; try, mods = evt.Modifier; catch, end
        if isempty(mods), mods = {}; end
        key = ''; try, key = char(evt.Key); catch, end
        ch  = ''; try, if ~isempty(evt.Character), ch = char(evt.Character); end, catch, end
        % STICKY CTRL (tombol '⌃ Ctrl'): perlakukan hotkey seolah +Ctrl walau Ctrl
        % TAK ditahan. DILEWATI saat fokus di kotak edit/uitable (supaya mengetik
        % teks di kolom DESC/dll tak memicu hotkey). Modifier lain (shift) dijaga.
        if ~any(strcmp(mods,'control'))
            hh = guidata(fig);
            if isstruct(hh) && isfield(hh,'stickyCtrl') && hh.stickyCtrl && ~i_typingFocus(fig)
                mods{end+1} = 'control'; %#ok<AGROW>
            end
        end
        hasShift = any(strcmp(mods,'shift'));
        if ~any(strcmp(mods,'control')), return; end   % SEMUA hotkey pakai Ctrl
        % --- Ctrl(+Shift)+ , / . : langkah frame (berlaku semua tab) ---
        isPrev = strcmp(key,'comma')  || strcmp(ch,',') || strcmp(ch,'<');
        isNext = strcmp(key,'period') || strcmp(ch,'.') || strcmp(ch,'>');
        if isPrev || isNext
            n = 1; if hasShift, n = 5; end   % Ctrl+Shift (=< />) -> 5 frame
            if isPrev, pivui.grain4Shell.stepFrame(fig, -n); else, pivui.grain4Shell.stepFrame(fig, +n); end
            return;
        end
        % --- Ctrl+Shift+←/→ = GESER jendela X 10 frame (spt tombol ◀ ▶). ---
        if hasShift && (strcmp(key,'leftarrow') || strcmp(key,'rightarrow'))
            if strcmp(key,'leftarrow'), i_onPotXPan(fig, -1); else, i_onPotXPan(fig, +1); end
            return;
        end
        % --- Ctrl+Shift+↑/↓ = NAIK/TURUN cut-off net-slip AXSLIP (langkah 0.1) ---
        if hasShift && (strcmp(key,'uparrow') || strcmp(key,'downarrow'))
            if strcmp(key,'uparrow'), i_onAxslipCutStep(fig, +1); else, i_onAxslipCutStep(fig, -1); end
            return;
        end
        % --- Interpolasi evolusi kini ALWAYS-ON (mesin latar): hotkey Ctrl+Shift+Q
        %     DIBUANG (dulu toggle overlay). Recompute otomatis saat keyframe di-commit
        %     via Ctrl+Q. Shift+Q kini jatuh ke cabang Ctrl+Q input di bawah. ---
        % --- Ctrl+Q = INPUT/COPY BIDANG SESAR utk BARIS DESKRIPSI (DX) terpilih
        %     (kontekstual, gaya After Effects): DX kosong + interpolasi AKTIF -> COPY
        %     bentuk interpolasi @frame DX jadi ROI editable; DX kosong + tak aktif ->
        %     ROI kosong (gambar manual); DX sudah ber-vertices -> edit. Tekan lagi =
        %     KUNCI -> jadi SUPERVISED keyframe + auto-recompute interpolasi. Ctrl+E/\
        %     alias. ---
        if strcmp(key,'q') || strcmp(ch,'q') || strcmp(ch,'Q') ...
                || strcmp(key,'e') || strcmp(ch,'e') || strcmp(ch,'E') ...
                || strcmp(key,'backslash') || strcmp(ch,'\')
            i_onToggleFaultPoly(fig); return;
        end
        % --- Ctrl+W (±Shift) = TOGGLE alat TAPER (kemiringan topografi) DX terpilih
        %     (toggle: buka garis 2-titik -> tekan lagi = kunci/simpan ke baris DX).
        %     Interpolasi taper kini ALWAYS-ON (mesin latar; recompute saat commit/hapus)
        %     -> tak ada lagi hotkey interpolasi terpisah. Ctrl+W di frame antara AUTO-
        %     SEED dari interpolasi. Sejajar Ctrl+Q bidang sesar. ---
        if strcmp(key,'w') || strcmp(ch,'w') || strcmp(ch,'W')
            i_onToggleTaper(fig); return;
        end
        % --- Ctrl+R = TOGGLE alat TITIK NUKLEASI (garis 2-titik; DX POI=NUC-FSR):
        %     titik-1 = posisi nukleasi, titik-2 = dinding pendorong. Tekan lagi =
        %     kunci/simpan (jarak/kedalaman/jarak-F1 cm) ke baris DX. ---
        if strcmp(key,'r') || strcmp(ch,'r') || strcmp(ch,'R')
            i_onToggleNucPt(fig); return;
        end
        % --- Ctrl+G = "GRAB from overlap": toggle alat taper dgn seed dari keyframe
        %     taper TERDEKAT LINTAS-F# (kontinuitas topografi zona overlap antar sesar).
        %     Objek topografi kontinu tapi jendela pengamatan per-sesar -> di overlap
        %     bentuk taper harus konsisten antar-F#. Ctrl+G lagi = kunci ke DX aktif. ---
        if strcmp(key,'g') || strcmp(ch,'g') || strcmp(ch,'G')
            i_onToggleTaperGrab(fig); return;
        end
        % --- Ctrl+- = PERLEBAR jendela X axPOT (zoom-out) · Ctrl+shift+= (=Ctrl++)
        %     = PERSEMPIT (zoom-in). Independen (sebelum guard). Deteksi robust:
        %     minus/hyphen/'-' -> perlebar ; equal/plus/'+'/'=' -> persempit. ---
        isWiden  = strcmp(key,'hyphen') || strcmp(key,'minus') || strcmp(ch,'-') || strcmp(key,'subtract');
        isNarrow = strcmp(key,'equal') || strcmp(ch,'+') || strcmp(ch,'=') || strcmp(key,'add');
        if isWiden,  i_onPotXWin(fig, +1); return; end   % perlebar (lebih banyak frame)
        if isNarrow, i_onPotXWin(fig, -1); return; end   % persempit (renggangkan)
        % --- Geser SELEKSI kurva tabel kiri: Ctrl+[ / ] (±1) · { / } (±5). ---
        %     Berlaku SEMUA tab (butuh kolom kiri mode 'curve'). Deteksi via
        %     Character ('[' ']' '{' '}') atau Key (leftbracket/rightbracket)+shift.
        isUp   = strcmp(ch,'[') || strcmp(ch,'{') || strcmp(key,'leftbracket');
        isDown = strcmp(ch,']') || strcmp(ch,'}') || strcmp(key,'rightbracket');
        if isUp || isDown
            big = hasShift || strcmp(ch,'{') || strcmp(ch,'}');   % { } = 5
            step = 1; if big, step = 5; end
            if isUp, i_moveCurveSel(fig, -step); else, i_moveCurveSel(fig, +step); end
            return;
        end
        % --- Ctrl+F = TOGGLE plot bawah AXSLIP <-> axPOT (independen; sebelum guard) ---
        if strcmp(key,'f') || strcmp(ch,'f') || strcmp(ch,'F')
            i_onToggleFaultSlip(fig); return;
        end
        % --- Navigasi sesar & POI (HANYA saat panel deskripsi/render sesar aktif) ---
        h = guidata(fig);
        if ~i_faultVisible(h), return; end
        % GRAIN4: hotkey ASSIGN GRAIN5 (Ctrl+Q/W HW/FW, Ctrl+E sudut, Ctrl+Shift+W chain)
        % DINONAKTIFKAN — GRAIN4 = editor interpretasi (catat), bukan assign.
        % --- Ctrl+` (backtick) = CYCLE FS (fault slip 0→1→2→0) baris terpilih ---
        if strcmp(key,'backquote') || strcmp(ch,'`') || strcmp(ch,'~')
            i_onDescCycleFs(fig); return;
        end
        % --- Ctrl+O = CYCLE seleksi baris deskripsi (siklik ke bawah) ---
        if strcmp(key,'o') || strcmp(ch,'o') || strcmp(ch,'O')
            i_onDescCycleRow(fig); return;
        end
        % --- HAPUS baris deskripsi terpilih: Ctrl+Shift+Backspace ATAU Ctrl+Shift+D.
        %   CATATAN: saat FOKUS di tabel DESKRIPSI (uitable), tombol Backspace/Delete
        %   DIMAKAN oleh uitable (dianggap edit sel) & TAK sampai ke WindowKeyPressFcn
        %   -> hotkey Backspace kerap "tak berfungsi". Ctrl+Shift+D (huruf) SELALU
        %   sampai (spt Ctrl+4/Ctrl+Q). Tombol '🗑 Hapus baris' tetap tersedia. ---
        if hasShift && (strcmp(key,'backspace') || strcmp(key,'delete') ...
                || double(ch)==8 || double(ch)==127 ...
                || strcmp(key,'d') || strcmp(ch,'d') || strcmp(ch,'D'))
            i_onDescDelRow(fig); return;
        end
        % --- Ctrl+1..4 (+Shift utk PRP) / Ctrl+T = TAMBAH BARIS deskripsi pada
        %     FRAME live dgn POI sesuai tombol (F# = sesar aktif). ---
        %     NUC: 1=BDF1 · 2=TF · 3=FSR · 4=ACT-FSR
        %     PRP (Ctrl+Shift+angka): 1=BDF1 · 2=TF · 3=FSR · 4=X-FS
        %     T=</blank>.
        %   Deteksi DIGIT via `key` (stabil lintas layout; Ctrl+Shift+digit kadang
        %   menghasilkan Character simbol). Shift memilih fase PRP.
        dig = 0;
        switch key
            case {'1','numpad1'}, dig = 1;
            case {'2','numpad2'}, dig = 2;
            case {'3','numpad3'}, dig = 3;
            case {'4','numpad4'}, dig = 4;
        end
        if dig == 0   % fallback via Character (US layout shift-digit -> simbol)
            switch ch
                case {'1','!'}, dig = 1;
                case {'2','@'}, dig = 2;
                case {'3','#'}, dig = 3;
                case {'4','$'}, dig = 4;
            end
        end
        poiKey = '';
        pref = 'NUC-'; if hasShift, pref = 'PRP-'; end
        switch dig
            case 1, poiKey = [pref 'BDF1'];                                       % Ctrl+1 NUC-BDF1 · +Shift PRP-BDF1
            case 2, poiKey = [pref 'TF'];                                         % Ctrl+2 NUC-TF · +Shift PRP-TF
            case 3, poiKey = [pref 'FSR'];                                        % Ctrl+3 NUC-FSR · +Shift PRP-FSR
            case 4, if hasShift, poiKey = 'X-FS'; else, poiKey = 'ACT-FSR'; end    % Ctrl+4 FS-max · +Shift FS-x
        end
        if ~isempty(poiKey), i_onDescAddRowPoi(fig, poiKey); return; end
        if strcmp(key,'t') || strcmp(ch,'t') || strcmp(ch,'T'), i_onDescAddRowPoi(fig, '</blank>'); return; end
        % Ctrl+M = prev F# ; Ctrl+/ = next F# (urutan tampil, clamp no-wrap).
        if strcmp(key,'m') || strcmp(ch,'m') || strcmp(ch,'M')
            i_stepFault(fig, -1); return;
        elseif strcmp(key,'slash') || strcmp(ch,'/')
            i_stepFault(fig, +1); return;
        end
        % Ctrl+J/K/L/; = LONCAT ke POI START/END/NUC/FSR · Ctrl+H = cycle antar DX.
        if strcmp(key,'h') || strcmp(ch,'h') || strcmp(ch,'H')
            if hasShift, i_onDescCycleRow(fig, -1); else, i_onDescCycleRow(fig, +1); end   % Shift=atas
            return;
        end
        if strcmp(key,'j') || strcmp(ch,'j') || strcmp(ch,'J'), i_jumpToPoi(fig,'start'); return; end
        if strcmp(key,'k') || strcmp(ch,'k') || strcmp(ch,'K'), i_jumpToPoi(fig,'end');   return; end
        if strcmp(key,'l') || strcmp(ch,'l') || strcmp(ch,'L'), i_jumpToPoi(fig,'nuc');   return; end
        if strcmp(key,'semicolon') || strcmp(ch,';'),           i_jumpToPoi(fig,'fsr');   return; end
    catch
    end
end

function tf = i_typingFocus(fig)
%I_TYPINGFOCUS  TRUE bila fokus figure sedang di kontrol PENGETIKAN (uitable atau
%   uicontrol Style='edit') -> hotkey tombol POLOS harus dilewati supaya tak
%   memicu aksi saat user mengetik. Deteksi via CurrentObject (andal utk tipe;
%   uitable Type='uitable', edit Style='edit'). Dipakai guard hotkey 'w' polos.
    tf = false;
    try
        co = get(fig, 'CurrentObject');
        if isempty(co) || ~ishghandle(co), return; end
        t = ''; try, t = get(co,'Type'); catch, end
        if strcmp(t,'uitable'), tf = true; return; end
        st = ''; try, st = get(co,'Style'); catch, end
        if strcmp(st,'edit'), tf = true; return; end
    catch
    end
end

function i_jumpToPoi(fig, which)
%I_JUMPTOPOI  Loncat frame aktif LANGSUNG ke POI tertentu (start/end/nuc/fsr)
%   sesar terseleksi bila POI itu sudah di-set. Beda dari i_onJumpPoi (siklik).
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, pivui.setStatus(fig,'Pilih sesar dulu (klik baris tabel).'); return; end
    switch lower(char(which))
        case 'start', v = f.startF; nm = 'START';
        case 'end',   v = f.endF;   nm = 'END';
        case 'nuc',   v = f.nuc;    nm = 'NUC';
        case 'fsr',   v = f.fsr;    nm = 'FSR';
        otherwise, return;
    end
    if ~(isscalar(v) && isfinite(v))
        pivui.setStatus(fig, sprintf('%s: %s belum ditandai.', f.id, nm)); return;
    end
    target = max(1, min(round(v), max(h.nF,1)));
    pivui.grain4Shell.gotoFrame(fig, target);
    pivui.setStatus(fig, sprintf('%s: loncat ke %s = frame %d.', f.id, nm, target));
end

function i_moveCurveSel(fig, d)
%I_MOVECURVESEL  Geser SELEKSI kurva di tabel kiri (mode 'curve') sebesar d baris
%   (negatif = ke atas, positif = ke bawah), clamp [1..nRecs]. Update h.selRows +
%   seleksi tabel + sorot kurva di axPOT (klik-kurva). Bila kolom kiri belum mode
%   kurva atau tak ada kurva -> pesan.
    h = guidata(fig);
    if isempty(h.recs)
        pivui.setStatus(fig,'Belum ada kurva.'); return;
    end
    if ~(isfield(h,'leftMode') && strcmp(h.leftMode,'curve'))
        pivui.setStatus(fig,'Tabel kiri belum mode KURVA (klik "Kurva/Exp" dulu).'); return;
    end
    n = numel(h.recs);
    cur = 1;
    if isfield(h,'selRows') && ~isempty(h.selRows), cur = round(h.selRows(1)); end
    nx = max(1, min(n, cur + d));
    if nx == cur && ((d<0 && cur==1) || (d>0 && cur==n))
        pivui.setStatus(fig, sprintf('Sudah di kurva %s.', i_edgeWord(d))); return;
    end
    h.selRows = nx; guidata(fig, h);
    if isfield(h,'tbl') && ishghandle(h.tbl)
        try, h.tbl.Selection = nx; catch, end
    end
    % Sorot kurva terpilih di axPOT + penanda sampling (axMain) — PANGGIL machinery
    % shell LANGSUNG (callHook onCurveClick saja TAK menyorot; itu cuma refresh
    % konteks). Ini yang bikin geser-kurva sebelumnya "engine jalan, kosmetik mati".
    pivui.grain4Shell.highlightSelPOT(fig);       % sorot kurva di axPOT (warna selCurveColor)
    try, pivui.grain4Shell.highlightSelAC(fig); catch, end
    pivui.grain4Shell.drawSampleMarker(fig);      % titik sampling kurva di axMain (garis PSG)
    try, pivui.grain4Shell.highlightCurveRow(fig, nx); catch, end
    pivui.grain4Shell.callHook(fig,'onCurveClick', nx);   % refresh konteks + txtFaultSel
    pivui.setStatus(fig, sprintf('Kurva terpilih: baris %d/%d.', nx, n));
end

function s = i_edgeWord(d)
    s = 'pertama'; if d > 0, s = 'terakhir'; end
end

function i_onNudgePoint(fig, which, d)
%I_ONNUDGEPOINT  Geser posisi START/END sesar aktif ±1 frame (spinner ▲/▼).
%   Auto-update: tabel + render (clamp kurva luar rentang otomatis). Bila titik
%   belum ada, mulai dari frame aktif.
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, pivui.setStatus(fig,'Pilih/tambah sesar dulu.'); return; end
    nF = h.nF;
    if strcmp(which,'start'), cur = f.startF; else, cur = f.endF; end
    if ~isfinite(cur), cur = max(1, min(pivcore.util.scalarOr(h.frame,1), nF)); end
    v = max(1, min(nF, round(cur) + d));
    if strcmp(which,'start'), f.startF = v; else, f.endF = v; end
    h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f); guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('%s: %s digeser -> frame %d.', f.id, upper(which), v));
end

function i_onFaultClearPoints(fig)
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, return; end
    f.nuc = NaN; f.fsr = NaN; f.startF = NaN; f.endF = NaN;
    h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f); guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Titik sesar %s dihapus.', f.id));
end

function i_onFaultRegen(fig)
%I_ONFAULTREGEN  Reset plot kurva ke semula: pulihkan SEMUA trim & kurva dibuang
%   (di seluruh recs), matikan mode "Semua sesar" & auto-SE. Model sesar (titik
%   /assign) tak disentuh — hanya keadaan TAMPIL kurva yang di-reset.
    h = guidata(fig);
    for r = 1:numel(h.recs)
        h.recs(r).cutManual = false; h.recs(r).cutFrame = NaN; h.recs(r).dataCut = [];
        h.recs(r).excluded  = false;
    end
    h.showAllFaults = false;
    if isfield(h,'btnShowAll') && ishghandle(h.btnShowAll), set(h.btnShowAll,'Value',0); end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    i_refreshFaultTab(fig);
    pivui.grain4Shell.callHook(fig,'onPotChanged');
    pivui.setStatus(fig,'Plot kurva di-regenerate (trim & kurva dibuang dipulihkan).');
end

function i_onToggleFaultSlip(fig)
    h = guidata(fig);
    h.showAllSlip = false;   % Slip F# tunggal -> matikan mode slip-all
    cur = 'pot'; if isfield(h,'potView') && ~isempty(h.potView), cur = h.potView; end
    if strcmp(cur,'slip'), newv = 'pot'; else, newv = 'slip'; end
    guidata(fig, h);
    pivui.grain4Shell.setPotView(fig, newv);   % set + renderPOT (slip -> slipOverride)
    i_applyPotXLim(fig);   % PASTIKAN zoom horizontal (potXWin) TETAP saat toggle view
    i_syncFaultSlipBtn(fig);
    i_refreshFaultAngleLabel(fig);
end

function i_onFaultSlipAll(fig)
%I_ONFAULTSLIPALL  TOGGLE plot bawah: net-slip SEMUA sesar bertumpuk <-> view
%   Semua Kurva standar. Klik saat aktif -> kembali ke kurva POT.
    h = guidata(fig);
    alreadyAll = isfield(h,'showAllSlip') && h.showAllSlip && ...
                 isfield(h,'potView') && strcmp(h.potView,'slip');
    if alreadyAll
        h.showAllSlip = false; guidata(fig, h);
        pivui.grain4Shell.setPotView(fig, 'pot');   % balik ke Semua Kurva standar
        pivui.setStatus(fig, 'Kembali ke view Semua Kurva.');
    else
        h.showAllSlip = true; guidata(fig, h);
        pivui.grain4Shell.setPotView(fig, 'slip');
        pivui.setStatus(fig, 'Plot bawah: net-slip SEMUA sesar bertumpuk.');
    end
    i_syncFaultSlipBtn(fig);
    i_refreshFaultAngleLabel(fig);
end

function i_syncFaultSlipBtn(fig)
    h = guidata(fig);
    allSlip = isfield(h,'showAllSlip') && h.showAllSlip;
    isSlip = isfield(h,'potView') && strcmp(h.potView,'slip');
    if isfield(h,'btnFaultSlip') && ishghandle(h.btnFaultSlip)
        set(h.btnFaultSlip,'Value',double(isSlip && ~allSlip));
        if isSlip && ~allSlip, set(h.btnFaultSlip,'String','Slip F# ✔');
        else,                  set(h.btnFaultSlip,'String','Slip F#'); end
    end
    if isfield(h,'btnSlipAll') && ishghandle(h.btnSlipAll)
        if isSlip && allSlip, set(h.btnSlipAll,'String','Slp Semua Sesar ✔');
        else,                 set(h.btnSlipAll,'String','Slip all'); end
    end
    i_syncAutoDxBtns(fig);   % grup AUTO — DX aktif hanya saat AXSLIP tampil
end

function i_syncAutoDxBtns(fig)
%I_SYNCAUTODXBTNS  Grup AUTO — DX (Auto FS-max + Clear FS-max) aktif HANYA saat
%   plot AXSLIP tampil (potView='slip'). Selain itu -> disabled (abu-abu).
    h = guidata(fig);
    onSlip = isfield(h,'potView') && strcmp(h.potView,'slip');
    en = 'off'; if onSlip, en = 'on'; end
    if isfield(h,'btnAutoFsMax')  && ishghandle(h.btnAutoFsMax),  set(h.btnAutoFsMax,'Enable',en);  end
    if isfield(h,'btnClearFsMax') && ishghandle(h.btnClearFsMax), set(h.btnClearFsMax,'Enable',en); end
end

function i_onAxslipCutStep(fig, d)
%I_ONAXSLIPCUTSTEP  Naik/turun cut-off net-slip AXSLIP (langkah 0.1; min 0).
%   Update label + redraw garis ambang (bila AXSLIP tampil). Hotkey Ctrl+Shift+↑/↓.
    h = guidata(fig);
    cur = 2.0; if isfield(h,'axslipCutoff') && isscalar(h.axslipCutoff), cur = h.axslipCutoff; end
    h.axslipCutoff = max(0, round((cur + 0.1*sign(d))*10)/10);   % kelipatan 0.1 bersih
    if isfield(h,'txtAxslipCut') && ishghandle(h.txtAxslipCut)
        set(h.txtAxslipCut,'String',sprintf('%.1f', h.axslipCutoff));
    end
    guidata(fig, h);
    i_drawAxslipCutLine(fig);   % perbarui garis ambang (no-op bila bukan view slip)
    i_setDescStatus(fig, sprintf('Cut-off net-slip AXSLIP = %.1f (px/frame).', h.axslipCutoff));
end

function i_drawAxslipCutLine(fig)
%I_DRAWAXSLIPCUTLINE  Garis horizontal ambang (cut-off) di AXSLIP saja. Dihapus
%   & digambar ulang (Tag 'axslipCutLine'). No-op bila view bukan 'slip'.
    h = guidata(fig);
    if ~(isfield(h,'axPOT') && ishghandle(h.axPOT)), return; end
    ax = h.axPOT;
    delete(findobj(ax,'Tag','axslipCutLine'));
    if ~(isfield(h,'potView') && strcmp(h.potView,'slip')), return; end
    c = 2.0; if isfield(h,'axslipCutoff') && isscalar(h.axslipCutoff), c = h.axslipCutoff; end
    xl = get(ax,'XLim'); hs = ishold(ax); hold(ax,'on');
    plot(ax, xl, [c c], '--', 'Color',[0.85 0.20 0.20], 'LineWidth',1.2, ...
        'Tag','axslipCutLine', 'HitTest','off','PickableParts','none');
    text(ax, xl(1), c, sprintf(' cut-off %.1f', c), 'Color',[0.7 0.1 0.1], ...
        'FontSize',7,'VerticalAlignment','bottom','Tag','axslipCutLine', ...
        'HitTest','off','PickableParts','none');
    if ~hs, hold(ax,'off'); end
end

function frames = i_axslipCrossFrames(ns, cutoff)
%I_AXSLIPCROSSFRAMES  Frame masuk & keluar tiap SEGMEN kurva net-slip yg berada
%   DI ATAS (>=) cut-off. Untuk tiap segmen kontigu {ns>=cutoff}: 2 frame (awal &
%   akhir segmen) -> pasangan FS-max. Mengembalikan vektor frame (genap; boleh
%   kosong). NaN diperlakukan sebagai di bawah ambang (pemutus segmen).
    frames = [];
    if isempty(ns) || ~isscalar(cutoff) || ~isfinite(cutoff), return; end
    above = isfinite(ns) & (ns >= cutoff);
    n = numel(above); k = 1;
    while k <= n
        if above(k)
            a = k;
            while k <= n && above(k), k = k + 1; end
            b = k - 1;             % segmen [a..b] semuanya >= cutoff
            frames(end+1) = a;     %#ok<AGROW>  frame masuk
            frames(end+1) = b;     %#ok<AGROW>  frame keluar
        else
            k = k + 1;
        end
    end
end

function i_onAutoFsMax(fig)
%I_ONAUTOFSMAX  Auto-assign DX FS-max pada sesar AKTIF dari cut-off net-slip.
%   Tiap segmen kurva net-slip (ns>=cutoff) -> 2 baris FS-max (frame masuk & keluar).
%   Baris FS-max lama sesar aktif DIHAPUS dulu (regenerate bersih). Hanya saat AXSLIP.
    h = guidata(fig);
    if ~(isfield(h,'potView') && strcmp(h.potView,'slip'))
        i_setDescStatus(fig, 'Auto FS-max hanya saat plot AXSLIP tampil (klik "Slip F#").'); return;
    end
    i_captureDescFromTable(fig); h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1
        i_setDescStatus(fig, 'Pilih sesar (F#) dulu untuk auto FS-max.'); return;
    end
    fNum = i_uiNumStr(f);
    if isempty(fNum) || strcmp(fNum,'—')
        i_setDescStatus(fig, 'Sesar aktif belum bernomor F#.'); return;
    end
    fNum = ['F' fNum];
    [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    if ~(okHW && okFW) || isempty(ns) || ~any(isfinite(ns))
        i_setDescStatus(fig, 'Net-slip sesar aktif belum lengkap (butuh HW & FW).'); return;
    end
    cutoff = 2.0; if isfield(h,'axslipCutoff'), cutoff = h.axslipCutoff; end
    fr = i_axslipCrossFrames(ns, cutoff);
    if isempty(fr)
        i_setDescStatus(fig, sprintf('Tak ada potongan net-slip di atas cut-off %.1f (F# %s).', cutoff, fNum)); return;
    end
    % Regenerate bersih: buang FS-max lama F# aktif dulu, lalu tambah pasangan baru.
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    keep = {};
    for k = 1:numel(rows)
        isFsMax = strcmpi(strtrim(char(rows{k}.poi)),'ACT-FSR');
        sameF   = strcmp(strtrim(rows{k}.fNum), strtrim(fNum));
        if isFsMax && sameF, continue; end   % buang FS-max lama sesar ini
        keep{end+1} = rows{k}; %#ok<AGROW>
    end
    rows = keep;
    % Tambah 1 baris FS-max per frame potongan (tiap frame unik; hindari duplikat
    % (F#,frame) yg sudah ada -> ganti POI jadi FS-max supaya aturan 1 DX/frame utuh).
    added = 0;
    for j = 1:numel(fr)
        frame = round(fr(j));
        ex = i_findDescRowIdx(rows, fNum, frame);
        if ex > 0
            r = rows{ex}; r.poi = 'ACT-FSR'; rows{ex} = r;   % pakai baris yg ada
        else
            r = pivcore.io.grain4Desc.rowStruct(h.activePsgId, fNum, frame, 'ACT-FSR', NaN, '1', '', '', '', NaN);
            rows{end+1} = r; %#ok<AGROW>
            added = added + 1;
        end
    end
    rows = i_sortDescRowsByFrame(rows);
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    guidata(fig, h);
    i_refreshDescTable(fig);
    i_renderPotKeepZoom(fig);   % fill FS-max→FS-max + garis DX ikut muncul (zoom tetap)
    i_setDescStatus(fig, sprintf('Auto FS-max %s: %d segmen -> %d FS-max (cut-off %.1f).', ...
        fNum, numel(fr)/2, numel(fr), cutoff));
end

function i_onClearFsMax(fig)
%I_ONCLEARFSMAX  Hapus SEMUA baris DX FS-max pada sesar AKTIF (garis PSG aktif).
    h = guidata(fig);
    if ~(isfield(h,'potView') && strcmp(h.potView,'slip'))
        i_setDescStatus(fig, 'Clear FS-max hanya saat plot AXSLIP tampil (klik "Slip F#").'); return;
    end
    i_captureDescFromTable(fig); h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, i_setDescStatus(fig, 'Pilih sesar (F#) dulu.'); return; end
    fNum = i_uiNumStr(f);
    if isempty(fNum) || strcmp(fNum,'—'), i_setDescStatus(fig, 'Sesar aktif belum bernomor F#.'); return; end
    fNum = ['F' fNum];
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    keep = {}; nDel = 0;
    for k = 1:numel(rows)
        isFsMax = strcmpi(strtrim(char(rows{k}.poi)),'ACT-FSR');
        sameF   = strcmp(strtrim(rows{k}.fNum), strtrim(fNum));
        if isFsMax && sameF, nDel = nDel + 1; continue; end
        keep{end+1} = rows{k}; %#ok<AGROW>
    end
    if nDel == 0, i_setDescStatus(fig, sprintf('Tak ada FS-max pada %s.', fNum)); return; end
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, keep);
    h.descSelRow = [];
    guidata(fig, h);
    i_refreshDescTable(fig);
    i_renderPotKeepZoom(fig);
    i_setDescStatus(fig, sprintf('Hapus %d FS-max pada %s.', nDel, fNum));
end

% --- Zona sesar: alpha transparansi + palet warna --------------------
function i_onZoneAlpha(fig, d)
%I_ONZONEALPHA  Naik-turun transparansi fill zona/area sesar (step 0.05, 0.05..0.9).
    h = guidata(fig);
    h.zoneAlpha = max(0.05, min(0.95, h.zoneAlpha + 0.05*d));
    if isfield(h,'txtZoneAlpha') && ishghandle(h.txtZoneAlpha)
        set(h.txtZoneAlpha,'String',sprintf('%.2f',h.zoneAlpha));
    end
    if isfield(h,'edZoneAlpha') && ishghandle(h.edZoneAlpha)
        set(h.edZoneAlpha,'String',sprintf('%.2f',h.zoneAlpha));   % sinkron kotak edit Tab ①
    end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    pivui.setStatus(fig, sprintf('Alpha zona sesar = %.2f.', h.zoneAlpha));
end

function i_onZonePalette(fig)
%I_ONZONEPALETTE  Ganti koleksi warna zona sesar: lembut (pastel) / ngejreng.
    h = guidata(fig);
    v = 1; if isfield(h,'popZonePalette') && ishghandle(h.popZonePalette), v = get(h.popZonePalette,'Value'); end
    if v == 2, h.zonePalette = 'ngejreng'; else, h.zonePalette = 'lembut'; end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    pivui.setStatus(fig, sprintf('Palet zona sesar: %s.', h.zonePalette));
end

% --- Ukuran titik POI · garis PSG · Moving Average -------------------
function i_onPoiSize(fig, d)
    h = guidata(fig);
    h.poiMarkerScale = max(0.3, min(3.0, h.poiMarkerScale + 0.15*d));
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);   % titik POI digambar ulang lewat decoratePOT
    pivui.setStatus(fig, sprintf('Ukuran titik POI: %.0f%%.', 100*h.poiMarkerScale));
end

function ms = i_markerSize(h)
%I_MARKERSIZE  Ukuran titik indikator (HW/FW axMain + seleksi kurva axPOT).
    ms = 4;
    if isstruct(h) && isfield(h,'indMarkerSize') && isscalar(h.indMarkerSize) && h.indMarkerSize>0
        ms = h.indMarkerSize;
    end
end

function i_onIndMarker(fig, d)
%I_ONINDMARKER  Spinner ▲/▼ ukuran titik indikator HW/FW + seleksi kurva.
    h = guidata(fig);
    h.indMarkerSize = max(2, min(14, i_markerSize(h) + d));
    guidata(fig, h);
    % Segarkan penanda: seleksi kurva (axPOT) + titik HW/FW garis PSG (axMain).
    if ~isempty(h.recs), pivui.grain4Shell.renderPOT(fig); end
    i_drawFaultPsgMarker(fig);
    pivui.setStatus(fig, sprintf('Ukuran titik indikator: %d.', h.indMarkerSize));
end

function i_onPsgLW(fig, d)
    h = guidata(fig);
    h.psgLineWidth = max(0.25, min(8, h.psgLineWidth + 0.25*d));
    guidata(fig, h);
    i_reapplyPsgStyle(fig);
    pivui.setStatus(fig, sprintf('Tebal garis PSG: %.2f.', h.psgLineWidth));
end

function i_onPsgMS(fig, d)
    h = guidata(fig);
    h.psgMarkerSize = max(1, min(24, h.psgMarkerSize + d));
    guidata(fig, h);
    i_reapplyPsgStyle(fig);
    pivui.setStatus(fig, sprintf('Ukuran titik garis PSG: %d.', h.psgMarkerSize));
end

function i_reapplyPsgStyle(fig)
%I_REAPPLYPSGSTYLE  Terapkan tebal/ukuran-titik garis PSG ke ROI aktif tanpa
%   membangun ulang (real-time).
    h = guidata(fig);
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi)
        try
            h.roi.LineWidth  = h.psgLineWidth;
            h.roi.MarkerSize = h.psgMarkerSize;
        catch
        end
    end
end

function i_onToggleMA(fig)
    h = guidata(fig);
    h.maOn = isfield(h,'chkMA') && ishghandle(h.chkMA) && get(h.chkMA,'Value')==1;
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Moving Average: %s (window %d).', ...
        pivui.grain5Fmt.tern(h.maOn,'ON','OFF'), h.maWin));
end

function w = i_descMaWin(h)
%I_DESCMAWIN  Window MA terkini (>=1). 1 = OFF.
    w = 1;
    if isfield(h,'maWin') && isscalar(h.maWin) && isfinite(h.maWin) && h.maWin>=1
        w = round(h.maWin);
    end
end

function i_onDescMAStep(fig, d)
%I_ONDESCMASTEP  Spinner MA (1 = OFF; 2,3,4,..). Set maOn = (window>1) supaya
%   hook curveTransform (i_maApply) aktif hanya saat window>1.
    h = guidata(fig);
    w = max(1, min(99, i_descMaWin(h) + d));
    h.maWin = w; h.maOn = (w > 1);
    guidata(fig, h);
    if isfield(h,'txtDescMA') && ishghandle(h.txtDescMA), set(h.txtDescMA,'String',sprintf('%d', w)); end
    pivui.grain4Shell.renderPOT(fig);
    i_refreshFaultTab(fig);
    if w > 1
        pivui.setStatus(fig, sprintf('Moving Average: window %d.', w));
    else
        pivui.setStatus(fig, 'Moving Average: OFF (window 1).');
    end
end

% =====================================================================
% Zoom HORIZONTAL axPOT (eksplorasi samping) + rata-kiri ke START saat seleksi F
% =====================================================================
function i_onPotXWin(fig, dir)
%I_ONPOTXWIN  Cycle lebar jendela X axPOT dalam PERSEN total frame, langkah 5%:
%   100% -> 95% -> 90% -> ... (dir<0 persempit) dan sebaliknya (dir>0 perlebar).
%   Batas bawah 5% (min 2 frame). Persen disimpan di h.potXPct (5..100), lalu
%   potXWin (frame) diturunkan. 100% = penuh (potXWin=0). Berlaku SAMA utk AXSLIP
%   (satu sumber X-window: i_applyPotXLim). Disimpan ke progress (viewSettings).
    h = guidata(fig);
    nF = max(h.nF, 2);
    pct = 100;
    if isfield(h,'potXPct') && isscalar(h.potXPct) && isfinite(h.potXPct) && h.potXPct>0
        pct = h.potXPct;
    elseif isfield(h,'potXWin') && isscalar(h.potXWin) && isfinite(h.potXWin) && h.potXWin>0
        pct = max(5, min(100, round(100*h.potXWin/nF/5)*5));   % turunkan dari potXWin lama
    end
    % snap ke kelipatan 5 lalu geser 1 langkah (dir<0 = persempit -> pct turun).
    pct = round(pct/5)*5;
    if dir < 0, pct = pct - 5; else, pct = pct + 5; end
    pct = max(5, min(100, pct));
    h.potXPct = pct;
    if pct >= 100, h.potXWin = 0;                 % penuh
    else, h.potXWin = max(2, round(pct/100*nF)); end
    if ~isfinite(h.potXCenter), h.potXCenter = round(h.frame); end
    guidata(fig, h);
    i_applyPotXLim(fig);
    if h.potXWin<=0, pivui.setStatus(fig,'axPOT/AXSLIP: tampil penuh (100% frame).');
    else, pivui.setStatus(fig, sprintf('axPOT/AXSLIP: jendela %d%% (%d frame).', pct, h.potXWin)); end
end

function i_onPotXPan(fig, dir)
%I_ONPOTXPAN  Geser jendela X axPOT/AXSLIP ke KIRI(-1)/KANAN(+1) sebesar 10 FRAME.
    h = guidata(fig);
    nF = max(h.nF, 2);
    w = h.potXWin; if ~(isscalar(w) && isfinite(w) && w>0), w = nF; end
    if w >= nF, pivui.setStatus(fig,'axPOT penuh — persempit dulu (⊞) untuk geser.'); return; end
    c = h.potXCenter; if ~isfinite(c), c = round(h.frame); end
    c = c + dir*10;   % geser 10 frame per klik
    c = max(1, min(nF, c));
    h.potXCenter = c; guidata(fig, h);
    i_applyPotXLim(fig);
    pivui.setStatus(fig, sprintf('axPOT/AXSLIP: geser %d frame %s.', 10, pivui.grain5Fmt.tern(dir<0,'ke kiri','ke kanan')));
end

function i_onPotXFull(fig)
%I_ONPOTXFULL  Kembali ke tampilan penuh axPOT/AXSLIP (100%).
    h = guidata(fig);
    h.potXWin = 0; h.potXCenter = NaN; h.potXPct = 100; guidata(fig, h);
    i_applyPotXLim(fig);
    pivui.setStatus(fig,'axPOT/AXSLIP: tampilan penuh (100%).');
end

function i_renderPotKeepZoom(fig)
%I_RENDERPOTKEEPZOOM  renderPOT TAPI pertahankan zoom axPOT apa pun sumbernya
%   (kotak/lock, jendela potXWin, atau geser mouse). Tangkap XLim/YLim SEBELUM
%   render, lalu kembalikan SESUDAH — supaya "tambah/hapus baris deskripsi TAK
%   mereset zoom". Zoom tetap terkunci sampai user geser/ubah sendiri.
%   Bila view SUDAH dikunci (viewLock) renderPOT sudah menghormatinya; helper ini
%   hanya menambah proteksi untuk zoom TAK-terkunci (mis. scroll/pan mouse).
    h = guidata(fig);
    xl = []; yl = [];
    if isfield(h,'axPOT') && ishghandle(h.axPOT)
        try, xl = get(h.axPOT,'XLim'); yl = get(h.axPOT,'YLim'); catch, end
    end
    try, pivui.grain4Shell.renderPOT(fig); catch, end
    h = guidata(fig);
    if ~(isfield(h,'axPOT') && ishghandle(h.axPOT)), return; end
    % Bila view terkunci -> renderPOT sudah set limit beku; hormati itu.
    if pivui.grain4Shell.viewIsLocked(h), i_applyPotXLim(fig); return; end
    % Bila jendela horizontal aktif -> pakai itu (X), tapi jaga Y hasil tangkapan.
    if ~isempty(xl) && numel(xl)==2 && all(isfinite(xl))
        try, set(h.axPOT,'XLim',xl); catch, end
    end
    if ~isempty(yl) && numel(yl)==2 && all(isfinite(yl))
        try, set(h.axPOT,'YLim',yl); catch, end
    end
    i_applyPotXLim(fig);   % kalau ada jendela potXWin, timpa X sesuai jendela
end

function i_applyPotXLim(fig)
%I_APPLYPOTXLIM  Terapkan XLim axPOT sesuai jendela potXWin/potXCenter. potXWin<=0
%   -> auto (penuh). Dipanggil setelah renderPOT (afterRenderMain? tidak — panggil
%   langsung + di hook onFrameChanged agar tetap saat ganti frame).
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
    ax = h.axPOT; nF = max(h.nF, 2);
    w = h.potXWin;
    if ~(isscalar(w) && isfinite(w) && w>0) || w >= nF
        try, set(ax,'XLimMode','auto'); catch, end
        return;
    end
    c = h.potXCenter; if ~isfinite(c), c = round(h.frame); end
    lo = round(c - w/2); hi = lo + w - 1;
    if lo < 1, lo = 1; hi = w; end
    if hi > nF, hi = nF; lo = nF - w + 1; end
    lo = max(1, lo);
    try, set(ax, 'XLim', [lo hi]); catch, end
end

function i_potXLeftAlign(fig, f)
%I_POTXLEFTALIGN  Saat seleksi sesar F: bila jendela X aktif (potXWin>0), RATA-KIRI
%   plot ke START sesar (skala horizontal DIJAGA = potXWin). Bila START NaN, pusat
%   di frame live. Tak mengubah lebar jendela.
    h = guidata(fig);
    if ~(isfield(h,'potXWin') && isscalar(h.potXWin) && h.potXWin>0), return; end
    w = h.potXWin; nF = max(h.nF,2);
    s = NaN; if isstruct(f) && isfield(f,'startF'), s = f.startF; end
    if ~(isscalar(s) && isfinite(s)), s = h.frame; end
    s = max(1, min(nF, round(s)));
    % rata-KIRI: START di tepi kiri jendela -> pusat = START + w/2.
    h.potXCenter = s + round(w/2); guidata(fig, h);
    i_applyPotXLim(fig);
end

function i_onMAStep(fig, d)
    h = guidata(fig);
    h.maWin = max(1, min(99, h.maWin + d));
    if isfield(h,'txtMAwin') && ishghandle(h.txtMAwin), set(h.txtMAwin,'String',sprintf('w=%d',h.maWin)); end
    guidata(fig, h);
    if h.maOn, pivui.grain4Shell.renderPOT(fig); i_refreshFaultTab(fig); end
    pivui.setStatus(fig, sprintf('Window Moving Average: %d.', h.maWin));
end

function yv = i_maApply(fig, yv)
%I_MAAPPLY  Hook curveTransform: bila MA aktif, haluskan yv dgn moving-average
%   window h.maWin (NaN-aware, tepi centered via movmean 'omitnan'). No-op OFF.
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    if ~(isstruct(h) && isfield(h,'maOn') && h.maOn), return; end
    w = 3; if isfield(h,'maWin') && isscalar(h.maWin) && h.maWin>=1, w = round(h.maWin); end
    if w <= 1, return; end
    try
        yv = movmean(yv, w, 'omitnan', 'Endpoints','shrink');
    catch
    end
end

% --- Tampilkan semua sesar + label ----------------------------------
function i_onToggleShowAll(fig)
    h = guidata(fig);
    h.showAllFaults = isfield(h,'btnShowAll') && ishghandle(h.btnShowAll) && get(h.btnShowAll,'Value')==1;
    if h.showAllFaults
        h.showAllSlip = false;
        if isfield(h,'potView') && strcmp(h.potView,'slip')
            pivui.grain4Shell.setPotView(fig,'pot'); h = guidata(fig);
        end
    end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    i_syncFaultSlipBtn(fig);
    pivui.setStatus(fig, sprintf('Tampilan "Semua sesar": %s.', pivui.grain5Fmt.tern(h.showAllFaults,'ON','OFF')));
end

% --- Sembunyikan/tampilkan SEMUA sesar teridentifikasi (toggle 👁/🚫) --------
function i_onToggleHideFaults(fig)
    h = guidata(fig);
    h.hideAllFaults = isfield(h,'btnHideFaults') && ishghandle(h.btnHideFaults) && get(h.btnHideFaults,'Value')==1;
    if isfield(h,'btnHideFaults') && ishghandle(h.btnHideFaults)
        if h.hideAllFaults, set(h.btnHideFaults,'String','🚫 Sesar');
        else,               set(h.btnHideFaults,'String','👁 Sesar'); end
    end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    pivui.setStatus(fig, sprintf('Semua sesar: %s.', ...
        pivui.grain5Fmt.tern(h.hideAllFaults,'DISEMBUNYIKAN','ditampilkan')));
end

function i_onToggleFaultLabel(fig)
    h = guidata(fig);
    h.faultLabelOn = isfield(h,'chkFaultLabel') && ishghandle(h.chkFaultLabel) && get(h.chkFaultLabel,'Value')==1;
    guidata(fig, h);
    if h.showAllFaults, pivui.grain4Shell.renderPOT(fig); end
end

function i_onFaultLabelPos(fig)
    h = guidata(fig);
    v = 1; if isfield(h,'popFaultLabelPos') && ishghandle(h.popFaultLabelPos), v = get(h.popFaultLabelPos,'Value'); end
    if v == 2, h.faultLabelPos = 'center'; else, h.faultLabelPos = 'top'; end
    guidata(fig, h);
    if h.showAllFaults, pivui.grain4Shell.renderPOT(fig); end
end

function i_onFaultSign(fig)
    h = guidata(fig);
    v = 1; if isfield(h,'popFaultSign') && ishghandle(h.popFaultSign), v = get(h.popFaultSign,'Value'); end
    opts = {'signed','absolute'}; h.signConv = opts{max(1,min(v,2))};
    if isfield(h,'popSign') && ishghandle(h.popSign), set(h.popSign,'Value',v); end
    guidata(fig, h);
    i_refreshFaultTab(fig);
end


% --- Refresh / render sesar ------------------------------------------
function i_refreshFaultTab(fig)
    i_refreshFaultTable(fig);
    h = guidata(fig);
    % SELALU MENYELEKSI: bila belum ada seleksi valid & ADA sesar -> pilih baris
    % TERISI pertama (slot kosong dilewati). Belum ada sesar -> '' (tak menyeleksi).
    reSel = false;
    if isempty(h.activeFaultId) || ~any(strcmp(h.activeFaultId, h.faultIds))
        first = ''; nz = find(~cellfun(@isempty, h.faultIds), 1);
        if ~isempty(nz), first = h.faultIds{nz}; end
        h.activeFaultId = first;
        guidata(fig, h); reSel = true;
    end
    % Baris terpilih = POSISI activeFaultId di h.faultIds (urutan tampil tabel),
    % BUKAN idx penyimpanan (agar SF terpilih pd baris yang benar).
    row = find(strcmp(h.activeFaultId, h.faultIds), 1);
    if ~isempty(row)
        if isfield(h,'tblFault') && ishghandle(h.tblFault), try, h.tblFault.Selection = row; catch, end, end
    end
    % Bila seleksi baru saja di-default-kan, i_refreshFaultTable tadi sudah jalan
    % dgn activeFaultId LAMA (kosong) -> sorotan hijau belum terpasang. Style ulang.
    if reSel, i_styleFaultTable(fig); end
    i_syncFaultSlipBtn(fig);
    i_syncFaultEditBtn(fig);        % selaraskan tombol Edit no. dgn h.faultEditMode
    if ~isempty(h.recs) && i_faultVisible(h), pivui.grain4Shell.renderPOT(fig); end
    i_refreshFaultAngleLabel(fig);
end

function i_refreshFaultTable(fig)
%I_REFRESHFAULTTABLE  Isi tabel sesar dari model "slot spreadsheet":
%   sumber urutan = h.faultSlots (id per-baris; '' = slot kosong). Baris slot X
%   TETAP di posisi X (tak reorder). Kolom F#/SF = ANGKA (via idToNumbers).
    h = guidata(fig);
    slots = i_ensureSlots(h);
    n = numel(slots);
    data = repmat({''}, n, 14); ids = cell(1, n); subIds = cell(1, n);
    poiFull = false(1, n); faultOn = true(1, n);
    lenCntCol = repmat({'0'}, n, 1);   % jumlah DX yg SUDAH punya bidang sesar (per F#)
    ang0Col = repmat({'—'}, n, 1);     % θ0 = sudut bidang sesar AWAL (DX frame terkecil)
    ang1Col = repmat({'—'}, n, 1);     % θ1 = sudut bidang sesar AKHIR (DX frame terbesar)
    meanAngCol = repmat({'—'}, n, 1);  % θ̄ = sudut rata-rata semua DX terukur (per F#)
    tp0Col = repmat({'—'}, n, 1);      % Tp0 = taper AWAL (DX ber-taper frame terkecil)
    tp1Col = repmat({'—'}, n, 1);      % Tp1 = taper AKHIR (DX ber-taper frame terbesar)
    tpDCol = repmat({'—'}, n, 1);      % ΔTp = Tp1 − Tp0 (change kemiringan topografi)
    for k = 1:n
        id = slots{k}; ids{k} = ''; subIds{k} = '';
        if ~i_slotHasRecord(id), continue; end         % baris kosong -> sel kosong
        [f, ix] = pivcore.io.grain5Faults.findFault(h.fdoc, id);
        if ix < 1, slots{k} = ''; continue; end        % record hilang -> kosongkan slot
        ids{k} = f.id;
        isSub = ~isempty(pivui.grain5Model.parentId(f));
        [ns, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        area = NaN;
        if okHW && okFW && ~isempty(ns), area = pivcore.pot.netslip.area(ns, f.startF, f.endF); end
        % Kolom F# = NOMOR TAMPIL sesar (f.uiNum; boleh duplikat). Kolom DX =
        % JUMLAH baris deskripsi (DX) utk F# ini di garis PSG aktif (default 0).
        fCol = ''; sCol = '0';
        uN = pivui.grain5Model.faultUiNum(f);
        if ~isempty(uN), fCol = sprintf('%d', round(uN)); sCol = sprintf('%d', i_dxCountForFault(h, uN)); end
        % HW/FW = NOMOR KURVA (bukan posPx).
        hwNum = pivui.grain5Fmt.curveNumTag(h, hwRow, f.hwPosPx);
        if isSub, fwNum = '·'; else, fwNum = pivui.grain5Fmt.curveNumTag(h, fwRow, f.fwPosPx); end
        % Kolom ST/EN = SELISIH |HW−FW| pada frame START/END (2 desimal).
        stVal = pivui.grain5Fmt.nsAtFrame(ns, f.startF);
        enVal = pivui.grain5Fmt.nsAtFrame(ns, f.endF);
        % Len# = JUMLAH baris DESC (DX) F# ini yg SUDAH punya bidang sesar tergambar
        % (vertices >= 2). Geometri detail (sudut/panjang/growth) kini PER-DX di
        % tabel DESKRIPSI. angStr tak lagi kolom sesar (dibuang).
        angStr = '—';
        lenCntCol{k} = sprintf('%d', i_dxGeomCountForFault(h, uN));
        % Sudut bidang sesar: AWAL (θ0) / AKHIR (θ1) / RATA-RATA (θ̄), per-F#.
        [a0, a1, aMean] = i_faultStartEndMeanAngle(h, uN);
        if isscalar(a0)    && isfinite(a0),    ang0Col{k}    = sprintf('%.1f', a0);    end
        if isscalar(a1)    && isfinite(a1),    ang1Col{k}    = sprintf('%.1f', a1);    end
        if isscalar(aMean) && isfinite(aMean), meanAngCol{k} = sprintf('%.1f', aMean); end
        % TAPER awal/akhir/change per-F# (DX ber-taper; urut frame).
        [tp0, tp1, tpD] = i_taperStartEndChange(h, uN);
        if isfinite(tp0), tp0Col{k} = sprintf('%.1f', tp0); end
        if isfinite(tp1), tp1Col{k} = sprintf('%.1f', tp1); end
        if isfinite(tpD), tpDCol{k} = sprintf('%.1f', tpD); end
        % CHECKLIST (✓) definisi baru: HW + FW + START + END (bukan NUC/FSR).
        full = pivui.grain5Model.faultChecklistDone(f);
        poiFull(k) = full;
        chkCol = ''; if full, chkCol = '✓'; end
        % Kolom 1 ⏻ = ON/OFF (hijau ✓ / merah ✗; warna via i_styleFaultTable).
        on = pivui.grain5Model.faultEnabled(f); faultOn(k) = on;
        onCol = '✓'; if ~on, onCol = '✗'; end
        nucTCol = ''; if isfield(f,'nucT'), nucTCol = pivui.grain5Fmt.numDash(f.nucT); end
        fsrTCol = ''; if isfield(f,'fsrT'), fsrTCol = pivui.grain5Fmt.numDash(f.fsrT); end
        data(k,:) = {onCol, chkCol, fCol, sCol, hwNum, fwNum, ...
                    pivui.grain5Fmt.numDash(f.nuc), nucTCol, pivui.grain5Fmt.numDash(f.fsr), fsrTCol, ...
                    pivui.grain5Fmt.num2(stVal), pivui.grain5Fmt.num2(enVal), pivui.grain5Fmt.num(area), angStr};
        subIds{k} = pivui.grain5Model.parentId(f);
    end
    % Tabel menampilkan 3 kolom: F#(idx3) · DX(idx4) · Len# (jumlah DX ber-bidang
    % sesar). Geometri per-DX pindah ke tabel DESKRIPSI.
    if isfield(h,'tblFault') && ishghandle(h.tblFault)
        if isempty(data), set(h.tblFault,'Data',cell(0,9));
        else,             set(h.tblFault,'Data',[data(:,[3 4]) lenCntCol ang0Col ang1Col meanAngCol tp0Col tp1Col tpDCol]); end
    end
    h.faultSlots = slots; h.faultIds = ids; h.subIds = subIds;
    h.faultPoiFull = poiFull; h.faultOn = faultOn;
    guidata(fig, h);
    i_styleFaultTable(fig);   % ⏻ hijau/merah + ✓ biru + baris aktif hijau
end

function i_styleFaultTable(fig)
%I_STYLEFAULTTABLE  Style tabel sesar (3 kolom tampil: F#/DX/Len#). Baris sesar
%   AKTIF -> latar HIJAU muda. Sel MERAH: DX<4 (kol 2) + Len#=0 (kol 3, belum ada
%   bidang sesar tergambar). uistyle/addStyle (uitable R2025b).
    h = guidata(fig);
    if ~(isfield(h,'tblFault') && ishghandle(h.tblFault)), return; end
    try, removeStyle(h.tblFault); catch, end
    if isempty(h.faultIds), return; end
    % Sel MERAH per-baris: kol 2 (DX) bila DX<4 · kol 3 (Len#) bila Len#=0.
    redCols = cell(1, numel(h.faultIds));   % kolom yg merah per baris (utk skip hijau)
    try
        D = get(h.tblFault,'Data');
        if iscell(D) && size(D,2) >= 3
            for i = 1:size(D,1)
                rc = [];
                dxv = str2double(i_cellStr(D{i,2}));
                if isfinite(dxv) && dxv < 4
                    rc(end+1) = 2; %#ok<AGROW>
                    addStyle(h.tblFault, uistyle('BackgroundColor',[1.0 0.80 0.80], ...
                        'FontColor',[0.6 0 0],'FontWeight','bold'), 'cell', [i 2]);
                end
                lnv = str2double(i_cellStr(D{i,3}));
                if isfinite(lnv) && lnv == 0
                    rc(end+1) = 3; %#ok<AGROW>
                    addStyle(h.tblFault, uistyle('BackgroundColor',[1.0 0.80 0.80], ...
                        'FontColor',[0.6 0 0],'FontWeight','bold'), 'cell', [i 3]);
                end
                redCols{i} = rc;
            end
        end
    catch
    end
    % Baris aktif hijau muda (kolom yg SUDAH merah TAK ditimpa hijau).
    if isfield(h,'activeFaultId') && ~isempty(h.activeFaultId)
        row = find(strcmp(h.activeFaultId, h.faultIds), 1);
        if ~isempty(row)
            cols = setdiff((1:9).', reshape(redCols{min(row,numel(redCols))},[],1));
            try
                addStyle(h.tblFault, uistyle('BackgroundColor',[0.72 0.93 0.72], ...
                    'FontWeight','bold'), 'cell', [repmat(row,numel(cols),1) cols]);
            catch
            end
        end
    end
end



function i_refreshFaultAngleLabel(fig)
%I_REFRESHFAULTANGLELABEL  (Fase 4c) Segarkan label sudut sesar aktif di Tab ②
%   (h.txtFaultAngle) — menggantikan panel "Ringkasan sesar aktif" yang dibuang.
%   Juga reset h.txtFaultSel (Tab ①) ke '—' saat tak ada sesar aktif (meniru
%   perilaku lama i_refreshFaultSummary supaya UI konsisten).
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1
        if isfield(h,'txtFaultAngle') && ishghandle(h.txtFaultAngle)
            set(h.txtFaultAngle,'String','sudut sesar aktif: — °  (belum ada sesar aktif)');
        end
        if isfield(h,'txtFaultSel') && ishghandle(h.txtFaultSel)
            set(h.txtFaultSel,'String','kurva terpilih: —');
        end
        return;
    end
    if isfield(h,'txtFaultAngle') && ishghandle(h.txtFaultAngle)
        det = i_detachmentDoc(h);
        detStr = 'detachment belum di-set (sudut absolut)';
        if pivcore.pot.faultAngle.isValidDetachment(det), detStr = 'relatif detachment'; end
        ang = NaN; if isfield(f,'angleDeg'), ang = f.angleDeg; end
        set(h.txtFaultAngle,'String', sprintf('sudut sesar %s: %s °  (%s)', ...
            f.id, pivui.grain5Fmt.num2(ang), detStr));
    end
end

function det = i_detachmentDoc(h)
%I_DETACHMENTDOC  Ambil struct detachment dari h.fdoc (default kosong).
    det = pivcore.pot.faultAngle.emptyDetachment();
    if isstruct(h.fdoc) && isfield(h.fdoc,'detachment') && isstruct(h.fdoc.detachment)
        det = h.fdoc.detachment;
    end
end

function cmap = i_faultColorMap(h)
%I_FAULTCOLORMAP  Peta warna sesar utama (index kemunculan -> warna zona),
%   konsisten dgn i_drawAllFaults. Map: id sesar utama -> warna (palet aktif).
    cmap = containers.Map('KeyType','char','ValueType','any');
    if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults')), return; end
    pastel = pivui.grain5Palette.zonePalette(h); ci = 0;
    Fa = i_activeFaults(h);   % scoping multi-PSG: warna hanya utk sesar garis aktif
    for k = 1:numel(Fa)
        f = Fa{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        ci = ci + 1; cmap(f.id) = pastel{mod(ci-1,numel(pastel))+1};
    end
end

function i_augmentCurveTable(fig)
%I_AUGMENTCURVETABLE  Tambah kolom ke-5 "ΔΔLuas" ke tabel kurva (kolom kiri) di
%   SAMPING ΔLuas: ΔΔ = ΔLuas(baris ini) − ΔLuas(baris atasnya) = "delta dari
%   delta luas" (bawah dikurangi atas). Shell fillTable men-set 4 kolom; kita
%   pasca-proses jadi 5 tiap render (mode 'curve'). No-op bila bukan mode curve.
    h = guidata(fig);
    if ~(isfield(h,'tbl') && ishghandle(h.tbl)), return; end
    if ~(isfield(h,'leftMode') && strcmp(h.leftMode,'curve')), return; end
    D = get(h.tbl,'Data');
    if isempty(D) || size(D,2) < 4, return; end
    n = size(D,1);
    % Ambil ΔLuas (kolom 4) sbg angka (string '%.0f' dari shell).
    dA = nan(n,1);
    for i = 1:n
        v = str2double(D{i,4});
        if isfinite(v), dA(i) = v; end
    end
    % ΔΔLuas baris-i = ΔLuas(i) − ΔLuas(i-1). Baris pertama '—'.
    out = D;
    if size(out,2) < 5, out(:,5) = {''}; end
    for i = 1:n
        if i == 1 || ~isfinite(dA(i)) || ~isfinite(dA(i-1))
            out{i,5} = '—';
        else
            out{i,5} = sprintf('%.0f', dA(i) - dA(i-1));
        end
    end
    set(h.tbl, 'ColumnName', {'#','posPx','Label','ΔLuas','ΔΔLuas'}, ...
        'ColumnWidth', {30 42 54 50 52}, 'Data', out);
end

function i_colorCurveTable(fig)
%I_COLORCURVETABLE  Warnai baris tabel KURVA (kolom kiri, mode 'curve') menurut
%   sesar AKTIF: baris HW -> latar merah muda, FW -> biru muda; kurva DI ANTARA
%   HW & FW -> latar warna fill pastel sesar (seakan penanda sesar di tabel).
%   Pakai uistyle/addStyle (uitable app di R2025b). No-op bila bukan mode curve.
    h = guidata(fig);
    if ~(isfield(h,'tbl') && ishghandle(h.tbl)), return; end
    if ~(isfield(h,'leftMode') && strcmp(h.leftMode,'curve')), return; end
    i_augmentCurveTable(fig);   % +kolom ΔΔLuas (SEBELUM style; ubah Data/kolom)
    try, removeStyle(h.tbl); catch, end
    if isempty(h.recs), return; end
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, return; end
    % HW & FW row = kurva yang membentuk net-slip sesar/SF aktif (SF: FW =
    % pasangan bawahnya). Konsisten dgn garis tebal di axPOT (HW merah / FW biru).
    fm = pivui.grain5Model.mainFaultOf(h, f);
    [~, hwRow, fwRow] = pivui.grain5Model.faultNetslip(h, f);
    hwCol = [1.00 0.82 0.82];   % HW: merah muda (utama & SF sama)
    fwCol = [0.82 0.88 1.00];   % FW: biru muda
    cmap = i_faultColorMap(h);
    fillCol = [0.90 0.90 0.90];
    if cmap.isKey(fm.id), fillCol = cmap(fm.id); end
    fillCol = 0.55*fillCol + 0.45*[1 1 1];   % lembutkan utk latar tabel
    % Kurva DI ANTARA HW & FW (indeks baris record antara hwRow..fwRow).
    if ~isempty(hwRow) && ~isempty(fwRow)
        lo = min(hwRow,fwRow); hi = max(hwRow,fwRow);
        inner = (lo+1):(hi-1);
        if ~isempty(inner)
            try, addStyle(h.tbl, uistyle('BackgroundColor',fillCol), 'row', inner); catch, end
        end
    end
    if ~isempty(hwRow)
        try, addStyle(h.tbl, uistyle('BackgroundColor',hwCol,'FontColor',[0.5 0 0],'FontWeight','bold'), 'row', hwRow); catch, end
    end
    if ~isempty(fwRow)
        try, addStyle(h.tbl, uistyle('BackgroundColor',fwCol,'FontColor',[0 0 0.5],'FontWeight','bold'), 'row', fwRow); catch, end
    end
end

function i_decorateFaultPOT(fig)
%I_DECORATEFAULTPOT  Di axPOT (view kurva): mode normal = sorot HW/FW sesar aktif
%   + titik POI (TANPA label HW/FW — sudah jelas merah=HW biru=FW). mode "Semua
%   sesar" = hanya kurva sesar teridentifikasi + fill pastel + label F#.
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax) || isempty(h.recs), return; end
    i_colorCurveTable(fig);   % warnai baris tabel kurva menurut sesar aktif
    try, delete(findall(ax,'Tag','nsPoint')); catch, end
    try, delete(findall(ax,'Tag','faultHL')); catch, end
    try, delete(findall(ax,'Tag','faultFill')); catch, end
    try, delete(findall(ax,'Tag','poiVline')); catch, end   % garis vertikal POI (TAB ⑨)
    if isfield(h,'potView') && strcmp(h.potView,'slip'), return; end   % slip view dirender i_renderFaultSlip
    if isfield(h,'hideAllFaults') && h.hideAllFaults, return; end       % toggle 🚫: semua sesar disembunyikan
    if isfield(h,'showAllFaults') && h.showAllFaults
        i_drawAllFaults(fig); return;
    end
    hs = ishold(ax); hold(ax,'on');
    % PERSISTEN: untuk SETIAP sesar LENGKAP (HW+FW+START+END): REDAM versi penuh
    % kurva HW/FW (spaghetti shell), fill zona, & gambar kurva HW/FW TERPOTONG ke
    % [start,end]. Persisten walau sesar itu TIDAK aktif — ujung yg disembunyikan
    % tak muncul lagi saat pindah sesar.
    i_drawPersistentZones(fig);

    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, i_raiseIndenter(fig); if ~hs, hold(ax,'off'); end, return; end
    nF = h.nF;
    [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    isSub = ~isempty(pivui.grain5Model.parentId(f));
    % HW & FW sesar/SF AKTIF disorot garis tebal: HW MERAH, FW BIRU (SF pun sama —
    % FW SF = kurva pasangan bawahnya, lihat faultNetslip). Konsisten utama & SF.
    hwCol = [0.85 0.10 0.10];
    % START & END terisi -> potong tampilan kurva DI LUAR [start,end] (visual).
    clampAB = [];
    if isfinite(f.startF) && isfinite(f.endF)
        clampAB = [f.startF f.endF];
    end
    if okHW, i_hlCurve(fig, hwRow, hwCol, '', clampAB); end     % TANPA label saat tab ①
    if okFW, i_hlCurve(fig, fwRow, [0.10 0.30 0.85], '', clampAB); end
    if okHW
        y = pivui.grain5Fmt.clampRange(i_rowDispY(h, hwRow), clampAB);
        i_plotPt(ax, y, f.startF,'start'); i_plotPt(ax, y, f.nuc,'nuc');
        i_plotPt(ax, y, f.fsr,'fsr');      i_plotPt(ax, y, f.endF,'end');
        if isfield(f,'nucT'), i_plotPt(ax, y, f.nucT,'nuct'); end
        if isfield(f,'fsrT'), i_plotPt(ax, y, f.fsrT,'fsrt'); end
    end
    if okFW
        y = pivui.grain5Fmt.clampRange(i_rowDispY(h, fwRow), clampAB);
        i_plotPt(ax, y, f.startF,'start'); i_plotPt(ax, y, f.nuc,'nuc');
        i_plotPt(ax, y, f.fsr,'fsr');      i_plotPt(ax, y, f.endF,'end');
        if isfield(f,'nucT'), i_plotPt(ax, y, f.nucT,'nuct'); end
        if isfield(f,'fsrT'), i_plotPt(ax, y, f.fsrT,'fsrt'); end
    end
    % Sesar UTAMA aktif & punya SF -> nyalakan JUGA kurva HW tiap SF, TIAP SF
    % warna BERBEDA (varian hijau berjenjang zoneGreen). Jadi 1 seleksi F# =
    % HW(merah)+FW(biru)+semua kurva SF tampak sekaligus.
    if ~isSub
        subs = pivui.grain5Model.subFaultsOf(h, f.id);
        for j = 1:numel(subs)
            sfj = subs{j};
            sfRow = pivui.grain5Model.rowForPos(h, sfj.hwPosPx);
            if isempty(sfRow), continue; end
            sfCol = pivui.grain5Palette.zoneGreen(h, j);
            sfAB = [];
            if isfield(sfj,'startF') && isfield(sfj,'endF') && isfinite(sfj.startF) && isfinite(sfj.endF)
                sfAB = [sfj.startF sfj.endF];
            end
            i_hlCurve(fig, sfRow, sfCol, '', sfAB);
            ysf = pivui.grain5Fmt.clampRange(i_rowDispY(h, sfRow), sfAB);
            i_plotPt(ax, ysf, sfj.startF,'start'); i_plotPt(ax, ysf, sfj.nuc,'nuc');
            i_plotPt(ax, ysf, sfj.fsr,'fsr');      i_plotPt(ax, ysf, sfj.endF,'end');
        end
    end
    % 4 GARIS VERTIKAL POI (START/END/NUC/FSR) sesar aktif + label nomor frame di
    % puncak. Warna per-jenis POI (snapPoints.color). HANYA saat TAB ⑨ (Export)
    % aktif — di Tab ①/② garis vertikal ini TAK ditampilkan (permintaan user).
    if i_onExportTab(h), i_drawPoiVlines(fig, f); end
    i_drawDescVlines(fig);   % GRAIN4: garis vertikal tiap frame yang SUDAH dideskripsi
    i_raiseIndenter(fig);   % indenter max selalu paling atas
    if ~hs, hold(ax,'off'); end
end

function rgb = i_poiColor(poi)
%I_POICOLOR  Warna POI berdasarkan AKHIRAN: *-FSR=merah · *-TF/NUC-FSR=cokelat ·
%   *-BDF0=biru (di alas kaca model) · *-BDF1=hijau (di tengah model) ·
%   Start/End/FS-x=hitam (sel tabel abu2) · FS-max=ungu. Lainnya -> hijau-teal.
%   Cek Start/End/FS-X/FS-MAX & BDF0/BDF1 SEBELUM 'FSR'/'TF' — spesifik dulu.
%   NUC-FSR (dulu 'NUC-TF') = KHUSUS cokelat (cegah tertangkap aturan *-FSR merah).
    p = upper(strtrim(char(poi)));
    if strcmp(p,'START') || strcmp(p,'END') || strcmp(p,'X-FS'), rgb = [0 0 0];   % HITAM (sel tabel -> abu2)
    elseif strcmp(p,'ACT-FSR'),rgb = [0.50 0.10 0.75];   % UNGU (fault slip maksimum)
    elseif strcmp(p,'NUC-FSR'),rgb = [0.55 0.35 0.15];  % COKELAT (dulu NUC-TF; tetap cokelat)
    elseif endsWith(p,'BDF0'),rgb = [0.10 0.35 0.90];   % BLUE  (alas kaca)
    elseif endsWith(p,'BDF1'),rgb = [0.10 0.65 0.20];   % GREEN (tengah model)
    elseif endsWith(p,'FSR'), rgb = [0.90 0.10 0.10];   % RED
    elseif endsWith(p,'TF'),  rgb = [0.55 0.35 0.15];   % COKELAT (brown)
    else,                     rgb = [0.10 0.55 0.45];   % teal (blank/lainnya)
    end
end

function ls = i_poiLineStyle(poi)
%I_POILINESTYLE  Gaya garis vertikal DX berdasar FASE POI (awalan):
%   NUC-* = dashed ':' (nukleasi) · PRP-* = full '-' (propagasi) ·
%   FS-max = full '-' (fault slip maksimum). Lainnya -> dashed ':' (default).
    p = upper(strtrim(char(poi)));
    if startsWith(p,'PRP') || strcmp(p,'ACT-FSR') || strcmp(p,'START') || strcmp(p,'END'), ls = '-'; else, ls = ':'; end
end

function i_drawDescFills(fig, rows)
%I_DRAWDESCFILLS  Fill vertikal di axPOT (garis PSG aktif):
%   (1) MERAH tipis = kondisi sesar SEDANG SLIP. Ambil FRAME baris ber-POI
%       'ACT-FSR' (BUKAN kolom FS), urut menaik, PASANGKAN 2-2: (fmax1..fmax2),
%       (fmax3..fmax4),... tiap pasangan -> patch merah alpha rendah. Fill HANYA
%       antara FS-max ke FS-max (tak meluas ke luar).
%   (2) HIJAU tipis = TRANSISI (hand-off imbrikasi). Tiap baris POI='TRX' dgn
%       fTrx valid -> patch hijau dari frame(awal)..fTrx(akhir).
%   Digambar SEBELUM garis vertikal (di belakang). Tag 'descVline' (ikut terhapus
%   tiap decorate bersama vline).
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
    ax = h.axPOT; yl = get(ax,'YLim');
    hs = ishold(ax); hold(ax,'on');
    % --- (1) HITAM: rentang AKTIVITAS FSR = NUC-FSR pertama -> X-FS terakhir,
    %     PER-F# (tiap sesar 1 rentang; studi lifecycle FSR). NUC-FSR = FSR mulai
    %     (length 0); X-FS = FSR berhenti (length 0). Kelompokkan frame per fNum. ---
    grpNuc = containers.Map('KeyType','char','ValueType','any');
    grpXfs = containers.Map('KeyType','char','ValueType','any');
    for k = 1:numel(rows)
        p = upper(strtrim(char(rows{k}.poi)));
        v = rows{k}.frame; if ~(isscalar(v) && isfinite(v)), continue; end
        key = strtrim(char(rows{k}.fNum)); if isempty(key), key = '(none)'; end
        if strcmp(p,'NUC-FSR')
            if isKey(grpNuc,key), grpNuc(key)=[grpNuc(key) round(v)]; else, grpNuc(key)=round(v); end
        elseif strcmp(p,'X-FS')
            if isKey(grpXfs,key), grpXfs(key)=[grpXfs(key) round(v)]; else, grpXfs(key)=round(v); end
        end
    end
    ks = keys(grpNuc);
    for gi = 1:numel(ks)
        key = ks{gi};
        a = min(grpNuc(key));                                   % NUC-FSR pertama
        if ~isKey(grpXfs,key), continue; end                    % perlu X-FS utk tutup
        b = max(grpXfs(key));                                   % X-FS terakhir
        i_fillBand(ax, a, b, yl, [0 0 0], 0.30, 'descSlipFill');   % HITAM alpha 0.3
    end
    % --- (2) HIJAU: transisi TRX (frame..fTrx) ---
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmpi(strtrim(char(r.poi)),'TRX'), continue; end
        a = r.frame; b = NaN; if isfield(r,'fTrx'), b = r.fTrx; end
        if ~(isscalar(a) && isfinite(a) && isscalar(b) && isfinite(b)), continue; end
        i_fillBand(ax, round(a), round(b), yl, [0.10 0.70 0.25], 0.15, 'descTrxFill');
    end
    if ~hs, hold(ax,'off'); end
end

function i_fillBand(ax, a, b, yl, rgb, alpha, tag)
%I_FILLBAND  Patch persegi vertikal [min(a,b)..max(a,b)] x YLim. Tag='descVline'
%   supaya ikut terhapus tiap decorate; ditandai jenis via UserData `tag`.
    lo = min(a,b); hi = max(a,b);
    if ~(isfinite(lo) && isfinite(hi)) || hi <= lo, return; end
    patch(ax, [lo hi hi lo], [yl(1) yl(1) yl(2) yl(2)], rgb, ...
        'FaceAlpha',alpha, 'EdgeColor','none', 'Tag','descVline', ...
        'UserData',tag, 'HitTest','off','PickableParts','none');
end

function rows = i_descRowsForVlines(h)
%I_DESCROWSFORVLINES  Baris DESC utk garis vertikal/fill axPOT, HORMATI Filter F#:
%   Filter ON (h.descFilterF) & ada sesar aktif -> HANYA baris F# aktif; else
%   (filter OFF atau tak ada sesar aktif) -> SEMUA baris garis PSG aktif.
    rows = {};
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    all = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    doFilter = false; fFilter = '';
    if isfield(h,'descFilterF') && h.descFilterF
        [fa, ia] = pivui.grain5Model.activeFault(h);
        if ia >= 1
            u = i_uiNumStr(fa);
            if ~isempty(u) && ~strcmp(u,'—'), fFilter = ['F' u]; doFilter = true; end
        end
    end
    if ~doFilter, rows = all; return; end
    for k = 1:numel(all)
        if strcmp(strtrim(all{k}.fNum), fFilter), rows{end+1} = all{k}; end %#ok<AGROW>
    end
end

function i_drawDescVlines(fig)
%I_DRAWDESCVLINES  Gambar garis vertikal di axPOT pada SETIAP frame yang sudah
%   punya baris deskripsi (garis PSG AKTIF, HORMATI Filter F#). WARNA per-POI
%   (akhiran): FSR=merah, TF=cokelat, BDF=biru, blank/lainnya=teal. GAYA per-FASE:
%   NUC-*=dashed, PRP-*=full (i_poiLineStyle). Tag 'descVline' (dihapus tiap decorate).
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
    ax = h.axPOT;
    try, delete(findall(ax,'Tag','descVline')); catch, end
    if ~isfield(h,'descDoc') || ~isstruct(h.descDoc), return; end
    rows = i_descRowsForVlines(h);   % hormati Filter F# (ON=hanya F# aktif)
    if isempty(rows), return; end
    i_drawDescFills(fig, rows);   % fill MERAH (slip pasangan FS) + HIJAU (transisi TRX)
    % Frame unik + POI-nya (bila 1 frame punya banyak baris, ambil POI ber-warna
    % pertama; blank di-override oleh POI ber-warna bila ada di frame sama).
    frMap = containers.Map('KeyType','double','ValueType','char');
    for k = 1:numel(rows)
        v = rows{k}.frame;
        if ~(isscalar(v) && isfinite(v)), continue; end
        fk = round(v); p = rows{k}.poi;
        if ~isKey(frMap, fk)
            frMap(fk) = p;
        else
            % prioritaskan POI ber-warna (non-blank) supaya garis tak jadi teal.
            old = frMap(fk);
            if strcmp(old,'</blank>') && ~strcmp(p,'</blank>'), frMap(fk) = p; end
        end
    end
    fr = cell2mat(keys(frMap));
    if isempty(fr), return; end
    yl = get(ax,'YLim');
    hs = ishold(ax); hold(ax,'on');
    for k = 1:numel(fr)
        xf = fr(k);
        poi = frMap(xf);
        col = i_poiColor(poi);
        ls  = i_poiLineStyle(poi);   % FASE: NUC-* = dashed ':' · PRP-* = full '-'
        plot(ax, [xf xf], [yl(1) yl(2)], ls, 'Color',[col 0.85], 'LineWidth',2.2, ...
            'Tag','descVline','HitTest','off','PickableParts','none');
        plot(ax, xf, yl(1), '^', 'MarkerSize',6, 'MarkerEdgeColor',col, ...
            'MarkerFaceColor',col, 'Tag','descVline','HitTest','off','PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end

function i_drawPoiVlines(fig, f)
%I_DRAWPOIVLINES  Gambar hingga 4 garis vertikal pada frame POI sesar `f`
%   (START/NUC/FSR/END) setinggi YLim axPOT + label " f<frame>" di dekat puncak.
%   KETINGGIAN LABEL DIBEDAKAN per-jenis POI (selisih tinggi KONSTAN) supaya bila
%   dua POI berdekatan, labelnya TAK berhimpit (permintaan user). Warna garis =
%   warna POI (snapPoints.color). Tag 'poiVline' (dihapus di awal decorate).
%   Melewati POI yang belum di-set (NaN). Pola meniru grain4Shell.updateFrameLine.
    h = guidata(fig); ax = h.axPOT;
    if ~ishghandle(ax) || ~isstruct(f), return; end
    yl = get(ax,'YLim'); xl = get(ax,'XLim');
    % Kolom: field · key warna · label · TIER ketinggian (0=paling atas, dst).
    specs = { 'startF','start','START',0 ; 'nuc','nuc','NUC-D',1 ; ...
              'nucT','nuct','NUC-T',2 ; 'fsr','fsr','FSR-D',3 ; ...
              'fsrT','fsrt','FSR-T',4 ; 'endF','end','END',5 };
    step = 0.075 * (yl(2)-yl(1));   % selisih tinggi konstan antar-tier
    hs = ishold(ax); hold(ax,'on');
    for k = 1:size(specs,1)
        fld = specs{k,1};
        if ~isfield(f, fld), continue; end
        xf = f.(fld);
        if ~(isscalar(xf) && isfinite(xf)), continue; end
        xf = round(xf);
        col = pivcore.pot.snapPoints.color(specs{k,2});
        yLab = yl(2) - specs{k,4}*step;   % tier ketinggian per POI
        % Garis vertikal HANYA sampai label-nya (biar rapi + tier terlihat).
        plot(ax, [xf xf], [yl(1) yLab], '--', 'Color',[col 0.85], 'LineWidth',1.3, ...
            'Tag','poiVline','HitTest','off','PickableParts','none');
        % Label frame di ujung atas garis. Sisi label ikut posisi (dekat tepi
        % kanan -> tulis ke KIRI supaya tak terpotong).
        ha = 'left';
        if isfinite(xl(2)) && xf > xl(1) + 0.85*(xl(2)-xl(1)), ha = 'right'; end
        txt = sprintf('%s f%d', specs{k,3}, xf);
        text(ax, xf, yLab, txt, 'Color',col, 'FontSize',7.5, 'FontWeight','bold', ...
            'VerticalAlignment','top', 'HorizontalAlignment',ha, ...
            'BackgroundColor',[1 1 1 0.6], 'Margin',1, ...
            'Tag','poiVline','HitTest','off','PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end

function i_drawPersistentZones(fig)
%I_DRAWPERSISTENTZONES  Untuk SETIAP sesar (utama & SF) yang LENGKAP (HW+FW/
%   pasangan + START + END): (1) REDAM versi PENUH kurva HW/FW (spaghetti shell)
%   supaya ujung di luar [start,end] TAK menjulur, (2) fill zona pastel, (3)
%   gambar kurva HW/FW TERPOTONG ke [start,end]. PERSISTEN walau sesar itu tidak
%   aktif (pindah sesar → ujung yg disembunyikan tetap hilang). Tag faultFill/faultHL.
    h = guidata(fig); ax = h.axPOT; nF = h.nF;
    F = i_activeFaults(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    cmap = i_faultColorMap(h);
    % Kumpulkan baris record yang menjadi HW/FW sesar lengkap -> redam versi penuh.
    dimRows = [];
    for k = 1:numel(F)
        f = F{k};
        if ~pivui.grain5Model.faultEnabled(f), continue; end   % sesar OFF -> tak dirender
        if ~(isfinite(f.startF) && isfinite(f.endF)), continue; end
        [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        if okHW, dimRows(end+1) = hwRow; end %#ok<AGROW>
        if okFW, dimRows(end+1) = fwRow; end %#ok<AGROW>
    end
    dimRows = unique(dimRows);
    % Redam garis potCurve (spaghetti) utk baris tsb (biar tak ada ujung penuh).
    if ~isempty(dimRows)
        try
            cc = findall(ax,'Tag','potCurve');
            for c = cc(:).'
                ud = get(c,'UserData');
                if isscalar(ud) && ismember(ud, dimRows)
                    set(c,'Color',[0.92 0.92 0.92],'LineWidth',0.4);
                end
            end
        catch
        end
    end
    % F UTAMA dulu (fill HW→FW PENUH sbg latar; tak terganggu SF), baru SF di atas.
    for pass = 0:1        % pass 0 = utama, pass 1 = SF
        for k = 1:numel(F)
            f = F{k};
            if ~pivui.grain5Model.faultEnabled(f), continue; end   % sesar OFF -> tak dirender
            isSub = ~isempty(pivui.grain5Model.parentId(f));
            if (pass==0) == isSub, continue; end     % pass 0 skip SF; pass 1 skip utama
            if ~(isfinite(f.startF) && isfinite(f.endF)), continue; end
            [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
            if ~(okHW && okFW), continue; end
            fm = pivui.grain5Model.mainFaultOf(h, f);
            fillCol = [0.7 0.85 0.7];
            if ~isSub && cmap.isKey(f.id), fillCol = cmap(f.id);
            elseif isSub && cmap.isKey(fm.id), fillCol = 0.6*cmap(fm.id) + 0.4*[0.4 0.9 0.4]; end
            a = max(1, round(min(f.startF,f.endF))); b = min(nF, round(max(f.startF,f.endF)));
            if b <= a, continue; end
            clampAB = [a b];
            yHW = pivui.grain5Fmt.clampRange(i_rowDispY(h, hwRow), clampAB);
            yFW = pivui.grain5Fmt.clampRange(i_rowDispY(h, fwRow), clampAB);
            % Fill zona — HANYA sesar UTAMA (F#). SF tak diberi fill (permintaan
            % user: arsir zona cuma untuk F#, bukan sub-fault).
            if ~isSub
                ia = a:b; top = yHW(ia); bot = yFW(ia);
                gg = isfinite(top) & isfinite(bot);
                xa = ia(gg); ta = top(gg); ba = bot(gg);
                if numel(xa) >= 2
                    fill(ax, [xa fliplr(xa)], [ta fliplr(ba)], fillCol, ...
                        'FaceAlpha',pivui.grain5Palette.zoneAlpha(h),'EdgeColor','none','Tag','faultFill', ...
                        'HitTest','off','PickableParts','none');
                end
            end
            % Kurva HW/FW TERPOTONG (konteks tipis; sesar aktif ditebalkan i_hlCurve).
            xh = 1:nF; gH = isfinite(yHW);
            hwCol = [0.85 0.30 0.30]; if isSub, hwCol = [0.30 0.65 0.35]; end
            if any(gH), plot(ax, xh(gH), yHW(gH), '-', 'Color',hwCol, 'LineWidth',1.6, ...
                    'Tag','faultFill','HitTest','off','PickableParts','none'); end
            if ~isSub
                gF = isfinite(yFW);
                if any(gF), plot(ax, xh(gF), yFW(gF), '-', 'Color',[0.30 0.45 0.85], 'LineWidth',1.6, ...
                        'Tag','faultFill','HitTest','off','PickableParts','none'); end
            end
        end
    end
end


function y = i_rowDispY(h, row)
%I_ROWDISPY  Deret-Y TAMPIL kurva baris row (trim + moving-average) — sinkron
%   dgn yang dirender di axPOT.
    y = [];
    if isempty(row) || row < 1 || row > numel(h.recs), return; end
    [~, y] = pivcore.pot.records.curveXY(h.recs(row), h.nF);
    y = pivui.grain4Shell.applyTrimYV(h.recs(row), y);
    y = pivui.grain4Shell.dispYV(h, y);
end

function i_hlCurve(fig, row, col, label, clampAB)
    if nargin < 5, clampAB = []; end
    h = guidata(fig); ax = h.axPOT;
    if row < 1 || row > numel(h.recs), return; end
    [xv, ~] = pivcore.pot.records.curveXY(h.recs(row), h.nF);
    yv = pivui.grain5Fmt.clampRange(i_rowDispY(h, row), clampAB);
    g = isfinite(xv) & isfinite(yv); if ~any(g), return; end
    plot(ax, xv(g), yv(g), '-', 'Color',col, 'LineWidth',3.2, ...
        'Tag','faultHL','HitTest','off','PickableParts','none');
    if ~isempty(label)
        [pv, pf] = max(yv);
        if isfinite(pv)
            text(ax, pf, pv, [' ' label], 'Color',col, 'FontWeight','bold','FontSize',9, ...
                'BackgroundColor','w','EdgeColor',col,'Margin',2, ...
                'VerticalAlignment','bottom','HorizontalAlignment','center', ...
                'Tag','faultHL','HitTest','off','PickableParts','none');
        end
    end
end

function i_drawAllFaults(fig)
%I_DRAWALLFAULTS  Mode "Semua sesar": untuk TIAP sesar utama, gambar HW (merah)
%   & FW (biru) + fill pastel transparan area sesar (batas kiri/kanan = START..END
%   bila ada, else rentang penuh) + label F#. SF anaknya digambar hijau + fill
%   pastel. Kurva mentah lain disembunyikan (shell tetap gambar spaghetti di
%   belakang; kita cukup TIDAK menutupinya — user minta HANYA sesar tampil, jadi
%   kita gambar patch putih semi-opaque? -> lebih baik: sembunyikan spaghetti).
    h = guidata(fig); ax = h.axPOT; nF = h.nF;
    % Redam kurva spaghetti (mentah) supaya HANYA sesar menonjol.
    try
        cc = findall(ax,'Tag','potCurve');
        for c = cc(:).', set(c,'Color',[0.90 0.90 0.90],'LineWidth',0.4); end
    catch
    end
    hs = ishold(ax); hold(ax,'on');
    pastel = pivui.grain5Palette.zonePalette(h);
    F = i_activeFaults(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    ci = 0; nMain = 0;
    for k = 1:numel(F), if isempty(pivui.grain5Model.parentId(F{k})), nMain = nMain + 1; end, end
    for k = 1:numel(F)
        f = F{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end       % SF via induk
        if ~pivui.grain5Model.faultEnabled(f), continue; end            % sesar OFF -> tak dirender
        ci = ci + 1; pcol = pastel{mod(ci-1,numel(pastel))+1};
        i_drawFaultBand(fig, f, pcol, false, ci, nMain);
        subs = pivui.grain5Model.subFaultsOf(h, f.id);
        for j = 1:numel(subs)
            scol = pivui.grain5Palette.zoneGreen(h, j);
            i_drawFaultBand(fig, subs{j}, scol, true, ci, nMain);
        end
    end
    i_raiseIndenter(fig);   % kurva indenter max SELALU paling atas (tak tertimpa)
    if ~hs, hold(ax,'off'); end
end

function i_raiseIndenter(fig)
%I_RAISEINDENTER  Pastikan kurva envelope INDENTER MAX (garis hitam tebal) berada
%   di LAPIS PALING ATAS axPOT — tak tertimpa fill/kurva sesar. Gambar ulang di
%   atas (Tag potIndenter sudah ada dari shell; kita re-plot salinan di atas).
    h = guidata(fig); ax = h.axPOT;
    if ~ishghandle(ax), return; end
    env = [];
    if isfield(h,'indenter') && ~isempty(h.indenter), env = h.indenter;
    else, try, env = pivui.grain4Shell.indenterEnvelope(h); catch, end, end
    if isempty(env), return; end
    try, delete(findall(ax,'Tag','potIndenterTop')); catch, end
    xe = 1:numel(env); ge = isfinite(env);
    if ~any(ge), return; end
    hs = ishold(ax); hold(ax,'on');
    plot(ax, xe(ge), env(ge), '-', 'Color',[0 0 0], 'LineWidth',3, ...
        'Tag','potIndenterTop','HitTest','off','PickableParts','none');
    if ~hs, hold(ax,'off'); end
end

function i_drawFaultBand(fig, f, fillCol, isSub, ci, nMain)
%I_DRAWFAULTBAND  Gambar 1 sesar (HW+FW/pasangan) + fill pastel area + label F#.
%   ci/nMain = index & jumlah sesar utama (utk sebar posisi-X label agar tak
%   bertumpuk saat rentang fill sama).
    if nargin < 5, ci = 1; end
    if nargin < 6, nMain = 1; end
    h = guidata(fig); ax = h.axPOT; nF = h.nF;
    [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    if ~okHW, return; end
    yHW = i_rowDispY(h, hwRow);
    yFW = []; if okFW, yFW = i_rowDispY(h, fwRow); end
    x = 1:nF;
    % Batas kiri/kanan = START..END bila ada, else seluruh rentang valid.
    a = f.startF; b = f.endF;
    hasSE = isfinite(a) && isfinite(b);
    if ~hasSE
        gg = isfinite(yHW); if okFW, gg = gg & isfinite(yFW); end
        idxg = find(gg); if isempty(idxg), a = 1; b = nF; else, a = idxg(1); b = idxg(end); end
    end
    a = max(1, round(min(a,b))); b = min(nF, round(max(a,b)));
    % POTONG ujung: bila START & END terdefinisi, kurva HW/FW & fill DIPOTONG ke
    % [a,b] (NaN di luar) supaya distribusi sesar terlihat jelas (tak menjulur).
    if hasSE
        clampAB = [a b];
        yHW = pivui.grain5Fmt.clampRange(yHW, clampAB);
        if okFW, yFW = pivui.grain5Fmt.clampRange(yFW, clampAB); end
    end
    % Fill area antara HW & pasangan (bawah) pada rentang a..b — HANYA F# utama.
    % SF tak diberi fill (permintaan user: arsir zona cuma untuk F#).
    if okFW && b > a && ~isSub
        ia = a:b;
        top = yHW(ia); bot = yFW(ia);
        gg = isfinite(top) & isfinite(bot);
        xa = ia(gg); ta = top(gg); ba = bot(gg);
        if numel(xa) >= 2
            fill(ax, [xa fliplr(xa)], [ta fliplr(ba)], fillCol, ...
                'FaceAlpha',pivui.grain5Palette.zoneAlpha(h),'EdgeColor','none','Tag','faultFill', ...
                'HitTest','off','PickableParts','none');
        end
    end
    % Kurva HW (merah / hijau utk SF) & FW (biru; SF tak punya FW sendiri).
    hwCol = [0.85 0.10 0.10]; if isSub, hwCol = [0.10 0.60 0.15]; end
    gH = isfinite(yHW);
    if any(gH)
        plot(ax, x(gH), yHW(gH), '-', 'Color',hwCol, 'LineWidth',2.4, ...
            'Tag','faultHL','HitTest','off','PickableParts','none');
    end
    if okFW && ~isSub
        gF = isfinite(yFW);
        if any(gF)
            plot(ax, x(gF), yFW(gF), '-', 'Color',[0.10 0.30 0.85], 'LineWidth',2.4, ...
                'Tag','faultHL','HitTest','off','PickableParts','none');
        end
    end
    % Label F# (checkbox on/off). NOMOR TAMPIL = f.uiNum (BUKAN f.id yg unik-internal
    % naik terus jadi F11-F20). Posisi-X = FRAME FS-MAX PERTAMA sesar (dari baris
    % DESC POI='ACT-FSR'); fallback tengah rentang bila tak ada FS-max.
    if isfield(h,'faultLabelOn') && ~h.faultLabelOn, return; end
    lbl = ['F' i_uiNumStr(f)]; if isSub, lbl = pivui.grain5Fmt.subTag(f.id); end
    xFs = i_faultFsMaxFrame(h, f);            % frame FS-max pertama (NaN bila tak ada)
    if isfinite(xFs), xc = round(xFs); else, xc = round((a+b)/2); end
    if xc < 1, xc = 1; end; if xc > nF, xc = nF; end
    yl = get(ax,'YLim');
    if isfield(h,'faultLabelPos') && strcmp(h.faultLabelPos,'center')
        yTop = NaN; yBot = NaN;
        if xc>=1 && xc<=numel(yHW), yTop = yHW(xc); end
        if okFW && xc>=1 && xc<=numel(yFW), yBot = yFW(xc); end
        if isfinite(yTop) && isfinite(yBot), yc = (yTop+yBot)/2; elseif isfinite(yTop), yc = yTop; else, yc = mean(yl); end
        text(ax, xc, yc, lbl, 'Color',[0 0 0], 'FontWeight','bold','FontSize',9, ...
            'BackgroundColor',fillCol,'EdgeColor',[0.4 0.4 0.4],'Margin',2, ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'Tag','faultHL','HitTest','off','PickableParts','none');
    else
        % Label DI FS-MAX: taruh tepat di atas kurva HW pada frame FS-max (bukan
        % melayang di puncak sumbu). Garis penunjuk pendek dari kurva ke label.
        yTop = NaN; if xc>=1 && xc<=numel(yHW), yTop = yHW(xc); end
        if ~isfinite(yTop), yTop = yl(2) - 0.10*(yl(2)-yl(1)); end
        ytxt = min(yl(2)-0.02*(yl(2)-yl(1)), yTop + 0.06*(yl(2)-yl(1)));
        plot(ax,[xc xc],[yTop ytxt],'-','Color',[0.3 0.3 0.3],'LineWidth',0.8, ...
            'Tag','faultHL','HitTest','off','PickableParts','none');
        text(ax, xc, ytxt, lbl, 'Color',[0 0 0], 'FontWeight','bold','FontSize',9, ...
            'BackgroundColor',fillCol,'EdgeColor',[0.4 0.4 0.4],'Margin',2, ...
            'HorizontalAlignment','center','VerticalAlignment','bottom', ...
            'Tag','faultHL','HitTest','off','PickableParts','none');
    end
end

function fr = i_faultFsMaxFrame(h, f)
%I_FAULTFSMAXFRAME  Frame FS-MAX PERTAMA sesar f (uiNum) dari baris DESC GRAIN4
%   (POI='ACT-FSR', garis PSG aktif). NaN bila tak ada. Dipakai menempatkan label F#.
    fr = NaN;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    if isempty(rows), return; end
    ftag = pivcore.io.grain4Report.normFtag(['F' i_uiNumStr(f)]);
    best = NaN;
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmpi(strtrim(char(r.poi)),'ACT-FSR'), continue; end
        if ~strcmp(pivcore.io.grain4Report.normFtag(r.fNum), ftag), continue; end
        v = r.frame;
        if isscalar(v) && isfinite(v), if ~isfinite(best) || v<best, best=v; end, end
    end
    fr = best;
end

function i_renderFaultSlip(fig)
%I_RENDERFAULTSLIP  AXSLIP: net-slip sesar AKTIF = HW−FW. Luas START..END
%   (= ∫ net-slip) diarsir; titik START/NUC/FSR/END ditandai. Dipanggil shell
%   renderSlip lewat hook slipOverride saat view='slip'.
%   TANPA GATE: SELALU tampilkan net-slip F# yang sedang AKTIF (tak dialihkan ke
%   mode "Slip all" & tak diblok placeholder). Bila net-slip belum bisa dihitung
%   (HW/FW belum lengkap) -> axes kosong (frame line + garis DX tetap tampil).
    h = guidata(fig);
    ax = h.axPOT; cla(ax);
    set(ax,'Color',[0.99 0.99 0.96],'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
    hold(ax,'on');
    [f, idx] = pivui.grain5Model.activeFault(h);
    ns = [];
    if idx >= 1, [ns, ~, ~, ~, ~] = pivui.grain5Model.faultNetslip(h, f); end
    nF = h.nF;
    % Net-slip F# aktif belum bisa dihitung -> render axes kosong (BUKAN gate/return
    % dini yg memblok). Frame line + garis vertikal DX tetap tampil.
    if isempty(ns) || ~any(isfinite(ns))
        hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'net-slip (px/frame)'); grid(ax,'on');
        ttl = 'AXSLIP — net-slip sesar aktif';
        if idx >= 1, ttl = sprintf('AXSLIP — net-slip %s (HW/FW belum lengkap)', f.id); end
        title(ax, ttl, 'Color',[0 0 0]);
        if nF > 1, xlim(ax,[1 nF]); end
        i_applyPotXLim(fig);   % X AXSLIP = X axPOT (jendela potXWin/potXCenter)
        i_drawDescVlines(fig);
        i_drawAxslipCutLine(fig);   % garis ambang cut-off (AUTO — DX)
        pivui.grain4Shell.updateFrameLine(fig); return;
    end
    % POTONG net-slip di START..END: kurva slip HANYA tampil dalam rentang aktif
    % (di luar itu di-NaN-kan). Bila START/END belum diisi, tampil penuh.
    nsClamp = ns;
    if isfinite(f.startF) && isfinite(f.endF)
        nsClamp = pivui.grain5Fmt.clampRange(ns, [f.startF f.endF]);
    end
    xe = 1:numel(nsClamp); g = isfinite(nsClamp);
    % Arsir luas START..END (∫ net-slip).
    a = f.startF; b = f.endF;
    if isfinite(a) && isfinite(b)
        a = max(1, round(min(a,b))); b = min(numel(ns), round(max(a,b)));
        if b > a
            ia = a:b; gg = isfinite(ns(ia)); xa = ia(gg); ya = ns(ia); ya = ya(gg);
            if numel(xa) >= 2
                fill(ax, [xa fliplr(xa)], [ya zeros(1,numel(xa))], [0.95 0.85 0.30], ...
                    'FaceAlpha',0.35,'EdgeColor','none','Tag','slipArea', ...
                    'HitTest','off','PickableParts','none');
            end
        end
    end
    col = [0.55 0.10 0.55];
    plot(ax, xe(g), nsClamp(g), '-', 'Color',col, 'LineWidth',2.6, 'Tag','slipCurve');
    i_plotPt(ax, ns, f.startF,'start'); i_plotPt(ax, ns, f.nuc,'nuc');
    i_plotPt(ax, ns, f.fsr,'fsr');      i_plotPt(ax, ns, f.endF,'end');
    hold(ax,'off');
    xlabel(ax,'Frame'); ylabel(ax, sprintf('net-slip = HW−FW (%s)', pivui.grain5Fmt.unitsStr(h)));
    area = pivcore.pot.netslip.area(ns, f.startF, f.endF);
    if isscalar(area) && isfinite(area), atxt = sprintf(' · luas=%.3g', area); else, atxt = ''; end
    title(ax, sprintf('AXSLIP — net-slip %s%s', f.id, atxt), 'Color',[0 0 0]);
    grid(ax,'on');
    set(ax,'ButtonDownFcn',@(s,e) pivui.grain4Shell.onAxPotClick(fig));
    yv = ns(g); ylo = min(0, min(yv)); yhi = max(yv); if yhi <= ylo, yhi = ylo + 1; end
    h.yBase = [ylo yhi]; guidata(fig, h);
    if pivui.grain4Shell.viewIsLocked(h)
        pivui.grain4Shell.applyViewLock(fig);
    else
        if nF > 1, xlim(ax,[1 nF]); end, ylim(ax,[ylo yhi]);
        i_applyPotXLim(fig);   % X AXSLIP = X axPOT (jendela potXWin/potXCenter)
    end
    i_drawDescVlines(fig);   % garis vertikal POI ber-WARNA (FSR/TF/BDF) juga di AXSLIP
    i_drawAxslipCutLine(fig);   % garis ambang cut-off (AUTO — DX)
    pivui.grain4Shell.updateFrameLine(fig);
end

function i_renderAllSlip(fig)
%I_RENDERALLSLIP  AXSLIP: net-slip SEMUA sesar utama teridentifikasi bertumpuk
%   (tiap sesar warna pastel; luas START..END diarsir tipis).
    h = guidata(fig);
    ax = h.axPOT; cla(ax); nF = h.nF;
    set(ax,'Color',[0.99 0.99 0.96],'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
    hold(ax,'on');
    F = i_activeFaults(h);   % scoping multi-PSG: hanya sesar garis PSG aktif
    pastel = pivui.grain5Palette.zonePalette(h); ci = 0; ny = [];
    for k = 1:numel(F)
        f = F{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        if ~(okHW && okFW) || isempty(ns) || ~any(isfinite(ns)), continue; end
        ci = ci + 1; col = pastel{mod(ci-1,numel(pastel))+1}; dcol = 0.6*col;
        a = f.startF; b = f.endF;
        % POTONG net-slip di START..END (bila terisi) — kurva slip hanya rentang aktif.
        nsC = ns;
        if isfinite(a) && isfinite(b), nsC = pivui.grain5Fmt.clampRange(ns, [a b]); end
        xe = 1:numel(nsC); g = isfinite(nsC);
        if isfinite(a) && isfinite(b)
            a = max(1, round(min(a,b))); b = min(numel(ns), round(max(a,b)));
            if b > a
                ia = a:b; gg = isfinite(ns(ia)); xa = ia(gg); ya = ns(ia); ya = ya(gg);
                if numel(xa) >= 2
                    fill(ax, [xa fliplr(xa)], [ya zeros(1,numel(xa))], col, ...
                        'FaceAlpha',pivui.grain5Palette.zoneAlpha(h),'EdgeColor','none','Tag','slipArea', ...
                        'HitTest','off','PickableParts','none');
                end
            end
        end
        plot(ax, xe(g), nsC(g), '-', 'Color',pivui.grain5Fmt.dol(dcol), 'LineWidth',2.2, 'Tag','slipCurve');
        pv = NaN; pf = NaN; if any(g), [pv,pf] = max(nsC); end
        if isfinite(pv)
            text(ax, pf, pv, [' F' i_uiNumStr(f)], 'Color',pivui.grain5Fmt.dol(dcol),'FontWeight','bold','FontSize',8, ...
                'BackgroundColor','w','Margin',1,'Tag','slipCurve', ...
                'HitTest','off','PickableParts','none');
        end
        ny = [ny nsC(g)]; %#ok<AGROW>
    end
    hold(ax,'off');
    xlabel(ax,'Frame'); ylabel(ax, sprintf('net-slip = HW−FW (%s)', pivui.grain5Fmt.unitsStr(h)));
    title(ax, sprintf('AXSLIP — net-slip SEMUA sesar (%d)', ci), 'Color',[0 0 0]);
    grid(ax,'on');
    i_drawDescVlines(fig);   % garis vertikal DX GRAIN4 juga di AXSLIP-semua
    set(ax,'ButtonDownFcn',@(s,e) pivui.grain4Shell.onAxPotClick(fig));
    if isempty(ny)
        text(ax,0.5,0.5,'Belum ada sesar dgn HW & FW lengkap.', ...
            'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
    else
        ylo = min(0, min(ny)); yhi = max(ny); if yhi<=ylo, yhi=ylo+1; end
        h.yBase = [ylo yhi]; guidata(fig,h);
        if pivui.grain4Shell.viewIsLocked(h)
            pivui.grain4Shell.applyViewLock(fig);
        else
            if nF>1, xlim(ax,[1 nF]); end, ylim(ax,[ylo yhi]);
            i_applyPotXLim(fig);   % X AXSLIP = X axPOT
        end
    end
    pivui.grain4Shell.updateFrameLine(fig);
end


function xl = i_slipXWindow(h, nF)
%I_SLIPXWINDOW  XLim AXSLIP menurut mode XMAX. Penuh (h.slipXMax<=0) -> [1 nF].
%   Mode N: window selebar N frame BERPUSAT di tengah rentang START..END sesar
%   aktif (acuan slip F#), clamp ke [1..nF]. Bila sesar/POI tak ada, pusat =
%   frame aktif; bila itu pun absen, pusat = tengah data. Kurva slip ter-stretch.
    nF = max(1, round(pivcore.util.scalarOr(nF, 1)));
    N = 0; try, N = round(pivcore.util.scalarOr(h.slipXMax, 0)); catch, end
    if ~(isfinite(N) && N > 0) || N >= nF, xl = [1 nF]; return; end   % Penuh
    % Pusat window = tengah START..END sesar aktif (acuan). Fallback: frame aktif.
    c = NaN;
    try
        [f, idx] = pivui.grain5Model.activeFault(h);
        if idx >= 1 && isfinite(f.startF) && isfinite(f.endF)
            c = 0.5*(f.startF + f.endF);
        elseif idx >= 1 && isfinite(f.startF)
            c = f.startF;
        end
    catch
    end
    if ~isfinite(c), c = pivcore.util.scalarOr(h.frame, 0.5*nF); end
    c = max(1, min(nF, c));
    lo = round(c - N/2); hi = lo + N;
    if lo < 1,  lo = 1;  hi = 1 + N;  end     % geser ke kiri bila mentok awal
    if hi > nF, hi = nF; lo = nF - N; end      % geser ke kanan bila mentok akhir
    lo = max(1, lo);
    xl = [lo hi];
end

function i_onSlipXMax(fig, n)
%I_ONSLIPXMAX  Set mode XMAX AXSLIP (tombol TAB②): n=0 Penuh · 50/100/150/200
%   lebar window frame. Re-render slip -> XLim baru berlaku. Sorot tombol aktif.
    h = guidata(fig);
    h.slipXMax = max(0, round(pivcore.util.scalarOr(n, 0))); guidata(fig, h);
    i_syncSlipXMaxBtns(fig);
    % Render ulang plot bawah (renderPOT hormati potView: slip -> slipOverride ->
    % i_renderFaultSlip/i_renderAllSlip yg kini pakai i_slipXWindow). XLim langsung
    % berlaku. Bila plot bawah bukan slip, XMAX tak berpengaruh (window hanya slip).
    if ~isempty(h.recs)
        try, pivui.grain4Shell.renderPOT(fig); catch, end
    end
    if h.slipXMax > 0
        pivui.setStatus(fig, sprintf('AXSLIP: window %d frame (stretch slip F# di sekitar START..END).', h.slipXMax));
    else
        pivui.setStatus(fig,'AXSLIP: tampilan frame PENUH.');
    end
end

function i_syncSlipXMaxBtns(fig)
%I_SYNCSLIPXMAXBTNS  Sorot tombol XMAX yang aktif (Value togglebutton) sesuai
%   h.slipXMax. Tombol disimpan di h.btnSlipXMax (map nilai->handle via UserData).
    h = guidata(fig);
    if ~(isfield(h,'btnSlipXMax') && ~isempty(h.btnSlipXMax)), return; end
    for k = 1:numel(h.btnSlipXMax)
        b = h.btnSlipXMax(k);
        if ~ishghandle(b), continue; end
        v = get(b,'UserData');
        try, set(b,'Value', double(isequal(round(v), round(h.slipXMax)))); catch, end
    end
end

function tf = i_slipOverride(fig)
%I_SLIPOVERRIDE  Hook shell: SELALU render net-slip per-SESAR (HW−FW) F# AKTIF
%   (GRAIN4 TANPA GATE — dulu digate i_onFaultTab yg selalu false di GRAIN4 -> shell
%   malah gambar placeholder "pilih HW dgn pasangan"). Return true -> shell
%   berhenti; i_renderFaultSlip yg menggambar (termasuk axes kosong bila HW/FW
%   belum lengkap).
    tf = true;
    h = guidata(fig);
    if isfield(h,'showAllSlip') && h.showAllSlip
        i_renderAllSlip(fig);   % AXSLIP net-slip SEMUA sesar (+ garis DX)
    else
        i_renderFaultSlip(fig);
    end
end


% =====================================================================
% Pengukur SUDUT sesar (Tab ① Label HW) — 2 TOMBOL TOGGLE (ON/OFF)
%   Engine murni: pivcore.pot.faultAngle. ROI 2-titik draggable di axMain via
%   pivui.makePsgLineROI. Detachment -> h.fdoc.detachment; sudut -> f.angleDeg.
%
%   POLA (mirip kunci PSG): tombol ON -> garis muncul & bisa digeser; tombol
%   diklik lagi (OFF) -> kunci + simpan.
%     • "Set bidang detachment": ON = garis HORIZONTAL draggable (0°). OFF =
%       kunci & simpan sbg bidang referensi 0°.
%     • "Hitung sudut sesar": ON = garis MIRING draggable utk sesar aktif; sudut
%       ter-update LIVE di label saat digeser. OFF = kunci & simpan ke f.angleDeg
%       (kolom Sudut tabel sesar ter-update).
%
%   HEADLESS-SAFE: di mode pivui.quiet() TIDAK membuat ROI interaktif — tombol
%   di-nonaktifkan balik; test memanggil engine langsung (lihat test_smoke_grain5).
% =====================================================================
function i_onToggleDetach(fig)
%I_ONTOGGLEDETACH  Toggle bidang detachment. ON -> seed garis horizontal
%   draggable; OFF -> kunci (hapus ROI) + simpan sbg bidang 0°.
    h = guidata(fig);
    on = get(h.btnDetach,'Value') == 1;
    if ~on
        % OFF: kunci & simpan posisi terakhir sbg bidang 0°.
        i_captureDetach(fig); h = guidata(fig);
        if isfield(h,'roiDetach') && ~isempty(h.roiDetach) && isvalid(h.roiDetach)
            try, delete(h.roiDetach); catch, end
        end
        h.roiDetach = []; guidata(fig, h);
        set(h.btnDetach,'String','Set bidang detachment');
        det = i_detachmentDoc(h);
        if pivcore.pot.faultAngle.isValidDetachment(det)
            pivui.setStatus(fig,'Bidang detachment (0°) dikunci & disimpan.');
        else
            pivui.setStatus(fig,'Detachment belum valid — sudut dihitung absolut.');
        end
        i_refreshFaultAngleLabel(fig);
        return;
    end
    % ON: butuh axMain + mode interaktif.
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain)
        set(h.btnDetach,'Value',0); pivui.setStatus(fig,'axMain belum siap.'); return;
    end
    if pivui.quiet(), set(h.btnDetach,'Value',0); return; end   % headless: batal
    ax = h.axMain;
    det = i_detachmentDoc(h);
    if pivcore.pot.faultAngle.isValidDetachment(det)
        p1 = det.p1; p2 = det.p2;                 % lanjut dari posisi tersimpan
    else
        xl = get(ax,'XLim'); yl = get(ax,'YLim');
        yc = mean(yl); dx = 0.30*(xl(2)-xl(1));
        p1 = [mean(xl)-dx, yc]; p2 = [mean(xl)+dx, yc];   % horizontal default
    end
    if isfield(h,'roiDetach') && ~isempty(h.roiDetach) && isvalid(h.roiDetach)
        try, delete(h.roiDetach); catch, end
    end
    h.roiDetach = pivui.makePsgLineROI(ax, p1, p2, @() i_captureDetach(fig));
    try, h.roiDetach.Color = [0.10 0.55 0.20]; h.roiDetach.Label = 'detachment'; catch, end
    guidata(fig, h);
    i_captureDetach(fig);                          % simpan seed awal
    set(h.btnDetach,'String','Kunci detachment ✔');
    pivui.setStatus(fig,'Seret garis DETACHMENT (horizontal) di axMain. Klik tombol lagi utk kunci.');
end

function i_captureDetach(fig)
%I_CAPTUREDETACH  Baca posisi ROI detachment -> simpan p1/p2 ke h.fdoc.detachment.
    h = guidata(fig);
    if ~(isfield(h,'roiDetach') && ~isempty(h.roiDetach) && isvalid(h.roiDetach)), return; end
    pos = [];
    try, pos = h.roiDetach.Position; catch, end
    if isempty(pos) || size(pos,1) < 2, return; end
    if ~isstruct(h.fdoc), h.fdoc = pivcore.io.grain5Faults.emptyDoc(h.df); end
    h.fdoc.detachment = struct('p1', pos(1,:), 'p2', pos(2,:));
    guidata(fig, h);
    i_refreshFaultAngleLabel(fig);
end

% =====================================================================
% MODUL BIDANG SESAR PER-DX (polyline; hotkey Ctrl+Q) — GRAIN4
%   Tiap baris DESKRIPSI (DX / titik pengamatan) punya BENTUK bidang sesarnya
%   SENDIRI. User pilih baris DX -> Ctrl+Q -> gambar polyline di axMain (frame
%   DX itu) -> hitung SUDUT (regresi, relatif ref horizontal) + PANJANG (cm).
%   Toggle OFF (Ctrl+Q lagi) = KUNCI + simpan vertices/angleDeg/lenCm ke BARIS
%   DESC itu (_desc.json) + refresh tabel. Growth per-DX = turunan antar-DX
%   (Len[n]-Len[n-1])/(Δframe*dt), dihitung saat refresh. TIDAK per-sesar lagi.
% =====================================================================
function i_onToggleFaultPoly(fig)
%I_ONTOGGLEFAULTPOLY  Toggle input bidang sesar utk DX TERPILIH. ON -> loncat ke
%   frame DX + gambar/tampilkan polyline + label LIVE. OFF -> simpan ke baris DX.
    h = guidata(fig);
    if isfield(h,'faultPolyOn') && h.faultPolyOn
        i_faultPolyCommit(fig); return;
    end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum siap.'); i_syncFaultPolyBtn(fig,false); return;
    end
    % Butuh BARIS DESC terpilih (DX). Capture dulu supaya sinkron.
    i_captureDescFromTable(fig); h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        pivui.setStatus(fig,'Pilih BARIS DESKRIPSI (DX) dulu — bidang sesar terikat titik pengamatan.');
        i_syncFaultPolyBtn(fig,false); return;
    end
    r = rows{fullIdx};
    % LIFECYCLE FSR: NUC-FSR & X-FS = panjang FSR := 0 (ujung siklus, TAK diukur).
    poiU = upper(strtrim(char(r.poi)));
    if any(strcmp(poiU, {'NUC-FSR','X-FS'}))
        pivui.setStatus(fig, sprintf(['POI %s: FSR_length = 0 (ujung siklus; tak digambar). ' ...
            'Ukur bidang sesar mulai dari NUC-* hingga ACT-FSR (interpolasi NUC->ACT-FSR).'], strtrim(char(r.poi))));
        i_syncFaultPolyBtn(fig,false); return;
    end
    h.faultPolyDxIdx = fullIdx;
    % Loncat ke frame DX itu (bidang sesar diamati di frame pengamatan).
    frameRef = r.frame;
    if ~(isscalar(frameRef) && isfinite(frameRef)), frameRef = pivcore.util.scalarOr(h.frame,1); end
    guidata(fig, h);
    try, pivui.grain4Shell.gotoFrame(fig, round(frameRef)); catch, end
    % Matikan MODE zoom/pan interaktif (kursor jadi crosshair) TAPI pertahankan view
    % zoom-in yg dikunci. Tanpa ini, klik input vertex malah men-zoom axMain.
    i_suspendAxZoomForRoi(fig);
    h = guidata(fig);
    ax = h.axMain; col = [0 0 0];   % HITAM (ikut ter-ekspor)
    V = pivcore.io.grain4Desc.normVerts(r.vertices);
    seededFromInterp = false;
    % COPY INTERPOLASI (gaya After Effects): DX ini BELUM punya bidang sendiri
    % (unsupervised) TAPI interpolasi sedang AKTIF -> materialisasi bentuk INTERPOLASI
    % @frame DX ini jadi ROI yg bisa diedit. Kalau user tak mengubahnya lalu Ctrl+Q
    % lagi -> tersimpan sbg supervised keyframe identik; kalau diedit -> jadi
    % supervised keyframe baru yg "memberdayakan" interpolasi antar keyframe terdekat.
    % Bila interpolasi TAK aktif -> ROI KOSONG (gambar manual dari nol).
    if size(V,1) < 2
        Vi = i_interpVertsAtFrameForFault(h, strtrim(char(r.fNum)), r.frame);
        if size(Vi,1) >= 2, V = Vi; seededFromInterp = true; end
    end
    roi = [];
    if size(V,1) >= 2
        try, roi = images.roi.Polyline('Parent',ax,'Position',V, ...
                'Color',col,'LineWidth',1.6,'MarkerSize',5); catch, roi = []; end
    end
    if isempty(roi)
        if pivui.quiet(), i_syncFaultPolyBtn(fig,false); return; end
        try, roi = drawpolyline(ax,'Color',col,'LineWidth',1.6,'MarkerSize',5); catch, roi = []; end
        if isempty(roi) || ~isvalid(roi) || size(roi.Position,1) < 2
            try, if ~isempty(roi) && isvalid(roi), delete(roi); end, catch, end
            pivui.setStatus(fig,'Bidang sesar batal (perlu ≥2 vertex).'); i_syncFaultPolyBtn(fig,false); return;
        end
    end
    h.roiFaultPoly = roi;
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    h.faultPolyLabel = text(ax, xl(1)+0.02*(xl(2)-xl(1)), yl(2)-0.04*(yl(2)-yl(1)), '', ...
        'Color',[0.15 0.15 0.15],'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[1 1 1 0.85],'Margin',3,'Tag','faultPolyLabel', ...
        'VerticalAlignment','top','HorizontalAlignment','left');
    h.faultPolyOn = true; guidata(fig, h);
    try
        addlistener(roi,'MovingROI', @(s,e2) i_updateFaultPoly(fig));
        addlistener(roi,'ROIMoved',  @(s,e2) i_updateFaultPoly(fig));
    catch, end
    i_syncFaultPolyBtn(fig,true);
    i_updateFaultPoly(fig);
    if seededFromInterp
        pivui.setStatus(fig, sprintf(['Bidang sesar %s@frame%d ON — bentuk DI-COPY dari INTERPOLASI. ' ...
            'Seret utk edit (jadi keyframe supervised) atau Ctrl+Q utk kunci apa adanya.'], ...
            strtrim(r.fNum), round(frameRef)));
    else
        pivui.setStatus(fig, sprintf(['Bidang sesar %s@frame%d ON — gambar/seret polyline; ' ...
            'Ctrl+Q lagi utk KUNCI & simpan ke baris DX (jadi keyframe supervised).'], ...
            strtrim(r.fNum), round(frameRef)));
    end
end

function i_updateFaultPoly(fig)
%I_UPDATEFAULTPOLY  Metrik LIVE (sudut+panjang cm) dari ROI -> label. Per-DX.
    h = guidata(fig);
    if ~(isfield(h,'faultPolyOn') && h.faultPolyOn), return; end
    if ~(isfield(h,'roiFaultPoly') && ~isempty(h.roiFaultPoly) && isvalid(h.roiFaultPoly)), return; end
    V = []; try, V = h.roiFaultPoly.Position; catch, end
    lenCm = pivcore.io.grain4Desc.lenCmOf(V, i_faultCmPerPx(h));
    ang   = pivcore.io.grain4Desc.angleDegRelOf(V, i_faultRefDeg(h));
    nV = size(pivcore.io.grain4Desc.normVerts(V),1);
    if isfield(h,'faultPolyLabel') && ishghandle(h.faultPolyLabel)
        set(h.faultPolyLabel,'String', sprintf(' Len = %s cm   sudut = %s° ', ...
            i_polyFmt(lenCm,4), i_polyFmt(ang,4)));
    end
    pivui.setStatus(fig, sprintf('Bidang sesar: %d vertex · Len=%s cm · sudut=%s°', ...
        nV, i_polyFmt(lenCm,4), i_polyFmt(ang,4)));
end

function i_faultPolyCommit(fig)
%I_FAULTPOLYCOMMIT  Toggle OFF: simpan vertices/angleDeg/lenCm ke BARIS DX ->
%   _desc.json -> refresh tabel (kolom Sudut/Len/Growth ikut update).
    h = guidata(fig);
    V = zeros(0,2);
    if isfield(h,'roiFaultPoly') && ~isempty(h.roiFaultPoly) && isvalid(h.roiFaultPoly)
        try, V = h.roiFaultPoly.Position; catch, end
    end
    V = pivcore.io.grain4Desc.normVerts(V);
    idx = []; if isfield(h,'faultPolyDxIdx'), idx = h.faultPolyDxIdx; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if ~isempty(idx) && idx>=1 && idx<=numel(rows) && size(V,1) >= 2
        r = rows{idx};
        r.vertices = V;
        r.lenCm    = pivcore.io.grain4Desc.lenCmOf(V, i_faultCmPerPx(h));
        r.angleDeg = pivcore.io.grain4Desc.angleDegRelOf(V, i_faultRefDeg(h));
        rows{idx} = r;
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
        % (Tulis _desc.json DIBUANG: commit bidang sesar hanya update MEMORI+tabel;
        %  file ditulis HANYA saat 💾 Save eksplisit.)
        guidata(fig, h);
        % AUTO-RECOMPUTE (gaya After Effects): baris DX ini kini SUPERVISED keyframe.
        % Bila interpolasi sedang aktif, bangun-ulang track F# ini supaya frame
        % unsupervised di antara keyframe MENYESUAIKAN dgn bentuk baru ini.
        recomputed = false;
        if isfield(h,'interpOn') && h.interpOn
            uNc = pivcore.io.grain4Interp.normFtag(r.fNum);
            uiNumC = str2double(uNc);
            if isscalar(uiNumC) && isfinite(uiNumC)
                [okR] = i_rebuildInterpTrack(fig, uiNumC);
                recomputed = okR;
            end
        end
        if recomputed
            pivui.setStatus(fig, sprintf(['Keyframe supervised TERSIMPAN (%d vertex · Len=%s · sudut=%s°) — ' ...
                'interpolasi antar-keyframe di-recompute.'], size(V,1), i_polyFmt(r.lenCm,4), i_polyFmt(r.angleDeg,4)));
        else
            pivui.setStatus(fig, sprintf('Bidang sesar TERSIMPAN ke DX (%d vertex · Len=%s · sudut=%s°).', ...
                size(V,1), i_polyFmt(r.lenCm,4), i_polyFmt(r.angleDeg,4)));
        end
    else
        guidata(fig, h);
        pivui.setStatus(fig,'Bidang sesar tak disimpan (perlu baris DX + ≥2 vertex).');
    end
    i_faultPolyCleanup(fig);
    i_refreshDescTable(fig);   % Sudut/Len/Growth per-DX + Len# tabel sesar ter-update
end

function i_onClearFaultPoly(fig)
%I_ONCLEARFAULTPOLY  Hapus bidang sesar (vertices/angle/len) BARIS DX terpilih.
    h = guidata(fig);
    if isfield(h,'faultPolyOn') && h.faultPolyOn, i_faultPolyCleanup(fig); h = guidata(fig); end
    i_captureDescFromTable(fig); h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        pivui.setStatus(fig,'Pilih baris DESKRIPSI (DX) dulu.'); return;
    end
    r = rows{fullIdx};
    r.vertices = zeros(0,2); r.angleDeg = NaN; r.lenCm = NaN;
    rows{fullIdx} = r;
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    % (Tulis _desc.json DIBUANG: hapus bidang hanya update MEMORI+tabel; file
    %  ditulis HANYA saat 💾 Save eksplisit.)
    guidata(fig, h);
    i_refreshDescTable(fig);
    pivui.setStatus(fig, 'Bidang sesar DX dihapus (klik 💾 Save utk simpan).');
end

% =====================================================================
% TAPER ANGLE (kemiringan topografi) per-DX — alat garis 2-titik (hotkey 'w').
%   Meniru pola bidang sesar (i_onToggleFaultPoly) tapi: garis HIJAU topografi,
%   sudut = angleDegRelOf(garis, refHorizon), disimpan ke taperVerts/taperDeg
%   BARIS DESC terpilih. Model After Effects (sejajar bidang sesar): Ctrl+W di DX
%   kosong + interpolasi taper aktif -> COPY garis interpolasi (i_taperInterpVertsAtFrame);
%   commit -> keyframe + AUTO-RECOMPUTE (i_rebuildTaperTrack). Interpolasi via grain4Interp.
% =====================================================================
function i_onToggleTaper(fig, grabMode)
%I_ONTOGGLETAPER  Toggle alat TAPER utk DX terpilih. ON -> loncat ke frame DX +
%   gambar/tampilkan garis taper + label sudut LIVE. OFF -> simpan ke baris DX.
%   grabMode=true (Ctrl+G) -> seed ROI dari keyframe taper TERDEKAT LINTAS-F#
%   (kontinuitas overlap) alih-alih interpolasi F# sendiri. Commit identik (ke DX
%   F# aktif). Default false (Ctrl+W = alur After Effects intra-F#).
    if nargin < 2 || isempty(grabMode), grabMode = false; end
    % GUARD: callback bisa terpicu saat figure DIHANCURKAN (DestroyedObject Callback);
    % fig invalid / sedang di-destroy -> guidata/drawpolyline lempar. Abaikan.
    if isempty(fig) || ~ishghandle(fig), return; end
    if strcmp(get(fig,'BeingDeleted'),'on'), return; end
    h = guidata(fig);
    if isfield(h,'taperOn') && h.taperOn
        i_taperCommit(fig); return;
    end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum siap.'); i_syncTaperBtn(fig,false); return;
    end
    i_captureDescFromTable(fig); h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        pivui.setStatus(fig,'Pilih BARIS DESKRIPSI (DX) dulu — taper terikat titik pengamatan.');
        i_syncTaperBtn(fig,false); return;
    end
    r = rows{fullIdx};
    h.taperDxIdx = fullIdx;
    frameRef = r.frame;
    if ~(isscalar(frameRef) && isfinite(frameRef)), frameRef = pivcore.util.scalarOr(h.frame,1); end
    guidata(fig, h);
    try, pivui.grain4Shell.gotoFrame(fig, round(frameRef)); catch, end
    % Matikan MODE zoom/pan interaktif (kursor jadi crosshair) TAPI pertahankan view
    % zoom-in yg dikunci — sama spt input bidang sesar.
    i_suspendAxZoomForRoi(fig);
    h = guidata(fig);
    ax = h.axMain; col = [0.10 0.55 0.20];   % HIJAU topografi (ikut ter-ekspor)
    V = pivcore.io.grain4Desc.normVerts(r.taperVerts);
    seededFromInterp = false; grabInfo = '';
    if grabMode
        % Ctrl+G "grab from overlap": seed dari keyframe taper TERDEKAT — PRIORITAS F#
        % SENDIRI (frame terjauh/terdekat yg sudah digambar di sesar ini) lalu LINTAS-F#
        % (kontinuitas zona overlap). Baris DX ini sendiri dilewati (excludeFrame) supaya
        % tak seed dari dirinya; grab = niat eksplisit menyalin tetangga/keyframe lain.
        [Vg, srcF, srcFr] = i_taperGrabVertsCrossFault(h, r.frame, strtrim(char(r.fNum)), r.frame);
        if size(Vg,1) >= 2
            V = Vg; seededFromInterp = true;
            grabInfo = sprintf(' (grab dari %s@frame%d)', srcF, srcFr);
        end
    elseif size(V,1) < 2
        % COPY INTERPOLASI (gaya After Effects, sejajar bidang sesar Ctrl+Q): DX ini
        % BELUM punya garis taper sendiri (unsupervised) TAPI interpolasi taper sedang
        % AKTIF -> materialisasi bentuk INTERPOLASI HIJAU @frame DX ini jadi ROI editable.
        % Kalau tak diubah lalu Ctrl+W lagi -> tersimpan sbg keyframe identik; kalau
        % diedit -> jadi keyframe taper baru. Interpolasi TAK aktif -> ROI KOSONG
        % (gambar manual dari nol). Seed warisan "taper DX terdekat di bawah" DIBUANG.
        Vi = i_taperInterpVertsAtFrame(h, strtrim(char(r.fNum)), r.frame);
        if size(Vi,1) >= 2, V = Vi; seededFromInterp = true; end
    end
    roi = [];
    if size(V,1) >= 2
        try, roi = images.roi.Polyline('Parent',ax,'Position',V, ...
                'Color',col,'LineWidth',1.6,'MarkerSize',5); catch, roi = []; end
    end
    if isempty(roi)
        if pivui.quiet(), i_syncTaperBtn(fig,false); return; end
        try, roi = drawpolyline(ax,'Color',col,'LineWidth',1.6,'MarkerSize',5); catch, roi = []; end
        if isempty(roi) || ~isvalid(roi) || size(roi.Position,1) < 2
            try, if ~isempty(roi) && isvalid(roi), delete(roi); end, catch, end
            pivui.setStatus(fig,'Taper batal (perlu ≥2 vertex).'); i_syncTaperBtn(fig,false); return;
        end
    end
    h.roiTaper = roi;
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    h.taperLabel = text(ax, xl(1)+0.02*(xl(2)-xl(1)), yl(2)-0.11*(yl(2)-yl(1)), '', ...
        'Color',[0.10 0.40 0.15],'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[1 1 1 0.85],'Margin',3,'Tag','taperLabel', ...
        'VerticalAlignment','top','HorizontalAlignment','left');
    h.taperOn = true; guidata(fig, h);
    try
        addlistener(roi,'MovingROI', @(s,e2) i_updateTaper(fig));
        addlistener(roi,'ROIMoved',  @(s,e2) i_updateTaper(fig));
    catch, end
    i_syncTaperBtn(fig,true);
    i_updateTaper(fig);
    if grabMode && seededFromInterp
        pivui.setStatus(fig, sprintf(['Taper %s@frame%d ON — garis DI-GRAB%s. ' ...
            'Seret utk sesuaikan lalu Ctrl+G/Ctrl+W lagi utk KUNCI ke DX %s.'], ...
            strtrim(r.fNum), round(frameRef), grabInfo, strtrim(r.fNum)));
    elseif grabMode
        pivui.setStatus(fig, sprintf(['Taper %s@frame%d ON — TAK ada keyframe taper utk di-grab; ' ...
            'gambar/seret manual lalu Ctrl+G/Ctrl+W utk kunci.'], strtrim(r.fNum), round(frameRef)));
    elseif seededFromInterp
        pivui.setStatus(fig, sprintf(['Taper %s@frame%d ON — garis DI-COPY dari INTERPOLASI. ' ...
            'Seret utk edit (jadi keyframe baru) atau Ctrl+W lagi utk kunci apa adanya.'], ...
            strtrim(r.fNum), round(frameRef)));
    else
        pivui.setStatus(fig, sprintf(['Taper %s@frame%d ON — gambar/seret garis kemiringan topografi; ' ...
            'tekan Ctrl+W lagi utk KUNCI & simpan ke baris DX.'], strtrim(r.fNum), round(frameRef)));
    end
end

function i_onToggleTaperGrab(fig)
%I_ONTOGGLETAPERGRAB  Ctrl+G "grab from overlap": toggle alat taper dgn seed dari
%   keyframe taper TERDEKAT LINTAS-F# (kontinuitas topografi zona overlap). Bila alat
%   sudah ON -> commit (= i_onToggleTaper). Bila OFF -> buka dgn grabMode=true.
    if isempty(fig) || ~ishghandle(fig) || strcmp(get(fig,'BeingDeleted'),'on'), return; end  % guard destroy-callback
    h = guidata(fig);
    if isfield(h,'taperOn') && h.taperOn
        i_onToggleTaper(fig);            % commit (grabMode tak relevan saat OFF)
    else
        i_onToggleTaper(fig, true);      % buka dgn seed lintas-F#
    end
end

function i_updateTaper(fig)
%I_UPDATETAPER  Sudut taper LIVE (relatif ref horizontal) dari ROI -> label.
    h = guidata(fig);
    if ~(isfield(h,'taperOn') && h.taperOn), return; end
    if ~(isfield(h,'roiTaper') && ~isempty(h.roiTaper) && isvalid(h.roiTaper)), return; end
    V = []; try, V = h.roiTaper.Position; catch, end
    ang = pivcore.io.grain4Desc.angleDegRelOf(V, i_faultRefDeg(h));
    nV = size(pivcore.io.grain4Desc.normVerts(V),1);
    if isfield(h,'taperLabel') && ishghandle(h.taperLabel)
        set(h.taperLabel,'String', sprintf(' Taper = %s° ', i_polyFmt(ang,4)));
    end
    pivui.setStatus(fig, sprintf('Taper (topografi): %d vertex · sudut=%s°', nV, i_polyFmt(ang,4)));
end

function i_taperCommit(fig)
%I_TAPERCOMMIT  Toggle OFF: simpan taperVerts/taperDeg ke BARIS DX -> _desc.json.
%   DX PERTAMA F# = acuan -> COPY ke DX F# lain yg belum ber-taper. Refresh tabel.
    h = guidata(fig);
    V = zeros(0,2);
    if isfield(h,'roiTaper') && ~isempty(h.roiTaper) && isvalid(h.roiTaper)
        try, V = h.roiTaper.Position; catch, end
    end
    V = pivcore.io.grain4Desc.normVerts(V);
    idx = []; if isfield(h,'taperDxIdx'), idx = h.taperDxIdx; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if ~isempty(idx) && idx>=1 && idx<=numel(rows) && size(V,1) >= 2
        r = rows{idx};
        r.taperVerts = V;
        r.taperDeg   = pivcore.io.grain4Desc.angleDegRelOf(V, i_faultRefDeg(h));
        rows{idx} = r;
        % AUTO-COPY ACUAN DIBUANG (gaya After Effects; sejajar pensiun warisan bidang
        % sesar 2026-07-17): tiap keyframe taper diisi manual berjenjang, interpolasi
        % mengisi frame antara. Tak ada lagi bentuk lama yg membajak garis interpolasi.
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
        % (Tulis _desc.json DIBUANG 2026-07-18: commit taper hanya update descDoc di
        %  MEMORI + tabel; file ditulis HANYA saat 💾 Save eksplisit. GRAIN4 tak menyentuh
        %  disk tanpa perintah user.)
        guidata(fig, h);
        % AUTO-RECOMPUTE EVENT-DRIVEN (interpolasi taper always-on): baris DX ini kini
        % keyframe taper -> bangun-ulang sample. Rebuild SEMUA F# (murah; jumlah F#
        % kecil) supaya bayangan referensi F# tetangga juga ikut terkini. Recompute
        % HANYA di sini (commit) & saat hapus taper / exp-PSG load — BUKAN per-frame.
        uNc = pivcore.io.grain4Interp.normFtag(r.fNum);
        uiNumC = str2double(uNc);
        recomputed = isscalar(uiNumC) && isfinite(uiNumC);
        i_rebuildAllTaperTracks(fig);
        msg = sprintf('Taper TERSIMPAN ke DX (%d vertex · sudut=%s°).', size(V,1), i_polyFmt(r.taperDeg,4));
        if recomputed, msg = sprintf('%s Interpolasi taper di-recompute.', msg); end
        pivui.setStatus(fig, msg);
    else
        guidata(fig, h);
        pivui.setStatus(fig,'Taper tak disimpan (perlu baris DX + ≥2 vertex).');
    end
    i_taperCleanup(fig);
    i_refreshDescTable(fig);
end

function V = i_taperInterpVertsAtFrame(h, fNum, frame)
%I_TAPERINTERPVERTSATFRAME  Garis taper HASIL INTERPOLASI (unsupervised) utk (garis
%   PSG aktif, fNum) pada `frame`, DIHITUNG DARI keyframe taper TERKINI. Padanan
%   taper dari i_interpVertsAtFrameForFault (bidang sesar). Dipakai Ctrl+W utk "copy
%   interpolasi" ke DX kosong (gaya After Effects). Interpolasi taper ALWAYS-ON -> seed
%   selalu bisa selama ada >=2 keyframe. Kembalikan 0x2 bila: <2 keyframe valid, atau
%   frame di LUAR rentang keyframe (extrapolasi tak dilakukan — biar user gambar manual).
    V = zeros(0,2);
    if ~(isstruct(h) && isfield(h,'descDoc')), return; end
    uN = pivcore.io.grain4Interp.normFtag(fNum);   % 'F3'/'3'/3 -> '3'
    if isempty(uN), return; end
    uiNum = str2double(uN);
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    kf = i_taperKeyframesForFault(h, uiNum);
    [ok] = pivcore.io.grain4Interp.validateKeyframes(kf);
    if ~ok, return; end
    f = round(pivcore.util.scalarOr(frame, NaN));
    if ~isfinite(f), return; end
    fr = cellfun(@(e) round(e.frame), kf);
    [fr, ord] = sort(fr); kf = kf(ord);
    if f < fr(1) || f > fr(end), return; end   % di luar rentang -> no seed
    j = find(fr <= f, 1, 'last');
    if isempty(j), return; end
    if fr(j) == f
        V = pivcore.io.grain4Desc.normVerts(kf{j}.vertices); return;
    end
    j2 = j + 1;
    if j2 > numel(fr), V = pivcore.io.grain4Desc.normVerts(kf{j}.vertices); return; end
    t = (f - fr(j)) / (fr(j2) - fr(j));
    try
        V = pivcore.io.grain4Interp.lerpVerts(kf{j}.vertices, kf{j2}.vertices, t);
    catch
        V = zeros(0,2);
    end
end

function [V, srcF, srcFrame] = i_taperGrabVertsCrossFault(h, frameLive, activeFtag, excludeFrame)
%I_TAPERGRABVERTSCROSSFAULT  Vertex taper dari keyframe supervised TERDEKAT utk Ctrl+G
%   ("grab from overlap"). PRIORITAS DUA TAHAP: (1) keyframe taper di F# AKTIF SENDIRI
%   (activeFtag) TERDEKAT ke frameLive — utk kontinuitas dlm sesar sama (mis. loncat ke
%   POI pertama F9@250, grab dari keyframe F9 terjauh/terakhir yg sudah digambar). (2)
%   BILA F# aktif belum punya keyframe taper sama sekali -> cari LINTAS-F# (sesar lain
%   di garis PSG ini) terdekat (kontinuitas OVERLAP antar-sesar). Baris `excludeFrame`
%   (baris DX yg sedang di-grab) DILEWATI supaya tak seed dari dirinya. Objek topografi
%   KONTINU tapi jendela pengamatan per-sesar -> di overlap bentuk taper harus konsisten.
%   Kembalikan V (0x2 bila tak ada), srcF (tag F# sumber), srcFrame.
    V = zeros(0,2); srcF = ''; srcFrame = NaN;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(frameLive) && isfinite(frameLive)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    activeFtag = strtrim(char(activeFtag));
    if nargin < 4 || isempty(excludeFrame) || ~isfinite(excludeFrame), excludeFrame = NaN; end
    % TAHAP 1: F# aktif sendiri (kecuali baris yg sedang di-grab).
    [V, srcF, srcFrame] = i_nearestTaperKf(rows, frameLive, activeFtag, true, excludeFrame);
    if size(V,1) >= 2, return; end
    % TAHAP 2: lintas-F# (sesar lain) — F# aktif belum ada keyframe taper.
    [V, srcF, srcFrame] = i_nearestTaperKf(rows, frameLive, activeFtag, false, NaN);
end

function [V, srcF, srcFrame] = i_nearestTaperKf(rows, frameLive, ftagFilter, matchActive, excludeFrame)
%I_NEARESTTAPERKF  Keyframe taper (>=2 vertex) TERDEKAT ke frameLive di antara baris DX.
%   matchActive=true -> HANYA F# == ftagFilter (kecuali baris ber-frame excludeFrame).
%   matchActive=false -> HANYA F# != ftagFilter (sesar lain). Kembalikan V/srcF/srcFrame.
    V = zeros(0,2); srcF = ''; srcFrame = NaN; bestD = inf;
    ftagFilter = strtrim(char(ftagFilter));
    for k = 1:numel(rows)
        r = rows{k};
        ftag = strtrim(char(r.fNum));
        if isempty(ftag), continue; end
        isActive = ~isempty(ftagFilter) && strcmp(ftag, ftagFilter);
        if matchActive
            if ~isActive, continue; end
        else
            if isActive, continue; end
        end
        Vk = pivcore.io.grain4Desc.normVerts(r.taperVerts);
        if size(Vk,1) < 2, continue; end
        v = r.frame;
        if ~(isscalar(v) && isfinite(v)), continue; end
        if isfinite(excludeFrame) && round(v) == round(excludeFrame), continue; end   % lewati baris sendiri
        d = abs(round(v) - round(frameLive));
        if d < bestD
            bestD = d; V = Vk; srcF = ftag; srcFrame = round(v);
        end
    end
end

function i_taperCleanup(fig)
%I_TAPERCLEANUP  Hapus ROI + label taper, reset state alat.
    h = guidata(fig);
    if isfield(h,'roiTaper') && ~isempty(h.roiTaper)
        try, if isvalid(h.roiTaper), delete(h.roiTaper); end, catch, end
    end
    if isfield(h,'taperLabel') && ishghandle(h.taperLabel)
        try, delete(h.taperLabel); catch, end
    end
    h.roiTaper = []; h.taperLabel = []; h.taperOn = false; h.taperDxIdx = [];
    guidata(fig, h);
    i_syncTaperBtn(fig,false);
end

function i_syncTaperBtn(fig, on)
%I_SYNCTAPERBTN  Selaraskan Value togglebutton "📐 Taper (⌃W)" + "🔗 Grab (⌃G)"
%   (keduanya merefleksikan alat taper aktif; sama mesin ROI/commit).
    if ~ishghandle(fig), return; end   % callback fire saat figure ditutup -> diam
    h = guidata(fig);
    v = double(logical(on));
    if isfield(h,'btnTaper') && ishghandle(h.btnTaper)
        try, set(h.btnTaper,'Value', v); catch, end
    end
    if isfield(h,'btnTaperGrab') && ishghandle(h.btnTaperGrab)
        try, set(h.btnTaperGrab,'Value', v); catch, end
    end
end

% =====================================================================
%   TITIK NUKLEASI (SATU titik; POI=NUC-FSR)
%   Pola alat ROI: toggle -> loncat frame DX + drawpoint 1 titik -> KUNCI ->
%   simpan ke BARIS DX. Turunan disimpan:
%   nucDistCm  = jarak HORIZONTAL nukleasi -> garis INDENTER AWAL (datum X;
%                proyeksi ke sumbu shortening) × cmPerPx kalibrasi (X0/Lpos).
%   nucDepthPx/Cm = kedalaman tegak-lurus titik nukleasi ke ref horizontal.
%   Kolom "Nuk" tabel DESC jadi ✓. (Data LAMA garis 2-titik -> vertex-1 dipakai
%   sbg titik nukleasi; backward-compat via nucPointPx.)
% =====================================================================
function i_onToggleNucPt(fig)
%I_ONTOGGLENUCPT  Toggle alat titik nukleasi (1 titik) utk DX terpilih (POI=NUC-FSR).
%   ON -> loncat ke frame DX + drawpoint. OFF -> simpan.
    if isempty(fig) || ~ishghandle(fig), return; end
    if strcmp(get(fig,'BeingDeleted'),'on'), return; end
    h = guidata(fig);
    if isfield(h,'nucPtOn') && h.nucPtOn
        i_nucPtCommit(fig); return;
    end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum siap.'); i_syncNucPtBtn(fig,false); return;
    end
    i_captureDescFromTable(fig); h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        pivui.setStatus(fig,'Pilih BARIS DESKRIPSI (DX) dulu — titik nukleasi terikat DX.');
        i_syncNucPtBtn(fig,false); return;
    end
    r = rows{fullIdx};
    if ~i_isNucPoi(r.poi)
        pivui.setStatus(fig,'Titik nukleasi HANYA utk baris POI NUC-* (NUC-FSR/NUC-TF/NUC-BDF0/NUC-BDF1) atau X-FS. Set POI baris ini dulu.');
        i_syncNucPtBtn(fig,false); return;
    end
    h.nucPtDxIdx = fullIdx;
    frameRef = r.frame;
    if ~(isscalar(frameRef) && isfinite(frameRef)), frameRef = pivcore.util.scalarOr(h.frame,1); end
    guidata(fig, h);
    try, pivui.grain4Shell.gotoFrame(fig, round(frameRef)); catch, end
    i_suspendAxZoomForRoi(fig);
    h = guidata(fig);
    ax = h.axMain; col = [0.10 0.55 0.75];   % CYAN nukleasi (ikut ter-ekspor)
    p0 = pivcore.io.grain4Desc.nucPointPx(r.nucVerts);   % titik nukleasi tersimpan (vertex-1)
    roi = [];
    if ~isempty(p0)
        try, roi = images.roi.Point('Parent',ax,'Position',p0(1,:), ...
                'Color',col,'MarkerSize',9); catch, roi = []; end
    end
    if isempty(roi)
        if pivui.quiet(), i_syncNucPtBtn(fig,false); return; end
        try, roi = drawpoint(ax,'Color',col,'MarkerSize',9); catch, roi = []; end
        if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
            try, if ~isempty(roi) && isvalid(roi), delete(roi); end, catch, end
            pivui.setStatus(fig,'Titik nukleasi batal (perlu 1 titik).');
            i_syncNucPtBtn(fig,false); return;
        end
    end
    h.roiNucPt = roi;
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    h.nucPtLabel = text(ax, xl(1)+0.02*(xl(2)-xl(1)), yl(2)-0.18*(yl(2)-yl(1)), '', ...
        'Color',[0.05 0.30 0.45],'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[1 1 1 0.85],'Margin',3,'Tag','nucPtLabel', ...
        'VerticalAlignment','top','HorizontalAlignment','left');
    h.nucPtOn = true; guidata(fig, h);
    try
        addlistener(roi,'MovingROI', @(s,e2) i_updateNucPt(fig));
        addlistener(roi,'ROIMoved',  @(s,e2) i_updateNucPt(fig));
    catch, end
    i_syncNucPtBtn(fig,true);
    i_updateNucPt(fig);
    pivui.setStatus(fig, sprintf(['Titik nukleasi %s@frame%d ON — klik/seret SATU titik = ' ...
        'posisi nukleasi. Tekan Ctrl+R lagi utk KUNCI & simpan.'], ...
        strtrim(r.fNum), round(frameRef)));
end

function i_updateNucPt(fig)
%I_UPDATENUCPT  Metrik nukleasi LIVE dari ROI titik -> label (jarak horizontal ke
%   indenter awal + kedalaman).
    h = guidata(fig);
    if ~(isfield(h,'nucPtOn') && h.nucPtOn), return; end
    if ~(isfield(h,'roiNucPt') && ~isempty(h.roiNucPt) && isvalid(h.roiNucPt)), return; end
    P = []; try, P = h.roiNucPt.Position; catch, end
    m = i_nucPtMetrics(h, P);
    if isfield(h,'nucPtLabel') && ishghandle(h.nucPtLabel)
        set(h.nucPtLabel,'String', sprintf([' Jarak dr dinding pendorong = %s cm \n Kedalaman = %s cm '], ...
            i_polyFmt(m.distCm,3), i_polyFmt(m.depthCm,3)));
    end
    pivui.setStatus(fig, sprintf('Nukleasi: jarak(horiz)->dinding pendorong=%s cm · kedalaman=%s cm%s', ...
        i_polyFmt(m.distCm,3), i_polyFmt(m.depthCm,3), m.calibNote));
end

function tf = i_isNucPoi(poi)
%I_ISNUCPOI  True bila POI menerima INPUT TITIK (Ctrl+R): salah satu NUC-*
%   (NUC-FSR/NUC-TF/NUC-BDF0/NUC-BDF1/…) ATAU X-FS (FSR berhenti aktif -> titik
%   posisi X-FS juga dicatat). Titik disimpan di nucVerts + metrik jarak/kedalaman.
    pU = upper(strtrim(char(poi)));
    tf = ~isempty(pU) && (startsWith(pU, 'NUC-') || strcmp(pU, 'X-FS'));
end

function m = i_nucPtMetrics(h, P)
%I_NUCPTMETRICS  Metrik titik nukleasi (1 titik P = [x y], atau Nx2 lama -> vertex-1):
%   distCm   = JARAK HORIZONTAL nukleasi -> garis INDENTER AWAL (datum X = X0)
%              × cmPerPx KALIBRASI, proyeksi ke sumbu shortening (1-D).
%   depthPx/Cm = kedalaman tegak-lurus titik nukleasi ke ref horizontal.
%   cmPerPx KALIBRASI: dari pasangan (indenter awal=X0, dinding pembatas=Lpos)
%   ber-jarak L0_cm (experiment_geometry); fallback cmPerPx isotropik.
    m = struct('distCm',NaN,'depthPx',NaN,'depthCm',NaN,'distF1Cm',NaN,'p',[],'calibNote','');
    [cmPerPx, srcNote] = i_nucCmPerPx(h);
    m.calibNote = srcNote;
    p = pivcore.io.grain4Desc.nucPointPx(P);   % 1 titik (atau vertex-1 data lama)
    m.p = p;
    if ~isempty(p)
        % JARAK HORIZONTAL ke datum X (garis indenter awal).
        xRef = i_indenterInitX(h);
        dPxH = pivcore.io.grain4Desc.horizDistPx(p, xRef);
        if isfinite(dPxH) && isscalar(cmPerPx) && isfinite(cmPerPx) && cmPerPx > 0
            m.distCm = dPxH * cmPerPx;
        end
        % KEDALAMAN tegak-lurus ke ref horizontal.
        m.depthPx = i_nucDepthPxFor(h, p);
        if isfinite(m.depthPx) && isscalar(cmPerPx) && isfinite(cmPerPx) && cmPerPx > 0
            m.depthCm = m.depthPx * cmPerPx;
        end
    end
end

function R = i_modelRefs(h)
%I_MODELREFS  Referensi geometri EFEKTIF (turunan). PRIORITAS: dari KOTAK MODEL
%   4-titik (meta.modelBoxPts) -> sisi kiri=pendorong(X0), kanan=pembatas(Lpos),
%   atas=ref horizontal, bawah=base. FALLBACK: garis-garis terpisah (indenterInitPts/
%   limitWallPts/refHorizonPts/basePts) bila kotak belum diinput. Struct:
%     .xLeft   datum X dinding pendorong (px)  · .xRight  datum X dinding pembatas
%     .topPts  garis ref horizontal 2x2 (atas) · .botPts  garis base 2x2 (bawah)
%     .fromBox true bila sumber = kotak model.
    R = struct('xLeft',NaN,'xRight',NaN,'topPts',[],'botPts',[],'fromBox',false);
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    B = pivcore.io.grain4Desc.modelBoxPts(h.descDoc);
    if ~isempty(B) && size(B,1) >= 4
        s = pivcore.io.grain4Desc.boxSides(B);
        R.xLeft = s.xLeft; R.xRight = s.xRight;
        R.topPts = s.top;  R.botPts = s.bottom; R.fromBox = true;
        return;
    end
    % FALLBACK: garis-garis terpisah.
    Pi = pivcore.io.grain4Desc.metaLine(h.descDoc,'indenterInitPts');
    if ~isempty(Pi), R.xLeft = pivcore.io.grain4Desc.lineMeanX(Pi); end
    Pw = pivcore.io.grain4Desc.metaLine(h.descDoc,'limitWallPts');
    if ~isempty(Pw), R.xRight = pivcore.io.grain4Desc.lineMeanX(Pw); end
    R.topPts = pivcore.io.grain4Desc.refHorizonPts(h.descDoc);
    R.botPts = pivcore.io.grain4Desc.metaLine(h.descDoc,'basePts');
end

function xPx = i_indenterInitX(h)
%I_INDENTERINITX  Koordinat X (pixel) DATUM DINDING PENDORONG (sisi kiri kotak
%   model, atau garis indenter awal). NaN bila belum diset.
    xPx = NaN; R = i_modelRefs(h); if isfinite(R.xLeft), xPx = R.xLeft; end
end

function [cpp, note] = i_nucCmPerPx(h)
%I_NUCCMPERPX  cmPerPx utk pengukuran nukleasi. PRIORITAS: kalibrasi dari pasangan
%   (dinding pendorong=X0 kiri, dinding pembatas=Lpos kanan) ber-jarak L0_cm
%   (experiment_geometry). Fallback: cmPerPx isotropik. cpp + catatan sumber.
    cpp = NaN; note = '';
    R = i_modelRefs(h);
    L0 = NaN;
    if isfield(h,'df') && ~isempty(h.df)
        try, g = pivcore.export.frameCatalog.readGeomFull(h.df); L0 = g.L0_cm; catch, end
    end
    if isfinite(R.xLeft) && isfinite(R.xRight) && isfinite(L0) && L0 > 0
        cpp = pivcore.io.grain4Desc.cmPerPxFromRefPair(R.xLeft, R.xRight, L0);
        if isfinite(cpp) && cpp > 0
            if R.fromBox, note = ' [kalib kotak X0/Lpos]'; else, note = ' [kalib X0/Lpos]'; end
            return;
        end
    end
    cpp = i_faultCmPerPx(h);   % fallback isotropik
    if isfinite(cpp) && cpp > 0, note = ' [cmPerPx isotropik]'; end
end

function dPx = i_nucDepthPxFor(h, p)
%I_NUCDEPTHPXFOR  Kedalaman (PIXEL) titik nukleasi p ke REF HORIZONTAL (sisi ATAS
%   kotak model, atau garis ref horizontal tersimpan). Jarak tegak-lurus ke garis;
%   fallback garis lewat origin citra (sudut refHorizonDeg). NaN bila p tak valid.
    dPx = NaN;
    if numel(p) < 2 || any(~isfinite(p(1:2))), return; end
    R = i_modelRefs(h);
    if ~isempty(R.topPts) && size(R.topPts,1) >= 2
        dPx = pivcore.io.grain4Desc.pointToSegLineDistPx(p, R.topPts);
    else
        dPx = pivcore.io.grain4Desc.pointToLineDistPx(p, i_faultRefDeg(h));
    end
end

function i_recomputeAllNucDepths(fig)
%I_RECOMPUTEALLNUCDEPTHS  Hitung ulang SEMUA metrik nukleasi (nucDistCm horizontal
%   ke indenter awal + nucDepthPx/Cm ke ref horizontal) utk SEMUA baris DX
%   ber-titik-nukleasi (garis PSG aktif & lain). Dipanggil setelah ref horizontal /
%   indenter awal / dinding pembatas di-commit (datum & kalibrasi berubah). Baris
%   LAMA garis 2-titik -> vertex-1 dipakai. Update descDoc MEMORI (disk saat Save).
    h = guidata(fig);
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    psgIds = i_realPsgIds(h.descDoc);
    if isempty(psgIds), psgIds = {h.activePsgId}; end
    for pi = 1:numel(psgIds)
        rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psgIds{pi});
        changed = false;
        for k = 1:numel(rows)
            r = rows{k};
            Vn = pivcore.io.grain4Desc.normVerts(r.nucVerts);
            if size(Vn,1) < 1, continue; end       % perlu >=1 titik (single-point)
            m = i_nucPtMetrics(h, Vn);
            r.nucDistCm  = m.distCm;
            r.nucDepthPx = m.depthPx;
            r.nucDepthCm = m.depthCm;
            rows{k} = r; changed = true;
        end
        if changed
            h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psgIds{pi}, rows);
        end
    end
    guidata(fig, h);
end

function i_nucPtCommit(fig)
%I_NUCPTCOMMIT  Toggle OFF: simpan nucVerts + metrik ke BARIS DX -> descDoc
%   (memori; disk hanya saat 💾 Save). Refresh tabel (kolom Nuk -> ✓).
    h = guidata(fig);
    V = zeros(0,2);
    if isfield(h,'roiNucPt') && ~isempty(h.roiNucPt) && isvalid(h.roiNucPt)
        try, V = h.roiNucPt.Position; catch, end
    end
    V = pivcore.io.grain4Desc.normVerts(V);
    idx = []; if isfield(h,'nucPtDxIdx'), idx = h.nucPtDxIdx; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if ~isempty(idx) && idx>=1 && idx<=numel(rows) && size(V,1) >= 1
        r = rows{idx};
        p = pivcore.io.grain4Desc.nucPointPx(V);   % 1 titik nukleasi
        m = i_nucPtMetrics(h, p);
        r.nucVerts    = p;                       % SIMPAN 1 titik (1x2)
        r.nucDistCm   = m.distCm;
        r.nucDepthPx  = m.depthPx;
        r.nucDepthCm  = m.depthCm;
        rows{idx} = r;
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
        guidata(fig, h);
        pivui.setStatus(fig, sprintf(['Titik nukleasi TERSIMPAN ke DX — jarak(horiz)->dinding pendorong=%s cm · ' ...
            'kedalaman=%s cm%s.'], i_polyFmt(m.distCm,3), i_polyFmt(m.depthCm,3), m.calibNote));
    else
        guidata(fig, h);
        pivui.setStatus(fig,'Titik tak disimpan (perlu baris DX POI NUC-*/X-FS + 1 titik).');
    end
    i_nucPtCleanup(fig);
    i_refreshDescTable(fig);
end

function i_onClearNucPt(fig)
%I_ONCLEARNUCPT  Hapus titik nukleasi (nucVerts + metrik) BARIS DX terpilih.
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    if isfield(h,'nucPtOn') && h.nucPtOn, i_nucPtCleanup(fig); h = guidata(fig); end
    i_captureDescFromTable(fig); h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        pivui.setStatus(fig,'Pilih baris DX dulu.'); return;
    end
    r = rows{fullIdx};
    r.nucVerts = zeros(0,2); r.nucDistCm = NaN; r.nucDepthPx = NaN; r.nucDepthCm = NaN; r.nucDistF1Cm = NaN;
    rows{fullIdx} = r;
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    guidata(fig, h);
    pivui.setStatus(fig,'Titik nukleasi DIHAPUS dari baris DX.');
    i_refreshDescTable(fig);
end

function i_nucPtCleanup(fig)
%I_NUCPTCLEANUP  Hapus ROI + label titik nukleasi, reset state alat.
    h = guidata(fig);
    if isfield(h,'roiNucPt') && ~isempty(h.roiNucPt)
        try, if isvalid(h.roiNucPt), delete(h.roiNucPt); end, catch, end
    end
    if isfield(h,'nucPtLabel') && ishghandle(h.nucPtLabel)
        try, delete(h.nucPtLabel); catch, end
    end
    h.roiNucPt = []; h.nucPtLabel = []; h.nucPtOn = false; h.nucPtDxIdx = [];
    guidata(fig, h);
    i_syncNucPtBtn(fig,false);
end

function i_syncNucPtBtn(fig, on)
%I_SYNCNUCPTBTN  Selaraskan Value togglebutton "🎯 Titik nukleasi".
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    if isfield(h,'btnNucPt') && ishghandle(h.btnNucPt)
        try, set(h.btnNucPt,'Value', double(logical(on))); catch, end
    end
end

function kf = i_taperKeyframesForFault(h, uiNum)
%I_TAPERKEYFRAMESFORFAULT  KEYFRAME taper sesar ber-uiNum (garis PSG aktif): tiap
%   DX yg PUNYA garis taper (taperVerts>=2) -> {frame, vertices}. Urut frame
%   menaik. Cell of struct ({} bila <2 keyframe -> tak bisa interpolasi).
    kf = {};
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    fr = [];
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmp(strtrim(char(r.fNum)), tgt), continue; end
        V = pivcore.io.grain4Desc.normVerts(r.taperVerts);
        v = r.frame;
        if size(V,1) < 2 || ~(isscalar(v) && isfinite(v)), continue; end
        kf{end+1} = struct('frame',round(v),'vertices',V); %#ok<AGROW>
        fr(end+1) = round(v); %#ok<AGROW>
    end
    if numel(kf) >= 2, [~, ord] = sort(fr); kf = kf(ord); end
end

function [ok, nSamp, nKf, msg] = i_rebuildTaperTrack(fig, uiNum)
%I_REBUILDTAPERTRACK  Bangun-ulang sample interpolasi TAPER (garis PSG aktif, uiNum)
%   dari keyframe taper TERKINI -> buildSamples -> simpan di MEMORI (h.taperSamples
%   map) + track KERJA h.taperInterpDoc (sidecar _taperinterp.json, ditulis saat Save
%   Progress). Padanan taper dari i_rebuildInterpTrack (bidang sesar). EVENT-DRIVEN:
%   dipanggil i_taperCommit & i_onClearTaper (recompute saat keyframe berubah, BUKAN
%   per-frame). Interpolasi taper always-on. Kembalikan ok/#sample/#keyframe/pesan.
    ok = false; nSamp = 0; nKf = 0; msg = '';
    h = guidata(fig);
    kf = i_taperKeyframesForFault(h, uiNum);
    nKf = numel(kf);
    key = sprintf('%s|F%d', h.activePsgId, round(uiNum));
    [vok, vmsg] = pivcore.io.grain4Interp.validateKeyframes(kf);
    if ~vok
        % KEYFRAME turun <2 (mis. semua dihapus) -> interpolasi TAK boleh jalan.
        % HAPUS cache lama supaya sample interpolasi tak PERSISTEN setelah keyframe
        % dihapus (aturan: interpolasi hanya bila ujung2 ada data / >=2 keyframe).
        i_clearTaperTrack(fig, uiNum, key);
        msg = vmsg; return;
    end
    cmPerPx = i_faultCmPerPx(h); refDeg = i_faultRefDeg(h);
    try
        samples = pivcore.io.grain4Interp.buildSamples(kf, cmPerPx, refDeg);
    catch ME
        i_clearTaperTrack(fig, uiNum, key);
        msg = ME.message; return;
    end
    if ~(isfield(h,'taperSamples') && isa(h.taperSamples,'containers.Map'))
        h.taperSamples = containers.Map('KeyType','char','ValueType','any');
    end
    kfFrames = cellfun(@(e)e.frame,kf);
    h.taperSamples(key) = struct('samples',{samples}, 'keyFrames', kfFrames);
    % SIDECAR KERJA (_taperinterp.json): track taper LENGKAP per-frame utk plot evolusi.
    % Diperbarui event-driven (di sini) + ditulis ke disk saat Save Progress. Terpisah
    % dari tabel DESKRIPSI (keyframe) & JSON laporan (nilai per-POI).
    if ~(isfield(h,'taperInterpDoc') && isstruct(h.taperInterpDoc))
        h.taperInterpDoc = pivcore.io.grain4TaperInterp.emptyDoc(h.df);
    end
    try
        h.taperInterpDoc = pivcore.io.grain4TaperInterp.setTrackFor(h.taperInterpDoc, ...
            h.activePsgId, sprintf('F%d',round(uiNum)), samples, kfFrames);
    catch, end
    guidata(fig, h);
    nSamp = numel(samples); ok = true;
end

function i_clearTaperTrack(fig, uiNum, key)
%I_CLEARTAPERTRACK  Hapus track interpolasi taper F# (garis PSG aktif) dari cache
%   MEMORI (h.taperSamples) + sidecar kerja (h.taperInterpDoc). Dipanggil saat keyframe
%   turun <2 supaya interpolasi TAK persisten setelah keyframe dihapus. `key` opsional.
    h = guidata(fig);
    if nargin < 3 || isempty(key)
        psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
        key = sprintf('%s|F%d', psg, round(uiNum));
    end
    if isfield(h,'taperSamples') && isa(h.taperSamples,'containers.Map') && isKey(h.taperSamples, key)
        try, remove(h.taperSamples, key); catch, end
    end
    if isfield(h,'taperInterpDoc') && isstruct(h.taperInterpDoc)
        try
            h.taperInterpDoc = pivcore.io.grain4TaperInterp.clearTrackFor(h.taperInterpDoc, ...
                h.activePsgId, sprintf('F%d',round(uiNum)));
        catch, end
    end
    guidata(fig, h);
end

function i_drawTaperInterp(fig)
%I_DRAWTAPERINTERP  Overlay interpolasi taper (ALWAYS-ON) di axMain saat scrub:
%   (1) F# AKTIF -> garis HIJAU (Tag 'taperInterp'); (2) SETIAP F# TETANGGA yg
%   overlap di frame ini -> garis interpolasi taper PINK CERAH putus-putus + label F#
%   di TENGAH garis (Tag 'taperInterpRef') sbg REFERENSI KONTINUITAS (bantu lihat frame
%   aktif menyimpang & perlu commit/edit; TIDAK ikut perhitungan/ekspor). Frame yg
%   PERSIS keyframe F# aktif dilewati utk garis hijau (taper manual sudah tampil).
%   Sample dari cache h.taperSamples (recompute event-driven; lihat i_rebuildTaperTrack).
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if ~(isfield(h,'taperSamples') && isa(h.taperSamples,'containers.Map')), return; end
    try, delete(findall(h.axMain,'Tag','taperInterp')); catch, end
    try, delete(findall(h.axMain,'Tag','taperInterpRef')); catch, end
    try, delete(findall(h.axMain,'Tag','taperInterpRefLeader')); catch, end
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    [fA, idxA] = pivui.grain5Model.activeFault(h);
    uActive = NaN;
    if idxA >= 1, uActive = round(pivui.grain5Model.faultUiNum(fA)); end
    ax = h.axMain; washold = ishold(ax); hold(ax,'on');
    prefix = sprintf('%s|F', h.activePsgId);
    keys = h.taperSamples.keys;
    nRef = 0;
    for ki = 1:numel(keys)
        key = keys{ki};
        if ~startsWith(key, prefix), continue; end   % hanya garis PSG aktif
        uN = str2double(key(numel(prefix)+1:end));
        if ~(isscalar(uN) && isfinite(uN)), continue; end
        S = h.taperSamples(key);
        % frame PERSIS keyframe F# ini -> garis manual sudah ada; utk F# AKTIF dilewati
        % (hijau tak dobel). Utk tetangga TETAP gambar bayangan (referensi kontinu).
        isActive = isfinite(uActive) && round(uN) == uActive;
        if isActive && isfield(S,'keyFrames') && any(round(S.keyFrames) == frameLive), continue; end
        V = i_taperSampleAtFrame(S.samples, frameLive);
        if size(V,1) < 2, continue; end
        if isActive
            plot(ax, V(:,1), V(:,2), '-', 'Color',[0.10 0.75 0.30], 'LineWidth',2.2, ...
                'Marker','o','MarkerSize',4,'MarkerFaceColor',[0.10 0.75 0.30], ...
                'Tag','taperInterp','Clipping','on');
        else
            % Bayangan referensi F# tetangga: PINK CERAH garis PENUH TEBAL (kontras di
            % atas gambar PIV abu/berbintik) sbg panduan kontinuitas. Label F# di TENGAH
            % garis, diangkat ~beberapa puluh px ke ATAS + garis penunjuk (gaya HW-F#).
            pink = [1 0.10 0.60];
            plot(ax, V(:,1), V(:,2), '-', 'Color',pink, 'LineWidth',1.8, ...
                'Tag','taperInterpRef','Clipping','on');
            try
                % titik TENGAH garis (interpolasi sepanjang polyline).
                mid = i_polylineMidpoint(V);
                yl = ylim(ax); off = 0.06 * (yl(2)-yl(1));   % jarak label ke ATAS garis (VISUAL)
                % "atas visual": YDir normal -> y lebih BESAR; YDir reverse -> y lebih KECIL.
                if strcmp(get(ax,'YDir'),'reverse'), yLab = mid(2) - off; else, yLab = mid(2) + off; end
                plot(ax, [mid(1) mid(1)], [mid(2) yLab], '-', 'Color',[pink 0.7], ...
                    'LineWidth',0.9, 'Tag','taperInterpRefLeader','HitTest','off','PickableParts','none');
                text(ax, mid(1), yLab, sprintf('F%d', round(uN)), ...
                    'Color',[1 1 1],'FontSize',7,'FontWeight','bold', ...
                    'BackgroundColor',pink,'EdgeColor',[0 0 0],'Margin',1, ...
                    'HorizontalAlignment','center','VerticalAlignment','middle', ...
                    'Tag','taperInterpRefLeader','HitTest','off','PickableParts','none');
            catch, end
            nRef = nRef + 1;
        end
    end
    if ~washold, hold(ax,'off'); end
    % INDIKATOR jumlah keyframe taper F# aktif (bantu tahu kapan interpolasi jalan).
    i_taperKfIndicator(fig, uActive, nRef);
end

function i_taperKfIndicator(fig, uActive, nRef)
%I_TAPERKFINDICATOR  Status ringkas jumlah keyframe taper F# AKTIF + bayangan referensi
%   tetangga -> bantu user tahu kapan interpolasi jalan (butuh >=2 keyframe) & bahwa
%   ada panduan F# lain. Non-invasif: hanya set status strip.
    if ~(isscalar(uActive) && isfinite(uActive)), return; end
    h = guidata(fig);
    kf = i_taperKeyframesForFault(h, uActive);
    nkf = numel(kf);
    if nkf >= 2
        msg = sprintf('Taper F%d: %d keyframe -> interpolasi AKTIF (garis hijau).', round(uActive), nkf);
    elseif nkf == 1
        msg = sprintf(['Taper F%d: BARU 1 keyframe -> interpolasi belum jalan (butuh >=2). ' ...
            'Ctrl+G di frame lain utk grab dari F# tetangga.'], round(uActive));
    else
        msg = sprintf('Taper F%d: BELUM ada keyframe. Ctrl+W gambar / Ctrl+G grab dari F# tetangga.', round(uActive));
    end
    if nRef > 0, msg = sprintf('%s [%d bayangan referensi F# tetangga (pink)].', msg, nRef); end
    pivui.setStatus(fig, msg);
end

function m = i_polylineMidpoint(V)
%I_POLYLINEMIDPOINT  Titik pd 50% panjang busur polyline V (Nx2). Utk menaruh label
%   di TENGAH garis (gaya HW-F#). Fallback: rata-rata vertex bila panjang 0.
    m = [NaN NaN];
    V = pivcore.io.grain4Desc.normVerts(V);
    if size(V,1) < 2, if ~isempty(V), m = V(1,:); end, return; end
    seg = sqrt(sum(diff(V,1,1).^2, 2));
    L = sum(seg);
    if ~(L > 0), m = mean(V,1); return; end
    half = L/2; acc = 0;
    for i = 1:numel(seg)
        if acc + seg(i) >= half
            t = (half - acc) / seg(i);
            m = V(i,:) + t*(V(i+1,:) - V(i,:));
            return;
        end
        acc = acc + seg(i);
    end
    m = V(end,:);
end

function i_rebuildAllTaperTracks(fig)
%I_REBUILDALLTAPERTRACKS  Bangun-ulang cache sample interpolasi taper utk SEMUA F#
%   (garis PSG aktif) yg punya >=2 keyframe taper. Dipanggil saat exp dimuat / garis
%   PSG ganti / commit / hapus taper. Event-driven; TIDAK per-frame.
%   BERSIHKAN DULU cache PSG aktif -> isi ulang HANYA F# valid (>=2 keyframe) supaya
%   TAK ADA sample basi setelah keyframe/baris dihapus (aturan: interpolasi hanya bila
%   >=2 keyframe). i_rebuildTaperTrack juga hapus per-F# saat gagal validasi.
    h = guidata(fig);
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    % 1) buang SEMUA cache PSG aktif (key '<psg>|F...') supaya F# yg barisnya sudah
    %    hilang total tak meninggalkan sample basi.
    if isfield(h,'taperSamples') && isa(h.taperSamples,'containers.Map')
        prefix = sprintf('%s|F', psg);
        for kk = h.taperSamples.keys
            if startsWith(kk{1}, prefix), try, remove(h.taperSamples, kk{1}); catch, end, end
        end
        guidata(fig, h);
    end
    % 2) isi ulang hanya F# yg VALID (>=2 keyframe); gagal -> i_rebuildTaperTrack hapus.
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    seen = [];
    for k = 1:numel(rows)
        uNc = pivcore.io.grain4Interp.normFtag(rows{k}.fNum);
        uiNum = str2double(uNc);
        if ~(isscalar(uiNum) && isfinite(uiNum)), continue; end
        if any(seen == round(uiNum)), continue; end
        seen(end+1) = round(uiNum); %#ok<AGROW>
        i_rebuildTaperTrack(fig, uiNum);   % gagal (<2 kf) -> cache + sidecar F# itu dihapus
    end
end

function V = i_taperSampleAtFrame(samples, frame)
%I_TAPERSAMPLEATFRAME  Vertices sample pada frame (cari yg .frame==frame). [] bila
%   tak ada.
    V = zeros(0,2);
    samples = pivcore.io.grain4Interp.tocell(samples);
    for k = 1:numel(samples)
        s = samples{k};
        if isstruct(s) && isfield(s,'frame') && round(s.frame)==round(frame)
            if isfield(s,'vertices'), V = pivcore.io.grain4Desc.normVerts(s.vertices); end
            return;
        end
    end
end

function [deg, status, V, srcU] = i_taperValueForRow(h, r)
%I_TAPERVALUEFORROW  Nilai taper utk baris DESC r (utk kolom T° tampilan + warna sel):
%   status 'super' = baris punya taperVerts sendiri (keyframe supervised, tersimpan;
%   sel BIRU) -> deg = r.taperDeg. status 'auto' = kosong TAPI ada interpolasi @frame
%   (F# SENDIRI dulu, fallback F# TETANGGA terdekat overlap; sel HIJAU) -> deg dari
%   sample cache. status 'empty' = tak ada data & tak ter-cakup interpolasi (sel MERAH).
%   V = vertices sumber (utk seed). srcU = uiNum sumber interpolasi (NaN bila super/empty).
    deg = NaN; status = 'empty'; V = zeros(0,2); srcU = NaN;
    if ~isstruct(r), return; end
    Vs = pivcore.io.grain4Desc.normVerts(r.taperVerts);
    if size(Vs,1) >= 2
        status = 'super'; V = Vs;
        deg = NaN; if isfield(r,'taperDeg'), deg = r.taperDeg; end
        if ~isfinite(deg), deg = pivcore.io.grain4Desc.angleDegRelOf(Vs, i_faultRefDeg(h)); end
        return;
    end
    frame = r.frame;
    if ~(isscalar(frame) && isfinite(frame)), return; end
    if ~(isfield(h,'taperSamples') && isa(h.taperSamples,'containers.Map')), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    uSelf = str2double(pivcore.io.grain4Interp.normFtag(r.fNum));
    % 1) F# SENDIRI: sample interpolasi @frame.
    if isscalar(uSelf) && isfinite(uSelf)
        key = sprintf('%s|F%d', psg, round(uSelf));
        if isKey(h.taperSamples, key)
            S = h.taperSamples(key);
            Vi = i_taperSampleAtFrame(S.samples, frame);
            if size(Vi,1) >= 2
                V = Vi; status = 'auto'; srcU = round(uSelf);
                deg = pivcore.io.grain4Desc.angleDegRelOf(Vi, i_faultRefDeg(h)); return;
            end
        end
    end
    % 2) TETANGGA terdekat: F# lain yg sample-nya mencakup frame (jarak keyFrames terkecil).
    prefix = sprintf('%s|F', psg);
    keys = h.taperSamples.keys; bestD = inf;
    for ki = 1:numel(keys)
        key = keys{ki};
        if ~startsWith(key, prefix), continue; end
        uN = str2double(key(numel(prefix)+1:end));
        if ~(isscalar(uN) && isfinite(uN)), continue; end
        if isscalar(uSelf) && isfinite(uSelf) && round(uN)==round(uSelf), continue; end
        S = h.taperSamples(key);
        Vi = i_taperSampleAtFrame(S.samples, frame);
        if size(Vi,1) < 2, continue; end
        d = 0;
        if isfield(S,'keyFrames') && ~isempty(S.keyFrames)
            d = min(abs(round(S.keyFrames) - round(frame)));
        end
        if d < bestD
            bestD = d; V = Vi; status = 'auto'; srcU = round(uN);
            deg = pivcore.io.grain4Desc.angleDegRelOf(Vi, i_faultRefDeg(h));
        end
    end
end

function i_onClearTaper(fig)
%I_ONCLEARTAPER  Hapus taper (taperVerts/taperDeg) BARIS DX terpilih.
    if isempty(fig) || ~ishghandle(fig) || strcmp(get(fig,'BeingDeleted'),'on'), return; end  % guard destroy-callback
    h = guidata(fig);
    if isfield(h,'taperOn') && h.taperOn, i_taperCleanup(fig); h = guidata(fig); end
    i_captureDescFromTable(fig); h = guidata(fig);
    fullIdx = i_descSelFullIdx(h);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(fullIdx) || fullIdx < 1 || fullIdx > numel(rows)
        pivui.setStatus(fig,'Pilih baris DESKRIPSI (DX) dulu.'); return;
    end
    r = rows{fullIdx};
    r.taperVerts = zeros(0,2); r.taperDeg = NaN;
    rows{fullIdx} = r;
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, h.activePsgId, rows);
    % (Tulis _desc.json DIBUANG: hapus taper hanya update MEMORI+tabel; file
    %  ditulis HANYA saat 💾 Save eksplisit.)
    guidata(fig, h);
    % AUTO-RECOMPUTE EVENT-DRIVEN: keyframe taper berkurang -> bangun-ulang SEMUA F#
    % (bayangan referensi tetangga ikut terkini).
    i_rebuildAllTaperTracks(fig);
    i_refreshDescTable(fig);
    pivui.setStatus(fig, 'Taper DX dihapus (klik 💾 Save utk simpan).');
end

function kf = i_interpKeyframesForFault(h, uiNum)
%I_INTERPKEYFRAMESFORFAULT  Kumpulkan KEYFRAME interpolasi sesar ber-uiNum (garis
%   PSG aktif): tiap baris DESC (DX) yg PUNYA bidang tergambar (vertices>=2) ->
%   struct {frame, vertices}. Diurutkan frame menaik. NUC-FSR/X-FS otomatis
%   terlewati (vertices kosong). Cell of struct (bisa {} bila <1 keyframe).
    kf = {};
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    fr = [];
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmp(strtrim(r.fNum), tgt), continue; end
        V = pivcore.io.grain4Desc.normVerts(r.vertices);
        v = r.frame;
        if size(V,1) < 2 || ~(isscalar(v) && isfinite(v)), continue; end
        kf{end+1} = struct('frame',round(v),'vertices',V); %#ok<AGROW>
        fr(end+1) = round(v); %#ok<AGROW>
    end
    if numel(kf) >= 2, [~, ord] = sort(fr); kf = kf(ord); end
end

function V = i_interpVertsAtFrameForFault(h, fNum, frame)
%I_INTERPVERTSATFRAMEFORFAULT  Bentuk bidang sesar HASIL INTERPOLASI (unsupervised)
%   utk (garis PSG aktif, fNum) pada `frame`, DIHITUNG DARI supervised keyframe
%   TERKINI (bukan sample lama) supaya selalu mencerminkan editan keyframe. Dipakai
%   Ctrl+Q utk "copy interpolasi" ke DX kosong (gaya After Effects). Kembalikan 0x2
%   bila: interpolasi TAK aktif (h.interpOn false), <2 keyframe valid, atau frame di
%   LUAR rentang keyframe (extrapolasi tak dilakukan — biar user gambar manual).
    V = zeros(0,2);
    if ~(isstruct(h) && isfield(h,'interpOn') && h.interpOn), return; end
    uN = pivcore.io.grain4Interp.normFtag(fNum);   % 'F3'/'3'/3 -> '3'
    if isempty(uN), return; end
    uiNum = str2double(uN);
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    kf = i_interpKeyframesForFault(h, uiNum);
    [ok] = pivcore.io.grain4Interp.validateKeyframes(kf);
    if ~ok, return; end
    f = round(pivcore.util.scalarOr(frame, NaN));
    if ~isfinite(f), return; end
    % Susun (frame, vertices) menaik.
    fr = cellfun(@(e) round(e.frame), kf);
    [fr, ord] = sort(fr); kf = kf(ord);
    if f < fr(1) || f > fr(end), return; end   % di luar rentang -> no seed
    j = find(fr <= f, 1, 'last');
    if isempty(j), return; end
    if fr(j) == f
        V = pivcore.io.grain4Desc.normVerts(kf{j}.vertices); return;
    end
    j2 = j + 1;
    if j2 > numel(fr), V = pivcore.io.grain4Desc.normVerts(kf{j}.vertices); return; end
    t = (f - fr(j)) / (fr(j2) - fr(j));
    try
        V = pivcore.io.grain4Interp.lerpVerts(kf{j}.vertices, kf{j2}.vertices, t);
    catch
        V = zeros(0,2);   % jumlah vertex beda antar keyframe -> tak bisa lerp
    end
end

function [f0, f1, Vlast, xfsExcl] = i_faultLifeAndLastAct(h, uiNum)
%I_FAULTLIFEANDLASTACT  Rentang AKTIF sesar ber-uiNum (garis PSG aktif) + bentuk
%   ACT-FSR TERAKHIR. Dipakai BAYANGAN MERAH sesar-lain (visual aid hitung sesar
%   aktif). Rentang [f0 f1] + flag xfsExcl DIAMBIL DARI ENGINE YANG SAMA dgn kolom
%   Deteksi (pivcore.io.grain4Desc.faultActiveRange) -> bayangan merah & angka Deteksi
%   TAK PERNAH divergen. xfsExcl=true berarti frame X-FS EKSKLUSIF (sesar SUDAH tak
%   aktif di frame X-FS; pemanggil pakai frameLive < f1). Vlast = vertices baris
%   ACT-FSR ber-frame TERBESAR yg punya bidang (>=2 vertex). f0/f1 NaN & Vlast 0x2
%   bila data tak cukup / sesar tak pernah "terbentuk".
    f0 = NaN; f1 = NaN; Vlast = zeros(0,2); xfsExcl = false;
    if ~(isstruct(h) && isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    if ~(isscalar(uiNum) && isfinite(uiNum)), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    tgt = sprintf('F%d', round(uiNum));
    rowsOfFault = {}; bestActFr = -inf;
    for k = 1:numel(rows)
        r = rows{k};
        if ~strcmp(strtrim(char(r.fNum)), tgt), continue; end
        rowsOfFault{end+1} = r; %#ok<AGROW>
        poiU = upper(strtrim(char(r.poi)));
        v = r.frame; hasFr = isscalar(v) && isfinite(v);
        % ACT-FSR terakhir ber-bidang -> sumber bentuk bayangan.
        if strcmp(poiU,'ACT-FSR') && hasFr
            V = pivcore.io.grain4Desc.normVerts(r.vertices);
            if size(V,1) >= 2 && round(v) > bestActFr
                bestActFr = round(v); Vlast = V;
            end
        end
    end
    % Rentang aktif = SUMBER TUNGGAL dgn Deteksi (NUC & X-FS eksklusif; f_start =
    % NUC-* PERTAMA apa pun — PRP TIDAK dipakai, POI PRP-FSR dipensiunkan).
    % ok=false -> f0/f1 tetap NaN (bayangan tak tampil).
    [fr0, fr1, ok, xe] = pivcore.io.grain4Desc.faultActiveRange(rowsOfFault);
    if ok, f0 = fr0; f1 = fr1; xfsExcl = xe; end
end

function [ok, nSamp, nKf, msg] = i_rebuildInterpTrack(fig, uiNum)
%I_REBUILDINTERPTRACK  Bangun-ulang track interpolasi (garis PSG aktif, uiNum) dari
%   supervised keyframe TERKINI -> buildSamples -> setTrackFor -> tulis
%   _faultinterp.json. Dipakai i_faultPolyCommit (recompute otomatis saat keyframe
%   di-commit; interpolasi ALWAYS-ON). Kembalikan ok/#sample/#keyframe/pesan.
    ok = false; nSamp = 0; nKf = 0; msg = '';
    h = guidata(fig);
    kf = i_interpKeyframesForFault(h, uiNum);
    nKf = numel(kf);
    [vok, vmsg] = pivcore.io.grain4Interp.validateKeyframes(kf);
    if ~vok, msg = vmsg; return; end
    cmPerPx = i_faultCmPerPx(h); refDeg = i_faultRefDeg(h);
    try
        samples = pivcore.io.grain4Interp.buildSamples(kf, cmPerPx, refDeg);
    catch ME
        msg = ME.message; return;
    end
    kfFrames = cellfun(@(e) e.frame, kf);
    if ~(isfield(h,'interpDoc') && isstruct(h.interpDoc)), h.interpDoc = pivcore.io.grain4Interp.emptyDoc(h.df); end
    h.interpDoc = pivcore.io.grain4Interp.setTrackFor(h.interpDoc, h.activePsgId, sprintf('F%d',round(uiNum)), samples, kfFrames);
    guidata(fig, h);
    if isfield(h,'df') && ~isempty(h.df)
        try, pivcore.io.grain4Interp.write(h.df, h.interpDoc); catch, end
    end
    ok = true; nSamp = numel(samples); nKf = numel(kf);
end

function i_drawInterpPolylines(fig)
%I_DRAWINTERPPOLYLINES  Overlay EVOLUSI: bila h.interpOn, tiap track sesar (garis
%   PSG aktif) yg punya sample pada frame live -> gambar polyline CYAN di axMain
%   (Tag 'interpFaultPoly'). Frame yg SUDAH keyframe (bidang manual hitam) dilewati
%   supaya tak dobel. Redraw tiap render.
    h = guidata(fig);
    if ~(isfield(h,'interpOn') && h.interpOn), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if ~(isfield(h,'interpDoc') && isstruct(h.interpDoc)), return; end
    try, delete(findall(h.axMain,'Tag','interpFaultPoly')); catch, end
    ax = h.axMain;
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    tracks = pivcore.io.grain4Interp.tocell(h.interpDoc.tracks);
    if isempty(tracks), return; end
    psg = ''; if isfield(h,'activePsgId'), psg = h.activePsgId; end
    washold = ishold(ax); hold(ax,'on');
    for k = 1:numel(tracks)
        e = pivcore.io.grain4Interp.normEntry(tracks{k});
        if ~strcmp(pivcore.io.grain4Interp.tostr(e.psgId), pivcore.io.grain4Interp.tostr(psg)), continue; end
        % Lewati frame yg PERSIS keyframe (polyline hitam manual sudah tampil).
        if any(round(e.keyFrames) == frameLive), continue; end
        V = pivcore.io.grain4Interp.vertsAtFrame(e, frameLive);
        if size(V,1) < 2, continue; end
        plot(ax, V(:,1), V(:,2), '-', 'Color',[0 0.75 0.85], 'LineWidth',1.6, ...
            'Marker','o', 'MarkerSize',3, 'MarkerFaceColor',[0 0.75 0.85], ...
            'Tag','interpFaultPoly', 'Clipping','on');
    end
    if ~washold, hold(ax,'off'); end
end

function i_drawOtherFaultShadows(fig)
%I_DRAWOTHERFAULTSHADOWS  BAYANGAN MERAH sesar LAIN (visual aid hitung sesar aktif).
%   Saat overlay Evolusi ON (h.interpOn), utk SETIAP sesar SELAIN yg sedang aktif di
%   garis PSG aktif: bila frame live berada di dalam rentang HIDUP-nya (PRP-FSR..X-FS
%   via i_faultLifeAndLastAct) -> gambar polyline MERAH putus-putus = SALINAN vertex
%   ACT-FSR TERAKHIR sesar itu (STATIS). Ini murni VISUAL — TIDAK disimpan, TIDAK ikut
%   perhitungan/ekspor (Tag 'otherFaultShadow', tak commit). Membantu melihat bahwa
%   sesar yg sedang deaktivasi (ACT-FSR->X-FS) pada dasarnya MASIH aktif.
    h = guidata(fig);
    if ~(isfield(h,'interpOn') && h.interpOn), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if ~(isfield(h,'fdoc') && isstruct(h.fdoc)), return; end
    try, delete(findall(h.axMain,'Tag','otherFaultShadow')); catch, end
    F = i_activeFaults(h);
    if isempty(F), return; end
    % uiNum sesar AKTIF -> dilewati (bayangan hanya utk sesar LAIN).
    activeUi = NaN;
    [fa, ia] = pivui.grain5Model.activeFault(h);
    if ia >= 1, activeUi = pivui.grain5Model.faultUiNum(fa); end
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    ax = h.axMain; washold = ishold(ax); hold(ax,'on'); drawn = {};
    for k = 1:numel(F)
        uN = pivui.grain5Model.faultUiNum(F{k});
        if ~(isscalar(uN) && isfinite(uN)), continue; end
        if isscalar(activeUi) && isfinite(activeUi) && abs(uN-activeUi) < 0.5, continue; end
        if any(cellfun(@(x) abs(x-round(uN))<0.5, drawn)), continue; end   % 1x per uiNum
        [f0, f1, Vlast, xfsExcl] = i_faultLifeAndLastAct(h, uN);
        if ~(isfinite(f0) && isfinite(f1)) || size(Vlast,1) < 2, continue; end
        % X-FS EKSKLUSIF (selaras Deteksi): di frame X-FS sesar SUDAH tak aktif ->
        % bayangan HILANG tepat di frame X-FS (frameLive < f1). Tanpa X-FS = inklusif.
        if frameLive < f0, continue; end                     % sebelum aktif -> tak tampil
        if xfsExcl
            if frameLive >= f1, continue; end                % di/melewati X-FS -> tak tampil
        else
            if frameLive > f1, continue; end                 % tak ada X-FS -> inklusif
        end
        plot(ax, Vlast(:,1), Vlast(:,2), '--', 'Color',[0.85 0.10 0.10], 'LineWidth',1.4, ...
            'Tag','otherFaultShadow', 'Clipping','on');
        % label kecil F# di ujung pertama (bantu identifikasi).
        try
            text(ax, Vlast(1,1), Vlast(1,2), sprintf(' F%d', round(uN)), ...
                'Color',[0.75 0.05 0.05], 'FontSize',8, 'FontWeight','bold', ...
                'VerticalAlignment','bottom', 'Tag','otherFaultShadow', 'Clipping','on');
        catch, end
        drawn{end+1} = round(uN); %#ok<AGROW>
    end
    if ~washold, hold(ax,'off'); end
end

function i_faultPolyCleanup(fig)
%I_FAULTPOLYCLEANUP  Hapus ROI + label modul bidang sesar.
    h = guidata(fig);
    for fld = {'roiFaultPoly','faultPolyLabel'}
        f = fld{1};
        if isfield(h,f) && ~isempty(h.(f))
            try, if isvalid(h.(f)), delete(h.(f)); end, catch, end
            h.(f) = [];
        end
    end
    h.faultPolyOn = false; guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','faultPolyLabel')); catch, end
    i_syncFaultPolyBtn(fig,false);
end

function i_syncFaultPolyBtn(fig, on)
%I_SYNCFAULTPOLYBTN  Selaraskan Value togglebutton "📐 Bidang sesar".
    h = guidata(fig);
    if isfield(h,'btnFaultPoly') && ishghandle(h.btnFaultPoly)
        try, set(h.btnFaultPoly,'Value', double(logical(on))); catch, end
    end
end

% =====================================================================
% REFERENSI HORIZONTAL (koreksi kemiringan kamera) — tombol "⇄ Ref horizontal"
%   ON: garis hijau draggable di axMain (seed horizontal di tengah) + label
%   sudut LIVE. OFF: baca sudut garis -> simpan doc.refHorizonDeg (_faultgeom.
%   json) -> SEMUA sudut sesar (angleDegRel) dihitung relatif garis ini.
% =====================================================================
function i_onToggleRefHoriz(fig)
%I_ONTOGGLEREFHORIZ  Toggle set-referensi-horizontal. Tekan-1 buka garis; tekan-2
%   kunci+simpan sudut ref.
    h = guidata(fig);
    if isfield(h,'refHorizOn') && h.refHorizOn
        i_refHorizCommit(fig); return;
    end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum siap.'); i_syncRefHorizBtn(fig,false); return;
    end
    % Matikan mode zoom/pan interaktif (kursor crosshair) tapi pertahankan view kunci.
    i_suspendAxZoomForRoi(fig); h = guidata(fig);
    ax = h.axMain;
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    % SEED dari POSISI garis ref TERSIMPAN bila ada (JANGAN reset -> user tahu garis
    % memang sudah di sana, tinggal geser bila perlu). Belum ada -> garis datar di
    % tengah view (seed dari sudut tersimpan sbg kemiringan).
    Pstored = pivcore.io.grain4Desc.refHorizonPts(h.descDoc);
    if ~isempty(Pstored) && size(Pstored,1) >= 2
        p1 = Pstored(1,:); p2 = Pstored(2,:);
    else
        xc = mean(xl); yc = mean(yl); dx = 0.28*(xl(2)-xl(1));
        refDeg = i_faultRefDeg(h);
        if isfinite(refDeg), sl = tand(refDeg); else, sl = 0; end
        p1 = [xc-dx, yc - sl*dx]; p2 = [xc+dx, yc + sl*dx];
    end
    if pivui.quiet(), i_syncRefHorizBtn(fig,false); return; end
    h.roiRefHoriz = pivui.makePsgLineROI(ax, p1, p2, @() i_updateRefHoriz(fig), @() i_updateRefHoriz(fig));
    try, h.roiRefHoriz.Color = [0.10 0.55 0.20]; h.roiRefHoriz.Label = 'ref horizon'; catch, end
    h.refHorizLabel = text(ax, xl(1)+0.02*(xl(2)-xl(1)), yl(1)+0.06*(yl(2)-yl(1)), '', ...
        'Color',[0.05 0.35 0.12],'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[1 1 1 0.85],'Margin',3,'Tag','refHorizLabel', ...
        'VerticalAlignment','bottom','HorizontalAlignment','left');
    h.refHorizOn = true; guidata(fig, h);
    i_syncRefHorizBtn(fig,true);
    i_updateRefHoriz(fig);
    pivui.setStatus(fig,'Ref horizontal ON — seret garis sejajar horizon sebenarnya; tekan lagi utk kunci.');
end

function i_updateRefHoriz(fig)
%I_UPDATEREFHORIZ  Label sudut garis referensi LIVE (vs horizontal citra).
    h = guidata(fig);
    if ~(isfield(h,'refHorizOn') && h.refHorizOn), return; end
    if ~(isfield(h,'roiRefHoriz') && ~isempty(h.roiRefHoriz) && isvalid(h.roiRefHoriz)), return; end
    pos = []; try, pos = h.roiRefHoriz.Position; catch, end
    if isempty(pos) || size(pos,1) < 2, return; end
    deg = pivcore.pot.faultAngle.fromPoints(pos(1,:), pos(2,:));
    if isfield(h,'refHorizLabel') && ishghandle(h.refHorizLabel)
        set(h.refHorizLabel,'String', sprintf(' ref = %.2f° (koreksi kamera) ', deg));
    end
    pivui.setStatus(fig, sprintf('Ref horizontal = %.2f° vs citra.', deg));
end

function i_refHorizCommit(fig)
%I_REFHORIZCOMMIT  OFF: baca sudut garis ref -> simpan meta.refHorizonDeg
%   (_desc.json) + HITUNG ULANG angleDeg SEMUA baris DX (relatif ref baru) ->
%   refresh tabel.
    h = guidata(fig);
    if isfield(h,'roiRefHoriz') && ~isempty(h.roiRefHoriz) && isvalid(h.roiRefHoriz)
        pos = []; try, pos = h.roiRefHoriz.Position; catch, end
        if ~isempty(pos) && size(pos,1) >= 2
            deg = pivcore.pot.faultAngle.fromPoints(pos(1,:), pos(2,:));
            h.descDoc = pivcore.io.grain4Desc.setRefHorizonDeg(h.descDoc, deg);
            % SIMPAN POSISI garis (datum kedalaman nukleasi).
            h.descDoc = pivcore.io.grain4Desc.setRefHorizonPts(h.descDoc, pos(1:2,:));
            % Re-hitung angleDeg tiap baris (SEMUA garis PSG) dari vertices+ref baru.
            h.descDoc = i_recomputeAllDxAngles(h.descDoc, deg);
            % Re-hitung KEDALAMAN nukleasi (nucDepthPx/Cm) semua baris NUC-FSR
            % (datum garis ref berubah -> kedalaman berubah).
            guidata(fig, h);
            i_recomputeAllNucDepths(fig); h = guidata(fig);
            % (Tulis _desc.json DIBUANG: ref-horizontal hanya update MEMORI+tabel;
            %  file ditulis HANYA saat 💾 Save eksplisit.)
            pivui.setStatus(fig, sprintf('Ref horizontal = %.2f° + posisi tersimpan (sudut & kedalaman nukleasi dikoreksi; 💾 Save utk simpan).', deg));
        else
            guidata(fig, h);
        end
    else
        guidata(fig, h);
    end
    i_refHorizCleanup(fig);
    i_refreshDescTable(fig);   % kolom Sudut per-DX dihitung ulang relatif ref
    i_drawStoredRefHoriz(fig); % tampilkan garis ref tersimpan (datum kedalaman)
end

function doc = i_recomputeAllDxAngles(doc, refDeg)
%I_RECOMPUTEALLDXANGLES  Set r.angleDeg = angleDegRelOf(r.vertices, refDeg) utk
%   SEMUA baris ber-vertices (>=2). Baris tanpa vertices dibiarkan.
    if ~isstruct(doc) || ~isfield(doc,'rows'), return; end
    all = pivcore.io.grain4Desc.tocell(doc.rows);
    for k = 1:numel(all)
        r = pivcore.io.grain4Desc.normRow(all{k});
        V = pivcore.io.grain4Desc.normVerts(r.vertices);
        if size(V,1) >= 2, r.angleDeg = pivcore.io.grain4Desc.angleDegRelOf(V, refDeg); end
        all{k} = r;
    end
    doc.rows = all;
end

function i_refHorizCleanup(fig)
%I_REFHORIZCLEANUP  Hapus ROI + label referensi horizontal.
    h = guidata(fig);
    for fld = {'roiRefHoriz','refHorizLabel'}
        f = fld{1};
        if isfield(h,f) && ~isempty(h.(f))
            try, if isvalid(h.(f)), delete(h.(f)); end, catch, end
            h.(f) = [];
        end
    end
    h.refHorizOn = false; guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','refHorizLabel')); catch, end
    i_syncRefHorizBtn(fig,false);
end

function i_syncRefHorizBtn(fig, on)
%I_SYNCREFHORIZBTN  Selaraskan Value togglebutton "⇄ Ref horizontal".
    h = guidata(fig);
    if isfield(h,'btnRefHoriz') && ishghandle(h.btnRefHoriz)
        try, set(h.btnRefHoriz,'Value', double(logical(on))); catch, end
    end
end

function i_onToggleShowRefHoriz(fig)
%I_ONTOGGLESHOWREFHORIZ  Toggle overlay garis ref horizontal tersimpan.
    h = guidata(fig);
    if isfield(h,'chkShowRefHoriz') && ishghandle(h.chkShowRefHoriz)
        h.showRefHoriz = get(h.chkShowRefHoriz,'Value')==1;
    else
        h.showRefHoriz = ~(isfield(h,'showRefHoriz') && h.showRefHoriz);
    end
    guidata(fig, h);
    i_drawStoredRefHoriz(fig);
end

function i_drawStoredRefHoriz(fig)
%I_DRAWSTOREDREFHORIZ  Overlay PERSISTEN garis ref horizontal tersimpan
%   (meta.refHorizonPts) di axMain, semua frame, bila checkbox ON. Datum kedalaman
%   nukleasi -> perlu terlihat. Tag 'storedRefHoriz'. Dilewati saat alat set-ref
%   AKTIF (ROI editable sudah tampil).
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    try, delete(findall(h.axMain,'Tag','storedRefHoriz')); catch, end
    if isfield(h,'refHorizOn') && h.refHorizOn, return; end   % sedang diedit
    if ~(isfield(h,'showRefHoriz') && h.showRefHoriz), return; end
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    P = pivcore.io.grain4Desc.refHorizonPts(h.descDoc);
    if isempty(P) || size(P,1) < 2, return; end
    ax = h.axMain; washold = ishold(ax); hold(ax,'on');
    % perpanjang garis ke selebar XLim supaya tampak sbg datum horizon penuh.
    xl = get(ax,'XLim');
    a = P(1,:); b = P(2,:); dvec = b - a;
    if abs(dvec(1)) > eps
        m = dvec(2)/dvec(1);
        y1 = a(2) + m*(xl(1)-a(1)); y2 = a(2) + m*(xl(2)-a(1));
        xx = [xl(1) xl(2)]; yy = [y1 y2];
    else
        xx = [a(1) a(1)]; yy = get(ax,'YLim');
    end
    plot(ax, xx, yy, '-.', 'Color',[0.10 0.55 0.20], 'LineWidth',1.2, ...
        'Tag','storedRefHoriz', 'Clipping','on');
    if ~washold, hold(ax,'off'); end
end

% =====================================================================
%   REFERENSI GEOMETRI GENERIK (dinding pembatas + base) — koordinat robust
%   Garis 2-titik tersimpan di meta _desc.json; alat toggle pola ref horizontal.
%   kind: 'limitWall' (meta.limitWallPts) / 'base' (meta.basePts).
% =====================================================================
function cfg = i_metaLineCfg(kind)
%I_METALINECFG  Konfigurasi per-jenis garis referensi geometri.
    switch kind
        case 'limitWall'
            cfg = struct('kind','limitWall','field','limitWallPts', ...
                'name','Dinding pembatas','tag','storedLimitWall', ...
                'color',[0.75 0.20 0.15],'showField','showLimitWall', ...
                'btn','btnLimitWall','chk','chkShowLimitWall','style','-');
        case 'base'
            cfg = struct('kind','base','field','basePts', ...
                'name','Base','tag','storedBaseRef', ...
                'color',[0.25 0.25 0.70],'showField','showBaseRef', ...
                'btn','btnBaseRef','chk','chkShowBaseRef','style','--');
        case 'indenterInit'
            cfg = struct('kind','indenterInit','field','indenterInitPts', ...
                'name','Indenter/pendorong awal','tag','storedIndenterInit', ...
                'color',[0.85 0.45 0.05],'showField','showIndenterInit', ...
                'btn','btnIndenterInit','chk','chkShowIndenterInit','style','-');
        otherwise
            cfg = [];
    end
end

function i_onToggleMetaLine(fig, kind)
%I_ONTOGGLEMETALINE  Toggle alat garis referensi (dinding pembatas / base).
%   ON: garis draggable (SEED dari tersimpan bila ada -> tak reset). OFF: kunci +
%   simpan posisi ke meta. Hanya 1 alat aktif; membuka satu -> commit yg lain.
    if isempty(fig) || ~ishghandle(fig) || strcmp(get(fig,'BeingDeleted'),'on'), return; end
    cfg = i_metaLineCfg(kind); if isempty(cfg), return; end
    h = guidata(fig);
    % Alat meta-line SAMA sudah aktif -> commit. Alat LAIN aktif -> commit dulu.
    if isfield(h,'metaLineKind') && strcmp(h.metaLineKind, kind)
        i_metaLineCommit(fig); return;
    elseif isfield(h,'metaLineKind') && ~isempty(h.metaLineKind)
        i_metaLineCommit(fig); h = guidata(fig);
    end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum siap.'); i_syncMetaLineBtn(fig,kind,false); return;
    end
    i_suspendAxZoomForRoi(fig); h = guidata(fig);
    ax = h.axMain; xl = get(ax,'XLim'); yl = get(ax,'YLim');
    Pstored = pivcore.io.grain4Desc.metaLine(h.descDoc, cfg.field);
    if ~isempty(Pstored) && size(Pstored,1) >= 2
        p1 = Pstored(1,:); p2 = Pstored(2,:);
    elseif strcmp(kind,'limitWall') || strcmp(kind,'indenterInit')
        % dinding pembatas / indenter awal = garis VERTIKAL default (batas model).
        xc = mean(xl); if strcmp(kind,'indenterInit'), xc = xl(1)+0.25*(xl(2)-xl(1)); end
        p1 = [xc yl(1)+0.1*(yl(2)-yl(1))]; p2 = [xc yl(2)-0.1*(yl(2)-yl(1))];
    else
        % base = garis MENDATAR default di bawah.
        yc = yl(1)+0.85*(yl(2)-yl(1)); dx = 0.35*(xl(2)-xl(1)); xc = mean(xl);
        p1 = [xc-dx yc]; p2 = [xc+dx yc];
    end
    if pivui.quiet(), i_syncMetaLineBtn(fig,kind,false); return; end
    h.roiMetaLine = pivui.makePsgLineROI(ax, p1, p2, @() i_updateMetaLine(fig), @() i_updateMetaLine(fig));
    try, h.roiMetaLine.Color = cfg.color; h.roiMetaLine.Label = cfg.name; catch, end
    h.metaLineKind = kind;
    h.metaLineLabel = text(ax, xl(1)+0.02*(xl(2)-xl(1)), yl(1)+0.12*(yl(2)-yl(1)), '', ...
        'Color',cfg.color*0.7,'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[1 1 1 0.85],'Margin',3,'Tag','metaLineLabel', ...
        'VerticalAlignment','bottom','HorizontalAlignment','left');
    guidata(fig, h);
    i_syncMetaLineBtn(fig,kind,true);
    i_updateMetaLine(fig);
    pivui.setStatus(fig, sprintf('%s ON — seret garis; tekan lagi utk KUNCI & simpan.', cfg.name));
end

function i_updateMetaLine(fig)
%I_UPDATEMETALINE  Label LIVE posisi garis referensi (endpoint).
    h = guidata(fig);
    if ~(isfield(h,'metaLineKind') && ~isempty(h.metaLineKind)), return; end
    if ~(isfield(h,'roiMetaLine') && ~isempty(h.roiMetaLine) && isvalid(h.roiMetaLine)), return; end
    cfg = i_metaLineCfg(h.metaLineKind); if isempty(cfg), return; end
    pos = []; try, pos = h.roiMetaLine.Position; catch, end
    if isempty(pos) || size(pos,1) < 2, return; end
    if isfield(h,'metaLineLabel') && ishghandle(h.metaLineLabel)
        set(h.metaLineLabel,'String', sprintf(' %s: (%.0f,%.0f)-(%.0f,%.0f) px ', ...
            cfg.name, pos(1,1),pos(1,2),pos(2,1),pos(2,2)));
    end
    pivui.setStatus(fig, sprintf('%s: garis di (%.0f,%.0f)-(%.0f,%.0f) px.', ...
        cfg.name, pos(1,1),pos(1,2),pos(2,1),pos(2,2)));
end

function i_metaLineCommit(fig)
%I_METALINECOMMIT  OFF: baca posisi garis -> simpan meta.(field). descDoc MEMORI
%   (disk hanya saat 💾 Save). Refresh overlay.
    h = guidata(fig);
    kind = ''; if isfield(h,'metaLineKind'), kind = h.metaLineKind; end
    cfg = i_metaLineCfg(kind);
    if ~isempty(cfg) && isfield(h,'roiMetaLine') && ~isempty(h.roiMetaLine) && isvalid(h.roiMetaLine)
        pos = []; try, pos = h.roiMetaLine.Position; catch, end
        if ~isempty(pos) && size(pos,1) >= 2
            h.descDoc = pivcore.io.grain4Desc.setMetaLine(h.descDoc, cfg.field, pos(1:2,:));
            guidata(fig, h);
            % Indenter awal & dinding pembatas = datum X + kalibrasi jarak nukleasi
            % -> HITUNG ULANG metrik nukleasi semua DX.
            if strcmp(kind,'indenterInit') || strcmp(kind,'limitWall')
                i_recomputeAllNucDepths(fig); h = guidata(fig);
                i_refreshDescTable(fig);
            end
            pivui.setStatus(fig, sprintf('%s TERSIMPAN (💾 Save utk tulis ke berkas).', cfg.name));
        else
            guidata(fig, h);
        end
    else
        guidata(fig, h);
    end
    i_metaLineCleanup(fig);
    if ~isempty(cfg), i_drawStoredMetaLine(fig, kind); end
end

function i_metaLineCleanup(fig)
%I_METALINECLEANUP  Hapus ROI + label garis referensi aktif, reset state.
    h = guidata(fig);
    for fld = {'roiMetaLine','metaLineLabel'}
        f = fld{1};
        if isfield(h,f) && ~isempty(h.(f))
            try, if isvalid(h.(f)), delete(h.(f)); end, catch, end
            h.(f) = [];
        end
    end
    kind = ''; if isfield(h,'metaLineKind'), kind = h.metaLineKind; end
    h.metaLineKind = ''; guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','metaLineLabel')); catch, end
    if ~isempty(kind), i_syncMetaLineBtn(fig,kind,false); end
end

function i_syncMetaLineBtn(fig, kind, on)
%I_SYNCMETALINEBTN  Selaraskan Value togglebutton garis referensi.
    if ~ishghandle(fig), return; end
    cfg = i_metaLineCfg(kind); if isempty(cfg), return; end
    h = guidata(fig);
    if isfield(h,cfg.btn) && ishghandle(h.(cfg.btn))
        try, set(h.(cfg.btn),'Value', double(logical(on))); catch, end
    end
end

function i_onToggleShowMetaLine(fig, kind)
%I_ONTOGGLESHOWMETALINE  Toggle overlay garis referensi tersimpan.
    cfg = i_metaLineCfg(kind); if isempty(cfg), return; end
    h = guidata(fig);
    if isfield(h,cfg.chk) && ishghandle(h.(cfg.chk))
        h.(cfg.showField) = get(h.(cfg.chk),'Value')==1;
    else
        h.(cfg.showField) = ~(isfield(h,cfg.showField) && h.(cfg.showField));
    end
    guidata(fig, h);
    i_drawStoredMetaLine(fig, kind);
end

function i_drawStoredMetaLine(fig, kind)
%I_DRAWSTOREDMETALINE  Overlay PERSISTEN garis referensi tersimpan (meta.(field))
%   di axMain, semua frame, bila checkbox ON. Dilewati saat alat kind ini AKTIF.
    cfg = i_metaLineCfg(kind); if isempty(cfg), return; end
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    try, delete(findall(h.axMain,'Tag',cfg.tag)); catch, end
    if isfield(h,'metaLineKind') && strcmp(h.metaLineKind, kind), return; end   % sedang diedit
    if ~(isfield(h,cfg.showField) && h.(cfg.showField)), return; end
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    P = pivcore.io.grain4Desc.metaLine(h.descDoc, cfg.field);
    if isempty(P) || size(P,1) < 2, return; end
    ax = h.axMain; washold = ishold(ax); hold(ax,'on');
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    a = P(1,:); b = P(2,:); dvec = b - a;
    if abs(dvec(1)) > abs(dvec(2))          % lebih mendatar -> rentang X penuh
        m = dvec(2)/dvec(1);
        xx = [xl(1) xl(2)]; yy = [a(2)+m*(xl(1)-a(1)), a(2)+m*(xl(2)-a(1))];
    elseif abs(dvec(2)) > eps               % lebih tegak -> rentang Y penuh
        mi = dvec(1)/dvec(2);
        yy = [yl(1) yl(2)]; xx = [a(1)+mi*(yl(1)-a(2)), a(1)+mi*(yl(2)-a(2))];
    else
        xx = [a(1) a(1)]; yy = yl;
    end
    plot(ax, xx, yy, cfg.style, 'Color',cfg.color, 'LineWidth',1.3, ...
        'Tag',cfg.tag, 'Clipping','on');
    if ~washold, hold(ax,'off'); end
end

function i_drawStoredMetaLines(fig)
%I_DRAWSTOREDMETALINES  Gambar SEMUA garis referensi tersimpan. KOTAK MODEL
%   (4-titik) jadi sumber utama -> gambar kotak; garis-terpisah hanya bila kotak
%   TAK ADA (fallback/kompat) supaya tak dobel.
    h = guidata(fig);
    hasBox = false;
    if isfield(h,'descDoc') && isstruct(h.descDoc)
        hasBox = ~isempty(pivcore.io.grain4Desc.modelBoxPts(h.descDoc));
    end
    i_drawStoredModelBox(fig);
    if ~hasBox
        i_drawStoredMetaLine(fig, 'limitWall');
        i_drawStoredMetaLine(fig, 'base');
        i_drawStoredMetaLine(fig, 'indenterInit');
    else
        % kotak ada -> pastikan overlay garis-terpisah dibersihkan.
        try, delete(findall(h.axMain,'Tag','storedLimitWall')); catch, end
        try, delete(findall(h.axMain,'Tag','storedBaseRef')); catch, end
        try, delete(findall(h.axMain,'Tag','storedIndenterInit')); catch, end
    end
end

% =====================================================================
%   KOTAK MODEL (4 titik sudut, klik CLOCKWISE dari KIRI-ATAS)
%   1 tombol: klik -> input 4 titik berturut (KiA·KaA·KaB·KiB). Klik tombol
%   lagi setelah ada isi -> RESET & input dari 0. Sumber tunggal semua referensi
%   (pendorong=kiri · pembatas=kanan · base=bawah · ref horizontal=atas).
% =====================================================================
function i_onToggleModelBox(fig)
%I_ONTOGGLEMODELBOX  Input KOTAK MODEL via 4 klik. Bila sudah ada -> reset & ulang.
    if isempty(fig) || ~ishghandle(fig) || strcmp(get(fig,'BeingDeleted'),'on'), return; end
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum siap.'); i_syncModelBoxBtn(fig,false); return;
    end
    % Sedang mengumpulkan titik? -> klik tombol lagi = BATAL (reset).
    if isfield(h,'boxCollect') && isstruct(h.boxCollect) && h.boxCollect.active
        i_boxCollectCancel(fig); return;
    end
    % HOOK TES (headless): h.boxTestPts = 4x2 -> langsung finalisasi tanpa interaksi
    % (CurrentPoint read-only tak bisa disimulasi). Jalur produksi TAK terpengaruh.
    if isfield(h,'boxTestPts') && ~isempty(h.boxTestPts)
        Pt = pivcore.io.grain4Desc.normVerts(h.boxTestPts);
        if size(Pt,1) >= 4
            h.descDoc = pivcore.io.grain4Desc.setModelBoxPts(h.descDoc, Pt(1:4,:));
            guidata(fig, h);
            i_recomputeAllNucDepths(fig); i_refreshDescTable(fig); i_drawStoredModelBox(fig);
            i_syncModelBoxBtn(fig,false);
            pivui.setStatus(fig,'Kotak model TERSIMPAN (hook tes).');
            return;
        end
    end
    if pivui.quiet(), i_syncModelBoxBtn(fig,false); return; end   % headless -> tak interaktif
    % RESET input lama (kalau ada) — user minta selalu mulai dari 0.
    h.descDoc = pivcore.io.grain4Desc.setModelBoxPts(h.descDoc, []);
    guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','storedModelBox')); catch, end
    i_suspendAxZoomForRoi(fig); h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), i_syncModelBoxBtn(fig,false); return; end
    % Mulai KOLEKSI KLIK non-blocking (loupe hidup di WindowButtonMotionFcn).
    bc = struct();
    bc.active   = true;
    bc.busy     = false;   % guard re-entry (klik/motion tak saling menimpa)
    bc.pts      = zeros(0,2);
    bc.markers  = gobjects(0);
    bc.prevMotion = get(fig,'WindowButtonMotionFcn');
    bc.prevDown   = get(fig,'WindowButtonDownFcn');
    bc.prevAxDown = get(h.axMain,'ButtonDownFcn');
    bc.prevPtr    = get(fig,'Pointer');
    h.boxCollect = bc;
    guidata(fig, h);
    % KLIK HANYA dari 1 sumber (WindowButtonDownFcn figure). JANGAN pasang JUGA
    % ax.ButtonDownFcn -> klik di axMain akan fire DUA kali (fig+ax) -> 2 titik/klik
    % -> hang/finalize prematur (bug "hang di plot ke-3"). ax.ButtonDownFcn dikosongkan.
    try, set(h.axMain,'ButtonDownFcn',''); catch, end
    set(fig,'WindowButtonMotionFcn',@(s,e) i_boxOnMotion(fig), ...
            'WindowButtonDownFcn', @(s,e) i_boxOnClick(fig), ...
            'Pointer','crosshair');
    i_syncModelBoxBtn(fig,true);
    pivui.setStatus(fig,'Kotak model: klik titik 1/4 = KIRI-ATAS (clockwise). Loupe 2× ikut kursor. Klik tombol lagi utk BATAL.');
end

function i_boxOnMotion(fig)
%I_BOXONMOTION  Update LOUPE (kaca pembesar 2×) mengikuti kursor di axMain saat
%   mode input kotak model aktif. Loupe = axes overlay kecil berisi SALINAN isi
%   axMain, di-zoom 2× di sekitar kursor + crosshair titik tengah.
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    if ~i_boxCollecting(h), return; end
    if isfield(h.boxCollect,'busy') && h.boxCollect.busy, return; end   % sedang proses klik -> skip loupe
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    ax = h.axMain;
    cp = []; try, cp = get(ax,'CurrentPoint'); catch, end
    if isempty(cp) || size(cp,2) < 2, return; end
    x = double(cp(1,1)); y = double(cp(1,2));
    if ~(isscalar(x) && isscalar(y) && isfinite(x) && isfinite(y)), return; end
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    inside = (x>=xl(1)) && (x<=xl(2)) && (y>=yl(1)) && (y<=yl(2));
    if ~inside
        i_loupeHide(fig); i_boxGuideHide(fig); return;
    end
    try, i_loupeShow(fig, x, y); catch, i_loupeHide(fig); end
    try, i_boxGuideShow(fig, x, y); catch, i_boxGuideHide(fig); end
end

function i_boxGuideShow(fig, x, y)
%I_BOXGUIDESHOW  Garis panduan crosshair MELINTANG PENUH di axMain (horizontal +
%   vertikal lewat kursor) supaya bisa disejajarkan dgn garis TOP lapisan model.
%   Merah tipis putus-putus; tak interaktif; dihapus tiap gerak.
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    ax = h.axMain;
    try, delete(findall(ax,'Tag','boxGuide')); catch, end
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    washold = ishold(ax); hold(ax,'on');
    plot(ax, xl, [y y], ':', 'Color',[1 0 0], 'LineWidth',1.0, ...
        'Tag','boxGuide','HitTest','off','PickableParts','none','Clipping','on');
    plot(ax, [x x], yl, ':', 'Color',[1 0 0], 'LineWidth',1.0, ...
        'Tag','boxGuide','HitTest','off','PickableParts','none','Clipping','on');
    if ~washold, hold(ax,'off'); end
    try, set(ax,'XLim',xl,'YLim',yl); catch, end   % jaga limit (anti-geser)
end

function i_boxGuideHide(fig)
%I_BOXGUIDEHIDE  Hapus garis panduan crosshair axMain.
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    if isfield(h,'axMain') && ishghandle(h.axMain)
        try, delete(findall(h.axMain,'Tag','boxGuide')); catch, end
    end
end

function tf = i_boxCollecting(h)
%I_BOXCOLLECTING  True bila state koleksi kotak model aktif (scalar-safe).
    tf = false;
    if ~(isstruct(h) && isfield(h,'boxCollect')), return; end
    bc = h.boxCollect;
    if ~(isstruct(bc) && isscalar(bc) && isfield(bc,'active')), return; end
    tf = isscalar(bc.active) && logical(bc.active);
end

function tf = i_isValidH(v)
%I_ISVALIDH  True bila v = SATU handle grafik valid (scalar-safe; cegah error
%   '&& non-scalar' saat v=[] atau array).
    tf = ~isempty(v) && isscalar(v) && ishghandle(v);
end

function i_loupeShow(fig, x, y)
%I_LOUPESHOW  Tampilkan/segarkan loupe pada titik data (x,y) axMain. Zoom 2×.
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    ax = h.axMain; par = get(ax,'Parent');
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    if ~(numel(xl)==2 && numel(yl)==2 && diff(xl)~=0 && diff(yl)~=0), return; end
    axPos = getpixelposition(ax, true);   % [x y w h] px relatif figure
    figPos = getpixelposition(fig);
    if numel(axPos)<4 || numel(figPos)<4 || axPos(3)<=0 || axPos(4)<=0, return; end
    % Ukuran loupe = ~28% lebar axMain (kotak sedang, persegi).
    Lw = 0.28*axPos(3); Lh = Lw;
    % Jendela DATA (zoom 2×) = setengah lebar loupe / 2 dalam satuan data.
    dxData = (xl(2)-xl(1)) / max(axPos(3),1);
    dyData = (yl(2)-yl(1)) / max(axPos(4),1);
    halfWx = (Lw/2)/2 * dxData;
    halfWy = (Lh/2)/2 * dyData;
    if ~(isfinite(halfWx) && isfinite(halfWy) && halfWx>0 && halfWy>0), return; end
    % Posisi kursor dlm px figure.
    cpx = axPos(1) + (x-xl(1))/(xl(2)-xl(1)) * axPos(3);
    cpy = axPos(2) + (y-yl(1))/(yl(2)-yl(1)) * axPos(4);
    off = 0.02*figPos(3);
    Lx = cpx + off; Ly = cpy + off;
    if Lx + Lw > figPos(3), Lx = cpx - off - Lw; end
    if Ly + Lh > figPos(4), Ly = cpy - off - Lh; end
    Lx = max(Lx,2); Ly = max(Ly,2);
    % Buat axes loupe SEKALI (scalar-safe; cegah ganda).
    if ~i_isValidH(i_getf(h,'loupeAx'))
        lax = axes('Parent',par,'Units','pixels','Box','on','XTick',[],'YTick',[], ...
            'Tag','boxLoupeAx','HandleVisibility','off','HitTest','off');
        try, set(lax,'YDir',get(ax,'YDir')); catch, end
        try
            % Salin HANYA objek GAMBAR (image/surface) — ringan & cukup utk loupe.
            % Hindari copyobj SELURUH anak (garis/patch/marker/guide kita sendiri ->
            % berat + bisa menyalin overlay dinamis). Ambil yg terbawah (gambar).
            src = [findobj(ax,'Type','image'); findobj(ax,'Type','surface')];
            if ~isempty(src)
                kids = copyobj(src, lax);
                for k = 1:numel(kids)
                    try, set(kids(k),'HitTest','off','PickableParts','none'); catch, end
                end
            end
        catch, end
        try, colormap(lax, colormap(ax)); catch, end
        try, clim(lax, clim(ax)); catch, end
        try, set(lax,'Color',get(ax,'Color')); catch, end
        h.loupeAx = lax; guidata(fig, h);
    end
    lax = h.loupeAx;
    if ~i_isValidH(lax), return; end
    set(lax,'Position',[Lx Ly Lw Lh], ...
        'XLim',[x-halfWx x+halfWx],'YLim',[y-halfWy y+halfWy],'XTick',[],'YTick',[]);
    try, uistack(lax,'top'); catch, end
    % Crosshair PANJANG (membentang PENUH loupe) = panduan sejajar dgn garis top
    % lapisan. Koordinat dibuat jauh melampaui jendela supaya garis tak terpotong di
    % ujung + tetap melintasi seluruh kotak loupe (clipping loupe memotong di tepi).
    try, delete(findall(lax,'Tag','loupeCross')); catch, end
    washold = ishold(lax); hold(lax,'on');
    bigX = 100*halfWx; bigY = 100*halfWy;   % jauh > jendela -> pasti penuh melintang
    plot(lax,[x-bigX x+bigX],[y y],'-','Color',[1 0 0],'LineWidth',0.9,'Tag','loupeCross','HitTest','off','Clipping','on');
    plot(lax,[x x],[y-bigY y+bigY],'-','Color',[1 0 0],'LineWidth',0.9,'Tag','loupeCross','HitTest','off','Clipping','on');
    plot(lax, x, y,'+','Color',[1 0 0],'MarkerSize',14,'LineWidth',1.4,'Tag','loupeCross','HitTest','off');
    if ~washold, hold(lax,'off'); end
end

function v = i_getf(s, f)
%I_GETF  Ambil field s.(f) atau [] bila absen.
    if isstruct(s) && isfield(s,f), v = s.(f); else, v = []; end
end

function i_loupeHide(fig)
%I_LOUPEHIDE  Sembunyikan/hapus loupe (scalar-safe + bersihkan sisa by-Tag).
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    lax = i_getf(h,'loupeAx');
    if i_isValidH(lax), try, delete(lax); catch, end, end
    % Jaring pengaman: hapus SEMUA axes loupe sisa (bila pernah dobel).
    try, delete(findall(fig,'Tag','boxLoupeAx')); catch, end
    h.loupeAx = [];
    guidata(fig, h);
end

function i_boxOnClick(fig)
%I_BOXONCLICK  Handler klik: baca posisi kursor axMain lalu rekam titik.
%   Guard busy: cegah re-entry (klik ganda/motion saat finalisasi).
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    if ~i_boxCollecting(h), return; end
    if isfield(h.boxCollect,'busy') && h.boxCollect.busy, return; end   % sedang proses -> abaikan
    ax = h.axMain;
    cp = []; try, cp = get(ax,'CurrentPoint'); catch, end
    if isempty(cp) || size(cp,2) < 2, return; end
    i_boxRecordPoint(fig, double(cp(1,1)), double(cp(1,2)));
end

function i_boxRecordPoint(fig, x, y)
%I_BOXRECORDPOINT  Rekam 1 titik sudut kotak model pada (x,y) data-coord axMain.
%   Titik ke-4 -> finalisasi (simpan + recompute + restore). Dipisah dari handler
%   klik supaya bisa diuji headless (CurrentPoint read-only). Klik luar limit ->
%   diabaikan.
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    if ~i_boxCollecting(h), return; end
    ax = h.axMain;
    if ~(isscalar(x) && isscalar(y) && isfinite(x) && isfinite(y)), return; end
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    if ~((x>=xl(1)) && (x<=xl(2)) && (y>=yl(1)) && (y<=yl(2))), return; end   % luar axMain -> abaikan
    bc = h.boxCollect;
    if isfield(bc,'busy') && bc.busy, return; end   % re-entry guard
    if ~isfield(bc,'pts'), bc.pts = zeros(0,2); end
    if ~isfield(bc,'markers'), bc.markers = gobjects(0); end
    bc.busy = true;                                 % kunci selama proses klik ini
    bc.pts(end+1,:) = [x y];
    col = [0.55 0.30 0.75];
    % PRESERVE limit + hold: plot marker TAK boleh menggeser/relimit axMain (bug
    % "gambar geser saat klik pertama" -> plot tanpa hold me-reset NextPlot).
    xlK = get(ax,'XLim'); ylK = get(ax,'YLim');
    washold = ishold(ax); hold(ax,'on');
    m = plot(ax, x, y, 'o','MarkerSize',7,'MarkerFaceColor',col, ...
        'MarkerEdgeColor',[0.25 0.10 0.35],'Tag','boxCollectMark','HitTest','off','PickableParts','none');
    if ~washold, hold(ax,'off'); end
    try, set(ax,'XLim',xlK,'YLim',ylK); catch, end
    bc.markers(end+1) = m;
    n = size(bc.pts,1);
    labels = {'KIRI-ATAS','KANAN-ATAS','KANAN-BAWAH','KIRI-BAWAH'};
    if n < 4
        bc.busy = false;                            % buka kunci utk klik berikutnya
        h.boxCollect = bc; guidata(fig, h);
        pivui.setStatus(fig, sprintf('Kotak model: klik titik %d/4 = %s.', n+1, labels{n+1}));
        return;
    end
    % 4 titik lengkap -> finalisasi (busy TETAP true -> abaikan klik/motion nyasar).
    h.boxCollect = bc; guidata(fig, h);
    P = bc.pts(1:4,:);
    i_boxCollectStop(fig);   % restore callbacks + hapus loupe + marker sementara + set active=false
    h = guidata(fig);
    h.descDoc = pivcore.io.grain4Desc.setModelBoxPts(h.descDoc, P);
    guidata(fig, h);
    i_recomputeAllNucDepths(fig);
    i_refreshDescTable(fig);
    i_drawStoredModelBox(fig);
    s = pivcore.io.grain4Desc.boxSides(P);
    pivui.setStatus(fig, sprintf(['Kotak model TERSIMPAN (4 titik). Pendorong x=%.0f · pembatas x=%.0f px. ' ...
        'Jarak nukleasi & kedalaman dihitung ulang. 💾 Save utk simpan.'], s.xLeft, s.xRight));
end

function i_boxCollectCancel(fig)
%I_BOXCOLLECTCANCEL  Batalkan koleksi (klik tombol saat sedang input) -> reset.
    i_boxCollectStop(fig);
    pivui.setStatus(fig,'Kotak model BATAL (input direset).');
end

function i_boxCollectStop(fig)
%I_BOXCOLLECTSTOP  Pulihkan WindowButton*Fcn + pointer + hapus loupe & marker
%   sementara. Nonaktifkan state koleksi.
    h = guidata(fig);
    if isfield(h,'boxCollect') && isstruct(h.boxCollect)
        bc = h.boxCollect;
        try, set(fig,'WindowButtonMotionFcn', bc.prevMotion); catch, end
        try, set(fig,'WindowButtonDownFcn',   bc.prevDown);   catch, end
        try, set(fig,'Pointer', bc.prevPtr); catch, end
        if isfield(bc,'prevAxDown') && isfield(h,'axMain') && ishghandle(h.axMain)
            try, set(h.axMain,'ButtonDownFcn', bc.prevAxDown); catch, end
        end
        if isfield(bc,'markers')
            for k = 1:numel(bc.markers)
                try, if ishghandle(bc.markers(k)), delete(bc.markers(k)); end, catch, end
            end
        end
    end
    h.boxCollect = struct('active',false,'busy',false);
    guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','boxCollectMark')); catch, end
    i_loupeHide(fig);
    i_boxGuideHide(fig);
    i_syncModelBoxBtn(fig,false);
end

function i_onClearModelBox(fig)
%I_ONCLEARMODELBOX  Hapus kotak model + recompute (kembali ke fallback garis).
    if isempty(fig) || ~ishghandle(fig), return; end
    h = guidata(fig);
    h.descDoc = pivcore.io.grain4Desc.setModelBoxPts(h.descDoc, []);
    guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','storedModelBox')); catch, end
    i_recomputeAllNucDepths(fig);
    i_refreshDescTable(fig);
    pivui.setStatus(fig,'Kotak model DIHAPUS.');
end

function i_syncModelBoxBtn(fig, on)
%I_SYNCMODELBOXBTN  Selaraskan Value togglebutton kotak model.
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    if isfield(h,'btnModelBox') && ishghandle(h.btnModelBox)
        try, set(h.btnModelBox,'Value', double(logical(on))); catch, end
    end
end

function i_onToggleShowModelBox(fig)
%I_ONTOGGLESHOWMODELBOX  Toggle overlay kotak model tersimpan.
    h = guidata(fig);
    if isfield(h,'chkShowModelBox') && ishghandle(h.chkShowModelBox)
        h.showModelBox = get(h.chkShowModelBox,'Value')==1;
    else
        h.showModelBox = ~(isfield(h,'showModelBox') && h.showModelBox);
    end
    guidata(fig, h);
    i_drawStoredModelBox(fig);
end

function i_drawStoredModelBox(fig)
%I_DRAWSTOREDMODELBOX  Overlay PERSISTEN kotak model (4 titik) di axMain: poligon
%   ungu + penanda tiap sudut + label sisi (pendorong/pembatas/base/ref). Semua
%   frame bila checkbox tampil ON. Tag 'storedModelBox'.
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    try, delete(findall(h.axMain,'Tag','storedModelBox')); catch, end
    if ~(isfield(h,'showModelBox') && h.showModelBox), return; end
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    P = pivcore.io.grain4Desc.modelBoxPts(h.descDoc);
    if isempty(P) || size(P,1) < 4, return; end
    ax = h.axMain; washold = ishold(ax); hold(ax,'on');
    col = [0.55 0.30 0.75];
    poly = [P; P(1,:)];   % tutup poligon
    plot(ax, poly(:,1), poly(:,2), '-', 'Color',col, 'LineWidth',1.4, ...
        'Tag','storedModelBox','Clipping','on');
    plot(ax, P(:,1), P(:,2), 'o', 'MarkerSize',5, 'MarkerFaceColor',col, ...
        'MarkerEdgeColor',[0.25 0.10 0.35], 'Tag','storedModelBox','Clipping','on');
    if ~washold, hold(ax,'off'); end
end

function i_onSetModelThick(fig)
%I_ONSETMODELTHICK  Set ketebalan model (cm) dari kotak edit -> meta. Invalid ->
%   pulihkan tampilan ke nilai tersimpan.
    h = guidata(fig);
    if ~(isfield(h,'edModelThick') && ishghandle(h.edModelThick)), return; end
    s = strtrim(get(h.edModelThick,'String'));
    v = str2double(strrep(s, ',', '.'));
    if isscalar(v) && isfinite(v) && v > 0
        h.descDoc = pivcore.io.grain4Desc.setModelThicknessCm(h.descDoc, v);
        guidata(fig, h);
        % kalibrasi ulang kedalaman nukleasi tak perlu (tebal ≠ datum kedalaman;
        % tebal = skala model utk CLCW). Cukup simpan + normalkan tampilan.
        set(h.edModelThick,'String', num2str(v));
        pivui.setStatus(fig, sprintf('Ketebalan model = %g cm (💾 Save utk simpan).', v));
    else
        cur = pivcore.io.grain4Desc.modelThicknessCm(h.descDoc);
        set(h.edModelThick,'String', num2str(cur));
        pivui.setStatus(fig, 'Ketebalan tak valid (harus angka > 0). Dipulihkan.');
    end
end

% ---------------------------------------------------------------------
%   HELPER modul polyline sesar (metrik + frame POI + kalibrasi)
% ---------------------------------------------------------------------
function tag = i_faultUiTag(f)
%I_FAULTUITAG  Nomor tampil sesar sbg string ('3' utk F3). '' bila tak ada.
    tag = '';
    uN = pivui.grain5Model.faultUiNum(f);
    if ~isempty(uN) && isfinite(uN), tag = sprintf('%d', round(uN)); end
end

function frames = i_faultFsMaxFramesDesc(h, f)
%I_FAULTFSMAXFRAMESDESC  Vektor frame baris DESC ber-POI 'ACT-FSR' utk sesar f
%   (uiNum) di garis PSG aktif, terurut menaik. [] bila tak ada.
    frames = [];
    if isempty(f) || ~isfield(h,'descDoc'), return; end
    tag = i_faultUiTag(f); if isempty(tag), return; end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    pairs = pivcore.io.grain4Report.fsMaxPairs(rows, tag);   % Nx2 sort+pair
    frames = sort(unique(pairs(:).'));
end

function fr = i_faultFirstFsMax(h, f)
%I_FAULTFIRSTFSMAX  Frame FS-max PERTAMA (min) sesar f. NaN bila tak ada.
    fr = NaN;
    ff = i_faultFsMaxFramesDesc(h, f);
    if ~isempty(ff), fr = min(ff); end
end

function fr = i_faultNucFsrFrame(h, f)
%I_FAULTNUCFSRFRAME  Frame baris DESC ber-POI 'NUC-FSR' (=NUC-TF) sesar f di
%   garis PSG aktif. Bila >1, ambil yang PERTAMA (min). NaN bila tak ada.
    fr = NaN;
    if isempty(f) || ~isfield(h,'descDoc'), return; end
    tag = i_faultUiTag(f); if isempty(tag), return; end
    tgt = sprintf('F%s', tag);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    cand = [];
    for k = 1:numel(rows)
        r = rows{k};
        poi = ''; if isfield(r,'poi'), poi = strtrim(char(r.poi)); end
        if ~strcmpi(poi,'NUC-FSR'), continue; end
        if ~strcmp(strtrim(r.fNum), tgt), continue; end
        v = NaN; if isfield(r,'frame'), v = r.frame; end
        if isscalar(v) && isfinite(v), cand(end+1) = round(v); end %#ok<AGROW>
    end
    if ~isempty(cand), fr = min(cand); end
end

function cpp = i_faultCmPerPx(h)
%I_FAULTCMPERPX  Rasio cm/pixel ISOTROPIK dari geometri indenter:
%   cmPerPx = dxCm / lebarFrameSumbuX. dxCm = h.axCalR.dxCm (readGeom).
%   lebar = span h.xExt (data-coord axMain = pixel gambar). NaN bila tak ada.
    cpp = NaN;
    dxCm = NaN;
    if isfield(h,'axCalR') && isstruct(h.axCalR) && isfield(h.axCalR,'dxCm'), dxCm = h.axCalR.dxCm; end
    widthPx = NaN;
    if isfield(h,'xExt') && numel(h.xExt) == 2 && all(isfinite(h.xExt))
        widthPx = abs(h.xExt(2) - h.xExt(1));
    end
    cpp = pivcore.io.grain4Desc.cmPerPxFromGeom(dxCm, widthPx);
end

function deg = i_faultRefDeg(h)
%I_FAULTREFDEG  Sudut referensi horizontal tersimpan (meta _desc.json) utk
%   koreksi kemiringan kamera. NaN bila tak diset (pakai horizontal citra).
    deg = NaN;
    if isfield(h,'descDoc') && isstruct(h.descDoc)
        deg = pivcore.io.grain4Desc.refHorizonDeg(h.descDoc);
    end
end

function dt = i_faultDtSec(h)
%I_FAULTDTSEC  dt detik/frame (EXIF) exp aktif; fallback 10 s.
    dt = 10;
    if isfield(h,'df') && ~isempty(h.df)
        try
            v = pivcore.export.frameCatalog.readExifDt(h.df);
            if isscalar(v) && isfinite(v) && v > 0, dt = v; end
        catch, end
    end
end

function fr = i_faultFsMaxSecondFrame(h, f)
%I_FAULTFSMAXSECONDFRAME  Frame FS-max KEDUA sesar f (elemen ke-2 urut menaik).
%   NaN bila <2 FS-max.
    fr = NaN;
    fsAll = i_faultFsMaxFramesDesc(h, f);   % sudah sort unik menaik
    if numel(fsAll) >= 2, fr = fsAll(2); end
end

function fr = i_faultFsxFrame(h, f)
%I_FAULTFSXFRAME  Frame baris DESC ber-POI 'X-FS' sesar f (garis PSG aktif).
%   Bila >1, ambil PERTAMA (min). NaN bila tak ada.
    fr = NaN;
    if isempty(f) || ~isfield(h,'descDoc'), return; end
    tag = i_faultUiTag(f); if isempty(tag), return; end
    tgt = sprintf('F%s', tag);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    cand = [];
    for k = 1:numel(rows)
        r = rows{k};
        poi = ''; if isfield(r,'poi'), poi = strtrim(char(r.poi)); end
        if ~strcmpi(poi,'X-FS'), continue; end
        if ~strcmp(strtrim(r.fNum), tgt), continue; end
        v = NaN; if isfield(r,'frame'), v = r.frame; end
        if isscalar(v) && isfinite(v), cand(end+1) = round(v); end %#ok<AGROW>
    end
    if ~isempty(cand), fr = min(cand); end
end

function s = i_polyFmt(v, nd)
%I_POLYFMT  Format angka -> string '—' bila NaN.
    if ~(isscalar(v) && isfinite(v)), s = '—'; return; end
    s = sprintf('%.*f', nd, v);
end

function i_hotToggleMeasAngle(fig)
%I_HOTTOGGLEMEASANGLE  Hotkey Ctrl+E = "klik" tombol Hitung sudut sesar. Balik
%   nilai togglebutton lalu jalankan callback-nya — persis seperti klik user
%   (tekan-1 buka sesi, tekan-2 kunci+tutup). No-op bila tombol tak ada.
    h = guidata(fig);
    if ~(isfield(h,'btnMeasAngle') && ishghandle(h.btnMeasAngle)), return; end
    cur = get(h.btnMeasAngle,'Value');
    set(h.btnMeasAngle,'Value', 1 - (cur==1));   % flip 0<->1 seperti klik toggle
    i_onToggleMeasAngle(fig);
end

function i_onToggleMeasAngle(fig)
%I_ONTOGGLEMEASANGLE  Toggle pengukur sudut sesar aktif. ON -> seed garis MIRING
%   draggable (sudut LIVE di label saat geser); OFF -> kunci + simpan ke
%   f.angleDeg (kolom Sudut tabel ter-update).
    h = guidata(fig);
    on = get(h.btnMeasAngle,'Value') == 1;
    if ~on
        % OFF: hitung final dari ROI + simpan ke f.angleDeg.
        i_captureAngle(fig, true); h = guidata(fig);
        if isfield(h,'roiFaultLine') && ~isempty(h.roiFaultLine) && isvalid(h.roiFaultLine)
            try, delete(h.roiFaultLine); catch, end
        end
        h.roiFaultLine = []; guidata(fig, h);
        set(h.btnMeasAngle,'String','Hitung sudut sesar');
        return;
    end
    % ON.
    [~, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1
        set(h.btnMeasAngle,'Value',0); pivui.setStatus(fig,'Pilih sesar aktif dulu (tabel).'); return;
    end
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain)
        set(h.btnMeasAngle,'Value',0); pivui.setStatus(fig,'axMain belum siap.'); return;
    end
    if pivui.quiet(), set(h.btnMeasAngle,'Value',0); return; end   % headless: batal
    ax = h.axMain;
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    dx = 0.20*(xl(2)-xl(1)); dy = 0.30*(yl(2)-yl(1));
    p1 = [mean(xl)-dx, mean(yl)-dy]; p2 = [mean(xl)+dx, mean(yl)+dy];
    [p1, p2] = pivcore.pot.faultAngle.enforceLeftDip(p1, p2);
    if isfield(h,'roiFaultLine') && ~isempty(h.roiFaultLine) && isvalid(h.roiFaultLine)
        try, delete(h.roiFaultLine); catch, end
    end
    % LIVE (MovingROI) -> update label saja; ROIMoved -> juga update label.
    h.roiFaultLine = pivui.makePsgLineROI(ax, p1, p2, ...
        @() i_captureAngle(fig, false), @() i_captureAngle(fig, false));
    try, h.roiFaultLine.Color = [0.80 0.15 0.15]; h.roiFaultLine.Label = 'sesar'; catch, end
    guidata(fig, h);
    i_captureAngle(fig, false);            % tampilkan sudut awal di label
    set(h.btnMeasAngle,'String','Kunci sudut ✔');
    pivui.setStatus(fig,'Seret garis SESAR di axMain — sudut update LIVE. Klik tombol lagi utk kunci & simpan.');
end

function i_captureAngle(fig, doSave)
%I_CAPTUREANGLE  Hitung sudut sesar aktif dari ROI garis sesar RELATIF detachment.
%   doSave=false -> hanya update LABEL (live saat geser). doSave=true -> simpan ke
%   f.angleDeg + refresh tabel (kolom Sudut). Bila detachment invalid, engine
%   relativeToDetachment jatuh ke sudut absolut.
    h = guidata(fig);
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, return; end
    if ~(isfield(h,'roiFaultLine') && ~isempty(h.roiFaultLine) && isvalid(h.roiFaultLine)), return; end
    pos = [];
    try, pos = h.roiFaultLine.Position; catch, end
    if isempty(pos) || size(pos,1) < 2, return; end
    det = i_detachmentDoc(h);
    deg = pivcore.pot.faultAngle.relativeToDetachment(pos(1,:), pos(2,:), det.p1, det.p2);
    % Label LIVE (selalu).
    if isfield(h,'txtFaultAngle') && ishghandle(h.txtFaultAngle)
        detStr = 'absolut'; if pivcore.pot.faultAngle.isValidDetachment(det), detStr = 'rel. detachment'; end
        set(h.txtFaultAngle,'String', sprintf('sudut sesar %s: %s °  (%s)', ...
            f.id, pivui.grain5Fmt.num2(deg), detStr));
    end
    if doSave
        f.angleDeg = deg;
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, f); guidata(fig, h);
        i_refreshFaultTable(fig);           % kolom Sudut ter-update
        i_refreshFaultAngleLabel(fig);
        pivui.setStatus(fig, sprintf('%s: sudut = %s ° dikunci & disimpan.', f.id, pivui.grain5Fmt.num2(deg)));
    end
end



% ---------------------------------------------------------------------
function h = i_buildLblTab(h, P)
%I_BUILDLBLTAB  TAB ① "Label HW" (Fase 4) = fase PENENTU garis PSG + ASSIGN
%   label + EDIT sesar (tabel sesar + assign HW/FW + titik POI + hapus/trim).
%   Blok tampilan/render/final sesar (▦ Semua sesar, Slip, zona, pengukur
%   sudut) ada di TAB ② Sesar. Tata letak rapat; tema TERANG (putih).
    WHITE = [1 1 1]; fig = h.fig;
    % --- Garis PSG tersimpan (PALING ATAS) ---
    % Tiap garis PSG = ID sendiri; "Aktifkan" -> tabel sesar (F#) MILIK garis itu
    % ter-restore (scoping multi-PSG per-F). Listbox dipersempit utk memberi ruang
    % blok "Generate N garis PSG" (GRAIN5_temp_2).
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.972 0.92 0.024],'String','Garis PSG tersimpan (tiap garis = tabel F sendiri):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    h.lstLines = uicontrol('Parent',P,'Style','listbox','Units','normalized', ...
        'Position',[0.04 0.900 0.92 0.070],'String',{}, 'FontSize',8, ...
        'TooltipString','Garis PSG ber-ID exp aktif. Klik -> bayangan posisi; Aktifkan utk pindah (tabel F ikut ganti).', ...
        'Callback',@(s,e) i_onPickLine(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.870 0.92 0.026],'String','Aktifkan garis terpilih', ...
        'TooltipString','Aktifkan garis PSG terpilih (baca + sampel POT + seed). Tabel sesar F# ganti ke garis ini.', ...
        'Callback',@(s,e) i_onActivateLine(fig));

    % (DIBUANG: tombol "Simpan garis"/"Hapus garis" + panel "★ Jadikan L1 / ⊞
    %  Generate". GRAIN4 = PEMBACA garis PSG — TIDAK menulis/menghapus/membuat garis.
    %  Garis PSG dibuat & diedit HANYA di GRAIN3a; GRAIN4 hanya memilih garis tersimpan
    %  utk dibaca + mencatat POI/deskripsi. Membiarkan tombol tulis-garis di sini
    %  membuka jalur geser/generate -> psgId berubah -> baris DESC yatim -> data
    %  hilang (insiden P-CON-F1). Baris tab digeser ke atas mengisi ruang bekas.)

    % --- Tebal garis per-kelompok (live) ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.782 0.24 0.024],'String','Tebal garis →', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.28 0.782 0.18 0.024],'String','HW/label:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edLwA = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.47 0.783 0.10 0.026],'String',sprintf('%g',h.lwAssigned), ...
        'BackgroundColor',WHITE,'TooltipString','Tebal kurva ber-label (live).', ...
        'Callback',@(s,e) i_onLineWidths(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.58 0.782 0.16 0.024],'String','mentah:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edLwR = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.75 0.783 0.10 0.026],'String',sprintf('%g',h.lwRaw), ...
        'BackgroundColor',WHITE,'TooltipString','Tebal kurva mentah belum di-assign (live).', ...
        'Callback',@(s,e) i_onLineWidths(fig));

    % --- Zoom + kunci tampilan axPOT (untuk baca bentuk kurva saat assign) ---
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.756 0.30 0.026],'String','🔍 Zoom kotak', ...
        'TooltipString','Tarik kotak di axPOT untuk zoom-in (otomatis mengunci view).', ...
        'Callback',@(s,e) pivui.grain4Shell.zoomBoxPOT(fig));
    uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.35 0.756 0.34 0.026],'String','🔓 View bebas','Value',0, ...
        'Tag','grain4ViewLock', ...
        'TooltipString',['Kunci tampilan axPOT: zoom bertahan saat Assign/pindah kurva. ' ...
        'Zoom dulu lalu kunci.'], ...
        'Callback',@(s,e) pivui.grain4Shell.setViewLock(fig, get(gcbo,'Value')==1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.70 0.756 0.26 0.026],'String','Reset view', ...
        'Callback',@(s,e) pivui.grain4Shell.resetViewPOT(fig));

    % (DIBUANG atas permintaan user: baris Label HW (dropdown+#+Assign+Unassign)
    %  + "kurva terpilih" + panel "Kurva berlabel" + Trim/Pulih/Buang/Pulih-k. —
    %  warisan GRAIN4 label-HW yang tak dipakai di workflow sesar GRAIN5. Alur GRAIN5 =
    %  klik kurva → ⬆Jadikan HW / ⬇Jadikan FW di blok SESAR. Trim/Buang kurva
    %  tetap ada di blok edit sesar & daftar Kurva kiri.)

    % --- BLOK EDIT SESAR: kini mengisi ruang penuh Tab ① (dinaikkan+diperbesar) --
    h = i_buildFaultEditBlock(h, P, fig);

    i_saveBtn(P, fig, 0.04);
end


function h = i_buildFaultEditBlock(h, P, fig)
%I_BUILDFAULTEDITBLOCK  (Fase 4b) Kontrol EDIT sesar di TAB ① Label HW: tabel
%   sesar (h.tblFault) + ➕Sesar/＋SubFault/🗑Hapus + ⬆HW/⬇FW + 4 tombol POI +
%   Hapus titik/clean plot/Hapus kurva/regen. String tombol & tag DIPERTAHANKAN
%   PERSIS (di-assert test_smoke_grain5). Callback tak berubah — hanya Parent &
%   Position. Tema TERANG.
    WHITE = [1 1 1];
    % Judul + tombol tambah/sort/edit/hapus. (SF DINONAKTIFKAN sementara: sesar
    % hanya bernomor 1,2,3,...; kolom SF read-only.)
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.744 0.92 0.022],'String','SESAR (ketik F# = angka; klik → aktif; "Edit" utk tukar-nukar nomor):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    % Baris tombol sesar: 5 kolom (+F | Sort | Edit | ⏻On/Off | Hapus). Sesar LAHIR
    % dari ISIAN tabel (ketik F#). "+F" tambah 1 slot (>15). "Sort" urut by nomor.
    % "Edit" buka kunci penomoran (duplikat OK) -> klik lagi = kunci + auto-sort.
    % "⏻ On/Off" nonaktifkan/aktifkan sesar aktif (input dipertahankan).
    bwF = 0.178; gwF = 0.006;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.718 bwF 0.032],'String','+F', ...
        'FontWeight','bold','ForegroundColor',[0 0.45 0], ...
        'TooltipString','Tambah 1 BARIS slot kosong (hanya bila butuh > 15 baris). Ketik F# di baris untuk membuat sesar.', ...
        'Callback',@(s,e) i_onFaultAddSlot(fig));
    h.btnHideFaults = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04+(bwF+gwF) 0.718 bwF 0.032],'String','👁 Sesar','Value',0, ...
        'FontWeight','bold','ForegroundColor',[0.20 0.30 0.60], ...
        'TooltipString',['Sembunyikan/tampilkan SEMUA sesar teridentifikasi di axPOT (toggle). ' ...
        'Klik = semua sesar HILANG (👁→🚫); klik lagi = tampil kembali seperti semula.'], ...
        'Callback',@(s,e) i_onToggleHideFaults(fig));
    h.btnFaultEdit = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04+2*(bwF+gwF) 0.718 bwF 0.032],'String','✎ Edit','Value',0, ...
        'FontWeight','bold','ForegroundColor',[0.20 0.30 0.60], ...
        'TooltipString',['Buka KUNCI penomoran: boleh tulis nomor apa pun TERMASUK DUPLIKAT ' ...
        '(2 baris nomor sama). Klik lagi = kunci + otomatis urutkan by nomor.'], ...
        'Callback',@(s,e) i_onFaultEditToggle(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+3*(bwF+gwF) 0.718 bwF 0.032],'String','⏻ On/Off', ...
        'FontWeight','bold','ForegroundColor',[0.55 0.35 0], ...
        'TooltipString',['Nonaktifkan/aktifkan sesar AKTIF. Sesar OFF tak dirender & tak diekspor ' ...
        '(input DIPERTAHANKAN). Bisa juga klik sel kolom ⏻ (paling kiri) di tabel.'], ...
        'Callback',@(s,e) i_onToggleActiveFault(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+4*(bwF+gwF) 0.718 bwF 0.032],'String','🗑 Hapus', ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus baris sesar aktif (terpilih). Atau kosongkan sel F# untuk menghapus baris.', ...
        'Callback',@(s,e) i_onFaultRemove(fig));
    % TABEL SESAR — model "slot spreadsheet": 15 baris slot default. Kolom F#
    % (kolom 2) EDITABLE = NOMOR sesar (angka; boleh duplikat di mode Edit).
    % Kolom SF (3) READ-ONLY (sub-fault dinonaktifkan sementara).
    % Kolom 1 "⏻" = ON/OFF sesar (klik utk toggle; hijau ✓=on, merah ✗=off).
    % Kolom 2 "✓" = indikator kelengkapan POI. Kolom 3 "F#" editable.
    % Kolom NUC=NUC-D (manual) + NUC-T (auto) ; FSR=FSR-D (manual) + FSR-T (auto).
    edCol = false(1,14); edCol(3) = true;                    % hanya F# (kol 3) editable (SF nonaktif)
    h.tblFault = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.04 0.384 0.92 0.330], ...
        'ColumnName',{'⏻','✓','F#','DX','HW','FW','NUC','NUC-T','FSR','FSR-T','ST','EN','luas','Sudut'}, ...
        'ColumnWidth',{1 22 30 26 34 34 30 34 30 34 34 34 44 40}, ...   % kol 1 (⏻) disembunyikan
        'ColumnEditable',edCol,'RowName',[],'FontSize',8, ...
        'CellEditCallback',@(s,e) i_onFaultCellEdit(fig, e), ...
        'CellSelectionCallback',@(s,e) i_onPickFaultRow(fig, e));

    % --- Assign HW/FW dari kurva terpilih ---
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.350 0.45 0.030],'String','⬆ Jadikan HW', ...
        'FontWeight','bold','ForegroundColor',[0.75 0.10 0.10], ...
        'TooltipString','Kurva terpilih (klik di axPOT) jadi HANGING WALL sesar/SF aktif.', ...
        'Callback',@(s,e) i_onFaultAssign(fig,'hw'));
    h.btnFaultFW = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.350 0.45 0.030],'String','⬇ Jadikan FW', ...
        'FontWeight','bold','ForegroundColor',[0.10 0.20 0.75], ...
        'TooltipString','Kurva terpilih jadi FOOTWALL sesar aktif. (SF: FW tak berlaku.)', ...
        'Callback',@(s,e) i_onFaultAssign(fig,'fw'));
    h.txtFaultSel = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.324 0.92 0.020],'String','kurva terpilih: —', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.15 0.30 0.55]);

    % --- Titik perkembangan sesar (+ hotkey Ctrl+1..4) + spinner geser S/E ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.296 0.42 0.022],'String','Titik POI (scrub lalu tekan / Ctrl+1..4):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',8);
    % Tombol loncat ke frame POI (siklik START→NUC→FSR→END) F# terseleksi.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.455 0.294 0.145 0.026],'String','⤓ Loncat POI', ...
        'FontSize',8,'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString',['Loncat frame aktif ke titik POI BERIKUTNYA yang sudah ada pada F# terseleksi ' ...
        '(siklik START→NUC→FSR→END).'], ...
        'Callback',@(s,e) i_onJumpPoi(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.60 0.296 0.06 0.020],'String','S:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, 0.665, 0.296, @() i_onNudgePoint(fig,'start',+1), @() i_onNudgePoint(fig,'start',-1), 'spNudgeS');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.79 0.296 0.06 0.020],'String','E:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, 0.855, 0.296, @() i_onNudgePoint(fig,'end',+1), @() i_onNudgePoint(fig,'end',-1), 'spNudgeE');
    Lp = {'START','NUC','FSR','END'}; wKind = {'start','nuc','fsr','end'}; bw = 0.227;
    % Hotkey per-KIND (urutan diminta user): START=Ctrl+1 · END=Ctrl+2 · NUC=Ctrl+3 · FSR=Ctrl+4.
    Hk = {'Ctrl+1','Ctrl+3','Ctrl+4','Ctrl+2'};   % paralel Lp: START,NUC,FSR,END
    for i = 1:4
        uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
            'Position',[0.04+(i-1)*(bw+0.01) 0.262 bw 0.030],'String',Lp{i}, ...
            'TooltipString',sprintf('Tandai %s = frame aktif (snap ke kurva HW sesar aktif). Hotkey: %s.', Lp{i}, Hk{i}), ...
            'Callback',@(s,e) i_onFaultSetPoint(fig, wKind{i}));
    end
    % Baris: Hapus titik sesar + Clean plot + Hapus kurva + Regenerate.
    bw4 = 0.223;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.228 bw4 0.030],'String','Hapus titik', ...
        'TooltipString','Hapus titik POI (START/NUC/FSR/END) sesar aktif.', ...
        'Callback',@(s,e) i_onFaultClearPoints(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+(bw4+0.008) 0.228 bw4 0.030],'String','clean plot', ...
        'TooltipString','Trim kurva terpilih -> max indenter (buang ekor pasca-sentuh; non-destruktif).', ...
        'Callback',@(s,e) pivui.grain4Shell.trimSelectedToIndenter(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+2*(bw4+0.008) 0.228 bw4 0.030],'String','Hapus kurva', ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Buang kurva terpilih dari plot (non-destruktif; sama spt Tab ② Label).', ...
        'Callback',@(s,e) pivui.grain4Shell.deleteSelectedCurves(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+3*(bw4+0.008) 0.228 bw4 0.030],'String','regen', ...
        'TooltipString','Reset plot kurva ke semula: pulihkan semua trim & kurva yang dibuang.', ...
        'Callback',@(s,e) i_onFaultRegen(fig));

    % --- Pengukur SUDUT sesar (dipindah dari Tab ②): 2 tombol ON/OFF ---
    %     Set bidang detachment = tombol toggle (ON: garis horizontal draggable;
    %     OFF: kunci+simpan sbg bidang 0°). Hitung sudut sesar = toggle (ON: garis
    %     miring draggable, sudut LIVE di label; OFF: kunci+simpan ke kolom Sudut).
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.196 0.92 0.020],'String','Sudut sesar (relatif bidang detachment):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',8);
    h.btnDetach = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 0.164 0.45 0.030],'String','Set bidang detachment','Value',0, ...
        'TooltipString',['ON: tampil garis detachment HORIZONTAL draggable di axMain (atur posisi). ' ...
        'Klik lagi (OFF): kunci & simpan sbg bidang 0° referensi sudut.'], ...
        'Callback',@(s,e) i_onToggleDetach(fig));
    h.btnMeasAngle = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.51 0.164 0.45 0.030],'String','Hitung sudut sesar','Value',0, ...
        'FontWeight','bold','ForegroundColor',[0.10 0.20 0.55], ...
        'TooltipString',['ON: tampil garis SESAR miring draggable di axMain; sudut ter-update LIVE di label ' ...
        'saat digeser. Klik lagi (OFF): kunci & simpan sudut ke kolom Sudut sesar aktif.'], ...
        'Callback',@(s,e) i_onToggleMeasAngle(fig));
    h.txtFaultAngle = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.140 0.92 0.020],'String','sudut sesar aktif: — °', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.15 0.30 0.55]);

    % --- Navigasi exp + toggles klik axPOT (kurva/frame) di DASAR tab ---
    %     (Kontrol tampilan POI-size/MA/garis-PSG ada di Tab ② Sesar.)
    h = i_clickToggles(h, P, fig, 0.04);
end


function i_saveBtn(P, fig, x)
    % TIGA tombol save & tutup di PALING DASAR tab (sedasar mungkin, tetap dalam
    % GUI). Save | Save & Tutup | Tutup. Kontrol tambahan lain diletakkan DI ATAS
    % baris ini oleh masing-masing pembangun tab.
    W = 0.96 - x; g = 0.012;
    w1 = 0.40*W; w2 = 0.34*W; w3 = W - w1 - w2 - 2*g;
    x1 = x; x2 = x1 + w1 + g; x3 = x2 + w2 + g;
    yB = 0.008; hB = 0.040;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x1 yB w1 hB],'String','💾 Save', ...
        'FontWeight','bold','BackgroundColor',[0.85 0.92 0.85], ...
        'TooltipString',['Tulis _potdata (garis/kurva/label/net-slip/setting tampilan/trim) ' ...
        '+ _comments + _faults ke disk. Komentar yang belum di-tambahkan ikut disimpan.'], ...
        'Callback',@(s,e) i_onSave(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x2 yB w2 hB],'String','💾 Save & Tutup', ...
        'FontWeight','bold','BackgroundColor',[0.80 0.90 0.80], ...
        'TooltipString','Simpan semua lalu tutup jendela.', ...
        'Callback',@(s,e) i_onSaveClose(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x3 yB w3 hB],'String','✖ Tutup', ...
        'BackgroundColor',[0.95 0.90 0.90], ...
        'TooltipString','Tutup jendela (progres tetap di-flush otomatis ke disk).', ...
        'Callback',@(s,e) i_onClose(fig));
end

function h = i_clickToggles(h, P, fig, x)
    % Navigasi eksperimen (◀ sebelumnya | berikutnya ▶) + dua checkbox seleksi
    % klik axPOT (KURVA & FRAME), TEPAT DI ATAS baris save. Diletakkan di dasar
    % kolom kanan (semua tab). Default checkbox keduanya ON.
    W = 0.96 - x; g = 0.012; w = (W - g)/2;
    % --- Navigasi Prev/Next eksperimen (pindah baris di tabel kiri; auto-flush
    %     progres exp lama lewat hook beforeLoad). ---
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x 0.120 w 0.030],'String','◀ Exp sebelumnya', ...
        'FontWeight','bold','BackgroundColor',[0.90 0.93 0.98],'FontSize',8, ...
        'TooltipString','Muat eksperimen SEBELUMNYA di daftar (progres exp kini di-flush otomatis).', ...
        'Callback',@(s,e) i_onStepExp(fig,-1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x+w+g 0.120 w 0.030],'String','Exp berikutnya ▶', ...
        'FontWeight','bold','BackgroundColor',[0.90 0.93 0.98],'FontSize',8, ...
        'TooltipString','Muat eksperimen BERIKUTNYA di daftar (progres exp kini di-flush otomatis).', ...
        'Callback',@(s,e) i_onStepExp(fig,+1));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[x 0.088 W 0.020],'String','Seleksi klik axPOT:', ...
        'HorizontalAlignment','left','FontSize',8,'ForegroundColor',[0.35 0.35 0.35], ...
        'BackgroundColor',[1 1 1]);
    % Checkbox klik kurva/frame diringkas ke KIRI; kontrol ALPHA fill sesar di
    % KANAN-JAUH (user: "taro inputnya di kanan checkbox ... kanan jauh").
    wc = 0.26;
    h.chkClickCurve = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[x 0.056 wc 0.028],'String','klik kurva','Value',1, ...
        'BackgroundColor',[1 1 1],'FontSize',8, ...
        'TooltipString','Klik kurva di axPOT -> loncat/seleksi kurva itu. Matikan bila ingin klik kurva pun memilih FRAME.', ...
        'Callback',@(s,e) i_onClickToggle(fig,'curve',get(s,'Value')==1));
    h.chkClickFrame = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[x+wc+0.01 0.056 wc 0.028],'String','klik frame','Value',1, ...
        'BackgroundColor',[1 1 1],'FontSize',8, ...
        'TooltipString','Klik di area axPOT (di luar kurva) -> pilih FRAME pada posisi-X itu + tampil di axMain.', ...
        'Callback',@(s,e) i_onClickToggle(fig,'frame',get(s,'Value')==1));
    % --- Spinner ukuran titik indikator (HW/FW + seleksi kurva) ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.545 0.056 0.075 0.024],'String','titik', ...
        'HorizontalAlignment','right','FontSize',8,'ForegroundColor',[0.35 0.35 0.35], ...
        'BackgroundColor',[1 1 1]);
    i_spinBtns(P, fig, 0.545+0.075+0.004, 0.058, @() i_onIndMarker(fig,+1), @() i_onIndMarker(fig,-1), 'spInd');
    % --- Alpha fill zona sesar (kanan jauh) ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.63 0.056 0.14 0.024],'String','α fill:', ...
        'HorizontalAlignment','right','FontSize',8,'ForegroundColor',[0.20 0.35 0.55], ...
        'BackgroundColor',[1 1 1]);
    h.edZoneAlpha = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.78 0.055 0.18 0.030],'String',sprintf('%.2f',h.zoneAlpha), ...
        'BackgroundColor',[1 1 1],'FontSize',8, ...
        'TooltipString','Transparansi fill area sesar F# (0.05–0.95). Makin besar makin PEKAT/terlihat.', ...
        'Callback',@(s,e) i_onZoneAlphaEdit(fig));
end

function i_onZoneAlphaEdit(fig)
%I_ONZONEALPHAEDIT  Set alpha fill zona dari kotak edit (kanan checkbox klik).
%   Clamp 0.05..0.95; sinkron dgn spinner/label Tab ②; render ulang.
    h = guidata(fig);
    v = h.zoneAlpha;
    try, v = str2double(get(h.edZoneAlpha,'String')); catch, end
    if ~(isscalar(v) && isfinite(v)), v = h.zoneAlpha; end
    h.zoneAlpha = max(0.05, min(0.95, v)); guidata(fig, h);
    set(h.edZoneAlpha,'String',sprintf('%.2f',h.zoneAlpha));
    if isfield(h,'txtZoneAlpha') && ishghandle(h.txtZoneAlpha)
        set(h.txtZoneAlpha,'String',sprintf('%.2f',h.zoneAlpha));
    end
    if i_faultVisible(h), pivui.grain4Shell.renderPOT(fig); end
    pivui.setStatus(fig, sprintf('Alpha fill zona sesar = %.2f.', h.zoneAlpha));
end

function i_onClickToggle(fig, which, on)
    h = guidata(fig);
    switch which
        case 'curve', h.clickCurveOn = logical(on);
        case 'frame', h.clickFrameOn = logical(on);
    end
    guidata(fig, h);
    if strcmp(which,'curve'), s='KURVA'; else, s='FRAME'; end
    pivui.setStatus(fig, sprintf('Seleksi klik %s: %s.', s, pivui.grain5Fmt.tern(logical(on),'ON','OFF')));
end

function i_onStepExp(fig, d)
%I_ONSTEPEXP  Pindah ke eksperimen berikutnya (d=+1) / sebelumnya (d=-1) di
%   daftar tabel kiri. Clamp ke [1, N]. Memuat lewat shell (loadExperiment)
%   yang otomatis memicu hook beforeLoad = flush progres exp kini dulu. Sinkron
%   sorotan tabel bila didukung. No-op bila belum ada daftar / sudah di ujung.
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list)
        pivui.setStatus(fig,'Belum ada daftar eksperimen (pilih folder dulu).'); return;
    end
    N = numel(h.list);
    cur = 1; if isfield(h,'activeRow') && isscalar(h.activeRow) && h.activeRow>=1, cur = h.activeRow; end
    tgt = min(max(cur + d, 1), N);
    if tgt == cur
        if d > 0, msg = 'Sudah di eksperimen TERAKHIR.'; else, msg = 'Sudah di eksperimen PERTAMA.'; end
        pivui.setStatus(fig, msg); return;
    end
    % AUTO-SAVE progres exp kini SEBELUM pindah (2026-07-16): tangkap edit tabel
    % DESC yang mungkin belum masuk ke h.descDoc + rebuild interpretasi, supaya
    % hook beforeLoad (yang menulis _desc.json) menyimpan keadaan tabel TERKINI.
    try
        i_captureDescFromTable(fig); h = guidata(fig);
        h.descDoc = i_descBuildInterp(fig, h.descDoc);
        guidata(fig, h);
    catch
    end
    try, h.tbl.Selection = tgt; catch, end   % sorot baris target (bila didukung)
    pivui.grain4Shell.loadExperiment(fig, tgt);
    h = guidata(fig);
    nm = ''; if tgt>=1 && tgt<=numel(h.list), nm = h.list(tgt).name; end
    pivui.setStatus(fig, sprintf('Eksperimen %d/%d: %s', tgt, N, nm));
end


% =====================================================================
% Hooks shell
% =====================================================================
function i_beforeLoad(fig) %#ok<INUSD>
%I_BEFORELOAD  (DINONAKTIFKAN 2026-07-18.) Dulu AUTO-SAVE _potdata + _desc saat
%   ganti eksperimen — menimpa data disk TANPA user klik Save. Bila tabel sedang
%   kosong/terfilter -> DATA HILANG. GRAIN4 kini TAK PERNAH menulis file tanpa
%   perintah eksplisit + konfirmasi (i_onSave). Ganti exp = buang state runtime
%   saja; pekerjaan belum-tersimpan hilang dari MEMORI (bukan dari disk) — itu
%   perilaku yang diinginkan (user simpan sendiri via tombol Save). No-op.
end

function i_onExpLoaded(fig)
    h = guidata(fig);
    h.df  = h.realData;
    h.doc = pivcore.io.grain4PotData.read(h.df);
    % Pulihkan konvensi tanda TERSIMPAN sebelum i_syncDocMeta (yang menulis
    % doc.signConvention = h.signConv) menimpanya dgn nilai default 'signed'.
    if isfield(h.doc,'signConvention') && any(strcmp(char(h.doc.signConvention),{'signed','absolute'}))
        h.signConv = char(h.doc.signConvention);
    end
    h.doc = i_syncDocMeta(h);
    h.cdoc = pivcore.io.grain4Comments.read(h.df);
    % --- Model SESAR GRAIN5 (sidecar terpisah _faults.json) ---
    h.fdoc = pivcore.io.grain5Faults.read(h.df);
    if isfield(h.fdoc,'signConvention') && any(strcmp(char(h.fdoc.signConvention),{'signed','absolute'}))
        h.signConv = char(h.fdoc.signConvention);   % fault doc = kebenaran sign GRAIN5
    end
    % SCOPING multi-PSG (GRAIN5_temp_2): reset map slot per-PSG + MIGRASI LAZY file
    % lama. Fault ber-psgId '' (dibuat GRAIN4/GRAIN5/GRAIN6 atau versi lama) -> ditandai
    % milik garis PSG PERTAMA supaya tampil di tabel garis itu (tak jadi orphan).
    h.faultSlotsByPsg = struct();
    if isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines)
        firstId = h.doc.psgLines{1}.id;
        h.fdoc = pivui.grain5Model.assignOrphanFaultsTo(h.fdoc, firstId);
    end
    % AUTO-BERSIHKAN sesar HANTU: record ber-psgId yang TIDAK ADA di psgLines
    % (garis PSG lama dihapus/diregenerasi tapi sesarnya tertinggal) -> buang &
    % SIMPAN. Mencegah #F menggelembung & duplikat (lihat pruneGhostFaults).
    realIds = i_realPsgIds(h.doc);
    [h.fdoc, nGhost] = pivui.grain5Model.pruneGhostFaults(h.fdoc, realIds);
    if nGhost > 0
        try, pivcore.io.grain5Faults.write(h.df, h.fdoc); catch, end
    end
    % PERBAIKI penomoran: NOMOR TAMPIL sesar (uiNum) harus LOKAL per garis PSG.
    % File lama/pra-multi-PSG tanpa uiNum bikin faultUiNum bocor angka id GLOBAL
    % (mis. "F11" utk sesar pertama garis-2). normalizeUiNumsPerPsg -> 1,2,3,... lokal.
    h.fdoc = pivui.grain5Model.normalizeUiNumsPerPsg(h.fdoc);
    % (AUTO-FILL F1..F15 kini PER-GARIS via i_seedFaultsForPsg saat garis diaktifkan —
    %  dipanggil dari i_activateLineById / i_initLineAndSeed. Tak lagi di sini agar
    %  tiap garis PSG punya F1..F15 SENDIRI ber-psgId benar.)
    % --- Kalibrasi sumbu cm (GRAINAXCAL, sidecar _axcal.json) ---
    % Dibaca sekali per-exp; renderMain (grain4Shell) memakainya bila enabled.
    % axCalR hanya perlu dxCm utk segitiga indenter (readGeom murah).
    h.axCal = pivcore.io.grainAxCal.read(h.df);
    dxCm = NaN; strTot = NaN;
    try, [strTot, ~, dxCm] = pivcore.export.frameCatalog.readGeom(h.df); catch, end
    h.axCalR = struct('dxCm', dxCm, 'strainTotalPct', strTot);
    % (Geometri bidang sesar kini PER-DX di _desc.json — vertices/angleDeg/lenCm
    %  per baris deskripsi + meta.refHorizonDeg. _faultgeom.json dipensiunkan.)

    h.activeFaultId = '';
    h.pts = pivcore.pot.snapPoints.emptyPts();
    h.activeHW = NaN; h.selCurveLabel='';
    if isfield(h,'popSign') && ishghandle(h.popSign)
        set(h.popSign,'Value', 1 + double(strcmp(h.signConv,'absolute')));   % selaraskan popup
    end
    if isfield(h,'popFaultSign') && ishghandle(h.popFaultSign)
        set(h.popFaultSign,'Value', 1 + double(strcmp(h.signConv,'absolute')));
    end
    guidata(fig, h);
    i_applyViewSettings(fig);     % restore setting tampilan tersimpan
    i_initLineAndSeed(fig);       % garis tersimpan -> aktif+sampel+seed; else 75% unlocked
    % Pastikan garis PSG AKTIF (apa pun jalurnya: tersimpan / autopot / 75% fresh)
    % punya F1..F15 bila belum ada sesar. Set seleksi ke sesar pertama garis itu.
    h = guidata(fig);
    if isfield(h,'activePsgId') && ~isempty(h.activePsgId)
        i_seedFaultsForPsg(fig, h.activePsgId);
        h = guidata(fig); act = i_activeFaults(h);
        if ~isempty(act), h.activeFaultId = act{1}.id; guidata(fig, h); end
    end
    i_refreshLines(fig);
    i_refreshAssignTable(fig);
    i_refreshContext(fig);
    i_refreshPoi(fig);
    i_syncTabIndicators(fig);     % on/off penanda titik/label ikut tab aktif
    pivui.grain4Shell.renderPOT(fig);
    % Data siap -> langsung tampilkan kolom KURVA di kiri (siap kerja).
    h = guidata(fig); h.leftMode = 'curve'; guidata(fig, h);
    pivui.grain4Shell.fillTable(fig);
    i_syncFaultCtrls(fig);           % selaraskan checkbox/spinner dgn state
    i_reapplyPsgStyle(fig);          % tebal/titik garis PSG ke ROI baru
    i_refreshFaultTab(fig);          % tabel sesar + render sesar aktif (GRAIN5)
    i_refreshExportTab(fig);         % (no-op di GRAIN4: tak ada tblExport)
    % GRAIN4: muat tabel DESKRIPSI dari _desc.json (bila ada) + tampilkan garis aktif.
    h = guidata(fig);
    try, h.descDoc = pivcore.io.grain4Desc.read(h.df); catch, h.descDoc = pivcore.io.grain4Desc.emptyDoc(h.df); end
    % ADOPSI baris DESC YATIM ke garis PSG aktif: bila garis PSG bergeser (id psg
    % berubah), baris DESC lama tak cocok garis mana pun -> tabel kosong walau data
    % ADA. Bila HANYA 1 garis PSG (tak ambigu), re-map baris yatim ke garis aktif
    % supaya tetap tampil. Simpan bila ada yang diadopsi (id psg baru dipersist).
    try
        [h.descDoc, nAdopt] = pivcore.io.grain4Desc.adoptOrphanRows( ...
            h.descDoc, i_realPsgIds(h.doc), h.activePsgId);
        if nAdopt > 0
            % Adopsi hanya di MEMORI (descDoc); TAK menulis file saat load (GRAIN4 tak
            % menyentuh disk tanpa Save). User klik 💾 Save utk mempersist pemulihan.
            pivui.setStatus(fig, sprintf(['%d baris deskripsi yatim (garis PSG bergeser) ' ...
                'dipulihkan ke garis aktif — klik 💾 Save utk simpan.'], nAdopt));
        end
    catch
    end
    try, h.interpDoc = pivcore.io.grain4Interp.read(h.df); catch, h.interpDoc = pivcore.io.grain4Interp.emptyDoc(h.df); end
    try, h.taperInterpDoc = pivcore.io.grain4TaperInterp.read(h.df); catch, h.taperInterpDoc = pivcore.io.grain4TaperInterp.emptyDoc(h.df); end
    h.detMap = containers.Map('KeyType','double','ValueType','char');   % reset Deteksi (per-exp)
    h.taperSamples = containers.Map('KeyType','char','ValueType','any'); % reset cache interp taper (per-exp)
    h.descSelRow = [];
    guidata(fig, h);
    % Sinkronkan kotak KETEBALAN model dgn nilai tersimpan exp ini.
    if isfield(h,'edModelThick') && ishghandle(h.edModelThick)
        try, set(h.edModelThick,'String', num2str(pivcore.io.grain4Desc.modelThicknessCm(h.descDoc))); catch, end
    end
    i_rebuildAllTaperTracks(fig);   % cache + track interpolasi taper SEMUA F# (bayangan + sidecar kerja)
    i_refreshDescTable(fig);
    try, pivui.grain4Shell.renderPOT(fig); catch, end   % garis vertikal penanda DESC tampil saat exp dibuka
    % TERAKHIR: terapkan ZOOM X-window tersimpan (potXPct) SETELAH semua render
    % (renderPOT/refreshFaultTab set XLim auto). Supaya load awal langsung di zoom
    % horizontal sesi sebelumnya.
    i_applyPotXLim(fig);
end

function i_syncFaultCtrls(fig)
%I_SYNCFAULTCTRLS  Selaraskan tampilan kontrol tab ① dgn state (checkbox Value,
%   alpha/palet zona, window MA). Dipanggil saat exp dimuat.
    h = guidata(fig);
    if isfield(h,'txtZoneAlpha') && ishghandle(h.txtZoneAlpha), set(h.txtZoneAlpha,'String',sprintf('%.2f',h.zoneAlpha)); end
    if isfield(h,'edZoneAlpha') && ishghandle(h.edZoneAlpha), set(h.edZoneAlpha,'String',sprintf('%.2f',h.zoneAlpha)); end
    if isfield(h,'popZonePalette') && ishghandle(h.popZonePalette)
        set(h.popZonePalette,'Value', 1 + double(strcmp(h.zonePalette,'ngejreng')));
    end
    if isfield(h,'chkMA') && ishghandle(h.chkMA), set(h.chkMA,'Value',double(h.maOn)); end
    if isfield(h,'txtMAwin') && ishghandle(h.txtMAwin), set(h.txtMAwin,'String',sprintf('w=%d',h.maWin)); end
    if isfield(h,'btnShowAll') && ishghandle(h.btnShowAll), set(h.btnShowAll,'Value',double(h.showAllFaults)); end
    if isfield(h,'chkFaultLabel') && ishghandle(h.chkFaultLabel), set(h.chkFaultLabel,'Value',double(h.faultLabelOn)); end
    if isfield(h,'chkClickCurve') && ishghandle(h.chkClickCurve), set(h.chkClickCurve,'Value',double(h.clickCurveOn)); end
    if isfield(h,'chkClickFrame') && ishghandle(h.chkClickFrame), set(h.chkClickFrame,'Value',double(h.clickFrameOn)); end
    if isfield(h,'popFaultLabelPos') && ishghandle(h.popFaultLabelPos)
        set(h.popFaultLabelPos,'Value', 1 + double(strcmp(h.faultLabelPos,'center')));
    end
    % (Blok "Generate N garis PSG" dibuang — GRAIN4 tak membuat garis.)
end

function i_onLineChanged(fig)
%I_ONLINECHANGED  (GRAIN4 = PEMBACA garis, BUKAN penulis.) Garis PSG di GRAIN4 BEKU:
%   id + geometri berasal dari _potdata.json (GRAIN3a) dan TAK PERNAH dihitung ulang
%   dari koordinat runtime. Dulu fungsi ini `psgId.fromLine(h.line)` lalu menimpa
%   h.activePsgId -> geseran ROI beberapa px (bahkan re-snap render saat STARTUP)
%   bikin id BARU -> semua baris DESC ber-psgId lama JADI YATIM -> tabel kosong ->
%   Save menimpa kosong -> DATA HILANG (insiden P-CON-F1). Kini activePsgId DIKUNCI
%   ke id tersimpan (lihat i_freezePsgLine); hook ini hanya menyegarkan tampilan.
    i_clearGhostLine(fig);            % fokus pindah -> bayangan hilang
    i_refreshLines(fig); i_drawAnnotForActive(fig);
    i_refreshContext(fig);
end

function i_onPotChanged(fig)
    h = guidata(fig);
    % Re-seed dari _potdata HANYA saat POT baru DI-SAMPEL ULANG (recs segar,
    % belum ter-edit). Aksi edit (Buang/Pulih, Trim/un-trim) juga memicu hook ini
    % TAPI recs sudah membawa keadaan TERKINI -> lewati bila recs sudah "hidup".
    % PENTING (alur fault-first): pulihkan cutFrame/excluded WALAU tak ada label
    % HW — supaya clean-plot & hapus-kurva PERSISTEN lintas eksperimen. Kriteria
    % "recs hidup" diperluas: ber-label ATAU sudah ada trim/excluded.
    if strcmp(h.df, h.realData) && ~i_recsAreEdited(h.recs)
        [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, h.activePsgId);
        if idx >= 1 && (i_lineHasLabels(ln) || i_lineHasCuts(ln))
            h.recs = i_applyDocLabels(h.recs, ln);   % pulihkan label + trim + excluded
            h.recs = pivcore.pot.records.applyColors(h.recs);
            guidata(fig, h);
        end
    end
    i_refreshAssignTable(fig); i_refreshPoi(fig);
end

function tf = i_recsAreEdited(recs)
%I_RECSAREEDITED  TRUE bila recs sudah "hidup" (hasil edit): ber-label ATAU ada
%   kurva ter-trim / dibuang. Cegah re-seed menimpa keadaan terkini user.
    tf = false;
    for r = 1:numel(recs)
        if ~isempty(pivcore.pot.records.label(recs(r))), tf = true; return; end
        if isfield(recs(r),'cutManual') && isscalar(recs(r).cutManual) && recs(r).cutManual, tf = true; return; end
        if isfield(recs(r),'excluded') && isscalar(recs(r).excluded) && logical(recs(r).excluded), tf = true; return; end
    end
end

function tf = i_lineHasCuts(ln)
%I_LINEHASCUTS  TRUE bila garis tersimpan punya >=1 kurva ber-cutFrame / excluded.
    tf = false;
    if ~isstruct(ln) || ~isfield(ln,'curves'), return; end
    for k = 1:numel(ln.curves)
        c = ln.curves{k};
        if ~isstruct(c), continue; end
        if isfield(c,'cutFrame') && isscalar(c.cutFrame) && isfinite(c.cutFrame), tf = true; return; end
        if isfield(c,'excluded') && isscalar(c.excluded) && logical(c.excluded), tf = true; return; end
    end
end

function tf = i_recsHaveLabels(recs)
%I_RECSHAVELABELS  TRUE bila ada >=1 record kurva sudah ber-label (HW/F/F0/FFW).
%   Penanda recs "hidup" (hasil edit) vs recs segar pasca-sampling ulang.
    tf = false;
    for r = 1:numel(recs)
        if ~isempty(pivcore.pot.records.label(recs(r))), tf = true; return; end
    end
end

function i_onCurveClick(fig, r)
    h = guidata(fig);
    if r >= 1 && r <= numel(h.recs)
        % Sumber seleksi: klik BARIS TABEL vs klik kurva di axPOT. Auto-scroll
        % HANYA saat dari axPOT (klik tabel sudah menampilkan barisnya sendiri;
        % scroll saat itu = lari-lari).
        fromTable = false;
        try
            co = get(fig,'CurrentObject');
            fromTable = ~isempty(co) && isfield(h,'tbl') && isequal(co, h.tbl);
        catch
        end
        h.selCurveLabel = i_curveLabelAt(h, r); guidata(fig, h);
        i_refreshContext(fig); i_refreshPoi(fig);
        % (h.txtSel dibuang — info kurva terpilih tampil via txtFaultSel di blok sesar)
        if i_faultVisible(h) && isfield(h,'txtFaultSel') && ishghandle(h.txtFaultSel)
            pp = NaN; if isfield(h.recs(r),'posPx')&&isscalar(h.recs(r).posPx), pp=h.recs(r).posPx; end
            set(h.txtFaultSel,'String', ...
                sprintf('kurva terpilih: #%d  posPx=%s  → tekan Jadikan HW / FW', r, pivui.grain5Fmt.numDash(pp)));
        end
        if ~fromTable, i_scrollCurveTable(fig, r); end   % geser tabel -> baris kelihatan (mulus)
    end
end

function i_scrollCurveTable(fig, row)
%I_SCROLLCURVETABLE  Geser viewport tabel KURVA supaya baris `row` KELIHATAN saat
%   kurva diklik di axPOT. HANYA `scroll(tbl,'row',row)` (baris itu sendiri —
%   masuk viewport, TAK melompat ke akhir; tak ada offset "+15" yang bikin loncat
%   aneh di baris akhir). TIDAK men-set `Selection` (memicu loop "lari-lari").
    h = guidata(fig);
    if ~(isfield(h,'tbl') && ishghandle(h.tbl)), return; end
    if ~(isfield(h,'leftMode') && strcmp(h.leftMode,'curve')), return; end
    n = numel(h.recs);
    if ~(isscalar(row) && isfinite(row) && row>=1 && row<=n), return; end
    try, scroll(h.tbl, 'row', row); catch, end
end

function i_onFrameChanged(fig), i_refreshContext(fig); i_refreshPoi(fig); i_ensurePotXShowsFrame(fig); i_applyPotXLim(fig); i_autoSelDescForFrame(fig); end

function i_ensurePotXShowsFrame(fig)
%I_ENSUREPOTXSHOWSFRAME  Saat jendela X axPOT/AXSLIP di-zoom (potXWin>0), pastikan
%   FRAME AKTIF selalu masuk jendela: bila frame keluar rentang tampil sekarang,
%   geser potXCenter secukupnya (margin ~15% lebar) supaya garis frame/POI
%   terlihat. Berlaku SERAGAM utk axPOT & AXSLIP (satu sumber X-window). Tak
%   mengubah lebar jendela. No-op saat tampil penuh (potXWin<=0).
%   Ini yang membuat loncat DX (Ctrl+H/O, klik baris DESC, J/K/L/;) menggeser
%   fokus pengamatan meski sedang zoom pada AXSLIP.
    h = guidata(fig);
    if ~(isfield(h,'potXWin') && isscalar(h.potXWin) && isfinite(h.potXWin) && h.potXWin>0), return; end
    nF = max(h.nF,2); w = h.potXWin; if w >= nF, return; end
    f = round(pivcore.util.scalarOr(h.frame,1)); f = max(1, min(nF, f));
    c = h.potXCenter; if ~isfinite(c), c = f; end
    lo = round(c - w/2); hi = lo + w - 1;      % rentang tampil sekarang (sebelum clamp tepi)
    mrg = max(1, round(0.15*w));
    if f < lo + mrg || f > hi - mrg
        h.potXCenter = f;                       % pusatkan ke frame aktif
        guidata(fig, h);
    end
end

function i_autoSelDescForFrame(fig)
%I_AUTOSELDESCFORFRAME  Saat frame scrubber mendarat di frame yg punya DX untuk
%   (F# AKTIF, garis PSG aktif) -> otomatis SELECT baris DX itu di tabel (sorot +
%   Selection). Tak loncat frame (kita SUDAH di frame itu). No-op bila tak ada DX
%   padanan. Dipanggil di ekor i_onFrameChanged.
    h = guidata(fig);
    if ~(isfield(h,'tblDesc') && ishghandle(h.tblDesc)), return; end
    if ~isfield(h,'descDoc') || ~isstruct(h.descDoc), return; end
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    % F# aktif (bila ada) -> cocokkan DX per (F#, frame); bila tak ada sesar aktif,
    % cocokkan per-frame saja (garis PSG aktif).
    fNum = '';
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx >= 1
        u = i_uiNumStr(f);
        if ~isempty(u) && ~strcmp(u,'—'), fNum = ['F' u]; end
    end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    hit = 0;
    for k = 1:numel(rows)
        v = rows{k}.frame;
        if ~(isscalar(v) && isfinite(v) && round(v)==frameLive), continue; end
        if ~isempty(fNum) && ~strcmp(strtrim(rows{k}.fNum), fNum), continue; end
        hit = k; break;
    end
    if hit < 1, return; end
    i_selectDescByFullIdx(fig, hit);   % sorot + Selection (tak loncat frame)
end
function i_freezePsgLine(fig)
%I_FREEZEPSGLINE  (GRAIN4 = PEMBACA garis.) Kunci garis PSG supaya TAK bisa digeser
%   dan TAK bisa tercemar oleh ROI. Dipanggil tiap afterRenderMain karena
%   renderMain shell (bersama GRAIN5/GRAIN6) MEMBUAT ULANG ROI draggable + menimpa
%   h.line dari ROI setiap frame. Di GRAIN4 kita netralkan itu SETEMPAT:
%     (1) ROI garis PSG dijadikan non-interaktif (tak bisa diseret mouse).
%     (2) h.line + h.activePsgId di-RE-ASSERT ke garis TERSIMPAN aktif (id +
%         koordinat asli dari _potdata.json) — pembulatan float ROI tak menggeser
%         id melewati grid psgId -> baris DESC tak pernah jadi yatim.
    h = guidata(fig);
    % (1) Bekukan ROI garis PSG (bila ada). Alat Tab ② (sesar/detach/taper) pakai
    %     ROI TERPISAH (h.roiFaultLine dsb.) — tak disentuh di sini.
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi)
        try, h.roi.InteractionsAllowed = 'none'; catch, end
    end
    % (2) Re-assert geometri+id dari garis TERSIMPAN aktif. Bila garis aktif tak
    %     ada di doc (mis. belum ada garis) -> jangan paksa apa-apa.
    id = ''; if isfield(h,'activePsgId'), id = char(h.activePsgId); end
    if ~isempty(id) && isstruct(h.doc)
        [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, id);
        if idx >= 1 && all(isfinite([ln.p1(:); ln.p2(:)])')
            frac = NaN; if isfield(ln,'frac'), frac = ln.frac; end
            h.line = struct('p1', ln.p1(:).', 'p2', ln.p2(:).', 'frac', frac);
            guidata(fig, h);
        end
    end
end

function i_afterRenderMain(fig)
    i_freezePsgLine(fig);   % GRAIN4: garis PSG BEKU — ROI non-interaktif + h.line/psgId
                            % dikunci ke garis tersimpan (renderMain shell menghidupkan
                            % ROI draggable tiap frame; netralkan SETIAP render).
    % Terapkan ULANG tinggi axMain (GRAIN4): renderMain menambah colorbar tiap render
    % -> axes menyusut ke default. Kembalikan ke h.axMainPos supaya axMain TETAP
    % tinggi setelah load/scrub. Colorbar sudah dibuat (afterRenderMain pasca-render)
    % -> set Position hanya mengembalikan tinggi axes, colorbar tetap di kanan.
    h = guidata(fig);
    if isfield(h,'axMainPos') && numel(h.axMainPos)==4 ...
            && isfield(h,'axMain') && ishghandle(h.axMain)
        try
            cur = get(h.axMain,'Position');
            if any(abs(cur - h.axMainPos) > 1e-4)
                set(h.axMain,'Position', h.axMainPos);
            end
        catch, end
    end
    i_fillAxMainHeight(fig);   % isi TINGGI box axMain (1:1 -> whitespace atas-bawah)
    i_drawBufferPreview(fig); i_drawAnnotForActive(fig); i_drawFaultPsgMarker(fig);
    i_drawStoredFaultPolylines(fig);   % overlay garis sesar persisten (frame FS-max)
    i_drawInterpPolylines(fig);        % overlay EVOLUSI interpolasi (cyan) bila interpOn
    i_drawOtherFaultShadows(fig);      % BAYANGAN MERAH sesar-lain (visual aid; bila interpOn)
    i_drawStoredTaperLines(fig);       % overlay garis TAPER persisten (DX frame live)
    i_drawStoredRefHoriz(fig);         % overlay garis REF HORIZONTAL tersimpan (datum kedalaman)
    i_drawStoredMetaLines(fig);        % overlay DINDING PEMBATAS + BASE tersimpan (koordinat robust)
    i_drawStoredNucPoints(fig);        % overlay TITIK NUKLEASI persisten (DX NUC-FSR frame live)
    i_drawTaperInterp(fig);            % overlay interpolasi TAPER (hijau muda) bila On
    i_applyAxMainZoomMode(fig);   % pasang ulang interaksi zoom (render me-null-kan tiap frame)
    i_applyAxMainViewLock(fig);   % pertahankan zoom/pan beku (render reset ke full)
end

function i_fillAxMainHeight(fig)
%I_FILLAXMAINHEIGHT  Buat gambar 1:1 MENGISI TINGGI box axMain (GRAIN4). Masalah:
%   renderMain memakai daspect([1 1 1]) + xlim/ylim=ekstent data. Utk gambar
%   LEBAR-PENDEK (xspan >> yspan), MATLAB MENYUSUTKAN plot box vertikal agar 1:1 ->
%   axMain terlihat "kecil/pendek" walau Position besar. Solusi: PERBESAR YLim
%   (tambah margin atas-bawah SIMETRIS) sampai rasio data (xspan/yspan) == rasio
%   BOX axes (lebarPx/tinggiPx) -> gambar 1:1 mengisi tinggi box PENUH, whitespace
%   jadi di DATA (atas-bawah) bukan box yg menyusut. Hormati KUNCI PANDANG (skip
%   bila view dikunci -> XLim/YLim user dipakai apa adanya).
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if isfield(h,'axMainViewLock') && h.axMainViewLock, return; end   % hormati kunci
    ax = h.axMain;
    try
        if ~strcmp(get(ax,'DataAspectRatioMode'),'manual'), return; end
        da = get(ax,'DataAspectRatio');
        if ~(numel(da)>=2 && da(1)==da(2)), return; end   % hanya saat 1:1 (x:y sama)
    catch, return; end
    % Rasio box axes dalam PIXEL (lebar/tinggi).
    oldU = get(ax,'Units');
    try
        set(ax,'Units','pixels'); ppx = get(ax,'Position'); set(ax,'Units',oldU);
    catch
        set(ax,'Units',oldU); return;
    end
    boxW = ppx(3); boxH = ppx(4);
    if ~(boxW>0 && boxH>0), return; end
    boxAspect = boxW / boxH;                 % >1 = box lebih lebar dari tinggi
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    xspan = diff(xl); yspan = diff(yl);
    if ~(xspan>0 && yspan>0), return; end
    dataAspect = xspan / yspan;
    % Agar 1:1 mengisi box penuh: xspan/yspanTarget == boxAspect -> yspanTarget =
    % xspan/boxAspect. Bila data lebih "lebar" dari box (dataAspect>boxAspect),
    % yspan perlu DIPERBESAR (tambah whitespace atas-bawah). Bila sudah <=, biarkan
    % (gambar sudah mengisi tinggi; menambah lebar bukan tujuan).
    if dataAspect <= boxAspect + 1e-6, return; end
    yspanTarget = xspan / boxAspect;
    yc = mean(yl);
    ylNew = [yc - yspanTarget/2, yc + yspanTarget/2];
    try, set(ax,'YLim', ylNew); catch, end
end

function i_drawStoredTaperLines(fig)
%I_DRAWSTOREDTAPERLINES  Overlay PERSISTEN garis TAPER per-DX di axMain: tiap baris
%   DESKRIPSI (garis PSG aktif) yg frame==frame live & punya taperVerts (>=2) ->
%   garis HIJAU (Tag 'storedTaper'). Ikut ter-ekspor. Dilewati bila alat taper
%   sedang aktif utk DX itu (ROI editable sudah tampil).
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    try, delete(findall(h.axMain,'Tag','storedTaper')); catch, end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(rows), return; end
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    editIdx = []; if isfield(h,'taperOn') && h.taperOn && isfield(h,'taperDxIdx'), editIdx = h.taperDxIdx; end
    ax = h.axMain; washold = ishold(ax); hold(ax,'on');
    for k = 1:numel(rows)
        if ~isempty(editIdx) && k == editIdx, continue; end    % sedang diedit
        r = rows{k};
        if ~(isscalar(r.frame) && isfinite(r.frame) && round(r.frame)==frameLive), continue; end
        V = pivcore.io.grain4Desc.normVerts(r.taperVerts);
        if size(V,1) < 2, continue; end
        plot(ax, V(:,1), V(:,2), '-', 'Color',[0.10 0.55 0.20], 'LineWidth',1.6, ...
            'Marker','o','MarkerSize',3,'MarkerFaceColor',[0.10 0.55 0.20], ...
            'Tag','storedTaper','Clipping','on');
    end
    if ~washold, hold(ax,'off'); end
end

function i_drawStoredNucPoints(fig)
%I_DRAWSTOREDNUCPOINTS  Overlay PERSISTEN titik nukleasi per-DX di axMain: tiap
%   baris DESKRIPSI (garis PSG aktif) yg frame==frame live & punya titik nukleasi
%   -> penanda ★ CYAN di posisi nukleasi (vertex-1; data lama garis 2-titik ->
%   vertex-1). Ikut ter-ekspor. Dilewati bila alat titik nukleasi sedang aktif.
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    try, delete(findall(h.axMain,'Tag','storedNucPt')); catch, end
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(rows), return; end
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    editIdx = []; if isfield(h,'nucPtOn') && h.nucPtOn && isfield(h,'nucPtDxIdx'), editIdx = h.nucPtDxIdx; end
    ax = h.axMain; washold = ishold(ax); hold(ax,'on');
    col = [0.10 0.55 0.75];
    for k = 1:numel(rows)
        if ~isempty(editIdx) && k == editIdx, continue; end
        r = rows{k};
        if ~(isscalar(r.frame) && isfinite(r.frame) && round(r.frame)==frameLive), continue; end
        p = pivcore.io.grain4Desc.nucPointPx(r.nucVerts);   % titik nukleasi (vertex-1)
        if isempty(p), continue; end
        plot(ax, p(1), p(2), 'p', 'MarkerSize',12, 'MarkerFaceColor',col, ...
            'MarkerEdgeColor',[0 0.2 0.35], 'Tag','storedNucPt','Clipping','on');
    end
    if ~washold, hold(ax,'off'); end
end

function i_drawStoredFaultPolylines(fig)
%I_DRAWSTOREDFAULTPOLYLINES  Overlay PERSISTEN bidang sesar PER-DX di axMain.
%   Tiap baris DESKRIPSI (garis PSG aktif) yg frame-nya == frame live DAN punya
%   vertices (>=2) -> gambar polyline HITAM TANPA label (sudah jelas terikat POI
%   itu). Ikut ter-EKSPOR saat commit (di-render di axMain). Redraw tiap
%   renderMain (afterRenderMain). Tag 'storedFaultPoly'. Skip DX yg sedang di-
%   edit ROI (biar tak dobel).
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if ~(isfield(h,'descDoc') && isstruct(h.descDoc)), return; end
    try, delete(findall(h.axMain,'Tag','storedFaultPoly')); catch, end
    ax = h.axMain;
    frameLive = round(pivcore.util.scalarOr(h.frame,1));
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    if isempty(rows), return; end
    editIdx = 0;
    if isfield(h,'faultPolyOn') && h.faultPolyOn && isfield(h,'faultPolyDxIdx')
        editIdx = h.faultPolyDxIdx;
    end
    washold = ishold(ax); hold(ax,'on');
    for k = 1:numel(rows)
        if k == editIdx, continue; end
        r = rows{k};
        v = r.frame;
        if ~(isscalar(v) && isfinite(v) && round(v) == frameLive), continue; end
        V = pivcore.io.grain4Desc.normVerts(r.vertices);
        if size(V,1) < 2, continue; end
        plot(ax, V(:,1), V(:,2), '-', 'Color',[0 0 0], 'LineWidth',1.6, ...
            'Marker','none', 'Tag','storedFaultPoly', 'Clipping','on');
    end
    if ~washold, hold(ax,'off'); end
end

function i_applyAxMainViewLock(fig)
%I_APPLYAXMAINVIEWLOCK  Bila kunci pandang axMain aktif, re-set XLim/YLim ke view
%   beku (h.axMainViewLim). renderMain shell reset ke ekstent penuh tiap frame; hook
%   ini dipanggil SESUDAHNYA. TETAP 1:1 (daspect([1 1 1]) dari renderMain TAK diubah).
    h = guidata(fig);
    if ~(isfield(h,'axMainViewLock') && h.axMainViewLock), return; end
    if ~(isfield(h,'axMainViewLim') && numel(h.axMainViewLim)==4), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    L = h.axMainViewLim;
    try
        set(h.axMain,'XLim',L(1:2),'YLim',L(3:4));
    catch
    end
end

function i_setAxMainLockListener(fig, on)
%I_SETAXMAINLOCKLISTENER  Pasang/lepas listener anti-FLICKER kunci pandang axMain.
%   MASALAH (terbukti via probe): saat lock ON, 1x ganti frame -> XLim di-SET 5 KALI
%   berayun: PENUH -> zoom -> PENUH LAGI -> zoom -> zoom. Dua reset ke PENUH
%   (renderMain `xlim(ax,xExt)` + re-render overlay/colorbar) di-PAINT sesaat ->
%   ISI axMain terlihat zoom-out lalu zoom-in = FLICKER KONTEN. Listener MarkedClean
%   jalan saat PAINT (terlambat: paint penuh sudah tampil).
%   FIX: listener **PostSet** pada XLim & YLim. PostSet dipicu SEGERA saat properti
%   di-set (SINKRON, sebelum paint) -> tiap upaya set-ke-PENUH langsung DITIMPA ke
%   view beku dalam callback set yg sama -> tak ada satu pun paint limit penuh.
%   Guard re-entrancy via appdata (menimpa XLim memicu PostSet lagi). Aman-gagal.
    h = guidata(fig);
    % Selalu buang listener lama dulu (idempoten; hindari dobel). Bisa array (X+Y).
    if isfield(h,'axMainLockLsnr') && ~isempty(h.axMainLockLsnr)
        try, delete(h.axMainLockLsnr); catch, end
        h.axMainLockLsnr = []; guidata(fig, h);
    end
    if ~on, return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    try
        lx = addlistener(h.axMain, 'XLim', 'PostSet', @(s,e) i_onAxMainLimPostSet(fig));
        ly = addlistener(h.axMain, 'YLim', 'PostSet', @(s,e) i_onAxMainLimPostSet(fig));
        h.axMainLockLsnr = [lx, ly];
        guidata(fig, h);
    catch
    end
end

function i_onAxMainLimPostSet(fig)
%I_ONAXMAINLIMPOSTSET  Callback PostSet XLim/YLim axMain: bila kunci pandang aktif &
%   limit menyimpang dari view beku -> TIMPA ke beku SEGERA (sinkron, sebelum paint).
%   Inilah anti-flicker ISI: renderMain reset XLim/YLim ke PENUH tiap frame; PostSet
%   dipicu SAAT set itu -> langsung timpa balik ke zoom SEBELUM MATLAB mem-paint ->
%   ISI axMain tak pernah terlihat zoom-out. TETAP 1:1 (daspect TAK disentuh). Guard
%   re-entrant via appdata (menimpa XLim memicu PostSet lagi).
%
%   BERLAKU JUGA saat alat ROI aktif (Ctrl+Q bidang sesar / Ctrl+W taper / ref
%   horizontal): TANPA ini, render/overlay saat alat ON mereset XLim ke penuh & tak
%   ditimpa -> ISI zoom-out (flicker) yg dikeluhkan user. AMAN: PostSet hanya menimpa
%   XLim/YLim axes; drag ROI mengubah POSISI VERTEX (i_updateFaultPoly/i_updateTaper
%   cuma refresh label, TAK menyentuh XLim) -> tak bertabrakan.
    if ~ishghandle(fig), return; end
    if isappdata(fig,'axMainLockBusy') && getappdata(fig,'axMainLockBusy'), return; end
    h = guidata(fig);
    if ~(isfield(h,'axMainViewLock') && h.axMainViewLock), return; end
    if ~(isfield(h,'axMainViewLim') && numel(h.axMainViewLim)==4), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    L = h.axMainViewLim; ax = h.axMain;
    cx = get(ax,'XLim'); cy = get(ax,'YLim');
    if isequal(cx(:).',L(1:2)) && isequal(cy(:).',L(3:4)), return; end   % sudah beku
    setappdata(fig,'axMainLockBusy',true);
    try
        set(ax,'XLim',L(1:2),'YLim',L(3:4));
    catch
    end
    setappdata(fig,'axMainLockBusy',false);
end

function i_onAxMainZoom(fig)
%I_ONAXMAINZOOM  Toggle mode ZOOM/PAN interaktif pada axMain. ON: aktifkan zoom
%   (scroll) + pan (drag) HANYA pada axMain via ax.Interactions MODERN (bukan mode
%   zoom() klasik). OFF: matikan + reset ke tampilan penuh (buang kunci pandang).
%   CATATAN: renderMain shell memanggil pivui.lockAxInteractions(axMain) TIAP frame
%   (ax.Interactions=[] -> scroll/pan MATI). Karena itu interaksi zoom DIPASANG-ULANG
%   di i_afterRenderMain (via i_applyAxMainZoomMode) selama mode ON; tombol klasik
%   zoom()/pan() DITINGGALKAN (sumber warning mode-manager "not permitted").
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum ada.'); return;
    end
    want = ~h.axMainZoomOn;
    if want
        h.axMainZoomOn = true; guidata(fig, h);
        i_applyAxMainZoomMode(fig);   % pasang zoomInteraction+panInteraction + toolbar
        set(h.btnAxZoom,'Value',1);
        pivui.setStatus(fig,'Zoom axMain AKTIF: scroll=zoom, drag=geser. Klik 🔒 utk kunci pandang.');
    else
        h.axMainZoomOn = false; h.axMainViewLock = false; h.axMainViewLim = [];
        guidata(fig, h);
        i_setAxMainLockListener(fig, false);  % zoom OFF juga melepas kunci -> buang listener
        try, set(h.btnAxViewLock,'Value',0); catch, end
        set(h.btnAxZoom,'Value',0);
        % Reset ke ekstent penuh: render ulang axMain (xlim/ylim kembali ke xExt/yExt);
        % renderMain juga lockAxInteractions -> interaksi zoom mati (mode OFF, benar).
        try, pivui.grain4Shell.renderMain(fig); catch, end
        pivui.setStatus(fig,'Zoom axMain MATI: tampilan penuh dipulihkan.');
    end
end

function i_applyAxMainZoomMode(fig)
%I_APPLYAXMAINZOOMMODE  Bila mode zoom axMain ON (h.axMainZoomOn), PASANG-ULANG
%   interaksi scroll-zoom + drag-pan pada axMain via ax.Interactions MODERN +
%   pulihkan Toolbar. renderMain shell me-null-kan ax.Interactions tiap frame, jadi
%   helper ini dipanggil SESUDAH tiap render (i_afterRenderMain) supaya zoom tak
%   "mati sendiri" saat scrub. Aman-gagal lintas-versi. Tak melakukan apa pun bila
%   mode OFF (axes tetap terkunci spt default garis PSG).
    h = guidata(fig);
    if ~(isfield(h,'axMainZoomOn') && h.axMainZoomOn), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    ax = h.axMain;
    try, enableDefaultInteractivity(ax); catch, end
    try
        ax.Interactions = [zoomInteraction('Dimensions','xy'); panInteraction()];
    catch
        try, ax.Interactions = [zoomInteraction; panInteraction]; catch, end
    end
    try, ax.Toolbar = axtoolbar(ax, {'zoomin','zoomout','pan','restoreview'}); catch, end
end

function i_suspendAxZoomForRoi(fig)
%I_SUSPENDAXZOOMFORROI  Matikan MODE interaktif zoom/pan MATLAB pada axMain SUPAYA
%   kursor jadi crosshair utk input vertex ROI (drawpolyline/images.roi.*). Tanpa
%   ini, saat zoom aktif kursor tetap "kaca pembesar" & klik = zoom (bukan taruh
%   vertex). KUNCI PANDANG (axMainViewLim + XLim/YLim zoom-in) DIPERTAHANKAN — yg
%   dimatikan hanya INTERAKSI zoom, bukan view. Tombol 🔍 disinkron OFF supaya
%   status UI konsisten ("sudah dikunci -> tak bisa zoom lagi"). Aman-gagal.
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    % Rekam limit view saat ini supaya PASTI tak berubah saat mode dimatikan.
    xl = []; yl = [];
    try, xl = get(h.axMain,'XLim'); yl = get(h.axMain,'YLim'); catch, end
    try, zoom(h.axMain,'off'); catch, end
    try, pan(fig,'off'); catch, end
    % Matikan JUGA interaksi MODERN (ax.Interactions) supaya kursor jadi crosshair
    % utk input vertex ROI (bukan zoom). lockAxInteractions = null-kan Interactions.
    try, pivui.lockAxInteractions(h.axMain); catch, end
    % Interaksi zoom mati -> update state & tombol (tapi kunci pandang tetap ON).
    if isfield(h,'axMainZoomOn'), h.axMainZoomOn = false; end
    guidata(fig, h);
    try, if isfield(h,'btnAxZoom') && ishghandle(h.btnAxZoom), set(h.btnAxZoom,'Value',0); end, catch, end
    % Kembalikan limit view (mematikan mode kadang me-reset sedikit) + kunci ulang.
    if numel(xl)==2 && numel(yl)==2
        try, set(h.axMain,'XLim',xl,'YLim',yl); catch, end
    end
    i_applyAxMainViewLock(fig);
end

function i_reclaimFigureKeys(fig)
%I_RECLAIMFIGUREKEYS  Saat mode zoom/pan MATLAB aktif, mode-manager memasang
%   window key-listener yg MEMBAJAK keypress figure -> WindowKeyPressFcn kustom
%   (hotkey Ctrl+,/. langkah frame, Ctrl+1..4 POI, dst.) TAK terpanggil. Helper
%   ini menonaktifkan listener mode-manager itu sehingga hotkey figure kembali
%   berfungsi walau zoom/kunci pandang ON. Aman-gagal (try/catch) bila API
%   uigetmodemanager berubah antar-rilis.
    % Bila MODE interaktif (zoom/pan) sedang AKTIF, MATLAB MELARANG set
    % WindowKeyPressFcn/ButtonDownFcn -> memicu warning "not permitted while this
    % mode is active". Karena itu: bila mode aktif, NONAKTIFKAN dulu interaksinya
    % (tanpa mengganggu view/kunci), BARU set handler. Bila mode tak aktif, set
    % langsung. Semua di-guard supaya senyap.
    try
        modeActive = false;
        try
            hMgr = uigetmodemanager(fig);
            cm = ''; try, cm = hMgr.CurrentMode; catch, end
            modeActive = ~isempty(cm);
            % Nonaktifkan window key-listener mode-manager (membajak keypress kustom).
            try, [hMgr.WindowListenerHandles.Enabled] = deal(false);
            catch, try, set(hMgr.WindowListenerHandles,'Enable','off'); catch, end
            end
        catch
        end
        % Bila mode zoom/pan MASIH aktif, matikan interaksinya (view dipertahankan
        % oleh kunci pandang di render berikutnya) supaya set handler diizinkan.
        if modeActive
            try, zoom(fig,'off'); catch, end
            try, pan(fig,'off');  catch, end
        end
        % Pasang ulang handler figure. WindowKeyPressFcn = callback tingkat JENDELA
        % -> menangkap keypress (Ctrl+..) walau uicontrol/tombol memegang fokus.
        try, set(fig, 'WindowKeyPressFcn', @(s,e) i_onKeyPress(s, e)); catch, end
        try, set(fig, 'CurrentObject', fig); catch, end
    catch
    end
end

function i_onAxMainViewLock(fig)
%I_ONAXMAINVIEWLOCK  Toggle KUNCI PANDANG axMain. ON: bekukan XLim/YLim axMain
%   SEKARANG -> dipertahankan tiap ganti frame (via i_applyAxMainViewLock). OFF:
%   lepas kunci (view kembali mengikuti ekstent penuh saat render berikutnya).
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum ada.'); return;
    end
    want = ~h.axMainViewLock;
    if want
        xl = get(h.axMain,'XLim'); yl = get(h.axMain,'YLim');
        h.axMainViewLock = true; h.axMainViewLim = [xl(1) xl(2) yl(1) yl(2)];
        guidata(fig, h);
        set(h.btnAxViewLock,'Value',1);
        i_setAxMainLockListener(fig, true);   % anti-flicker ISI: PostSet timpa reset-ke-penuh
        pivui.setStatus(fig, sprintf('Pandang axMain DIKUNCI: X[%.0f %.0f] Y[%.0f %.0f] tetap saat ganti frame (1:1).', xl, yl));
    else
        h.axMainViewLock = false; h.axMainViewLim = []; guidata(fig, h);
        set(h.btnAxViewLock,'Value',0);
        i_setAxMainLockListener(fig, false);  % lepas listener saat kunci dibuka
        try, pivui.grain4Shell.renderMain(fig); catch, end   % kembali ke ekstent penuh
        pivui.setStatus(fig,'Kunci pandang axMain DILEPAS (kembali ke ekstent penuh).');
    end
end

function i_drawFaultPsgMarker(fig)
%I_DRAWFAULTPSGMARKER  Di axMain (garis PSG): tandai posisi sampling kurva HW
%   (MERAH) & FW (BIRU) sesar AKTIF, supaya kelihatan di garis PSG di mana HW/FW
%   sesar itu berada. HANYA saat tab ① Sesar aktif. SF: HW hijau, FW=FW induk.
    h = guidata(fig);
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain), return; end
    ax = h.axMain;
    try, delete(findall(ax,'Tag','faultPsgMarker')); catch, end
    if isfield(h,'mainView') && strcmp(h.mainView,'ac'), return; end
    if ~i_faultVisible(h) || isempty(h.recs), return; end
    [f, idx] = pivui.grain5Model.activeFault(h);
    if idx < 1, return; end
    isSub = ~isempty(pivui.grain5Model.parentId(f));
    hwRow = pivui.grain5Model.rowForPos(h, f.hwPosPx);
    fm = pivui.grain5Model.mainFaultOf(h, f); fwRow = pivui.grain5Model.rowForPos(h, fm.fwPosPx);
    hwCol = [0.85 0.10 0.10]; if isSub, hwCol = [0.10 0.60 0.15]; end
    hs = ishold(ax); hold(ax,'on');
    % Label pakai NOMOR TAMPIL (uiNum) 'F<n>', BUKAN f.id unik-internal (F11-F20
    % utk PSG-2). SF pakai subTag. Konsisten dgn i_drawFaultBand.
    hwTag = ['F' i_uiNumStr(f)]; if isSub, hwTag = pivui.grain5Fmt.subTag(f.id); end
    fwTag = ['F' i_uiNumStr(fm)];
    i_psgDot(ax, h, hwRow, hwCol, sprintf('HW·%s', hwTag));
    if ~isSub, i_psgDot(ax, h, fwRow, [0.10 0.30 0.85], sprintf('FW·%s', fwTag)); end
    if ~hs, hold(ax,'off'); end
end

% =====================================================================
% BUFFER area sampling POT — kontrol UI + preview overlay.
% =====================================================================
function bm = i_bufferMult(h)
%I_BUFFERMULT  Ambil kelipatan buffer aktif (0 = mati).
    bm = 0;
    if isstruct(h) && isfield(h,'bufferMult') && isscalar(h.bufferMult) ...
            && isfinite(h.bufferMult) && h.bufferMult > 0
        bm = round(h.bufferMult);
    end
end

function sp = i_sampleSpacing(h)
%I_SAMPLESPACING  Spacing sampling efektif (px): h.spacing bila di-set, else
%   round(nodeSpacing) grid PIV (cocok dgn resolusi shell collectPOT).
    sp = NaN;
    if isfield(h,'spacing'), sp = pivcore.util.scalarOr(h.spacing, NaN); end
    if ~(isfinite(sp) && sp > 0)
        dd = NaN;
        if isfield(h,'data') && ~isempty(h.data)
            try, dd = pivcore.data.nodeSpacing(h.data); catch, dd = NaN; end
        end
        if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end
    end
end

function h = i_buildBufferCtrl(h)
%I_BUILDBUFFERCTRL  Popup "Buffer" di strip tengah (sebelah "Spacing px").
%   Ditempel ke figure; shell GRAIN4 tak diubah. Karena ruang antara edSpacing
%   (x≈0.458) & label Skala-V (x≈0.470) sempit, geser sedikit slider Skala-V &
%   labelnya ke kanan utk memberi slot popup (reposisi LOKAL GRAIN5_temp).
    fig = h.fig;
    WHITE = [1 1 1];
    % Reposisi LOKAL strip tengah agar muat slot "Buffer" TANPA saling tumpuk:
    % [Buffer lbl][popup][Skala-V lbl][slider][🔒 lock]. Semua digeser+dirampingkan
    % di sini (shell GRAIN4 tak diubah). Sebelumnya slider digeser masuk ke bawah
    % tombol kunci -> tombol menutupi slider; kini tiap kontrol punya slot sendiri.
    try
        lblV = findobj(fig,'Style','text','String','Skala-V:');
        if ~isempty(lblV), set(lblV,'Position',[0.542 0.430 0.044 0.034]); end
    catch, end
    try
        if isfield(h,'sldVScale') && ishghandle(h.sldVScale)
            set(h.sldVScale,'Position',[0.588 0.434 0.042 0.032]);
        end
    catch, end
    % Rampingkan tombol kunci & geser ke ujung kanan strip (jangan tutupi slider).
    try
        if isfield(h,'btnLock') && ishghandle(h.btnLock)
            set(h.btnLock,'Position',[0.634 0.432 0.050 0.036],'FontSize',7);
        end
    catch, end
    % Slot popup: tepat setelah edSpacing (x≈0.458), y sejajar strip (0.432).
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.458 0.430 0.040 0.034],'String','Buffer:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    bmVal = i_bufferMult(h);                 % 0/1/2/3 -> Value 1/2/3/4
    h.popBuffer = uicontrol('Parent',fig,'Style','popupmenu','Units','normalized', ...
        'Position',[0.500 0.432 0.040 0.034], ...
        'String',{'off','1×','2×','3×'},'Value', min(4, max(1, bmVal+1)), ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString',['Lebar PITA sampling POT = kelipatan spacing (nodeSpacing grid PIV). ' ...
        'Band 2D di atas-bawah garis PSG -> nilai POT = rata-rata area (lebih akurat utk sesar miring).'], ...
        'Callback',@(s,e) i_onBuffer(fig));
    guidata(fig, h);
end

function i_onBuffer(fig)
%I_ONBUFFER  Ganti kelipatan buffer -> re-sampel POT + refresh preview.
    h = guidata(fig);
    v = 1; try, v = get(h.popBuffer,'Value'); catch, end
    h.bufferMult = max(0, round(v) - 1);     % Value 1/2/3/4 -> 0/1/2/3
    guidata(fig, h);
    % Re-sampel bila ada garis; render axMain agar preview & POT segar.
    if isfield(h,'line') && ~isempty(h.line)
        pivui.grain4Shell.collectPOT(fig);
    end
    pivui.grain4Shell.renderMain(fig);
    if h.bufferMult > 0
        pivui.setStatus(fig, sprintf('Buffer band ×%d (band %d baris) aktif.', ...
            h.bufferMult, 2*h.bufferMult+1));
    else
        pivui.setStatus(fig, 'Buffer band MATI (sampling 1D di garis PSG).');
    end
end

function i_drawBufferPreview(fig)
%I_DRAWBUFFERPREVIEW  Overlay di axMain: pita band transparan (ikut orientasi
%   garis) + SEMUA titik grid sampling (kecil), supaya kelihatan seberapa luas &
%   rapat area sampling. Geometri = pivcore.pot.step1Collect.bandGeom (SAMA dgn
%   engine -> preview = area yg benar-benar disampel). Kosong bila buffer mati.
    h = guidata(fig);
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain), return; end
    ax = h.axMain;
    try, delete(findall(ax,'Tag','bufferPreview')); catch, end
    if isfield(h,'mainView') && strcmp(h.mainView,'ac'), return; end
    k = i_bufferMult(h);
    if k <= 0, return; end
    % Garis PSG aktif (ROI atau h.line).
    L = [];
    try, L = pivui.grain4Shell.currentLine(h); catch, end
    if isempty(L) && isfield(h,'line'), L = h.line; end
    if isempty(L) || ~isfield(L,'p1') || ~isfield(L,'p2'), return; end
    sp = i_sampleSpacing(h);
    [bx, by, corners] = pivcore.pot.step1Collect.bandGeom(L.p1, L.p2, sp, k);
    if isempty(bx), return; end

    hs = ishold(ax); hold(ax,'on');
    % Pita transparan (poligon 4-sudut, ikut kemiringan garis).
    if ~isempty(corners)
        patch(ax, corners(:,1), corners(:,2), [0.15 0.55 0.95], ...
            'FaceAlpha',0.12, 'EdgeColor',[0.10 0.45 0.85], 'LineWidth',0.8, ...
            'LineStyle','--', 'Tag','bufferPreview', ...
            'HitTest','off','PickableParts','none');
    end
    % SEMUA titik sampling — kecil (sedikit lebih kecil dari indikator HW/FW).
    ms = max(2, i_markerSize(h) - 1);
    plot(ax, bx(:), by(:), 'o', 'MarkerSize',ms, 'LineWidth',0.5, ...
        'MarkerEdgeColor','none', 'MarkerFaceColor',[0.10 0.45 0.85], ...
        'Tag','bufferPreview','HitTest','off','PickableParts','none');
    if ~hs, hold(ax,'off'); end
end

function i_psgDot(ax, h, row, col, label)
%I_PSGDOT  Satu titik marker (origin record) di axMain + label kecil.
    if isempty(row) || row < 1 || row > numel(h.recs), return; end
    o = h.recs(row).origin;
    if numel(o)~=2 || ~all(isfinite(o)), return; end
    ms = i_markerSize(h);   % ukuran titik indikator (spinner di baris klik)
    plot(ax, o(1), o(2), 'o', 'MarkerSize',ms, 'LineWidth',1.2, ...
        'MarkerEdgeColor',[0 0 0], 'MarkerFaceColor',col, ...
        'Tag','faultPsgMarker','HitTest','off','PickableParts','none');
    tc = [1 1 1]; if mean(col) > 0.6, tc = [0 0 0]; end
    % Label DIANGKAT JAUH dari titik supaya tak menghalangi: taruh di ~80% tinggi
    % sumbu (dari bawah), skala ke rentang ylim aktif (adaptif tiap gambar). Garis
    % penunjuk tipis titik->label agar tetap jelas milik titik yang mana.
    yl = ylim(ax); yLab = yl(1) + 0.80 * (yl(2)-yl(1));
    plot(ax, [o(1) o(1)], [o(2) yLab], '-', 'Color',[col 0.6], 'LineWidth',0.8, ...
        'Tag','faultPsgMarker','HitTest','off','PickableParts','none');
    text(ax, o(1), yLab, label, 'Color',tc, 'BackgroundColor',col, ...
        'EdgeColor',[0 0 0], 'Margin',1, 'FontWeight','bold', 'FontSize',7, ...
        'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
        'Tag','faultPsgMarker','HitTest','off','PickableParts','none');
end

function i_decoratePOT(fig)
%I_DECORATEPOT  GRAIN5: dekorasi axPOT. Tab ① Sesar -> HW/FW + titik POI sesar
%   (i_decorateFaultPOT). Tab lain (Label) -> tak ada titik observasi (sistem
%   net-slip/komentar dibuang di Fase 1).
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax) || isempty(h.recs), return; end
    if i_faultVisible(h)               % Tab ① (F# Anlz) & ② (F# Dip) -> HW/FW + titik sesar
        i_decorateFaultPOT(fig); return;
    end
    try, delete(findall(ax,'Tag','nsPoint')); catch, end
end

function i_plotPt(ax, yvec, f, which)
    if ~(isscalar(f) && isfinite(f) && f>=1 && f<=numel(yvec)), return; end
    yv = yvec(round(f)); if ~isfinite(yv), return; end
    col = pivcore.pot.snapPoints.color(which);
    sc = 1.0;   % skala ukuran titik POI (tombol ▲/▼ di tab ①), dibaca dari state
    try
        fg = ancestor(ax,'figure'); hh = guidata(fg);
        if isstruct(hh) && isfield(hh,'poiMarkerScale') && isscalar(hh.poiMarkerScale) && hh.poiMarkerScale>0
            sc = hh.poiMarkerScale;
        end
    catch
    end
    ms = max(2, 9*sc);
    plot(ax, f, yv, 'o', 'MarkerSize',ms, 'LineWidth',1.4, ...
        'MarkerEdgeColor',col, 'MarkerFaceColor','w', ...
        'Tag','nsPoint','HitTest','off','PickableParts','none');
end


% =====================================================================
% Garis PSG (tab Label)
% =====================================================================
function i_onActivateLine(fig)
    h = guidata(fig);
    id = i_selectedLineId(h);
    if isempty(id), pivui.setStatus(fig,'Pilih garis dari daftar dulu.'); return; end
    i_clearGhostLine(fig);            % renderMain juga akan menghapus, ini jaga-jaga
    i_activateLineById(fig, id);
end

function i_onPickLine(fig)
%I_ONPICKLINE  Baris garis PSG dipilih -> tampilkan GARIS BAYANGAN di axMain
%   pada posisi datanya. HANYA utk garis yang TIDAK aktif (yang aktif sudah
%   ditandai » + ROI oranye). Hilang saat fokus pindah/garis digeser.
    i_drawGhostLine(fig);
end

function i_drawGhostLine(fig)
    h = guidata(fig);
    i_clearGhostLine(fig);
    if ~ishghandle(h.axMain), return; end
    id = i_selectedLineId(h);
    if isempty(id) || strcmp(id, h.activePsgId), return; end   % aktif -> tak perlu bayangan
    [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, id);
    if idx < 1 || ~all(isfinite([ln.p1(:); ln.p2(:)])'), return; end
    ax = h.axMain; hs = ishold(ax); hold(ax,'on');
    xx = [ln.p1(1) ln.p2(1)]; yy = [ln.p1(2) ln.p2(2)];
    plot(ax, xx, yy, '--', 'Color',[0.95 0.45 0.05], 'LineWidth',2.0, ...
        'Tag','psgGhost','HitTest','off','PickableParts','none');
    plot(ax, xx, yy, 'o', 'MarkerSize',6, 'MarkerEdgeColor',[0.95 0.45 0.05], ...
        'MarkerFaceColor','w', 'Tag','psgGhost','HitTest','off','PickableParts','none');
    if ~hs, hold(ax,'off'); end
    pivui.setStatus(fig, sprintf('Bayangan garis "%s". Klik "Aktifkan" untuk pindah ke sana.', id));
end

function i_clearGhostLine(fig)
    h = guidata(fig);
    if isfield(h,'axMain') && ishghandle(h.axMain)
        try, delete(findall(h.axMain,'Tag','psgGhost')); catch, end
    end
end

function i_activateLineById(fig, id)
    h = guidata(fig);
    [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, id);
    if idx < 1, return; end
    % SCOPING multi-PSG: simpan slot tabel F garis LAMA sebelum berganti, lalu muat
    % slot garis BARU (id). Tiap garis PSG punya tabel sesar F# SENDIRI.
    h = i_stashActivePsgSlots(h);          % simpan h.faultSlots -> map by activePsgId lama
    frac = NaN; if isfield(ln,'frac'), frac = ln.frac; end
    h.line = struct('p1',ln.p1(:).', 'p2',ln.p2(:).', 'frac',frac);
    h.activePsgId = id; h.psgLocked = true;
    h.faultSlots = i_loadPsgSlots(h, id);  % slot tabel F garis BARU (kosong -> seed nanti)
    % PENTING: buang ROI lama dulu — kalau tidak, renderMain membaca posisi ROI
    % LAMA (currentLine) dan menimpa h.line yang baru -> garis tak pindah.
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi = [];
    if isfield(h,'btnLock') && ishghandle(h.btnLock), set(h.btnLock,'Value',1,'String','🔒 Terkunci'); end
    guidata(fig, h);
    % Garis BARU belum punya sesar sama sekali -> auto-fill F1..F15 (ber-psgId=id).
    i_seedFaultsForPsg(fig, id);
    h = guidata(fig);
    pivui.grain4Shell.renderMain(fig);
    pivui.grain4Shell.collectPOT(fig);        % sampel di garis tersimpan
    h = guidata(fig);
    % Gap fix (multi-psg-per-side-scoping): restore label/trim/excluded WALAU tanpa
    % label HW (konsisten dgn i_onPotChanged) — supaya clean-plot/hapus-kurva per
    % garis PSG ikut ter-restore saat Aktifkan.
    if i_lineHasLabels(ln) || i_lineHasCuts(ln)
        h.recs = i_applyDocLabels(h.recs, ln);
        h.recs = pivcore.pot.records.applyColors(h.recs);
        h.pts  = i_ptsFromNetslip(ln);
        guidata(fig, h);
    end
    % Seleksi sesar pertama garis ini (atau '' bila tak ada).
    h = guidata(fig); act = i_activeFaults(h);
    h.activeFaultId = ''; if ~isempty(act), h.activeFaultId = act{1}.id; end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    i_refreshContext(fig); i_refreshLines(fig); i_refreshAssignTable(fig);
    i_refreshPoi(fig);
    i_refreshFaultTab(fig);                 % tabel sesar GANTI ke garis PSG aktif
    nF = numel(i_activeFaults(guidata(fig)));
    pivui.setStatus(fig, sprintf('Garis "%s" diaktifkan (tersampel + seed; %d sesar).', id, nF));
end

% --- Slot tabel F per-garis PSG (UI-state; disimpan di h.faultSlotsByPsg) -------
function key = i_psgKey(id)
%I_PSGKEY  Sanitasi id garis PSG -> nama field struct MATLAB yang valid.
    key = char(id);
    if isempty(key), key = 'psg_none'; end
    key = regexprep(key, '[^A-Za-z0-9]', '_');
    if isempty(regexp(key, '^[A-Za-z]', 'once')), key = ['p_' key]; end
end

function h = i_stashActivePsgSlots(h)
%I_STASHACTIVEPSGSLOTS  Simpan h.faultSlots (tabel F garis aktif skrg) ke map
%   h.faultSlotsByPsg keyed by activePsgId. No-op bila belum ada garis aktif.
    if ~isfield(h,'faultSlotsByPsg') || ~isstruct(h.faultSlotsByPsg), h.faultSlotsByPsg = struct(); end
    pid = ''; if isfield(h,'activePsgId'), pid = char(h.activePsgId); end
    if isempty(pid) || ~isfield(h,'faultSlots'), return; end
    h.faultSlotsByPsg.(i_psgKey(pid)) = h.faultSlots(:).';
end

function slots = i_loadPsgSlots(h, id)
%I_LOADPSGSLOTS  Ambil slot tabel F tersimpan utk garis `id` dari map; '' -> {}
%   (i_ensureSlots akan seed dari fault garis itu). Reset supaya i_ensureSlots
%   tak memakai slot garis LAMA.
    slots = {};
    if isfield(h,'faultSlotsByPsg') && isstruct(h.faultSlotsByPsg)
        k = i_psgKey(id);
        if isfield(h.faultSlotsByPsg, k), slots = h.faultSlotsByPsg.(k); end
    end
end

function i_seedFaultsForPsg(fig, id)
%I_SEEDFAULTSFORPSG  Bila garis PSG `id` belum punya sesar SAMA SEKALI, isi 15
%   slot F1..F15 (uiNum 1..15, kosong) ber-psgId=id. Konsisten auto-fill exp.
    h = guidata(fig);
    if isempty(char(id)), return; end
    if ~isempty(pivui.grain5Model.faultsForPsg(h.fdoc, char(id))), return; end   % sudah ada
    if ~isstruct(h.fdoc), h.fdoc = pivcore.io.grain5Faults.emptyDoc(h.df); end
    for nnum = 1:15
        uid = sprintf('F%d', pivui.grain5Model.nextUniqueIdNum(h.fdoc));   % id INTERNAL unik lintas-PSG
        fnew = pivcore.io.grain5Faults.faultStruct(uid, NaN, NaN, NaN, NaN, NaN, NaN);
        fnew.uiNum = nnum; fnew.psgId = char(id);
        h.fdoc = pivcore.io.grain5Faults.upsertFault(h.fdoc, fnew);
    end
    h.faultSlots = {};   % biar i_ensureSlots seed dari record baru (urut)
    guidata(fig, h);
end

% ======================================================================
% L-GRID PSG: garis acuan L1 + N garis di bawahnya -> export AXPOT (satuan nyata).
% Bukti sampling PSG dekat permukaan = info paling kaya. L2..Ln TEMPORER: buffer
% DIPAKSA OFF (sampling 1-D), garis asli DIRESTORE, tak masuk h.doc.psgLines.
% ======================================================================

function i_onSetRefLine(fig)
%I_ONSETREFLINE  Tandai garis PSG yang SEDANG AKTIF sebagai L1 (acuan).
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    L1 = i_lgridRefLine(h);
    if isempty(L1), pivui.setStatus(fig,'Belum ada garis PSG aktif. Aktifkan/gambar garis dulu.'); return; end
    id = h.activePsgId; if isempty(id), id = '(garis aktif)'; end
    h.refPsgId = h.activePsgId;   % boleh '' bila garis belum tersimpan -> tetap pakai h.line
    guidata(fig, h);
    i_refreshLgridUI(fig);
    pivui.setStatus(fig, sprintf('L1 (acuan) = garis "%s".', id));
end

function i_onLgridN(fig, d)
    h = guidata(fig);
    h.lgridN = max(1, min(20, round(h.lgridN) + d));
    guidata(fig, h); i_refreshLgridUI(fig);
    if h.lgridPreviewOn, i_drawLgridPreview(fig); end   % preview live saat terkunci
    pivui.setStatus(fig, sprintf('L-grid: %d garis.', h.lgridN));
end

function i_onLgridDy(fig, d)
    h = guidata(fig);
    h.lgridDy = max(10, round(h.lgridDy) + d*10);   % increment 10 px
    guidata(fig, h); i_refreshLgridUI(fig);
    if h.lgridPreviewOn, i_drawLgridPreview(fig); end
    pivui.setStatus(fig, sprintf('L-grid: spasi %d px.', h.lgridDy));
end

function i_refreshLgridUI(fig)
    h = guidata(fig);
    if isfield(h,'txtLgridN') && ishghandle(h.txtLgridN), set(h.txtLgridN,'String',sprintf('%d',h.lgridN)); end
    if isfield(h,'txtLgridDy') && ishghandle(h.txtLgridDy), set(h.txtLgridDy,'String',sprintf('%d',h.lgridDy)); end
    if isfield(h,'txtRefLine') && ishghandle(h.txtRefLine)
        if isempty(i_lgridRefLine(h))
            set(h.txtRefLine,'String','L1: — (belum di-set)');
        else
            id = h.refPsgId; if isempty(id), id = 'garis aktif'; end
            set(h.txtRefLine,'String',sprintf('L1: %s', id));
        end
    end
end

function L1 = i_lgridRefLine(h)
%I_LGRIDREFLINE  Geometri garis acuan L1 = struct('p1','p2'). Ambil dari doc bila
%   refPsgId ada; else dari garis aktif runtime (h.line). [] bila tak ada.
    L1 = [];
    if isstruct(h) && isfield(h,'refPsgId') && ~isempty(h.refPsgId) ...
            && isstruct(h.doc) && isfield(h.doc,'psgLines')
        [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, h.refPsgId);
        if idx >= 1 && all(isfinite([ln.p1(:); ln.p2(:)])')
            L1 = struct('p1', ln.p1(:).', 'p2', ln.p2(:).'); return;
        end
    end
    if isfield(h,'line') && ~isempty(h.line) && isfield(h.line,'p1') && isfield(h.line,'p2') ...
            && all(isfinite([h.line.p1(:); h.line.p2(:)])')
        L1 = struct('p1', h.line.p1(:).', 'p2', h.line.p2(:).');
    end
end

function lines = i_lgridGeom(h)
%I_LGRIDGEOM  Daftar geometri L1..Ln (cell, tiap sel = struct p1/p2). L1 = acuan
%   (paling ATAS); L(i>1) = L1 di-offset TEGAK-LURUS (arah normal garis) sejauh
%   (i-1)*lgridDy px KE BAWAH LAYAR. Arah "bawah layar" bergantung YDir axMain
%   (normal -> Y kecil; reverse/citra -> Y besar) supaya Ln selalu tampak di bawah L1.
    lines = {};
    L1 = i_lgridRefLine(h);
    if isempty(L1), return; end
    p1 = L1.p1(:).'; p2 = L1.p2(:).';
    % downY = tanda komponen-Y "ke bawah layar". axMain default YDir 'normal' ->
    % bawah = Y BERKURANG (downY=-1); 'reverse' (citra) -> bawah = Y BERTAMBAH (+1).
    downY = -1;
    if isfield(h,'axMain') && ishghandle(h.axMain) && strcmpi(get(h.axMain,'YDir'),'reverse')
        downY = +1;
    end
    d  = p2 - p1; Ln = hypot(d(1), d(2));
    if Ln > eps
        % Normal unit = putar arah garis 90°; arahkan agar bergerak KE BAWAH layar.
        nrm = [-d(2), d(1)] / Ln;
        if nrm(2) ~= 0 && sign(nrm(2)) ~= sign(downY), nrm = -nrm; end
        if nrm(2) == 0, nrm = [0, downY]; end   % garis vertikal -> pakai downY murni
    else
        nrm = [0, downY];
    end
    N  = max(1, round(h.lgridN));
    dy = max(1, round(h.lgridDy));
    for i = 1:N
        off = (i-1) * dy * nrm;
        lines{end+1} = struct('p1', p1 + off, 'p2', p2 + off); %#ok<AGROW>
    end
end

% ======================================================================
% (DIBUANG: GENERATE N garis PSG PERMANEN — i_onGenSetRef/i_onGenN/i_onGenDy/
%  i_refreshGenUI/i_genRefLine/i_genGeom/i_onGenPsgLines. GRAIN4 = PEMBACA garis;
%  membuat garis PSG baru dilarang. Garis multi-PSG dibuat di GRAIN3a/GRAIN5.)
% ======================================================================
function i_onLgridPreview(fig)
%I_ONLGRIDPREVIEW  Toggle: ON = kunci + gambar L1..Ln (aktifkan POT Export);
%   OFF = buang overlay + nonaktifkan POT Export.
    h = guidata(fig);
    on = false;
    if isfield(h,'btnLgridPreview') && ishghandle(h.btnLgridPreview)
        on = get(h.btnLgridPreview,'Value') == 1;
    else
        on = ~h.lgridPreviewOn;   % headless fallback
    end
    if on
        lines = i_lgridGeom(h);
        if isempty(lines)
            pivui.setStatus(fig,'Belum ada L1. Klik "Jadikan L1" pada garis PSG aktif dulu.');
            if isfield(h,'btnLgridPreview') && ishghandle(h.btnLgridPreview), set(h.btnLgridPreview,'Value',0); end
            return;
        end
        h.lgridLines = lines; h.lgridPreviewOn = true; guidata(fig, h);
        i_drawLgridPreview(fig);
        if isfield(h,'btnLgridPreview') && ishghandle(h.btnLgridPreview)
            set(h.btnLgridPreview,'String','👁 Preview (terkunci)');
        end
        if isfield(h,'btnLgridExport') && ishghandle(h.btnLgridExport), set(h.btnLgridExport,'Enable','on'); end
        pivui.setStatus(fig, sprintf('Preview %d garis L-grid (terkunci). Klik "POT Export".', numel(lines)));
    else
        h.lgridPreviewOn = false; guidata(fig, h);
        i_clearLgridPreview(fig);
        if isfield(h,'btnLgridPreview') && ishghandle(h.btnLgridPreview)
            set(h.btnLgridPreview,'String','👁 Preview garis PSG');
        end
        if isfield(h,'btnLgridExport') && ishghandle(h.btnLgridExport), set(h.btnLgridExport,'Enable','off'); end
        pivui.setStatus(fig,'Preview L-grid dibuka (POT Export nonaktif).');
    end
end

function i_clearLgridPreview(fig)
    h = guidata(fig);
    if isfield(h,'axMain') && ishghandle(h.axMain)
        try, delete(findall(h.axMain,'Tag','lgridPreview')); catch, end
    end
end

function i_drawLgridPreview(fig)
%I_DRAWLGRIDPREVIEW  Overlay axMain: garis L1..Ln (kuning/oranye) + label L1..Ln.
    h = guidata(fig);
    i_clearLgridPreview(fig);
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain), return; end
    lines = h.lgridLines; if isempty(lines), lines = i_lgridGeom(h); end
    if isempty(lines), return; end
    ax = h.axMain; hs = ishold(ax); hold(ax,'on');
    N = numel(lines);
    for i = 1:N
        p1 = lines{i}.p1; p2 = lines{i}.p2;
        % L1 lebih tebal/oranye; L2..Ln kuning lebih tipis.
        if i == 1, col = [0.95 0.45 0.05]; lw = 2.2; else, col = [0.95 0.80 0.10]; lw = 1.4; end
        plot(ax, [p1(1) p2(1)], [p1(2) p2(2)], '-', 'Color',col, 'LineWidth',lw, ...
            'Tag','lgridPreview','HitTest','off','PickableParts','none');
        text(ax, p1(1), p1(2), sprintf(' L%d', i), 'Color',col, 'FontWeight','bold', ...
            'FontSize',9, 'VerticalAlignment','middle', 'HorizontalAlignment','left', ...
            'Tag','lgridPreview','HitTest','off','PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end

function i_onLgridExport(fig)
%I_ONLGRIDEXPORT  Export axPOT tiap garis L1..Ln (satuan nyata: X=strain%, Y=cm/s)
%   + 1 AX main gabungan -> PAB5_export/<exp>/PSG_LGRID/. Buffer DIPAKSA OFF
%   (sampling 1-D). Setting L1 (kurva dihapus + clean-plot acuan kurva terjauh)
%   direplikasi ke L2..Ln. Garis asli user DIRESTORE sesudahnya.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    if ~h.lgridPreviewOn, pivui.setStatus(fig,'Klik "Preview" (kunci) dulu sebelum export.'); return; end
    lines = h.lgridLines; if isempty(lines), lines = i_lgridGeom(h); end
    if isempty(lines), pivui.setStatus(fig,'L-grid kosong (set L1 dulu).'); return; end

    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ~isempty(h.exportRootOverride) && isfolder(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
    end
    dpi = 150;
    if isfield(h,'edExpDpi') && ishghandle(h.edExpDpi)
        v = str2double(get(h.edExpDpi,'String')); if isfinite(v) && v>=50 && v<=600, dpi = round(v); end
    end
    velMult = 0.005;
    if isfield(h,'edExpMult') && ishghandle(h.edExpMult)
        v = str2double(get(h.edExpMult,'String')); if isfinite(v) && v>0, velMult = v; end
    end
    opts = struct('dpi',dpi,'velMult',velMult,'grainRoot',grainRoot);
    strainTot = i_strainTotalSafe(h);

    % --- Simpan state utk RESTORE ---
    prevLine       = h.line;
    prevActivePsgId= h.activePsgId;
    prevBuffer     = h.bufferMult;
    prevRecs       = h.recs;
    prevFrame      = h.frame;
    prevRoi        = []; if isfield(h,'roi'), prevRoi = h.roi; end
    % Simpan state DEKORASI axPOT (dipulihkan sesudah export).
    prevActiveFault= h.activeFaultId;
    prevHideFaults = h.hideAllFaults;
    prevShowAll    = h.showAllFaults;
    prevShowSlip   = h.showAllSlip;
    prevSelRows    = []; if isfield(h,'selRows'), prevSelRows = h.selRows; end
    prevPotView    = ''; if isfield(h,'potView'), prevPotView = h.potView; end

    % --- KURVA MENTAH BERSIH: buang SEMUA dekorasi sesar + seleksi sebelum export.
    %     (permintaan user: hijau seleksi & fill zona/HW/FW/POI TAK boleh terbawa —
    %     hanya kurva mentah polos.) hideAllFaults=true -> i_decorateFaultPOT return
    %     lebih awal (tak gambar zona/HW/FW/POI); selRows=[] -> tak ada sorot hijau.
    h = guidata(fig);
    h.activeFaultId = ''; h.hideAllFaults = true;
    h.showAllFaults = false; h.showAllSlip = false;
    h.selRows = []; h.potView = 'curve';
    guidata(fig, h);

    % --- Tangkap setting L1 (kurva dihapus + kurva terjauh dipakai utk clean plot) ---
    % L1 = garis pertama; pastikan recs L1 tersampel dulu.
    i_lgridSampleLine(fig, lines{1});
    h = guidata(fig);
    [exclIdx, lastUsedIdx] = i_lgridCaptureL1(h);

    outDir = pivcore.io.grain5PsgExport.lgridDir(grainRoot, h.df);
    pivcore.io.grain5PsgExport.purge(grainRoot, h.df);
    if ~isfolder(outDir), mkdir(outDir); end

    quiet = pivui.quiet();
    wb = []; if ~quiet
        try, wb = waitbar(0,'L-grid PSG export…','Name','L-grid PSG export'); pivui.forceLightTheme(wb); catch, wb = []; end
    end
    cleanWb = onCleanup(@() i_closeIf(wb)); %#ok<NASGU>

    nOk = 0;
    % --- 1) AX main gabungan (garis L1..Ln berlabel) ---
    fnMain = pivcore.io.grain5PsgExport.axMainFile(h.df);
    if i_shotLgridAxMain(fig, lines, fullfile(outDir, fnMain), opts, strainTot, velMult)
        nOk = nOk + 1;
    end
    % --- 2) axPOT tiap L ---
    for i = 1:numel(lines)
        if ~isempty(wb) && ishghandle(wb)
            try, waitbar(i/numel(lines), wb, sprintf('Export L%d/%d…', i, numel(lines))); catch, end
        end
        i_lgridSampleLine(fig, lines{i});
        i_lgridApplyL1(fig, exclIdx, lastUsedIdx);   % replikasi hapus + clean plot L1
        fnPot = pivcore.io.grain5PsgExport.axpotFile(h.df, i);
        if i_shotAxPotCalib(fig, [], fullfile(outDir, fnPot), opts, strainTot, velMult, [], sprintf('PSG L%d', i))
            nOk = nOk + 1;
        end
    end

    % --- RESTORE garis asli + buffer + recs ---
    % Re-sampel garis SEMULA (buffer OFF sudah, tapi restore buffer asli sesudah),
    % lalu PAKSA h.line = garis semula (currentLine/ensureROI bisa menulis ulang
    % h.line dari posisi ROI yang tersnap beda -> garis "melompat" ke Ln terakhir).
    i_lgridSampleLine(fig, struct('p1',prevLine.p1,'p2',prevLine.p2));
    h = guidata(fig);
    h.line = prevLine; h.recs = prevRecs;
    h.activePsgId = prevActivePsgId; h.bufferMult = prevBuffer;
    guidata(fig, h);
    % Buang ROI (posisinya masih di Ln) + gambar ulang ROI dari h.line yg benar.
    h = guidata(fig);
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi = []; guidata(fig, h);
    try, pivui.grain4Shell.ensureROI(fig); catch, end
    h = guidata(fig); h.line = prevLine;   % final: kunci ke garis semula
    % Pulihkan state DEKORASI axPOT (sesar aktif, hide/showAll, seleksi) seperti semula.
    h.activeFaultId = prevActiveFault; h.hideAllFaults = prevHideFaults;
    h.showAllFaults = prevShowAll; h.showAllSlip = prevShowSlip;
    h.selRows = prevSelRows;
    if ~isempty(prevPotView), h.potView = prevPotView; end
    guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    pivui.grain4Shell.gotoFrame(fig, prevFrame);
    % Reset preview + tombol.
    i_clearLgridPreview(fig);
    h = guidata(fig); h.lgridPreviewOn = false; guidata(fig, h);
    if isfield(h,'btnLgridPreview') && ishghandle(h.btnLgridPreview)
        set(h.btnLgridPreview,'Value',0,'String','👁 Preview garis PSG');
    end
    if isfield(h,'btnLgridExport') && ishghandle(h.btnLgridExport), set(h.btnLgridExport,'Enable','off'); end
    pivui.setStatus(fig, sprintf('L-grid export: %d gambar -> %s', nOk, outDir));
end

function i_lgridSampleLine(fig, L)
%I_LGRIDSAMPLELINE  Set garis runtime ke L (p1/p2), PAKSA buffer OFF, buang ROI,
%   render + sampel POT (collectAlongLine 1-D). TIDAK menyentuh h.doc.
    h = guidata(fig);
    h.bufferMult = 0;                          % buffer DIPAKSA OFF (sampling 1-D)
    h.line = struct('p1', L.p1(:).', 'p2', L.p2(:).', 'frac', NaN);
    h.psgLocked = true;
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi = [];
    guidata(fig, h);
    pivui.grain4Shell.renderMain(fig);
    pivui.grain4Shell.collectPOT(fig);           % sampel garis L (buffer 0 -> 1-D)
    pivui.grain4Shell.renderPOT(fig);
end

function [exclIdx, lastUsedIdx] = i_lgridCaptureL1(h)
%I_LGRIDCAPTUREL1  Dari recs L1: exclIdx = indeks kurva dibuang (excluded);
%   lastUsedIdx = indeks kurva TERAKHIR yang TAK dibuang (kurva terjauh dipakai
%   L1 -> acuan clean plot utk L2..Ln). [] bila semua dibuang.
    exclIdx = []; lastUsedIdx = [];
    if ~isfield(h,'recs') || isempty(h.recs), return; end
    n = numel(h.recs);
    for r = 1:n
        if pivui.grain4Shell.isExcluded(h.recs(r)), exclIdx(end+1) = r; end %#ok<AGROW>
    end
    used = setdiff(1:n, exclIdx);
    if ~isempty(used), lastUsedIdx = max(used); end
end

function i_lgridApplyL1(fig, exclIdx, lastUsedIdx)
%I_LGRIDAPPLYL1  Terapkan setting L1 ke recs garis L aktif: (a) buang kurva bernomor
%   sama (exclIdx); (b) clean plot #1..#lastUsedIdx (kurva terjauh L1 = acuan trim).
    h = guidata(fig);
    if ~isfield(h,'recs') || isempty(h.recs), return; end
    n = numel(h.recs);
    % (a) buang kurva bernomor sama.
    for r = exclIdx(:).'
        if r >= 1 && r <= n, h.recs(r).excluded = true; end
    end
    guidata(fig, h);
    % (b) clean plot: seleksi kurva #1..#lastUsedIdx lalu trim ke indenter (acuan =
    %     nomor kurva terakhir yang dipakai L1). trimSelectedToIndenter baca h.selRows.
    if ~isempty(lastUsedIdx) && lastUsedIdx >= 1
        sel = 1:min(lastUsedIdx, n);
        h = guidata(fig); h.selRows = sel; guidata(fig, h);
        try, pivui.grain4Shell.trimSelectedToIndenter(fig); catch, end
    end
    % DESELECT sebelum render final: seleksi hijau (Tag 'selCurve') TAK boleh terbawa
    % ke gambar export (permintaan user: kurva mentah bersih). selRows=[] -> renderPOT
    % -> highlightSelPOT hapus 'selCurve' & return. trim tetap tersimpan di rec.cutFrame.
    h = guidata(fig); h.selRows = []; guidata(fig, h);
    pivui.grain4Shell.renderPOT(fig);
    try, delete(findall(h.axPOT,'Tag','selCurve')); catch, end        % sisa sorot seleksi
    try, delete(findall(h.axPOT,'Tag','sampleMarker')); catch, end    % titik sampling kurva
end

function ok = i_shotLgridAxMain(fig, lines, file, opts, strainTot, velMult) %#ok<INUSD>
%I_SHOTLGRIDAXMAIN  AX main (velmag) TERANG + colorbar cm/s + garis L1..Ln berlabel
%   oranye/kuning. Meniru i_shotAxMainCalib tapi TANPA HW/FW; gambar SEMUA garis L.
    ok = false;
    h = guidata(fig);
    if isempty(h.data), return; end
    scKey = 'velocity_magnitude';
    kk = max(1, min(round(pivcore.util.scalarOr(h.frame,1)), pivcore.util.scalarOr(h.imgFrames,1)));
    if kk > 1 && ~pivcore.util.isFullLoaded(h)
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    lc = pivui.grain4Shell.lockedClim(fig);
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 1120 560]);
    try, pivui.forceLightTheme(tmp); catch, end
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    try
        ax = axes('Parent',tmp);
        cfg = h; cfg.scalarSrc = scKey; cfg.climVel = lc.velmag;
        pivcore.montage.renderScalarPanel(ax, h.data, kk, scKey, cfg);
        set(ax, 'Color','w', 'XColor',[0 0 0], 'YColor',[0 0 0], 'XTick',[], 'YTick',[]);
        cb = colorbar(ax); cb.Label.String = '|V| (cm/s)';
        cl = clim(ax); t = get(cb,'Ticks');
        if isempty(t), t = linspace(cl(1), cl(2), 6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*velMult), t, 'UniformOutput', false));
        set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
        hold(ax,'on');
        for i = 1:numel(lines)
            p1 = lines{i}.p1; p2 = lines{i}.p2;
            if i == 1, col = [0.95 0.45 0.05]; lw = 1.6; else, col = [0.95 0.80 0.10]; lw = 1.0; end
            plot(ax, [p1(1) p2(1)], [p1(2) p2(2)], '-', 'Color',col, 'LineWidth',lw);
            text(ax, p1(1), p1(2), sprintf(' L%d', i), 'Color',col, 'FontWeight','bold', ...
                'FontSize',9, 'BackgroundColor','w', 'Margin',1, ...
                'VerticalAlignment','middle', 'HorizontalAlignment','left');
        end
        hold(ax,'off');
        title(ax, sprintf('%s — L-grid PSG (L1 acuan .. L%d)', i_baseNameSafe(h.df), numel(lines)), ...
            'Interpreter','none', 'Color',[0 0 0]);
        exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true;
    catch
        ok = false;
    end
end

% (DIBUANG: i_onSaveLine / i_onDeleteLine. GRAIN4 = PEMBACA garis PSG — tak menulis
%  geometri garis baru & tak menghapus garis. Kurva/net-slip garis aktif tetap
%  tersimpan lewat jalur Save utama via i_captureActiveLine, tanpa mengubah id/
%  koordinat. Buat/hapus garis PSG dilakukan di GRAIN3a.)


% =====================================================================
% Labeling HW + tebal garis (tab Label)
% =====================================================================
function i_onLineWidths(fig)
    h = guidata(fig);
    lwA = str2double(get(h.edLwA,'String')); lwR = str2double(get(h.edLwR,'String'));
    pivui.grain4Shell.setLineWidths(fig, lwA, lwR);   % LIVE
    h = guidata(fig);
    set(h.edLwA,'String',sprintf('%g',h.lwAssigned)); set(h.edLwR,'String',sprintf('%g',h.lwRaw));
end


% =====================================================================
% Strain helper (dipakai jalur render/konteks)
% =====================================================================
function pct = i_strainAt(h, k)
%I_STRAINAT  Strain kumulatif (%) pada frame k dari geometri eksperimen.
    pct = NaN;
    g = h.geom;
    if isstruct(g) && isfield(g,'strain_cumm_pct') && isscalar(g.strain_cumm_pct) ...
            && isfinite(g.strain_cumm_pct)
        nF = max(h.nF,1);
        if nF <= 1, pct = g.strain_cumm_pct; else, pct = (k-1)/(nF-1) * g.strain_cumm_pct; end
    end
end

% =====================================================================
% Persist (Save / Export)
% =====================================================================
function i_onSaveClose(fig)
    i_onSave(fig);
    if ishghandle(fig), delete(fig); end
end

function ok = i_confirmWriteDesc(fig, descDoc)
%I_CONFIRMWRITEDESC  GERBANG TUNGGAL semua penulisan _desc.json. TAK PERNAH menulis
%   tanpa konfirmasi user (insiden data-hilang 2026-07-18: auto-save diam menimpa
%   95 baris jadi 0). Bandingkan #baris BARU vs #baris di DISK:
%     - Menyusut (baru < disk)  -> peringatan KERAS merah + konfirmasi ekstra.
%     - Normal (baru >= disk)   -> konfirmasi biasa (Simpan/Batal).
%   Return TRUE hanya bila user setuju & tulis SUKSES.
    ok = false;
    h = guidata(fig);
    if isempty(h.df), return; end
    nNew = numel(pivcore.io.grain4Desc.tocell(descDoc.rows));
    nDisk = 0;
    try
        dDisk = pivcore.io.grain4Desc.read(h.df);
        nDisk = numel(pivcore.io.grain4Desc.tocell(dDisk.rows));
    catch
    end
    [~, base] = fileparts(h.df);
    % Mode SENYAP (tes headless): lolos tanpa dialog (tak ada user utk klik).
    if pivui.grain4Shell.silent()
        try, pivcore.io.grain4Desc.write(h.df, descDoc, true); ok = true; catch, end
        return;
    end
    if nNew < nDisk
        q = sprintf(['⚠ PERINGATAN — DATA AKAN MENYUSUT!\n\n' ...
            'File di disk: %d baris deskripsi\n' ...
            'Akan ditulis: %d baris  (BERKURANG %d)\n\n' ...
            'Eksperimen: %s\n\n' ...
            'Ini bisa berarti tabel sedang TERFILTER/kosong. Menyimpan sekarang ' ...
            'akan MENGHAPUS %d baris dari disk. Lanjutkan?'], ...
            nDisk, nNew, nDisk-nNew, base, nDisk-nNew);
        ans = questdlg(q, 'Konfirmasi SAVE (data menyusut)', ...
            'Batal (jangan tulis)', 'Ya, timpa dgn lebih sedikit', 'Batal (jangan tulis)');
        if ~strcmp(ans, 'Ya, timpa dgn lebih sedikit')
            pivui.setStatus(fig, sprintf('Save DIBATALKAN (disk %d baris dipertahankan).', nDisk));
            return;
        end
    else
        q = sprintf('Simpan %d baris deskripsi ke _desc.json?\n\nEksperimen: %s', nNew, base);
        ans = questdlg(q, 'Konfirmasi SAVE', 'Simpan', 'Batal', 'Simpan');
        if ~strcmp(ans, 'Simpan')
            pivui.setStatus(fig, 'Save dibatalkan.'); return;
        end
    end
    try
        pivcore.io.grain4Desc.write(h.df, descDoc, true);   % allowShrink: user SUDAH konfirmasi
        ok = true;
    catch ME
        pivui.setStatus(fig, sprintf('GAGAL menulis _desc.json: %s', ME.message));
    end
end

function i_onSave(fig)
%I_ONSAVE  GRAIN4: simpan HANYA tabel DESKRIPSI (_desc.json, BERKONFIRMASI).
%   TIDAK menulis _potdata.json (garis PSG/kurva = data mendasar GRAIN3a, read-only —
%   tulis-ulang berisiko menimpanya, insiden 2026-07-18), TIDAK _faults.json
%   (GRAIN5 = ground truth) / _comments.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    i_captureDescFromTable(fig); h = guidata(fig);
    % _desc.json (deskripsi) = SATU-SATUNYA file yang GRAIN4 tulis -> GERBANG KONFIRMASI.
    if ~i_confirmWriteDesc(fig, h.descDoc), return; end
    i_refreshLines(fig);
    nRow = numel(pivcore.io.grain4Desc.tocell(h.descDoc.rows));
    pivui.setStatus(fig, sprintf('💾 Tersimpan: %d baris deskripsi (_desc.json).', nRow));
end

% =====================================================================
% Capture truth + view settings
% =====================================================================
function doc = i_captureActiveLine(h)
%I_CAPTUREACTIVELINE  (GRAIN4 = PEMBACA garis.) Simpan HANYA kurva/net-slip (bagian
%   POI/deskripsi) ke garis PSG AKTIF. GEOMETRI garis (id/p1/p2/frac) DIKUNCI ke
%   nilai TERSIMPAN di _potdata.json (GRAIN3a) — TAK PERNAH di-derive ulang dari
%   koordinat ROI/runtime. Dulu fungsi ini `currentLine`->`h.line`->`psgId.fromLine`
%   sehingga geseran ROI beberapa px melahirkan id BARU -> garis tersimpan
%   TERTIMPA / baris DESC yatim (insiden P-CON-F1). Kini: cari garis tersimpan by
%   h.activePsgId; bila tak ada (tak wajar), garis tak disentuh.
    doc = h.doc; if ~isstruct(doc), doc = pivcore.io.grain4PotData.emptyDoc(h.df); end
    id = ''; if isfield(h,'activePsgId'), id = char(h.activePsgId); end
    if isempty(id), return; end
    [ln, idx] = pivcore.io.grain4PotData.findLine(doc, id);
    if idx < 1, return; end   % garis PSG hanya dibuat di GRAIN3a; GRAIN4 tak membuat garis
    % Geometri (p1/p2/frac/id/spacingPx) SENGAJA tak diubah — read-only. Hanya
    % kurva (label+cutFrame) & net-slip (POI) yang diperbarui oleh GRAIN4.
    ln.curves  = pivcore.io.grain4PotData.curvesFromRecs(h.recs, h.nF);
    ln.netslip = i_netslipEntries(h);
    doc = pivcore.io.grain4PotData.upsertLine(doc, ln);
end

function NS = i_netslipEntries(h)
    NS = {}; nF = h.nF; recsHW = i_recsHW(h);   % abaikan kurva dibuang
    nums = pivcore.pot.hwLabel.hwNumbers(recsHW);
    units = 'px/frame';
    if isstruct(h.doc) && isfield(h.doc,'units') && ~isempty(h.doc.units), units = h.doc.units; end
    for num = nums
        [A,B,partner,okB] = pivcore.pot.hwLabel.pair(recsHW, num, nF);
        row = pivcore.pot.snapPoints.getHW(h.pts, num);
        if isempty(row), row = struct('startF',NaN,'nclF',NaN,'fsrF',NaN,'endF',NaN); end
        ns = []; area = NaN; dNet = NaN;
        if okB
            ns = pivcore.pot.netslip.applySign(pivcore.pot.netslip.netslipVec(A,B), h.signConv);
            ns = pivui.grain4Shell.clipNeg(ns);   % net-slip negatif -> 0 (juga utk area/dNet)
            area = pivcore.pot.netslip.area(ns, row.startF, row.endF);
            dNet = pivcore.pot.netslip.dNet(ns, row.startF, row.endF);
        end
        NS{end+1} = struct('hw',num, 'partner',partner, ...
            'start',row.startF, 'nuc',row.nclF, 'fsr',row.fsrF, 'end',row.endF, ...
            'area',area, 'dNet',dNet, 'units',units, ...
            'convention',h.signConv, 'values',ns); %#ok<AGROW>
    end
end

function doc = i_syncDocMeta(h)
%I_SYNCDOCMETA  Selaraskan meta. TIDAK menyentuh viewSettings (itu ditulis hanya
%   di jalur SAVE via i_captureForSave) supaya setting tersimpan tak ketimpa
%   default saat exp dibuka.
    doc = h.doc; if ~isstruct(doc), doc = pivcore.io.grain4PotData.emptyDoc(h.df); end
    doc.meta.frames = max([h.nF, h.imgFrames, 1]);
    if ~isfield(doc,'units') || isempty(doc.units), doc.units = 'px/frame'; end
    doc.signConvention = h.signConv;
    [~, base, ext] = fileparts(h.df);
    doc.source = [base ext]; doc.meta.basename = base;
end

function doc = i_captureForSave(h)
%I_CAPTUREFORSAVE  doc lengkap utk persist: garis+kurva+netslip + meta + setting
%   tampilan terkini.
    doc = i_captureActiveLine(h);
    h.doc = doc; doc = i_syncDocMeta(h);
    doc.viewSettings = i_captureViewSettings(h);
end

function vs = i_captureViewSettings(h)
    vs = struct('scalarSrc',h.scalarSrc, 'climVel',h.climVel, 'shearAbs',h.shearAbs, ...
        'gsOn',h.gsOn, 'gsAlpha',h.gsAlpha, 'claheOn',h.claheOn, 'adjOn',h.adjOn, ...
        'glyphOn',h.glyphOn, 'glyphLW',h.glyphLW, 'glyphSp',h.glyphSp, ...
        'glyphColor',h.glyphColor, 'vScale',h.vScale, ...
        'lwAssigned',h.lwAssigned, 'lwRaw',h.lwRaw);
    % Zoom X-window axPOT/AXSLIP (persist -> sesi berikutnya lanjut di zoom sama).
    if isfield(h,'potXPct'),    vs.potXPct = h.potXPct; end
    if isfield(h,'potXCenter'), vs.potXCenter = h.potXCenter; end
end

function i_applyViewSettings(fig)
    h = guidata(fig);
    if ~isstruct(h.doc) || ~isfield(h.doc,'viewSettings') || ~isstruct(h.doc.viewSettings), return; end
    vs = h.doc.viewSettings; if isempty(fieldnames(vs)), return; end
    f = {'scalarSrc','climVel','shearAbs','gsOn','gsAlpha','claheOn','adjOn', ...
         'glyphOn','glyphLW','glyphSp','glyphColor','vScale','lwAssigned','lwRaw'};
    for i=1:numel(f)
        if isfield(vs, f{i}) && ~isempty(vs.(f{i})), h.(f{i}) = vs.(f{i}); end
    end
    % Restore zoom X-window (persist antar-sesi). potXWin diturunkan dari potXPct.
    if isfield(vs,'potXPct') && isscalar(vs.potXPct) && isfinite(vs.potXPct)
        pct = max(5, min(100, round(vs.potXPct/5)*5));
        h.potXPct = pct; nF = max(h.nF,2);
        if pct >= 100, h.potXWin = 0; else, h.potXWin = max(2, round(pct/100*nF)); end
    end
    if isfield(vs,'potXCenter') && isscalar(vs.potXCenter), h.potXCenter = vs.potXCenter; end
    guidata(fig, h);
    i_applyPotXLim(fig);   % terapkan zoom X tersimpan ke axPOT/AXSLIP
    % Selaraskan kontrol UI tampilan.
    pivui.grain4Shell.syncClimControls(h);
    if isfield(h,'edLwA') && ishghandle(h.edLwA), set(h.edLwA,'String',sprintf('%g',h.lwAssigned)); end
    if isfield(h,'edLwR') && ishghandle(h.edLwR), set(h.edLwR,'String',sprintf('%g',h.lwRaw)); end
    if isfield(h,'edAlpha') && ishghandle(h.edAlpha), set(h.edAlpha,'String',sprintf('%.2f',h.gsAlpha)); end
end


% =====================================================================
% Seed/aktivasi garis saat buka exp
% =====================================================================
function i_initLineAndSeed(fig)
%I_INITLINEANDSEED  (1) _potdata punya garis -> aktifkan (terkunci+sampel+seed).
%   (2) _autopot GRAIN3a -> seed read-only. (3) else garis 75% TAK-terkunci, BELUM
%   disampel (user kunci utk sampel).
    h = guidata(fig);
    if isstruct(h.doc) && isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines)
        id = h.doc.psgLines{1}.id;            % garis pertama tersimpan
        i_activateLineById(fig, id);
        h = guidata(fig); h.seedMsg = 'garis+label dari _potdata.json (GRAIN4)';
        guidata(fig, h); i_setSeedMsg(h); return;
    end
    ap = pivcore.io.step1Session.autopotPath(h.df);
    if isfile(ap)
        L = pivcore.io.step1Session.loadLine(h.df);
        if ~isempty(L) && isfield(L,'p1') && all(isfinite([L.p1 L.p2]))
            h.line = struct('p1',L.p1(:).','p2',L.p2(:).','frac',NaN);
            h.psgLocked = true;
            if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
            h.roi = [];   % buang ROI auto-75% supaya renderMain tak menimpa h.line
            if isfield(h,'btnLock')&&ishghandle(h.btnLock), set(h.btnLock,'Value',1,'String','🔒 Terkunci'); end
            guidata(fig, h);
            pivui.grain4Shell.renderMain(fig); pivui.grain4Shell.collectPOT(fig); h = guidata(fig);
        end
        saved = pivcore.io.step1Session.loadAssignments(h.df);
        h.recs = pivcore.pot.assign.applySaved(h.recs, saved);
        h.recs = pivcore.pot.records.applyColors(h.recs);
        s4 = pivcore.io.step1Session.loadStep4Points(h.df);
        if isstruct(s4) && isfield(s4,'pts') && ~isempty(s4.pts)
            h.pts = pivcore.pot.snapPoints.normalize(s4.pts);
        end
        h.activePsgId = pivcore.pot.psgId.fromLine(h.line);
        nlab = 0; for r=1:numel(h.recs), if ~isempty(pivcore.pot.records.label(h.recs(r))), nlab=nlab+1; end, end
        h.seedMsg = sprintf('seed dari _autopot GRAIN3a (%d label, %d titik-HW)', nlab, numel(h.pts));
        guidata(fig, h); i_setSeedMsg(h); return;
    end
    % TAK ADA garis tersimpan (_potdata.json / _autopot). GRAIN4 = PEMBACA garis —
    % TIDAK membuat garis 75% sendiri (dulu di sini; dibuang: garis PSG hanya
    % dibuat di GRAIN3a). Buang ROI auto-75% yg mungkin dibuat shell (autoPSG saat
    % loadExperiment) supaya tak ada garis draggable menggantung.
    h.line = []; h.activePsgId = '';
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), try, delete(h.roi); catch, end, end
    h.roi = [];
    try, delete(findall(h.axMain,'Tag','psgLine')); catch, end
    h.seedMsg = 'Garis PSG belum ada — buat garis di GRAIN3a dulu.';
    guidata(fig, h); i_setSeedMsg(h);
    pivui.setStatus(fig, 'Garis PSG belum ada untuk eksperimen ini — buat/assign di GRAIN3a dulu.');
end

function i_setSeedMsg(h)
%I_SETSEEDMSG  Tulis pesan seed ke label txtSeed BILA masih ada. Widget itu dulu
%   di tab Net-slip (dibuang Fase 1) -> guard supaya seed tetap tersimpan di
%   h.seedMsg tanpa error saat label absen.
    if isfield(h,'txtSeed') && ishghandle(h.txtSeed)
        set(h.txtSeed,'String',['seed: ' h.seedMsg]);
    end
end


% =====================================================================
% Anotasi (render dari _potdata)
% =====================================================================
function i_drawAnnotForActive(fig)
    h = guidata(fig);
    if ~ishghandle(h.axMain), return; end
    [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, h.activePsgId);
    if idx < 1, pivui.grain4Annot.clear(h.axMain); return; end
    A = [ln.annotations.lines, ln.annotations.points, ln.annotations.measures];
    pivui.grain4Annot.drawAll(h.axMain, A);
end


% =====================================================================
% Refresh
% =====================================================================
function i_refreshLines(fig)
    h = guidata(fig);
    L = {}; if isstruct(h.doc) && isfield(h.doc,'psgLines'), L = h.doc.psgLines; end
    ids = cell(1, numel(L));
    for k = 1:numel(L)
        ln = L{k}; nC = 0; nN = 0;
        if isfield(ln,'curves'),  nC = numel(ln.curves);  end
        if isfield(ln,'netslip'), nN = numel(ln.netslip); end
        mark = ''; if strcmp(ln.id, h.activePsgId), mark = '» '; end
        ids{k} = sprintf('%s%s  (kurva %d, netslip %d)', mark, ln.id, nC, nN);
    end
    if isempty(ids), ids = {'(belum ada garis tersimpan)'}; end
    val = get(h.lstLines,'Value'); if val > numel(ids) || val < 1, val = 1; end
    set(h.lstLines,'String',ids,'Value',val);
end

function i_refreshAssignTable(fig)
    h = guidata(fig);
    if ~isfield(h,'tblAssign') || ~ishghandle(h.tblAssign), return; end
    rr = i_labeledRows(h);
    C = cell(numel(rr),3);
    for i = 1:numel(rr)
        r = rr(i); lab = i_curveLabelAt(h, r);
        if pivui.grain4Shell.isExcluded(h.recs(r)), lab = [lab ' 🗑']; end   % dibuang dari net-slip
        C{i,1} = i; C{i,2} = lab;
        [~, yv] = pivcore.pot.records.curveXY(h.recs(r), h.nF);
        pf = ''; if ~isempty(yv), [~, pk] = max(yv); if isfinite(pk), pf = sprintf('%d', pk); end; end
        C{i,3} = pf;
    end
    set(h.tblAssign,'Data',C);
end

function i_refreshContext(fig)
    h = guidata(fig);
    if ~(isfield(h,'txtCtx') && ishghandle(h.txtCtx)), return; end   % tab Komentar dibuang
    p = i_strainAt(h, h.frame); ps = ''; if isfinite(p), ps = sprintf(' · strain %.1f%%', p); end
    set(h.txtCtx,'String', sprintf('Frame %d%s · kurva %s · garis %s', ...
        h.frame, ps, pivui.grain5Fmt.orDash(h.selCurveLabel), pivui.grain5Fmt.orDash(h.activePsgId)));
end

function i_refreshPoi(fig)
%I_REFRESHPOI  Tabel POI (objek + parameter terikat) + token referensinya.
    h = guidata(fig);
    if ~isfield(h,'tblPoi') || ~ishghandle(h.tblPoi), return; end
    [~, base] = fileparts(h.df);
    rows = {}; toks = {};
    % 1) garis PSG aktif
    if ~isempty(h.activePsgId)
        rows(end+1,:) = {sprintf('garis PSG: %s', h.activePsgId), '', ''}; %#ok<AGROW>
        toks{end+1} = sprintf('@psg:%s', h.activePsgId); %#ok<AGROW>
    end
    % 2) kurva berlabel
    rr = i_labeledRows(h);
    for i = 1:numel(rr)
        r = rr(i); lab = i_curveLabelAt(h, r);
        [~, yv] = pivcore.pot.records.curveXY(h.recs(r), h.nF);
        pf = NaN; if ~isempty(yv), [~,pf] = max(yv); end
        ps = i_strainAt(h, pf);
        rows(end+1,:) = {sprintf('kurva: %s', lab), pivui.grain5Fmt.numDash(pf), pivui.grain5Fmt.pctStr(ps)}; %#ok<AGROW>
        toks{end+1} = sprintf('@curve:%s', lab); %#ok<AGROW>
    end
    % 3) titik observasi per HW
    nums = pivcore.pot.hwLabel.hwNumbers(i_recsHW(h));
    KN = {'startF','Start'; 'nclF','NUC'; 'fsrF','FSR'; 'endF','END'};
    for num = nums
        row = pivcore.pot.snapPoints.getHW(h.pts, num);
        if isempty(row), continue; end
        for j = 1:size(KN,1)
            f = row.(KN{j,1});
            if isscalar(f) && isfinite(f)
                rows(end+1,:) = {sprintf('titik: HW-%d.%s', num, KN{j,2}), ...
                    pivui.grain5Fmt.numDash(f), pivui.grain5Fmt.pctStr(i_strainAt(h,f))}; %#ok<AGROW>
                toks{end+1} = sprintf('@pt:HW-%d.%s@f%d', num, KN{j,2}, round(f)); %#ok<AGROW>
            end
        end
    end
    if isempty(rows), rows = {'(belum ada POI)','',''}; toks = {''}; end
    set(h.tblPoi,'Data',rows); h.poiRefs = toks; guidata(fig, h);
end

function i_onPickPoi(fig, evt)
    if isempty(evt) || isempty(evt.Indices), return; end
    row = evt.Indices(1,1);
    h = guidata(fig);
    if row >= 1 && row <= numel(h.poiRefs)
        h.selPoiTok = h.poiRefs{row}; guidata(fig, h);
    end
end

% =====================================================================
% Tutup -> flush
% =====================================================================
function i_onClose(fig)
%I_ONCLOSE  Tutup GRAIN4. TIDAK MENULIS APA PUN ke disk (dulu i_onCloseFlush auto-
%   save _desc/_potdata saat close -> tabel yg kebetulan kosong/terfilter MENIMPA
%   data lengkap TANPA user klik Save -> DATA HILANG, insiden 2026-07-18). Kini
%   close = tutup saja. Simpan HANYA via tombol Save eksplisit (berkonfirmasi).
%
%   Sebelum delete: BERSIHKAN callback-yatim (insiden banjir "DestroyedObject
%   Callback" 2026-07-18). Saat figure dihancurkan, tombol/ROI yg callback-nya
%   masih menunggu (alat taper/bidang interaktif, drawpolyline) ikut fire ->
%   guidata(fig) gagal krn fig sudah mati -> puluhan error. Netralkan di SATU
%   titik: hentikan mode figure + kosongkan callback semua uicontrol + ROI
%   sebelum delete, jadi tak ada handler-yatim yang jalan.
    if ~ishghandle(fig), return; end
    try, set(fig,'CloseRequestFcn',''); end                    %#ok<TRYNC> cegah re-entry
    % Hentikan koleksi kotak model (loupe) bila aktif -> pulihkan WindowButton*Fcn.
    try
        h0 = guidata(fig);
        if isfield(h0,'boxCollect') && isstruct(h0.boxCollect) && isfield(h0.boxCollect,'active') && h0.boxCollect.active
            i_boxCollectStop(fig);
        end
        if isfield(h0,'loupeAx') && ishghandle(h0.loupeAx), delete(h0.loupeAx); end
    catch
    end
    try, pivui.clearFigModes(fig); end                         %#ok<TRYNC> matikan zoom/pan/draw mode
    % Buang ROI aktif (taper/bidang/PSG) supaya callback interaktifnya tak fire.
    try
        h = guidata(fig);
        roiFields = {'roi','roiTaper','roiNucPt','roiMetaLine','roiFaultLine','roiFaultPoly','roiDetach','roiRefHoriz'};
        for i = 1:numel(roiFields)
            f = roiFields{i};
            if isfield(h,f) && ~isempty(h.(f)) && isvalid(h.(f)), delete(h.(f)); end
        end
    catch
    end
    % Kosongkan Callback semua uicontrol + uitable -> tak ada handler-yatim.
    try
        kids = findall(fig,'-property','Callback');
        for i = 1:numel(kids)
            try, set(kids(i),'Callback',''); end                %#ok<TRYNC>
        end
        try, set(findall(fig,'Type','uitable'),'CellEditCallback','','CellSelectionCallback',''); end %#ok<TRYNC>
    catch
    end
    delete(fig);
end

% (DIBUANG: i_onCloseFlush — auto-save-on-close. GRAIN4 tak pernah menulis file tanpa
%  perintah eksplisit + konfirmasi user. Lihat i_onSave.)


% =====================================================================
% Helper kecil
% =====================================================================
function id = i_selectedLineId(h)
    id = '';
    if ~isstruct(h.doc) || ~isfield(h.doc,'psgLines'), return; end
    L = h.doc.psgLines; if isempty(L), return; end
    v = get(h.lstLines,'Value');
    if ~isscalar(v) || v < 1 || v > numel(L), return; end
    id = L{v}.id;
end

function lab = i_curveLabelAt(h, r)
    lab = '';
    if r < 1 || r > numel(h.recs), return; end
    lab = pivcore.pot.records.label(h.recs(r));
    if isempty(lab)
        if isfield(h.recs(r),'point') && ~isempty(h.recs(r).point), lab = h.recs(r).point;
        else, lab = sprintf('P-%d', r); end
    end
end

function r = i_selCurveRow(h)
    r = [];
    if ~isfield(h,'selRows') || isempty(h.selRows), return; end
    rr = h.selRows(:).'; rr = rr(rr>=1 & rr<=numel(h.recs));
    if ~isempty(rr), r = rr(1); end
end

function rr = i_labeledRows(h)
    rr = [];
    if isempty(h.recs), return; end
    for r = 1:numel(h.recs)
        if ~isempty(pivcore.pot.records.label(h.recs(r))), rr(end+1) = r; end %#ok<AGROW>
    end
end

function tf = i_lineHasLabels(ln)
    tf = false;
    if ~isstruct(ln) || ~isfield(ln,'curves'), return; end
    for k = 1:numel(ln.curves)
        c = ln.curves{k};
        if isstruct(c) && isfield(c,'label')
            ty = pivcore.pot.labels.parseLabel(c.label);
            if ~isempty(ty), tf = true; return; end
        end
    end
end

function recs = i_applyDocLabels(recs, ln)
    if ~isstruct(ln) || ~isfield(ln,'curves'), return; end
    m = min(numel(recs), numel(ln.curves));
    for k = 1:m
        c = ln.curves{k};
        if ~isstruct(c), continue; end
        if isfield(c,'label')
            ty = pivcore.pot.labels.parseLabel(c.label);
            if ~isempty(ty), recs(k).assignLabel = c.label; end
        end
        if isfield(c,'cutFrame') && isscalar(c.cutFrame) && isfinite(c.cutFrame)
            recs(k).cutManual = true; recs(k).cutFrame = c.cutFrame;   % pulihkan trim
        end
        if isfield(c,'excluded') && isscalar(c.excluded) && logical(c.excluded)
            recs(k).excluded = true;   % pulihkan kurva yang dibuang
        end
    end
end

function pts = i_ptsFromNetslip(ln)
    pts = pivcore.pot.snapPoints.emptyPts();
    if ~isstruct(ln) || ~isfield(ln,'netslip'), return; end
    for k = 1:numel(ln.netslip)
        e = ln.netslip{k};
        if ~isstruct(e) || ~isfield(e,'hw'), continue; end
        pts = pivcore.pot.snapPoints.setPoint(pts, e.hw, 'start', pivui.grain5Fmt.gf(e,'start'));
        pts = pivcore.pot.snapPoints.setPoint(pts, e.hw, 'nuc',   pivui.grain5Fmt.gf(e,'nuc'));
        pts = pivcore.pot.snapPoints.setPoint(pts, e.hw, 'fsr',   pivui.grain5Fmt.gf(e,'fsr'));
        pts = pivcore.pot.snapPoints.setPoint(pts, e.hw, 'end',   pivui.grain5Fmt.gf(e,'end'));
    end
end

function R = i_recsHW(h), R = pivui.grain4Shell.recsForHW(h.recs); end  % kurva dibuang diabaikan utk HW/net-slip
function s = i_typeStr(v), L = {'HW','F','F0','FFW'}; v = max(1,min(v,4)); s = L{v}; end
