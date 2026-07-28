function GRAINSYNC(linkOrTgt)
%GRAINSYNC  Penafsir ikatan strain — menampilkan view PENAMPANG (acuan) & TAMPAK
%   PETA (target) BERSAMAAN, digerakkan SATU slider STRAIN master. Membaca sidecar
%   "georeferensi" `<tgt_base>_link.json` yang dibuat GRAINLINK.
%
%   GRAINSYNC                    % pilih file *_link.json lewat dialog
%   GRAINSYNC(linkJsonPath)      % langsung dari sidecar
%   GRAINSYNC(targetMatPath)     % langsung dari MAT peta (cari sidecar di sampingnya)
%
%   Geser slider strain → tiap view loncat ke frame yang strain-nya sama:
%       frame penampang = pivcore.io.grainLink.frameAtRef(doc, s)
%       frame peta      = pivcore.io.grainLink.frameAtTgt(doc, s)
%   Caption strain kedua view = s (konsisten). Plus tabel sinkronisasi
%   (strain% → frame penampang & peta) + rasio strain/frame.
%
%   Engine murni: pivcore.io.grainLink. Viewer bersama: pivui.linkView. Tema TERANG.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.io.grainLink'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
        addpath(here);
    end

    if nargin < 1 || isempty(linkOrTgt) || ~ischar(linkOrTgt) || ~isfile(linkOrTgt)
        [fn, fp] = uigetfile({'*_link.json','Sidecar ikatan (*_link.json)'; ...
            '*.mat','MAT PIV peta (*.mat)'}, 'Pilih sidecar ikatan GRAINLINK');
        if isequal(fn,0), return; end
        linkOrTgt = fullfile(fp, fn);
    end

    [tgtMat, ok, msg] = i_resolveTargetMat(linkOrTgt);
    if ~ok
        errordlg(msg, 'GRAINSYNC'); return;
    end
    doc = pivcore.io.grainLink.read(tgtMat);

    h = struct();
    h.doc     = doc;
    h.tgtMat  = tgtMat;
    h.refMat  = i_resolveSource(doc.reference, fileparts(tgtMat));
    h.strain  = NaN;
    h = i_buildUI(h);
    guidata(h.fig, h);

    i_loadBoth(h.fig);
end

