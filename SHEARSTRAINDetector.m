function figOut = SHEARSTRAINDetector(rootDir, varargin)
%SHEARSTRAINDETECTOR  Digitasi punggungan (ridge) SHEAR STRAIN RATE — semi-otomatis.
%   Analog interpretasi seismik: shear strain rate menampilkan pita merah (+) &
%   biru (−) yang mirip punggungan gelombang. User meng-KLIK satu titik di dekat
%   punggungan pada axMain; sistem men-SNAP klik ke puncak lokal lalu MENELUSURI
%   (auto-trace) sepanjang punggungan ke DUA arah sampai |shear| turun di bawah
%   ambang. Hasil = 1 polyline yang bisa diedit & disimpan.
%
%   Reuse kerangka GRAIN4 (pivui.grain4Shell) SEPENUHNYA: input = SATU FOLDER
%   eksperimen (output Step 2 / PIV_<tgl>/), axMain 3-kolom, load eksperimen,
%   scrub frame. HANYA panel kanan yang diganti dgn alat digitasi ridge. axMain
%   otomatis di-set ke mode SHEAR (skala ± absolut, merah/biru).
%
%   TAHAP 1 (modul ini): auto-trace PER-FRAME. Klik area di axMain -> ridge di
%   frame aktif. (Tahap 2 nanti: sampling beberapa frame sekaligus krn interval
%   gambar kecil -> posisi shear persisten.)
%
%   Basis ridge = |shear| ABSOLUT (atas-bawah sama; user atur "maks-min shear" =
%   ambang thrAbs, mis. 0.04). Hasil disimpan di sidecar TERPISAH
%   `<base>_shearridge.json` (tak menyentuh _desc.json GRAIN4). Engine murni:
%   pivcore.detect.ridgeWalk (auto-trace) + pivcore.io.shearRidge (sidecar).
%
%   HOTKEY: Ctrl+D = mode klik-deteksi ON/OFF · Ctrl+,/. = frame ·
%   Ctrl+Backspace = hapus ridge terpilih.
%
%   SHEARSTRAINDetector                 % pilih folder ROOT (dialog)
%   SHEARSTRAINDetector(rootDir)        % langsung ke folder
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

    opts = struct();
    opts.Name = 'SHEARSTRAINDetector — Digitasi Ridge Shear Strain';
    opts.rightTitle = 'Deteksi Ridge Shear';
    opts.hooks = struct( ...
        'onExpLoaded',     @i_onExpLoaded, ...
        'onLineChanged',   @i_onLineChanged, ...
        'onFrameChanged',  @i_onFrameChanged, ...
        'afterRenderMain', @i_afterRenderMain);

    h = pivui.grain4Shell.build(opts);
    try, set(h.pnlR, 'Position', [0.686 0.010 0.308 0.985]); catch, end

    % axMain lebih tinggi (isi whitespace) — sama pola GRAIN4.
    AXMAIN_POS = [0.205 0.470 0.455 0.400];
    h.axMainPos = AXMAIN_POS;
    try, set(h.axMain, 'Position', AXMAIN_POS); catch, end

    % --- MODE SHEAR: axMain tampil shear strain (merah/biru ±) -------------
    h.scalarSrc = 'shear';

    % --- State modul ridge -------------------------------------------------
    h.rdoc        = pivcore.io.shearRidge.emptyDoc('');  % sidecar dokumen
    h.detectOn    = false;   % mode klik-deteksi aktif (kursor menunggu klik)
    h.selRidgeId  = '';      % ridge terpilih di daftar
    h.roiRidge    = [];      % ROI polyline sedang diedit (setelah trace)
    h.editRidgeId = '';      % id ridge yg sedang diedit ROI ('' = ridge baru)
    h.ridgeOpt    = pivcore.detect.ridgeWalk.defaults();   % param deteksi
    h.clickListener = [];    % listener klik axMain (dipasang saat detectOn)
    h.skipSaveOnClose = false;   % ditandai true oleh "✖ Tutup tanpa simpan"

    guidata(h.fig, h);
    h = i_buildPanel(h, h.pnlR);
    guidata(h.fig, h);

    set(h.fig, 'CloseRequestFcn', @(s,e) i_onClose(s));
    set(h.fig, 'WindowKeyPressFcn', @(s,e) i_onKeyPress(s, e));
    pivui.grain4Shell.setRoot(h.fig, rootDir);

    if ~pivui.quiet()
        try, set(h.fig, 'WindowState', 'maximized'); catch, end
    end
    if nargout > 0, figOut = h.fig; end
