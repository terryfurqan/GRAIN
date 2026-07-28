function figOut = GRAIN5(rootDir, varargin)
%GRAIN5  Fault-first Step 4 (plan B GRAIN4) — versi produksi. Otomasi POI MaxNS/
%   MinFW/Start>FSR/END + Cek Inkonsistensi (Tab ②). (Dipromosikan dari salinan
%   kerja GRAIN5_temp pada 2026-07-06; versi lama diarsipkan di OLD GRAIN/.)
%   MULTI-PSG per-F (tiap garis PSG punya tabel sesar F# SENDIRI + tombol
%   Generate N garis PSG di TAB ①) + TAB ⑨ EXPORT SESAR (kanal CLCW) + TAB ⓪ Help.
%   TAB ⑨ "Export F#" = tabel sesar + tombol export terpilih/semua -> folder
%   PAB5_export/<exp>/F<no>/ berisi: AX main (velmag+shear @ 4 POI START/NUC/FSR/
%   END, TERANG, tanpa tick, |V| cm/s, label HW/FW), AX POT terkalibrasi (full +
%   zoom 200; X=cumulative strain % [0 di KIRI], Y=cm/s; garis vertikal POI
%   bertingkat), NET-SLIP (full + zoom), & <exp>_F<no>.json TERKALIBRASI (POI dlm
%   strain %, net-slip cm/s). Multiplier cm/s (default 0.005) diatur di TAB ⑨.
%   Engine: pivcore.io.grain5FaultExport. TAB ⓪ Help = daftar hotkey (Ctrl+...).
%   Sesar bisa di-ON/OFF (kolom ⏻ paling kiri; OFF = tak dirender/diekspor, input
%   dipertahankan). F1..F15 auto-terisi saat exp dimuat.
%GRAIN5  Tabel sesar model "SLOT SPREADSHEET" (2026-07-03). Kolom F# = ANGKA nomor
%   sesar editable (1,2,3,...); tabel default 15 baris slot; baris yang diketik
%   TETAP di posisinya. Tombol: "+F"(tambah slot >15) · "⇅ Sort"(urut baris by
%   nomor) · "✎ Edit no."(buka kunci penomoran -> boleh DUPLIKAT nomor utk
%   tukar-nukar; klik lagi = kunci + auto-sort) · "🗑 Hapus". Nomor tampil =
%   f.uiNum (boleh duplikat); id record = kunci UNIK internal. SUB-FAULT (SF)
%   DINONAKTIFKAN sementara (kolom SF read-only). TAK ADA lagi "Sisip F#"/"SubF".
%GRAIN5  Step 4 — varian FAULT-FIRST (plan B GRAIN4): mulai dari SESAR (F#), bukan
%   dari Hanging Wall. Duplikat penuh GRAIN4 (back-end SAMA: 1 dataset, 1 garis
%   PSG, kurva POT teruji) + TAB ① "Sesar (F#)". Tab lain digeser +1.
%   (Rombak "slot spreadsheet" masuk dari salinan kerja sementara; kini = GRAIN5.)
%
%   GRAIN5                        % pilih folder ROOT (dialog)
%   GRAIN5(rootDir)              % langsung ke folder
%   GRAIN5(rootDir,'tab','sesar') % buka di tab: sesar|label
%
%   TAB: ① Sesar (F#) — identifikasi N sesar; tiap sesar = 2 kurva (HW & FW) +
%   titik NUC/FSR/START/END; net-slip = HW−FW; "1 sesar = 1 luas" = ∫ net-slip
%   START..END · ② Label HW.
%   (Fase 1 refactor: tab Net-slip UI, Komentar, Produksi Gambar & Komposer
%   Cerita DIBUANG. Field `netslip` per-HW di _potdata.json TETAP dipertahankan.)
%
%   MODEL SESAR (Tab ①): kurva HW/FW dipilih dgn klik kurva di axPOT lalu tombol
%   "Jadikan HW/FW". Net-slip sesar aktif tampil di AXSLIP (luas START..END
%   diarsir). Kebenaran model sesar = `<base>_faults.json` (sidecar terpisah —
%   `_potdata.json`/`_comments.json` GRAIN4 TIDAK disentuh).
%
%   GARIS PSG: exp baru mulai 75% TAK-terkunci (kunci utk sampel); exp yang
%   sudah punya garis di _potdata -> aktif+sampel+seed.
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
    initTab = 'anlz';   % DEFAULT buka Tab ① F# Anlz (analisis/assign), bukan Dip
    for i = 1:2:numel(varargin)-1
        if strcmpi(varargin{i},'tab'), initTab = lower(char(varargin{i+1})); end
    end

    opts = struct();
    opts.Name = 'GRAIN5 — Sesar (F#) / Multi-PSG per-F / Export F# / Help (Step 4, fault-first)';
    opts.rightTitle = 'Operasi (Step 4 — fault-first)';
    opts.hooks = struct( ...
        'beforeLoad',      @i_beforeLoad, ...   % auto-flush progres exp lama sebelum ganti
        'onExpLoaded',     @i_onExpLoaded, ...
        'onLineChanged',   @i_onLineChanged, ...
        'onPotChanged',    @i_onPotChanged, ...
        'onCurveClick',    @i_onCurveClick, ...
        'onFrameChanged',  @i_onFrameChanged, ...
        'afterRenderMain', @i_afterRenderMain, ...
        'decoratePOT',     @i_decoratePOT, ...
        'onPsgEditEnter',  @i_onPsgEditEnter, ... % masuk EDIT garis PSG -> sinkron tombol Zoom
        'slipOverride',    @i_slipOverride);   % GRAIN5: AXSLIP net-slip per-SESAR (HW−FW)

    h = pivui.grain4Shell.build(opts);
    % Ratakan DASAR kolom kanan (pnlR) dgn kolom kiri (pnlL y=0.01) + naikkan
    % sedikit puncaknya -> lebih banyak ruang vertikal utk kontrol tab. (Reposisi
    % lokal GRAIN5_temp; GRAIN4 shell tak diubah.)
    try set(h.pnlR, 'Position', [0.686 0.010 0.308 0.985]); catch, end

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
    % --- Mode XMAX N-frame AXSLIP (stretch horizontal kurva slip F#) ------------
    % Window frame AXSLIP di-batasi N frame di sekitar rentang START..END sesar
    % aktif (pusat = tengah START..END; clamp [1..nF]) -> kurva slip ter-stretch
    % horizontal utk mengamati detail slip F#. 0/Inf = Penuh (1..nF). Tombol di TAB②.
    h.slipXMax = 0;   % 0 = Penuh; else 50/100/150/200 (lebar window frame)
    % --- Zoom/pan HORIZONTAL axPOT/AXSLIP via keyboard (pola GRAIN4) ---------------
    % potXWin = lebar jendela X (frame) yang tampil; 0 = penuh. potXPct = lebar
    % dalam PERSEN total frame (cycle 5%). potXCenter = frame pusat jendela.
    % Sumbu-Y TAK disentuh (hanya X). Satu sumber X-window: i_applyPotXLim -> axPOT
    % & AXSLIP seragam. Ctrl+-/Ctrl++ zoom, Ctrl+Shift+←/→ pan.
    h.potXWin        = 0;     % 0 = penuh; else N frame lebar jendela tampil
    h.potXPct        = 100;   % lebar jendela X dalam PERSEN (100=penuh; cycle 5%)
    h.potXCenter     = NaN;   % frame pusat jendela (NaN = auto/frame aktif)
    h.zonePalette    = 'ngejreng'; % DEFAULT ngejreng (jenuh/terang); 'lembut'=pastel (user: pastel tak kelihatan)
    h.selCurveColor  = [0 0.70 0]; % warna sorot kurva terpilih (HIJAU; dibaca shell highlightSelPOT)
    h.showAllFaults  = false; % tampilkan SEMUA sesar (HW/FW + fill pastel) di axPOT
    h.hideAllFaults  = false; % SEMBUNYIKAN semua sesar teridentifikasi di axPOT (toggle 👁/🚫)
    h.showAllSlip    = false; % AXSLIP: net-slip SEMUA sesar bertumpuk (vs 1 sesar)
    h.faultLabelOn   = true;  % label area sesar aktif (checkbox)
    h.faultLabelPos  = 'top'; % posisi label area: 'center' (di tengah fill) | 'top' (melayang atas)
    h.maOn           = false; % moving average kurva POT (checkbox; default OFF)
    h.maWin          = 3;     % window moving average (panah naik/turun)
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
    % --- GENERATE N garis PSG PERMANEN (GRAIN5_temp_2; TAB ①) --------------------
    % Beda dgn L-grid (temporer, export-only): ini MEMBUAT N garis PSG PERMANEN di
    % h.doc.psgLines (offset tegak-lurus dari garis acuan "L1"), tiap garis LANGSUNG
    % punya tabel sesar F1..F15 SENDIRI (di-scope via fault.psgId). Muncul di listbox.
    h.genRefId       = '';    % id garis PSG acuan (L1) utk generate ('' = pakai garis aktif)
    h.genN           = 3;     % jumlah TOTAL garis yang dibuat (termasuk L1), spinner 1..20
    h.genDy          = 20;    % jarak antar-garis px (spinner, increment 10, min 10)
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
    i_selectTab(h, initTab);
    pivui.grain4Shell.setRoot(h.fig, rootDir);
    % --- Maximize window saat buka (skip di mode senyap tes agar tak rebut fokus) ---
    if ~pivui.quiet()
        try set(h.fig, 'WindowState', 'maximized'); catch, end
    end
    if nargout > 0, figOut = h.fig; end
end


% =====================================================================
% Panel kanan = uitabgroup (urut: Label HW | Net-slip & Titik | Komentar)
% =====================================================================
function h = i_buildTabs(h)
    WHITE = [1 1 1];
    h.tg = uitabgroup('Parent',h.pnlR,'Units','normalized','Position',[0 0 1 1]);
    % URUTAN: ① F# Anlz (penentu PSG + ASSIGN sesar HW/FW + POI) DULU, lalu
    % ② F# Dip (tampilan/render/final + ukur SUDUT/kemiringan sesar). Urutan uitab
    % = urutan visual; mapping i_selectTab by-handle. tabLbl = tab analisis (F#
    % Anlz), tabFault = tab dip/sudut (F# Dip) — nama field dipertahankan agar
    % logika lama tak berubah.
    h.tabLbl  = uitab('Parent',h.tg,'Title','① F# Anlz','BackgroundColor',WHITE);
    h.tabFault= uitab('Parent',h.tg,'Title','② F# Dip','BackgroundColor',WHITE);
    % TAB ⑨ (dinomori 9 utk jaga-jaga penambahan tab lain di antara ②..⑨) —
    % EXPORT SESAR: tabel F# + tombol export terpilih / semua sesar -> folder
    % PAB5_export/<exp>/F<no>/ (screenshot + JSON utk CLCW).
    h.tabExport = uitab('Parent',h.tg,'Title','⑨ Export F#','BackgroundColor',WHITE);
    % TAB ⓪ HELP — daftar hotkey. Ditaruh di KANAN TAB ⑨ (permintaan user).
    h.tabHelp = uitab('Parent',h.tg,'Title','⓪ Help','BackgroundColor',WHITE);
    h = i_buildLblTab(h, h.tabLbl);
    h = i_buildFaultTab(h, h.tabFault);
    h = i_buildExportTab(h, h.tabExport);
    h = i_buildHelpTab(h, h.tabHelp);
    fig = h.fig;
    set(h.tg,'SelectionChangedFcn',@(s,e) i_onTabChanged(fig));
end

function i_onTabChanged(fig)
    i_syncTabIndicators(fig);              % on/off penanda titik/label ikut tab aktif
    h = guidata(fig);
    i_clearGhostLine(fig);                 % bayangan garis non-aktif hilang saat pindah tab
    if i_faultVisible(h)
        i_syncFaultSlipBtn(fig);
        i_refreshFaultTab(fig);            % tabel + render sesar aktif
        if i_onExportTab(h), i_refreshExportTab(fig); end   % TAB ⑨: sinkron tabel export
    elseif ~isempty(h.recs)
        pivui.grain4Shell.renderPOT(fig);    % segarkan label HW aktif + titik
    end
    pivui.grain4Shell.drawSampleMarker(fig); % refresh/sembunyikan sample marker per tab aktif
end

function tf = i_onExportTab(h)
%I_ONEXPORTTAB  Deteksi TAB ⑨ (Export F#) aktif, by-handle.
    tf = isfield(h,'tg') && isvalid(h.tg) && isfield(h,'tabExport') ...
        && isvalid(h.tabExport) && h.tg.SelectedTab==h.tabExport;
end

function i_syncTabIndicators(fig)
%I_SYNCTABINDICATORS  Indikator titik/label ikut TAB AKTIF. tab Sesar(①) ->
%   sample marker ON (lihat posisi sampling HW/FW), titik observasi HW-model OFF
%   (GRAIN5 gambar titik sesar sendiri). tab Label -> sample marker ON, titik
%   observasi OFF. Cegah penanda bocor antar-tab. (Tab Net-slip/Komentar dibuang.)
    h = guidata(fig);
    onFlt = i_onFaultTab(h);
    onLbl = isfield(h,'tg') && isvalid(h.tg) && h.tg.SelectedTab==h.tabLbl;
    h.showSampleMarker = true;            % hanya tab ①/② tersisa -> sample marker aktif
    h.showObsPoints    = ~onLbl && ~onFlt;% titik observasi HW-model OFF di tab Label & Sesar
    guidata(fig, h);
end

function tf = i_onFaultTab(h)
    tf = isfield(h,'tg') && isvalid(h.tg) && isfield(h,'tabFault') ...
        && isvalid(h.tabFault) && h.tg.SelectedTab==h.tabFault;
end

function tf = i_faultVisible(h)
%I_FAULTVISIBLE  Render sesar (HW/FW + fill + titik POI + marker garis PSG) boleh
%   TAMPIL. Kontrol assign sesar ada di Tab ① (F# Anlz) & tampilan/sudut di Tab ②
%   (F# Dip) -> render sesar HARUS terlihat di KEDUA tab (dulu keliru dikunci ke
%   i_onFaultTab saja -> HW/FW yang sudah di-assign tak muncul di axPOT).
    if ~(isfield(h,'tg') && isvalid(h.tg)), tf = false; return; end
    onFlt = isfield(h,'tabFault') && isvalid(h.tabFault) && h.tg.SelectedTab==h.tabFault;
    onLbl = isfield(h,'tabLbl')  && isvalid(h.tabLbl)  && h.tg.SelectedTab==h.tabLbl;
    onExp = i_onExportTab(h);   % TAB ⑨: render sesar (HW/FW+POI) juga tampil utk preview/screenshot
    tf = onFlt || onLbl || onExp;
end

function i_selectTab(h, name)
%I_SELECTTAB  Pilih tab. Tab ① = F# Anlz (tabLbl, analisis/assign) — DEFAULT.
%   Tab ② = F# Dip (tabFault, sudut/kemiringan).
    switch name
        case {'dip','sudut','fault','sesar','f','f#dip'}, set(h.tg,'SelectedTab',h.tabFault);
        case {'anlz','analisis','label','lbl','hw','f#anlz'}, set(h.tg,'SelectedTab',h.tabLbl);
        case {'export','ekspor','tab9','f#export','9'}, set(h.tg,'SelectedTab',h.tabExport);
        case {'help','bantuan','hotkey','tab0','0'}, set(h.tg,'SelectedTab',h.tabHelp);
        otherwise, set(h.tg,'SelectedTab',h.tabLbl);   % default = Tab ① F# Anlz
    end
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
        '── ZOOM / PAN axPOT · AXSLIP (jendela X; Y tetap) ─'; ...
        '  Ctrl + +  /  Ctrl + =       persempit jendela X (zoom-in)'; ...
        '  Ctrl + -                    perlebar jendela X (zoom-out)'; ...
        '  Ctrl+Shift+← / →           geser (pan) 10 frame kiri / kanan'; ...
        '              (frame aktif auto-panning agar selalu terlihat)'; ...
        '  Ctrl + F    toggle axPOT ↔ AXSLIP (net-slip)'; ...
        ''; ...
        '── LONCAT KE POI (sesar terpilih) ─────────────'; ...
        '  Ctrl + J    loncat ke START'; ...
        '  Ctrl + K    loncat ke END'; ...
        '  Ctrl + L    loncat ke NUC'; ...
        '  Ctrl + ;    loncat ke FSR'; ...
        '  Ctrl + H    cycle POI (START → NUC → FSR → END)'; ...
        ''; ...
        '── TANDAI POI (di frame aktif) ────────────────'; ...
        '  Ctrl + 1    set START'; ...
        '  Ctrl + 2    set END'; ...
        '  Ctrl + 3    set NUC'; ...
        '  Ctrl + 4    set FSR'; ...
        ''; ...
        '── ASSIGN KURVA (kurva terpilih) ──────────────'; ...
        '  Ctrl + Q    jadikan HW (Hanging Wall)'; ...
        '  Ctrl + W    jadikan FW (Foot Wall)'; ...
        '  Ctrl+Shift+W  rantai: kurva → FW(Fn) + HW(Fn+1)'; ...
        '              (assign FW, pindah sesar berikutnya, assign HW)'; ...
        ''; ...
        '── UKUR SUDUT SESAR ───────────────────────────'; ...
        '  Ctrl + E / Ctrl + T  klik "Hitung sudut sesar"'; ...
        '              (tekan-1: buka sesi ukur; tekan-2: klik "Kunci sudut")'; ...
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
        else, readyStr = 'HW/FW?'; 
        end
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
    ind = []; try ind = evt.Indices; catch, end
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
    dpi = 150; 
    if isfield(h,'edExpDpi') && ishghandle(h.edExpDpi)
        v = str2double(get(h.edExpDpi,'String')); if isfinite(v) && v>=50 && v<=600, dpi = round(v); end
    end
    velMult = 0.005; 
    if isfield(h,'edExpMult') && ishghandle(h.edExpMult)
        v = str2double(get(h.edExpMult,'String')); if isfinite(v) && v>0, velMult = v; end
    end
    doVel   = i_chkOn(h,'chkExpVel',true);
    doShear = i_chkOn(h,'chkExpShear',true);
    doAxpot = i_chkOn(h,'chkExpAxpot',true);
    opts = struct('dpi',dpi,'velMult',velMult,'doVel',doVel,'doShear',doShear, ...
        'doAxpot',doAxpot,'stamp',stamp,'grainRoot',grainRoot);

    quiet = pivui.quiet();
    wb = []; 
    if ~quiet
        try wb = waitbar(0,'Preparing fault export…','Name','Fault export (TAB ⑨)'); pivui.forceLightTheme(wb); catch, wb = []; end
    end
    cleanWb = onCleanup(@() i_closeIf(wb)); %#ok<NASGU>

    nOk = 0; nSkip = 0; lastDir = '';
    for i = 1:numel(ids)
        id = ids{i};
        if ~isempty(wb) && ishghandle(wb)
            try waitbar((i-1)/numel(ids), wb, sprintf('Exporting fault %d/%d…', i, numel(ids))); catch, end
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
        try delete(findall(ax2,'Tag','frameLine')); catch, end
        try delete(findall(ax2,'Tag','frameTxt')); catch, end
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
    try exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true; catch, ok = false; end
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
    try exportgraphics(tmp, file, 'Resolution', opts.dpi); ok = true; catch, ok = false; end
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

    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 1120 560]);
    try pivui.forceLightTheme(tmp); catch, end   % LIGHT theme (bg putih)
    set(tmp,'Color','w');
    cu = onCleanup(@() i_closeIf(tmp)); %#ok<NASGU>
    ax = axes('Parent',tmp);
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
function s = i_baseNameSafe(df)
    [~, s] = fileparts(char(df));
end

function out = i_expFaultCounts(df)
%I_EXPFAULTCOUNTS  Hook kolom EXTRA tabel eksperimen. df='__names__' -> {judul};
%   df=path .mat -> {nPSG, nFaultId} (string). Diagnostik multi-PSG:
%     #PSG = jumlah garis PSG di _potdata.json (harapan user = 1).
%     #F   = jumlah sesar TER-CHECKLIST (HW + FW + START + END finite) — total;
%            bila #PSG>1 ditulis "total (a+b+..)" per garis agar akar F# liar
%            (mis. F16 dari garis ekstra) langsung kelihatan. '?' = sesar tanpa
%            psgId (orphan). Baca headless; gagal -> '0'/'-'.
    if ischar(df) && strcmp(df,'__names__')
        out = {'#PSG','#F'};   % judul 2 kolom (ringkas): jumlah garis PSG | sesar ter-checklist
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
%I_FAULTCOUNTSTRINGS  Hitung #F ter-checklist. HANYA sesar ber-psgId ∈ psgLines
%   (garis PSG NYATA) yang dihitung. Sesar ber-psgId ASING (garis "hantu" — sisa
%   Generate/edit yang psgLines-nya sudah dihapus) ATAU orphan ('') TIDAK ikut
%   #F; dilaporkan terpisah sebagai "+Ng" (ghost) agar user tahu ada data yatim.
    % Set psgId nyata (∈ psgLines) untuk lookup cepat.
    realSet = containers.Map('KeyType','char','ValueType','logical');
    for k = 1:numel(psgIds), realSet(psgIds{k}) = true; end
    nIdTot = 0; nGhost = 0;   % nIdTot = checklist di garis NYATA; nGhost = checklist di garis hantu/orphan
    perPsg = containers.Map('KeyType','char','ValueType','double');
    try
        doc = pivcore.io.grain5Faults.read(df);   % [] -> emptyDoc (0 faults)
        if isstruct(doc) && isfield(doc,'faults')
            for k = 1:numel(doc.faults)
                f = doc.faults{k};
                if ~isstruct(f), continue; end
                if ~pivui.grain5Model.faultChecklistDone(f), continue; end   % slot kosong/parsial -> skip
                pid = '';
                if isfield(f,'psgId') && (ischar(f.psgId)||isstring(f.psgId)), pid = char(f.psgId); end
                if isempty(pid) || ~isKey(realSet, pid)
                    nGhost = nGhost + 1;   % psgId asing / orphan -> BUKAN garis nyata
                    continue;
                end
                nIdTot = nIdTot + 1;
                if isKey(perPsg, pid), perPsg(pid) = perPsg(pid) + 1; else, perPsg(pid) = 1; end
            end
        end
    catch
    end
    % Rangkai #F: banyak PSG -> "total (a+b+..)" urut psgLines; else angka saja.
    if nPSG > 1
        parts = {};
        for k = 1:numel(psgIds)
            v = 0; if isKey(perPsg, psgIds{k}), v = perPsg(psgIds{k}); end
            parts{end+1} = sprintf('%d', v); %#ok<AGROW>
        end
        fStr = sprintf('%d (%s)', nIdTot, strjoin(parts, '+'));
    else
        fStr = sprintf('%d', nIdTot);
    end
    if nGhost > 0, fStr = sprintf('%s +%dg', fStr, nGhost); end   % g = ghost (perlu bersihkan)
    out = {sprintf('%d', nPSG), fStr};
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
    % PERSIST urutan ke _faults.json (susun ulang record fdoc) supaya modul lain
    % (GRAIN4/GRAIN6) memuat urutan SAMA — tanpa ini sort hanya di memori GRAIN5 & sesar
    % "kembali sebelum diurut" saat dibuka di GRAIN4. Sesar garis PSG lain dijaga.
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
    r = ind(1,1); c = 0; if size(ind,2) >= 2, c = ind(1,2); end
    h = guidata(fig);
    if r < 1 || r > numel(h.faultIds), return; end
    id = h.faultIds{r};
    if c == 1 && ~isempty(id)      % klik kolom ⏻ (paling kiri) -> toggle ON/OFF
        i_toggleFaultEnabled(fig, id); return;
    end
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
    % Sinkronkan seleksi baris tabel (posisi di urutan tampil) + sorotan HIJAU.
    row = find(strcmp(h.activeFaultId, h.faultIds), 1);
    if ~isempty(row) && isfield(h,'tblFault') && ishghandle(h.tblFault)
        try, h.tblFault.Selection = row; catch, end
    end
    i_styleFaultTable(fig);        % pindahkan sorotan HIJAU ke baris sesar aktif baru
    if ~isempty(h.recs), pivui.grain4Shell.renderPOT(fig); end
    i_drawFaultPsgMarker(fig);     % titik HW/FW sesar aktif di garis PSG (axMain)
    i_refreshFaultAngleLabel(fig);
end

function i_stepFault(fig, d)
%I_STEPFAULT  Pindah seleksi sesar/SF ke tetangga TERISI di tabel (slot kosong
%   dilewati). d=-1 prev (Ctrl+M), d=+1 next (Ctrl+/). CLAMP di ujung (TAK wrap).
%   Belum ada seleksi -> pilih baris TERISI pertama.
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
%     Zoom X axPOT/AXSLIP: Ctrl++/= = persempit (zoom-in) · Ctrl+- = perlebar
%     Pan X axPOT/AXSLIP:  Ctrl+Shift+←/→ = geser 10 frame (Y tak disentuh)
%     Toggle plot bawah:  Ctrl+F = axPOT <-> AXSLIP (net-slip; semua tab)
%     Sesar (tab sesar):  Ctrl+M = prev F# · Ctrl+/ = next F#
%     Set POI:            Ctrl+1=START · 2=END · 3=NUC · 4=FSR
%     Loncat POI:         Ctrl+J=START · K=END · L=NUC · ;=FSR · H=cycle
%     Assign kurva:       Ctrl+Q=HW · Ctrl+W=FW
%     Rantai batas:       Ctrl+Shift+W = FW(Fn) -> next F# -> HW(Fn+1)
%     Ukur sudut sesar:   Ctrl+E / Ctrl+T = klik "Hitung sudut sesar" (toggle buka/tutup)
%     Geser seleksi kurva (tabel kiri): Ctrl+[ = naik 1 · ] = turun 1 ·
%                                       Ctrl+{ = naik 5 · } = turun 5
    try
        mods = {}; try, mods = evt.Modifier; catch, end
        if isempty(mods), mods = {}; end
        key = ''; try, key = char(evt.Key); catch, end
        ch  = ''; try, if ~isempty(evt.Character), ch = char(evt.Character); end, catch, end
        if ~any(strcmp(mods,'control')), return; end   % SEMUA hotkey GRAIN5 pakai Ctrl
        hasShift = any(strcmp(mods,'shift'));
        % --- Ctrl(+Shift)+ , / . : langkah frame (berlaku semua tab) ---
        isPrev = strcmp(key,'comma')  || strcmp(ch,',') || strcmp(ch,'<');
        isNext = strcmp(key,'period') || strcmp(ch,'.') || strcmp(ch,'>');
        if isPrev || isNext
            n = 1; if hasShift, n = 5; end   % Ctrl+Shift (=< />) -> 5 frame
            if isPrev, pivui.grain4Shell.stepFrame(fig, -n); else, pivui.grain4Shell.stepFrame(fig, +n); end
            return;
        end
        % --- Ctrl+Shift+←/→ = GESER (pan) jendela X axPOT/AXSLIP 10 frame (spt
        %     tombol ◀ ▶). Pola GRAIN4 (potXWin/potXCenter) — X saja, Y tak disentuh. ---
        if hasShift && (strcmp(key,'leftarrow') || strcmp(key,'rightarrow'))
            if strcmp(key,'leftarrow'), i_onPotXPan(fig, -1); else, i_onPotXPan(fig, +1); end
            return;
        end
        % --- ZOOM HORIZONTAL axPOT/AXSLIP (jendela X, Y DIKUNCI). Pola GRAIN4:
        %     Ctrl+- = PERLEBAR (zoom-out) · Ctrl++/Ctrl+= = PERSEMPIT (zoom-in).
        %     Deteksi robust minus/hyphen & equal/plus. Independen (sebelum guard). ---
        isWiden  = strcmp(key,'hyphen') || strcmp(key,'minus') || strcmp(ch,'-') || strcmp(key,'subtract');
        isNarrow = strcmp(key,'equal') || strcmp(ch,'+') || strcmp(ch,'=') || strcmp(key,'add');
        if isWiden,  i_onPotXWin(fig, +1); return; end   % perlebar (lebih banyak frame)
        if isNarrow, i_onPotXWin(fig, -1); return; end   % persempit (renggangkan)
        % --- Ctrl+F = TOGGLE plot bawah AXSLIP <-> axPOT (pola GRAIN4; INDEPENDEN,
        %     sebelum guard i_faultVisible -> berlaku di semua tab). ---
        if strcmp(key,'f') || strcmp(ch,'f') || strcmp(ch,'F')
            i_onToggleFaultSlip(fig); return;
        end
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
        % --- Navigasi sesar & POI (HANYA saat tab sesar terlihat) ---
        h = guidata(fig);
        if ~i_faultVisible(h), return; end
        % Ctrl+Shift+W = MAKRO rantai batas: kurva terpilih jadi FW(Fn) -> pindah
        % ke sesar berikutnya (Fn+1) -> kurva SAMA jadi HW(Fn+1). (Kurva batas
        % bersama = FW sesar ini & HW sesar tetangga.) Dicek SEBELUM Ctrl+W polos
        % karena ch bisa 'W' saat Shift ditekan.
        isW = strcmp(key,'w') || strcmp(ch,'w') || strcmp(ch,'W');
        if isW && hasShift, i_hotChainFwHw(fig); return; end
        % Ctrl+Q/W = assign kurva terpilih jadi HW/FW.
        if strcmp(key,'q') || strcmp(ch,'q') || strcmp(ch,'Q'), i_onFaultAssign(fig,'hw'); return; end
        if isW, i_onFaultAssign(fig,'fw'); return; end
        % Ctrl+E / Ctrl+T = klik tombol "Hitung sudut sesar" (toggle). Tekan-1 = buka
        % sesi pengukuran (garis miring draggable); tekan-2 = klik "Kunci sudut".
        if strcmp(key,'e') || strcmp(ch,'e') || strcmp(ch,'E'), i_hotToggleMeasAngle(fig); return; end
        if strcmp(key,'t') || strcmp(ch,'t') || strcmp(ch,'T'), i_hotToggleMeasAngle(fig); return; end
        % Ctrl+M = prev F#/SF ; Ctrl+/ = next F#/SF (urutan tampil, clamp no-wrap).
        if strcmp(key,'m') || strcmp(ch,'m') || strcmp(ch,'M')
            i_stepFault(fig, -1); return;
        elseif strcmp(key,'slash') || strcmp(ch,'/')
            i_stepFault(fig, +1); return;
        end
        % Ctrl+J/K/L/; = LONCAT ke POI START/END/NUC/FSR · Ctrl+H = cycle POI.
        if strcmp(key,'j') || strcmp(ch,'j') || strcmp(ch,'J'), i_jumpToPoi(fig,'start'); return; end
        if strcmp(key,'k') || strcmp(ch,'k') || strcmp(ch,'K'), i_jumpToPoi(fig,'end');   return; end
        if strcmp(key,'l') || strcmp(ch,'l') || strcmp(ch,'L'), i_jumpToPoi(fig,'nuc');   return; end
        if strcmp(key,'semicolon') || strcmp(ch,';'),           i_jumpToPoi(fig,'fsr');   return; end
        if strcmp(key,'h') || strcmp(ch,'h') || strcmp(ch,'H'), i_onJumpPoi(fig);          return; end
        % Ctrl+1..4: tandai POI. Ctrl+1=START · Ctrl+2=END · Ctrl+3=NUC · Ctrl+4=FSR.
        switch key
            case {'1','numpad1'}, i_onFaultSetPoint(fig,'start');
            case {'2','numpad2'}, i_onFaultSetPoint(fig,'end');
            case {'3','numpad3'}, i_onFaultSetPoint(fig,'nuc');
            case {'4','numpad4'}, i_onFaultSetPoint(fig,'fsr');
        end
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
    i_applyPotXLim(fig);   % PASTIKAN zoom horizontal (potXWin) TETAP saat toggle view (pola GRAIN4)
    i_syncFaultSlipBtn(fig);
    i_refreshFaultAngleLabel(fig);
end

% ===== Zoom/pan HORIZONTAL axPOT/AXSLIP (jendela X; Y DIKUNCI) — pola GRAIN4 =====
function i_onPotXWin(fig, dir)
%I_ONPOTXWIN  Cycle lebar jendela X axPOT/AXSLIP dalam PERSEN total frame, langkah
%   5%: 100% -> 95% -> ... (dir<0 persempit/zoom-in) & sebaliknya (dir>0 perlebar/
%   zoom-out). Batas bawah 5% (min 2 frame). 100% = penuh (potXWin=0). Y TAK
%   disentuh. Satu sumber X-window (i_applyPotXLim) -> axPOT & AXSLIP seragam.
    h = guidata(fig);
    nF = max(h.nF, 2);
    pct = 100;
    if isfield(h,'potXPct') && isscalar(h.potXPct) && isfinite(h.potXPct) && h.potXPct>0
        pct = h.potXPct;
    elseif isfield(h,'potXWin') && isscalar(h.potXWin) && isfinite(h.potXWin) && h.potXWin>0
        pct = max(5, min(100, round(100*h.potXWin/nF/5)*5));
    end
    pct = round(pct/5)*5;
    if dir < 0, pct = pct - 5; else, pct = pct + 5; end
    pct = max(5, min(100, pct));
    h.potXPct = pct;
    if pct >= 100, h.potXWin = 0;
    else, h.potXWin = max(2, round(pct/100*nF)); end
    if ~isfinite(h.potXCenter), h.potXCenter = round(h.frame); end
    guidata(fig, h);
    i_applyPotXLim(fig);
    if h.potXWin<=0, pivui.setStatus(fig,'axPOT/AXSLIP: tampil penuh (100% frame).');
    else, pivui.setStatus(fig, sprintf('axPOT/AXSLIP: jendela %d%% (%d frame).', pct, h.potXWin)); end
end

function i_onPotXPan(fig, dir)
%I_ONPOTXPAN  Geser jendela X axPOT/AXSLIP ke KIRI(-1)/KANAN(+1) sebesar 10 FRAME.
%   Hanya bermakna saat jendela di-zoom (potXWin>0). Y TAK disentuh.
    h = guidata(fig);
    nF = max(h.nF, 2);
    w = h.potXWin; if ~(isscalar(w) && isfinite(w) && w>0), w = nF; end
    if w >= nF, pivui.setStatus(fig,'axPOT penuh — persempit dulu (Ctrl++) untuk geser.'); return; end
    c = h.potXCenter; if ~isfinite(c), c = round(h.frame); end
    c = c + dir*10;
    c = max(1, min(nF, c));
    h.potXCenter = c; guidata(fig, h);
    i_applyPotXLim(fig);
    pivui.setStatus(fig, sprintf('axPOT/AXSLIP: geser 10 frame %s.', pivui.grain5Fmt.tern(dir<0,'ke kiri','ke kanan')));
end

function i_onPotXFull(fig)
%I_ONPOTXFULL  Kembali ke tampilan penuh axPOT/AXSLIP (100%).
    h = guidata(fig);
    h.potXWin = 0; h.potXCenter = NaN; h.potXPct = 100; guidata(fig, h);
    i_applyPotXLim(fig);
    pivui.setStatus(fig,'axPOT/AXSLIP: tampilan penuh (100%).');
end

function i_applyPotXLim(fig)
%I_APPLYPOTXLIM  Terapkan XLim axPOT sesuai jendela potXWin/potXCenter. potXWin<=0
%   -> auto (penuh; hormati slipXMax utk AXSLIP). Y TAK disentuh. Dipanggil setelah
%   renderPOT + di hook onFrameChanged agar tetap saat ganti frame.
    h = guidata(fig);
    if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
    ax = h.axPOT; nF = max(h.nF, 2);
    w = h.potXWin;
    if ~(isscalar(w) && isfinite(w) && w>0) || w >= nF
        return;   % jendela penuh -> biarkan XLim dari renderPOT/slipXMax
    end
    c = h.potXCenter; if ~isfinite(c), c = round(h.frame); end
    lo = round(c - w/2); hi = lo + w - 1;
    if lo < 1, lo = 1; hi = w; end
    if hi > nF, hi = nF; lo = nF - w + 1; end
    lo = max(1, lo);
    try, set(ax, 'XLim', [lo hi]); catch, end
end

function i_ensurePotXShowsFrame(fig)
%I_ENSUREPOTXSHOWSFRAME  Saat jendela X axPOT/AXSLIP di-zoom (potXWin>0), pastikan
%   FRAME AKTIF selalu masuk jendela: bila keluar rentang tampil (margin ~15%),
%   geser potXCenter (auto-panning). Tak mengubah lebar jendela. No-op saat penuh.
    h = guidata(fig);
    if ~(isfield(h,'potXWin') && isscalar(h.potXWin) && isfinite(h.potXWin) && h.potXWin>0), return; end
    nF = max(h.nF,2); w = h.potXWin; if w >= nF, return; end
    f = round(pivcore.util.scalarOr(h.frame,1)); f = max(1, min(nF, f));
    c = h.potXCenter; if ~isfinite(c), c = f; end
    lo = round(c - w/2); hi = lo + w - 1;
    mrg = max(1, round(0.15*w));
    if f < lo + mrg || f > hi - mrg
        h.potXCenter = f;
        guidata(fig, h);
    end
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
        % Kolom F# = NOMOR TAMPIL sesar (f.uiNum; boleh duplikat). Kolom SF kosong
        % (sub-fault DINONAKTIFKAN sementara).
        fCol = ''; sCol = '';
        uN = pivui.grain5Model.faultUiNum(f);
        if ~isempty(uN), fCol = sprintf('%d', round(uN)); end
        % HW/FW = NOMOR KURVA (bukan posPx).
        hwNum = pivui.grain5Fmt.curveNumTag(h, hwRow, f.hwPosPx);
        if isSub, fwNum = '·'; else, fwNum = pivui.grain5Fmt.curveNumTag(h, fwRow, f.fwPosPx); end
        % Kolom ST = no Frame START (f.startF); EN = SELISIH |HW−FW| pada frame END (2 desimal).
        stCol = pivui.grain5Fmt.numDash(f.startF);
        enVal = pivui.grain5Fmt.nsAtFrame(ns, f.endF);
        angStr = '—'; if isfield(f,'angleDeg'), angStr = pivui.grain5Fmt.num2(f.angleDeg); end
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
                    stCol, pivui.grain5Fmt.num2(enVal), pivui.grain5Fmt.num(area), angStr};
        subIds{k} = pivui.grain5Model.parentId(f);
    end
    if isfield(h,'tblFault') && ishghandle(h.tblFault), set(h.tblFault,'Data',data); end
    h.faultSlots = slots; h.faultIds = ids; h.subIds = subIds;
    h.faultPoiFull = poiFull; h.faultOn = faultOn;
    guidata(fig, h);
    i_styleFaultTable(fig);   % ⏻ hijau/merah + ✓ biru + baris aktif hijau
end

function i_styleFaultTable(fig)
%I_STYLEFAULTTABLE  Style tabel sesar Tab ①: (0) sel ⏻ (kolom 1) HIJAU bila ON
%   (✓) / MERAH bila OFF (✗); (1) sel "✓" POI (kolom 2) BIRU bila POI LENGKAP;
%   (2) baris sesar AKTIF -> latar HIJAU muda. uistyle/addStyle (uitable R2025b).
    h = guidata(fig);
    if ~(isfield(h,'tblFault') && ishghandle(h.tblFault)), return; end
    try, removeStyle(h.tblFault); catch, end
    if isempty(h.faultIds), return; end
    % (0) Sel ⏻ ON/OFF (kolom 1): hijau ✓ (on) / merah ✗ (off) utk baris berisi.
    if isfield(h,'faultOn')
        for r = 1:numel(h.faultIds)
            if isempty(h.faultIds{r}), continue; end   % slot kosong -> tak diwarnai
            if h.faultOn(r), bg = [0.30 0.75 0.35]; else, bg = [0.88 0.25 0.25]; end
            try
                addStyle(h.tblFault, uistyle('BackgroundColor',bg, ...
                    'FontColor',[1 1 1],'FontWeight','bold','HorizontalAlignment','center'), ...
                    'cell', [r 1]);
            catch
            end
        end
    end
    % (1) Sel ✓ POI (kolom 2) biru utk baris ber-POI lengkap.
    if isfield(h,'faultPoiFull')
        full = find(h.faultPoiFull);
        for r = full(:).'
            try
                addStyle(h.tblFault, uistyle('BackgroundColor',[0.20 0.45 0.90], ...
                    'FontColor',[1 1 1],'FontWeight','bold','HorizontalAlignment','center'), ...
                    'cell', [r 2]);
            catch
            end
        end
    end
    % (2) Baris aktif hijau muda (POSISI di urutan TAMPIL h.faultIds).
    if isfield(h,'activeFaultId') && ~isempty(h.activeFaultId)
        row = find(strcmp(h.activeFaultId, h.faultIds), 1);
        if ~isempty(row)
            try
                % Sorot baris aktif TAPI JANGAN timpa sel ⏻ (kolom 1) — warnai
                % kolom 2..akhir saja supaya indikator ON/OFF tetap terlihat.
                addStyle(h.tblFault, uistyle('BackgroundColor',[0.72 0.93 0.72], ...
                    'FontWeight','bold'), 'cell', [repmat(row,13,1) (2:14).']);
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
    i_raiseIndenter(fig);   % indenter max selalu paling atas
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
    % Label F# (checkbox on/off; posisi tengah fill / melayang atas).
    if isfield(h,'faultLabelOn') && ~h.faultLabelOn, return; end
    xc = round((a+b)/2); if xc < 1, xc = 1; end; if xc > nF, xc = nF; end
    lbl = f.id; if isSub, lbl = pivui.grain5Fmt.subTag(f.id); end
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
        % Melayang di ATAS. Posisi-X label DISEBAR (ci/(nMain+1) dari rentang X)
        % supaya label antar-sesar TAK bertumpuk saat rentang fill sama. Garis
        % penunjuk dari label ke titik tengah fill (xc) pada kurva HW.
        xl = get(ax,'XLim');
        if ~isSub && nMain > 1
            xlab = xl(1) + (ci/(nMain+1))*(xl(2)-xl(1));
        else
            xlab = xc;
        end
        yTop = NaN; if xc>=1 && xc<=numel(yHW), yTop = yHW(xc); end
        ytxt = yl(2) - 0.04*(yl(2)-yl(1));
        if isfinite(yTop)
            plot(ax,[xc xlab],[yTop ytxt],'-','Color',[0.3 0.3 0.3],'LineWidth',0.8, ...
                'Tag','faultHL','HitTest','off','PickableParts','none');
        end
        text(ax, xlab, ytxt, lbl, 'Color',[0 0 0], 'FontWeight','bold','FontSize',9, ...
            'BackgroundColor',fillCol,'EdgeColor',[0.4 0.4 0.4],'Margin',2, ...
            'HorizontalAlignment','center','VerticalAlignment','top', ...
            'Tag','faultHL','HitTest','off','PickableParts','none');
    end
end

function i_renderFaultSlip(fig)
%I_RENDERFAULTSLIP  AXSLIP: net-slip sesar aktif = HW−FW. Luas START..END
%   (= ∫ net-slip) diarsir; titik START/NUC/FSR/END ditandai. Dipanggil shell
%   renderSlip lewat hook slipOverride saat view='slip' & tab Sesar aktif.
%   Mode "Slip all" (h.showAllSlip) -> net-slip SEMUA sesar utama bertumpuk.
    h = guidata(fig);
    if isfield(h,'showAllSlip') && h.showAllSlip, i_renderAllSlip(fig); return; end
    ax = h.axPOT; cla(ax);
    set(ax,'Color',[0.99 0.99 0.96],'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
    hold(ax,'on');
    [f, idx] = pivui.grain5Model.activeFault(h);
    ns = []; okHW = false; okFW = false;
    if idx >= 1, [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f); end
    nF = h.nF;
    if isempty(ns) || ~(okHW && okFW) || ~any(isfinite(ns))
        text(ax,0.5,0.5,'AXSLIP sesar — assign HW & FW dulu (klik kurva → Jadikan HW/FW)', ...
            'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
        hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'net-slip (px/frame)'); grid(ax,'on');
        title(ax,'AXSLIP — net-slip sesar');
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
        if nF > 1, xlim(ax, i_slipXWindow(h, nF)); end, ylim(ax,[ylo yhi]);
    end
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
            text(ax, pf, pv, [' ' f.id], 'Color',pivui.grain5Fmt.dol(dcol),'FontWeight','bold','FontSize',8, ...
                'BackgroundColor','w','Margin',1,'Tag','slipCurve', ...
                'HitTest','off','PickableParts','none');
        end
        ny = [ny nsC(g)]; %#ok<AGROW>
    end
    hold(ax,'off');
    xlabel(ax,'Frame'); ylabel(ax, sprintf('net-slip = HW−FW (%s)', pivui.grain5Fmt.unitsStr(h)));
    title(ax, sprintf('AXSLIP — net-slip SEMUA sesar (%d)', ci), 'Color',[0 0 0]);
    grid(ax,'on');
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
            if nF>1, xlim(ax, i_slipXWindow(h, nF)); end, ylim(ax,[ylo yhi]);
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
%I_SLIPOVERRIDE  Hook shell: render net-slip per-SESAR (HW−FW) HANYA saat tab
%   Sesar aktif. Tab lain -> return false -> shell pakai net-slip HW bawaan.
    h = guidata(fig);
    tf = i_onFaultTab(h);
    if tf, i_renderFaultSlip(fig); end
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
        'Position',[0.04 0.870 0.295 0.026],'String','Aktifkan', ...
        'TooltipString','Aktifkan garis terpilih (terkunci + sampel + seed). Tabel sesar F# ganti ke garis ini.', ...
        'Callback',@(s,e) i_onActivateLine(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.352 0.870 0.305 0.026],'String','Simpan garis', ...
        'Callback',@(s,e) i_onSaveLine(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.665 0.870 0.295 0.026],'String','Hapus garis', ...
        'Callback',@(s,e) i_onDeleteLine(fig));

    % --- GENERATE N garis PSG PERMANEN (GRAIN5_temp_2) -------------------------
    %   2 tombol (Jadikan L1 + Generate) + 2 spinner (N garis & jarak antar-garis).
    %   Buat N garis PSG BARU (offset tegak-lurus dari L1) yang PERMANEN di
    %   h.doc.psgLines; tiap garis langsung punya tabel sesar F1..F15 SENDIRI.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.840 0.30 0.026],'String','★ Jadikan L1','Tag','btnGenSetRef', ...
        'FontWeight','bold','ForegroundColor',[0.55 0.35 0], ...
        'TooltipString','Tandai garis PSG AKTIF sebagai L1 (acuan). N−1 garis dibuat di bawahnya.', ...
        'Callback',@(s,e) i_onGenSetRef(fig));
    h.txtGenRef = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.35 0.841 0.61 0.024],'String','L1: — (belum di-set; pakai garis aktif)', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.35 0.30 0.10]);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.810 0.13 0.024],'String','N garis:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.txtGenN = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.17 0.810 0.07 0.024],'String',sprintf('%d',h.genN), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.25, 0.810, @() i_onGenN(fig,+1), @() i_onGenN(fig,-1), 'spGenN');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.44 0.810 0.15 0.024],'String','jarak px:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.txtGenDy = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.60 0.810 0.08 0.024],'String',sprintf('%d',h.genDy), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.69, 0.810, @() i_onGenDy(fig,+1), @() i_onGenDy(fig,-1), 'spGenDy');
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.80 0.808 0.16 0.028],'String','⊞ Generate','Tag','btnGenLines', ...
        'FontWeight','bold','BackgroundColor',[0.86 0.93 1.0],'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString','Buat N garis PSG PERMANEN (offset tegak-lurus L1). Tiap garis punya tabel F1..F15 sendiri.', ...
        'Callback',@(s,e) i_onGenPsgLines(fig));

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
    bwF = 0.148; gwF = 0.006;   % 6 tombol: +F | Sesar | Edit | On/Off | Hapus | Isi F1-15
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
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+5*(bwF+gwF) 0.718 bwF 0.032],'String','⟳ Isi F1-15', ...
        'FontWeight','bold','ForegroundColor',[0.55 0.20 0.55], ...
        'TooltipString',['RESET: HAPUS SEMUA sesar garis PSG aktif lalu isi ulang F1..F15 kosong. ' ...
        'Semua identifikasi (HW/FW/POI/dll) HILANG. Konfirmasi 2x sebelum jalan.'], ...
        'Callback',@(s,e) i_onFaultFillAll(fig));
    % TABEL SESAR — model "slot spreadsheet": 15 baris slot default. Kolom F#
    % (kolom 2) EDITABLE = NOMOR sesar (angka; boleh duplikat di mode Edit).
    % Kolom SF (3) READ-ONLY (sub-fault dinonaktifkan sementara).
    % Kolom 1 "⏻" = ON/OFF sesar (klik utk toggle; hijau ✓=on, merah ✗=off).
    % Kolom 2 "✓" = indikator kelengkapan POI. Kolom 3 "F#" editable.
    % Kolom NUC=NUC-D (manual) + NUC-T (auto) ; FSR=FSR-D (manual) + FSR-T (auto).
    edCol = false(1,14); edCol(3) = true;                    % hanya F# (kol 3) editable (SF nonaktif)
    h.tblFault = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.04 0.384 0.92 0.330], ...
        'ColumnName',{'⏻','✓','F#','SF','HW','FW','NUC','NUC-T','FSR','FSR-T','ST','EN','luas','Sudut'}, ...
        'ColumnWidth',{24 22 30 26 34 34 30 34 30 34 34 34 44 40}, ...
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
    % EMPAT tombol di PALING DASAR tab: Save | Save & Tutup | Tutup | ↔ Catat GRAIN4.
    % Kontrol tambahan lain diletakkan DI ATAS baris ini oleh pembangun tab.
    W = 0.96 - x; g = 0.010;
    w1 = 0.32*W; w2 = 0.28*W; w3 = 0.16*W; w4 = W - w1 - w2 - w3 - 3*g;
    x1 = x; x2 = x1 + w1 + g; x3 = x2 + w2 + g; x4 = x3 + w3 + g;
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
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[x4 yB w4 hB],'String','↔ Catat di GRAIN4', ...
        'BackgroundColor',[0.96 0.94 0.86],'FontSize',8, ...
        'TooltipString','Simpan assign lalu buka GRAIN4 (folder sama) untuk mencatat Tabel Deskripsi.', ...
        'Callback',@(s,e) i_onGoGRAIN4(fig));
