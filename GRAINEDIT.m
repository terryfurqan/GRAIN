function figOut = GRAINEDIT(rootDir, varargin)
%GRAINEDIT  Editor tampilan WYSIWYG untuk PRODUKSI GAMBAR SPESIFIK (Step 4b).
%   Input SAMA dgn GRAIN5 (_faults.json + _potdata.json), tapi FOKUS produksi gambar:
%   satu gambar spesifik per klik — AXPOT kurva POT · Net-slip · atau AX main —
%   dengan kontrol tampilan GRANULAR: tampilkan "semua NUC / FSR / START / END",
%   atau "semua NUC KECUALI F tertentu"; ubah warna & ukuran indikator POI, garis
%   vertikal POI, kurva/fill zona; atur judul, label, min/max CLim.
%
%   KONVENSI TERKUNCI: Sumbu X = cumulative strain % (SELALU) · Sumbu Y = cm/s
%   (px/frame × velMult). AX main POLOS (tanpa tick). Output = 1 gambar (bukan
%   batch). Preset: default global (setpref) + sidecar <base>_pabedit.json per-exp.
%
%   GRAINEDIT READ-ONLY terhadap _faults.json — hanya membaca, tak pernah menulis.
%   FANLZ / assign HW-FW / set POI / ukur sudut = TIDAK ada (itu tugas GRAIN5).
%
%   GRAINEDIT                      % pilih folder ROOT (dialog)
%   GRAINEDIT(rootDir)            % langsung ke folder
%   GRAINEDIT(rootDir, tmpRoot)  % arg-2: override folder induk ekspor (TES)
%
%   Jalankan `grain_setup` sekali per sesi. SELALU MATLAB R2025b.

    figOut = [];
    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivui.grain4Shell'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end
    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, 'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end
    exportRootOverride = '';   % arg-2 opsional = folder induk ekspor (TES)
    if ~isempty(varargin) && ~isempty(varargin{1}) && (ischar(varargin{1}) || isstring(varargin{1}))
        exportRootOverride = char(varargin{1});
    end

    opts = struct();
    opts.Name = 'GRAIN Editor — Produksi Gambar Spesifik (AXPOT / Net-slip / AX main)';
    opts.rightTitle = 'GRAIN Editor (Step 4b)';
    opts.hooks = struct('beforeLoad', @i_beforeLoad, 'onExpLoaded', @i_onExpLoaded);

    h = pivui.grain4Shell.build(opts);

    % --- State GRAINEDIT ---
    h.df = ''; h.doc = []; h.fdoc = []; h.signConv = 'signed';
    h.strainTotalPct = NaN; h.cmPerPx = NaN;
    h.exportRootOverride = exportRootOverride;
    h.lastExportMsg = '';
    % (Penyembunyian chrome shell dilakukan SETELAH i_buildUI via
    %  i_hideShellChrome — handle GRAINEDIT harus ada dulu untuk di-whitelist.)
    % MATIKAN auto-load exp pertama: user pilih manual.
    h.noAutoLoadExp = true;
    % Kolom EXTRA tabel exp kiri (jumlah F# teridentifikasi / checklist).
    h.expTableExtra = @(df) i_expFaultCounts(df);

    % Setelan tampilan (opts) — prioritas: default -> global pref.
    h.o = pivcore.io.grainEditProject.defaultOpts();
    h.o = i_loadGlobalPref(h.o);

    guidata(h.fig, h);
    h = i_buildUI(h);
    i_hideShellChrome(h);          % sembunyikan elemen shell yg tak dipakai GRAINEDIT
    guidata(h.fig, h);
    set(h.fig, 'CloseRequestFcn', @(s,e) delete(s));
    pivui.grain4Shell.setRoot(h.fig, rootDir);
    i_applyOptsToControls(h.fig);
    if ~pivui.quiet()
        % Tampilkan window (shell build bisa mewarisi Visible='off'; GRAINEDIT WAJIB
        % memaksa 'on' saat mode interaktif — kalau tidak window tak muncul).
        try, set(h.fig, 'Visible', 'on'); catch, end
        try, set(h.fig, 'WindowState', 'maximized'); catch, end
        try, figure(h.fig); catch, end   % bawa ke depan
    end
    if nargout > 0, figOut = h.fig; end
end


% =====================================================================
% BUILD UI (3 kolom, light-theme; kanvas cm-fisik di tengah, kontrol kanan)
% =====================================================================
function h = i_buildUI(h)
    fig = h.fig;
    try, pivui.forceLightTheme(fig); catch, end
    try, set(fig,'Name', pivui.titleWithVersion('GRAIN Editor')); catch, end

    % Panel kanan bawaan shell dipakai untuk kontrol GRAINEDIT — kosongkan isinya.
    if isfield(h,'pnlR') && ishghandle(h.pnlR)
        delete(allchild(h.pnlR));
        P = h.pnlR;
    else
        P = uipanel('Parent',fig,'Units','normalized','Position',[0.66 0.01 0.33 0.98], ...
            'BackgroundColor',[0.96 0.96 0.96]);
        h.pnlR = P;
    end
    set(P,'Title','Kontrol tampilan','BackgroundColor',[0.96 0.96 0.96]);

    % Panel KIRI shell (tabel exp) = induk h.tbl — WAJIB dipertahankan.
    h.pnlL = [];
    try, if isfield(h,'tbl') && ishghandle(h.tbl), h.pnlL = ancestor(h.tbl,'uipanel'); end, catch, end

    % --- KANVAS (tengah): panel + axes cm (perlebar isi ruang bekas axMain/axPOT).
    %     Bawah kanvas disisakan utk strip mode + masking + status (tak bertumpuk). ---
    h.pnlCanvas = uipanel('Parent',fig,'Units','normalized','Position',[0.185 0.190 0.475 0.790], ...
        'BackgroundColor',[1 1 1],'BorderType','line','HighlightColor',[0.8 0.8 0.8]);
    h.ax = axes('Parent',h.pnlCanvas,'Units','normalized','Position',[0.12 0.12 0.84 0.82]);

    % --- strip bawah kanvas: mode + slider frame ---
    yb = 0.03;
    h.btnModePot = uicontrol(fig,'Style','togglebutton','Units','normalized', ...
        'Position',[0.185 yb 0.075 0.05],'String','AXPOT','Value',1, ...
        'Callback',@(s,e) i_onSetMode(fig,'pot'));
    h.btnModeNs = uicontrol(fig,'Style','togglebutton','Units','normalized', ...
        'Position',[0.262 yb 0.075 0.05],'String','Net-slip', ...
        'Callback',@(s,e) i_onSetMode(fig,'netslip'));
    h.btnModeMain = uicontrol(fig,'Style','togglebutton','Units','normalized', ...
        'Position',[0.339 yb 0.075 0.05],'String','AX main', ...
        'Callback',@(s,e) i_onSetMode(fig,'main'));
    h.sldFrame = uicontrol(fig,'Style','slider','Units','normalized', ...
        'Position',[0.420 yb 0.11 0.05],'Min',1,'Max',2,'Value',1, ...
        'Callback',@(s,e) i_onFrameSlider(fig));
    h.txtFrame = uicontrol(fig,'Style','text','Units','normalized', ...
        'Position',[0.533 yb 0.05 0.045],'String','f1','BackgroundColor',[1 1 1]);

    % --- MASKING: 4 tombol (gambar kotak/poligon PUTIH borderless; hapus semua) ---
    ym = yb + 0.055;
    h.txtMaskLbl = uicontrol(fig,'Style','text','Units','normalized','Position',[0.185 ym 0.05 0.04], ...
        'String','Masking:','HorizontalAlignment','left','BackgroundColor',get(fig,'Color'));
    h.btnMaskRect = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.240 ym 0.078 0.045],'String','▭ Kotak','Callback',@(s,e) i_onDrawMask(fig,'rect'));
    h.btnMaskPoly = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.320 ym 0.078 0.045],'String','⬡ Poligon','Callback',@(s,e) i_onDrawMask(fig,'poly'));
    h.btnMaskDelRect = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.400 ym 0.088 0.045],'String','🗑 Kotak','Callback',@(s,e) i_onClearMask(fig,'rect'));
    h.btnMaskDelPoly = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.490 ym 0.088 0.045],'String','🗑 Poligon','Callback',@(s,e) i_onClearMask(fig,'poly'));

    % --- KONTROL KANAN: tab-group untuk kerapian ---
    tg = uitabgroup('Parent',P,'Units','normalized','Position',[0.01 0.10 0.98 0.89]);
    h.tabGlobal = uitab(tg,'Title','⓪ Umum');
    h.tabPoi    = uitab(tg,'Title','① POI');
    h.tabFault  = uitab(tg,'Title','② Sesar');
    h.tabMain   = uitab(tg,'Title','③ AX main');
    h = i_buildGlobalTab(h, h.tabGlobal);
    h = i_buildPoiTab(h, h.tabPoi);
    h = i_buildFaultTab(h, h.tabFault);
    h = i_buildMainTab(h, h.tabMain);

    % --- EXPORT DI AKHIR (menonjol, hijau) ---
    h.btnExport = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.012 0.22 0.075],'String','📤 Export gambar ini', ...
        'FontWeight','bold','BackgroundColor',[0.82 0.92 0.82], ...
        'Callback',@(s,e) i_onExport(fig));
    h.btnOpenFolder = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.885 0.012 0.075 0.075],'String','📂', ...
        'Callback',@(s,e) i_onOpenFolder(fig));
    % Status GRAINEDIT — nama field UNIK (h.txtStatus dipakai shell; jangan bentrok).
    % Ditaruh DI ANTARA kanvas & baris masking (y≈0.155) supaya tak bertumpuk.
    h.edStatus = uicontrol(fig,'Style','text','Units','normalized', ...
        'Position',[0.185 0.155 0.475 0.022],'String','Pilih eksperimen di kiri…', ...
        'HorizontalAlignment','left','BackgroundColor',get(fig,'Color'));

    % Kumpulkan handle milik GRAINEDIT (untuk whitelist i_hideShellChrome).
    h.myHandles = [h.pnlCanvas, h.ax, h.btnModePot, h.btnModeNs, h.btnModeMain, ...
        h.sldFrame, h.txtFrame, h.txtMaskLbl, h.btnMaskRect, h.btnMaskPoly, ...
        h.btnMaskDelRect, h.btnMaskDelPoly, h.btnExport, h.btnOpenFolder, h.edStatus];