% =====================================================================
%  UI
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    vis = 'on'; try, if pivui.quiet(), vis = 'off'; end; catch, end %#ok<CTCH>
    h.fig = figure('Name',pivui.titleWithVersion('GRAIN Sync — Penafsir ikatan (strain master)'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[50 50 1400 800], ...
        'MenuBar','none','ToolBar','none','Visible',vis, ...
        'CloseRequestFcn',@(s,e) delete(gcbf));
    try, pivui.forceLightTheme(h.fig); catch, end %#ok<CTCH>
    fig = h.fig;

    % ================= KIRI: kontrol =================
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.006 0.01 0.300 0.985],'Title','Penafsir ikatan', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);

    h.lblFiles = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.93 0.94 0.055],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'String','—');

    % --- strain master ---
    pM = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.78 0.94 0.145],'Title','Strain master (%)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.txtStrain = uicontrol('Parent',pM,'Style','text','Units','normalized', ...
        'Position',[0.03 0.62 0.94 0.34],'HorizontalAlignment','center', ...
        'FontWeight','bold','FontSize',15,'BackgroundColor',WHITE, ...
        'ForegroundColor',[0 0 0],'String','strain —');
    h.sld = uicontrol('Parent',pM,'Style','slider','Units','normalized', ...
        'Position',[0.03 0.30 0.94 0.26],'Min',0,'Max',1,'Value',0, ...
        'Callback',@(s,e) i_onMaster(fig));
    uicontrol('Parent',pM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.03 0.46 0.22],'String','⟸ FSR pertama', ...
        'FontSize',8,'Callback',@(s,e) i_onJumpTie(fig,'FSR pertama'));
    uicontrol('Parent',pM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.03 0.46 0.22],'String','FSR terakhir ⟹', ...
        'FontSize',8,'Callback',@(s,e) i_onJumpTie(fig,'FSR terakhir'));

    % --- rasio ---
    h.txtRatio = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.70 0.94 0.07],'HorizontalAlignment','left','FontSize',9, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'String','rasio —');

    % --- tabel sinkronisasi ---
    uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.665 0.60 0.025],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontWeight','bold','String','Tabel sinkronisasi');
    uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.40 0.665 0.20 0.025],'HorizontalAlignment','right', ...
        'BackgroundColor',WHITE,'FontSize',8,'String','langkah%');
    h.edStep = uicontrol('Parent',pnlL,'Style','edit','Units','normalized', ...
        'Position',[0.61 0.665 0.14 0.028],'String','0,5', ...
        'BackgroundColor',WHITE,'Callback',@(s,e) i_refreshTable(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.76 0.665 0.21 0.030],'String','↻','TooltipString','Segarkan tabel', ...
        'Callback',@(s,e) i_refreshTable(fig));
    h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.18 0.94 0.475], ...
        'ColumnName',{'strain%','f penampang','f peta'}, ...
        'ColumnWidth',{86 96 86}, 'ColumnFormat',repmat({'char'},1,3), ...
        'ColumnEditable',false(1,3),'RowName',[],'FontSize',8,'Multiselect','off', ...
        'CellSelectionCallback',@(s,e) i_onTableRow(fig,e));

    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.10 0.62 0.06],'String','💾 Ekspor tabel CSV', ...
        'BackgroundColor',[0.86 0.94 0.86],'Callback',@(s,e) i_onExportCsv(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.10 0.31 0.06],'String','✕ Tutup', ...
        'BackgroundColor',[0.97 0.86 0.86],'Callback',@(s,e) delete(fig));

    h.status = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.012 0.94 0.08],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','Memuat…');

    % ================= KANAN: dua viewer =================
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.312 0.01 0.682 0.985],'BackgroundColor',WHITE,'BorderType','none');
    h.pnRef = pivui.linkView.build(pnlR, [0.005 0.01 0.492 0.985], 'PENAMPANG (acuan)');
    h.pnTgt = pivui.linkView.build(pnlR, [0.503 0.01 0.492 0.985], 'TAMPAK PETA (target)');
    % Slider per-panel hanya cermin (master yang menggerakkan) → non-aktif.
    set(h.pnRef.slider,'Enable','inactive');
    set(h.pnTgt.slider,'Enable','inactive');
end

% =====================================================================
%  Muat kedua MAT + setel slider strain
% =====================================================================
function i_loadBoth(fig)
    h = guidata(fig);
    okR = ~isempty(h.refMat) && isfile(h.refMat);
    okT = ~isempty(h.tgtMat) && isfile(h.tgtMat);
    set(h.lblFiles,'String', sprintf('penampang: %s\npeta: %s', ...
        i_baseOf(h.refMat), i_baseOf(h.tgtMat)));

    if okR
        try
            h.pnRef = pivui.linkView.loadMat(h.pnRef, h.refMat);
            set(h.pnRef.txtTitle,'String', sprintf('PENAMPANG (acuan) — %s', i_baseOf(h.refMat)));
        catch ME
            set(h.status,'String', sprintf('Gagal muat penampang: %s', ME.message));
        end
    end
    if okT
        try
            h.pnTgt = pivui.linkView.loadMat(h.pnTgt, h.tgtMat);
            set(h.pnTgt.txtTitle,'String', sprintf('TAMPAK PETA (target) — %s', i_baseOf(h.tgtMat)));
        catch ME
            set(h.status,'String', sprintf('Gagal muat peta: %s', ME.message));
        end
    end
    guidata(fig, h);

    % Rentang slider strain dari ujung kedua view.
    sv = pivcore.io.grainLink.defaultStrainVec(h.doc, 0.5);
    if isempty(sv) || numel(sv) < 2
        set(h.sld,'Min',0,'Max',1,'Value',0,'Enable','off');
        set(h.status,'String','Kalibrasi belum lengkap di sidecar. Lengkapi di GRAINLINK.');
    else
        lo = min(sv); hi = max(sv);
        nstep = max(1, round((hi-lo)/0.5));
        set(h.sld,'Min',lo,'Max',hi,'Value',lo, ...
            'SliderStep',[1/nstep, max(1/nstep,0.1)],'Enable','on');
        if h.doc.calibration.valid
            set(h.status,'String','Geser slider strain → kedua view bergerak seirama.');
        else
            set(h.status,'String','⚠ Kalibrasi target invalid — view peta tak ikut bergerak.');
        end
    end
    i_refreshRatio(fig);
    i_refreshTable(fig);
    i_applyStrain(fig, get(h.sld,'Value'));