end

function i_onGoGRAIN4(fig)
%I_ONGOGRAIN4  Flush assign (faults/potdata) lalu buka GRAIN4 folder sama (pencatat).
    h = guidata(fig);
    root = ''; if isfield(h,'root') && ischar(h.root), root = h.root; end
    try, i_onCloseFlush(fig); catch, end
    try, delete(fig); catch, end
    try
        if ~isempty(root) && isfolder(root), GRAIN4(root); else, GRAIN4(); end
    catch ME
        warning('GRAIN5:goGRAIN4','Gagal buka GRAIN4: %s', ME.message);
    end
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
    try, h.tbl.Selection = tgt; catch, end   % sorot baris target (bila didukung)
    pivui.grain4Shell.loadExperiment(fig, tgt);
    h = guidata(fig);
    nm = ''; if tgt>=1 && tgt<=numel(h.list), nm = h.list(tgt).name; end
    pivui.setStatus(fig, sprintf('Eksperimen %d/%d: %s', tgt, N, nm));
end


% =====================================================================
% Hooks shell
% =====================================================================
function i_beforeLoad(fig)
%I_BEFORELOAD  Auto-flush progres eksperimen LAMA sebelum shell mengganti dataset
%   (reset h.recs/realData). Tulis _potdata (trim/kurva-dibuang/label/garis) +
%   _faults + _comments supaya clean-plot/hapus-kurva/sesar TIDAK hilang saat
%   pindah eksperimen. No-op bila belum ada exp termuat.
    h = guidata(fig);
    if ~isstruct(h) || ~isfield(h,'df') || isempty(h.df), return; end
    if ~strcmp(h.df, h.realData), return; end   % df lama = realData lama (belum diganti)
    try
        h.doc = i_captureForSave(h);
        hasLines = isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines);
        % Simpan bila ADA garis PSG (kurva tersampel) — supaya trim/excluded ikut
        % walau belum ada label HW (alur fault-first).
        if hasLines || ~isempty(h.recs)
            pivcore.io.grain4PotData.write(h.df, h.doc);
        end
        if isstruct(h.cdoc) && isfield(h.cdoc,'comments') && ~isempty(h.cdoc.comments)
            pivcore.io.grain4Comments.write(h.df, h.cdoc);
        end
        if isstruct(h.fdoc) && isfield(h.fdoc,'faults') && ~isempty(h.fdoc.faults)
            pivcore.io.grain5Faults.write(h.df, pivui.grain5Model.captureFaults(h));
        end
    catch
    end
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
    % SIMPAN. Mencegah #F menggelembung (mis. 20 vs checklist nyata 10) & duplikat.
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
    h.activeFaultId = '';
    h.pts = pivcore.pot.snapPoints.emptyPts();
    h.activeHW = NaN; h.selCurveLabel='';
    if isfield(h,'popSign') && ishghandle(h.popSign)
        set(h.popSign,'Value', 1 + double(strcmp(h.signConv,'absolute')));   % selaraskan popup
    end
    if isfield(h,'popFaultSign') && ishghandle(h.popFaultSign)
        set(h.popFaultSign,'Value', 1 + double(strcmp(h.signConv,'absolute')));
    end
    % Geom utk label STATE cummulative strain di axMain (kiri-atas). readGeom
    % murah (whos+load 1 var); label dirender oleh grain4Shell.drawStrainState.
    h.axCal = pivcore.io.grainAxCal.read(h.df);
    dxCm = NaN; strTot = NaN;
    try, [strTot, ~, dxCm] = pivcore.export.frameCatalog.readGeom(h.df); catch, end
    h.axCalR = struct('dxCm', dxCm, 'strainTotalPct', strTot);
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
    i_refreshExportTab(fig);         % TAB ⑨: tabel export sesar (GRAIN5_temp)
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
    i_refreshGenUI(fig);   % selaraskan blok "Generate N garis PSG" (ref/N/jarak)