end


% ---------------------------------------------------------------------
function i_hideShellChrome(h)
%I_HIDESHELLCHROME  Sembunyikan SEMUA elemen bawaan grain4Shell yang tak dipakai
%   GRAINEDIT (axMain/axPOT/axAC*/pnlC strip Vel-mag/GS/glyph + uicontrol lepas
%   btnAxView/edSpacing/sldVScale/btnLock/btnDisp/btnLeftMode/txtStatus). GRAINEDIT
%   punya kanvas & kontrol sendiri. Pendekatan WHITELIST: sembunyikan tiap anak-
%   langsung figure yang BUKAN panel kiri (tabel exp), panel kanan (kontrol), atau
%   handle milik GRAINEDIT. Tahan-perubahan (elemen shell baru pun ikut tersembunyi).
    fig = h.fig;
    keep = [];
    if isfield(h,'pnlL') && ~isempty(h.pnlL) && ishghandle(h.pnlL), keep(end+1) = h.pnlL; end
    if isfield(h,'pnlR') && ishghandle(h.pnlR), keep(end+1) = h.pnlR; end
    if isfield(h,'pnlCanvas') && ishghandle(h.pnlCanvas), keep(end+1) = h.pnlCanvas; end
    if isfield(h,'myHandles'), keep = [keep, h.myHandles(ishghandle(h.myHandles))]; end
    kids = allchild(fig);
    for i = 1:numel(kids)
        k = kids(i);
        if ~ishghandle(k), continue; end
        if any(k == keep), continue; end
        % Jangan sentuh menu/toolbar (uimenu/uitoolbar tak punya Visible relevan).
        try
            if isprop(k,'Visible'), set(k, 'Visible', 'off'); end
        catch
        end
    end
    % Tegas sembunyikan axes shell by-handle + ISI-nya (imagesc/plot tetap tampil
    % walau sumbu di-Visible-off; jadi sembunyikan children juga). renderMain shell
    % dipanggil ulang tiap muat exp -> helper ini dipanggil lagi di i_onExpLoaded.
    for fld = {'axMain','axPOT','axACtop','axACbot','cbMain'}
        try
            if isfield(h,fld{1}) && ~isempty(h.(fld{1})) && ishghandle(h.(fld{1}))
                ax = h.(fld{1});
                set(ax,'Visible','off');
                ch = allchild(ax);
                for c = ch(:).'
                    if ishghandle(c) && isprop(c,'Visible'), set(c,'Visible','off'); end
                end
            end
        catch
        end
    end
end


% ---------------------------------------------------------------------
function h = i_buildGlobalTab(h, T)
    y = 0.94; dy = 0.062;
    [h.edTitle, y] = i_lbledit(T, 'Judul (kosong=auto):', h.o.title, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkTitle, y] = i_chk(T, 'Tampilkan judul', h.o.showTitle, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edXlab, y] = i_lbledit(T, 'Label sumbu-X:', h.o.xlabel, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edYlab, y] = i_lbledit(T, 'Label sumbu-Y:', h.o.ylabel, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkXrev, y] = i_chk(T, 'X: 0% di KIRI (balik)', h.o.xReverse, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkGrid, y] = i_chk(T, 'Grid', h.o.showGrid, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edVelMult, y] = i_lbledit(T, 'velMult (cm/s per px/frame):', sprintf('%g',h.o.velMult), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkZoom, y] = i_chk(T, 'Zoom window (frame)', h.o.zoomOn, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edZoomSpan, y] = i_lbledit(T, 'Lebar zoom (frame):', sprintf('%d',h.o.zoomSpan), y, dy, @(s,e) i_onCtrl(h.fig));
    % Ukuran gambar & DPI.
    [h.edW, y] = i_lbledit(T, 'Lebar (cm):', sprintf('%g',h.o.widthCm), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edH, y] = i_lbledit(T, 'Tinggi (cm):', sprintf('%g',h.o.heightCm), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edDpi, y] = i_lbledit(T, 'DPI:', sprintf('%d',h.o.dpi), y, dy, @(s,e) i_onCtrl(h.fig));
    % Simpan default global.
    uicontrol(T,'Style','pushbutton','Units','normalized','Position',[0.05 y-0.005 0.44 0.05], ...
        'String','⭐ Jadikan default','Callback',@(s,e) i_onSaveGlobal(h.fig));
    uicontrol(T,'Style','pushbutton','Units','normalized','Position',[0.51 y-0.005 0.44 0.05], ...
        'String','↺ Reset','Callback',@(s,e) i_onResetGlobal(h.fig));
end


% ---------------------------------------------------------------------
function h = i_buildPoiTab(h, T)
    which = {'start','nuc','fsr','end'}; nm = {'START','NUC','FSR','END'};
    y = 0.95; dy = 0.052;
    h.poiCtrl = struct();
    for i = 1:numel(which)
        w = which{i}; p = h.o.poi.(w);
        % checkbox tampil
        cb = uicontrol(T,'Style','checkbox','Units','normalized','Position',[0.03 y 0.30 0.045], ...
            'String',nm{i},'Value',double(p.show),'FontWeight','bold', ...
            'Callback',@(s,e) i_onCtrl(h.fig));
        % tombol warna
        bc = uicontrol(T,'Style','pushbutton','Units','normalized','Position',[0.35 y 0.13 0.045], ...
            'String','warna','BackgroundColor',i_col(p.color), ...
            'Callback',@(s,e) i_onPoiColor(h.fig, w));
        % spinner ukuran
        [ed,bu,bd] = i_spin(T, 0.50, y, sprintf('%g',p.size), @(st) i_onPoiSize(h.fig,w,st));
        h.poiCtrl.(w) = struct('chk',cb,'btnCol',bc,'edSize',ed,'bUp',bu,'bDn',bd);
        % daftar exclude uiNum
        y = y - dy;
        uicontrol(T,'Style','text','Units','normalized','Position',[0.05 y 0.28 0.04], ...
            'String','  kecuali F#:','HorizontalAlignment','left','BackgroundColor',get(T,'BackgroundColor'));
        exStr = i_list2str(p.exclude);
        edx = uicontrol(T,'Style','edit','Units','normalized','Position',[0.35 y 0.60 0.042], ...
            'String',exStr,'HorizontalAlignment','left','Callback',@(s,e) i_onCtrl(h.fig));
        h.poiCtrl.(w).edExcl = edx;
        y = y - dy - 0.012;
    end
    % garis vertikal POI
    [h.chkVline, y] = i_chk(T, 'Garis vertikal POI', h.o.vline.show, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkVlineTier, y] = i_chk(T, '  label bertingkat', h.o.vline.tiered, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkVlineFrame, ~] = i_chk(T, '  label frame', h.o.vline.labelFrame, y, dy, @(s,e) i_onCtrl(h.fig));
end


