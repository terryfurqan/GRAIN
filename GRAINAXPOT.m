function GRAINAXPOT(projFile)
%GRAINAXPOT  Editor figur AX POT STANDALONE (1 file) — grade-paper raster.
%   Membaca berkas proyek <base>_axpot.mat (ekspor GRAIN4: "Save as AX POT"),
%   menampilkannya pada KANVAS WYSIWYG berukuran fisik (cm), lalu memproduksi
%   RASTER (PNG/JPEG) + JSON sidecar. Fokus TUNGGAL: merakit kurva AX POT untuk
%   bercerita — TANPA sistem komentar (itu di GRAIN4). UI ramping: hanya unsur yg
%   berhubungan dgn pembuatan kurva.
%
%   GRAINAXPOT                 % dialog pilih *_axpot.mat
%   GRAINAXPOT(projFile)       % langsung ke berkas proyek
%
%   WYSIWYG: kanvas kiri = axes Units centimeter (OuterPosition = lebar×tinggi
%   cm). Ekspor membuat figur OFFSCREEN cm yang SAMA + exportgraphics(DPI) ->
%   PNG/JPEG hampir identik dgn layar. Renderer DIPAKAI BERSAMA (i_drawAxpot)
%   untuk preview & ekspor -> paritas terjamin.
%
%   Titik informasi (anotasi) disimpan balik ke .mat (proj.infoPoints) +
%   ditulis ke JSON -> bisa "ngobrol" dgn GRAIN4 (penyerapan = pekerjaan menyusul).
%
%   SELALU MATLAB R2025b. Tema TERANG dipaksa.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.io.axpotProject'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end
    if nargin < 1 || isempty(projFile) || ~ischar(projFile) || ~isfile(projFile)
        [fn, fp] = uigetfile({'*_axpot.mat','Proyek AX POT (*_axpot.mat)'; '*.mat','MAT'}, ...
            'Pilih berkas proyek AX POT (ekspor GRAIN4)');
        if isequal(fn, 0), return; end
        projFile = fullfile(fp, fn);
    end
    proj = pivcore.io.axpotProject.load(projFile);
    % Bila proyek belum punya setelan tampilan, pakai DEFAULT (lintas-sesi):
    % prioritas (1) default per-FOLDER eksperimen (<dir>/_axpot_defaults.json),
    % lalu (2) pref global. Selebihnya = default kode (28×5×300).
    if ~isstruct(proj.display) || isempty(fieldnames(proj.display))
        d = i_loadFolderDefault(fileparts(projFile));
        if isempty(d), d = i_loadLayoutPref(); end
        if ~isempty(d), proj.display = d; end
    end
    % Paper bahasa Inggris: migrasi label sumbu Indonesia (proyek/default lama).
    proj.display = i_migrateLabelsEN(proj.display);
    % recs ada -> jadikan SUMBER kebenaran: curves/hw/indenter = turunan.
    proj = pivcore.io.axpotProject.deriveFromRecs(proj);

    h = i_build(projFile, proj);
    guidata(h.fig, h);
    i_loadDisplay(h.fig);     % pulihkan setelan tampilan tersimpan (round-trip)
    if ~strcmp(get(groot,'DefaultFigureVisible'),'off')   % jangan rebut fokus saat tes senyap
        try, set(h.fig, 'WindowState', 'maximized'); catch, end   % tukar fokus dgn GRAIN4
    end
    i_apply(h.fig);           % render pertama
end


% =====================================================================
% Bangun UI (figur klasik, tema terang)
% =====================================================================
function h = i_build(projFile, proj)
    WHITE = [1 1 1];
    [~, base] = fileparts(projFile);
    fig = figure('Name',pivui.titleWithVersion(sprintf('GRAINAXPOT — editor figur AX POT [%s]', base)), ...
        'NumberTitle','off','Color',WHITE,'Units','pixels', ...
        'Position',[80 80 1180 720],'MenuBar','none','ToolBar','figure');
    pivui.forceLightTheme(fig);   % paksa terang (R2025b ikut dark OS default; dark dilarang)
    h = i_buildInto(fig, projFile, proj);
end

function h = i_buildInto(fig, projFile, proj)
%I_BUILDINTO  Bangun seluruh UI ke dalam figur `fig` yg SUDAH ada (dipakai saat
%   buka pertama & saat Load proyek lain tanpa tutup app).
    WHITE = [1 1 1];
    h = struct();
    h.fig = fig;
    h.projFile = projFile;
    h.proj = proj;
    h.activeHW = NaN;       % HW aktif (navigasi ◀/▶) — disorot merah di kanvas
    h.selCurveRows = [];    % baris kurva terpilih di tabel Assign
    [~, base] = fileparts(projFile);
    set(fig,'Name',pivui.titleWithVersion(sprintf('GRAINAXPOT — editor figur AX POT [%s]', base)));

    % --- Kiri: kanvas WYSIWYG ---
    h.pnlCanvas = uipanel('Parent',h.fig,'Units','normalized','Position',[0.005 0.01 0.66 0.98], ...
        'BackgroundColor',WHITE,'Title','Kanvas WYSIWYG (ukuran fisik cm = output)', ...
        'FontWeight','bold','ForegroundColor',[0.2 0.2 0.35]);
    h.ax = axes('Parent',h.pnlCanvas,'Units','centimeters');
    set(h.ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');

    % --- Kanan: kontrol (2 tab: Tata letak · Edit kurva) ---
    h.pnlR = uipanel('Parent',h.fig,'Units','normalized','Position',[0.67 0.01 0.325 0.98], ...
        'BackgroundColor',WHITE,'BorderType','none');
    h.tg = uitabgroup('Parent',h.pnlR,'Units','normalized','Position',[0 0 1 1]);
    h.tabView  = uitab('Parent',h.tg,'Title','① Tata letak','BackgroundColor',WHITE);
    h.tabLayer = uitab('Parent',h.tg,'Title','② Layer & Output','BackgroundColor',WHITE);
    h.tabEdit  = uitab('Parent',h.tg,'Title','③ Assign HW','BackgroundColor',WHITE);
    h.tabBatch = uitab('Parent',h.tg,'Title','④ Batch Export','BackgroundColor',WHITE);
    P = h.tabView; fig = h.fig; y = 0.972;
    % WYSIWYG mengikuti ukuran jendela (mis. saat maximize): re-render saat resize.
    set(h.fig,'SizeChangedFcn',@(s,e) i_onResize(s));

    % == Kanvas (ukuran) ==
    y = i_sec(P, y, 'Kanvas (cm) & resolusi');
    [h.edW, h.btnWup, h.btnWdn] = i_spin(P, 0.04, y, 'Lebar', i_g(proj.display,'widthCm',28), fig);
    [h.edH, h.btnHup, h.btnHdn] = i_spin(P, 0.52, y, 'Tinggi', i_g(proj.display,'heightCm',5), fig);
    y = y - 0.044;
    h.edDPI = i_lbledit(P, 0.04, y, 'DPI', i_g(proj.display,'dpi',300));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 y 0.44 0.036],'String','↻ Terapkan & render','FontSize',8, ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.90], ...
        'Callback',@(s,e) i_apply(fig));
    y = y - 0.050;

    % == Sumbu ==
    y = i_sec(P, y, 'Sumbu');
    % Judul default = NAMA EKSPERIMEN (proj.source.base) — bisa diedit bebas.
    titleDflt = '';
    if isstruct(proj.source) && isfield(proj.source,'base') && ~isempty(proj.source.base)
        titleDflt = char(proj.source.base);
    end
    if isempty(titleDflt), titleDflt = base; end
    h.edTitle = i_lbledit(P, 0.04, y, 'Judul', i_gs(proj.display,'title',titleDflt), 0.20, 0.74);
    y = y - 0.044;
    h.edXLabel = i_lbledit(P, 0.04, y, 'Label X', i_gs(proj.display,'xlabel','Frame'), 0.30, 0.62);
    y = y - 0.044;
    h.edYLabel = i_lbledit(P, 0.04, y, 'Label Y', i_gs(proj.display,'ylabel','|V| (px/frame)'), 0.30, 0.62);
    y = y - 0.046;

    % --- Kalibrasi sumbu-Y dunia nyata: px/frame -> cm/s (3 OPSI, paritas GRAINEXPORT) ---
    yc = struct(); if isfield(proj,'ycal') && isstruct(proj.ycal), yc = proj.ycal; end
    tm = struct(); if isfield(proj,'timing') && isstruct(proj.timing), tm = proj.timing; end
    h.btnYUnit = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 y 0.92 0.034],'FontSize',8,'String','Sumbu-Y: px/frame (mentah)','Value',0, ...
        'TooltipString',['Konversi |V| px/frame -> cm/s memakai multiplier dari salah satu 3 sumber ' ...
        'di bawah. Bila multiplier tak terhitung, tetap px/frame (jujur).'], ...
        'Callback',@(s,e) i_onYUnit(fig));
    if isfield(yc,'enabled') && isscalar(yc.enabled) && logical(yc.enabled)
        set(h.btnYUnit,'Value',1,'String','Sumbu-Y: cm/s (terkalibrasi)');
    end
    y = y - 0.038;
    % SUMBER multiplier (3 opsi) — default 'geom'
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.16 0.028], ...
        'String','Sumber','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    srcList = {'1) Manual cm/px ÷ dt','2) Kalibrasi calxy','3) Geometri X0/X1 + dt'};
    srcVal = 3; sc = i_gs(yc,'source','geom');
    if strcmpi(sc,'manual'), srcVal=1; elseif strcmpi(sc,'calxy'), srcVal=2; end
    h.popYSrc = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.20 y 0.55 0.030],'String',srcList,'Value',srcVal,'FontSize',8, ...
        'Callback',@(s,e) i_onAutoMult(fig));
    h.btnAutoMult = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.76 y 0.20 0.030],'String','⚙ Hitung','FontSize',8,'FontWeight','bold', ...
        'BackgroundColor',[0.90 0.94 0.98],'TooltipString','Hitung multiplier cm/s dari sumber terpilih.', ...
        'Callback',@(s,e) i_onAutoMult(fig));
    y = y - 0.038;
    % dt (s/frame) [opsi 1/2/3] + cm/px [opsi 1] + ⤓EXIF
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.14 0.028], ...
        'String','dt(s)','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    dt0 = i_g(tm,'dtSec',NaN);
    h.edDt = i_edit(P, 0.18, y, dt0, 0.16);
    set(h.edDt,'Callback',@(s,e) i_onAutoMult(fig));
    h.btnUseExif = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 y 0.13 0.030],'String','⤓ EXIF','FontSize',7, ...
        'TooltipString','Pakai dt median EXIF (bila ada dari ekspor GRAIN4).', ...
        'Callback',@(s,e) i_onUseExifDt(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.50 y 0.14 0.028], ...
        'String','cm/px','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edCmPx = i_edit(P, 0.63 - 0.01, y, i_g(yc,'cmPerPx',NaN), 0.16);
    set(h.edCmPx,'Callback',@(s,e) i_onAutoMult(fig),'TooltipString','Skala spasial cm/px (opsi 1 manual).');
    % Satuan TERKUNCI ke cm/s (label, bukan input) — multiplier memang -> cm/s.
    h.edYUnit = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.80 y 0.16 0.028],'String','cm/s','BackgroundColor',WHITE, ...
        'FontSize',8,'FontWeight','bold','HorizontalAlignment','center', ...
        'ForegroundColor',[0.2 0.35 0.55],'TooltipString','Satuan sumbu-Y terkunci = cm/s.');
    y = y - 0.036;
    % multiplier (hasil/override, default 0.005) + info
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.20 0.028], ...
        'String','×mult','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edMult = i_edit(P, 0.20, y, i_g(yc,'velMult',0.005), 0.25);
    set(h.edMult,'Callback',@(s,e) i_apply(fig),'TooltipString','Pengali |V| px/frame -> cm/s (boleh override).');
    y = y - 0.028;
    h.txtMultInfo = uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.92 0.026], ...
        'String',i_yInfoText(tm), 'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',7, ...
        'ForegroundColor',[0.30 0.35 0.55]);
    y = y - 0.038;

    h.btnXUnit = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.04 y 0.92 0.034],'FontSize',8, ...
        'String','Sumbu-X: Frame','Value',0, ...
        'TooltipString','Frame (akuisisi) <-> Strain kumulatif %% (paper).', ...
        'Callback',@(s,e) i_onXUnit(fig));
    if strcmpi(i_gs(proj.display,'xUnit','frame'),'strain')
        set(h.btnXUnit,'Value',1,'String','Sumbu-X: Strain %');
    end
    y = y - 0.044;
    % limit X
    h.chkXAuto = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 y 0.30 0.030],'String','X auto','Value',i_g(proj.display,'xAuto',1), ...
        'BackgroundColor',WHITE,'FontSize',8,'Callback',@(s,e) i_apply(fig));
    h.edXmin = i_edit(P, 0.36, y, i_g(proj.display,'xmin',NaN), 0.28);
    h.edXmax = i_edit(P, 0.66, y, i_g(proj.display,'xmax',NaN), 0.28);
    y = y - 0.040;
    % limit Y
    h.chkYAuto = uicontrol('Parent',P,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 y 0.30 0.030],'String','Y auto','Value',i_g(proj.display,'yAuto',1), ...
        'BackgroundColor',WHITE,'FontSize',8,'Callback',@(s,e) i_apply(fig));
    h.edYmin = i_edit(P, 0.36, y, i_g(proj.display,'ymin',NaN), 0.28);
    h.edYmax = i_edit(P, 0.66, y, i_g(proj.display,'ymax',NaN), 0.28);
    y = y - 0.050;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.45 0.040],'String','↻ Terapkan & render','FontSize',9, ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.90],'Callback',@(s,e) i_apply(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 y 0.45 0.040],'String','🖼 Export single (uji)','FontSize',9, ...
        'FontWeight','bold','BackgroundColor',[0.88 0.92 0.98], ...
        'TooltipString',['Ekspor 1 JPEG proyek aktif (uji setelan) ke folder baru ' ...
        'AXPOT_jpg/AXPOT_<ts>/ pakai setelan tab① ini.'], ...
        'Callback',@(s,e) i_onExportSingle(fig));

    % == Tab ② "Layer & Output" ==
    h = i_buildLayerTab(h, h.tabLayer, fig, proj, base);

    % == Tab ③ "Assign HW" (navigasi HW + seleksi/sorot kurva + trim/assign/buang) ==
    h = i_buildEditTab(h, h.tabEdit, fig);
    h = i_refreshHWLabel(h);

    % == Tab ④ "Batch Export" ==
    h = i_buildBatchTab(h, h.tabBatch, fig);

    % == 3 TOMBOL MELAYANG (overlay paling atas) di sudut KIRI-BAWAH ==
    %   Diparent LANGSUNG ke figure (bukan panel) & dibuat TERAKHIR -> di atas
    %   semua objek. Susun horizontal: Save(hijau) · Save&Close(oranye) · Close(merah).
    h = i_buildFloatButtons(h, fig);
