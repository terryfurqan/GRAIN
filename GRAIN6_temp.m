function figOut = GRAIN6_temp(rootDir, varargin)
%GRAIN6_TEMP  Salinan KERJA GRAIN6 (staging fitur HB; pola GRAIN5_temp). Rename balik
%   GRAIN6_temp -> GRAIN6 saat puas = TAK butuh wiring baru (standalone di root,
%   dipanggil by-name; fungsi lokal & engine di-SHARE). Entry fn di-rename
%   GRAIN6->GRAIN6_temp (satu-satunya wiring, wajib = nama file).
%
%GRAIN6  Step 4 — varian TAMPAK PETA (map-view) = GRAIN5 + lapisan HB. Semua fitur
%   sesar F# GRAIN5 DIPERTAHANKAN PENUH (tabel F#, assign HW/FW, POI, sudut,
%   net-slip); GRAIN6 hanya MENAMBAH kurva HB (Hinterland Block). GRAIN5.m tetap utuh.
%
%   GRAIN6                        % pilih folder ROOT (dialog)
%   GRAIN6(rootDir)              % langsung ke folder
%   GRAIN6(rootDir,'tab','anlz') % buka di tab: anlz|dip
%
%   KURVA HB (tampak peta): "mirip max-indenter tapi untuk Hanging Wall aktif".
%   Dibangun dari beberapa KURVA KANDIDAT yang diseleksi user (klik axPOT), tiap
%   kurva diberi batas awal X0 & akhir X1 (klik kurva + scrub frame -> Set X0/X1,
%   snap ke kurva). Kurva-kurva overlap -> digabung jadi SATU garis HB; zona
%   overlap = MAX (envelope atas). Garis HB mulai di X0 kurva pertama (tanpa ekor
%   ke 0), terus dinilai maksimumnya. Tampil sbg OVERLAY hijau di axPOT sejajar
%   garis hitam max-indenter. 1 HB per garis PSG (terikat per-PSG).
%
%   Kebenaran HB = `<base>_hb.json` (sidecar terpisah — engine pivcore.io.grain6Hb;
%   `_potdata.json`/`_comments.json`/`_faults.json` TIDAK disentuh). Model sesar
%   F# = `<base>_faults.json` (spt GRAIN5, dipertahankan).
%
%   GARIS PSG: listbox -> DROPDOWN (hemat ruang; N garis PSG = N sisi pengamatan
%   kiri/kanan/atas). Setting per-kurva (excluded/cutFrame/POI/kandidat HB) UNIK
%   per garis PSG.
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
    opts.Name = 'GRAIN6 — Tampak Peta / Kurva HB (Hinterland Block) + Sesar F# (Step 4, map-view)';
    opts.rightTitle = 'Operasi (Step 4 — tampak peta / HB)';
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
    % --- Model "slot spreadsheet" (rombak tabel sesar; ditiru dari GRAIN5_temp) ---
    h.faultSlots = {};     % id per-BARIS tabel ('' = baris kosong); sumber urutan tampil.
                           %   Baris X yang user ketik TETAP di posisi X (tak reorder).
                           %   Panjang >=15. Murni UI-state: TIDAK ditulis ke _faults.json.
    h.faultEditMode = false; % KUNCI penomoran: OFF=tolak duplikat nomor; ON=izinkan (tukar-nukar)
    % --- State fitur baru GRAIN5_temp (WAJIB sebelum builder tab membacanya) ---
    h.poiMarkerScale = 1.0;   % skala ukuran titik POI di axPOT (tombol ▲/▼)
    h.psgLineWidth   = 1.0;   % tebal garis PSG di axMain (tipis; kontrol di bawah save)
    h.psgMarkerSize  = 6;     % ukuran titik/marker ujung garis PSG di axMain
    h.zoneAlpha      = 0.45;  % transparansi fill zona/area sesar (naik: pastel dulu tak terlihat)
    h.zonePalette    = 'ngejreng'; % DEFAULT ngejreng (jenuh/terang); 'lembut'=pastel (user: pastel tak kelihatan)
    h.selCurveColor  = [0 0.70 0]; % warna sorot kurva terpilih (HIJAU; dibaca shell highlightSelPOT)
    h.showAllFaults  = false; % tampilkan SEMUA sesar (HW/FW + fill pastel) di axPOT
    h.showAllSlip    = false; % AXSLIP: net-slip SEMUA sesar bertumpuk (vs 1 sesar)
    h.faultLabelOn   = true;  % label area sesar aktif (checkbox)
    h.faultLabelPos  = 'top'; % posisi label area: 'center' (di tengah fill) | 'top' (melayang atas)
    h.maOn           = false; % moving average kurva POT (checkbox; default OFF)
    h.maWin          = 3;     % window moving average (panah naik/turun)
    h.clickCurveOn   = true;  % seleksi klik axPOT: KURVA aktif (checkbox, default ON)
    h.clickFrameOn   = true;  % seleksi klik axPOT: FRAME aktif (checkbox, default ON)
    % --- State HB (Hinterland Block; GRAIN6 map-view) ---
    h.hbdoc        = [];      % dokumen HB (pivcore.io.grain6Hb); diisi saat exp dimuat
    h.hbSelPos     = NaN;     % posPx kandidat HB terpilih di tblHb
    h.hbIds        = {};      % posPx (double) paralel baris tblHb
    h.showHbOverlay= true;    % tampilkan garis HB (overlay hijau di axPOT)
    % Hook transformasi tampil kurva (moving average) -> dibaca shell dispYV.
    h.curveTransform = @(yv) i_maApply(h.fig, yv);

    % Simpan state ke figure DULU supaya callback builder (i_dispCtrls dst yang
    % baca/tulis guidata) konsisten, lalu bangun tab.
    guidata(h.fig, h);
    h = i_buildTabs(h);

    guidata(h.fig, h);
    set(h.fig, 'CloseRequestFcn', @(s,e) i_onClose(s));
    set(h.fig, 'WindowKeyPressFcn', @(s,e) i_onKeyPress(s, e));   % hotkey frame Ctrl+,/. & POI Ctrl+1..4
    i_selectTab(h, initTab);
    pivui.grain4Shell.setRoot(h.fig, rootDir);
    % --- Maximize window saat buka (skip di mode senyap tes agar tak rebut fokus) ---
    if ~pivui.quiet()
        try, set(h.fig, 'WindowState', 'maximized'); catch, end
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
    h = i_buildLblTab(h, h.tabLbl);
    h = i_buildFaultTab(h, h.tabFault);
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
    elseif ~isempty(h.recs)
        pivui.grain4Shell.renderPOT(fig);    % segarkan label HW aktif + titik
    end
    pivui.grain4Shell.drawSampleMarker(fig); % refresh/sembunyikan sample marker per tab aktif
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
    tf = onFlt || onLbl;
end