% ---------------------------------------------------------------------
function h = i_buildFaultTab(h, T)
    % Tabel F# baca-saja (kolom: F# / HW / FW / tampil-toggle) — diisi saat exp muat.
    h.tblFault = uitable('Parent',T,'Units','normalized','Position',[0.03 0.42 0.94 0.55], ...
        'ColumnName',{'F#','HW','FW','Tampil'}, ...
        'ColumnFormat',{'char','char','char','logical'}, ...
        'ColumnEditable',[false false false true], ...
        'ColumnWidth',{40 60 60 55}, ...
        'CellEditCallback',@(s,e) i_onFaultToggle(h.fig,e), ...
        'RowStriping','on');
    y = 0.37; dy = 0.055;
    [h.edCurveW, y] = i_lbledit(T, 'Tebal kurva:', sprintf('%g',h.o.curveWidth), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edZoneAlpha, y] = i_lbledit(T, 'Alpha zona:', sprintf('%g',h.o.zoneAlpha), y, dy, @(s,e) i_onCtrl(h.fig));
    h.btnHwCol = uicontrol(T,'Style','pushbutton','Units','normalized','Position',[0.05 y 0.28 0.05], ...
        'String','warna HW','BackgroundColor',i_col(h.o.hwColor),'Callback',@(s,e) i_onFaultColor(h.fig,'hwColor'));
    h.btnFwCol = uicontrol(T,'Style','pushbutton','Units','normalized','Position',[0.35 y 0.28 0.05], ...
        'String','warna FW','BackgroundColor',i_col(h.o.fwColor),'Callback',@(s,e) i_onFaultColor(h.fig,'fwColor'));
    h.btnSlipCol = uicontrol(T,'Style','pushbutton','Units','normalized','Position',[0.66 y 0.29 0.05], ...
        'String','warna slip','BackgroundColor',i_col(h.o.slipColor),'Callback',@(s,e) i_onFaultColor(h.fig,'slipColor'));
    y = y - dy;
    [h.chkArea, y] = i_chk(T, 'Arsir luas (net-slip)', h.o.areaShade, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkFaultLabel, y] = i_chk(T, 'Label F# di kurva', h.o.faultLabel, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkClamp, y] = i_chk(T, 'Potong kurva ke START..END', h.o.clampAB, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkShowBg, ~] = i_chk(T, 'Kurva POT latar (konteks)', h.o.showBg, y, dy, @(s,e) i_onCtrl(h.fig));
end


% ---------------------------------------------------------------------
function h = i_buildMainTab(h, T)
    y = 0.94; dy = 0.06;
    h.popScalar = uicontrol(T,'Style','popupmenu','Units','normalized','Position',[0.35 y 0.60 0.05], ...
        'String',{'velmag','shear'},'Value',1+double(strcmp(h.o.scalar,'shear')), ...
        'Callback',@(s,e) i_onCtrl(h.fig));
    uicontrol(T,'Style','text','Units','normalized','Position',[0.05 y 0.28 0.045], ...
        'String','Skalar:','HorizontalAlignment','left','BackgroundColor',get(T,'BackgroundColor'));
    y = y - dy;
    [h.edClimLo, y] = i_lbledit(T, '|V| min:', sprintf('%g',h.o.climVel(1)), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edClimHi, y] = i_lbledit(T, '|V| max:', sprintf('%g',h.o.climVel(2)), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.edShearAbs, y] = i_lbledit(T, '|shear| max:', sprintf('%g',h.o.shearAbs), y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkTickPx, y] = i_chk(T, 'Tampilkan tick (X/Y)', h.o.tickPx, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkColorbar, y] = i_chk(T, 'Colorbar', h.o.showColorbar, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkGS, y] = i_chk(T, 'GS overlay', h.o.gsOn, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkGlyph, y] = i_chk(T, 'Glyph vektor', h.o.glyphOn, y, dy, @(s,e) i_onCtrl(h.fig));
    [h.chkMarkerHW, ~] = i_chk(T, 'Marker HW/FW', h.o.markerHWFW, y, dy, @(s,e) i_onCtrl(h.fig));
end


% =====================================================================
% LIFECYCLE — muat eksperimen (versi RAMPING dari GRAIN5)
% =====================================================================
function i_beforeLoad(fig) %#ok<INUSD>
    % GRAINEDIT read-only: tak perlu flush progres.
end

function i_onExpLoaded(fig)
    h = guidata(fig);
    h.df = h.realData;
    h.doc = pivcore.io.grain4PotData.read(h.df);
    if isfield(h.doc,'signConvention') && any(strcmp(char(h.doc.signConvention),{'signed','absolute'}))
        h.signConv = char(h.doc.signConvention);
    end
    h.fdoc = pivcore.io.grain5Faults.read(h.df);
    if isfield(h.fdoc,'signConvention') && any(strcmp(char(h.fdoc.signConvention),{'signed','absolute'}))
        h.signConv = char(h.fdoc.signConvention);
    end
    h.activeFaultId = '';
    h.pts = pivcore.pot.snapPoints.emptyPts();
    % Kalibrasi strain kumulatif % (untuk sumbu X).
    try
        [h.strainTotalPct, h.cmPerPx] = pivcore.export.frameCatalog.readGeom(h.df);
    catch
        h.strainTotalPct = NaN; h.cmPerPx = NaN;
    end
    guidata(fig, h);
    % Aktifkan garis PSG tersimpan -> sampel POT (mengisi h.recs). Ramping dari
    % i_initLineAndSeed GRAIN5: kita cuma butuh recs + pts, tanpa UI seed.
    i_initRecs(fig);
    h = guidata(fig);
    % Sidecar setelan per-exp menimpa global bila ada.
    try
        sp = pivcore.io.grainEditProject.defaultPath(h.df);
        if isfile(sp)
            h.o = pivcore.io.grainEditProject.load(sp);
            guidata(fig, h);
            i_applyOptsToControls(fig);
            h = guidata(fig);
        end
    catch
    end
    % Slider frame ikut nF.
    if isfield(h,'sldFrame') && ishghandle(h.sldFrame)
        nF = max(2, h.nF);
        set(h.sldFrame,'Min',1,'Max',nF,'Value',min(max(1,h.o.frame),nF), ...
            'SliderStep',[1/(nF-1) max(2/(nF-1),0.1)]);
    end
    i_refreshFaultTable(fig);
    % Shell loadExperiment merender ulang axMain/axPOT (memunculkannya lagi) +
    % kolektor bisa membuat colorbar -> sembunyikan chrome shell LAGI di sini.
    i_hideShellChrome(guidata(fig));
    i_apply(fig);
    i_setStatus(fig, sprintf('Dimuat: %s (%d kurva, %d frame).', i_baseName(h.df), numel(h.recs), h.nF));
end


function i_initRecs(fig)
%I_INITRECS  Aktifkan garis PSG tersimpan (_potdata / _autopot) -> collectPOT
%   mengisi h.recs. Bila tak ada garis, recs kosong (renderer tampilkan pesan).
    h = guidata(fig);
    ok = false;
    if isstruct(h.doc) && isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines)
        L = h.doc.psgLines{1};
        if isfield(L,'p1') && isfield(L,'p2') && all(isfinite([L.p1(:).' L.p2(:).']))
            h.line = struct('p1',L.p1(:).','p2',L.p2(:).','frac',NaN);
            h.psgLocked = true;
            if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
            h.roi = [];
            guidata(fig, h);
            pivui.grain4Shell.collectPOT(fig);
            ok = true;
        end
    end
    if ~ok
        ap = pivcore.io.step1Session.autopotPath(h.df);
        if isfile(ap)
            L = pivcore.io.step1Session.loadLine(h.df);
            if ~isempty(L) && isfield(L,'p1') && all(isfinite([L.p1(:).' L.p2(:).']))
                h.line = struct('p1',L.p1(:).','p2',L.p2(:).','frac',NaN);
                h.psgLocked = true;
                if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
                h.roi = [];
                guidata(fig, h);
                pivui.grain4Shell.collectPOT(fig);
            end
        end
    end
    h = guidata(fig);
    % Fallback: tak ada garis tersimpan -> pakai garis auto-75% dari shell
    % (autoPSG) lalu KUNCI + sampel supaya kurva POT tetap ada (editor produksi
    % butuh kurva). Bila garis auto juga tak ada, recs kosong (pesan di kanvas).
    if (~isfield(h,'recs') || isempty(h.recs)) && isfield(h,'line') && ~isempty(h.line) ...
            && isfield(h.line,'p1') && all(isfinite([h.line.p1(:).' h.line.p2(:).']))
        h.psgLocked = true; guidata(fig, h);
        try, pivui.grain4Shell.collectPOT(fig); catch, end
        h = guidata(fig);
    end
    if ~isfield(h,'recs') || isempty(h.recs), h.recs = []; end
    if ~isfield(h,'nF') || isempty(h.nF) || ~isfinite(h.nF), h.nF = 1; end
    guidata(fig, h);
end