end


% =====================================================================
%                       PANEL KANAN (alat ridge)
% =====================================================================
function h = i_buildPanel(h, P)
    fig = h.fig;
    set(P, 'Title', 'Deteksi Ridge Shear Strain', 'FontWeight','bold');

    % ---- Instruksi ringkas ----
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.930 0.94 0.058],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',[1 1 1], ...
        'String',['Klik "🎯 Deteksi (Ctrl+D)" lalu klik SATU titik di dekat ' ...
                  'punggungan shear (pita merah/biru) pada axMain. Sistem menelusuri ' ...
                  'puncak ke dua arah.']);

    % ---- Tombol mode deteksi + hapus ----
    h.btnDetect = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.03 0.880 0.46 0.045],'String','🎯 Deteksi (Ctrl+D)', ...
        'FontWeight','bold','Value',0, ...
        'TooltipString','Aktifkan mode klik-deteksi ridge. Klik lagi untuk mematikan.', ...
        'Callback',@(s,e) i_onToggleDetect(fig));
    h.btnClearRidge = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.880 0.46 0.045],'String','🗑 Hapus ridge', ...
        'TooltipString','Buang ridge terpilih di daftar.', ...
        'Callback',@(s,e) i_onDeleteRidge(fig));

    % ---- Parameter deteksi ----
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.828 0.94 0.030],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',[1 1 1],'String','Parameter deteksi');

    % ambang absolut |shear|
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.788 0.44 0.032],'HorizontalAlignment','left', ...
        'BackgroundColor',[1 1 1],'String','Ambang pita shear:');
    h.edThr = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.49 0.788 0.22 0.036],'String',num2str(h.ridgeOpt.thrAbs), ...
        'TooltipString',['Magnitudo pita minimum: walk berhenti bila shear (searah ' ...
                         'polaritas klik) turun di bawah ambang ini. Default 0.015 ' ...
                         '(pita lemah ikut tertelusur). Naikkan untuk lebih ketat.'], ...
        'Callback',@(s,e) i_onParam(fig));

    % radius snap
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.744 0.44 0.032],'HorizontalAlignment','left', ...
        'BackgroundColor',[1 1 1],'String','Radius snap (sel grid):');
    h.edSnap = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.49 0.744 0.22 0.036],'String',num2str(h.ridgeOpt.snapRadius), ...
        'TooltipString','Jari-jari window pencarian puncak lokal dari titik klik (dalam sel grid PIV).', ...
        'Callback',@(s,e) i_onParam(fig));

    % smoothing
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.700 0.44 0.032],'HorizontalAlignment','left', ...
        'BackgroundColor',[1 1 1],'String','Penghalus (sigma):');
    h.edSmooth = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.49 0.700 0.22 0.036],'String',num2str(h.ridgeOpt.smoothSigma), ...
        'TooltipString','Gaussian smoothing |shear| sebelum walk (stabilkan ridge). 0 = tanpa.', ...
        'Callback',@(s,e) i_onParam(fig));

    % ---- Daftar ridge (frame aktif) ----
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.648 0.94 0.030],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',[1 1 1], ...
        'String','Ridge di frame ini (garis PSG aktif):');
    h.tblRidge = uitable('Parent',P,'Units','normalized', ...
        'Position',[0.03 0.360 0.94 0.280], ...
        'ColumnName',{'ID','Frm','±','#vtx','mean|sh|','Len px'}, ...
        'ColumnWidth',{40 40 30 44 66 60}, ...
        'ColumnEditable',[false false false false false false], ...
        'RowName',[], ...
        'CellSelectionCallback',@(s,e) i_onSelRidge(fig,e));

    % ---- Tombol simpan ----
    h.btnSave = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.300 0.46 0.048],'String','💾 Simpan', ...
        'FontWeight','bold', ...
        'TooltipString','Tulis semua ridge ke <base>_shearridge.json.', ...
        'Callback',@(s,e) i_onSave(fig));
    h.btnSaveClose = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.300 0.46 0.048],'String','💾 Simpan & Tutup', ...
        'Callback',@(s,e) i_onSaveClose(fig));
    h.btnCloseNoSave = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.248 0.94 0.044],'String','✖ Tutup tanpa simpan', ...
        'ForegroundColor',[0.55 0.05 0.05], ...
        'TooltipString','Tutup jendela TANPA menyimpan perubahan ke _shearridge.json.', ...
        'Callback',@(s,e) i_onCloseNoSave(fig));

    % ---- Status ----
    h.txtRidgeStatus = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.020 0.94 0.210],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',[1 1 1],'ForegroundColor',[0.15 0.15 0.15], ...
        'String','Siap. Muat eksperimen di daftar kiri.');