end


function h = i_buildFloatButtons(h, fig)
%I_BUILDFLOATBUTTONS  Tombol overlay melayang di sudut kiri-bawah figure:
%   📂 Open · 💾 Save · 💾✖ Save & Close · ✖ Close.
    bw = 0.085; bh = 0.045; x0 = 0.006; yb = 0.008; gap = 0.004;
    x = x0;
    h.btnFloatOpen = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[x yb bw bh],'String','📂 Open','FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.20 0.45 0.75],'ForegroundColor',[1 1 1], ...
        'TooltipString','Buka proyek AX POT lain (*_axpot.mat) di jendela ini.', ...
        'Callback',@(s,e) i_onOpenProject(fig));
    x = x + bw + gap;
    h.btnFloatSave = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[x yb bw bh],'String','💾 Save','FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.20 0.65 0.25],'ForegroundColor',[1 1 1], ...
        'TooltipString','Simpan proyek (round-trip) — jendela tetap terbuka.', ...
        'Callback',@(s,e) i_saveProject(fig));
    x = x + bw + gap;
    h.btnFloatSaveClose = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[x yb bw+0.03 bh],'String','💾✖ Save & Close','FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.95 0.55 0.10],'ForegroundColor',[1 1 1], ...
        'TooltipString','Simpan proyek lalu TUTUP jendela.', ...
        'Callback',@(s,e) i_onSaveClose(fig));
    x = x + bw + 0.03 + gap;
    h.btnFloatClose = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[x yb bw bh],'String','✖ Close','FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.80 0.15 0.15],'ForegroundColor',[1 1 1], ...
        'TooltipString','Tutup tanpa menyimpan.', ...
        'Callback',@(s,e) i_onCloseOnly(fig));
end

function i_onOpenProject(fig)
%I_ONOPENPROJECT  Load proyek *_axpot.mat lain & ganti isi jendela INI (tanpa
%   tutup app). Minimize dulu sebelum dialog (aturan global).
    h = guidata(fig);
    % Hook tes: bila ada override path di appdata, lewati dialog (uigetfile blok
    % di headless). Hanya dipakai test; produksi tetap pakai dialog.
    if isappdata(fig,'grainaxpotOpenOverride')
        f = getappdata(fig,'grainaxpotOpenOverride'); rmappdata(fig,'grainaxpotOpenOverride');
        if ~isempty(f) && ischar(f), i_loadProjectInto(fig, f); end
        return;
    end
    start = '';
    if ~isempty(h.projFile), start = fileparts(h.projFile); end
    i_minimizeForDialog(fig);
    restore = onCleanup(@() i_restoreAfterDialog(fig)); %#ok<NASGU>
    if isempty(start)
        [fn, fp] = uigetfile({'*_axpot.mat','Proyek AX POT (*_axpot.mat)'; '*.mat','MAT'}, ...
            'Buka proyek AX POT');
    else
        [fn, fp] = uigetfile({'*_axpot.mat','Proyek AX POT (*_axpot.mat)'; '*.mat','MAT'}, ...
            'Buka proyek AX POT', fullfile(start, filesep));
    end
    if isequal(fn,0), return; end
    i_loadProjectInto(fig, fullfile(fp, fn));
end

function ok = i_loadProjectInto(fig, newFile)
%I_LOADPROJECTINTO  Muat proyek baru & bangun ulang UI di figur yg SAMA. Dipakai
%   i_onOpenProject (setelah dialog) + bisa diuji langsung tanpa dialog.
    ok = false; h = guidata(fig);
    try
        proj = pivcore.io.axpotProject.load(newFile);
        if ~isstruct(proj.display) || isempty(fieldnames(proj.display))
            d = i_loadFolderDefault(fileparts(newFile));
            if isempty(d), d = i_loadLayoutPref(); end
            if ~isempty(d), proj.display = d; end
        end
        proj.display = i_migrateLabelsEN(proj.display);
        proj = pivcore.io.axpotProject.deriveFromRecs(proj);
    catch ME
        if isfield(h,'txtStatus') && ishghandle(h.txtStatus)
            set(h.txtStatus,'String',sprintf('GAGAL buka: %s', ME.message),'ForegroundColor',[0.7 0 0]);
        end
        return;
    end
    % Ganti isi jendela: hapus semua anak, bangun ulang di figur yg sama.
    batch = {}; if isfield(h,'batchFiles'), batch = h.batchFiles; end   % pertahankan antrian batch
    delete(allchild(fig));
    h2 = i_buildInto(fig, newFile, proj);
    h2.batchFiles = batch;
    guidata(fig, h2);
    i_loadDisplay(fig); i_batchRefresh(h2); i_apply(fig);
    set(h2.txtStatus,'String',sprintf('Dibuka: %s', i_bn(newFile)),'ForegroundColor',[0.2 0.4 0.2]);
    ok = true;
end

function i_onSaveClose(fig)
    i_saveProject(fig);
    if ishghandle(fig), delete(fig); end
end

function i_onCloseOnly(fig)
    if ishghandle(fig), delete(fig); end
end


% =====================================================================
% Tab ② "Layer & Output" — layer ditampilkan + titik informasi + ekspor
% =====================================================================
function h = i_buildLayerTab(h, P, fig, proj, base)
    WHITE = [1 1 1]; y = 0.972;

    % == Layer ==
    y = i_sec(P, y, 'Layer ditampilkan');
    h.chkHW  = i_chk(P, 0.04, y, 'Kurva HW teridentifikasi', i_g(proj.display,'showHW',1), fig);
    y = y - 0.034;
    h.chkRaw = i_chk(P, 0.04, y, 'Kurva mentah (semua)', i_g(proj.display,'showRaw',1), fig);
    y = y - 0.034;
    h.chkHWLab = i_chk(P, 0.04, y, 'Label HW#', i_g(proj.display,'hwLabels',1), fig);
    h.chkPts = i_chk(P, 0.52, y, 'Titik POI', i_g(proj.display,'points',1), fig);
    y = y - 0.034;
    h.chkInd = i_chk(P, 0.04, y, 'Garis indenter (max)', i_g(proj.display,'indenter',1), fig);
    y = y - 0.040;
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.30 0.028], ...
        'String','Garis frame:','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edFrameLines = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.34 y 0.50 0.030],'String',i_gs(proj.display,'frameLines',''), ...
        'BackgroundColor',WHITE,'FontSize',8,'HorizontalAlignment','left', ...
        'TooltipString','Daftar frame (pisah koma) -> garis tegak putus-putus. Mis: 12,40,77');
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.85 y 0.11 0.030],'String','↻','FontSize',8,'Callback',@(s,e) i_apply(fig));
    y = y - 0.050;

    % == Titik informasi (anotasi) ==
    y = i_sec(P, y, 'Titik informasi (anotasi → GRAIN)');
    h.tblInfo = uitable('Parent',P,'Units','normalized','Position',[0.04 y-0.18 0.92 0.18], ...
        'ColumnName',{'Frame','Nilai Y','Label'}, 'ColumnEditable',[true true true], ...
        'ColumnWidth',{60 70 170}, 'FontSize',8, 'RowName',[], ...
        'CellEditCallback',@(s,e) i_onInfoEdit(fig));
    y = y - 0.190;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.30 0.034],'String','➕ Titik','FontSize',8, ...
        'BackgroundColor',[0.90 0.94 0.98],'Callback',@(s,e) i_onInfoAdd(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 y 0.30 0.034],'String','🗑 Hapus','FontSize',8, ...
        'ForegroundColor',[0.7 0 0],'Callback',@(s,e) i_onInfoDel(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 y 0.30 0.034],'String','↻ Render','FontSize',8, ...
        'Callback',@(s,e) i_apply(fig));
    y = y - 0.052;

    % == Output ==
    y = i_sec(P, y, 'Output raster (Corel) + JSON');
    h.edName = i_lbledit(P, 0.04, y, 'Nama', i_gs(proj.display,'outName',base), 0.20, 0.74);
    y = y - 0.050;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.30 0.040],'String','🖼 PNG','FontWeight','bold','FontSize',8, ...
        'BackgroundColor',[0.88 0.92 0.98],'Callback',@(s,e) i_export(fig,'png'));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 y 0.30 0.040],'String','🖼 JPEG','FontWeight','bold','FontSize',8, ...
        'BackgroundColor',[0.88 0.92 0.98],'Callback',@(s,e) i_export(fig,'jpg'));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 y 0.30 0.040],'String','📦 Semua','FontWeight','bold','FontSize',8, ...
        'BackgroundColor',[0.86 0.90 0.96],'Callback',@(s,e) i_export(fig,'all'));
    y = y - 0.050;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.28 0.038],'String','{ } JSON','FontSize',8, ...
        'Callback',@(s,e) i_export(fig,'json'));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.34 y 0.34 0.038],'String','💾 Simpan proyek','FontSize',8, ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.90], ...
        'TooltipString','Tulis setelan tampilan + titik informasi balik ke <base>_axpot.mat (round-trip).', ...
        'Callback',@(s,e) i_saveProject(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.70 y 0.26 0.038],'String','⭐ Default folder','FontSize',8, ...
        'BackgroundColor',[0.98 0.96 0.86], ...
        'TooltipString',['Simpan SEMUA setelan tata letak sbg DEFAULT FOLDER ini ' ...
        '(_axpot_defaults.json) — dipakai otomatis tiap buka proyek AX POT lain di ' ...
        'folder yg sama, lintas-sesi. (+ pref global sbg cadangan.)'], ...
        'Callback',@(s,e) i_saveLayoutDefault(fig));
    y = y - 0.046;
    h.txtStatus = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.030],'String',sprintf('proyek: %d kurva · %d HW · nF=%d', ...
        numel(proj.curves), numel(proj.hw), proj.nFrames), ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.2 0.4 0.2]);

    h = i_fillInfoTable(h);   % isi tabel info awal