function i_selectTab(h, name)
%I_SELECTTAB  Pilih tab. Tab ① = F# Anlz (tabLbl, analisis/assign) — DEFAULT.
%   Tab ② = F# Dip (tabFault, sudut/kemiringan).
    switch name
        case {'dip','sudut','fault','sesar','f','f#dip'}, set(h.tg,'SelectedTab',h.tabFault);
        case {'anlz','analisis','label','lbl','hw','f#anlz'}, set(h.tg,'SelectedTab',h.tabLbl);
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

    % --- Zona sesar: alpha (transparansi) + palet warna ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.532 0.14 0.026],'String','Zona:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.17 0.532 0.12 0.026],'String','alpha', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.txtZoneAlpha = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.30 0.532 0.09 0.026],'String',sprintf('%.2f',h.zoneAlpha), ...
        'HorizontalAlignment','center','BackgroundColor',[0.95 0.95 0.90],'FontSize',8);
    i_spinBtns(P, fig, 0.40, 0.534, @() i_onZoneAlpha(fig,+1), @() i_onZoneAlpha(fig,-1), 'spZoneA');
    h.popZonePalette = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.53 0.532 0.43 0.028],'String',{'Palet: lembut','Palet: ngejreng'}, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Koleksi warna zona/area sesar: lembut (pastel) atau ngejreng (jenuh).', ...
        'Callback',@(s,e) i_onZonePalette(fig));

    % --- Plot bawah: split Kurva Slip all / F# + konvensi ---
    h.btnSlipAll = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.496 0.28 0.032],'String','Slip all', ...
        'FontWeight','bold', ...
        'TooltipString',['Plot bawah: net-slip SEMUA sesar teridentifikasi bertumpuk. ' ...
        'Klik lagi -> kembali ke view Semua Kurva standar.'], ...
        'Callback',@(s,e) i_onFaultSlipAll(fig));
    h.btnFaultSlip = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.33 0.496 0.30 0.032],'String','Slip F#','Value',0, ...
        'FontWeight','bold', ...
        'TooltipString',['Plot bawah: net-slip SATU sesar aktif (HW−FW; luas START..END diarsir). ' ...
        'Klik lagi -> kembali ke kurva POT.'], ...
        'Callback',@(s,e) i_onToggleFaultSlip(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.64 0.498 0.12 0.026],'String','Konv:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.popFaultSign = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.76 0.496 0.20 0.030],'String',{'signed','absolute'}, ...
        'BackgroundColor',WHITE, ...
        'TooltipString',['Konvensi tanda net-slip. signed: HW−FW bisa +/− (arah nyata; luas bertanda). ' ...
        'absolute: |HW−FW| (selalu ≥0; besaran saja).'], ...
        'Callback',@(s,e) i_onFaultSign(fig));

    % --- Tampilkan semua sesar + Zoom/Reset ---
    h.btnShowAll = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 0.460 0.40 0.032],'String','▦ Semua sesar','Value',0, ...
        'FontWeight','bold', ...
        'TooltipString',['Tampilkan HANYA kurva sesar teridentifikasi (HW merah / FW biru) + ' ...
        'fill pastel transparan tiap sesar + label F#.'], ...
        'Callback',@(s,e) i_onToggleShowAll(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.45 0.460 0.25 0.032],'String','🔍 Zoom', ...
        'TooltipString','Tarik kotak di plot bawah untuk zoom-in (auto-kunci view).', ...
        'Callback',@(s,e) pivui.grain4Shell.zoomBoxPOT(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.71 0.460 0.25 0.032],'String','Reset view', ...
        'Callback',@(s,e) pivui.grain4Shell.resetViewPOT(fig));
    % Label area sesar (checkbox on/off + posisi tengah/atas).
    h.chkFaultLabel = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 0.428 0.40 0.028],'String','Label area','Value',1, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Tampilkan label F# pada area fill sesar (mode "Semua sesar").', ...
        'Callback',@(s,e) i_onToggleFaultLabel(fig));
    h.popFaultLabelPos = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.45 0.426 0.51 0.030],'String',{'label di ATAS (garis penunjuk)','label di TENGAH fill'}, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Posisi label area: melayang di atas (tak menghalangi kurva) atau di tengah fill.', ...
        'Callback',@(s,e) i_onFaultLabelPos(fig));

    % --- Kontrol tampilan tambahan (POI size · MA · garis PSG) DI ATAS save ---
    h = i_dispCtrls(h, P, fig, 0.04);
    i_saveBtn(P, fig, 0.04);
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

function slots = i_ensureSlots(h)
%I_ENSURESLOTS  Pastikan h.faultSlots ada, sinkron dgn record, & panjang >=15.
%   - Kosong (mis. baru load) -> seed dari faultRowOrder (induk-lalu-anak) lalu pad.
%   - Slot yang id-nya tak lagi punya record -> kosongkan ('') TANPA compact
%     (spreadsheet: baris bertahan di posisinya).
%   - Record yang ADA tapi belum muncul di slot manapun -> tempel ke slot kosong
%     pertama / akhir (mis. dibuat lewat jalur lain).
    MINROWS = 15;
    if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults'))
        slots = repmat({''}, 1, MINROWS); return;
    end
    slots = {};
    if isfield(h,'faultSlots') && ~isempty(h.faultSlots), slots = h.faultSlots(:).'; end
    if isempty(slots)
        ord = pivui.grain5Model.faultRowOrder(h);         % seed awal (load file lama)
        slots = cell(1, numel(ord));
        for k = 1:numel(ord), slots{k} = ord{k}.id; end
    end
    % Kosongkan slot yang record-nya hilang.
    for k = 1:numel(slots)
        if isempty(slots{k}), continue; end
        [~, ix] = pivcore.io.grain5Faults.findFault(h.fdoc, slots{k});
        if ix < 1, slots{k} = ''; end
    end
    % Tempel record yang belum ada di slot manapun.
    for k = 1:numel(h.fdoc.faults)
        fk = h.fdoc.faults{k};
        if ~(isstruct(fk) && isfield(fk,'id')), continue; end
        if any(strcmp(slots, fk.id)), continue; end
        empt = find(cellfun(@isempty, slots), 1);
        if isempty(empt), slots{end+1} = fk.id; else, slots{empt} = fk.id; end %#ok<AGROW>
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
    if c ~= 2, i_refreshFaultTab(fig); return; end             % hanya F# (kol 2) editable (SF nonaktif)
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
    h.faultSlots = newSlots; guidata(fig, h);
    i_refreshFaultTab(fig);
    pivui.setStatus(fig, sprintf('Diurutkan %d sesar berdasarkan nomor.', numel(sorted)));
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
    if r >= 1 && r <= numel(h.faultIds)
        i_setActiveFault(fig, h.faultIds{r});
    end
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