% =====================================================================
% RENDER — i_apply (kanvas) + i_drawEdit (renderer BERSAMA preview=export)
% =====================================================================
function i_apply(fig)
%I_APPLY  Render mode aktif ke kanvas GUI (h.ax). Ukuran fisik cm (pola GRAINAXPOT).
    h = guidata(fig);
    if ~isfield(h,'ax') || ~ishghandle(h.ax), return; end
    o = i_readControls(h);   % UI -> o
    h.o = o; guidata(fig, h);
    % Ukuran kanvas fisik cm (fit-to-panel jaga rasio).
    try
        cm2px = get(0,'ScreenPixelsPerInch')/2.54;
        pos = getpixelposition(h.pnlCanvas);
        availW = max(50,pos(3)-20); availH = max(50,pos(4)-20);
        wpx = o.widthCm*cm2px; hpx = o.heightCm*cm2px;
        s = min([availW/wpx, availH/hpx, 1]);
        set(h.ax,'Units','pixels','Position',[ (pos(3)-wpx*s)/2, (pos(4)-hpx*s)/2, wpx*s, hpx*s]);
    catch
    end
    i_drawEdit(h.ax, h, o);
end


function i_drawEdit(ax, h, o)
%I_DRAWEDIT  Renderer BERSAMA (dipakai preview kanvas & export offscreen). 3 mode:
%   'pot'      — kurva POT HW/FW semua sesar tampil (X strain%, Y cm/s)
%   'netslip'  — net-slip HW−FW semua sesar bertumpuk (arsir luas)
%   'main'     — peta velmag/shear + marker HW/FW (POLOS, CLim min/max)
    cla(ax, 'reset');
    try, pivui.forceLightTheme(ancestor(ax,'figure')); catch, end
    if strcmp(o.mode,'main')
        i_drawMain(ax, h, o); return;
    end
    % --- mode POT / NET-SLIP ---
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top');
    if isempty(h.recs)
        text(ax,0.5,0.5,'Belum ada kurva POT (garis PSG belum tersimpan di exp ini).', ...
            'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
        return;
    end
    nF = h.nF; strainTot = h.strainTotalPct; velMult = o.velMult;
    xOn = isfinite(strainTot);   % strain kalibrasi tersedia?
    hold(ax,'on');
    % Kurva POT latar (spaghetti tipis abu-abu) sbg KONTEKS — hanya mode POT &
    % bila diaktifkan. Sesar/POI digambar DI ATASNYA.
    if strcmp(o.mode,'pot') && o.showBg
        for r = 1:numel(h.recs)
            [xv,yv] = i_curveXYcal(h, r, [], strainTot, velMult, xOn);
            g = isfinite(xv)&isfinite(yv);
            if any(g), plot(ax, xv(g), yv(g), '-','Color',[0.85 0.85 0.85],'LineWidth',0.4, ...
                    'Tag','bgCurve','HitTest','off','PickableParts','none'); end
        end
    end
    F = {}; if isstruct(h.fdoc) && isfield(h.fdoc,'faults'), F = h.fdoc.faults; end
    pastel = pivui.grain5Palette.zonePalette(h);
    ci = 0;
    for k = 1:numel(F)
        f = F{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end      % SF nonaktif
        if ~pivui.grain5Model.faultEnabled(f), continue; end
        if ~i_faultVisible(f, o), continue; end                       % toggle tampil per-F#
        ci = ci + 1;
        if strcmp(o.mode,'pot')
            i_drawFaultPot(ax, h, o, f, nF, strainTot, velMult, xOn);
        else
            i_drawFaultNetslip(ax, h, o, f, nF, strainTot, velMult, xOn, pastel, ci);
        end
    end
    hold(ax,'off');
    % Sumbu & label.
    if o.showGrid, grid(ax,'on'); else, grid(ax,'off'); end
    xlabel(ax, o.xlabel, 'Color',[0 0 0]);
    ylabel(ax, o.ylabel, 'Color',[0 0 0]);
    if xOn && o.xReverse, set(ax,'XDir','reverse'); else, set(ax,'XDir','normal'); end
    i_setTitle(ax, h, o);
    % Zoom window (frame -> strain).
    i_applyZoom(ax, h, o, nF, strainTot, xOn);
end


function i_drawFaultPot(ax, h, o, f, nF, strainTot, velMult, xOn)
%I_DRAWFAULTPOT  Kurva HW/FW 1 sesar (potong ke START..END bila diminta) + POI.
    [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    clampAB = [];
    if o.clampAB && isfinite(f.startF) && isfinite(f.endF), clampAB = [f.startF f.endF]; end
    if okHW
        [xv,yv] = i_curveXYcal(h, hwRow, clampAB, strainTot, velMult, xOn);
        g = isfinite(xv)&isfinite(yv);
        if any(g), plot(ax, xv(g), yv(g), '-','Color',o.hwColor,'LineWidth',o.curveWidth,'Tag','hwCurve'); end
        i_drawPoiSet(ax, h, o, f, hwRow, clampAB, strainTot, velMult, xOn);
    end
    if okFW
        [xv,yv] = i_curveXYcal(h, fwRow, clampAB, strainTot, velMult, xOn);
        g = isfinite(xv)&isfinite(yv);
        if any(g), plot(ax, xv(g), yv(g), '-','Color',o.fwColor,'LineWidth',o.curveWidth,'Tag','fwCurve'); end
        i_drawPoiSet(ax, h, o, f, fwRow, clampAB, strainTot, velMult, xOn);
    end
    if o.faultLabel && okHW
        [xv,yv] = i_curveXYcal(h, hwRow, clampAB, strainTot, velMult, xOn);
        [pv,pi] = max(yv); if isfinite(pv)
            text(ax, xv(pi), pv, sprintf(' F%s',i_uiNumStr(f)),'Color',o.hwColor, ...
                'FontWeight','bold','FontSize',8,'BackgroundColor','w','Margin',1,'Tag','fLabel');
        end
    end
    if o.vline.show, i_drawVlines(ax, h, o, f, strainTot, velMult, xOn); end
end


function i_drawFaultNetslip(ax, h, o, f, nF, strainTot, velMult, xOn, pastel, ci)
%I_DRAWFAULTNETSLIP  Net-slip HW−FW 1 sesar (arsir luas START..END) + POI.
    [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
    if ~(okHW&&okFW) || isempty(ns) || ~any(isfinite(ns)), return; end
    col = o.slipColor;
    if ci>1, col = pastel{mod(ci-1,numel(pastel))+1}; col = 0.7*col; end
    nsC = ns;
    if o.clampAB && isfinite(f.startF)&&isfinite(f.endF)
        nsC = pivui.grain5Fmt.clampRange(ns, [f.startF f.endF]);
    end
    xf = 1:numel(nsC);
    xv = i_xmap(xf, nF, strainTot, xOn);
    yv = nsC*velMult;
    g = isfinite(xv)&isfinite(yv);
    % Arsir luas.
    if o.areaShade && isfinite(f.startF)&&isfinite(f.endF)
        a = max(1,round(min(f.startF,f.endF))); b = min(numel(ns),round(max(f.startF,f.endF)));
        if b>a
            ia = a:b; gg = isfinite(ns(ia)); xa = ia(gg);
            ya = ns(ia); ya = ya(gg)*velMult;
            xax = i_xmap(xa, nF, strainTot, xOn);
            if numel(xax)>=2
                fill(ax,[xax fliplr(xax)],[ya zeros(1,numel(xax))],col, ...
                    'FaceAlpha',o.zoneAlpha,'EdgeColor','none','Tag','slipArea', ...
                    'HitTest','off','PickableParts','none');
            end
        end
    end
    if any(g), plot(ax, xv(g), yv(g), '-','Color',pivui.grain5Fmt.dol(col),'LineWidth',o.curveWidth,'Tag','slipCurve'); end
    % Titik POI di kurva net-slip.
    i_drawPoiOnVec(ax, h, o, f, ns*velMult, nF, strainTot, xOn);
    if o.faultLabel
        [pv,pi] = max(yv); if isfinite(pv)
            text(ax, xv(pi), pv, sprintf(' F%s',i_uiNumStr(f)),'Color',pivui.grain5Fmt.dol(col), ...
                'FontWeight','bold','FontSize',8,'BackgroundColor','w','Margin',1,'Tag','fLabel');
        end
    end
    if o.vline.show, i_drawVlines(ax, h, o, f, strainTot, velMult, xOn); end
end


function i_drawMain(ax, h, o)
%I_DRAWMAIN  Peta velmag/shear frame o.frame + marker HW/FW SEMUA sesar. POLOS
%   (tanpa tick), CLim min/max user, colorbar cm/s (velmag).
    if isempty(h.data)
        text(ax,0.5,0.5,'Data frame belum dimuat.','Units','normalized', ...
            'HorizontalAlignment','center','Color',[0.5 0.5 0.5]); return;
    end
    scKey = 'velocity_magnitude'; if strcmp(o.scalar,'shear'), scKey='shear'; end
    k = max(1, min(round(o.frame), pivcore.util.scalarOr(h.imgFrames,1)));
    if k>1 && ~pivcore.util.isFullLoaded(h)
        pivui.grain4Shell.ensureFull(ancestor(ax,'figure')); h = guidata(ancestor(ax,'figure'));
    end
    cfg = h; cfg.scalarSrc = scKey;
    isShear = strcmp(o.scalar,'shear');
    if isShear, cfg.shearAbs = o.shearAbs; else, cfg.climVel = o.climVel; end
    cfg.gsOn = o.gsOn; cfg.glyphOn = o.glyphOn;
    pivcore.montage.renderScalarPanel(ax, h.data, k, scKey, cfg);
    set(ax,'Color','w','XColor',[0 0 0],'YColor',[0 0 0]);
    % MASKING (putih borderless) DI ATAS gambar background, DI BAWAH elemen.
    i_drawMasks(ax, o);
    if o.tickPx
        % biarkan tick default
    else
        set(ax,'XTick',[],'YTick',[]);   % POLOS (kunci konvensi)
    end
    if o.showColorbar
        cb = colorbar(ax);
        if isShear
            cb.Label.String = 'shear strain (du/dy+dv/dx)';
        else
            cb.Label.String = '|V| (cm/s)';
            cl = clim(ax); t = get(cb,'Ticks');
            if isempty(t), t = linspace(cl(1),cl(2),6); set(cb,'Ticks',t); end
            set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*o.velMult), t,'UniformOutput',false));
        end
        set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
    end
    hold(ax,'on');
    if ~isempty(h.line) && isfield(h.line,'p1')
        plot(ax,[h.line.p1(1) h.line.p2(1)],[h.line.p1(2) h.line.p2(2)],'-','Color',[1 0.6 0.1],'LineWidth',0.8);
    end
    if o.markerHWFW
        F = {}; if isstruct(h.fdoc)&&isfield(h.fdoc,'faults'), F = h.fdoc.faults; end
        for kk = 1:numel(F)
            f = F{kk};
            if ~isempty(pivui.grain5Model.parentId(f)), continue; end
            if ~pivui.grain5Model.faultEnabled(f), continue; end
            if ~i_faultVisible(f, o), continue; end
            [~, hwRow, fwRow, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
            if okHW, i_mainMarker(ax, h, hwRow, o.hwColor, sprintf('HW%s',i_uiNumStr(f)), o.indMarkerSize); end
            if okFW, i_mainMarker(ax, h, fwRow, o.fwColor, sprintf('FW%s',i_uiNumStr(f)), o.indMarkerSize); end
        end
    end
    hold(ax,'off');
    i_setTitle(ax, h, o);
end


% ---------------------------------------------------------------------
function [xv, yv] = i_curveXYcal(h, row, clampAB, strainTot, velMult, xOn)
%I_CURVEXYCAL  Deret X (strain%) & Y (cm/s) TERKALIBRASI dari kurva baris `row`.
    xv = []; yv = [];
    if isempty(row) || row<1 || row>numel(h.recs), return; end
    [xf, yraw] = pivcore.pot.records.curveXY(h.recs(row), h.nF);
    yraw = pivui.grain4Shell.applyTrimYV(h.recs(row), yraw);
    yraw = pivui.grain4Shell.dispYV(h, yraw);
    yraw = pivui.grain5Fmt.clampRange(yraw, clampAB);
    xv = i_xmap(xf, h.nF, strainTot, xOn);
    yv = yraw * velMult;
end


function x = i_xmap(xf, nF, strainTot, xOn)
%I_XMAP  Map vektor frame -> strain% (bila kalibrasi ada) else identitas (frame).
    if xOn && nF>1 && isfinite(strainTot)
        x = (xf-1)/(nF-1)*strainTot;
    else
        x = xf;
    end
end


function i_drawPoiSet(ax, h, o, f, row, clampAB, strainTot, velMult, xOn)
%I_DRAWPOISET  4 titik POI (START/NUC/FSR/END) pada kurva baris `row` (mode POT).
    if isempty(row) || row<1 || row>numel(h.recs), return; end
    [~, yv] = i_curveXYcal(h, row, clampAB, strainTot, velMult, xOn);
    which = {'start','nuc','fsr','end'}; fld = {'startF','nuc','fsr','endF'};
    for i = 1:numel(which)
        i_plotPtStyled(ax, h, o, f, which{i}, f.(fld{i}), yv, strainTot, xOn);
    end
end


function i_drawPoiOnVec(ax, h, o, f, yvec, nF, strainTot, xOn)
%I_DRAWPOIONVEC  4 titik POI pada vektor net-slip terkalibrasi `yvec` (cm/s).
    which = {'start','nuc','fsr','end'}; fld = {'startF','nuc','fsr','endF'};
    for i = 1:numel(which)
        i_plotPtStyled(ax, h, o, f, which{i}, f.(fld{i}), yvec, strainTot, xOn);
    end
end


function i_plotPtStyled(ax, h, o, f, which, frameF, yvec, strainTot, xOn)
%I_PLOTPTSTYLED  Satu titik POI TERKONTROL: show/warna/ukuran dari o.poi.(which),
%   + filter exclude uiNum. X = strain% (bila kalibrasi), Y = nilai yvec di frame.
    p = o.poi.(which);
    if ~p.show, return; end
    if ~(isscalar(frameF)&&isfinite(frameF)&&frameF>=1&&frameF<=numel(yvec)), return; end
    uin = pivui.grain5Model.faultUiNum(f);
    if any(p.exclude(:)' == round(uin)), return; end   % "kecuali F#"
    yv = yvec(round(frameF)); if ~isfinite(yv), return; end
    xv = i_xmap(round(frameF), h.nF, strainTot, xOn);
    ms = max(2, p.size);
    plot(ax, xv, yv, 'o','MarkerSize',ms,'LineWidth',1.4, ...
        'MarkerEdgeColor',i_col(p.color),'MarkerFaceColor','w', ...
        'Tag','nsPoint','HitTest','off','PickableParts','none');
end


function i_drawVlines(ax, h, o, f, strainTot, velMult, xOn) %#ok<INUSD>
%I_DRAWVLINES  Garis vertikal POI (tinggi bertingkat) di frame START/NUC/FSR/END.
    yl = get(ax,'YLim'); xl = get(ax,'XLim');
    specs = {'startF','start','START',0; 'nuc','nuc','NUC',1; 'fsr','fsr','FSR',2; 'endF','end','END',3};
    step = 0.075*(yl(2)-yl(1));
    for k = 1:size(specs,1)
        fld = specs{k,1}; if ~isfield(f,fld), continue; end
        xf = f.(fld); if ~(isscalar(xf)&&isfinite(xf)), continue; end
        p = o.poi.(specs{k,2});
        uin = pivui.grain5Model.faultUiNum(f);
        if any(p.exclude(:)'==round(uin)), continue; end
        col = i_col(p.color);
        tier = 0; if o.vline.tiered, tier = specs{k,4}; end
        yLab = yl(2) - tier*step;
        xv = i_xmap(round(xf), h.nF, strainTot, xOn);
        plot(ax,[xv xv],[yl(1) yLab],'--','Color',[col 0.85],'LineWidth',o.vline.lineWidth, ...
            'Tag','poiVline','HitTest','off','PickableParts','none');
        if o.vline.labelFrame
            ha = 'left';
            if isfinite(xl(2)) && xv > xl(1)+0.85*(xl(2)-xl(1)), ha='right'; end
            txt = sprintf('%s f%d', specs{k,3}, round(xf));
            text(ax, xv, yLab, txt,'Color',col,'FontSize',7.5,'FontWeight','bold', ...
                'VerticalAlignment','top','HorizontalAlignment',ha, ...
                'BackgroundColor',[1 1 1 0.6],'Margin',1,'Tag','poiVline', ...
                'HitTest','off','PickableParts','none');
        end
    end
end


function i_mainMarker(ax, h, row, col, label, ms)
%I_MAINMARKER  Marker HW/FW di origin sampling PSG (mode AX main) + label.
    if isempty(row) || row<1 || row>numel(h.recs), return; end
    if ~isfield(h.recs(row),'origin'), return; end
    ori = h.recs(row).origin;
    if numel(ori)~=2 || ~all(isfinite(ori)), return; end
    plot(ax, ori(1), ori(2), 'o','MarkerSize',max(3,ms),'LineWidth',1.0, ...
        'MarkerEdgeColor',[1 1 1],'MarkerFaceColor',col,'HitTest','off','PickableParts','none');
    text(ax, ori(1), ori(2), [' ' label],'Color',[1 1 1],'BackgroundColor',col, ...
        'Margin',1,'FontWeight','bold','FontSize',8,'VerticalAlignment','middle', ...
        'HitTest','off','PickableParts','none');
end


function tf = i_faultVisible(f, o)
%I_FAULTVISIBLE  True bila sesar boleh tampil menurut o.faultsOn/faultsOff.
    uin = round(pivui.grain5Model.faultUiNum(f));
    tf = true;
    if ~isempty(o.faultsOn), tf = any(o.faultsOn(:)'==uin); end
    if tf && ~isempty(o.faultsOff) && any(o.faultsOff(:)'==uin), tf = false; end
end


function i_setTitle(ax, h, o)
    if ~o.showTitle, title(ax,''); return; end
    t = o.title; if isempty(t), t = i_baseName(h.df); end
    title(ax, t, 'Interpreter','none','Color',[0 0 0]);
end


function i_applyZoom(ax, h, o, nF, strainTot, xOn)
%I_APPLYZOOM  Batasi XLim ke jendela zoom (frame span -> strain) bila zoomOn.
    if ~o.zoomOn || ~(nF>1), return; end
    span = max(2, round(o.zoomSpan)); if span>=nF, return; end
    % Pusatkan di rentang START..END sesar tampil (fallback tengah).
    lo = 1; hi = nF;
    a = round((nF-span)/2)+1; b = a+span-1;
    a = max(1,a); b = min(nF,b);
    xa = i_xmap(a, nF, strainTot, xOn); xb = i_xmap(b, nF, strainTot, xOn); %#ok<NASGU>
    xlo = i_xmap(a, nF, strainTot, xOn); xhi = i_xmap(b, nF, strainTot, xOn);
    if xlo>xhi, tmp=xlo; xlo=xhi; xhi=tmp; end
    try, xlim(ax,[xlo xhi]); catch, end %#ok<NASGU>
end


% =====================================================================
% MASKING (patch putih borderless; draw kotak/poligon; hapus semua)
% =====================================================================
function i_drawMasks(ax, o)
%I_DRAWMASKS  Gambar SEMUA mask (kotak + poligon) sbg patch PUTIH TANPA border.
%   Dipanggil setelah background (renderScalarPanel) & sebelum elemen -> elemen
%   tetap di atas. Koordinat = data (piksel gambar). Tag 'graineditMask'.
    if ~isstruct(o) || ~isfield(o,'masks') || ~isstruct(o.masks), return; end
    m = o.masks; hs = ishold(ax); hold(ax,'on');
    if isfield(m,'rects') && ~isempty(m.rects)
        R = m.rects;
        for i = 1:size(R,1)
            x=R(i,1); y=R(i,2); w=R(i,3); hgt=R(i,4);
            patch(ax,[x x+w x+w x],[y y y+hgt y+hgt],[1 1 1], ...
                'EdgeColor','none','FaceColor',[1 1 1],'Tag','graineditMask', ...
                'HitTest','off','PickableParts','none');
        end
    end
    if isfield(m,'polys') && ~isempty(m.polys)
        for i = 1:numel(m.polys)
            v = m.polys{i};
            if isnumeric(v) && size(v,2)==2 && size(v,1)>=3
                patch(ax, v(:,1), v(:,2), [1 1 1], ...
                    'EdgeColor','none','FaceColor',[1 1 1],'Tag','graineditMask', ...
                    'HitTest','off','PickableParts','none');
            end
        end
    end
    if ~hs, hold(ax,'off'); end
end


function i_onDrawMask(fig, kind)
%I_ONDRAWMASK  Tombol gambar mask: buka ROI interaktif (drawrectangle/drawpolygon)
%   di kanvas, ambil vertices, SIMPAN ke o.masks, hapus ROI, re-render (patch putih).
    if pivui.quiet(), return; end   % headless: draw interaktif di-skip
    h = guidata(fig);
    if ~ishghandle(h.ax), return; end
    try
        if strcmp(kind,'rect')
            roi = drawrectangle(h.ax,'Color',[1 1 1],'FaceAlpha',0.35);
            if isempty(roi) || ~isvalid(roi), return; end
            p = roi.Position;   % [x y w h]
            delete(roi);
            if numel(p)==4, h.o.masks.rects = [h.o.masks.rects; p(:)']; end
        else
            roi = drawpolygon(h.ax,'Color',[1 1 1],'FaceAlpha',0.35);
            if isempty(roi) || ~isvalid(roi), return; end
            v = roi.Position;   % Kx2
            delete(roi);
            if isnumeric(v) && size(v,2)==2 && size(v,1)>=3
                h.o.masks.polys{end+1} = v;
            end
        end
    catch ME
        i_setStatus(fig, sprintf('Masking gagal: %s', ME.message)); return;
    end
    guidata(fig, h);
    i_apply(fig);
end


function i_onClearMask(fig, kind)
%I_ONCLEARMASK  Hapus SEMUA kotak (kind='rect') atau SEMUA poligon (kind='poly').
    h = guidata(fig);
    if strcmp(kind,'rect'), h.o.masks.rects = []; else, h.o.masks.polys = {}; end
    guidata(fig, h);
    i_apply(fig);
    i_setStatus(fig, sprintf('Semua %s dihapus.', i_kindLabel(kind)));
end

function s = i_kindLabel(kind)
    if strcmp(kind,'rect'), s = 'kotak'; else, s = 'poligon'; end
end


% =====================================================================
% CALLBACK UI
% =====================================================================
function i_onCtrl(fig)
    i_apply(fig);
end

function i_onSetMode(fig, mode)
    h = guidata(fig);
    h.o.mode = mode;
    if isfield(h,'btnModePot'), set(h.btnModePot,'Value',double(strcmp(mode,'pot'))); end
    if isfield(h,'btnModeNs'),  set(h.btnModeNs,'Value',double(strcmp(mode,'netslip'))); end
    if isfield(h,'btnModeMain'),set(h.btnModeMain,'Value',double(strcmp(mode,'main'))); end
    guidata(fig, h);
    i_apply(fig);
end

function i_onFrameSlider(fig)
    h = guidata(fig);
    if ~isfield(h,'sldFrame')||~ishghandle(h.sldFrame), return; end
    k = round(get(h.sldFrame,'Value'));
    h.o.frame = k; guidata(fig, h);
    if isfield(h,'txtFrame')&&ishghandle(h.txtFrame), set(h.txtFrame,'String',sprintf('f%d',k)); end
    i_apply(fig);
end

function i_onPoiColor(fig, which)
    h = guidata(fig);
    cur = i_col(h.o.poi.(which).color);
    if ~pivui.quiet()
        c = uisetcolor(cur, sprintf('Warna %s', upper(which)));
        if isscalar(c) && c==0, return; end
        h.o.poi.(which).color = c;
    end
    if isfield(h.poiCtrl,which) && ishghandle(h.poiCtrl.(which).btnCol)
        set(h.poiCtrl.(which).btnCol,'BackgroundColor',i_col(h.o.poi.(which).color));
    end
    guidata(fig, h); i_apply(fig);
end

function i_onPoiSize(fig, which, step)
    h = guidata(fig);
    v = h.o.poi.(which).size + step;
    v = max(2, min(30, v));
    h.o.poi.(which).size = v;
    if isfield(h.poiCtrl,which) && ishghandle(h.poiCtrl.(which).edSize)
        set(h.poiCtrl.(which).edSize,'String',sprintf('%g',v));
    end
    guidata(fig, h); i_apply(fig);
end

function i_onFaultColor(fig, field)
    h = guidata(fig);
    cur = i_col(h.o.(field));
    if ~pivui.quiet()
        c = uisetcolor(cur, 'Warna');
        if isscalar(c) && c==0, return; end
        h.o.(field) = c;
    end
    switch field
        case 'hwColor',   b = 'btnHwCol';
        case 'fwColor',   b = 'btnFwCol';
        case 'slipColor', b = 'btnSlipCol';
        otherwise, b = '';
    end
    if ~isempty(b) && isfield(h,b) && ishghandle(h.(b)), set(h.(b),'BackgroundColor',i_col(h.o.(field))); end
    guidata(fig, h); i_apply(fig);
end

function i_onFaultToggle(fig, evt)
%I_ONFAULTTOGGLE  Kolom "Tampil" tabel sesar diubah -> update o.faultsOff.
    h = guidata(fig);
    if ~isstruct(evt) && ~isobject(evt), return; end
    try, idx = evt.Indices; catch, return; end
    if isempty(idx) || idx(2)~=4, return; end
    row = idx(1);
    if ~isfield(h,'faultRowUiNum') || row>numel(h.faultRowUiNum), return; end
    uin = h.faultRowUiNum(row);
    on = true; try, on = logical(evt.NewData); catch, end
    off = h.o.faultsOff(:)';
    if on, off(off==uin) = []; else, off = unique([off uin]); end
    h.o.faultsOff = off;
    guidata(fig, h); i_apply(fig);
end


% =====================================================================
% TABEL SESAR (baca-saja + toggle tampil)
% =====================================================================
function i_refreshFaultTable(fig)
    h = guidata(fig);
    if ~isfield(h,'tblFault') || ~ishghandle(h.tblFault), return; end
    F = {}; if isstruct(h.fdoc)&&isfield(h.fdoc,'faults'), F = h.fdoc.faults; end
    rows = {}; uinums = [];
    for k = 1:numel(F)
        f = F{k};
        if ~isempty(pivui.grain5Model.parentId(f)), continue; end
        [~, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
        if ~(okHW||okFW), continue; end     % hanya sesar teridentifikasi
        uin = round(pivui.grain5Model.faultUiNum(f));
        vis = ~any(h.o.faultsOff(:)'==uin);
        rows(end+1,:) = {sprintf('F%d',uin), i_tf(okHW,'✓','—'), i_tf(okFW,'✓','—'), vis}; %#ok<AGROW>
        uinums(end+1) = uin; %#ok<AGROW>
    end
    set(h.tblFault,'Data',rows);
    h.faultRowUiNum = uinums;
    guidata(fig, h);
end


% =====================================================================
% PERSISTENSI (o <-> UI, global setpref, sidecar)
% =====================================================================
function o = i_readControls(h)
%I_READCONTROLS  Baca semua widget -> struct o (dgn clamp). Masks/frame/faultsOff
%   tetap dari h.o (state, bukan widget).
    o = h.o;
    g = @(w,d) i_gnum(w,d); gs = @(w,d) i_gstr(w,d);
    if isfield(h,'edTitle'),   o.title = gs(h.edTitle, o.title); end
    if isfield(h,'chkTitle'),  o.showTitle = logical(get(h.chkTitle,'Value')); end
    if isfield(h,'edXlab'),    o.xlabel = gs(h.edXlab, o.xlabel); end
    if isfield(h,'edYlab'),    o.ylabel = gs(h.edYlab, o.ylabel); end
    if isfield(h,'chkXrev'),   o.xReverse = logical(get(h.chkXrev,'Value')); end
    if isfield(h,'chkGrid'),   o.showGrid = logical(get(h.chkGrid,'Value')); end
    if isfield(h,'edVelMult'), o.velMult = max(1e-9, g(h.edVelMult, o.velMult)); end
    if isfield(h,'chkZoom'),   o.zoomOn = logical(get(h.chkZoom,'Value')); end
    if isfield(h,'edZoomSpan'),o.zoomSpan = max(2, round(g(h.edZoomSpan, o.zoomSpan))); end
    if isfield(h,'edW'),       o.widthCm = max(2, g(h.edW, o.widthCm)); end
    if isfield(h,'edH'),       o.heightCm = max(2, g(h.edH, o.heightCm)); end
    if isfield(h,'edDpi'),     o.dpi = max(50, round(g(h.edDpi, o.dpi))); end
    % POI per-jenis.
    which = {'start','nuc','fsr','end'};
    for i = 1:numel(which)
        w = which{i};
        if isfield(h,'poiCtrl') && isfield(h.poiCtrl,w)
            c = h.poiCtrl.(w);
            if ishghandle(c.chk),   o.poi.(w).show = logical(get(c.chk,'Value')); end
            if ishghandle(c.edSize),o.poi.(w).size = max(2, g(c.edSize, o.poi.(w).size)); end
            if isfield(c,'edExcl')&&ishghandle(c.edExcl), o.poi.(w).exclude = i_parseList(get(c.edExcl,'String')); end
        end
    end
    if isfield(h,'chkVline'),      o.vline.show = logical(get(h.chkVline,'Value')); end
    if isfield(h,'chkVlineTier'),  o.vline.tiered = logical(get(h.chkVlineTier,'Value')); end
    if isfield(h,'chkVlineFrame'), o.vline.labelFrame = logical(get(h.chkVlineFrame,'Value')); end
    % Sesar & zona.
    if isfield(h,'edCurveW'),   o.curveWidth = max(0.5, g(h.edCurveW, o.curveWidth)); end
    if isfield(h,'edZoneAlpha'),o.zoneAlpha = min(0.95, max(0.02, g(h.edZoneAlpha, o.zoneAlpha))); end
    if isfield(h,'chkArea'),    o.areaShade = logical(get(h.chkArea,'Value')); end
    if isfield(h,'chkFaultLabel'), o.faultLabel = logical(get(h.chkFaultLabel,'Value')); end
    if isfield(h,'chkClamp'),   o.clampAB = logical(get(h.chkClamp,'Value')); end
    if isfield(h,'chkShowBg'),  o.showBg = logical(get(h.chkShowBg,'Value')); end
    % AX main.
    if isfield(h,'popScalar'),  o.scalar = i_tf(get(h.popScalar,'Value')==2,'shear','velmag'); end
    if isfield(h,'edClimLo'),   o.climVel(1) = g(h.edClimLo, o.climVel(1)); end
    if isfield(h,'edClimHi'),   o.climVel(2) = g(h.edClimHi, o.climVel(2)); end
    if o.climVel(2) <= o.climVel(1), o.climVel(2) = o.climVel(1) + eps; end
    if isfield(h,'edShearAbs'), o.shearAbs = max(1e-6, g(h.edShearAbs, o.shearAbs)); end
    if isfield(h,'chkTickPx'),  o.tickPx = logical(get(h.chkTickPx,'Value')); end
    if isfield(h,'chkColorbar'),o.showColorbar = logical(get(h.chkColorbar,'Value')); end
    if isfield(h,'chkGS'),      o.gsOn = logical(get(h.chkGS,'Value')); end
    if isfield(h,'chkGlyph'),   o.glyphOn = logical(get(h.chkGlyph,'Value')); end
    if isfield(h,'chkMarkerHW'),o.markerHWFW = logical(get(h.chkMarkerHW,'Value')); end
end


function i_applyOptsToControls(fig)
%I_APPLYOPTSTOCONTROLS  o -> semua widget (arah balik).
    h = guidata(fig); o = h.o;
    sset = @(w,v) i_setIf(h, w, 'String', v);
    vset = @(w,v) i_setIf(h, w, 'Value', v);
    sset('edTitle', o.title); vset('chkTitle', double(o.showTitle));
    sset('edXlab', o.xlabel); sset('edYlab', o.ylabel);
    vset('chkXrev', double(o.xReverse)); vset('chkGrid', double(o.showGrid));
    sset('edVelMult', sprintf('%g',o.velMult));
    vset('chkZoom', double(o.zoomOn)); sset('edZoomSpan', sprintf('%d',round(o.zoomSpan)));
    sset('edW', sprintf('%g',o.widthCm)); sset('edH', sprintf('%g',o.heightCm)); sset('edDpi', sprintf('%d',round(o.dpi)));
    which = {'start','nuc','fsr','end'};
    for i = 1:numel(which)
        w = which{i};
        if isfield(h,'poiCtrl') && isfield(h.poiCtrl,w)
            c = h.poiCtrl.(w);
            if ishghandle(c.chk), set(c.chk,'Value',double(o.poi.(w).show)); end
            if ishghandle(c.btnCol), set(c.btnCol,'BackgroundColor',i_col(o.poi.(w).color)); end
            if ishghandle(c.edSize), set(c.edSize,'String',sprintf('%g',o.poi.(w).size)); end
            if isfield(c,'edExcl')&&ishghandle(c.edExcl), set(c.edExcl,'String',i_list2str(o.poi.(w).exclude)); end
        end
    end
    vset('chkVline', double(o.vline.show)); vset('chkVlineTier', double(o.vline.tiered));
    vset('chkVlineFrame', double(o.vline.labelFrame));
    sset('edCurveW', sprintf('%g',o.curveWidth)); sset('edZoneAlpha', sprintf('%g',o.zoneAlpha));
    vset('chkArea', double(o.areaShade)); vset('chkFaultLabel', double(o.faultLabel)); vset('chkClamp', double(o.clampAB));
    vset('chkShowBg', double(o.showBg));
    if isfield(h,'btnHwCol')&&ishghandle(h.btnHwCol), set(h.btnHwCol,'BackgroundColor',i_col(o.hwColor)); end
    if isfield(h,'btnFwCol')&&ishghandle(h.btnFwCol), set(h.btnFwCol,'BackgroundColor',i_col(o.fwColor)); end
    if isfield(h,'btnSlipCol')&&ishghandle(h.btnSlipCol), set(h.btnSlipCol,'BackgroundColor',i_col(o.slipColor)); end
    vset('popScalar', 1+double(strcmp(o.scalar,'shear')));
    sset('edClimLo', sprintf('%g',o.climVel(1))); sset('edClimHi', sprintf('%g',o.climVel(2)));
    sset('edShearAbs', sprintf('%g',o.shearAbs));
    vset('chkTickPx', double(o.tickPx)); vset('chkColorbar', double(o.showColorbar));
    vset('chkGS', double(o.gsOn)); vset('chkGlyph', double(o.glyphOn)); vset('chkMarkerHW', double(o.markerHWFW));
    if isfield(h,'btnModePot'), set(h.btnModePot,'Value',double(strcmp(o.mode,'pot'))); end
    if isfield(h,'btnModeNs'),  set(h.btnModeNs,'Value',double(strcmp(o.mode,'netslip'))); end
    if isfield(h,'btnModeMain'),set(h.btnModeMain,'Value',double(strcmp(o.mode,'main'))); end
end


function o = i_loadGlobalPref(o)
%I_LOADGLOBALPREF  Merge pref global tersimpan ke o (tahan-migrasi).
    try
        if ispref('GRAINEDIT','global')
            g = getpref('GRAINEDIT','global');
            o = pivcore.io.grainEditProject.mergeOpts(g);
        end
    catch
    end
end

function i_onSaveGlobal(fig)
    h = guidata(fig); o = i_readControls(h); h.o = o; guidata(fig,h);
    try, setpref('GRAINEDIT','global', o); i_setStatus(fig,'Setelan disimpan sebagai default global.');
    catch ME, i_setStatus(fig, sprintf('Gagal simpan default: %s', ME.message)); end
end

function i_onResetGlobal(fig)
    h = guidata(fig);
    keepMasks = h.o.masks;   % masks per-gambar, jangan direset paksa
    h.o = pivcore.io.grainEditProject.defaultOpts();
    h.o.masks = keepMasks;
    guidata(fig, h);
    i_applyOptsToControls(fig); i_apply(fig);
    i_setStatus(fig,'Setelan dikembalikan ke default.');
end


% =====================================================================
% EXPORT (1 gambar mode aktif + sidecar setelan)
% =====================================================================
function i_onExport(fig)
    h = guidata(fig); o = i_readControls(h); h.o = o; guidata(fig,h);
    if isempty(h.df), i_setStatus(fig,'Muat eksperimen dulu.'); return; end
    grainRoot = fileparts(mfilename('fullpath'));
    root = h.exportRootOverride; if isempty(root), root = grainRoot; end
    try
        pivcore.io.grainEditExport.ensureDir(root, h.df);
        imgPath = pivcore.io.grainEditExport.imagePath(root, h.df, o.mode, '', 'png');
        jsPath  = pivcore.io.grainEditExport.jsonPath(root, h.df, o.mode, '');
        % Render OFFSCREEN ukuran fisik cm (WYSIWYG = kanvas).
        tmp = figure('Visible','off','Color','w','Units','centimeters', ...
            'Position',[1 1 o.widthCm o.heightCm]);
        try, pivui.forceLightTheme(tmp); catch, end
        set(tmp,'Color','w');
        cu = onCleanup(@() i_closeIf(tmp));
        ax = axes('Parent',tmp,'Units','normalized','OuterPosition',[0 0 1 1]);
        i_drawEdit(ax, h, o);
        exportgraphics(tmp, imgPath, 'Resolution', o.dpi);
        clear cu;
        % Sidecar setelan (di FOLDER export, bukan samping .mat — arsip repro).
        pivcore.io.grainEditProject.save(jsPath, o, h.df);
        i_setStatus(fig, sprintf('Diekspor: %s', imgPath));
        h.lastExportMsg = imgPath; guidata(fig, h);
    catch ME
        i_setStatus(fig, sprintf('Export GAGAL: %s', ME.message));
    end
end

function i_onOpenFolder(fig)
    h = guidata(fig);
    if isempty(h.df), return; end
    grainRoot = fileparts(mfilename('fullpath'));
    root = h.exportRootOverride; if isempty(root), root = grainRoot; end
    d = pivcore.io.grainEditExport.expDir(root, h.df);
    if ~isfolder(d), i_setStatus(fig,'Folder export belum ada (export dulu).'); return; end
    if pivui.quiet(), return; end
    try
        if ispc, winopen(d);
        elseif ismac, system(['open "' d '"']);
        else, system(['xdg-open "' d '"']);
        end
    catch
    end
end


% =====================================================================
% HELPER widget & util
% =====================================================================
function [ed, y] = i_lbledit(T, lbl, val, y, dy, cb)
    uicontrol(T,'Style','text','Units','normalized','Position',[0.03 y 0.55 0.042], ...
        'String',lbl,'HorizontalAlignment','left','BackgroundColor',get(T,'BackgroundColor'));
    ed = uicontrol(T,'Style','edit','Units','normalized','Position',[0.60 y 0.36 0.045], ...
        'String',val,'HorizontalAlignment','left','Callback',cb);
    y = y - dy;
end

function [cb, y] = i_chk(T, lbl, val, y, dy, cbf)
    cb = uicontrol(T,'Style','checkbox','Units','normalized','Position',[0.05 y 0.90 0.045], ...
        'String',lbl,'Value',double(logical(val)),'BackgroundColor',get(T,'BackgroundColor'), ...
        'Callback',cbf);
    y = y - dy;
end

function [ed, bUp, bDn] = i_spin(T, x, y, val, cbstep)
    ed = uicontrol(T,'Style','edit','Units','normalized','Position',[x y 0.14 0.045], ...
        'String',val,'HorizontalAlignment','center','Enable','inactive');
    bUp = uicontrol(T,'Style','pushbutton','Units','normalized','Position',[x+0.15 y+0.022 0.10 0.024], ...
        'String','▲','Callback',@(s,e) cbstep(1));
    bDn = uicontrol(T,'Style','pushbutton','Units','normalized','Position',[x+0.15 y 0.10 0.024], ...
        'String','▼','Callback',@(s,e) cbstep(-1));
end

function c = i_col(x)
    if isnumeric(x) && numel(x)==3, c = min(1,max(0,double(x(:).'))); else, c = [0.4 0.4 0.4]; end
end

function v = i_gnum(w, d)
    v = d;
    if ishghandle(w)
        x = str2double(get(w,'String'));
        if isscalar(x) && isfinite(x), v = x; end
    end
end

function s = i_gstr(w, d)
    s = d; if ishghandle(w), s = get(w,'String'); if iscell(s)&&~isempty(s), s=s{1}; end, end
    if ~ischar(s), s = char(string(s)); end
end

function i_setIf(h, w, prop, val)
    if isfield(h,w) && ishghandle(h.(w))
        try, set(h.(w), prop, val); catch, end
    end
end

function v = i_parseList(s)
%I_PARSELIST  "1,2,5" / "1 2 5" -> [1 2 5] (uiNum yang di-exclude).
    v = [];
    if isempty(s), return; end
    if iscell(s), s = strjoin(s,' '); end
    tok = regexp(char(s), '-?\d+', 'match');
    if ~isempty(tok), v = cellfun(@str2double, tok); v = v(isfinite(v)); end
end

function s = i_list2str(v)
    if isempty(v), s = ''; else, s = strjoin(arrayfun(@(x) sprintf('%d',round(x)), v(:)','UniformOutput',false), ', '); end
end

function s = i_tf(cond, a, b)
    if cond, s = a; else, s = b; end
end

function s = i_baseName(df)
    s = ''; if ~isempty(df), [~, s] = fileparts(char(df)); end
end

function i_setStatus(fig, msg)
    h = guidata(fig);
    if isfield(h,'edStatus') && ishghandle(h.edStatus), set(h.edStatus,'String',msg); end
end

function i_closeIf(f)
    try, if ~isempty(f) && ishghandle(f), close(f); end, catch, end
end

function n = i_expFaultCounts(df)
%I_EXPFAULTCOUNTS  Kolom EXTRA tabel exp kiri: [F id, F ✓] (baca _faults.json).
    if ischar(df) && strcmp(df,'__names__'), n = {'F id','F ✓'}; return; end
    nId = 0; nCk = 0;
    try
        doc = pivcore.io.grain5Faults.read(df);
        F = {}; if isstruct(doc)&&isfield(doc,'faults'), F = doc.faults; end
        for k = 1:numel(F)
            f = F{k};
            if ~isempty(pivui.grain5Model.parentId(f)), continue; end
            hasHW = isfield(f,'hwPosPx') && isscalar(f.hwPosPx) && isfinite(f.hwPosPx);
            hasFW = isfield(f,'fwPosPx') && isscalar(f.fwPosPx) && isfinite(f.fwPosPx);
            if hasHW||hasFW, nId = nId + 1; end
            ok4 = all(cellfun(@(fl) isfield(f,fl)&&isscalar(f.(fl))&&isfinite(f.(fl)), {'startF','nuc','fsr','endF'}));
            if ok4, nCk = nCk + 1; end
        end
    catch
    end
    n = {sprintf('%d',nId), sprintf('%d',nCk)};
end

function s = i_uiNumStr(f)
    s = '?';
    try, n = pivui.grain5Model.faultUiNum(f); if isfinite(n), s = sprintf('%d',round(n)); end, catch, end
end