end

% =====================================================================
%  Strain master → kedua view
% =====================================================================
function i_onMaster(fig)
    h = guidata(fig);
    i_applyStrain(fig, get(h.sld,'Value'));
end

function i_applyStrain(fig, s)
    h = guidata(fig);
    h.strain = s;
    set(h.txtStrain,'String', sprintf('strain %+.3g %%', s));
    if ~isempty(h.refMat) && isfile(h.refMat)
        fR = pivcore.io.grainLink.frameAtRef(h.doc, s);
        if isfinite(fR)
            h.pnRef = pivui.linkView.gotoFrame(h.pnRef, fR, s);
        end
    end
    if ~isempty(h.tgtMat) && isfile(h.tgtMat)
        fT = pivcore.io.grainLink.frameAtTgt(h.doc, s);
        if isfinite(fT)
            h.pnTgt = pivui.linkView.gotoFrame(h.pnTgt, fT, s);
        end
    end
    guidata(fig, h);
end

function i_onJumpTie(fig, name)
    h = guidata(fig);
    s = NaN;
    for k = 1:numel(h.doc.tiePoints)
        t = h.doc.tiePoints{k};
        if isstruct(t) && isfield(t,'name') && strcmp(t.name, name)
            s = pivcore.io.grainLink.strainAtRef(h.doc, t.refFrame); break;
        end
    end
    if ~isfinite(s), set(h.status,'String', sprintf('%s belum ditandai.', name)); return; end
    s = min(max(s, get(h.sld,'Min')), get(h.sld,'Max'));
    set(h.sld,'Value', s);
    i_applyStrain(fig, s);
end

% =====================================================================
%  Tabel sinkronisasi + rasio
% =====================================================================
function i_refreshTable(fig)
    h = guidata(fig);
    step = i_str2num(get(h.edStep,'String'));
    if ~isfinite(step) || step <= 0, step = 0.5; end
    sv = pivcore.io.grainLink.defaultStrainVec(h.doc, step);
    T = pivcore.io.grainLink.syncTable(h.doc, sv);
    C = cell(numel(T),3);
    for i = 1:numel(T)
        C{i,1} = sprintf('%+.4g', T(i).strainPct);
        C{i,2} = i_frStr(T(i).frameRef);
        C{i,3} = i_frStr(T(i).frameTgt);
    end
    set(h.tbl,'Data',C);
    h.syncTable = T; guidata(fig,h);
end

function i_refreshRatio(fig)
    h = guidata(fig);
    cal = h.doc.calibration;
    if isfinite(cal.refStrainPerFrame) && isfinite(cal.slopePctPerFrame)
        rat = cal.slopePctPerFrame / cal.refStrainPerFrame;
        set(h.txtRatio,'String', sprintf('penampang %+.3g · peta %+.3g %%/frame · rasio %.3f', ...
            cal.refStrainPerFrame, cal.slopePctPerFrame, rat));
    else
        set(h.txtRatio,'String','rasio — (kalibrasi belum lengkap)');
    end
end

function i_onTableRow(fig, e)
    if isempty(e.Indices), return; end
    h = guidata(fig);
    if ~isfield(h,'syncTable') || e.Indices(1) > numel(h.syncTable), return; end
    s = h.syncTable(e.Indices(1)).strainPct;
    s = min(max(s, get(h.sld,'Min')), get(h.sld,'Max'));
    set(h.sld,'Value', s);
    i_applyStrain(fig, s);