end

function i_onLineChanged(fig)
    i_clearGhostLine(fig);            % garis digeser/fokus pindah -> bayangan hilang
    h = guidata(fig);
    newId = pivcore.pot.psgId.fromLine(h.line);
    if ~strcmp(newId, h.activePsgId)
        h.pts = pivcore.pot.snapPoints.emptyPts(); h.activeHW = NaN;
    end
    h.activePsgId = newId;
    guidata(fig, h);
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

function i_onFrameChanged(fig), i_refreshContext(fig); i_refreshPoi(fig); i_ensurePotXShowsFrame(fig); i_applyPotXLim(fig); end
function i_afterRenderMain(fig)
    i_drawBufferPreview(fig); i_drawAnnotForActive(fig); i_drawFaultPsgMarker(fig);
    i_applyAxMainViewLock(fig);   % pertahankan zoom/pan beku (render reset ke full)
end

function i_applyAxMainViewLock(fig)
%I_APPLYAXMAINVIEWLOCK  Bila kunci pandang axMain aktif, re-set XLim/YLim ke view
%   beku (h.axMainViewLim). renderMain shell selalu reset ke ekstent penuh tiap
%   frame; hook ini dipanggil SESUDAHNYA -> view zoom/pan bertahan lintas-frame.
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

function i_onPsgEditEnter(fig)
%I_ONPSGEDITENTER  Dipanggil shell saat garis PSG masuk mode EDIT (unlock). Shell
%   sudah mematikan mode figure (clearFigModes) supaya ROI bisa diseret; di sini
%   kita SINKRONKAN status internal tombol "Zoom axMain" agar tak tampak menyala
%   padahal zoom nyata sudah mati (kalau tidak, tombol 🔍 tetap Value=1 tapi zoom
%   tak aktif -> membingungkan + view-lock basi).
    h = guidata(fig);
    changed = false;
    if isfield(h,'axMainZoomOn') && h.axMainZoomOn
        h.axMainZoomOn = false; changed = true;
    end
    if isfield(h,'axMainViewLock') && h.axMainViewLock
        h.axMainViewLock = false; changed = true;
    end
    if changed, h.axMainViewLim = []; guidata(fig, h); end
    try, if isfield(h,'btnAxZoom') && ishghandle(h.btnAxZoom), set(h.btnAxZoom,'Value',0); end, catch, end
    try, if isfield(h,'btnAxViewLock') && ishghandle(h.btnAxViewLock), set(h.btnAxViewLock,'Value',0); end, catch, end
