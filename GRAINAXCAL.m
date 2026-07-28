function GRAINAXCAL(rootDir)
%GRAINAXCAL  Kalibrasi SUMBU cm untuk gambar AX main (X = Cummulative Shortening,
%   Y = Height) + segitiga indenter — modul STANDALONE (1 file GUI), WYSIWYG.
%
%   GRAINAXCAL              % dialog pilih folder .mat PIV (output Step 2)
%   GRAINAXCAL(rootDir)     % langsung ke folder ROOT
%
%   TUJUAN: menetapkan pemetaan PIXEL -> cm per-eksperimen agar saat GRAIN4
%   commit/ekspor, gambar AX main tampil dengan tick cm + label + segitiga
%   merah posisi indenter (bergeser ikut frame) — bukan lagi tick pixel.
%
%   ALUR: klik/ketik 2 pasang (pixel, cm) untuk sumbu-X dan sumbu-Y (kalibrasi
%   linear 2-titik; robust walau PIVlab calxy=1). LIHAT hasil di KANVAS
%   (renderer BERSAMA pivcore.export.frameCatalog.drawScalarPanel -> preview =
%   ekspor). Save -> sidecar `<base>_axcal.json` (engine pivcore.io.grainAxCal).
%
%   Segitiga indenter: mode 'shortening' -> posisi cm bingkai-k =
%     (k-1)/(nF-1) * dxCm  (dxCm = |X0_cm-X1_cm| dari experiment_geometry).
%
%   NON-DESTRUKTIF: MAT PIV & sidecar lain tak disentuh. Tema TERANG dipaksa.
%   Lihat memori [[grainexport-catalog]], [[grain-step4-ecosystem]].

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.export.frameCatalog'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, ...
            'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end

    h = struct();
    h.root      = rootDir;
    h.list      = struct('name',{},'file',{},'sizeMB',{},'nFrames',{}, ...
                         'sel',{},'status',{});
    h.busy      = false;

    % --- SESSION state (per-exp) ---
    h.activeRow = 0;
    h.realData  = '';
    h.data      = [];
    h.fullLoaded= false;
    h.imgFrames = 1;
    h.nF        = 1;
    h.frame     = 1;
    h.scalar    = 'velmag';
    h.resolve   = [];
    h.axcal     = [];        % doc pivcore.io.grainAxCal exp aktif
    h.pickAxis  = '';        % 'x'|'y' saat sedang menunggu klik ambil titik
    h.pickSlot  = 0;         % 1|2 titik ke berapa

    % --- default tick/label lintas-sesi (setpref) ---
    h.g = i_defaultGlobal();
    h.g = i_loadGlobalPref(h.g);

    h = i_buildUI(h);
    guidata(h.fig, h);
    i_rescan(h.fig);
end


% =====================================================================
% Default tick/label (ke FILE lintas-sesi via setpref 'GRAINAXCAL')
% =====================================================================
function g = i_defaultGlobal()
    g = struct();
    g.xTickCm  = [0 5 10 15 20 25 30];
    g.yTickCm  = [0 4 8];
    g.xLabel   = 'Cummulative Shortening (cm)';
    g.yLabel   = 'Height (cm)';
    g.widthCm  = 18;
    g.heightCm = 10;
end

function g = i_loadGlobalPref(g)
    try
        if ispref('GRAINAXCAL','global')
            p = getpref('GRAINAXCAL','global');
            f = fieldnames(g);
            for i = 1:numel(f)
                if isfield(p, f{i}) && ~isempty(p.(f{i})), g.(f{i}) = p.(f{i}); end
            end
        end
    catch
    end
end

function i_onSaveGlobal(fig)
    h = guidata(fig);
    i_readTicksToCal(fig); h = guidata(fig);
    if isstruct(h.axcal)
        h.g.xTickCm = h.axcal.x.tickCm; h.g.yTickCm = h.axcal.y.tickCm;
        h.g.xLabel  = h.axcal.x.label;  h.g.yLabel  = h.axcal.y.label;
        guidata(fig, h);
    end
    try
        setpref('GRAINAXCAL','global', h.g);
        i_status(fig, '⭐ Tick & label disimpan sebagai DEFAULT (lintas-sesi).');
    catch ME
        i_status(fig, sprintf('Gagal simpan default: %s', ME.message));
    end