end


% =====================================================================
%                       HOOKS SHELL
% =====================================================================
function i_onExpLoaded(fig)
    h = guidata(fig);
    h.rdoc = pivcore.io.shearRidge.read(h.realData);
    h.selRidgeId = '';
    i_cleanupRoi(fig);   % (baca-tulis guidata sendiri)
    h = guidata(fig);
    guidata(fig, h);
    i_refreshRidgeTable(fig);
    i_setStatus(fig, sprintf('Eksperimen dimuat. %d ridge tersimpan (semua frame).', ...
        numel(pivcore.io.shearRidge.entries(h.rdoc))));
    % pastikan axMain di mode shear
    h = guidata(fig); h.scalarSrc = 'shear'; guidata(fig, h);
    try, pivui.grain4Shell.renderMain(fig); catch, end
end

function i_onLineChanged(fig)
    i_refreshRidgeTable(fig);
end

function i_onFrameChanged(fig)
    % Ganti frame -> batalkan edit ROI yg belum di-commit (ridge terikat 1 frame).
    i_cleanupRoi(fig);
    i_refreshRidgeTable(fig);
end

function i_afterRenderMain(fig)
    % Gambar ulang overlay ridge tersimpan (renderMain melakukan cla tiap frame).
    i_drawStoredRidges(fig);
end


% =====================================================================
%                       MODE DETEKSI (klik)
% =====================================================================
function i_onToggleDetect(fig)
    h = guidata(fig);
    h.detectOn = ~h.detectOn;
    guidata(fig, h);
    i_syncDetectBtn(fig);
    if h.detectOn
        i_armClick(fig);
        i_setStatus(fig, 'Mode DETEKSI aktif — klik SATU titik di dekat punggungan shear pada axMain.');
    else
        i_disarmClick(fig);
        i_setStatus(fig, 'Mode deteksi mati.');
    end
end

function i_armClick(fig)
    h = guidata(fig);
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain), return; end
    % Nonaktifkan zoom/pan supaya klik jadi pemilihan titik (bukan pan).
    try, zoom(fig,'off'); pan(fig,'off'); catch, end
    set(h.axMain, 'ButtonDownFcn', @(s,e) i_onAxMainClick(fig));
    % image dasar di renderScalarPanel di-set HitTest off -> klik sampai ke axes.
    guidata(fig, h);
end

function i_disarmClick(fig)
    h = guidata(fig);
    if isfield(h,'axMain') && ishghandle(h.axMain)
        set(h.axMain, 'ButtonDownFcn', '');
    end
    guidata(fig, h);
end

function i_onAxMainClick(fig)
    h = guidata(fig);
    if ~h.detectOn, return; end
    cp = get(h.axMain, 'CurrentPoint');
    clickXY = [cp(1,1) cp(1,2)];
    i_detectAt(fig, clickXY);
end