end

function h = i_refreshHWLabel(h)
%I_REFRESHHWLABEL  Perbarui teks "HW: …" sesuai jumlah HW teridentifikasi.
    if ~isfield(h,'txtHW') || ~ishghandle(h.txtHW), return; end
    nums = [];
    if isfield(h.proj,'recs') && ~isempty(h.proj.recs)
        nums = pivcore.pot.hwLabel.hwNumbers(pivcore.pot.records.normalize(h.proj.recs));
    end
    if isempty(nums)
        set(h.txtHW,'String','HW: — (belum ada label HW)','ForegroundColor',[0.5 0.5 0.5]);
    elseif isfinite(h.activeHW) && any(nums==h.activeHW)
        cur = find(nums==h.activeHW,1);
        set(h.txtHW,'String',sprintf('HW: HW-%d  (%d/%d)', h.activeHW, cur, numel(nums)), ...
            'ForegroundColor',[0.15 0.30 0.55]);
    else
        set(h.txtHW,'String',sprintf('HW: %d teridentifikasi — tekan Next ▶', numel(nums)), ...
            'ForegroundColor',[0.15 0.30 0.55]);
    end
end


% =====================================================================
% Tab ④ "Batch Export" — banyak _axpot.mat -> JPEG dgn SETELAN tab① aktif.
%   Output: AXPOT_jpg/AXPOT_<ts>/AXPOT_<exp>_<ts>.jpg
% =====================================================================
function h = i_buildBatchTab(h, P, fig)
%I_BUILDBATCHTAB  Tata letak KOORDINAT ABSOLUT (tak tergantung tinggi jendela)
%   supaya tombol EXPORT SEMUA SELALU terlihat (bug dulu: tombol ketiban/keluar
%   saat jendela tak maximized).
    WHITE = [1 1 1];
    % header + petunjuk
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.02 0.955 0.96 0.030], ...
        'String','Batch Export (banyak proyek AX POT)','HorizontalAlignment','left', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.35]);
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 0.900 0.92 0.050], ...
        'String',['Tambah berkas *_axpot.mat → render pakai SETELAN tab① (lebar/tinggi/DPI/' ...
        'sumbu/×mult). Kalibrasi-Y geom per-file. Output JPEG.'], ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.35 0.35 0.4]);
    % TOMBOL UTAMA di ATAS (selalu terlihat) ---
    h.btnBatchRun = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.840 0.92 0.050],'String','📦 EXPORT SEMUA (JPEG)','FontSize',11, ...
        'FontWeight','bold','BackgroundColor',[0.80 0.90 0.80], ...
        'TooltipString','Render tiap berkas ke JPEG dlm SATU folder baru AXPOT_jpg/AXPOT_<ts>/.', ...
        'Callback',@(s,e) i_onBatchRun(fig));
    % aksi antrian
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.792 0.45 0.040],'String','➕ Tambah berkas…','FontSize',9, ...
        'BackgroundColor',[0.90 0.94 0.98],'Callback',@(s,e) i_onBatchAdd(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.792 0.21 0.040],'String','✚ proyek ini','FontSize',8, ...
        'TooltipString','Tambahkan berkas proyek yg sedang dibuka.', ...
        'Callback',@(s,e) i_onBatchAddCurrent(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.73 0.792 0.23 0.040],'String','🗑 Kosongkan','FontSize',8, ...
        'ForegroundColor',[0.7 0 0],'Callback',@(s,e) i_onBatchClear(fig));
    % status
    h.txtBatch = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 0.760 0.92 0.026],'String','0 berkas dalam antrian.', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.2 0.4 0.2]);
    % daftar antrian (mengisi sisa ke bawah)
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 0.728 0.92 0.024], ...
        'String','Antrian:','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.lstBatch = uicontrol('Parent',P,'Style','listbox','Units','normalized', ...
        'Position',[0.04 0.04 0.92 0.685],'String',{},'Max',2,'Min',0,'FontSize',8, ...
        'TooltipString','Daftar proyek AX POT yg akan diekspor.');
    h.batchFiles = {};
end

function i_batchRefresh(h)
    n = numel(h.batchFiles); names = cell(n,1);
    for k=1:n, [~,b,e]=fileparts(h.batchFiles{k}); names{k}=[b e]; end
    set(h.lstBatch,'String',names,'Value',min(get(h.lstBatch,'Value'),max(n,1)));
    set(h.txtBatch,'String',sprintf('%d berkas dalam antrian.', n),'ForegroundColor',[0.2 0.4 0.2]);
end

function i_onBatchAdd(fig)
    h = guidata(fig);
    i_minimizeForDialog(fig);
    restore = onCleanup(@() i_restoreAfterDialog(fig)); %#ok<NASGU>
    [fn, fp] = uigetfile({'*_axpot.mat','Proyek AX POT (*_axpot.mat)'; '*.mat','MAT'}, ...
        'Pilih proyek AX POT (boleh banyak)', 'MultiSelect','on');
    if isequal(fn,0), return; end
    if ischar(fn), fn = {fn}; end
    for k=1:numel(fn)
        f = fullfile(fp, fn{k});
        if ~any(strcmp(h.batchFiles, f)), h.batchFiles{end+1} = f; end
    end
    guidata(fig, h); i_batchRefresh(h);
end

function i_onBatchAddCurrent(fig)
    h = guidata(fig);
    if ~isempty(h.projFile) && ~any(strcmp(h.batchFiles, h.projFile))
        h.batchFiles{end+1} = h.projFile; guidata(fig, h);
    end
    i_batchRefresh(h);
end

function i_onBatchClear(fig)
    h = guidata(fig); h.batchFiles = {}; guidata(fig, h); i_batchRefresh(h);
end

function i_onBatchRun(fig)
%I_ONBATCHRUN  Render SEMUA berkas antrian -> JPEG dlm 1 folder baru ber-ts,
%   pakai SETELAN tab① aktif (o). Kalibrasi-Y geom per-file via deriveFromRecs.
    i_apply(fig); h = guidata(fig); o = i_readOpts(h);
    files = h.batchFiles;
    if isempty(files)
        set(h.txtBatch,'String','Antrian kosong — tambah berkas dulu.','ForegroundColor',[0.6 0.4 0]); return;
    end
    ts = i_axpotStamp();
    parent = fileparts(files{1});   % folder berkas pertama -> AXPOT_jpg di situ
    try
        outDir = i_makeExportFolder(parent, ts);
    catch ME
        set(h.txtBatch,'String',sprintf('GAGAL buat folder: %s', ME.message),'ForegroundColor',[0.7 0 0]); return;
    end
    nOk = 0; nFail = 0; fails = {};
    for k = 1:numel(files)
        set(h.txtBatch,'String',sprintf('Render %d/%d…', k, numel(files)),'ForegroundColor',[0.2 0.3 0.6]);
        drawnow;
        try
            proj = pivcore.io.axpotProject.load(files{k});
            proj = pivcore.io.axpotProject.deriveFromRecs(proj);   % turunan + kalibrasi geom per-file
            fp = fullfile(outDir, i_axpotFileName(proj, ts));
            if i_renderProjToJpeg(proj, o, fp), nOk = nOk + 1;
            else, nFail = nFail + 1; fails{end+1} = files{k}; end %#ok<AGROW>
        catch
            nFail = nFail + 1; fails{end+1} = files{k}; %#ok<AGROW>
        end
    end
    msg = sprintf('Batch ✓ %d JPEG → AXPOT_jpg/AXPOT_%s/', nOk, ts);
    if nFail>0, msg = sprintf('%s  (%d gagal)', msg, nFail); end
    set(h.txtBatch,'String',msg,'ForegroundColor',i_ternary(nFail==0,[0.2 0.4 0.2],[0.6 0.4 0]));
end