end


% =====================================================================
% UI (tema TERANG) — 3 kolom: KIRI exp+slider, TENGAH kanvas, KANAN kalibrasi
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    vis = 'on'; if pivui.quiet(), vis = 'off'; end
    h.fig = figure('Name',pivui.titleWithVersion('GRAINAXCAL — Kalibrasi sumbu cm AX main'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[40 40 1400 820], ...
        'MenuBar','none','ToolBar','none','Visible',vis, ...
        'CloseRequestFcn',@(s,e) i_onCloseBtn(s));
    pivui.forceLightTheme(h.fig);
    fig = h.fig;

    % --- Panel KIRI: sumber + tabel exp ------------------------------
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.005 0.01 0.205 0.985],'Title','Eksperimen (.mat PIV)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.txtRoot = uicontrol('Parent',pnlL,'Style','text', ...
        'Units','normalized','Position',[0.03 0.955 0.94 0.035], ...
        'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'String',h.root);
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.915 0.46 0.035],'String','📂 Ganti folder', ...
        'Callback',@(s,e) i_onPickFolder(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.915 0.46 0.035],'String','↻ Pindai ulang', ...
        'Callback',@(s,e) i_rescan(fig));
    h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.02 0.94 0.885], ...
        'ColumnName',{'Eksperimen','Frame','Status'}, ...
        'ColumnWidth',{140 46 60}, 'ColumnEditable',[false false false], ...
        'RowName',[], 'CellSelectionCallback',@(s,e) i_onSelectRow(fig,e));

    % --- Panel TENGAH: kanvas WYSIWYG --------------------------------
    h.pnlCanvas = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.215 0.10 0.545 0.895],'Title','Kanvas (what-you-see = ekspor)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.ax = axes('Parent',h.pnlCanvas,'Units','normalized','Position',[0.08 0.10 0.88 0.85]);

    % Strip bawah kanvas: toggle skalar + slider frame
    h.btnScalar = uicontrol('Parent',fig,'Style','togglebutton','Units','normalized', ...
        'Position',[0.215 0.055 0.09 0.035],'String','Vel mag / Shear', ...
        'Callback',@(s,e) i_onToggleScalar(fig));
    h.sldFrame = uicontrol('Parent',fig,'Style','slider','Units','normalized', ...
        'Position',[0.315 0.058 0.40 0.028],'Min',1,'Max',2,'Value',1, ...
        'Callback',@(s,e) i_onFrameSlider(fig));
    h.txtFrame = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.72 0.052 0.04 0.035],'String','1/1', ...
        'BackgroundColor',WHITE,'HorizontalAlignment','center');
    h.txtStatus = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.215 0.012 0.545 0.035],'String','Pilih eksperimen di kiri.', ...
        'BackgroundColor',WHITE,'HorizontalAlignment','left','FontSize',8);

    % --- Panel KANAN: kalibrasi --------------------------------------
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.765 0.01 0.23 0.985],'Title','Kalibrasi sumbu cm', ...
        'FontWeight','bold','BackgroundColor',WHITE);

    % Sumbu-X
    y = 0.955;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 y 0.94 0.028],'String','SUMBU-X (Cummulative Shortening)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'HorizontalAlignment','left');
    [h.edX1Px,h.edX1Cm,h.btnX1] = i_calRow(pnlR, y-0.045, 'Titik-1', ...
        @(s,e) i_onPick(fig,'x',1));
    [h.edX2Px,h.edX2Cm,h.btnX2] = i_calRow(pnlR, y-0.085, 'Titik-2', ...
        @(s,e) i_onPick(fig,'x',2));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 y-0.120 0.30 0.026],'String','Tick cm:', ...
        'BackgroundColor',WHITE,'HorizontalAlignment','left');
    h.edXTick = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.34 y-0.122 0.63 0.030], ...
        'String',num2str(h.g.xTickCm),'HorizontalAlignment','left', ...
        'Callback',@(s,e) i_onEditTick(fig));
    h.edXLabel = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.03 y-0.158 0.94 0.030], ...
        'String',h.g.xLabel,'HorizontalAlignment','left', ...
        'Callback',@(s,e) i_onEditTick(fig));

    % Sumbu-Y
    y = 0.755;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 y 0.94 0.028],'String','SUMBU-Y (Height)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'HorizontalAlignment','left');
    [h.edY1Px,h.edY1Cm,h.btnY1] = i_calRow(pnlR, y-0.045, 'Titik-1', ...
        @(s,e) i_onPick(fig,'y',1));
    [h.edY2Px,h.edY2Cm,h.btnY2] = i_calRow(pnlR, y-0.085, 'Titik-2', ...
        @(s,e) i_onPick(fig,'y',2));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 y-0.120 0.30 0.026],'String','Tick cm:', ...
        'BackgroundColor',WHITE,'HorizontalAlignment','left');
    h.edYTick = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.34 y-0.122 0.63 0.030], ...
        'String',num2str(h.g.yTickCm),'HorizontalAlignment','left', ...
        'Callback',@(s,e) i_onEditTick(fig));
    h.edYLabel = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.03 y-0.158 0.94 0.030], ...
        'String',h.g.yLabel,'HorizontalAlignment','left', ...
        'Callback',@(s,e) i_onEditTick(fig));

    % Segitiga indenter
    y = 0.555;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 y 0.94 0.028],'String','SEGITIGA INDENTER (sumbu-X bawah)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'HorizontalAlignment','left');
    h.chkTri = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.03 y-0.036 0.94 0.028],'String','Tampilkan segitiga (ikut frame)', ...
        'Value',1,'BackgroundColor',WHITE,'Callback',@(s,e) i_apply(fig));
    h.txtTri = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 y-0.090 0.94 0.048], ...
        'String','dxCm (pemendekan total): —','BackgroundColor',WHITE, ...
        'HorizontalAlignment','left','FontSize',8);

    % Aktifkan kalibrasi + tombol simpan
    y = 0.395;
    h.chkEnabled = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.03 y 0.94 0.030],'String','AKTIFKAN sumbu cm (dipakai GRAIN4 ekspor)', ...
        'Value',1,'FontWeight','bold','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_apply(fig));

    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 y-0.070 0.94 0.045],'String','💾 Simpan (_axcal.json)', ...
        'FontWeight','bold','BackgroundColor',[0.80 0.95 0.80], ...
        'Callback',@(s,e) i_onSave(fig,false));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 y-0.120 0.46 0.042],'String','💾✖ Simpan & Tutup', ...
        'BackgroundColor',[0.98 0.85 0.60],'Callback',@(s,e) i_onSave(fig,true));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 y-0.120 0.46 0.042],'String','✖ Tutup', ...
        'BackgroundColor',[0.95 0.80 0.80],'Callback',@(s,e) i_onCloseBtn(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 y-0.170 0.94 0.040],'String','⭐ Jadikan tick/label default', ...
        'Callback',@(s,e) i_onSaveGlobal(fig));

    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.03 0.01 0.94 0.14], 'BackgroundColor',WHITE, ...
        'HorizontalAlignment','left','FontSize',8, ...
        'String',['Cara: klik "📍" lalu klik titik pada kanvas (atau ketik pixel ' ...
                  'manual), isi nilai cm-nya. Butuh 2 titik per sumbu. Segitiga ' ...
                  'butuh geometri X0/X1 di .mat (dxCm).']);