function i_detectAt(fig, clickXY)
    h = guidata(fig);
    % Pastikan semua frame termuat (shear butuh data lengkap frame k).
    if ~pivui.grain4Shell.ensureFull(fig)
        i_setStatus(fig, 'Data belum lengkap termuat; coba lagi.');
        return;
    end
    h = guidata(fig);
    k = max(1, min(h.frame, h.imgFrames));
    [Z, X, Y] = i_shearAt(h, k);
    if isempty(Z)
        i_setStatus(fig, sprintf('Shear kosong di frame %d.', k));
        return;
    end
    opt = i_readOpt(h);
    [V, info] = pivcore.detect.ridgeWalk.trace(Z, clickXY, X, Y, opt);
    if ~info.ok
        i_setStatus(fig, sprintf('Deteksi gagal: %s', info.msg));
        return;
    end
    % Buat ridge baru + buka ROI editable.
    i_openRidgeRoi(fig, V, info, k, '');
    i_setStatus(fig, sprintf(['Ridge terdeteksi: %d titik, %.0f px, mean|shear|=%.4f ' ...
        '(seed %.4f, %s). Geser vertex bila perlu; klik di luar/ganti frame utk kunci.'], ...
        size(V,1), info.lenGrid, info.meanAbs, info.seedVal, i_polarStr(info.polarity)));
end


% =====================================================================
%                       ROI edit + commit
% =====================================================================
function i_openRidgeRoi(fig, V, info, frame, editId)
    h = guidata(fig);
    i_cleanupRoi(fig);
    h = guidata(fig);
    ax = h.axMain;
    col = i_polarColor(info.polarity);
    roi = images.roi.Polyline('Parent',ax,'Position',V,'Color',col, ...
        'LineWidth',2.0,'MarkerSize',6);
    h.roiRidge   = roi;
    h.editRidgeId = editId;
    h.roiInfo    = info;
    h.roiFrame   = frame;
    guidata(fig, h);
    % Live listener: commit langsung saat geser selesai (biar ringan).
    addlistener(roi, 'ROIMoved',  @(s,e) i_roiCommit(fig));
    addlistener(roi, 'DeletingROI', @(s,e) i_cleanupRoi(fig));
    % Commit awal supaya ridge tercatat walau tak digeser.
    i_roiCommit(fig);
end

function i_roiCommit(fig)
    h = guidata(fig);
    if isempty(h.roiRidge) || ~isvalid(h.roiRidge), return; end
    V = h.roiRidge.Position;
    V = pivcore.io.grain4Desc.normVerts(V);
    if size(V,1) < 2, return; end
    info  = h.roiInfo;
    frame = h.roiFrame;
    cmPerPx = i_cmPerPx(h);
    lenCm = pivcore.io.grain4Desc.lenCmOf(V, cmPerPx);
    psgId = i_activePsgId(h);

    id = h.editRidgeId;
    if isempty(id)
        id = pivcore.io.shearRidge.nextId(h.rdoc);
        h.editRidgeId = id;   % lanjutan geser -> update ridge yg sama
    end
    e = pivcore.io.shearRidge.ridgeStruct('id',id,'psgId',psgId,'frame',frame, ...
        'vertices',V,'polarity',info.polarity,'seedVal',info.seedVal, ...
        'meanAbs',info.meanAbs,'lenCm',lenCm);
    h.rdoc = pivcore.io.shearRidge.upsert(h.rdoc, e);
    h.selRidgeId = id;
    guidata(fig, h);
    i_refreshRidgeTable(fig);
end

function i_cleanupRoi(fig)
    h = guidata(fig);
    if isfield(h,'roiRidge') && ~isempty(h.roiRidge) && isvalid(h.roiRidge)
        try, delete(h.roiRidge); catch, end
    end
    h.roiRidge = [];
    h.editRidgeId = '';
    guidata(fig, h);
end