% =====================================================================
% Tab "Edit kurva" — semua aksi atas kurva spt di GRAIN4 (sumber = proj.recs)
% =====================================================================
function h = i_buildEditTab(h, P, fig)
    WHITE = [1 1 1]; y = 0.972;

    % == Navigasi HW aktif (◀ / ▶ lingkar) — seperti GRAIN4 ==
    y = i_sec(P, y, 'HW aktif');
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.16 0.034],'String','◀ Prev','FontSize',8, ...
        'TooltipString','HW aktif sebelumnya (lingkar).','Callback',@(s,e) i_onStepHW(fig,-1));
    h.txtHW = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.21 y 0.56 0.030],'String','HW: —','HorizontalAlignment','center', ...
        'FontWeight','bold','BackgroundColor',[0.95 0.97 1],'FontSize',9,'ForegroundColor',[0.15 0.30 0.55]);
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.78 y 0.18 0.034],'String','Next ▶','FontSize',8,'FontWeight','bold', ...
        'TooltipString','HW aktif berikutnya (lingkar) — sorot kurvanya merah.','Callback',@(s,e) i_onStepHW(fig,+1));
    y = y - 0.048;

    y = i_sec(P, y, 'Kurva POT (sumber editan)');
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.92 0.052], ...
        'String',['Klik baris (multi: Ctrl/Shift) → kurva di-SOROT MERAH tebal di kanvas. ' ...
        'Lalu pakai aksi di bawah. Semua non-destruktif. Status: ✂=trim, 🗑=dibuang.'], ...
        'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.35 0.35 0.4]);
    y = y - 0.060;
    h.tblCurves = uitable('Parent',P,'Units','normalized','Position',[0.04 y-0.34 0.92 0.34], ...
        'ColumnName',{'#','posPx','Label','St'}, 'ColumnEditable',[false false false false], ...
        'ColumnWidth',{34 56 120 34}, 'FontSize',8, 'RowName',[], ...
        'CellSelectionCallback',@(s,e) i_onCurveSel(fig,e));
    h.selCurveRows = [];
    y = y - 0.36;

    % --- Trim / buang ---
    y = i_sec(P, y, 'Trim & buang (max indenter)');
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.46 0.038],'String','✂ Trim → max indenter','FontSize',8, ...
        'BackgroundColor',[0.92 0.95 0.90], ...
        'TooltipString','Potong kurva terpilih di titik sentuh max indenter (buang fase menurun).', ...
        'Callback',@(s,e) i_onTrim(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 y 0.44 0.038],'String','↩ Batal trim','FontSize',8, ...
        'Callback',@(s,e) i_onUntrim(fig));
    y = y - 0.048;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.46 0.038],'String','🗑 Buang kurva','FontSize',8, ...
        'ForegroundColor',[0.7 0 0], ...
        'TooltipString','Buang kurva terpilih (untuk kurva gagal naik / nyangkut). Non-destruktif.', ...
        'Callback',@(s,e) i_onExclude(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 y 0.44 0.038],'String','♻ Pulih kurva','FontSize',8, ...
        'Callback',@(s,e) i_onRestore(fig));
    y = y - 0.056;

    % --- Assign HW ---
    y = i_sec(P, y, 'Assign label (HW / F / F0 / FFW)');
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.04 y 0.16 0.030], ...
        'String','Tipe','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.popType = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.20 y 0.28 0.032],'String',{'HW','F','F0','FFW'},'FontSize',8, ...
        'Callback',@(s,e) i_onTypeChange(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.52 y 0.16 0.030], ...
        'String','No.','HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edNum = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.66 y 0.30 0.032],'String','1','BackgroundColor',WHITE,'FontSize',8, ...
        'HorizontalAlignment','left','TooltipString','Nomor HW/F (diabaikan utk F0/FFW).');
    y = y - 0.044;
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.46 0.038],'String','🏷 Assign ke terpilih','FontSize',8, ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.98], ...
        'TooltipString','Beri label tipe+nomor ke SEMUA kurva terpilih (group HW = beberapa kurva nomor sama).', ...
        'Callback',@(s,e) i_onAssign(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 y 0.44 0.038],'String','✖ Lepas label','FontSize',8, ...
        'Callback',@(s,e) i_onUnassign(fig));
    y = y - 0.050;
    % --- Pipeline ke GRAIN4 (eksplisit) ---
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 y 0.92 0.040],'String','🔗 Kirim assign → GRAIN4 (_autopot)','FontSize',8, ...
        'FontWeight','bold','BackgroundColor',[0.92 0.90 0.98], ...
        'TooltipString',['Tulis label HW/F/F0/FFW editan ini ke berkas sesi GRAIN4 supaya ' ...
        'terbaca di GRAIN4 (mengubah data GRAIN4 — konfirmasi dulu; garis PSG tak disentuh).'], ...
        'Callback',@(s,e) i_onSyncToPab4(fig));
    y = y - 0.052;

    h.txtEdit = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.060],'String','', 'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.2 0.4 0.2]);

    h = i_fillCurveTable(h);
end


% =====================================================================
% Apply: baca kontrol -> opts -> render preview (WYSIWYG cm)
% =====================================================================
function o = i_readOpts(h)
    o = struct();
    o.widthCm  = i_num(get(h.edW,'String'), 28);
    o.heightCm = i_num(get(h.edH,'String'), 5);
    o.dpi      = i_num(get(h.edDPI,'String'), 300);
    o.title    = strtrim(char(get(h.edTitle,'String')));
    o.xlabel   = strtrim(char(get(h.edXLabel,'String')));
    o.ylabel   = strtrim(char(get(h.edYLabel,'String')));
    o.xUnit    = 'frame'; if get(h.btnXUnit,'Value')==1, o.xUnit = 'strain'; end
    o.xAuto    = get(h.chkXAuto,'Value')==1;
    o.yAuto    = get(h.chkYAuto,'Value')==1;
    o.xmin     = i_num(get(h.edXmin,'String'), NaN);
    o.xmax     = i_num(get(h.edXmax,'String'), NaN);
    o.ymin     = i_num(get(h.edYmin,'String'), NaN);
    o.ymax     = i_num(get(h.edYmax,'String'), NaN);
    o.showHW   = get(h.chkHW,'Value')==1;
    o.showRaw  = get(h.chkRaw,'Value')==1;
    o.hwLabels = get(h.chkHWLab,'Value')==1;
    o.points   = get(h.chkPts,'Value')==1;
    o.indenter = get(h.chkInd,'Value')==1;
    o.frameLines = i_parseList(get(h.edFrameLines,'String'));
    o.outName  = i_safeName(get(h.edName,'String'), 'axpot');
    % --- kalibrasi sumbu-Y (px/frame -> cm/s, 3 opsi) ---
    o.yEnabled = isfield(h,'btnYUnit') && get(h.btnYUnit,'Value')==1;
    srcMap = {'manual','calxy','geom'};
    o.ySource = srcMap{get(h.popYSrc,'Value')};
    o.yDtSec   = i_num(get(h.edDt,'String'), NaN);
    o.yCmPx    = i_num(get(h.edCmPx,'String'), NaN);
    o.yMult    = i_num(get(h.edMult,'String'), NaN);
    o.yUnit    = 'cm/s';   % satuan sumbu-Y terkunci
end

function i_apply(fig)
    h = guidata(fig);
    o = i_readOpts(h);
    % sinkronkan kalibrasi Y ke proj (sumber kebenaran utk renderer + round-trip)
    if ~isfield(h.proj,'timing') || ~isstruct(h.proj.timing)
        h.proj.timing = struct('dtSec',NaN,'source','none','medianExifSec',NaN,'nValidExif',0);
    end
    if isfinite(o.yDtSec)   % dt: manual override bila beda EXIF
        med = NaN; if isfield(h.proj.timing,'medianExifSec'), med = h.proj.timing.medianExifSec; end
        h.proj.timing.dtSec = o.yDtSec;
        if isfinite(med) && abs(o.yDtSec - med) < 1e-9, h.proj.timing.source = 'exif';
        else, h.proj.timing.source = 'manual'; end
    end
    h.proj.ycal = struct('source',o.ySource, 'velMult',o.yMult, ...
        'cmPerPx',o.yCmPx, 'unit',o.yUnit, 'enabled',logical(o.yEnabled));
    guidata(fig, h);
    % ukuran kanvas fisik (cm) -> WYSIWYG (UKURAN FISIK px asli). Bila kanvas cm
    % melebihi panel, SKALA TURUN PROPORSIONAL (jaga rasio) supaya muat — JANGAN
    % potong satu dimensi (itu yg bikin preview gepeng ≠ output). Tak memperbesar.
    pp = getpixelposition(h.pnlCanvas);
    cm2px = get(0,'ScreenPixelsPerInch')/2.54;
    wpx = o.widthCm*cm2px; hpx = o.heightCm*cm2px;
    availW = max(pp(3)-16, 20); availH = max(pp(4)-16, 20);
    s = min([availW/wpx, availH/hpx, 1]);   % fit-to-panel jaga rasio, tak memperbesar
    wfit = wpx*s; hfit = hpx*s;
    set(h.ax,'Units','pixels');
    mx = max((pp(3)-wfit)/2, 8); my = max((pp(4)-hfit)/2, 8);
    set(h.ax,'OuterPosition',[mx my wfit hfit]);
    set(h.ax,'Units','centimeters');
    i_drawAxpot(h.ax, h.proj, o);
    h.opts = o; guidata(fig, h);
    i_highlightSel(fig);   % sorot kurva terpilih (merah tebal) di atas render
end