end

function i_onAxMainZoom(fig)
%I_ONAXMAINZOOM  Toggle mode ZOOM/PAN interaktif pada axMain. ON: aktifkan zoom
%   (scroll) + pan (drag) HANYA pada axMain. OFF: matikan + reset ke tampilan
%   penuh (buang kunci pandang juga). Render axMain me-lock interaksi tiap frame,
%   jadi mode diaktifkan ulang di sini saat ditekan.
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum ada.'); return;
    end
    want = ~h.axMainZoomOn;
    if want
        h.axMainZoomOn = true; guidata(fig, h);
        try
            z = zoom(h.axMain); set(z,'Enable','on','Motion','both');
            % pan diaktifkan bergantian lewat drag: pakai zoom scroll + pan tool.
            hp = pan(fig); set(hp,'Enable','off');   % pastikan pan off dulu (zoom pegang drag)
            i_reclaimFigureKeys(fig);   % kembalikan hotkey Ctrl+,/. saat zoom aktif
        catch
        end
        set(h.btnAxZoom,'Value',1);
        pivui.setStatus(fig,'Zoom axMain AKTIF: scroll=zoom, drag=geser. Klik 🔒 utk kunci pandang.');
    else
        h.axMainZoomOn = false; h.axMainViewLock = false; h.axMainViewLim = [];
        guidata(fig, h);
        try, zoom(h.axMain,'off'); catch, end
        try, pan(fig,'off'); catch, end
        try, set(h.btnAxViewLock,'Value',0); catch, end
        set(h.btnAxZoom,'Value',0);
        % Reset ke ekstent penuh: render ulang axMain (xlim/ylim kembali ke xExt/yExt).
        try, pivui.grain4Shell.renderMain(fig); catch, end
        pivui.setStatus(fig,'Zoom axMain MATI: tampilan penuh dipulihkan.');
    end