% =====================================================================
%                       OVERLAY tersimpan
% =====================================================================
function i_drawStoredRidges(fig)
    h = guidata(fig);
    if ~isfield(h,'axMain') || ~ishghandle(h.axMain), return; end
    ax = h.axMain;
    delete(findall(ax, 'Tag','shearRidgePoly'));
    if strcmp(h.scalarSrc,'shear') == 0, end   % overlay valid utk mode apa pun
    k = max(1, min(h.frame, h.imgFrames));
    psgId = i_activePsgId(h);
    ridges = pivcore.io.shearRidge.ridgesForFrame(h.rdoc, psgId, k);
    editId = '';
    if isfield(h,'editRidgeId'), editId = h.editRidgeId; end
    wasHold = ishold(ax); hold(ax,'on');
    for i = 1:numel(ridges)
        e = ridges{i};
        if strcmp(e.id, editId), continue; end   % yg sedang diedit ROI -> jangan gambar ganda
        V = pivcore.io.grain4Desc.normVerts(e.vertices);
        if size(V,1) < 2, continue; end
        col = i_polarColor(e.polarity);
        plot(ax, V(:,1), V(:,2), '-', 'Color',col, 'LineWidth',2.0, ...
            'Tag','shearRidgePoly', 'Clipping','on');
        % titik seleksi highlight
        if strcmp(e.id, h.selRidgeId)
            plot(ax, V(:,1), V(:,2), 'o', 'MarkerSize',4, ...
                'MarkerEdgeColor',[0 0 0], 'MarkerFaceColor',col, ...
                'Tag','shearRidgePoly', 'Clipping','on');
        end
    end
    if ~wasHold, hold(ax,'off'); end
end


% =====================================================================
%                       TABEL + SELEKSI
% =====================================================================
function i_refreshRidgeTable(fig)
    h = guidata(fig);
    if ~isfield(h,'tblRidge') || ~ishghandle(h.tblRidge), return; end
    k = max(1, min(h.frame, h.imgFrames));
    psgId = i_activePsgId(h);
    ridges = pivcore.io.shearRidge.ridgesForFrame(h.rdoc, psgId, k);
    n = numel(ridges);
    data = cell(n, 6);
    for i = 1:n
        e = ridges{i};
        V = pivcore.io.grain4Desc.normVerts(e.vertices);
        data{i,1} = e.id;
        data{i,2} = e.frame;
        data{i,3} = i_polarStr(e.polarity);
        data{i,4} = size(V,1);
        data{i,5} = i_fmt(e.meanAbs, 4);
        data{i,6} = i_fmt(pivcore.io.grain4Desc.polylineLenPx(V), 0);
    end
    if n == 0, data = cell(0,6); end
    set(h.tblRidge, 'Data', data);
end

function i_onSelRidge(fig, e)
    if ~isfield(e,'Indices') || isempty(e.Indices), return; end
    h = guidata(fig);
    r = e.Indices(1);
    k = max(1, min(h.frame, h.imgFrames));
    psgId = i_activePsgId(h);
    ridges = pivcore.io.shearRidge.ridgesForFrame(h.rdoc, psgId, k);
    if r < 1 || r > numel(ridges), return; end
    h.selRidgeId = ridges{r}.id;
    guidata(fig, h);
    i_drawStoredRidges(fig);
end

function i_onDeleteRidge(fig)
    h = guidata(fig);
    if isempty(h.selRidgeId)
        i_setStatus(fig, 'Pilih dulu ridge di daftar untuk dihapus.'); return;
    end
    delId = h.selRidgeId;
    h.rdoc = pivcore.io.shearRidge.removeById(h.rdoc, delId);
    h.selRidgeId = '';
    guidata(fig, h);
    i_cleanupRoi(fig);
    i_refreshRidgeTable(fig);
    i_drawStoredRidges(fig);
    i_setStatus(fig, sprintf('Ridge %s dihapus.', delId));
end


% =====================================================================
%                       PARAMETER
% =====================================================================
function i_onParam(fig)
    h = guidata(fig);
    h.ridgeOpt = i_readOpt(h);
    guidata(fig, h);
    i_setStatus(fig, sprintf('Parameter: ambang=%.4f, snap=%d, sigma=%.2f.', ...
        h.ridgeOpt.thrAbs, h.ridgeOpt.snapRadius, h.ridgeOpt.smoothSigma));