% =====================================================================
% Sorot kurva terpilih MERAH tebal di kanvas (paritas dgn GRAIN4
% grain4Shell.highlightSelPOT). Overlay terpisah (tag selCurve) digambar
% ulang tiap render. Sumber = recs (sumbu-x = frame, di-map ke strain bila
% mode strain aktif).
% =====================================================================
function i_highlightSel(fig)
    h = guidata(fig); ax = h.ax;
    if ~ishghandle(ax), return; end
    try, delete(findall(ax,'Tag','selCurve')); catch, end
    recs = []; if isfield(h.proj,'recs'), recs = h.proj.recs; end
    if isempty(recs), return; end
    rows = i_selCurveRows(h);
    if isempty(rows), return; end
    recs = pivcore.pot.records.normalize(recs);
    nF = max(h.proj.nFrames,1);
    o = []; if isfield(h,'opts'), o = h.opts; end
    useStrain = ~isempty(o) && isfield(o,'xUnit') && strcmpi(o.xUnit,'strain');
    st = h.proj.strainTotalPct;
    if useStrain && ~(isfinite(st) && st~=0 && nF>1), useStrain = false; end
    if useStrain, xmap = @(xf) (xf-1)/(nF-1)*st; else, xmap = @(xf) xf; end
    hs = ishold(ax); hold(ax,'on');
    for r = rows
        if r<1 || r>numel(recs), continue; end
        if pivcore.io.axpotProject.recExcluded(recs(r)), continue; end
        [xv, yv] = pivcore.pot.records.curveXY(recs(r), nF);
        yv = pivcore.io.axpotProject.trimYV(recs(r), yv);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        plot(ax, xmap(xv(g)), yv(g), '-', 'Color',[1 0 0], 'LineWidth',3.0, ...
            'Tag','selCurve', 'HitTest','off', 'PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end


% =====================================================================
% RENDERER BERSAMA (preview & ekspor) — paritas WYSIWYG
% =====================================================================
function i_drawAxpot(ax, proj, o)
    cla(ax,'reset');
    set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top','FontSize',9);
    hold(ax,'on');
    nF = max(proj.nFrames,1);
    useStrain = strcmpi(o.xUnit,'strain');
    st = proj.strainTotalPct;
    if useStrain && ~(isfinite(st) && st~=0 && nF>1), useStrain = false; end
    if useStrain, xmap = @(xf) (xf-1)/(nF-1)*st; else, xmap = @(xf) xf; end
    % konversi sumbu-Y: px/frame -> mm/s (bila kalibrasi lengkap & diaktifkan).
    % yf=1 & label asli bila tak lengkap (jujur). ymap dipakai utk SEMUA Y.
    [yf, yLabAuto, yOk] = pivcore.io.axpotProject.yFactor(proj, o.ylabel);
    ymap = @(yv) yv * yf;

    ymin = inf; ymax = -inf;
    % --- kurva (mentah + berlabel) ---
    C = proj.curves;
    for k = 1:numel(C)
        c = C(k);
        if c.excluded, continue; end
        isLab = ~isempty(c.label);
        if isLab && ~o.showHW, continue; end
        if ~isLab && ~o.showRaw, continue; end
        yv = c.values; if isempty(yv), continue; end
        xv = 1:numel(yv); g = isfinite(yv);
        if ~any(g), continue; end
        lw = 0.6; if isLab, lw = 2.4; end
        plot(ax, xmap(xv(g)), ymap(yv(g)), '-', 'Color',c.color, 'LineWidth',lw);
        ymin = min(ymin,min(ymap(yv(g)))); ymax = max(ymax,max(ymap(yv(g))));
    end
    % --- indenter ---
    if o.indenter && ~isempty(proj.indenter)
        env = proj.indenter; xe = 1:numel(env); ge = isfinite(env);
        if any(ge)
            plot(ax, xmap(xe(ge)), ymap(env(ge)), '-', 'Color',[0 0 0], 'LineWidth',3);
            ymin = min(ymin,min(ymap(env(ge)))); ymax = max(ymax,max(ymap(env(ge))));
        end
    end
    % --- titik POI per HW ---
    if o.points
        for k = 1:numel(proj.hw)
            w = proj.hw(k); rep = ymap(w.repValues); if isempty(rep), continue; end
            i_pt(ax, rep, w.startF, 'start', xmap(w.startF));
            i_pt(ax, rep, w.nclF,   'nuc',   xmap(w.nclF));
            i_pt(ax, rep, w.fsrF,   'fsr',   xmap(w.fsrF));
            i_pt(ax, rep, w.endF,   'end',   xmap(w.endF));
        end
    end
    hold(ax,'off');
    % --- label & limit ---
    % Bila Y terkalibrasi (mm/s) & label Y masih default px/frame, pakai label
    % otomatis dari yFactor supaya satuan sumbu JUJUR mengikuti konversi.
    yLab = o.ylabel;
    if yOk && (isempty(yLab) || ~isempty(strfind(lower(yLab),'px')))
        yLab = yLabAuto;
    end
    xlabel(ax, o.xlabel); ylabel(ax, yLab); grid(ax,'on');
    if isfield(o,'title') && ~isempty(o.title)
        title(ax, o.title, 'FontWeight','bold', 'FontSize',11, 'Color',[0.1 0.1 0.2]);
    end
    % Strain bisa NEGATIF (mis. kompresi). Kemajuan FRAME (1→nF) harus selalu
    % terbaca KIRI→KANAN walau nilai strain negatif. xlim wajib menaik, jadi saat
    % strain negatif kita balik arah sumbu (XDir reverse) supaya frame-1 (strain 0)
    % di kiri & frame akhir (paling negatif) di kanan.
    set(ax,'XDir','normal');
    if o.xAuto
        if useStrain
            xlim(ax, sort([0 st]));
            if st < 0, set(ax,'XDir','reverse'); end
        elseif nF>1, xlim(ax,[1 nF]); end
    else
        lo = o.xmin; hi = o.xmax;
        if isfinite(lo) && isfinite(hi) && hi>lo, xlim(ax,[lo hi]); end
        if useStrain && st < 0, set(ax,'XDir','reverse'); end
    end
    if o.yAuto
        if isfinite(ymin) && isfinite(ymax) && ymax>ymin
            pad = 0.05*(ymax-ymin); ylim(ax,[max(0,ymin-pad) ymax+pad]);
        end
    else
        lo = o.ymin; hi = o.ymax;
        if isfinite(lo) && isfinite(hi) && hi>lo, ylim(ax,[lo hi]); end
    end
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    hold(ax,'on');
    % --- label HW# ---
    if o.hwLabels
        for k = 1:numel(proj.hw)
            w = proj.hw(k); rep = w.repValues; if isempty(rep), continue; end
            g = isfinite(rep); if ~any(g), continue; end
            [yp, xp] = max(rep); yp = yp * yf; xpp = xmap(xp);
            if ~(isfinite(xpp) && isfinite(yp)), continue; end
            xpp = min(max(xpp, xl(1)), xl(2));
            text(ax, xpp, yp, sprintf(' %s', w.label), 'Color',[0 0 0], ...
                'BackgroundColor','w','EdgeColor',w.color,'Margin',1, ...
                'FontWeight','bold','FontSize',8, ...
                'HorizontalAlignment','center','VerticalAlignment','bottom');
        end
    end
    % --- garis frame ---
    for fr = o.frameLines(:).'
        if ~(isfinite(fr) && fr>=1 && fr<=nF), continue; end
        xf = xmap(fr);
        plot(ax,[xf xf],yl,'--','Color',[0.45 0.45 0.45],'LineWidth',1.0);
        if useStrain, lab = sprintf(' %.1f%% ', xf); else, lab = sprintf(' f%d ', round(fr)); end
        text(ax, xf, yl(2), lab, 'Color',[0.25 0.25 0.25], ...
            'BackgroundColor','w','EdgeColor',[0.6 0.6 0.6],'Margin',1, ...
            'FontSize',7,'HorizontalAlignment','center','VerticalAlignment','top');
    end
    % --- titik informasi (anotasi) ---
    for k = 1:numel(proj.infoPoints)
        ip = proj.infoPoints(k);
        fr = ip.frame; if ~(isfinite(fr) && fr>=1 && fr<=nF), continue; end
        xf = xmap(fr);
        yv = ip.value;
        if isfinite(yv)
            yv = yv * yf;   % nilai Y tersimpan mentah (px/frame) -> map ke satuan tampilan
        else               % default: nilai indenter di frame itu (map), else atas
            if ~isempty(proj.indenter) && fr<=numel(proj.indenter) && isfinite(proj.indenter(round(fr)))
                yv = proj.indenter(round(fr)) * yf;
            else, yv = yl(2)-0.05*(yl(2)-yl(1));
            end
        end
        col = ip.color; if numel(col)~=3, col=[0.1 0.1 0.1]; end
        plot(ax, xf, yv, 'p', 'MarkerSize',11, 'MarkerEdgeColor',[0 0 0], 'MarkerFaceColor',col, 'LineWidth',0.8);
        if ~isempty(ip.label)
            text(ax, xf, yv, sprintf('  %s', ip.label), 'Color',[0 0 0], ...
                'BackgroundColor',[1 1 0.85],'EdgeColor',col,'Margin',1, ...
                'FontSize',8,'FontWeight','bold','VerticalAlignment','middle','HorizontalAlignment','left');
        end
    end
    hold(ax,'off');
    set(ax,'XLim',xl,'YLim',yl);
end

function i_pt(ax, yvec, f, which, xPlot)
    if ~(isscalar(f) && isfinite(f) && f>=1 && f<=numel(yvec)), return; end
    yv = yvec(round(f)); if ~isfinite(yv), return; end
    if nargin<5 || ~isscalar(xPlot) || ~isfinite(xPlot), xPlot = f; end
    col = pivcore.pot.snapPoints.color(which);
    plot(ax, xPlot, yv, 'o', 'MarkerSize',8, 'LineWidth',1.4, ...
        'MarkerEdgeColor',col, 'MarkerFaceColor','w');
end


% =====================================================================
% Ekspor raster (WYSIWYG offscreen cm) + JSON
% =====================================================================
function i_export(fig, kind)
    h = guidata(fig); o = i_readOpts(h);
    outdir = fileparts(h.projFile);
    name = o.outName;
    didR = false;
    if any(strcmp(kind, {'png','jpg','all'}))
        figs = i_offscreenFig(o);
        cleaner = onCleanup(@() i_safeClose(figs.fig)); %#ok<NASGU>
        i_drawAxpot(figs.ax, h.proj, o);
        list = {}; if any(strcmp(kind,{'png','all'})), list{end+1}='png'; end
        if any(strcmp(kind,{'jpg','all'})), list{end+1}='jpg'; end
        for i=1:numel(list)
            f = fullfile(outdir, [name '.' list{i}]);
            try, exportgraphics(figs.fig, f, 'Resolution', round(o.dpi)); didR=true; catch ME
                set(h.txtStatus,'String',sprintf('GAGAL %s: %s', list{i}, ME.message));
            end
        end
    end
    if any(strcmp(kind, {'json','all'}))
        i_writeJSON(h, o, fullfile(outdir, [name '.json']));
    end
    msg = sprintf('Ekspor "%s": ', name);
    if didR, msg=[msg 'raster ✓ ']; end
    if any(strcmp(kind,{'json','all'})), msg=[msg 'json ✓']; end
    set(h.txtStatus,'String',msg,'ForegroundColor',[0.2 0.4 0.2]);
end

function s = i_offscreenFig(o)
%I_OFFSCREENFIG  Figur OFFSCREEN ukuran fisik cm = WYSIWYG ekspor.
    f = figure('Visible','off','Color','w','Units','centimeters', ...
        'Position',[1 1 o.widthCm o.heightCm],'PaperUnits','centimeters', ...
        'PaperPositionMode','auto');
    ax = axes('Parent',f,'Units','normalized','OuterPosition',[0 0 1 1]);
    s = struct('fig',f,'ax',ax);
end


% =====================================================================
% Konvensi folder + nama berkas ekspor JPEG (single & batch)
%   folder : <parent>/AXPOT_jpg/AXPOT_<ddmmyy>-<HHMMSS>/
%   berkas : AXPOT_<nama_exp>_<ddmmyy>-<HHMMSS>.jpg
% =====================================================================
function ts = i_axpotStamp()
    ts = datestr(now, 'ddmmyy-HHMMSS'); %#ok<TNOW1,DATST>
end

function outDir = i_makeExportFolder(parentDir, ts)
%I_MAKEEXPORTFOLDER  Buat <parent>/AXPOT_jpg/AXPOT_<ts>/ (folder baru per-ekspor).
    base = fullfile(parentDir, 'AXPOT_jpg');
    if ~isfolder(base), mkdir(base); end
    outDir = fullfile(base, sprintf('AXPOT_%s', ts));
    if ~isfolder(outDir), mkdir(outDir); end
end

function nm = i_axpotFileName(proj, ts)
%I_AXPOTFILENAME  AXPOT_<nama_exp>_<ts>.jpg dari nama eksperimen (source.base).
    exp = 'exp';
    if isstruct(proj.source) && isfield(proj.source,'base') && ~isempty(proj.source.base)
        exp = char(proj.source.base);
    end
    exp = i_safeName(exp, 'exp');
    nm = sprintf('AXPOT_%s_%s.jpg', exp, ts);
end

function ok = i_renderProjToJpeg(proj, o, filePath)
%I_RENDERPROJTOJPEG  Render 1 proyek AX POT ke 1 berkas JPEG (WYSIWYG offscreen cm).
    ok = false;
    figs = i_offscreenFig(o);
    cleaner = onCleanup(@() i_safeClose(figs.fig)); %#ok<NASGU>
    try
        i_drawAxpot(figs.ax, proj, o);
        exportgraphics(figs.fig, filePath, 'Resolution', round(o.dpi));
        ok = isfile(filePath);
    catch
        ok = false;
    end
end

function i_onExportSingle(fig)
%I_ONEXPORTSINGLE  Tab① "Export single image (uji)": 1 JPEG proyek aktif ke
%   folder baru AXPOT_jpg/AXPOT_<ts>/ pakai SETELAN tab① saat ini.
    i_apply(fig); h = guidata(fig); o = i_readOpts(h);
    ts = i_axpotStamp();
    parent = fileparts(h.projFile);
    try
        outDir = i_makeExportFolder(parent, ts);
    catch ME
        set(h.txtStatus,'String',sprintf('GAGAL buat folder: %s', ME.message),'ForegroundColor',[0.7 0 0]); return;
    end
    fn = i_axpotFileName(h.proj, ts);
    fp = fullfile(outDir, fn);
    if i_renderProjToJpeg(h.proj, o, fp)
        set(h.txtStatus,'String',sprintf('Single ✓ → %s', fullfile('AXPOT_jpg',['AXPOT_' ts], fn)), ...
            'ForegroundColor',[0.2 0.4 0.2]);
    else
        set(h.txtStatus,'String','GAGAL render single image.','ForegroundColor',[0.7 0 0]);
    end
end

function i_writeJSON(h, o, pth)
%I_WRITEJSON  Sidecar setelan+anotasi (bahan komentar GRAIN). Numerik kurva tetap
%   di .mat; JSON = ringkas + titik informasi.
    d = struct();
    d.formatName = 'GRAIN AXPOT Figure';
    d.source = h.proj.source;
    d.nFrames = h.proj.nFrames;
    d.strainTotalPct = h.proj.strainTotalPct;
    d.display = i_opts2disp(o);
    d.hw = {};
    for k=1:numel(h.proj.hw)
        w = h.proj.hw(k);
        d.hw{end+1} = struct('label',w.label,'startF',w.startF,'nclF',w.nclF, ...
            'fsrF',w.fsrF,'endF',w.endF);
    end
    d.infoPoints = {};
    for k=1:numel(h.proj.infoPoints)
        ip = h.proj.infoPoints(k);
        d.infoPoints{end+1} = struct('frame',ip.frame,'strainPct',ip.strainPct, ...
            'value',ip.value,'label',ip.label,'hw',ip.hw);
    end
    txt = jsonencode(d, 'PrettyPrint', true);
    fid = fopen(pth,'w'); if fid<0, return; end
    fwrite(fid, txt, 'char'); fclose(fid);
end


% =====================================================================
% Titik informasi (anotasi)
% =====================================================================
function h = i_fillInfoTable(h)
    n = numel(h.proj.infoPoints); D = cell(n,3);
    for k=1:n
        ip = h.proj.infoPoints(k);
        D{k,1} = i_orEmptyNum(ip.frame); D{k,2} = i_orEmptyNum(ip.value); D{k,3} = ip.label;
    end
    set(h.tblInfo,'Data',D);
end

function i_onInfoAdd(fig)
    h = guidata(fig);
    nF = max(h.proj.nFrames,1);
    ip = pivcore.io.axpotProject.infoPointStruct(struct('frame',round(nF/2),'label','titik'));
    if isempty(h.proj.infoPoints), h.proj.infoPoints = ip; else, h.proj.infoPoints(end+1) = ip; end
    guidata(fig, h); h = i_fillInfoTable(h); guidata(fig, h); i_apply(fig);
end

function i_onInfoDel(fig)
    h = guidata(fig);
    sel = []; try, sel = h.tblInfo.Selection; catch, end
    if isempty(sel)
        if ~isempty(h.proj.infoPoints), h.proj.infoPoints(end) = []; end   % buang terakhir
    else
        r = unique(sel(:,1)); r = r(r>=1 & r<=numel(h.proj.infoPoints));
        h.proj.infoPoints(r) = [];
    end
    guidata(fig, h); h = i_fillInfoTable(h); guidata(fig, h); i_apply(fig);
end

function i_onInfoEdit(fig)
    h = guidata(fig);
    D = get(h.tblInfo,'Data');
    nF = max(h.proj.nFrames,1);
    P = pivcore.io.axpotProject.infoPointStruct(struct());
    new = P([]);
    for k=1:size(D,1)
        fr = i_num(D{k,1}, NaN); vv = i_num(D{k,2}, NaN); lb = '';
        if size(D,2)>=3 && ~isempty(D{k,3}), lb = char(D{k,3}); end
        sp = NaN;
        if isfinite(fr) && nF>1 && isfinite(h.proj.strainTotalPct)
            sp = (fr-1)/(nF-1)*h.proj.strainTotalPct;
        end
        ip = pivcore.io.axpotProject.infoPointStruct(struct('frame',fr,'value',vv,'label',lb,'strainPct',sp));
        if isempty(new), new = ip; else, new(end+1) = ip; end %#ok<AGROW>
    end
    h.proj.infoPoints = new; guidata(fig, h); i_apply(fig);
end


% =====================================================================
% Persist (round-trip) + display load
% =====================================================================
function d = i_opts2disp(o)
    d = struct('widthCm',o.widthCm,'heightCm',o.heightCm,'dpi',o.dpi, ...
        'title',o.title, ...
        'xlabel',o.xlabel,'ylabel',o.ylabel,'xUnit',o.xUnit, ...
        'xAuto',o.xAuto,'yAuto',o.yAuto,'xmin',o.xmin,'xmax',o.xmax, ...
        'ymin',o.ymin,'ymax',o.ymax,'showHW',o.showHW,'showRaw',o.showRaw, ...
        'hwLabels',o.hwLabels,'points',o.points,'indenter',o.indenter, ...
        'frameLines',o.frameLines,'outName',o.outName);
end

function i_saveProject(fig)
    i_apply(fig);            % pastikan ycal/timing tersinkron ke h.proj sebelum simpan
    h = guidata(fig); o = i_readOpts(h);
    h.proj.display = i_opts2disp(o);
    % frameRefs = frame anotasi (utk montase nanti)
    fr = [];
    for k=1:numel(h.proj.infoPoints)
        if isfinite(h.proj.infoPoints(k).frame), fr(end+1) = round(h.proj.infoPoints(k).frame); end %#ok<AGROW>
    end
    h.proj.frameRefs = unique(fr);
    guidata(fig, h);
    try
        pivcore.io.axpotProject.save(h.projFile, h.proj);
        set(h.txtStatus,'String',sprintf('proyek tersimpan (round-trip) → %s', i_bn(h.projFile)), ...
            'ForegroundColor',[0.2 0.4 0.2]);
    catch ME
        set(h.txtStatus,'String',sprintf('GAGAL simpan proyek: %s', ME.message),'ForegroundColor',[0.7 0 0]);
    end
    % CATATAN: sinkron assignment balik ke GRAIN4 (_autopot) BUKAN side-effect
    % "Simpan proyek" — itu tombol terpisah "🔗 Kirim assign → GRAIN4" (eksplisit,
    % menyentuh data GRAIN4) supaya tak menimpa sesi GRAIN4 tanpa sengaja.
end

function i_onSyncToPab4(fig)
%I_ONSYNCTOGRAIN4  PIPELINE eksplisit: tulis assignment editan GRAINAXPOT ke
%   <base>_autopot.mat (step3Assign + potpsg4.records, read-modify-write — TIDAK
%   menyentuh garis PSG / progres lain) supaya GRAIN4 membaca label HW/F/F0/FFW yg
%   kita ubah di sini. Konfirmasi dulu (menulis data milik GRAIN4).
    h = guidata(fig);
    df = '';
    if isstruct(h.proj.source) && isfield(h.proj.source,'dataFile')
        df = char(h.proj.source.dataFile);
    end
    if isempty(df) || ~isfield(h.proj,'recs') || isempty(h.proj.recs)
        set(h.txtStatus,'String','Tak ada recs / sumber dataFile — sinkron dilewati.', ...
            'ForegroundColor',[0.6 0.4 0]); return;
    end
    if ~pivui.quiet()
        ans1 = questdlg(sprintf(['Tulis assignment HW/F/F0/FFW dari editor ini ke berkas ' ...
            'sesi GRAIN4 (_autopot)?\n\nIni mengubah data milik GRAIN4 (hanya field ' ...
            'assignment; garis PSG & progres lain TIDAK disentuh).']), ...
            'Kirim assign → GRAIN4', 'Ya, kirim', 'Batal', 'Batal');
        if ~strcmp(ans1,'Ya, kirim'), set(h.txtStatus,'String','Sinkron dibatalkan.'); return; end
    end
    try
        recs = pivcore.pot.records.normalize(h.proj.recs);
        a = pivcore.pot.assign.fromRecords(recs);
        env = []; if isfield(h.proj,'indenter'), env = h.proj.indenter; end
        pivcore.io.step1Session.saveAssignments(df, a, recs, env);
        set(h.txtStatus,'String',sprintf('🔗 Assign dikirim ke GRAIN4 (_autopot): %d label. GRAIN4 akan membacanya.', numel(a)), ...
            'ForegroundColor',[0.15 0.30 0.55]);
    catch ME
        set(h.txtStatus,'String',sprintf('GAGAL kirim ke GRAIN4: %s', ME.message),'ForegroundColor',[0.7 0 0]);
    end
end

function i_loadDisplay(fig)
    h = guidata(fig);
    if ~isstruct(h.proj.display) || isempty(fieldnames(h.proj.display)), return; end
    % nilai sudah dipasang saat build via i_g/i_gs; tabel info juga.
    h = i_fillInfoTable(h); guidata(fig, h);
end

function i_onXUnit(fig)
    h = guidata(fig);
    if get(h.btnXUnit,'Value')==1
        set(h.btnXUnit,'String','Sumbu-X: Strain %');
        if strcmp(strtrim(char(get(h.edXLabel,'String'))),'Frame')
            set(h.edXLabel,'String','Cumulative strain (%)');
        end
    else
        set(h.btnXUnit,'String','Sumbu-X: Frame');
        if strcmp(strtrim(char(get(h.edXLabel,'String'))),'Cumulative strain (%)')
            set(h.edXLabel,'String','Frame');
        end
    end
    i_apply(fig);
end

function i_onYUnit(fig)
%I_ONYUNIT  Toggle sumbu-Y px/frame <-> cm/s. ON tapi multiplier tak terhitung ->
%   beri tahu (renderer tetap px/frame — jujur). Auto-hitung multiplier bila kosong.
    h = guidata(fig);
    on = get(h.btnYUnit,'Value')==1;
    if on && ~isfinite(i_num(get(h.edMult,'String'),NaN))
        i_onAutoMult(fig); h = guidata(fig);   % coba isi multiplier dari sumber terpilih
    end
    i_apply(fig); h = guidata(fig);
    [~, ~, ok] = pivcore.io.axpotProject.yFactor(h.proj, 'px');
    if on
        if ok
            unit = 'cm/s'; if isfield(h.proj.ycal,'unit'), unit = h.proj.ycal.unit; end
            set(h.btnYUnit,'String',sprintf('Sumbu-Y: %s (terkalibrasi)', unit));
            set(h.txtStatus,'String','Sumbu-Y dikonversi ke satuan nyata (cm/s).','ForegroundColor',[0.2 0.4 0.2]);
        else
            set(h.btnYUnit,'String','Sumbu-Y: px/frame (multiplier belum ada)');
            set(h.txtStatus,'String','Tekan ⚙ Hitung / isi ×mult dulu. Sementara tetap px/frame.', ...
                'ForegroundColor',[0.6 0.4 0]);
        end
    else
        set(h.btnYUnit,'String','Sumbu-Y: px/frame (mentah)');
    end
end

function i_onAutoMult(fig)
%I_ONAUTOMULT  Hitung multiplier cm/s dari SUMBER terpilih (paritas GRAINEXPORT).
%   Sinkron ycal/timing dulu, panggil engine velMult, tulis ke ×mult + info.
    i_apply(fig); h = guidata(fig);
    srcMap = {'manual','calxy','geom'}; src = srcMap{get(h.popYSrc,'Value')};
    [mult, info, ok] = pivcore.io.axpotProject.velMult(h.proj, src);
    if ok && isfinite(mult) && mult>0
        set(h.edMult,'String',sprintf('%.5g', mult));
        set(h.txtMultInfo,'String', info,'ForegroundColor',[0.2 0.4 0.2]);
        i_apply(fig);   % render dgn multiplier baru
    else
        set(h.txtMultInfo,'String', info,'ForegroundColor',[0.6 0.4 0]);
        set(h.txtStatus,'String',['Multiplier tak terhitung — ' info '.'],'ForegroundColor',[0.6 0.4 0]);
    end
end

function i_onUseExifDt(fig)
%I_ONUSEEXIFDT  Isi dt dgn median EXIF dari proj.timing (bila ada), lalu hitung.
    h = guidata(fig);
    med = NaN;
    if isfield(h.proj,'timing') && isstruct(h.proj.timing) && isfield(h.proj.timing,'medianExifSec')
        med = h.proj.timing.medianExifSec;
    end
    if ~(isscalar(med) && isfinite(med) && med>0)
        set(h.txtStatus,'String','dt EXIF tak tersedia di proyek ini — isi dt manual.', ...
            'ForegroundColor',[0.6 0.4 0]); return;
    end
    set(h.edDt,'String', num2str(med));
    set(h.txtStatus,'String',sprintf('dt = %.3g s (median EXIF).', med),'ForegroundColor',[0.2 0.4 0.2]);
    i_onAutoMult(fig);
end

function s = i_yInfoText(tm)
%I_YINFOTEXT  Teks status sumber dt awal (badge EXIF).
    if isstruct(tm) && isfield(tm,'source') && strcmp(tm.source,'exif') ...
            && isfield(tm,'medianExifSec') && isfinite(tm.medianExifSec)
        nv = 0; if isfield(tm,'nValidExif'), nv = tm.nValidExif; end
        s = sprintf('dt EXIF: %.3g s (%d frame) — tekan ⚙ Hitung', tm.medianExifSec, nv);
    else
        s = 'Pilih sumber, isi dt(+cm/px utk manual), tekan ⚙ Hitung.';
    end
end


% =====================================================================
% WYSIWYG ikut ukuran jendela
% =====================================================================
function i_onResize(fig)
    h = guidata(fig);
    if ~isstruct(h) || ~isfield(h,'ax') || ~ishghandle(h.ax), return; end
    i_apply(fig);
end


% =====================================================================
% Layout DEFAULT sesi (lintas-sesi via setpref)
% =====================================================================
function d = i_loadLayoutPref()
    d = [];
    try
        if ispref('GRAINAXPOT','layout'), d = getpref('GRAINAXPOT','layout'); end
    catch
        d = [];
    end
    if ~isstruct(d), d = []; end
end

function i_saveLayoutDefault(fig)
%I_SAVELAYOUTDEFAULT  Simpan layout sbg DEFAULT lintas-sesi: (1) per-FOLDER
%   eksperimen (<dir>/_axpot_defaults.json) + (2) pref global (fallback). Default
%   folder dipakai lebih dulu saat membuka proyek lain di folder yg sama.
    h = guidata(fig); o = i_readOpts(h);
    d = i_opts2disp(o);
    % Buang field SPESIFIK-EKSPERIMEN: nama output & JUDUL (judul default =
    % nama eksperimen, jangan ikut jadi default folder/global).
    for fld = {'outName','title'}
        if isfield(d, fld{1}), d = rmfield(d, fld{1}); end
    end
    okFolder = i_saveFolderDefault(fileparts(h.projFile), d);
    try, setpref('GRAINAXPOT','layout', d); catch, end
    if okFolder
        set(h.txtStatus,'String','Layout jadi DEFAULT folder ini (+ global) — dipakai proyek lain di folder sama.', ...
            'ForegroundColor',[0.2 0.4 0.2]);
    else
        set(h.txtStatus,'String','Layout disimpan sbg DEFAULT global (gagal tulis default folder).', ...
            'ForegroundColor',[0.6 0.4 0]);
    end
end

function pth = i_folderDefaultPath(dirPath)
    pth = '';
    if isempty(dirPath) || ~ischar(dirPath), return; end
    pth = fullfile(dirPath, '_axpot_defaults.json');
end

function ok = i_saveFolderDefault(dirPath, d)
    ok = false;
    pth = i_folderDefaultPath(dirPath);
    if isempty(pth), return; end
    try
        txt = jsonencode(d, 'PrettyPrint', true);
        fid = fopen(pth, 'w'); if fid<0, return; end
        fwrite(fid, txt, 'char'); fclose(fid); ok = isfile(pth);
    catch
        ok = false;
    end
end

function disp = i_migrateLabelsEN(disp)
%I_MIGRATELABELSEN  Migrasi label sumbu Indonesia -> Inggris (paper EN). Hanya
%   ganti string Indonesia kanonik; label kustom user dibiarkan.
    if ~isstruct(disp), return; end
    map = { 'Strain kumulatif (%)', 'Cumulative strain (%)'; ...
            'Strain kumulatif (%%)','Cumulative strain (%)' };
    if isfield(disp,'xlabel') && ischar(disp.xlabel)
        for k=1:size(map,1)
            if strcmp(strtrim(disp.xlabel), map{k,1}), disp.xlabel = map{k,2}; break; end
        end
    end
end

function d = i_loadFolderDefault(dirPath)
%I_LOADFOLDERDEFAULT  Baca default per-folder (<dir>/_axpot_defaults.json). []
%   bila tak ada/korup.
    d = [];
    pth = i_folderDefaultPath(dirPath);
    if isempty(pth) || ~isfile(pth), return; end
    try
        txt = fileread(pth); d = jsondecode(txt);
        if ~isstruct(d), d = []; end
    catch
        d = [];
    end
end


% =====================================================================
% Edit kurva (trim / assign HW / buang) — sumber = proj.recs
% =====================================================================
function h = i_fillCurveTable(h)
    recs = []; if isfield(h.proj,'recs'), recs = h.proj.recs; end
    if isempty(recs)
        set(h.tblCurves,'Data',{});
        if isfield(h,'txtEdit') && ishghandle(h.txtEdit)
            set(h.txtEdit,'String',['Proyek lama tanpa data kurva mentah (recs). Buka ulang via ' ...
                'GRAIN4 “Save AX POT” versi baru untuk dapat mengedit.'],'ForegroundColor',[0.6 0.4 0]);
        end
        return;
    end
    recs = pivcore.pot.records.normalize(recs);
    n = numel(recs); D = cell(n,4);
    for r = 1:n
        rec = recs(r);
        D{r,1} = r;
        px = NaN; if isfield(rec,'posPx') && isscalar(rec.posPx), px = rec.posPx; end
        D{r,2} = i_orEmptyNum(px);
        D{r,3} = pivcore.pot.records.label(rec);
        st = '';
        if pivcore.io.axpotProject.recExcluded(rec), st = '🗑';
        elseif isfield(rec,'cutManual') && isscalar(rec.cutManual) && logical(rec.cutManual), st = '✂';
        end
        D{r,4} = st;
    end
    set(h.tblCurves,'Data',D);
end

function i_onCurveSel(fig, e)
    h = guidata(fig);
    % CATATAN: `e` di MATLAB nyata = OBJEK event (CellSelectionChangeData), BUKAN
    % struct -> `isfield` SELALU false. Akses properti .Indices langsung (spt GRAIN4
    % onSelectRow). Guard try utk panggilan sintetik/kosong.
    rows = [];
    try
        if ~isempty(e) && ~isempty(e.Indices), rows = unique(e.Indices(:,1)).'; end
    catch
    end
    n = 0; if isfield(h.proj,'recs'), n = numel(h.proj.recs); end
    rows = rows(rows>=1 & rows<=n);
    h.selCurveRows = rows; guidata(fig, h);
    i_highlightSel(fig);   % langsung sorot merah tebal di kanvas
    if isfield(h,'txtEdit') && ishghandle(h.txtEdit)
        if isempty(rows), set(h.txtEdit,'String','(tak ada kurva terpilih)','ForegroundColor',[0.4 0.4 0.4]);
        else, set(h.txtEdit,'String',sprintf('Terpilih %d kurva: #%s', numel(rows), ...
            strjoin(arrayfun(@(x) num2str(x), rows, 'UniformOutput',false), ', ')), ...
            'ForegroundColor',[0.7 0 0]);
        end
    end
end

function i_onStepHW(fig, step)
%I_ONSTEPHW  Pindah HW aktif +1/-1 (lingkar) — paritas GRAIN4. Memilih baris kurva
%   HW itu di tabel + menyorotnya MERAH tebal di kanvas.
    h = guidata(fig);
    recs = []; if isfield(h.proj,'recs'), recs = h.proj.recs; end
    if isempty(recs)
        set(h.txtHW,'String','HW: — (tak ada recs)'); return;
    end
    recs = pivcore.pot.records.normalize(recs);
    nums = pivcore.pot.hwLabel.hwNumbers(recs);
    if isempty(nums)
        h.activeHW = NaN; guidata(fig, h);
        set(h.txtHW,'String','HW: — (belum ada label HW)');
        return;
    end
    cur = find(nums==h.activeHW, 1);
    if isempty(cur), cur = 1; else, cur = mod(cur-1+step, numel(nums))+1; end
    h.activeHW = nums(cur);
    rows = pivcore.pot.hwLabel.rowsForHW(recs, h.activeHW);
    h.selCurveRows = rows(:).'; guidata(fig, h);
    % sinkronkan seleksi tabel (jika didukung) + sorot
    try, set(h.tblCurves,'Selection',[rows(:) ones(numel(rows),1)]); catch, end
    i_highlightSel(fig);
    set(h.txtHW,'String',sprintf('HW: HW-%d  (%d/%d)', h.activeHW, cur, numel(nums)), ...
        'ForegroundColor',[0.15 0.30 0.55]);
end

function rows = i_selCurveRows(h)
    rows = [];
    if isfield(h,'selCurveRows'), rows = h.selCurveRows(:).'; end
    n = 0; if isfield(h.proj,'recs'), n = numel(h.proj.recs); end
    rows = rows(rows>=1 & rows<=n);
end

function tf = i_hasRecs(fig)
    h = guidata(fig);
    tf = isfield(h.proj,'recs') && ~isempty(h.proj.recs);
    if ~tf, set(h.txtEdit,'String','Proyek lama tanpa data kurva mentah — tak bisa diedit. Simpan ulang dari GRAIN4.', ...
            'ForegroundColor',[0.6 0.4 0]); end
end

function i_afterEdit(fig)
%I_AFTEREDIT  Hitung ulang turunan dari recs + segarkan tabel + render.
    h = guidata(fig);
    h.proj = pivcore.io.axpotProject.deriveFromRecs(h.proj);
    guidata(fig, h);
    h = i_fillCurveTable(h);
    h = i_refreshHWLabel(h); guidata(fig, h);
    set(h.txtStatus,'String',sprintf('proyek: %d kurva · %d HW · nF=%d', ...
        numel(h.proj.curves), numel(h.proj.hw), h.proj.nFrames),'ForegroundColor',[0.2 0.4 0.2]);
    i_apply(fig);
end

function i_onTrim(fig)
    if ~i_hasRecs(fig), return; end
    h = guidata(fig); rows = i_selCurveRows(h);
    if isempty(rows), set(h.txtEdit,'String','Pilih baris kurva dulu, lalu Trim.','ForegroundColor',[0.6 0.4 0]); return; end
    env = h.proj.indenter;
    if isempty(env), set(h.txtEdit,'String','Max indenter belum ada.','ForegroundColor',[0.6 0.4 0]); return; end
    recs = pivcore.pot.records.normalize(h.proj.recs); nF = h.proj.nFrames;
    opt = struct('minHeightFrac',0.70, 'tolFrac',0.01, 'minHold',1); nHit = 0;
    for r = rows
        [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
        [~, dieF] = pivcore.pot.hw0Clean.cutAtIndenter(yv, env, opt);
        recs(r).cutManual = true; recs(r).cutFrame = dieF;
        if isfinite(dieF), nHit = nHit + 1; end
    end
    h.proj.recs = recs; guidata(fig, h);
    set(h.txtEdit,'String',sprintf('Trim ke max indenter: %d kurva (%d menyentuh).', numel(rows), nHit), ...
        'ForegroundColor',[0.2 0.4 0.2]);
    i_afterEdit(fig);
end

function i_onUntrim(fig)
    if ~i_hasRecs(fig), return; end
    h = guidata(fig); rows = i_selCurveRows(h); scope = 'terpilih';
    if isempty(rows), rows = 1:numel(h.proj.recs); scope = 'semua'; end
    recs = pivcore.pot.records.normalize(h.proj.recs);
    for r = rows, recs(r).cutManual = false; recs(r).cutFrame = NaN; recs(r).dataCut = []; end
    h.proj.recs = recs; guidata(fig, h);
    set(h.txtEdit,'String',sprintf('Batal trim (%s): kurva utuh.', scope),'ForegroundColor',[0.2 0.4 0.2]);
    i_afterEdit(fig);
end

function i_onExclude(fig)
    if ~i_hasRecs(fig), return; end
    h = guidata(fig); rows = i_selCurveRows(h);
    if isempty(rows), set(h.txtEdit,'String','Pilih baris kurva dulu, lalu Buang.','ForegroundColor',[0.6 0.4 0]); return; end
    recs = pivcore.pot.records.normalize(h.proj.recs);
    for r = rows, recs(r).excluded = true; end
    h.proj.recs = recs; h.selCurveRows = []; guidata(fig, h);
    set(h.txtEdit,'String',sprintf('🗑 Buang %d kurva (non-destruktif).', numel(rows)),'ForegroundColor',[0.5 0 0]);
    i_afterEdit(fig);
end

function i_onRestore(fig)
    if ~i_hasRecs(fig), return; end
    h = guidata(fig); rows = i_selCurveRows(h); scope = 'terpilih';
    if isempty(rows), rows = 1:numel(h.proj.recs); scope = 'semua'; end
    recs = pivcore.pot.records.normalize(h.proj.recs);
    for r = rows, recs(r).excluded = false; end
    h.proj.recs = recs; guidata(fig, h);
    set(h.txtEdit,'String',sprintf('Pulih kurva (%s).', scope),'ForegroundColor',[0.2 0.4 0.2]);
    i_afterEdit(fig);
end

function i_onAssign(fig)
    if ~i_hasRecs(fig), return; end
    h = guidata(fig); rows = i_selCurveRows(h);
    if isempty(rows), set(h.txtEdit,'String','Pilih baris kurva dulu, lalu Assign.','ForegroundColor',[0.6 0.4 0]); return; end
    tyList = get(h.popType,'String'); ty = tyList{get(h.popType,'Value')};
    num = i_num(get(h.edNum,'String'), 1); num = round(num);
    recs = pivcore.pot.records.normalize(h.proj.recs);
    for r = rows, recs = pivcore.pot.hwLabel.assign(recs, r, ty, num); end
    h.proj.recs = recs; guidata(fig, h);
    lbl = pivcore.pot.labels.makeLabel(ty, num);
    set(h.txtEdit,'String',sprintf('Assign “%s” → %d kurva.', lbl, numel(rows)),'ForegroundColor',[0.2 0.3 0.6]);
    i_afterEdit(fig);
end

function i_onUnassign(fig)
    if ~i_hasRecs(fig), return; end
    h = guidata(fig); rows = i_selCurveRows(h);
    if isempty(rows), set(h.txtEdit,'String','Pilih baris kurva dulu, lalu Lepas.','ForegroundColor',[0.6 0.4 0]); return; end
    recs = pivcore.pot.records.normalize(h.proj.recs);
    for r = rows, recs = pivcore.pot.hwLabel.unassign(recs, r); end
    h.proj.recs = recs; guidata(fig, h);
    set(h.txtEdit,'String',sprintf('Lepas label → %d kurva.', numel(rows)),'ForegroundColor',[0.2 0.4 0.2]);
    i_afterEdit(fig);
end

function i_onTypeChange(fig)
    h = guidata(fig);
    tyList = get(h.popType,'String'); ty = tyList{get(h.popType,'Value')};
    on = any(strcmp(ty,{'HW','F'}));   % F0/FFW tak butuh nomor
    set(h.edNum,'Enable', i_ternary(on,'on','off'));
end

function v = i_ternary(c,a,b), if c, v=a; else, v=b; end, end


% =====================================================================
% Helper UI/util kecil
% =====================================================================
function y2 = i_sec(P, y, ttl)
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[0.02 y 0.96 0.026], ...
        'String',ttl,'HorizontalAlignment','left','FontWeight','bold','FontSize',9, ...
        'BackgroundColor',[1 1 1],'ForegroundColor',[0.2 0.2 0.35]);
    y2 = y - 0.034;
end

function [e, bUp, bDn] = i_spin(P, x, y, lbl, val, fig)
%I_SPIN  Label + edit numerik + tombol panah ↑/↓ (±1 cm). Mengembalikan handle
%   edit + dua tombol. Dipakai utk Lebar/Tinggi kanvas.
    lw = 0.16; ew = 0.16;   % label + edit ramping (sisakan ruang tombol)
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[x y lw 0.030], ...
        'String',lbl,'HorizontalAlignment','left','BackgroundColor',[1 1 1],'FontSize',8);
    s = val; if isnumeric(val), s = num2str(val); end
    e = uicontrol('Parent',P,'Style','edit','Units','normalized','Position',[x+lw y ew 0.032], ...
        'String',s,'BackgroundColor',[1 1 1],'FontSize',8,'HorizontalAlignment','center', ...
        'Callback',@(s2,ev) i_apply(fig));
    xb = x+lw+ew+0.005;
    bUp = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[xb y+0.016 0.06 0.018],'String','▲','FontSize',6, ...
        'TooltipString','+1 cm','Callback',@(s2,ev) i_onSpin(fig, e, +1));
    bDn = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[xb y 0.06 0.018],'String','▼','FontSize',6, ...
        'TooltipString','-1 cm','Callback',@(s2,ev) i_onSpin(fig, e, -1));