end


function [edPx, edCm, btn] = i_calRow(parent, y, lbl, cb)
%I_CALROW  Satu baris kalibrasi: [📍] [label] px:[   ] cm:[   ].
    WHITE = [1 1 1];
    btn = uicontrol('Parent',parent,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 y 0.10 0.030],'String','📍','Callback',cb);
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',[0.14 y-0.002 0.22 0.028],'String',lbl, ...
        'BackgroundColor',WHITE,'HorizontalAlignment','left');
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',[0.36 y-0.002 0.10 0.028],'String','px', ...
        'BackgroundColor',WHITE,'HorizontalAlignment','right');
    edPx = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[0.46 y 0.20 0.030],'String','','HorizontalAlignment','left');
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',[0.66 y-0.002 0.10 0.028],'String','cm', ...
        'BackgroundColor',WHITE,'HorizontalAlignment','right');
    edCm = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[0.76 y 0.21 0.030],'String','','HorizontalAlignment','left');
end


% =====================================================================
% Kalibrasi <-> kontrol
% =====================================================================
function cal = i_calFromControls(fig)
%I_CALFROMCONTROLS  Rakit doc grainAxCal dari kontrol GUI (untuk render/simpan).
    h = guidata(fig);
    if isstruct(h.axcal), cal = h.axcal; else, cal = pivcore.io.grainAxCal.emptyDoc(h.realData); end
    cal.enabled = logical(get(h.chkEnabled,'Value'));
    cal.x.p1Px = i_num(get(h.edX1Px,'String'));  cal.x.p1Cm = i_num(get(h.edX1Cm,'String'));
    cal.x.p2Px = i_num(get(h.edX2Px,'String'));  cal.x.p2Cm = i_num(get(h.edX2Cm,'String'));
    cal.y.p1Px = i_num(get(h.edY1Px,'String'));  cal.y.p1Cm = i_num(get(h.edY1Cm,'String'));
    cal.y.p2Px = i_num(get(h.edY2Px,'String'));  cal.y.p2Cm = i_num(get(h.edY2Cm,'String'));
    cal.x.tickCm = i_numvec(get(h.edXTick,'String'));
    cal.y.tickCm = i_numvec(get(h.edYTick,'String'));
    cal.x.label  = strtrim(get(h.edXLabel,'String'));
    cal.y.label  = strtrim(get(h.edYLabel,'String'));
    cal.indenter.show = logical(get(h.chkTri,'Value'));