function i_onKeyPress(fig, evt)
%I_ONKEYPRESS  Hotkey langkah frame (SEGALA tab; step dari h.frame, bukan slider):
%     Ctrl+, / Ctrl+.   -> mundur/maju 1 frame
%     Ctrl+< / Ctrl+>   -> mundur/maju 5 frame  (< = Shift+, ; > = Shift+.)
%   Navigasi sesar (tab sesar terlihat): Ctrl+M = prev F#/SF · Ctrl+/ = next F#/SF
%   (urutan tampil tabel, clamp no-wrap).
%   Tandai POI (tab ① aktif): Ctrl+1=START · Ctrl+2=END · Ctrl+3=NUC · Ctrl+4=FSR.
%   MacBook keyboard Windows: Ctrl -> 'control', Shift -> 'shift'. CATATAN mac:
%   Ctrl+panah dipakai Mission Control -> DIHINDARI. Arah frame dari evt.Key
%   ('comma'/'period'); besar langkah dari ada/tidaknya 'shift' (5 vs 1). PENTING:
%   evt WindowKeyPressFcn = OBJEK KeyData (BUKAN struct) -> isfield() selalu false.
%   Akses properti LANGSUNG (aman utk objek & struct).
    try
        mods = {}; try, mods = evt.Modifier; catch, end
        if isempty(mods), mods = {}; end
        key = ''; try, key = char(evt.Key); catch, end
        ch  = ''; try, if ~isempty(evt.Character), ch = char(evt.Character); end, catch, end
        if ~any(strcmp(mods,'control')), return; end   % SEMUA hotkey GRAIN5 pakai Ctrl
        % --- Ctrl(+Shift)+ , / . : langkah frame (berlaku semua tab) ---
        isPrev = strcmp(key,'comma')  || strcmp(ch,',') || strcmp(ch,'<');
        isNext = strcmp(key,'period') || strcmp(ch,'.') || strcmp(ch,'>');
        if isPrev || isNext
            big = any(strcmp(mods,'shift'));   % Ctrl+Shift (=< />) -> 5 frame
            n = 1; if big, n = 5; end
            if isPrev, pivui.grain4Shell.stepFrame(fig, -n); else, pivui.grain4Shell.stepFrame(fig, +n); end
            return;
        end
        % --- Navigasi sesar & POI (HANYA saat tab sesar terlihat) ---
        h = guidata(fig);
        if ~i_faultVisible(h), return; end
        % Ctrl+M = prev F#/SF ; Ctrl+/ = next F#/SF (urutan tampil, clamp no-wrap).
        if strcmp(key,'m') || strcmp(ch,'m') || strcmp(ch,'M')
            i_stepFault(fig, -1); return;
        elseif strcmp(key,'slash') || strcmp(ch,'/')
            i_stepFault(fig, +1); return;
        end
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
    data = repmat({''}, n, 11); ids = cell(1, n); subIds = cell(1, n); poiFull = false(1, n);
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
        % Kolom ST/EN = SELISIH |HW−FW| pada frame START/END (2 desimal).
        stVal = pivui.grain5Fmt.nsAtFrame(ns, f.startF);
        enVal = pivui.grain5Fmt.nsAtFrame(ns, f.endF);
        angStr = '—'; if isfield(f,'angleDeg'), angStr = pivui.grain5Fmt.num2(f.angleDeg); end
        full = isfinite(f.startF) && isfinite(f.nuc) && isfinite(f.fsr) && isfinite(f.endF);
        poiFull(k) = full;
        chkCol = ''; if full, chkCol = '✓'; end
        data(k,:) = {chkCol, fCol, sCol, hwNum, fwNum, ...
                    pivui.grain5Fmt.numDash(f.nuc), pivui.grain5Fmt.numDash(f.fsr), pivui.grain5Fmt.num2(stVal), ...
                    pivui.grain5Fmt.num2(enVal), pivui.grain5Fmt.num(area), angStr};
        subIds{k} = pivui.grain5Model.parentId(f);
    end
    if isfield(h,'tblFault') && ishghandle(h.tblFault), set(h.tblFault,'Data',data); end
    h.faultSlots = slots; h.faultIds = ids; h.subIds = subIds; h.faultPoiFull = poiFull;
    guidata(fig, h);
    i_styleFaultTable(fig);   % highlight HIJAU baris aktif + sel ✓ biru bila POI lengkap
end

function i_styleFaultTable(fig)
%I_STYLEFAULTTABLE  Style tabel sesar Tab ①: (1) sel "✓" (kolom 1) BIRU +
%   teks putih bila POI baris itu LENGKAP (START/NUC/FSR/END semua ter-assign);
%   (2) baris sesar AKTIF -> latar HIJAU (penanda "sedang edit F# berapa").
%   Pakai uistyle/addStyle (uitable app R2025b). ✓ digambar dulu, hijau di atas.
    h = guidata(fig);
    if ~(isfield(h,'tblFault') && ishghandle(h.tblFault)), return; end
    try, removeStyle(h.tblFault); catch, end
    if isempty(h.faultIds), return; end
    % (1) Sel ✓ biru utk baris ber-POI lengkap.
    if isfield(h,'faultPoiFull')
        full = find(h.faultPoiFull);
        for r = full(:).'
            try
                addStyle(h.tblFault, uistyle('BackgroundColor',[0.20 0.45 0.90], ...
                    'FontColor',[1 1 1],'FontWeight','bold','HorizontalAlignment','center'), ...
                    'cell', [r 1]);
            catch
            end
        end
    end
    % (2) Baris aktif hijau (pakai POSISI di urutan TAMPIL h.faultIds, bukan idx
    %     penyimpanan — agar SF pun tersorot benar).
    if isfield(h,'activeFaultId') && ~isempty(h.activeFaultId)
        row = find(strcmp(h.activeFaultId, h.faultIds), 1);
        if ~isempty(row)
            try
                addStyle(h.tblFault, uistyle('BackgroundColor',[0.72 0.93 0.72], ...
                    'FontWeight','bold'), 'row', row);
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
    for k = 1:numel(h.fdoc.faults)
        f = h.fdoc.faults{k};
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
    if isfield(h,'potView') && strcmp(h.potView,'slip'), return; end   % slip view dirender i_renderFaultSlip
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
    end
    if okFW
        y = pivui.grain5Fmt.clampRange(i_rowDispY(h, fwRow), clampAB);
        i_plotPt(ax, y, f.startF,'start'); i_plotPt(ax, y, f.nuc,'nuc');
        i_plotPt(ax, y, f.fsr,'fsr');      i_plotPt(ax, y, f.endF,'end');
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
    i_raiseIndenter(fig);   % indenter max selalu paling atas
    if ~hs, hold(ax,'off'); end
end