end

function i_onSpin(fig, ed, step)
    v = i_num(get(ed,'String'), 0) + step;
    if v < 1, v = 1; end   % minimal 1 cm
    set(ed,'String', num2str(v));
    i_apply(fig);
end

function e = i_lbledit(P, x, y, lbl, val, lw, ew)
    if nargin<6, lw = 0.18; end
    if nargin<7, ew = 0.26; end
    uicontrol('Parent',P,'Style','text','Units','normalized','Position',[x y lw 0.030], ...
        'String',lbl,'HorizontalAlignment','left','BackgroundColor',[1 1 1],'FontSize',8);
    s = val; if isnumeric(val), s = num2str(val); end
    e = uicontrol('Parent',P,'Style','edit','Units','normalized','Position',[x+lw y ew 0.032], ...
        'String',s,'BackgroundColor',[1 1 1],'FontSize',8,'HorizontalAlignment','left');
end

function e = i_edit(P, x, y, val, w)
    if nargin<5, w = 0.26; end
    s = ''; if isfinite(val), s = num2str(val); end
    e = uicontrol('Parent',P,'Style','edit','Units','normalized','Position',[x y w 0.030], ...
        'String',s,'BackgroundColor',[1 1 1],'FontSize',8,'HorizontalAlignment','left', ...
        'TooltipString','kosong = abaikan');