end

function i_reclaimFigureKeys(fig)
%I_RECLAIMFIGUREKEYS  Saat mode zoom/pan MATLAB aktif, mode-manager memasang
%   window key-listener yg MEMBAJAK keypress figure -> WindowKeyPressFcn kustom
%   (hotkey Ctrl+,/. langkah frame, Ctrl+1..4 POI, dst.) TAK terpanggil. Helper
%   ini menonaktifkan listener mode-manager itu sehingga hotkey figure kembali
%   berfungsi walau zoom/kunci pandang ON. Aman-gagal (try/catch) bila API
%   uigetmodemanager berubah antar-rilis.
    try
        hMgr = uigetmodemanager(fig);
        try
            [hMgr.WindowListenerHandles.Enabled] = deal(false);
        catch
            set(hMgr.WindowListenerHandles, 'Enable', 'off');
        end
        set(fig, 'WindowKeyPressFcn', @(s,e) i_onKeyPress(s, e));
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
        pivui.setStatus(fig, sprintf('Pandang axMain DIKUNCI: X[%.0f %.0f] Y[%.0f %.0f] tetap saat ganti frame.', xl, yl));
    else
        h.axMainViewLock = false; h.axMainViewLim = []; guidata(fig, h);
        set(h.btnAxViewLock,'Value',0);
        pivui.setStatus(fig,'Kunci pandang axMain DILEPAS (mengikuti ekstent penuh).');
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
    i_psgDot(ax, h, hwRow, hwCol, sprintf('HW·%s', f.id));
    if ~isSub, i_psgDot(ax, h, fwRow, [0.10 0.30 0.85], sprintf('FW·%s', fm.id)); end
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
        i_decorateFaultPOT(fig);
    else
        try, delete(findall(ax,'Tag','nsPoint')); catch, end
    end
    % TERAKHIR: terapkan jendela zoom X (potXWin) supaya zoom horizontal keyboard
    % TETAP setelah renderPOT re-fit XLim (berlaku axPOT & AXSLIP). Y tak disentuh.
    i_applyPotXLim(fig);
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