end

function i_calToControls(fig, cal)
    h = guidata(fig);
    set(h.chkEnabled,'Value', logical(cal.enabled));
    set(h.edX1Px,'String', i_str(cal.x.p1Px));  set(h.edX1Cm,'String', i_str(cal.x.p1Cm));
    set(h.edX2Px,'String', i_str(cal.x.p2Px));  set(h.edX2Cm,'String', i_str(cal.x.p2Cm));
    set(h.edY1Px,'String', i_str(cal.y.p1Px));  set(h.edY1Cm,'String', i_str(cal.y.p1Cm));
    set(h.edY2Px,'String', i_str(cal.y.p2Px));  set(h.edY2Cm,'String', i_str(cal.y.p2Cm));
    if ~isempty(cal.x.tickCm), set(h.edXTick,'String', num2str(cal.x.tickCm)); end
    if ~isempty(cal.y.tickCm), set(h.edYTick,'String', num2str(cal.y.tickCm)); end
    if ~isempty(cal.x.label),  set(h.edXLabel,'String', cal.x.label); end
    if ~isempty(cal.y.label),  set(h.edYLabel,'String', cal.y.label); end
    set(h.chkTri,'Value', logical(cal.indenter.show));
end

function i_readTicksToCal(fig)
    h = guidata(fig);
    h.axcal = i_calFromControls(fig);
    guidata(fig, h);
end

function i_onEditTick(fig)
    i_readTicksToCal(fig); i_apply(fig);
end