end

function opt = i_readOpt(h)
    opt = pivcore.detect.ridgeWalk.defaults();
    if isfield(h,'ridgeOpt') && isstruct(h.ridgeOpt), opt = h.ridgeOpt; end
    if isfield(h,'edThr') && ishghandle(h.edThr)
        v = str2double(get(h.edThr,'String'));   if isfinite(v) && v>=0, opt.thrAbs = v; end
    end
    if isfield(h,'edSnap') && ishghandle(h.edSnap)
        v = str2double(get(h.edSnap,'String'));   if isfinite(v) && v>=1, opt.snapRadius = round(v); end
    end
    if isfield(h,'edSmooth') && ishghandle(h.edSmooth)
        v = str2double(get(h.edSmooth,'String'));  if isfinite(v) && v>=0, opt.smoothSigma = v; end
    end
end


% =====================================================================
%                       SAVE / CLOSE
% =====================================================================
function i_onSave(fig)
    h = guidata(fig);
    if isempty(h.realData)
        i_setStatus(fig, 'Belum ada eksperimen dimuat.'); return;
    end
    try
        pivcore.io.shearRidge.write(h.realData, h.rdoc);
        i_setStatus(fig, sprintf('Tersimpan: %d ridge -> %s', ...
            numel(pivcore.io.shearRidge.entries(h.rdoc)), ...
            pivcore.io.shearRidge.dataPath(h.realData)));
    catch ME
        i_setStatus(fig, sprintf('GAGAL simpan: %s', ME.message));
    end
end

function i_onSaveClose(fig)
    i_onSave(fig);
    try, delete(fig); catch, end
end

function i_onCloseNoSave(fig)
    % Tutup TANPA simpan: set flag lalu delete (CloseRequestFcn lihat flag -> skip save).
    try
        h = guidata(fig); h.skipSaveOnClose = true; guidata(fig, h);
    catch, end
    try, delete(fig); catch, end
end

function i_onClose(fig)
    % Simpan otomatis saat tutup (best-effort) — KECUALI ditandai skipSaveOnClose.
    try
        h = guidata(fig);
        skip = isfield(h,'skipSaveOnClose') && h.skipSaveOnClose;
        if ~skip && ~isempty(h.realData) && ~isempty(pivcore.io.shearRidge.entries(h.rdoc))
            pivcore.io.shearRidge.write(h.realData, h.rdoc);
        end
    catch, end
    try, delete(fig); catch, end
end


% =====================================================================
%                       KEYBOARD
% =====================================================================
function i_onKeyPress(fig, evt)
    try
        mods = {};
        if isprop(evt,'Modifier'), mods = evt.Modifier; end
        key = '';
        if isprop(evt,'Key'), key = lower(char(evt.Key)); end
        hasCtrl = any(strcmp(mods,'control')) || any(strcmp(mods,'command'));
        if ~hasCtrl, return; end
        switch key
            case 'd'
                i_onToggleDetect(fig);
            case {'comma'}
                pivui.grain4Shell.stepFrame(fig, -1);
            case {'period'}
                pivui.grain4Shell.stepFrame(fig, +1);
            case {'backspace','delete'}
                i_onDeleteRidge(fig);
        end
    catch
    end
end