end

function c = i_chk(P, x, y, lbl, val, fig)
    c = uicontrol('Parent',P,'Style','checkbox','Units','normalized','Position',[x y 0.46 0.030], ...
        'String',lbl,'Value',double(logical(val)),'BackgroundColor',[1 1 1],'FontSize',8, ...
        'Callback',@(s,e) i_apply(fig));
end

function v = i_g(s, f, dflt)   % numeric default dari display tersimpan
    v = dflt; if isstruct(s) && isfield(s,f) && ~isempty(s.(f)) && isnumeric(s.(f)) && isscalar(s.(f)), v = s.(f); end
    if islogical(dflt) || (isnumeric(dflt) && ismember(dflt,[0 1]) && ~isnan(dflt))
        if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = double(s.(f)); end
    end
end

function v = i_gs(s, f, dflt)  % string/char default
    v = dflt;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        x = s.(f);
        if ischar(x) || isstring(x), v = char(x);
        elseif isnumeric(x), v = i_list2str(x);   % frameLines tersimpan numerik
        end
    end
end

function v = i_num(s, dflt)
    v = dflt; x = str2double(strtrim(char(s))); if isscalar(x) && ~isnan(x), v = x; end
end

function L = i_parseList(s)
    s = char(s); L = [];
    if isempty(strtrim(s)), return; end
    t = regexp(s, '[,\s;]+', 'split');
    for k=1:numel(t), v=str2double(t{k}); if isfinite(v), L(end+1)=v; end, end %#ok<AGROW>