end

function i_onExportCsv(fig)
    h = guidata(fig);
    step = i_str2num(get(h.edStep,'String'));
    if ~isfinite(step) || step <= 0, step = 0.5; end
    sv = pivcore.io.grainLink.defaultStrainVec(h.doc, step);
    T = pivcore.io.grainLink.syncTable(h.doc, sv);
    if isempty(T), set(h.status,'String','Tabel kosong.'); return; end
    [~, tb] = fileparts(h.tgtMat);
    def = fullfile(fileparts(h.tgtMat), sprintf('%s_sync.csv', tb));
    try, pivui.minimizeForDialog(h.fig); catch, end %#ok<CTCH>
    [fn, fp] = uiputfile('*.csv','Simpan tabel sinkronisasi', def);
    try, pivui.restoreAfterDialog(h.fig); catch, end %#ok<CTCH>
    if isequal(fn,0), return; end
    p = fullfile(fp, fn);
    try
        fid = fopen(p,'w');
        fprintf(fid,'strain_pct,frame_penampang,frame_peta\n');
        for i = 1:numel(T)
            fprintf(fid,'%.6g,%d,%d\n', T(i).strainPct, ...
                i_orNeg1(T(i).frameRef), i_orNeg1(T(i).frameTgt));
        end
        fclose(fid);
        set(h.status,'String', sprintf('CSV tersimpan: %s', i_short(p)));
    catch ME
        set(h.status,'String', sprintf('Gagal tulis CSV: %s', ME.message));
    end
end

% =====================================================================
%  Resolusi berkas sumber
% =====================================================================
function [tgtMat, ok, msg] = i_resolveTargetMat(arg)
    tgtMat = ''; ok = false; msg = '';
    [d, nm, ext] = fileparts(arg);
    if strcmpi(ext,'.json')
        % <tgtbase>_link.json → tgtbase
        base = nm;
        if endsWith(base,'_link'), base = base(1:end-5); end
        cand = fullfile(d, [base '.mat']);
        if isfile(cand), tgtMat = cand; ok = true; return; end
        % fallback: baca path target dari isi sidecar
        try
            raw = jsondecode(fileread(arg));
            if isfield(raw,'target') && isfield(raw.target,'path') && isfile(raw.target.path)
                tgtMat = raw.target.path; ok = true; return;
            end
        catch
        end
        msg = sprintf('MAT peta tak ditemukan untuk sidecar: %s', arg);
    elseif strcmpi(ext,'.mat')
        tgtMat = arg; ok = true;
    else
        msg = 'Pilih *_link.json atau *.mat.';
    end
end

function p = i_resolveSource(src, sidecarDir)
    p = '';
    if isstruct(src)
        if isfield(src,'path') && ischar(src.path) && isfile(src.path)
            p = src.path; return;
        end
        if isfield(src,'basename') && ischar(src.basename)
            cand = fullfile(sidecarDir, [src.basename '.mat']);
            if isfile(cand), p = cand; return; end
        end
    end
end

% =====================================================================
%  Util
% =====================================================================
function s = i_baseOf(f)
    if isempty(f), s = '(?)'; return; end
    [~, s] = fileparts(char(f));
end
function s = i_frStr(v)
    if isempty(v) || ~isnumeric(v) || ~isfinite(v), s = '—'; else, s = sprintf('%d', round(v)); end
end
function v = i_orNeg1(x)
    if isempty(x) || ~isnumeric(x) || ~isfinite(x), v = -1; else, v = round(x); end
end
function v = i_str2num(s)
    s = strtrim(char(s));
    if isempty(s), v = NaN; return; end
    s = strrep(s, ',', '.');
    v = str2double(s);
end
function s = i_short(p)
    p = char(p);
    if numel(p) <= 46, s = p; return; end
    s = ['…' p(end-44:end)];
end