% =====================================================================
%                       HELPER
% =====================================================================
function [Z, X, Y] = i_shearAt(h, k)
%I_SHEARAT  Grid shear frame k + koordinat X/Y yang PERSIS SEPERTI DI LAYAR.
%   KRITIS: shell menampilkan shear via
%       imagesc(ax, xExt, [yExt(2) yExt(1)], Z)   (+ YDir normal)
%   -> imagesc MENGABAIKAN matriks data.y dan menyebar baris Z secara LINEAR dari
%   yExt(2) (atas) ke yExt(1) (bawah). Padahal matriks data.y{k}(1,:) = y-MIN
%   (kebalikan). Kalau engine ridge pakai data.y{k} langsung, posisi VERTIKAL
%   ridge TERCERMIN (flipped) thd yang terlihat -> "seperti deteksi objek beda".
%   Maka DI SINI kita bangun X/Y linear IDENTIK dengan imagesc supaya ridge jatuh
%   tepat di piksel yang tampil.
    Z = []; X = []; Y = [];
    if isempty(h.data), return; end
    try
        Z = pivcore.data.computeShearRate(h.data, k, 'mode','engineering');
    catch
        Z = [];
    end
    if isempty(Z), return; end
    [nR, nC] = size(Z);
    xg = pivcore.data.safeFrame(h.data.x, k);
    yg = pivcore.data.safeFrame(h.data.y, k);
    if isempty(xg) || isempty(yg) || ~isequal(size(Z), size(xg)), Z = []; return; end
    xExt = [min(xg(:)) max(xg(:))];
    yExt = [min(yg(:)) max(yg(:))];
    % X menaik kiri->kanan (kolom); Y MENURUN atas->bawah (baris) — samakan imagesc.
    xv = linspace(xExt(1), xExt(2), nC);
    yv = linspace(yExt(2), yExt(1), nR).';   % baris 1 = yExt(2) (atas layar)
    [X, Y] = meshgrid(xv, yv);
end

function cmPerPx = i_cmPerPx(h)
    cmPerPx = NaN;
    try
        geom = [];
        if isfield(h,'geom') && ~isempty(h.geom), geom = h.geom; end
        if isempty(geom) && isfield(h,'data') && isstruct(h.data) ...
                && isfield(h.data,'experiment_geometry')
            geom = h.data.experiment_geometry;
        end
        dxCm = NaN;
        if isstruct(geom) && isfield(geom,'X0_cm') && isfield(geom,'X1_cm')
            dxCm = abs(double(geom.X0_cm) - double(geom.X1_cm));
        end
        span = NaN;
        if isfield(h,'xExt') && numel(h.xExt)==2, span = abs(diff(h.xExt)); end
        cmPerPx = pivcore.io.grain4Desc.cmPerPxFromGeom(dxCm, span);
    catch
        cmPerPx = NaN;
    end
end

function id = i_activePsgId(h)
    % ID garis PSG aktif (konteks stabil ridge). Shell menyimpan garis di h.line;
    % psgId.fromLine -> "frac075" (auto-PSG) / "geom_..." (kustom). Ridge Tahap 1
    % terikat FRAME; psgId hanya label konteks (tetap konsisten antar-sesi).
    id = '';
    try
        if isfield(h,'line') && ~isempty(h.line)
            id = pivcore.pot.psgId.fromLine(h.line);
        end
    catch, end
    if isempty(id), id = 'frac075'; end
end

function s = i_polarStr(p)
    if p > 0, s = '+ (merah)'; elseif p < 0, s = '− (biru)'; else, s = '·'; end
end

function c = i_polarColor(p)
    if p > 0
        c = [0.75 0.05 0.05];   % merah
    elseif p < 0
        c = [0.05 0.15 0.75];   % biru
    else
        c = [0 0 0];
    end
end

function s = i_fmt(v, dec)
    if ~isfinite(v), s = '—'; return; end
    s = num2str(v, sprintf('%%.%df', dec));
end

function i_syncDetectBtn(fig)
    h = guidata(fig);
    if isfield(h,'btnDetect') && ishghandle(h.btnDetect)
        set(h.btnDetect, 'Value', double(h.detectOn));
        if h.detectOn
            set(h.btnDetect, 'BackgroundColor', [0.80 0.95 0.80]);
        else
            set(h.btnDetect, 'BackgroundColor', get(0,'defaultUicontrolBackgroundColor'));
        end
    end
end

function i_setStatus(fig, msg)
    h = guidata(fig);
    if isfield(h,'txtRidgeStatus') && ishghandle(h.txtRidgeStatus)
        set(h.txtRidgeStatus, 'String', msg);
    end
    try, pivui.setStatus(fig, msg); catch, end
end