end

function s = i_list2str(L)
    if isempty(L), s=''; return; end
    s = strjoin(arrayfun(@(x) num2str(round(x)), L(:).', 'UniformOutput',false), ',');
end

function s = i_safeName(raw, dflt)
    s = ''; if ischar(raw), s = strtrim(raw); elseif iscell(raw)&&~isempty(raw), s = strtrim(char(raw{1})); end
    s = regexprep(s, '[^A-Za-z0-9_\-]', '_'); s = regexprep(s, '_+', '_'); s = regexprep(s, '^_|_$', '');
    if isempty(s), s = dflt; end
end

function v = i_orEmptyNum(x)
    if isscalar(x) && isfinite(x), v = x; else, v = []; end
end

function b = i_bn(p), [~, n, e] = fileparts(p); b = [n e]; end

function i_safeClose(f), try, if ishghandle(f), delete(f); end, catch, end, end

function i_minimizeForDialog(fig)
%I_MINIMIZEFORDIALOG  Kecilkan jendela utama sebelum dialog berkas (aturan global).
%   Lewati saat tes senyap. Pakai helper bersama bila ada, else fallback langsung.
    if strcmp(get(groot,'DefaultFigureVisible'),'off'), return; end
    try
        if ~isempty(which('pivui.minimizeForDialog')), pivui.minimizeForDialog(fig);
        else, set(fig,'WindowState','minimized'); drawnow;
        end
    catch
    end
end

function i_restoreAfterDialog(fig)
%I_RESTOREAFTERDIALOG  Pulihkan jendela utama setelah dialog ditutup.
    if strcmp(get(groot,'DefaultFigureVisible'),'off'), return; end
    try
        if ~isempty(which('pivui.restoreAfterDialog')), pivui.restoreAfterDialog(fig);
        else, set(fig,'WindowState','maximized'); drawnow;
        end
    catch
    end
end