function i_onFaultFillAll(fig)
%I_ONFAULTFILLALL  Tombol "⟳ Isi F1-15": RESET total sesar garis PSG AKTIF lalu
%   isi ulang 15 slot kosong F1..F15. Menghapus SEMUA sesar teridentifikasi
%   (HW/FW/POI/dll) di garis ini. Karena destruktif -> konfirmasi DUA kali.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    id = char(i_field(h,'activePsgId',''));
    if isempty(id)
        pivui.setStatus(fig,'Aktifkan garis PSG dulu sebelum mengisi F1-F15.'); return;
    end
    existing = pivui.grain5Model.faultsForPsg(h.fdoc, id);
    nId = 0;
    for k = 1:numel(existing)
        if ~isempty(pivui.grain5Model.parentId(existing{k})), continue; end  % SF diabaikan di hitungan
        if i_faultIdentified(existing{k}), nId = nId + 1; end
    end

    % --- Konfirmasi 1 ---
    q1 = questdlg( ...
        sprintf(['Isi ulang F1..F15 untuk garis PSG aktif?' newline newline ...
        'Ini akan MENGHAPUS SEMUA sesar di garis ini' ...
        '%s lalu membuat 15 slot kosong.'], ...
        i_identifiedNote(nId)), ...
        'Isi F1-F15 (RESET)', 'Ya, lanjut', 'Batal', 'Batal');
    if ~strcmp(q1,'Ya, lanjut'), pivui.setStatus(fig,'Isi F1-15 dibatalkan.'); return; end

    % --- Konfirmasi 2 (penegasan destruktif) ---
    q2 = questdlg( ...
        sprintf(['KONFIRMASI TERAKHIR.' newline newline ...
        'Semua identifikasi sesar (HW/FW/POI/NUC/FSR/…) di garis PSG aktif ' ...
        'akan HILANG dan TAK BISA dibatalkan. Yakin reset & isi F1..F15?']), ...
        'Yakin RESET semua F#?', 'Ya, RESET sekarang', 'Batal', 'Batal');
    if ~strcmp(q2,'Ya, RESET sekarang'), pivui.setStatus(fig,'Isi F1-15 dibatalkan.'); return; end

    % --- Hapus semua sesar (utama + SF) garis PSG aktif ---
    h = guidata(fig);
    delIds = {};
    F = pivui.grain5Model.faultsForPsg(h.fdoc, id);
    for k = 1:numel(F), delIds{end+1} = F{k}.id; end %#ok<AGROW>
    for k = 1:numel(delIds), h = i_deleteFaultById(h, delIds{k}); end
    h.activeFaultId = '';
    h.faultSlots = {};            % biar seed dari record baru (urut 1..15)
    guidata(fig, h);

    % --- Isi ulang 15 slot kosong (garis kini benar-benar tak punya sesar) ---
    i_seedFaultsForPsg(fig, id);
    h = guidata(fig);
    % Seleksi sesar pertama supaya tabel & konteks konsisten.
    act = pivui.grain5Model.faultsForPsg(h.fdoc, id);
    if ~isempty(act), h.activeFaultId = act{1}.id; end
    guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.grain4Shell.renderMain(fig); pivui.grain4Shell.renderPOT(fig);
    pivui.setStatus(fig,'Sesar garis PSG aktif direset -> F1..F15 kosong.');