function i_drawPersistentZones(fig)
%I_DRAWPERSISTENTZONES  Untuk SETIAP sesar (utama & SF) yang LENGKAP (HW+FW/
%   pasangan + START + END): (1) REDAM versi PENUH kurva HW/FW (spaghetti shell)
%   supaya ujung di luar [start,end] TAK menjulur, (2) fill zona pastel, (3)
%   gambar kurva HW/FW TERPOTONG ke [start,end]. PERSISTEN walau sesar itu tidak
%   aktif (pindah sesar → ujung yg disembunyikan tetap hilang). Tag faultFill/faultHL.
    h = guidata(fig); ax = h.axPOT; nF = h.nF;
    F = {}; if isstruct(h.fdoc) && isfield(h.fdoc,'faults'), F = h.fdoc.faults; end
    cmap = i_faultColorMap(h);
    % Kumpulkan baris record yang menjadi HW/FW sesar lengkap -> redam versi penuh.
    dimRows = [];
    for k = 1:numel(F)
        f = F{k};
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
    F = {}; if isstruct(h.fdoc) && isfield(h.fdoc,'faults'), F = h.fdoc.faults; end
    ci = 0; nMain = 0;
    for k = 1:numel(F), if isempty(pivui.grain5Model.parentId(F{k})), nMain = nMain + 1; end, end
    for k = 1:numel(F)
        f = F{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end       % SF via induk
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
        if nF > 1, xlim(ax,[1 nF]); end, ylim(ax,[ylo yhi]);
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
    F = {}; if isstruct(h.fdoc) && isfield(h.fdoc,'faults'), F = h.fdoc.faults; end
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
            if nF>1, xlim(ax,[1 nF]); end, ylim(ax,[ylo yhi]);
        end
    end
    pivui.grain4Shell.updateFrameLine(fig);
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
%I_BUILDLBLTAB  TAB ① "HB Anlz" (GRAIN6) = PENENTU garis PSG (DROPDOWN) + tabel
%   KANDIDAT HB (kurva penyusun garis Hinterland Block + X0/X1) + EDIT sesar F#
%   (tabel sesar + assign HW/FW + POI + hapus/trim). Blok sesar DIGESER TURUN
%   memberi ruang tabel HB. Tema TERANG (putih).
    WHITE = [1 1 1]; fig = h.fig;
    % --- Garis PSG tersimpan: DROPDOWN (hemat ruang; N garis = N sisi pengamatan) ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.968 0.19 0.026],'String','Garis PSG:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    h.lstLines = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.24 0.966 0.72 0.030],'String',{' '}, 'FontSize',8, ...
        'TooltipString','Garis PSG ber-ID exp aktif. Pilih -> bayangan posisi; Aktifkan utk pindah.', ...
        'Callback',@(s,e) i_onPickLine(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.932 0.295 0.028],'String','Aktifkan', ...
        'TooltipString','Aktifkan garis terpilih (terkunci + sampel + seed).', ...
        'Callback',@(s,e) i_onActivateLine(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.352 0.932 0.305 0.028],'String','Simpan garis', ...
        'Callback',@(s,e) i_onSaveLine(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.665 0.932 0.295 0.028],'String','Hapus garis', ...
        'Callback',@(s,e) i_onDeleteLine(fig));

    % --- Tebal garis per-kelompok (live) ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.900 0.24 0.026],'String','Tebal garis →', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.28 0.900 0.18 0.026],'String','HW/label:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edLwA = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.47 0.901 0.10 0.028],'String',sprintf('%g',h.lwAssigned), ...
        'BackgroundColor',WHITE,'TooltipString','Tebal kurva ber-label (live).', ...
        'Callback',@(s,e) i_onLineWidths(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.58 0.900 0.16 0.026],'String','mentah:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edLwR = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.75 0.901 0.10 0.028],'String',sprintf('%g',h.lwRaw), ...
        'BackgroundColor',WHITE,'TooltipString','Tebal kurva mentah belum di-assign (live).', ...
        'Callback',@(s,e) i_onLineWidths(fig));

    % --- Zoom + kunci tampilan axPOT (untuk baca bentuk kurva saat assign) ---
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.868 0.30 0.028],'String','🔍 Zoom kotak', ...
        'TooltipString','Tarik kotak di axPOT untuk zoom-in (otomatis mengunci view).', ...
        'Callback',@(s,e) pivui.grain4Shell.zoomBoxPOT(fig));
    uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.35 0.868 0.34 0.028],'String','🔓 View bebas','Value',0, ...
        'Tag','grain4ViewLock', ...
        'TooltipString',['Kunci tampilan axPOT: zoom bertahan saat Assign/pindah kurva. ' ...
        'Zoom dulu lalu kunci.'], ...
        'Callback',@(s,e) pivui.grain4Shell.setViewLock(fig, get(gcbo,'Value')==1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.70 0.868 0.26 0.028],'String','Reset view', ...
        'Callback',@(s,e) pivui.grain4Shell.resetViewPOT(fig));

    % --- TABEL KANDIDAT HB (tabel kedua; di antara PSG & sesar F#) ---
    h = i_buildHbBlock(h, P, fig);

    % --- BLOK EDIT SESAR F# (DIPERTAHANKAN penuh; DIGESER TURUN dy = -0.166) ---
    h = i_buildFaultEditBlock(h, P, fig, -0.166);

    i_saveBtn(P, fig, 0.04);
end


function h = i_buildHbBlock(h, P, fig)
%I_BUILDHBBLOCK  (GRAIN6) Tabel KANDIDAT HB + tombol. Kurva penyusun garis
%   Hinterland Block: tiap baris = 1 kurva kandidat + batas X0 & X1 (frame).
%   Garis HB gabungan (merge overlap=MAX) tampil sbg overlay hijau di axPOT.
    WHITE = [1 1 1];
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.836 0.92 0.024], ...
        'String','KURVA KANDIDAT HB (1 HB/garis PSG; overlay hijau di axPOT):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    % Baris tombol: Tambah kandidat | Set X0 | Set X1 | Hapus.
    bwHb = 0.223;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.802 bwHb 0.030],'String','➕ Kandidat', ...
        'FontWeight','bold','ForegroundColor',[0 0.45 0], ...
        'TooltipString','Kurva terpilih (klik di axPOT) jadi kandidat penyusun garis HB.', ...
        'Callback',@(s,e) i_onHbAddCandidate(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+(bwHb+0.008) 0.802 bwHb 0.030],'String','Set X0', ...
        'FontWeight','bold','ForegroundColor',[0.10 0.35 0.10], ...
        'TooltipString','Batas AWAL kandidat terpilih = frame aktif (snap ke kurva). X0 kurva pertama = awal garis HB.', ...
        'Callback',@(s,e) i_onHbSetX(fig,'x0'));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+2*(bwHb+0.008) 0.802 bwHb 0.030],'String','Set X1', ...
        'FontWeight','bold','ForegroundColor',[0.10 0.35 0.10], ...
        'TooltipString','Batas AKHIR kandidat terpilih = frame aktif (snap ke kurva).', ...
        'Callback',@(s,e) i_onHbSetX(fig,'x1'));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+3*(bwHb+0.008) 0.802 bwHb 0.030],'String','🗑 Hapus', ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus kandidat HB terpilih.', ...
        'Callback',@(s,e) i_onHbRemove(fig));
    % Tabel kandidat: # | posPx | X0 | X1.
    h.tblHb = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.04 0.664 0.92 0.134], ...
        'ColumnName',{'#','posPx','X0','X1'}, ...
        'ColumnWidth',{34 90 70 70}, ...
        'ColumnEditable',false(1,4),'RowName',[],'FontSize',8, ...
        'CellSelectionCallback',@(s,e) i_onPickHbRow(fig, e));
    h.txtHbSel = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.640 0.58 0.020],'String','kandidat HB terpilih: —', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.10 0.35 0.10]);
    h.chkHbOverlay = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.63 0.638 0.33 0.022],'String','Tampilkan garis HB','Value',1, ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Overlay garis HB gabungan (hijau) di axPOT.', ...
        'Callback',@(s,e) i_onToggleHbOverlay(fig));
end