% =====================================================================
% Ambil titik dari kanvas (klik) atau manual
% =====================================================================
function i_onPick(fig, axis, slot)
    h = guidata(fig);
    if isempty(h.data)
        i_status(fig,'Muat eksperimen dulu sebelum ambil titik.'); return;
    end
    if pivui.quiet(), return; end   % senyap saat tes (tak ginput)
    i_status(fig, sprintf('Klik posisi %s pada kanvas untuk titik-%d…', upper(axis), slot));
    try
        pt = drawpoint(h.ax);
        p = pt.Position; delete(pt);
    catch
        i_status(fig,'Batal ambil titik.'); return;
    end
    if axis=='x', val = p(1); else, val = p(2); end
    edPx = i_pxEdit(h, axis, slot);
    set(edPx,'String', sprintf('%.1f', val));
    i_status(fig, sprintf('Titik-%d %s pixel=%.1f. Isi nilai cm-nya.', slot, upper(axis), val));
    i_readTicksToCal(fig); i_apply(fig);
end

function ed = i_pxEdit(h, axis, slot)
    if axis=='x'
        if slot==1, ed = h.edX1Px; else, ed = h.edX2Px; end
    else
        if slot==1, ed = h.edY1Px; else, ed = h.edY2Px; end
    end
end


% =====================================================================
% KANVAS WYSIWYG (renderer BERSAMA dgn GRAIN4 ekspor)
% =====================================================================
function i_apply(fig)
    h = guidata(fig);
    if ~ishghandle(h.ax), return; end
    if isempty(h.data) || isempty(h.resolve)
        cla(h.ax,'reset'); axis(h.ax,'off');
        text(h.ax,0.5,0.5,'Klik baris eksperimen di kiri untuk melihat gambar AX main', ...
            'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
        return;
    end
    i_readTicksToCal(fig); h = guidata(fig);
    k = max(1, min(round(h.frame), max(1,h.imgFrames)));
    if k > 1 && ~h.fullLoaded, i_ensureFull(fig); h = guidata(fig); end
    k = max(1, min(round(h.frame), max(1,h.imgFrames)));

    % Ukuran kanvas fisik cm -> OuterPosition (WYSIWYG pola GRAINEXPORT).
    pp = getpixelposition(h.pnlCanvas);
    cm2px = get(0,'ScreenPixelsPerInch')/2.54;
    wpx = h.g.widthCm*cm2px; hpx = h.g.heightCm*cm2px;
    set(h.ax,'Units','pixels');
    mx = max((pp(3)-wpx)/2, 6); my = max((pp(4)-hpx)/2, 6);
    set(h.ax,'OuterPosition',[mx my min(wpx,pp(3)-10) min(hpx,pp(4)-10)]);
    set(h.ax,'Units','normalized');
    cla(h.ax,'reset');

    up = struct('scalars',{{'velmag','shear'}});   % render skalar tampil
    spec = pivcore.export.frameCatalog.specFromResolve(h.resolve, up);
    cfg  = pivcore.export.frameCatalog.renderCfg(spec);
    decOpts = pivcore.export.frameCatalog.decOptsFromSpec(spec, struct());
    decOpts.axCal = h.axcal;    % <-- kalibrasi cm live -> preview = ekspor
    [~, base] = fileparts(h.realData);
    pivcore.export.frameCatalog.drawScalarPanel(h.ax, h.data, k, h.scalar, cfg, ...
        h.resolve, base, decOpts);
end


% =====================================================================
% LOAD EKSPERIMEN
% =====================================================================
function i_onSelectRow(fig, e)
    try
        if isempty(e.Indices), return; end
        r = e.Indices(1);
    catch
        return;
    end
    h = guidata(fig);
    if r>=1 && r<=numel(h.list), i_loadExperiment(fig, r); end
end

function i_loadExperiment(fig, row)
    h = guidata(fig);
    if row < 1 || row > numel(h.list), return; end
    df = h.list(row).file; [~, base] = fileparts(df);
    h.activeRow = row; h.realData = df;
    h.data = []; h.fullLoaded = false; h.imgFrames = 1; h.nF = 1; h.frame = 1;
    h.resolve = []; h.axcal = []; guidata(fig, h);

    i_status(fig, sprintf('Memuat %s…', base)); drawnow;
    try
        data1 = pivcore.io.step1Session.loadFrame1(df);
        R = pivcore.export.frameCatalog.resolveRender(df);
    catch ME
        i_status(fig, sprintf('GAGAL memuat %s: %s', base, ME.message));
        return;
    end
    h = guidata(fig);
    h.data = data1;
    h.imgFrames = pivcore.data.frameCount(data1);
    h.resolve = R;
    h.nF = max([1, h.imgFrames, R.nFrames]);
    h.frame = 1;

    % Muat sidecar _axcal bila ada; else default tick/label + emptyDoc.
    cal = pivcore.io.grainAxCal.read(df);
    if ~cal.enabled   % belum pernah dikalibrasi -> pakai tick/label default
        cal.x.tickCm = h.g.xTickCm; cal.y.tickCm = h.g.yTickCm;
        cal.x.label  = h.g.xLabel;  cal.y.label  = h.g.yLabel;
    end
    h.axcal = cal;
    guidata(fig, h);

    i_calToControls(fig, cal);
    % Info dxCm (untuk segitiga).
    if isfinite(R.dxCm)
        set(h.txtTri,'String', sprintf('dxCm (pemendekan total) = %.4g cm — segitiga ikut frame.', R.dxCm));
    else
        set(h.txtTri,'String', 'dxCm TAK ADA di .mat (X0/X1 geometri) — segitiga di-skip.');
    end
    i_syncFrameSlider(fig);
    i_apply(fig);
    i_status(fig, sprintf('%s dimuat: %d bingkai, PSG=%s, strain=%.2f%%.', ...
        base, R.nFrames, R.psgSource, R.strainTotalPct));
end

function ok = i_ensureFull(fig)
    h = guidata(fig); ok = false;
    if h.fullLoaded, ok = true; return; end
    if isempty(h.realData), return; end
    try
        dataAll = pivcore.io.step1Session.loadAllFrames(h.realData);
    catch ME
        i_status(fig, sprintf('Gagal memuat semua bingkai: %s', ME.message)); return;
    end
    h = guidata(fig);
    h.data = dataAll; h.fullLoaded = true;
    h.imgFrames = pivcore.data.frameCount(dataAll);
    guidata(fig, h); i_syncFrameSlider(fig); ok = true;
end


% =====================================================================
% Frame / skalar
% =====================================================================
function i_onFrameSlider(fig)
    h = guidata(fig);
    k = max(1, round(get(h.sldFrame,'Value')));
    h.frame = k; guidata(fig, h);
    if k > 1 && ~h.fullLoaded, i_ensureFull(fig); h = guidata(fig); end
    set(h.txtFrame,'String', sprintf('%d/%d', k, max(1,h.imgFrames)));
    i_apply(fig);
end

function i_syncFrameSlider(fig)
    h = guidata(fig);
    nF = max(1, h.imgFrames);
    set(h.sldFrame,'Min',1,'Max',max(2,nF),'Value',min(max(1,h.frame),nF));
    if nF > 1
        set(h.sldFrame,'SliderStep',[1/(nF-1) max(2/(nF-1),0.1)]);
    end
    set(h.txtFrame,'String', sprintf('%d/%d', min(max(1,h.frame),nF), nF));
end

function i_onToggleScalar(fig)
    h = guidata(fig);
    if strcmp(h.scalar,'velmag'), h.scalar='shear'; else, h.scalar='velmag'; end
    guidata(fig, h); i_apply(fig);
end


% =====================================================================
% Simpan / tutup
% =====================================================================
function i_onSave(fig, closeAfter)
    h = guidata(fig);
    if isempty(h.realData), i_status(fig,'Belum ada eksperimen aktif.'); return; end
    i_readTicksToCal(fig); h = guidata(fig);
    cal = h.axcal;
    % Peringatan bila diaktifkan tapi kalibrasi belum lengkap.
    if cal.enabled
        okx = pivcore.io.grainAxCal.isValid(cal,'x');
        oky = pivcore.io.grainAxCal.isValid(cal,'y');
        if ~okx || ~oky
            msg = sprintf('Kalibrasi belum lengkap (X:%s Y:%s). Tetap disimpan; sumbu yg belum valid pakai tick pixel.', ...
                i_ok(okx), i_ok(oky));
            i_status(fig, msg);
        end
    end
    try
        pivcore.io.grainAxCal.write(h.realData, cal);
        [~, base] = fileparts(h.realData);
        i_status(fig, sprintf('💾 Tersimpan: %s_axcal.json (enabled=%d).', base, cal.enabled));
    catch ME
        i_status(fig, sprintf('GAGAL simpan: %s', ME.message)); return;
    end
    if closeAfter, i_onCloseBtn(fig); end
end

function i_onCloseBtn(fig)
    try, delete(fig); catch, end
end


% =====================================================================
% Scan folder + tabel
% =====================================================================
function i_rescan(fig)
    h = guidata(fig);
    files = pivanalyzemat.core.scanPivMats(h.root);
    L = struct('name',{},'file',{},'sizeMB',{},'nFrames',{},'sel',{},'status',{});
    for i = 1:numel(files)
        df = files{i}; [~, base] = fileparts(df);
        d = dir(df); mb = 0; if ~isempty(d), mb = d.bytes/1e6; end
        L(end+1) = struct('name',base,'file',df,'sizeMB',mb, ...
            'nFrames',NaN,'sel',false,'status',i_calStatus(df)); %#ok<AGROW>
    end
    h.list = L; guidata(fig, h);
    i_refreshTable(fig);
    if ~isempty(L)
        i_status(fig, sprintf('%d eksperimen ditemukan.', numel(L)));
    else
        i_status(fig, 'Tak ada .mat PIV di folder ini.');
    end
end

function s = i_calStatus(df)
    cal = pivcore.io.grainAxCal.read(df);
    if cal.enabled && pivcore.io.grainAxCal.isValid(cal,'x') && pivcore.io.grainAxCal.isValid(cal,'y')
        s = '✔ cm';
    elseif isfile(pivcore.io.grainAxCal.dataPath(df))
        s = '~ parsial';
    else
        s = 'pixel';
    end
end

function i_refreshTable(fig)
    h = guidata(fig);
    n = numel(h.list); C = cell(n,3);
    for i = 1:n
        fr = h.list(i).nFrames; if isnan(fr), frs='—'; else, frs=num2str(fr); end
        C{i,1} = h.list(i).name; C{i,2} = frs; C{i,3} = h.list(i).status;
    end
    set(h.tbl,'Data',C);
end

function i_onPickFolder(fig)
    h = guidata(fig);
    if ~pivui.quiet()
        try, set(fig,'WindowState','minimized'); catch, end
    end
    d = uigetdir(h.root, 'Pilih folder .mat PIV');
    if ~pivui.quiet()
        try, set(fig,'WindowState','normal'); catch, end
    end
    if isequal(d,0), return; end
    h.root = d; guidata(fig, h);
    set(h.txtRoot,'String', d);
    i_rescan(fig);
end


% =====================================================================
% Util kecil
% =====================================================================
function i_status(fig, msg)
    h = guidata(fig);
    if isfield(h,'txtStatus') && ishghandle(h.txtStatus)
        set(h.txtStatus,'String', msg);
    end
    drawnow limitrate;
end

function v = i_num(s)
    v = str2double(strtrim(char(s)));
end

function v = i_numvec(s)
    v = str2num(char(s)); %#ok<ST2NM>
    if isempty(v), v = []; else, v = double(v(:)).'; end
end

function s = i_str(v)
    if isscalar(v) && isfinite(v), s = sprintf('%.4g', v); else, s = ''; end
end

function s = i_ok(tf)
    if tf, s = 'OK'; else, s = 'belum'; end
end