end

function tf = i_faultIdentified(f)
%I_FAULTIDENTIFIED  Sesar "teridentifikasi" bila punya HW atau FW ter-assign
%   (hwPosPx/fwPosPx berisi angka valid, bukan NaN).
    tf = false;
    if ~isstruct(f), return; end
    hwOK = isfield(f,'hwPosPx') && isscalar(f.hwPosPx) && isfinite(f.hwPosPx);
    fwOK = isfield(f,'fwPosPx') && isscalar(f.fwPosPx) && isfinite(f.fwPosPx);
    tf = hwOK || fwOK;
end

function s = i_identifiedNote(n)
    if n > 0
        s = sprintf(' (%d di antaranya SUDAH diidentifikasi)', n);
    else
        s = ' (belum ada yang diidentifikasi)';
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
% GENERATE N garis PSG PERMANEN (GRAIN5_temp_2; TAB ①). Beda L-grid (temporer,
% export-only): garis MASUK h.doc.psgLines + tiap garis punya tabel F sendiri
% (via fault.psgId; auto-fill F1..F15 saat garis diaktifkan).
% ======================================================================
function i_onGenSetRef(fig)
%I_ONGENSETREF  Tandai garis PSG AKTIF sebagai L1 (acuan generate).
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    if isempty(i_genRefLine(h))
        pivui.setStatus(fig,'Belum ada garis PSG aktif. Aktifkan/gambar garis dulu.'); return;
    end
    h.genRefId = ''; if isfield(h,'activePsgId'), h.genRefId = char(h.activePsgId); end
    guidata(fig, h); i_refreshGenUI(fig);
    id = h.genRefId; if isempty(id), id = '(garis aktif)'; end
    pivui.setStatus(fig, sprintf('L1 (acuan generate) = "%s".', id));
end

function i_onGenN(fig, d)
    h = guidata(fig);
    h.genN = max(1, min(20, round(h.genN) + d));
    guidata(fig, h); i_refreshGenUI(fig);
    pivui.setStatus(fig, sprintf('Generate: %d garis PSG.', h.genN));
end

function i_onGenDy(fig, d)
    h = guidata(fig);
    h.genDy = max(10, round(h.genDy) + d*10);   % increment 10 px
    guidata(fig, h); i_refreshGenUI(fig);
    pivui.setStatus(fig, sprintf('Generate: jarak %d px.', h.genDy));
end

function i_refreshGenUI(fig)
    h = guidata(fig);
    if isfield(h,'txtGenN')  && ishghandle(h.txtGenN),  set(h.txtGenN, 'String',sprintf('%d',h.genN));  end
    if isfield(h,'txtGenDy') && ishghandle(h.txtGenDy), set(h.txtGenDy,'String',sprintf('%d',h.genDy)); end
    if isfield(h,'txtGenRef') && ishghandle(h.txtGenRef)
        if isempty(i_genRefLine(h))
            set(h.txtGenRef,'String','L1: — (belum di-set; pakai garis aktif)');
        else
            id = h.genRefId; if isempty(id), id = 'garis aktif'; end
            set(h.txtGenRef,'String',sprintf('L1 (acuan): %s', id));
        end
    end
end