function h = i_buildFaultEditBlock(h, P, fig, dy)
%I_BUILDFAULTEDITBLOCK  (Fase 4b) Kontrol EDIT sesar di TAB ① Label HW: tabel
%   sesar (h.tblFault) + ➕Sesar/＋SubFault/🗑Hapus + ⬆HW/⬇FW + 4 tombol POI +
%   Hapus titik/clean plot/Hapus kurva/regen. String tombol & tag DIPERTAHANKAN
%   PERSIS. Callback tak berubah — hanya Parent & Position. Tema TERANG.
%   ARG dy (GRAIN6): geser SELURUH blok turun (dy<0) memberi ruang tabel HB di
%   atas; default 0 (identik GRAIN5). Semua koordinat Y dilewatkan helper Y().
%   TABEL SESAR dikecilkan (0.330->0.196) supaya blok muat sesudah tabel HB.
    if nargin < 4 || isempty(dy), dy = 0; end
    Y = @(v) v + dy;   % geser vertikal seragam
    WHITE = [1 1 1];
    % Judul + tombol +F/Sort/Edit/Hapus. (Model "slot spreadsheet": sesar LAHIR
    % dari ISIAN tabel (ketik F#=angka), bukan tombol. SF DINONAKTIFKAN sementara:
    % sesar bernomor 1,2,3,...; kolom SF read-only. Ditiru dari GRAIN5_temp.)
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 Y(0.752) 0.92 0.024],'String','SESAR (ketik F# = angka; klik → aktif; "Edit" utk tukar-nukar nomor):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',9);
    % Baris tombol sesar: 4 kolom (+F | ⇅ Sort | ✎ Edit no. | 🗑 Hapus).
    bwF = 0.166;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 Y(0.718) bwF 0.032],'String','+F', ...
        'FontWeight','bold','ForegroundColor',[0 0.45 0], ...
        'TooltipString','Tambah 1 BARIS slot kosong (hanya bila butuh > 15 baris). Ketik F# di baris untuk membuat sesar.', ...
        'Callback',@(s,e) i_onFaultAddSlot(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+(bwF+0.006) Y(0.718) bwF 0.032],'String','⇅ Sort', ...
        'FontWeight','bold','ForegroundColor',[0.20 0.30 0.60], ...
        'TooltipString','Susun ulang baris berdasarkan NOMOR sesar (menaik). Duplikat -> bersebelahan (urut stabil).', ...
        'Callback',@(s,e) i_onFaultSort(fig));
    h.btnFaultEdit = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04+2*(bwF+0.006) Y(0.718) bwF 0.032],'String','✎ Edit no.','Value',0, ...
        'FontWeight','bold','ForegroundColor',[0.20 0.30 0.60], ...
        'TooltipString',['Buka KUNCI penomoran: boleh tulis nomor apa pun TERMASUK DUPLIKAT ' ...
        '(2 baris nomor sama). Klik lagi = kunci + otomatis urutkan by nomor.'], ...
        'Callback',@(s,e) i_onFaultEditToggle(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+3*(bwF+0.006) Y(0.718) bwF 0.032],'String','🗑 Hapus', ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Hapus baris sesar aktif (terpilih). Atau kosongkan sel F# untuk menghapus baris.', ...
        'Callback',@(s,e) i_onFaultRemove(fig));
    % TABEL SESAR — model "slot spreadsheet": 15 baris slot default. Kolom F# (2)
    % EDITABLE = NOMOR sesar (angka). Kolom SF (3) READ-ONLY (SF nonaktif sementara).
    % Kolom "✓" (paling kiri) = indikator kelengkapan POI (START/NUC/FSR/END).
    % Dikecilkan (0.330 -> 0.196) supaya blok F# muat setelah tabel HB.
    edCol = false(1,11); edCol(2) = true;                    % hanya F# editable (SF nonaktif)
    h.tblFault = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.04 Y(0.518) 0.92 0.196], ...
        'ColumnName',{'✓','F#','SF','HW','FW','NUC','FSR','ST','EN','luas','Sudut'}, ...
        'ColumnWidth',{22 30 26 34 34 30 30 34 34 44 40}, ...
        'ColumnEditable',edCol,'RowName',[],'FontSize',8, ...
        'CellEditCallback',@(s,e) i_onFaultCellEdit(fig, e), ...
        'CellSelectionCallback',@(s,e) i_onPickFaultRow(fig, e));

    % --- Assign HW/FW dari kurva terpilih ---
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 Y(0.484) 0.45 0.030],'String','⬆ Jadikan HW', ...
        'FontWeight','bold','ForegroundColor',[0.75 0.10 0.10], ...
        'TooltipString','Kurva terpilih (klik di axPOT) jadi HANGING WALL sesar/SF aktif.', ...
        'Callback',@(s,e) i_onFaultAssign(fig,'hw'));
    h.btnFaultFW = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 Y(0.484) 0.45 0.030],'String','⬇ Jadikan FW', ...
        'FontWeight','bold','ForegroundColor',[0.10 0.20 0.75], ...
        'TooltipString','Kurva terpilih jadi FOOTWALL sesar aktif. (SF: FW tak berlaku.)', ...
        'Callback',@(s,e) i_onFaultAssign(fig,'fw'));
    h.txtFaultSel = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 Y(0.458) 0.92 0.020],'String','kurva terpilih: —', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.15 0.30 0.55]);

    % --- Titik perkembangan sesar (+ hotkey Ctrl+1..4) + spinner geser S/E ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 Y(0.430) 0.42 0.022],'String','Titik POI (scrub lalu tekan / Ctrl+1..4):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',8);
    % Tombol loncat ke frame POI (siklik START→NUC→FSR→END) F# terseleksi.
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.455 Y(0.428) 0.145 0.026],'String','⤓ Loncat POI', ...
        'FontSize',8,'ForegroundColor',[0.10 0.25 0.55], ...
        'TooltipString',['Loncat frame aktif ke titik POI BERIKUTNYA yang sudah ada pada F# terseleksi ' ...
        '(siklik START→NUC→FSR→END).'], ...
        'Callback',@(s,e) i_onJumpPoi(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.60 Y(0.430) 0.06 0.020],'String','S:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, 0.665, Y(0.430), @() i_onNudgePoint(fig,'start',+1), @() i_onNudgePoint(fig,'start',-1), 'spNudgeS');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.79 Y(0.430) 0.06 0.020],'String','E:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    i_spinBtns(P, fig, 0.855, Y(0.430), @() i_onNudgePoint(fig,'end',+1), @() i_onNudgePoint(fig,'end',-1), 'spNudgeE');
    Lp = {'START','NUC','FSR','END'}; wKind = {'start','nuc','fsr','end'}; bw = 0.227;
    % Hotkey per-KIND (urutan diminta user): START=Ctrl+1 · END=Ctrl+2 · NUC=Ctrl+3 · FSR=Ctrl+4.
    Hk = {'Ctrl+1','Ctrl+3','Ctrl+4','Ctrl+2'};   % paralel Lp: START,NUC,FSR,END
    for i = 1:4
        uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
            'Position',[0.04+(i-1)*(bw+0.01) Y(0.396) bw 0.030],'String',Lp{i}, ...
            'TooltipString',sprintf('Tandai %s = frame aktif (snap ke kurva HW sesar aktif). Hotkey: %s.', Lp{i}, Hk{i}), ...
            'Callback',@(s,e) i_onFaultSetPoint(fig, wKind{i}));
    end
    % Baris: Hapus titik sesar + Clean plot + Hapus kurva + Regenerate.
    bw4 = 0.223;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 Y(0.362) bw4 0.030],'String','Hapus titik', ...
        'TooltipString','Hapus titik POI (START/NUC/FSR/END) sesar aktif.', ...
        'Callback',@(s,e) i_onFaultClearPoints(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+(bw4+0.008) Y(0.362) bw4 0.030],'String','clean plot', ...
        'TooltipString','Trim kurva terpilih -> max indenter (buang ekor pasca-sentuh; non-destruktif).', ...
        'Callback',@(s,e) pivui.grain4Shell.trimSelectedToIndenter(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+2*(bw4+0.008) Y(0.362) bw4 0.030],'String','Hapus kurva', ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Buang kurva terpilih dari plot (non-destruktif; sama spt Tab ② Label).', ...
        'Callback',@(s,e) pivui.grain4Shell.deleteSelectedCurves(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04+3*(bw4+0.008) Y(0.362) bw4 0.030],'String','regen', ...
        'TooltipString','Reset plot kurva ke semula: pulihkan semua trim & kurva yang dibuang.', ...
        'Callback',@(s,e) i_onFaultRegen(fig));

    % --- Pengukur SUDUT sesar (dipindah dari Tab ②): 2 tombol ON/OFF ---
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 Y(0.330) 0.92 0.020],'String','Sudut sesar (relatif bidang detachment):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE,'FontSize',8);
    h.btnDetach = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 Y(0.298) 0.45 0.030],'String','Set bidang detachment','Value',0, ...
        'TooltipString',['ON: tampil garis detachment HORIZONTAL draggable di axMain (atur posisi). ' ...
        'Klik lagi (OFF): kunci & simpan sbg bidang 0° referensi sudut.'], ...
        'Callback',@(s,e) i_onToggleDetach(fig));
    h.btnMeasAngle = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.51 Y(0.298) 0.45 0.030],'String','Hitung sudut sesar','Value',0, ...
        'FontWeight','bold','ForegroundColor',[0.10 0.20 0.55], ...
        'TooltipString',['ON: tampil garis SESAR miring draggable di axMain; sudut ter-update LIVE di label ' ...
        'saat digeser. Klik lagi (OFF): kunci & simpan sudut ke kolom Sudut sesar aktif.'], ...
        'Callback',@(s,e) i_onToggleMeasAngle(fig));
    h.txtFaultAngle = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 Y(0.274) 0.92 0.020],'String','sudut sesar aktif: — °', ...
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
        if isstruct(h.hbdoc) && isfield(h.hbdoc,'psgHb') && ~isempty(h.hbdoc.psgHb)
            pivcore.io.grain6Hb.write(h.df, i_captureHb(h));
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
    h.activeFaultId = '';
    if isfield(h.fdoc,'faults') && ~isempty(h.fdoc.faults), h.activeFaultId = h.fdoc.faults{1}.id; end
    % --- Model HB GRAIN6 (sidecar terpisah _hb.json) ---
    h.hbdoc = pivcore.io.grain6Hb.read(h.df);
    h.hbSelPos = NaN; h.hbIds = {};
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
    i_refreshHbTable(fig);           % tabel kandidat HB garis PSG aktif (GRAIN6)
    i_renderHbOverlay(fig);          % overlay garis HB hijau
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
end

function i_onLineChanged(fig)
    i_clearGhostLine(fig);            % garis digeser/fokus pindah -> bayangan hilang
    h = guidata(fig);
    newId = pivcore.pot.psgId.fromLine(h.line);
    psgSwitched = ~strcmp(newId, h.activePsgId);
    if psgSwitched
        h.pts = pivcore.pot.snapPoints.emptyPts(); h.activeHW = NaN;
        h.hbSelPos = NaN;             % kandidat HB unik per garis PSG
    end
    h.activePsgId = newId;
    guidata(fig, h);
    i_refreshLines(fig); i_drawAnnotForActive(fig);
    i_refreshContext(fig);
    if psgSwitched                    % tabel HB & overlay ikut garis PSG aktif
        i_refreshHbTable(fig); i_renderHbOverlay(fig);
    end
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
                sprintf('kurva terpilih: #%d  posPx=%s  → Jadikan HW/FW atau ➕ Kandidat HB', r, pivui.grain5Fmt.numDash(pp)));
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

function i_onFrameChanged(fig), i_refreshContext(fig); i_refreshPoi(fig); end
function i_afterRenderMain(fig), i_drawAnnotForActive(fig); i_drawFaultPsgMarker(fig); end

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

function i_psgDot(ax, h, row, col, label)
%I_PSGDOT  Satu titik marker (origin record) di axMain + label kecil.
    if isempty(row) || row < 1 || row > numel(h.recs), return; end
    o = h.recs(row).origin;
    if numel(o)~=2 || ~all(isfinite(o)), return; end
    plot(ax, o(1), o(2), 'o', 'MarkerSize',7, 'LineWidth',1.4, ...
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
%I_DECORATEPOT  GRAIN6: dekorasi axPOT. Tab ① Sesar -> HW/FW + titik POI sesar
%   (i_decorateFaultPOT). Selalu + OVERLAY garis HB (hijau; GRAIN6 map-view) di
%   atas semua kurva, sejajar garis hitam max-indenter.
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax) || isempty(h.recs), return; end
    if i_faultVisible(h)               % Tab ① (F# Anlz) & ② (F# Dip) -> HW/FW + titik sesar
        i_decorateFaultPOT(fig);
        i_renderHbOverlay(fig);        % garis HB hijau paling atas (setelah sesar)
        return;
    end
    try, delete(findall(ax,'Tag','nsPoint')); catch, end
    i_renderHbOverlay(fig);
end


% =====================================================================
% KURVA HB (Hinterland Block) — GRAIN6 map-view. 1 HB per garis PSG; dibangun dari
% beberapa kurva KANDIDAT (posPx + batas X0/X1), digabung (overlap=MAX) jadi 1
% garis; overlay hijau di axPOT. Sidecar `<base>_hb.json` (engine grain6Hb).
% =====================================================================

function blk = i_activeHbBlock(h)
%I_ACTIVEHBBLOCK  Blok HB garis PSG aktif dari h.hbdoc; buat KOSONG bila belum ada.
    if ~isstruct(h.hbdoc), h.hbdoc = pivcore.io.grain6Hb.emptyDoc(h.df); end
    [blk, idx] = pivcore.io.grain6Hb.findBlock(h.hbdoc, h.activePsgId);
    if idx < 1, blk = pivcore.io.grain6Hb.hbBlockStruct(h.activePsgId); end
end

function i_onHbAddCandidate(fig)
%I_ONHBADDCANDIDATE  Kurva terpilih (klik axPOT) jadi kandidat HB garis PSG aktif.
    h = guidata(fig);
    if isempty(h.activePsgId)
        pivui.setStatus(fig,'Aktifkan garis PSG dulu sebelum menandai kandidat HB.'); return;
    end
    r = i_selCurveRow(h);
    if isempty(r)
        pivui.setStatus(fig,'Klik satu kurva di axPOT dulu, baru "➕ Kandidat".'); return;
    end
    posPx = NaN;
    if isfield(h.recs(r),'posPx') && isscalar(h.recs(r).posPx), posPx = h.recs(r).posPx; end
    if ~isfinite(posPx), pivui.setStatus(fig,'Kurva terpilih tak punya posPx valid.'); return; end
    blk = i_activeHbBlock(h);
    % Cegah duplikat posPx (toleransi kecil).
    for k = 1:numel(blk.candidates)
        c = blk.candidates{k};
        if isstruct(c) && isfield(c,'posPx') && abs(c.posPx - posPx) < 1e-6
            h.hbSelPos = posPx; guidata(fig, h);
            i_refreshHbTable(fig);
            pivui.setStatus(fig, sprintf('Kurva posPx=%.0f sudah jadi kandidat HB.', posPx)); return;
        end
    end
    blk.candidates{end+1} = pivcore.io.grain6Hb.candStruct(posPx, NaN, NaN);
    h.hbdoc = pivcore.io.grain6Hb.upsertBlock(h.hbdoc, blk);
    h.hbSelPos = posPx; guidata(fig, h);
    i_refreshHbTable(fig); i_renderHbOverlay(fig);
    pivui.setStatus(fig, sprintf('Kandidat HB ditambah: kurva #%d posPx=%.0f (set X0/X1).', r, posPx));
end

function i_onHbSetX(fig, which)
%I_ONHBSETX  Batas X0/X1 kandidat HB terpilih = frame aktif (snap ke kurva itu).
%   which = 'x0' | 'x1'. X0 kurva PERTAMA = awal garis HB.
    h = guidata(fig);
    if ~isfinite(h.hbSelPos)
        pivui.setStatus(fig,'Pilih baris kandidat HB dulu (klik tabel).'); return;
    end
    blk = i_activeHbBlock(h);
    [ci, cand] = i_hbFindCand(blk, h.hbSelPos);
    if ci < 1, pivui.setStatus(fig,'Kandidat HB terpilih tak ditemukan.'); return; end
    nF = h.nF; k = max(1, min(pivcore.util.scalarOr(h.frame,1), max(nF,1)));
    row = pivui.grain5Model.rowForPos(h, h.hbSelPos);
    fsnap = k;
    if ~isempty(row)
        [~, y] = pivcore.pot.records.curveXY(h.recs(row), nF);
        y = pivui.grain4Shell.applyTrimYV(h.recs(row), y);
        fsnap = pivcore.pot.snapPoints.snapFrame(y, k);
    end
    if ~isfinite(fsnap), fsnap = k; end
    switch lower(char(which))
        case 'x0', cand.x0 = fsnap;
        case 'x1', cand.x1 = fsnap;
    end
    blk.candidates{ci} = cand;
    h.hbdoc = pivcore.io.grain6Hb.upsertBlock(h.hbdoc, blk); guidata(fig, h);
    i_refreshHbTable(fig); i_renderHbOverlay(fig);
    pivui.setStatus(fig, sprintf('Kandidat posPx=%.0f: %s = frame %d.', h.hbSelPos, upper(which), round(fsnap)));
end

function i_onHbRemove(fig)
%I_ONHBREMOVE  Buang kandidat HB terpilih. Bila blok kosong -> removeBlock.
    h = guidata(fig);
    if ~isfinite(h.hbSelPos), pivui.setStatus(fig,'Pilih kandidat HB dulu.'); return; end
    blk = i_activeHbBlock(h);
    [ci, ~] = i_hbFindCand(blk, h.hbSelPos);
    if ci < 1, return; end
    blk.candidates(ci) = [];
    if isempty(blk.candidates)
        h.hbdoc = pivcore.io.grain6Hb.removeBlock(h.hbdoc, h.activePsgId);
    else
        h.hbdoc = pivcore.io.grain6Hb.upsertBlock(h.hbdoc, blk);
    end
    h.hbSelPos = NaN; guidata(fig, h);
    i_refreshHbTable(fig); i_renderHbOverlay(fig);
    pivui.setStatus(fig,'Kandidat HB dihapus.');
end

function i_onPickHbRow(fig, evt)
%I_ONPICKHBROW  Baris tabel HB dipilih -> set h.hbSelPos (posPx paralel h.hbIds).
    h = guidata(fig);
    try, rc = evt.Indices; catch, rc = []; end
    if isempty(rc), return; end
    r = rc(1);
    if r >= 1 && r <= numel(h.hbIds)
        h.hbSelPos = h.hbIds{r}; guidata(fig, h);
        set(h.txtHbSel,'String', sprintf('kandidat HB terpilih: posPx=%.0f', h.hbSelPos));
    end
end

function i_refreshHbTable(fig)
%I_REFRESHHBTABLE  Isi h.tblHb dari blok HB garis PSG aktif: # | posPx | X0 | X1.
    h = guidata(fig);
    if ~isfield(h,'tblHb') || ~ishghandle(h.tblHb), return; end
    blk = i_activeHbBlock(h);
    C = blk.candidates; n = numel(C);
    D = cell(n, 4); ids = cell(1, n);
    for k = 1:n
        c = C{k};
        pp = pivui.grain5Fmt.numDash(pivui.grain5Fmt.gf(c,'posPx'));
        x0 = pivui.grain5Fmt.numDash(pivui.grain5Fmt.gf(c,'x0'));
        x1 = pivui.grain5Fmt.numDash(pivui.grain5Fmt.gf(c,'x1'));
        D(k,:) = {k, pp, x0, x1};
        ids{k} = pivui.grain5Fmt.gf(c,'posPx');
    end
    h.hbIds = ids; guidata(fig, h);
    set(h.tblHb, 'Data', D);
end

function i_onToggleHbOverlay(fig)
    h = guidata(fig);
    h.showHbOverlay = get(h.chkHbOverlay,'Value')==1; guidata(fig, h);
    i_renderHbOverlay(fig);
end

function cands = i_hbCandsFromBlock(h, blk)
%I_HBCANDSFROMBLOCK  Ubah kandidat blok -> struct array {values,x0,x1} utk merge.
%   values = deret TAMPIL kurva (trim + moving-avg), sesuai axPOT.
    cands = struct('values',{}, 'x0',{}, 'x1',{});
    for k = 1:numel(blk.candidates)
        c = blk.candidates{k};
        row = pivui.grain5Model.rowForPos(h, pivui.grain5Fmt.gf(c,'posPx'));
        if isempty(row), continue; end     % kurva kandidat hilang di garis PSG ini
        y = i_rowDispY(h, row);
        cands(end+1) = struct('values', y, ...
            'x0', pivui.grain5Fmt.gf(c,'x0'), 'x1', pivui.grain5Fmt.gf(c,'x1')); %#ok<AGROW>
    end
end

function i_renderHbOverlay(fig)
%I_RENDERHBOVERLAY  Gambar garis HB gabungan (hijau tebal) di axPOT. Merge
%   overlap = MAX; mulai di X0 kurva pertama (tanpa ekor). Indenter hitam tetap
%   paling atas.
    h = guidata(fig); ax = h.axPOT;
    if ~ishghandle(ax), return; end
    try, delete(findall(ax,'Tag','hbLineTop')); catch, end
    if ~isfield(h,'showHbOverlay') || ~h.showHbOverlay, return; end
    if isempty(h.activePsgId) || isempty(h.recs), return; end
    if isfield(h,'potView') && strcmp(h.potView,'slip'), return; end   % slip view: skip
    blk = i_activeHbBlock(h);
    if isempty(blk.candidates), return; end
    cands = i_hbCandsFromBlock(h, blk);
    if isempty(cands), return; end
    [hb, ~] = pivcore.pot.hbMerge.merge(cands, h.nF);
    xe = 1:numel(hb); g = isfinite(hb);
    if ~any(g), return; end
    hs = ishold(ax); hold(ax,'on');
    plot(ax, xe(g), hb(g), '-', 'Color',[0 0.60 0], 'LineWidth',3, ...
        'Tag','hbLineTop','HitTest','off','PickableParts','none');
    if ~hs, hold(ax,'off'); end
    i_raiseIndenter(fig);   % indenter max hitam tetap di lapis paling atas
end

function [ci, cand] = i_hbFindCand(blk, posPx)
%I_HBFINDCAND  Cari kandidat ber-posPx di blok. ci=0 & cand=[] bila tak ada.
    ci = 0; cand = [];
    for k = 1:numel(blk.candidates)
        c = blk.candidates{k};
        if isstruct(c) && isfield(c,'posPx') && abs(c.posPx - posPx) < 1e-6
            ci = k; cand = c; return;
        end
    end
end

function doc = i_captureHb(h)
%I_CAPTUREHB  Segarkan cache (merged/startX/values) blok HB garis PSG aktif lalu
%   kembalikan h.hbdoc siap tulis. Model murni (posPx/x0/x1) tak diubah.
    doc = h.hbdoc;
    if ~isstruct(doc), doc = pivcore.io.grain6Hb.emptyDoc(h.df); end
    % Sinkron meta.
    doc.meta.frames = max([h.nF, h.imgFrames, 1]);
    [~, base, ext] = fileparts(h.df); doc.source = [base ext]; doc.meta.basename = base;
    if isempty(h.activePsgId), return; end
    [blk, idx] = pivcore.io.grain6Hb.findBlock(doc, h.activePsgId);
    if idx < 1, return; end
    % Cache deret tiap kandidat + garis HB gabungan (kanal Claude).
    for k = 1:numel(blk.candidates)
        c = blk.candidates{k};
        row = pivui.grain5Model.rowForPos(h, pivui.grain5Fmt.gf(c,'posPx'));
        if ~isempty(row), c.values = i_rowDispY(h, row); else, c.values = []; end
        blk.candidates{k} = c;
    end
    cands = i_hbCandsFromBlock(h, blk);
    if ~isempty(cands)
        [hb, sx] = pivcore.pot.hbMerge.merge(cands, h.nF);
        blk.merged = hb; blk.startX = sx;
    else
        blk.merged = []; blk.startX = NaN;
    end
    doc = pivcore.io.grain6Hb.upsertBlock(doc, blk);
end

function h = i_hbLoadForActivePsg(fig)
%I_HBLOADFORACTIVEPSG  Segarkan tabel HB + overlay untuk garis PSG aktif (dipanggil
%   saat exp dimuat / garis diaktifkan). Kandidat unik per psgId.
    i_refreshHbTable(fig);
    i_renderHbOverlay(fig);
    h = guidata(fig);
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
    frac = NaN; if isfield(ln,'frac'), frac = ln.frac; end
    h.line = struct('p1',ln.p1(:).', 'p2',ln.p2(:).', 'frac',frac);
    h.activePsgId = id; h.psgLocked = true;
    % PENTING: buang ROI lama dulu — kalau tidak, renderMain membaca posisi ROI
    % LAMA (currentLine) dan menimpa h.line yang baru -> garis tak pindah.
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi = [];
    if isfield(h,'btnLock') && ishghandle(h.btnLock), set(h.btnLock,'Value',1,'String','🔒 Terkunci'); end
    guidata(fig, h);
    h.hbSelPos = NaN;                        % kandidat HB unik per garis PSG
    guidata(fig, h);
    pivui.grain4Shell.renderMain(fig);
    pivui.grain4Shell.collectPOT(fig);        % sampel di garis tersimpan
    h = guidata(fig);
    % Restore per-PSG: SELALU pulihkan cutFrame/excluded (walau tak ada label HW —
    % kasus map-view GRAIN6). POI net-slip hanya bila garis ber-label. Selaras dgn
    % i_onPotChanged (gate label OR cuts).
    if i_lineHasLabels(ln) || i_lineHasCuts(ln)
        h.recs = i_applyDocLabels(h.recs, ln);
        h.recs = pivcore.pot.records.applyColors(h.recs);
        if i_lineHasLabels(ln), h.pts = i_ptsFromNetslip(ln); end
        guidata(fig, h);
    end
    pivui.grain4Shell.renderPOT(fig);
    i_refreshContext(fig); i_refreshLines(fig); i_refreshAssignTable(fig);
    i_refreshPoi(fig);
    i_refreshHbTable(fig); i_renderHbOverlay(fig);   % kandidat HB garis PSG ini
    pivui.setStatus(fig, sprintf('Garis "%s" diaktifkan (tersampel + seed).', id));
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
    h.doc = pivcore.io.grain4PotData.removeLine(h.doc, id); guidata(fig, h);
    i_refreshLines(fig);
    pivui.setStatus(fig, sprintf('Garis "%s" dihapus.', id));
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
    if ~isstruct(h.hbdoc), h.hbdoc = pivcore.io.grain6Hb.read(h.df); end
    h.hbdoc = i_captureHb(h);          % GRAIN6: cache merge + siap tulis
    guidata(fig, h);
    try
        pivcore.io.grain4PotData.write(h.df, h.doc);
        pivcore.io.grain4Comments.write(h.df, h.cdoc);
        pivcore.io.grain5Faults.write(h.df, h.fdoc);
        pivcore.io.grain6Hb.write(h.df, h.hbdoc);
    catch ME
        pivui.setStatus(fig, sprintf('GAGAL menyimpan: %s', ME.message)); return;
    end
    i_refreshLines(fig);
    nFlt = 0; if isstruct(h.fdoc) && isfield(h.fdoc,'faults'), nFlt = numel(h.fdoc.faults); end
    nHb = 0; blk = i_activeHbBlock(h); if isstruct(blk) && isfield(blk,'candidates'), nHb = numel(blk.candidates); end
    pivui.setStatus(fig, sprintf('💾 Tersimpan: %d sesar, %d kandidat HB, %d garis.', ...
        nFlt, nHb, numel(h.doc.psgLines)));
end

% =====================================================================
% Capture truth + view settings
% =====================================================================
function doc = i_captureActiveLine(h)
    doc = h.doc; if ~isstruct(doc), doc = pivcore.io.grain4PotData.emptyDoc(h.df); end
    % SELARASKAN h.line dgn ROI yang TAMPIL sebelum menangkap -> Save selalu
    % menyimpan garis yang terlihat (cegah desync h.line vs ROI).
    Lcur = pivui.grain4Shell.currentLine(h);
    if ~isempty(Lcur), h.line = Lcur; end
    if isempty(h.line), return; end
    id = pivcore.pot.psgId.fromLine(h.line);
    frac = NaN; if isstruct(h.line)&&isfield(h.line,'frac'), frac = h.line.frac; end
    [ln, idx] = pivcore.io.grain4PotData.findLine(doc, id);
    if idx < 1
        ln = pivcore.io.grain4PotData.lineStruct(id, h.line.p1, h.line.p2, frac, h.spacing);
    else
        ln.p1=h.line.p1; ln.p2=h.line.p2; ln.frac=frac;
        if isfinite(h.spacing), ln.spacingPx = h.spacing; end
    end
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
        if isstruct(h.hbdoc) && isfield(h.hbdoc,'psgHb') && ~isempty(h.hbdoc.psgHb)
            pivcore.io.grain6Hb.write(h.df, i_captureHb(h));   % flush model HB (GRAIN6)
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