function L1 = i_genRefLine(h)
%I_GENREFLINE  Geometri garis acuan L1 utk generate = struct('p1','p2'). Dari doc
%   bila genRefId ada; else dari garis aktif runtime (h.line). [] bila tak ada.
    L1 = [];
    if isstruct(h) && isfield(h,'genRefId') && ~isempty(h.genRefId) ...
            && isstruct(h.doc) && isfield(h.doc,'psgLines')
        [ln, idx] = pivcore.io.grain4PotData.findLine(h.doc, h.genRefId);
        if idx >= 1 && all(isfinite([ln.p1(:); ln.p2(:)])')
            L1 = struct('p1', ln.p1(:).', 'p2', ln.p2(:).'); return;
        end
    end
    if isfield(h,'line') && ~isempty(h.line) && isfield(h.line,'p1') && isfield(h.line,'p2') ...
            && all(isfinite([h.line.p1(:); h.line.p2(:)])')
        L1 = struct('p1', h.line.p1(:).', 'p2', h.line.p2(:).');
    end
end

function lines = i_genGeom(h)
%I_GENGEOM  Daftar geometri L1..Ln (cell struct p1/p2) utk generate. L1 = acuan;
%   L(i>1) = L1 di-offset TEGAK-LURUS ke BAWAH layar sejauh (i-1)*genDy px.
%   (Pola sama i_lgridGeom tapi baca genRefId/genN/genDy + komit permanen.)
    lines = {};
    L1 = i_genRefLine(h);
    if isempty(L1), return; end
    p1 = L1.p1(:).'; p2 = L1.p2(:).';
    downY = -1;
    if isfield(h,'axMain') && ishghandle(h.axMain) && strcmpi(get(h.axMain,'YDir'),'reverse')
        downY = +1;
    end
    d = p2 - p1; Ln = hypot(d(1), d(2));
    if Ln > eps
        nrm = [-d(2), d(1)] / Ln;
        if nrm(2) ~= 0 && sign(nrm(2)) ~= sign(downY), nrm = -nrm; end
        if nrm(2) == 0, nrm = [0, downY]; end
    else
        nrm = [0, downY];
    end
    N  = max(1, round(h.genN));
    dy = max(1, round(h.genDy));
    for i = 1:N
        off = (i-1) * dy * nrm;
        lines{end+1} = struct('p1', p1 + off, 'p2', p2 + off); %#ok<AGROW>
    end
end

function i_onGenPsgLines(fig)
%I_ONGENPSGLINES  Buat N garis PSG PERMANEN (offset tegak-lurus L1) di
%   h.doc.psgLines. Tiap garis BARU langsung punya tabel F1..F15 SENDIRI
%   (auto-fill saat garis diaktifkan / di sini via i_seedFaultsForPsg). L1 sendiri
%   TAK diubah (sudah tersimpan). Garis yang id-nya sudah ada -> dilewati.
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    L1 = i_genRefLine(h);
    if isempty(L1)
        pivui.setStatus(fig,'Belum ada garis acuan. Aktifkan garis PSG lalu "★ Jadikan L1".'); return;
    end
    lines = i_genGeom(h);
    if isempty(lines), pivui.setStatus(fig,'Geometri L1 tak valid.'); return; end
    sp = NaN; if isfield(h,'spacing'), sp = h.spacing; end
    nNew = 0; newIds = {};
    % i=1 = L1 (offset 0) = garis acuan yang SUDAH ada -> LEWATI (jangan duplikat).
    % Buat hanya garis BARU i=2..N (offset > 0). Skip-by-INDEX (bukan id-match) agar
    % kebal beda skema id L1: frac### (garis 75%) vs geom_### (hasil offset).
    for i = 2:numel(lines)
        Li = lines{i};
        id = pivcore.pot.psgId.fromGeom(Li.p1, Li.p2);
        [~, idx] = pivcore.io.grain4PotData.findLine(h.doc, id);
        if idx >= 1, continue; end                          % kebetulan sudah ada -> lewati
        ln = pivcore.io.grain4PotData.lineStruct(id, Li.p1, Li.p2, NaN, sp);
        h.doc = pivcore.io.grain4PotData.upsertLine(h.doc, ln);
        newIds{end+1} = id; nNew = nNew + 1; %#ok<AGROW>
    end
    guidata(fig, h);
    % Seed tabel F1..F15 utk tiap garis BARU (kurva disampel nanti saat diaktifkan).
    for i = 1:numel(newIds), i_seedFaultsForPsg(fig, newIds{i}); end
    i_refreshLines(fig);                                    % listbox garis PSG ter-update
    pivui.setStatus(fig, sprintf('%d garis PSG dibuat (total %d; tiap garis punya tabel F1..F15 sendiri).', ...
        nNew, numel(h.doc.psgLines) + 0));
end

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

function i_onSaveLine(fig)
    h = guidata(fig);
    if isempty(h.line) || isempty(h.df), pivui.setStatus(fig,'Belum ada garis aktif.'); return; end
    h.doc = i_captureActiveLine(h); guidata(fig, h);
    i_refreshLines(fig);
    pivui.setStatus(fig, sprintf('Garis "%s" disimpan ke dokumen.', h.activePsgId));
end

function i_onDeleteLine(fig)
    h = guidata(fig);
    id = i_selectedLineId(h);
    if isempty(id), return; end
    % Buang garis dari psgLines.
    h.doc = pivcore.io.grain4PotData.removeLine(h.doc, id);
    % Bila yang dihapus = garis AKTIF, LEPAS ROI + reset state garis aktif —
    % kalau tidak, i_captureActiveLine (saat Save) akan meng-upsert garis itu
    % KEMBALI dari koordinat ROI yang masih tampil (P-CON-F1: "muncul lagi tiap
    % Save"). Ganti aktif ke garis pertama yang tersisa (atau kosong).
    if isfield(h,'activePsgId') && strcmp(char(h.activePsgId), id)
        if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), try, delete(h.roi); catch, end, end
        h.roi = []; h.line = []; h.activePsgId = ''; h.psgLocked = false;
        i_clearGhostLine(fig);
    end
    % Buang sesar milik garis ini (psgId == id) supaya tak jadi hantu.
    if isstruct(h.fdoc)
        realIds = i_realPsgIds(h.doc);   % id garis PSG yang MASIH ada
        [h.fdoc, ~] = pivui.grain5Model.pruneGhostFaults(h.fdoc, realIds);
    end
    guidata(fig, h);
    % PERSIST LANGSUNG ke disk — hapus harus menempel tanpa menunggu Save (dan
    % tanpa jalur i_captureActiveLine yang bisa menghidupkan ulang).
    try
        pivcore.io.grain4PotData.write(h.df, h.doc);
        if isstruct(h.fdoc), pivcore.io.grain5Faults.write(h.df, h.fdoc); end
    catch ME
        pivui.setStatus(fig, sprintf('Garis dihapus di memori, GAGAL tulis: %s', ME.message));
        i_refreshLines(fig); return;
    end
    % Bila garis aktif ikut terhapus, aktifkan garis pertama yang tersisa.
    if isempty(h.activePsgId) && isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines)
        i_activateLineById(fig, h.doc.psgLines{1}.id);
    end
    i_refreshLines(fig);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Garis "%s" dihapus (tersimpan ke disk).', id));
end


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

function i_onSave(fig)
    h = guidata(fig);
    if isempty(h.df), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    h.doc = i_captureForSave(h);
    % Kontrak _comments.json GRAIN4 tetap dijaga (baca-lalu-tulis apa adanya, tak
    % pernah ditambah dari GUI di GRAIN5 — sistem komentar dibuang di Fase 1).
    if ~isstruct(h.cdoc), h.cdoc = pivcore.io.grain4Comments.read(h.df); end
    if ~isstruct(h.fdoc), h.fdoc = pivcore.io.grain5Faults.read(h.df); end
    h.fdoc = pivui.grain5Model.captureFaults(h);
    guidata(fig, h);
    try
        pivcore.io.grain4PotData.write(h.df, h.doc);
        pivcore.io.grain4Comments.write(h.df, h.cdoc);
        pivcore.io.grain5Faults.write(h.df, h.fdoc);
    catch ME
        pivui.setStatus(fig, sprintf('GAGAL menyimpan: %s', ME.message)); return;
    end
    i_refreshLines(fig);
    nFlt = 0; if isstruct(h.fdoc) && isfield(h.fdoc,'faults'), nFlt = numel(h.fdoc.faults); end
    pivui.setStatus(fig, sprintf('💾 Tersimpan: %d sesar, %d garis, %d HW.', ...
        nFlt, numel(h.doc.psgLines), numel(pivcore.pot.hwLabel.hwNumbers(i_recsHW(h)))));
end

% =====================================================================
% Capture truth + view settings
% =====================================================================
function doc = i_captureActiveLine(h)
    doc = h.doc; if ~isstruct(doc), doc = pivcore.io.grain4PotData.emptyDoc(h.df); end
    % SELARASKAN h.line dgn ROI yang TAMPIL sebelum menangkap -> Save menyimpan
    % garis yang terlihat (cegah desync h.line vs ROI).
    Lcur = pivui.grain4Shell.currentLine(h);
    if ~isempty(Lcur), h.line = Lcur; end
    if isempty(h.line), return; end
    % GARIS AKTIF = garis TERSIMPAN ber-id h.activePsgId. Update HANYA garis itu
    % (koordinat + kurva + netslip). JANGAN membuat garis baru dari koordinat ROI
    % saat Save: kalau garis aktif sudah DIHAPUS dari psgLines (i_onDeleteLine),
    % turunan id-dari-koordinat (fromLine) akan meng-upsert garis itu KEMBALI —
    % inilah "garis hantu muncul lagi tiap Save" (insiden P-CON-F1, bnd.
    % grain4-line-readonly). Jadi: kunci ke garis tersimpan; tak ada -> tak upsert.
    idActive = ''; if isfield(h,'activePsgId'), idActive = char(h.activePsgId); end
    if isempty(idActive), idActive = pivcore.pot.psgId.fromLine(h.line); end
    [ln, idx] = pivcore.io.grain4PotData.findLine(doc, idActive);
    if idx < 1
        % Garis aktif tak ada di psgLines (baru dihapus / belum pernah tersimpan).
        % Cadangan: hanya buat bila id turunan koordinat MASIH cocok garis tersimpan
        % lain; kalau tidak, JANGAN hidupkan garis apa pun.
        idFromLine = pivcore.pot.psgId.fromLine(h.line);
        [ln, idx] = pivcore.io.grain4PotData.findLine(doc, idFromLine);
        if idx < 1, return; end   % garis sudah dihapus -> jangan resurrect
        idActive = idFromLine;
    end
    frac = NaN; if isstruct(h.line)&&isfield(h.line,'frac'), frac = h.line.frac; end
    ln.p1=h.line.p1; ln.p2=h.line.p2; ln.frac=frac;
    if isfinite(h.spacing), ln.spacingPx = h.spacing; end
    ln.curves  = pivcore.io.grain4PotData.curvesFromRecs(h.recs, h.nF);  % label + cutFrame
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
    guidata(fig, h);
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
    % fresh: garis 75% tak-terkunci, belum disampel
    h.activePsgId = pivcore.pot.psgId.fromLine(h.line);
    h.seedMsg = '(garis baru 75% — KUNCI garis utk sampel POT)';
    guidata(fig, h); i_setSeedMsg(h);
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
    i_onCloseFlush(fig);
    if ishghandle(fig), delete(fig); end
end

function i_onCloseFlush(fig)
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    if ~isstruct(h) || ~isfield(h,'df') || isempty(h.df) || ~isstruct(h.doc), return; end
    try
        h.doc = i_captureForSave(h);
        hasLines = isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines);
        hasHW = ~isempty(pivcore.pot.hwLabel.hwNumbers(h.recs));
        if hasLines || hasHW, pivcore.io.grain4PotData.write(h.df, h.doc); end
        if isstruct(h.cdoc) && isfield(h.cdoc,'comments') && ~isempty(h.cdoc.comments)
            pivcore.io.grain4Comments.write(h.df, h.cdoc);
        end
        if isstruct(h.fdoc) && isfield(h.fdoc,'faults') && ~isempty(h.fdoc.faults)
            pivcore.io.grain5Faults.write(h.df, pivui.grain5Model.captureFaults(h));   % flush model sesar
        end
    catch
    end
end


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
